import '../models/offline_sync_contract.dart';
import '../models/queued_sales_requisition.dart';

abstract class OfflineQueueRepository {
  Future<void> initialize();

  List<QueuedSalesRequisition> getPendingSync();

  QueuedSalesRequisition? getSalesRequisition(String clientGeneratedId);

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
  });

  Future<void> incrementAutoRetry(String clientGeneratedId);

  Future<void> markSyncAccepted(String clientGeneratedId);

  Future<int> clearExpiredItems();
}
