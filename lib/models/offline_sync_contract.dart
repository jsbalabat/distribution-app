enum OfflineSorStatus {
  draftOffline,
  pendingSync,
  syncing,
  syncedAccepted,
  rejectedValidation,
  rejectedInventory,
  requiresRelogin,
  emailPending,
  emailSent,
  emailFailedRetryAvailable,
  rollbackAvailable,
  rolledBack,
  failedRequiresUserAction,
  cancelledByUser,
}

enum OfflineErrorCategory {
  auth,
  network,
  validation,
  inventory,
  email,
  unknown,
}

enum OfflineEventType {
  sorCreatedOffline,
  sorQueuedForSync,
  sorSyncStarted,
  sorSyncAccepted,
  sorSyncRejectedValidation,
  sorSyncRejectedInventory,
  sorSyncRequiresRelogin,
  sorSyncRetryScheduled,
  sorSyncExhausted,
  sorCancelledByUser,
  emailDispatchStarted,
  emailDispatchSent,
  emailDispatchFailed,
  emailResendRequested,
  emailResendFailed,
  rollbackEligible,
  rollbackRequested,
  rollbackCompleted,
}

const int manualRetryLimit = 3;
const Duration manualRetryCooldown = Duration(seconds: 30);

const List<Duration> autoRetrySchedule = [
  Duration(seconds: 0),
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
  Duration(minutes: 30),
  Duration(hours: 2),
  Duration(hours: 6),
  Duration(hours: 12),
  Duration(hours: 24),
];

const double retryJitterRate = 0.2;

extension OfflineSorStatusLabel on OfflineSorStatus {
  String get label {
    switch (this) {
      case OfflineSorStatus.draftOffline:
        return 'Draft Offline';
      case OfflineSorStatus.pendingSync:
        return 'Pending Sync';
      case OfflineSorStatus.syncing:
        return 'Syncing';
      case OfflineSorStatus.syncedAccepted:
        return 'Synced Accepted';
      case OfflineSorStatus.rejectedValidation:
        return 'Rejected Validation';
      case OfflineSorStatus.rejectedInventory:
        return 'Rejected Inventory';
      case OfflineSorStatus.requiresRelogin:
        return 'Requires Re-Login';
      case OfflineSorStatus.emailPending:
        return 'Email Pending';
      case OfflineSorStatus.emailSent:
        return 'Email Sent';
      case OfflineSorStatus.emailFailedRetryAvailable:
        return 'Email Failed Retry Available';
      case OfflineSorStatus.rollbackAvailable:
        return 'Rollback Available';
      case OfflineSorStatus.rolledBack:
        return 'Rolled Back';
      case OfflineSorStatus.failedRequiresUserAction:
        return 'Failed Requires User Action';
      case OfflineSorStatus.cancelledByUser:
        return 'Cancelled By User';
    }
  }
}

extension OfflineEventTypeKey on OfflineEventType {
  String get key {
    switch (this) {
      case OfflineEventType.sorCreatedOffline:
        return 'sor_created_offline';
      case OfflineEventType.sorQueuedForSync:
        return 'sor_queued_for_sync';
      case OfflineEventType.sorSyncStarted:
        return 'sor_sync_started';
      case OfflineEventType.sorSyncAccepted:
        return 'sor_sync_accepted';
      case OfflineEventType.sorSyncRejectedValidation:
        return 'sor_sync_rejected_validation';
      case OfflineEventType.sorSyncRejectedInventory:
        return 'sor_sync_rejected_inventory';
      case OfflineEventType.sorSyncRequiresRelogin:
        return 'sor_sync_requires_relogin';
      case OfflineEventType.sorSyncRetryScheduled:
        return 'sor_sync_retry_scheduled';
      case OfflineEventType.sorSyncExhausted:
        return 'sor_sync_exhausted';
      case OfflineEventType.sorCancelledByUser:
        return 'sor_cancelled_by_user';
      case OfflineEventType.emailDispatchStarted:
        return 'email_dispatch_started';
      case OfflineEventType.emailDispatchSent:
        return 'email_dispatch_sent';
      case OfflineEventType.emailDispatchFailed:
        return 'email_dispatch_failed';
      case OfflineEventType.emailResendRequested:
        return 'email_resend_requested';
      case OfflineEventType.emailResendFailed:
        return 'email_resend_failed';
      case OfflineEventType.rollbackEligible:
        return 'rollback_eligible';
      case OfflineEventType.rollbackRequested:
        return 'rollback_requested';
      case OfflineEventType.rollbackCompleted:
        return 'rollback_completed';
    }
  }
}
