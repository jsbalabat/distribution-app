import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../models/offline_sync_contract.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_service.dart';
import '../services/firestore_tenant.dart';
import '../services/queue_repository.dart';
import '../utils/app_logger.dart';

enum OfflineSubmissionRoute { online, queuedPendingSync, queuedRequiresRelogin }

class OfflineSubmissionResult {
  final OfflineSubmissionRoute route;
  final String requisitionId;
  final String? queueItemId;
  final OfflineSorStatus? queueStatus;
  // Set on the online route, where the server assigns these at write time; null
  // for queued routes, which receive them later when the sync worker uploads.
  final String? sorNumber;
  final String? remark1;
  final String? remark2;

  const OfflineSubmissionResult({
    required this.route,
    required this.requisitionId,
    this.queueItemId,
    this.queueStatus,
    this.sorNumber,
    this.remark1,
    this.remark2,
  });

  bool get wasQueued => route != OfflineSubmissionRoute.online;
  bool get requiresRelogin =>
      route == OfflineSubmissionRoute.queuedRequiresRelogin;
}

class OfflineSubmissionService {
  OfflineSubmissionService._();

  static final OfflineSubmissionService instance = OfflineSubmissionService._();

  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final QueueRepository _queueRepository = QueueRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // The uuid package's constructor is not const, so hold a single instance.
  final Uuid _uuidGen = Uuid();

  Future<OfflineSubmissionResult> submitOrQueue(
    Map<String, dynamic> formData,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final hasConnectivity = await ConnectivityService.instance.isOnline();
    final cachedSessionFresh = await _authService.hasFreshCachedSession();

    if (hasConnectivity) {
      final refreshed = await _authService.refreshSessionIfPossible();
      if (refreshed) {
        final outcome = await _firestoreService.submitSOR(formData);
        AppLogger.info(
          'Online requisition submission succeeded for uid=${user.uid}',
          tag: 'OFFLINE_GATE',
        );
        return OfflineSubmissionResult(
          route: OfflineSubmissionRoute.online,
          requisitionId: outcome.requisitionId,
          sorNumber: outcome.sorNumber,
          remark1: outcome.remark1,
          remark2: outcome.remark2,
        );
      }

      AppLogger.warning(
        'Unable to refresh session during submission gate; queuing locally',
        tag: 'OFFLINE_GATE',
      );
    }

    final queuedStatus = cachedSessionFresh
        ? OfflineSorStatus.pendingSync
        : OfflineSorStatus.requiresRelogin;

    return _queueSubmission(
      formData: formData,
      user: user,
      status: queuedStatus,
    );
  }

  Future<OfflineSubmissionResult> _queueSubmission({
    required Map<String, dynamic> formData,
    required User user,
    required OfflineSorStatus status,
  }) async {
    await _queueRepository.initialize();

    final clientGeneratedId = _resolveClientGeneratedId(formData);
    final correlationId = _resolveCorrelationId(formData, user.uid);
    final tenantDatabaseId = FirestoreTenant.instance.databaseId;

    await _queueRepository.enqueueSalesRequisition(
      clientGeneratedId: clientGeneratedId,
      tenantDatabaseId: tenantDatabaseId,
      userId: user.uid,
      sorDraftPayload: {
        ...formData,
        'clientGeneratedId': clientGeneratedId,
        'correlationId': correlationId,
        'tenantDatabaseId': tenantDatabaseId,
        'queuedAt': Timestamp.now(),
      },
      correlationId: correlationId,
    );

    await _queueRepository.updateStatus(
      clientGeneratedId,
      newStatus: status,
      lastError: status == OfflineSorStatus.requiresRelogin
          ? 'Session requires re-login before sync.'
          : 'Queued locally until connectivity returns.',
      errorCategory: status == OfflineSorStatus.requiresRelogin
          ? OfflineErrorCategory.auth
          : OfflineErrorCategory.network,
    );

    AppLogger.info(
      'Submission queued locally (${status.label}) for uid=${user.uid}',
      tag: 'OFFLINE_GATE',
    );

    return OfflineSubmissionResult(
      route: status == OfflineSorStatus.requiresRelogin
          ? OfflineSubmissionRoute.queuedRequiresRelogin
          : OfflineSubmissionRoute.queuedPendingSync,
      requisitionId: clientGeneratedId,
      queueItemId: clientGeneratedId,
      queueStatus: status,
    );
  }

  String _resolveClientGeneratedId(Map<String, dynamic> formData) {
    final existing = formData['clientGeneratedId']?.toString().trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    // UUID v7 is time-ordered and the format the submit callable requires as
    // its idempotency key / document id.
    return _uuidGen.v7();
  }

  String _resolveCorrelationId(Map<String, dynamic> formData, String uid) {
    final existing = formData['correlationId']?.toString().trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    return 'corr-$uid-${DateTime.now().microsecondsSinceEpoch}';
  }
}
