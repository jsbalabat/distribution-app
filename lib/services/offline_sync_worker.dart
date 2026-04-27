import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/offline_sync_contract.dart';
import '../models/queued_sales_requisition.dart';
import '../utils/app_logger.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'offline_queue_repository.dart';
import 'queue_repository.dart';

typedef ConnectivityCheck = Future<bool> Function();
typedef SessionFreshCheck = Future<bool> Function();
typedef SessionRefresh = Future<bool> Function();
typedef SubmitSor = Future<String> Function(Map<String, dynamic> payload);

class OfflineSyncReport {
  int scanned = 0;
  int skippedDraft = 0;
  int deferredByBackoff = 0;
  int syncedAccepted = 0;
  int rejectedValidation = 0;
  int rejectedInventory = 0;
  int requiresRelogin = 0;
  int exhausted = 0;
  int retryScheduled = 0;
  int cleanupDeleted = 0;
  bool blockedByConnectivity = false;

  @override
  String toString() {
    return 'OfflineSyncReport(scanned: $scanned, syncedAccepted: $syncedAccepted, '
        'rejectedValidation: $rejectedValidation, rejectedInventory: $rejectedInventory, '
        'requiresRelogin: $requiresRelogin, exhausted: $exhausted, '
        'retryScheduled: $retryScheduled, deferredByBackoff: $deferredByBackoff, '
        'cleanupDeleted: $cleanupDeleted, blockedByConnectivity: $blockedByConnectivity)';
  }
}

class OfflineSyncWorker {
  OfflineSyncWorker({
    OfflineQueueRepository? queueRepository,
    ConnectivityCheck? connectivityCheck,
    SessionFreshCheck? hasFreshSession,
    SessionRefresh? refreshSession,
    SubmitSor? submitSor,
  }) : _queueRepository = queueRepository ?? QueueRepository(),
       _connectivityCheck = connectivityCheck,
       _hasFreshSession = hasFreshSession,
       _refreshSession = refreshSession,
       _submitSor = submitSor;

  static final OfflineSyncWorker instance = OfflineSyncWorker();

  final OfflineQueueRepository _queueRepository;
  AuthService? _authService;
  FirestoreService? _firestoreService;
  Connectivity? _connectivity;

  final ConnectivityCheck? _connectivityCheck;
  final SessionFreshCheck? _hasFreshSession;
  final SessionRefresh? _refreshSession;
  final SubmitSor? _submitSor;

  bool _syncInProgress = false;

  Future<OfflineSyncReport> syncPendingQueue({
    DateTime? now,
    bool ignoreBackoff = false,
  }) async {
    final report = OfflineSyncReport();
    final syncTime = now ?? DateTime.now();

    if (_syncInProgress) {
      AppLogger.info('Sync worker is already in progress; skipping.', tag: 'OFFLINE_SYNC');
      return report;
    }

    _syncInProgress = true;

    try {
      await _queueRepository.initialize();

      final hasConnectivity = await _checkConnectivity();
      if (!hasConnectivity) {
        report.blockedByConnectivity = true;
        return report;
      }

      final pending = _queueRepository.getPendingSync()
        ..sort((a, b) => a.createdTimestamp.compareTo(b.createdTimestamp));

      for (final item in pending) {
        report.scanned++;

        if (item.status == OfflineSorStatus.draftOffline ||
            item.status == OfflineSorStatus.cancelledByUser) {
          report.skippedDraft++;
          continue;
        }

        if (item.status == OfflineSorStatus.failedRequiresUserAction) {
          report.exhausted++;
          continue;
        }

        if (item.autoRetryCount >= autoRetrySchedule.length) {
          await _queueRepository.updateStatus(
            item.clientGeneratedId,
            newStatus: OfflineSorStatus.failedRequiresUserAction,
            lastError: 'Automatic retries exhausted.',
            errorCategory: OfflineErrorCategory.network,
          );
          report.exhausted++;
          continue;
        }

        if (!ignoreBackoff && !_isRetryDue(item, syncTime)) {
          report.deferredByBackoff++;
          continue;
        }

        final hasFreshSession = await _checkFreshSession();
        if (!hasFreshSession) {
          final refreshed = await _refreshCurrentSession();
          if (!refreshed) {
            await _queueRepository.updateStatus(
              item.clientGeneratedId,
              newStatus: OfflineSorStatus.requiresRelogin,
              lastError: 'Session expired. Sign in again to continue sync.',
              errorCategory: OfflineErrorCategory.auth,
            );
            report.requiresRelogin++;
            continue;
          }
        }

        await _queueRepository.updateStatus(
          item.clientGeneratedId,
          newStatus: OfflineSorStatus.syncing,
          lastError: null,
          errorCategory: null,
        );

        try {
          await _submit(item.sorDraftPayload);
          await _queueRepository.markSyncAccepted(item.clientGeneratedId);
          report.syncedAccepted++;
        } catch (e, st) {
          final category = _classifySyncError(e);
          final message = e.toString();

          AppLogger.error(
            'Offline sync attempt failed for ${item.clientGeneratedId}',
            error: e,
            stackTrace: st,
            tag: 'OFFLINE_SYNC',
          );

          if (category == OfflineErrorCategory.validation) {
            await _queueRepository.updateStatus(
              item.clientGeneratedId,
              newStatus: OfflineSorStatus.rejectedValidation,
              lastError: message,
              errorCategory: category,
            );
            report.rejectedValidation++;
            continue;
          }

          if (category == OfflineErrorCategory.inventory) {
            await _queueRepository.updateStatus(
              item.clientGeneratedId,
              newStatus: OfflineSorStatus.rejectedInventory,
              lastError: message,
              errorCategory: category,
            );
            report.rejectedInventory++;
            continue;
          }

          if (category == OfflineErrorCategory.auth) {
            await _queueRepository.updateStatus(
              item.clientGeneratedId,
              newStatus: OfflineSorStatus.requiresRelogin,
              lastError: message,
              errorCategory: category,
            );
            report.requiresRelogin++;
            continue;
          }

          await _queueRepository.incrementAutoRetry(item.clientGeneratedId);
          final refreshedItem = _queueRepository.getSalesRequisition(
            item.clientGeneratedId,
          );

          if (refreshedItem == null ||
              refreshedItem.autoRetryCount >= autoRetrySchedule.length) {
            await _queueRepository.updateStatus(
              item.clientGeneratedId,
              newStatus: OfflineSorStatus.failedRequiresUserAction,
              lastError: 'Automatic retries exhausted: $message',
              errorCategory: category,
            );
            report.exhausted++;
            continue;
          }

          await _queueRepository.updateStatus(
            item.clientGeneratedId,
            newStatus: OfflineSorStatus.pendingSync,
            lastError: message,
            errorCategory: category,
          );
          report.retryScheduled++;
        }
      }

      report.cleanupDeleted = await _queueRepository.clearExpiredItems();
      AppLogger.info('Offline sync completed: $report', tag: 'OFFLINE_SYNC');
      return report;
    } finally {
      _syncInProgress = false;
    }
  }

  bool _isRetryDue(QueuedSalesRequisition item, DateTime now) {
    final lastAttempt = item.lastSyncAttemptTimestamp;
    if (lastAttempt == null) {
      return true;
    }

    if (item.autoRetryCount >= autoRetrySchedule.length) {
      return false;
    }

    final baseDelay = autoRetrySchedule[item.autoRetryCount];
    final jitteredDelay = _applyDeterministicJitter(
      baseDelay,
      item.clientGeneratedId,
    );

    return !now.isBefore(lastAttempt.add(jitteredDelay));
  }

  Duration _applyDeterministicJitter(Duration baseDelay, String seed) {
    if (baseDelay == Duration.zero) {
      return Duration.zero;
    }

    final hash = seed.codeUnits.fold<int>(0, (acc, v) => (acc * 31) ^ v) &
        0x7fffffff;
    final normalized = ((hash % 2001) - 1000) / 1000.0;
    final factor = 1 + (normalized * retryJitterRate);
    final jitteredMs = (baseDelay.inMilliseconds * factor).round();
    final safeMs = jitteredMs < 0 ? 0 : jitteredMs;
    return Duration(milliseconds: safeMs);
  }

  Future<bool> _checkConnectivity() async {
    if (_connectivityCheck != null) {
      return _connectivityCheck();
    }

    _connectivity ??= Connectivity();
    final results = await _connectivity!.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<bool> _checkFreshSession() async {
    if (_hasFreshSession != null) {
      return _hasFreshSession();
    }

    _authService ??= AuthService();
    return _authService!.hasFreshCachedSession();
  }

  Future<bool> _refreshCurrentSession() async {
    if (_refreshSession != null) {
      return _refreshSession();
    }

    _authService ??= AuthService();
    return _authService!.refreshSessionIfPossible();
  }

  Future<String> _submit(Map<String, dynamic> payload) async {
    if (_submitSor != null) {
      return _submitSor(payload);
    }

    _firestoreService ??= FirestoreService();
    return _firestoreService!.submitSOR(payload);
  }

  OfflineErrorCategory _classifySyncError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('inventory') ||
        message.contains('stock') ||
        message.contains('insufficient')) {
      return OfflineErrorCategory.inventory;
    }

    if (message.contains('validation') ||
        message.contains('invalid') ||
        message.contains('required')) {
      return OfflineErrorCategory.validation;
    }

    if (message.contains('auth') ||
        message.contains('permission-denied') ||
        message.contains('token') ||
        message.contains('login') ||
        message.contains('unauth')) {
      return OfflineErrorCategory.auth;
    }

    if (message.contains('network') ||
        message.contains('timeout') ||
        message.contains('socket') ||
        message.contains('unavailable')) {
      return OfflineErrorCategory.network;
    }

    return OfflineErrorCategory.unknown;
  }
}
