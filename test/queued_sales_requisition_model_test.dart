import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/models/offline_sync_contract.dart';
import 'package:new_test_store/models/queued_sales_requisition.dart';

void main() {
  group('QueuedSalesRequisition model', () {
    test('incrementManualRetryCount respects manual limit', () {
      final sor = QueuedSalesRequisition(
        clientGeneratedId: 'id-1',
        tenantDatabaseId: 'tenant-1',
        userId: 'user-1',
        sorDraftPayload: const {},
        status: OfflineSorStatus.pendingSync,
        correlationId: 'corr-1',
        manualRetryCount: manualRetryLimit,
      );

      sor.incrementManualRetryCount();
      expect(sor.manualRetryCount, manualRetryLimit);
    });

    test('canManualRetry enforces cooldown window', () {
      final now = DateTime.now();
      final sor = QueuedSalesRequisition(
        clientGeneratedId: 'id-2',
        tenantDatabaseId: 'tenant-1',
        userId: 'user-1',
        sorDraftPayload: const {},
        status: OfflineSorStatus.pendingSync,
        correlationId: 'corr-2',
        manualRetryCount: 1,
        lastManualRetryTimestamp: now,
      );

      expect(sor.canManualRetry(now), false);
      expect(sor.canManualRetry(now.add(manualRetryCooldown)), true);
    });

    test('canRollback returns true only before deadline', () {
      final now = DateTime.now();
      final sor = QueuedSalesRequisition(
        clientGeneratedId: 'id-3',
        tenantDatabaseId: 'tenant-1',
        userId: 'user-1',
        sorDraftPayload: const {},
        status: OfflineSorStatus.syncedAccepted,
        correlationId: 'corr-3',
        rollbackAvailableUntil: now.add(const Duration(hours: 1)),
      );

      expect(sor.canRollback(now), true);
      expect(sor.canRollback(now.add(const Duration(hours: 2))), false);
    });

    test('copyWith preserves existing values when omitted', () {
      final createdAt = DateTime(2026, 4, 27, 12, 0);
      final sor = QueuedSalesRequisition(
        clientGeneratedId: 'id-4',
        tenantDatabaseId: 'tenant-1',
        userId: 'user-1',
        sorDraftPayload: const {'x': 1},
        status: OfflineSorStatus.pendingSync,
        correlationId: 'corr-4',
        createdTimestamp: createdAt,
      );

      final updated = sor.copyWith(status: OfflineSorStatus.syncing);

      expect(updated.clientGeneratedId, sor.clientGeneratedId);
      expect(updated.tenantDatabaseId, sor.tenantDatabaseId);
      expect(updated.userId, sor.userId);
      expect(updated.sorDraftPayload, sor.sorDraftPayload);
      expect(updated.status, OfflineSorStatus.syncing);
      expect(updated.createdTimestamp, createdAt);
      expect(updated.correlationId, sor.correlationId);
    });

    test('incrementAutoRetryCount clamps to 9', () {
      final sor = QueuedSalesRequisition(
        clientGeneratedId: 'id-5',
        tenantDatabaseId: 'tenant-1',
        userId: 'user-1',
        sorDraftPayload: const {},
        status: OfflineSorStatus.pendingSync,
        correlationId: 'corr-5',
      );

      for (int i = 0; i < 20; i++) {
        sor.incrementAutoRetryCount();
      }

      expect(sor.autoRetryCount, 9);
    });
  });
}
