import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/models/offline_sync_contract.dart';
import 'package:new_test_store/models/queued_sales_requisition.dart';
import 'package:new_test_store/services/offline_queue_repository.dart';
import 'package:new_test_store/services/offline_sync_worker.dart';

void main() {
  group('OfflineSyncWorker', () {
    test('skips sync when connectivity is unavailable', () async {
      final repo = _FakeOfflineQueueRepository([
        _queuedSor('sor-1', status: OfflineSorStatus.pendingSync),
      ]);

      final worker = OfflineSyncWorker(
        queueRepository: repo,
        connectivityCheck: () async => false,
      );

      final report = await worker.syncPendingQueue();

      expect(report.blockedByConnectivity, true);
      expect(report.scanned, 0);
      expect(repo.lastStatusById['sor-1'], isNull);
    });

    test('syncs pending item when session is fresh and submit succeeds', () async {
      final repo = _FakeOfflineQueueRepository([
        _queuedSor('sor-2', status: OfflineSorStatus.pendingSync),
      ]);

      final worker = OfflineSyncWorker(
        queueRepository: repo,
        connectivityCheck: () async => true,
        hasFreshSession: () async => true,
        submitSor: (_) async => 'server-id-1',
      );

      final report = await worker.syncPendingQueue(ignoreBackoff: true);

      expect(report.syncedAccepted, 1);
      expect(report.scanned, 1);
      expect(repo.markedAcceptedIds, contains('sor-2'));
      expect(repo.lastStatusById['sor-2'], OfflineSorStatus.syncing);
    });

    test('marks requiresRelogin when refresh fails', () async {
      final repo = _FakeOfflineQueueRepository([
        _queuedSor('sor-3', status: OfflineSorStatus.pendingSync),
      ]);

      final worker = OfflineSyncWorker(
        queueRepository: repo,
        connectivityCheck: () async => true,
        hasFreshSession: () async => false,
        refreshSession: () async => false,
      );

      final report = await worker.syncPendingQueue(ignoreBackoff: true);

      expect(report.requiresRelogin, 1);
      expect(repo.lastStatusById['sor-3'], OfflineSorStatus.requiresRelogin);
      expect(repo.lastErrorCategoryById['sor-3'], OfflineErrorCategory.auth);
    });

    test('maps validation errors to rejectedValidation', () async {
      final repo = _FakeOfflineQueueRepository([
        _queuedSor('sor-4', status: OfflineSorStatus.pendingSync),
      ]);

      final worker = OfflineSyncWorker(
        queueRepository: repo,
        connectivityCheck: () async => true,
        hasFreshSession: () async => true,
        submitSor: (_) async => throw Exception('Validation failed: required field'),
      );

      final report = await worker.syncPendingQueue(ignoreBackoff: true);

      expect(report.rejectedValidation, 1);
      expect(repo.lastStatusById['sor-4'], OfflineSorStatus.rejectedValidation);
      expect(repo.lastErrorCategoryById['sor-4'], OfflineErrorCategory.validation);
    });

    test('schedules retry and eventually exhausts retries', () async {
      final repo = _FakeOfflineQueueRepository([
        _queuedSor(
          'sor-5',
          status: OfflineSorStatus.pendingSync,
          autoRetryCount: autoRetrySchedule.length - 1,
        ),
      ]);

      final worker = OfflineSyncWorker(
        queueRepository: repo,
        connectivityCheck: () async => true,
        hasFreshSession: () async => true,
        submitSor: (_) async => throw Exception('Network timeout'),
      );

      final report = await worker.syncPendingQueue(ignoreBackoff: true);

      expect(report.exhausted, 1);
      expect(repo.lastStatusById['sor-5'], OfflineSorStatus.failedRequiresUserAction);
    });

    test('defers item when backoff window has not elapsed', () async {
      final now = DateTime.now();
      final repo = _FakeOfflineQueueRepository([
        _queuedSor(
          'sor-6',
          status: OfflineSorStatus.pendingSync,
          autoRetryCount: 1,
          lastSyncAttemptTimestamp: now,
        ),
      ]);

      final worker = OfflineSyncWorker(
        queueRepository: repo,
        connectivityCheck: () async => true,
        hasFreshSession: () async => true,
        submitSor: (_) async => 'server-id-2',
      );

      final report = await worker.syncPendingQueue(now: now, ignoreBackoff: false);

      expect(report.deferredByBackoff, 1);
      expect(report.syncedAccepted, 0);
      expect(repo.markedAcceptedIds, isEmpty);
    });
  });
}

QueuedSalesRequisition _queuedSor(
  String id, {
  required OfflineSorStatus status,
  int autoRetryCount = 0,
  DateTime? lastSyncAttemptTimestamp,
}) {
  return QueuedSalesRequisition(
    clientGeneratedId: id,
    tenantDatabaseId: 'tenant-1',
    userId: 'user-1',
    sorDraftPayload: const {'sorNumber': 'S-1'},
    status: status,
    correlationId: 'corr-$id',
    autoRetryCount: autoRetryCount,
    lastSyncAttemptTimestamp: lastSyncAttemptTimestamp,
  );
}

class _FakeOfflineQueueRepository implements OfflineQueueRepository {
  _FakeOfflineQueueRepository(List<QueuedSalesRequisition> seed)
    : _items = {for (final item in seed) item.clientGeneratedId: item};

  final Map<String, QueuedSalesRequisition> _items;
  final Map<String, OfflineSorStatus> lastStatusById = {};
  final Map<String, OfflineErrorCategory?> lastErrorCategoryById = {};
  final List<String> markedAcceptedIds = [];

  @override
  Future<void> initialize() async {}

  @override
  List<QueuedSalesRequisition> getPendingSync() => _items.values.toList();

  @override
  QueuedSalesRequisition? getSalesRequisition(String clientGeneratedId) {
    return _items[clientGeneratedId];
  }

  @override
  Future<void> updateStatus(
    String clientGeneratedId, {
    required OfflineSorStatus newStatus,
    String? lastError,
    OfflineErrorCategory? errorCategory,
    String? rejectionReasons,
    int? autoRetryCount,
    int? manualRetryCount,
    DateTime? rollbackAvailableUntil,
    OfflineSorStatus? emailStatus,
  }) async {
    final existing = _items[clientGeneratedId];
    if (existing == null) return;

    final updated = existing.copyWith(
      status: newStatus,
      lastError: lastError,
      errorCategory: errorCategory,
      rejectionReasons: rejectionReasons,
      autoRetryCount: autoRetryCount,
      manualRetryCount: manualRetryCount,
      rollbackAvailableUntil: rollbackAvailableUntil,
      emailStatus: emailStatus,
      lastSyncAttemptTimestamp: DateTime.now(),
    );

    _items[clientGeneratedId] = updated;
    lastStatusById[clientGeneratedId] = newStatus;
    lastErrorCategoryById[clientGeneratedId] = errorCategory;
  }

  @override
  Future<void> incrementAutoRetry(String clientGeneratedId) async {
    final existing = _items[clientGeneratedId];
    if (existing == null) return;

    existing.incrementAutoRetryCount();
    _items[clientGeneratedId] = existing;
  }

  @override
  Future<void> markSyncAccepted(String clientGeneratedId) async {
    final existing = _items[clientGeneratedId];
    if (existing == null) return;

    final updated = existing.copyWith(
      status: OfflineSorStatus.syncedAccepted,
      emailStatus: OfflineSorStatus.emailPending,
      rollbackAvailableUntil: DateTime.now().add(const Duration(hours: 24)),
      lastError: null,
      errorCategory: null,
    );
    _items[clientGeneratedId] = updated;
    markedAcceptedIds.add(clientGeneratedId);
  }

  @override
  Future<int> clearExpiredItems() async => 0;
}
