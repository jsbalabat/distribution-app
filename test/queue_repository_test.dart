import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../lib/services/queue_repository.dart';
import '../lib/models/queued_sales_requisition.dart';
import '../lib/models/offline_sync_contract.dart';

void main() {
  group('QueueRepository - Secure Local Queue Storage', () {
    late QueueRepository repository;
    late MockSecureStorage mockSecureStorage;

    setUpAll(() async {
      // Initialize Hive for testing (in-memory)
      Hive.init('test_hive');
    });

    setUp(() {
      mockSecureStorage = MockSecureStorage();
      repository = QueueRepository(secureStorage: mockSecureStorage);
    });

    tearDown(() async {
      await repository.close();
      // Clean up Hive boxes
      try {
        await Hive.deleteBoxFromDisk('offline_sor_queue');
        await Hive.deleteBoxFromDisk('offline_queue_audit');
      } catch (e) {
        // Ignore errors during cleanup
      }
    });

    test('Repository initializes successfully with encryption key', () async {
      // Arrange: Verify initialization state
      expect(repository.isInitialized, false);

      // Act: Initialize repository
      await repository.initialize();

      // Assert: Repository is initialized and ready
      expect(repository.isInitialized, true);
      expect(repository.queueCount, 0);
    });

    test('Enqueue creates new SOR with draft offline status', () async {
      // Arrange
      await repository.initialize();
      final clientId = 'test-sor-001';
      final tenantId = 'tenant-123';
      final userId = 'user-456';
      final sorData = {'items': [], 'total': 0.0};
      final correlationId = 'corr-789';

      // Act: Enqueue a new SOR
      final enqueuedId = await repository.enqueueSalesRequisition(
        clientGeneratedId: clientId,
        tenantDatabaseId: tenantId,
        userId: userId,
        sorDraftPayload: sorData,
        correlationId: correlationId,
      );

      // Assert: SOR is stored with correct initial state
      expect(enqueuedId, clientId);
      expect(repository.queueCount, 1);

      final queued = repository.getSalesRequisition(clientId);
      expect(queued, isNotNull);
      expect(queued!.status, OfflineSorStatus.draftOffline);
      expect(queued.autoRetryCount, 0);
      expect(queued.manualRetryCount, 0);
      expect(queued.lastError, isNull);
    });

    test('Update status transitions SOR through lifecycle states', () async {
      // Arrange
      await repository.initialize();
      final clientId = 'test-sor-002';
      await _createTestSOR(repository, clientId);

      // Act: Transition from draft to pending sync
      await repository.updateStatus(
        clientId,
        newStatus: OfflineSorStatus.pendingSync,
      );

      // Assert: Status updated
      var sor = repository.getSalesRequisition(clientId);
      expect(sor!.status, OfflineSorStatus.pendingSync);

      // Act: Transition to syncing
      await repository.updateStatus(
        clientId,
        newStatus: OfflineSorStatus.syncing,
      );

      // Assert
      sor = repository.getSalesRequisition(clientId);
      expect(sor!.status, OfflineSorStatus.syncing);
    });

    test('Manual retry is capped at 3 attempts with cooldown', () async {
      // Arrange
      await repository.initialize();
      final clientId = 'test-sor-003';
      await _createTestSOR(repository, clientId);

      // Act & Assert: First retry succeeds
      await repository.incrementManualRetry(clientId);
      var sor = repository.getSalesRequisition(clientId);
      expect(sor!.manualRetryCount, 1);

      // Try immediate second retry (should fail due to cooldown)
      expect(
        () async => await repository.incrementManualRetry(clientId),
        throwsException,
      );

      // Wait past cooldown (simulated by manipulating timestamp)
      final existing = repository.getSalesRequisition(clientId)!;
      existing.lastManualRetryTimestamp = DateTime.now().subtract(
        const Duration(seconds: 31),
      );
      await repository.updateStatus(clientId, newStatus: existing.status);

      // Act: Second retry should succeed
      await repository.incrementManualRetry(clientId);
      sor = repository.getSalesRequisition(clientId);
      expect(sor!.manualRetryCount, 2);

      // Act: Third retry succeeds
      existing.lastManualRetryTimestamp = DateTime.now();
      await repository.updateStatus(clientId, newStatus: existing.status);
      await Future.delayed(const Duration(seconds: 1));
      await repository.incrementManualRetry(clientId);
      sor = repository.getSalesRequisition(clientId);
      expect(sor!.manualRetryCount, 3);

      // Act & Assert: Fourth retry fails (at limit)
      expect(
        () async => await repository.incrementManualRetry(clientId),
        throwsException,
      );
    });

    test('Auto retry count increments and is clamped at 9', () async {
      // Arrange
      await repository.initialize();
      final clientId = 'test-sor-004';
      await _createTestSOR(repository, clientId);

      // Act: Increment auto retry count multiple times
      for (int i = 0; i < 15; i++) {
        await repository.incrementAutoRetry(clientId);
      }

      // Assert: Clamped at 9
      final sor = repository.getSalesRequisition(clientId);
      expect(sor!.autoRetryCount, 9);
    });

    test('Mark as accepted sets 24-hour rollback window', () async {
      // Arrange
      await repository.initialize();
      final clientId = 'test-sor-005';
      await _createTestSOR(repository, clientId);

      // Act: Mark as accepted
      await repository.markSyncAccepted(clientId);

      // Assert: Rollback window is set
      final sor = repository.getSalesRequisition(clientId)!;
      expect(sor.status, OfflineSorStatus.syncedAccepted);
      expect(sor.rollbackAvailableUntil, isNotNull);

      final windowDuration = sor.rollbackAvailableUntil!.difference(
        DateTime.now(),
      );
      expect(windowDuration.inHours, greaterThanOrEqualTo(23));
      expect(windowDuration.inHours, lessThanOrEqualTo(24));

      // Assert: Email status is pending
      expect(sor.emailStatus, OfflineSorStatus.emailPending);
    });

    test('Rollback only available within 24-hour window', () async {
      // Arrange
      await repository.initialize();
      final clientId = 'test-sor-006';
      await _createTestSOR(repository, clientId);
      await repository.markSyncAccepted(clientId);

      // Act: Rollback within window succeeds
      await repository.markRolledBack(clientId, 'User requested rollback');

      // Assert: Status is rolledBack
      var sor = repository.getSalesRequisition(clientId);
      expect(sor!.status, OfflineSorStatus.rolledBack);

      // Arrange: Create another SOR with expired window
      final clientId2 = 'test-sor-007';
      await _createTestSOR(repository, clientId2);
      await repository.markSyncAccepted(clientId2);

      // Manipulate rollback window to be in the past
      final existing = repository.getSalesRequisition(clientId2)!;
      existing.rollbackAvailableUntil = DateTime.now().subtract(
        const Duration(hours: 25),
      );
      await repository.updateStatus(clientId2, newStatus: existing.status);

      // Act & Assert: Rollback outside window fails
      expect(
        () async => await repository.markRolledBack(clientId2, 'Expired'),
        throwsException,
      );
    });

    test('Get pending sync returns only active SORs', () async {
      // Arrange
      await repository.initialize();

      // Create SORs in various states
      await _createTestSOR(repository, 'sor-001');
      await _createTestSOR(repository, 'sor-002');
      await _createTestSOR(repository, 'sor-003');

      // Transition one to accepted (not pending)
      await repository.updateStatus(
        'sor-001',
        newStatus: OfflineSorStatus.syncedAccepted,
      );

      // Transition one to rolled back (not pending)
      await repository.updateStatus(
        'sor-002',
        newStatus: OfflineSorStatus.rolledBack,
      );

      // Act: Get pending sync
      final pending = repository.getPendingSync();

      // Assert: Only draft SOR is pending
      expect(pending.length, 1);
      expect(pending.first.clientGeneratedId, 'sor-003');
    });

    test('Clear expired items removes old completed SORs', () async {
      // Arrange
      await repository.initialize();

      // Create old SOR (more than 1 day old, already accepted)
      final oldClientId = 'old-sor-001';
      final now = DateTime.now();
      final twoAgesAgo = now.subtract(const Duration(days: 2));

      final oldSor = QueuedSalesRequisition(
        clientGeneratedId: oldClientId,
        tenantDatabaseId: 'tenant-1',
        userId: 'user-1',
        sorDraftPayload: {},
        status: OfflineSorStatus.syncedAccepted,
        correlationId: 'corr-1',
        createdTimestamp: twoAgesAgo,
        rollbackAvailableUntil: twoAgesAgo.add(const Duration(hours: 24)),
      );

      // Manually add to queue (simulating old item)
      final box = await Hive.openBox<QueuedSalesRequisition>(
        'offline_sor_queue',
      );
      await box.put(oldClientId, oldSor);
      await box.close();

      // Create recent SOR (should not be deleted)
      await _createTestSOR(repository, 'recent-sor-001');
      await repository.updateStatus(
        'recent-sor-001',
        newStatus: OfflineSorStatus.syncedAccepted,
      );

      // Act: Clear expired items
      final deletedCount = await repository.clearExpiredItems();

      // Assert: Old item deleted, recent item retained
      expect(deletedCount, 1);
      expect(repository.getSalesRequisition(oldClientId), isNull);
      expect(repository.getSalesRequisition('recent-sor-001'), isNotNull);
    });

    test('Audit log captures all major operations', () async {
      // Arrange
      await repository.initialize();
      final clientId = 'test-sor-008';

      // Act: Perform operations
      await repository.enqueueSalesRequisition(
        clientGeneratedId: clientId,
        tenantDatabaseId: 'tenant-1',
        userId: 'user-1',
        sorDraftPayload: {},
        correlationId: 'corr-1',
      );

      await repository.updateStatus(
        clientId,
        newStatus: OfflineSorStatus.pendingSync,
      );

      // Assert: Audit log contains entries
      final auditLog = repository.getAuditLog(maxEntries: 10);
      expect(
        auditLog.length,
        greaterThanOrEqualTo(3),
      ); // INIT + ENQUEUE + UPDATE

      // Verify log entry structure
      final enqueueEntry = auditLog.firstWhere(
        (entry) => entry['eventType'] == 'SOR_ENQUEUED',
        orElse: () => {},
      );
      expect(enqueueEntry, isNotEmpty);
      expect(enqueueEntry['details']['clientGeneratedId'], clientId);
    });
  });
}

/// Helper function to create a test SOR
Future<void> _createTestSOR(QueueRepository repository, String clientId) async {
  await repository.enqueueSalesRequisition(
    clientGeneratedId: clientId,
    tenantDatabaseId: 'tenant-123',
    userId: 'user-456',
    sorDraftPayload: {'test': 'data'},
    correlationId: 'corr-$clientId',
  );
}

/// Mock secure storage for testing (in-memory)
class MockSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    WebOptions? webOptions,
  }) async {
    return _storage[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    WebOptions? webOptions,
  }) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    WebOptions? webOptions,
  }) async {
    _storage.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    WebOptions? webOptions,
  }) async {
    return Map.from(_storage);
  }
}
