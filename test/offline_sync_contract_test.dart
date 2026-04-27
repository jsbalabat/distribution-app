import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/models/offline_sync_contract.dart';

void main() {
  group('Offline sync contract', () {
    test('manual retry constants match agreed policy', () {
      expect(manualRetryLimit, 3);
      expect(manualRetryCooldown.inSeconds, 30);
    });

    test('auto retry schedule matches expected backoff profile', () {
      const expected = [0, 30, 120, 600, 1800, 7200, 21600, 43200, 86400];
      expect(autoRetrySchedule.map((d) => d.inSeconds).toList(), expected);
    });

    test('retry jitter rate remains within safe range', () {
      expect(retryJitterRate, greaterThan(0));
      expect(retryJitterRate, lessThanOrEqualTo(0.5));
      expect(retryJitterRate, 0.2);
    });

    test('offline status labels are stable for user-facing states', () {
      expect(OfflineSorStatus.pendingSync.label, 'Pending Sync');
      expect(OfflineSorStatus.requiresRelogin.label, 'Requires Re-Login');
      expect(OfflineSorStatus.syncedAccepted.label, 'Synced Accepted');
    });

    test('event keys map to expected analytics values', () {
      expect(
        OfflineEventType.sorSyncRequiresRelogin.key,
        'sor_sync_requires_relogin',
      );
      expect(OfflineEventType.emailDispatchSent.key, 'email_dispatch_sent');
      expect(OfflineEventType.rollbackCompleted.key, 'rollback_completed');
    });
  });
}
