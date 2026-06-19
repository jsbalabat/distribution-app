import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_tenant.dart';
import '../utils/app_logger.dart';

/// Pre-fetches the reference data the SOR form reads so Firestore's on-disk cache
/// can serve it offline. Best-effort: a failure to warm never blocks the caller,
/// it just leaves that collection's cache as-is.
class ReferenceDataWarmer {
  ReferenceDataWarmer._();

  static final ReferenceDataWarmer instance = ReferenceDataWarmer._();

  // Every collection the SOR form resolves at creation time, plus the signed-in
  // user's own profile (so app routing survives a cold offline reopen).
  static const List<String> _collections = [
    'customers',
    'itemsAvailable',
    'itemMaster',
    'accountReceivable',
  ];

  final Connectivity _connectivity = Connectivity();
  bool _warmInProgress = false;

  Future<void> warm() async {
    if (_warmInProgress) {
      AppLogger.info(
        'Reference warm already in progress; skipping.',
        tag: 'REF_WARM',
      );
      return;
    }

    // Warming only refreshes the cache when online — a server read is the point.
    if (!await _hasConnectivity()) {
      AppLogger.info('Skipping reference warm; device is offline.', tag: 'REF_WARM');
      return;
    }

    _warmInProgress = true;
    try {
      final firestore = FirestoreTenant.instance.firestore;

      for (final path in _collections) {
        await _warmCollection(firestore, path);
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _warmUserProfile(firestore, uid);
      }

      AppLogger.info('Reference data warm complete.', tag: 'REF_WARM');
    } finally {
      _warmInProgress = false;
    }
  }

  Future<void> _warmCollection(FirebaseFirestore firestore, String path) async {
    try {
      // Source.server forces a network read so the persistent cache that offline
      // .get() falls back to is genuinely refreshed, not just re-read.
      final snapshot = await firestore
          .collection(path)
          .get(const GetOptions(source: Source.server));
      AppLogger.info(
        'Warmed $path (${snapshot.docs.length} docs).',
        tag: 'REF_WARM',
      );
    } catch (e, st) {
      AppLogger.error(
        'Failed to warm $path',
        error: e,
        stackTrace: st,
        tag: 'REF_WARM',
      );
    }
  }

  Future<void> _warmUserProfile(FirebaseFirestore firestore, String uid) async {
    try {
      await firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      AppLogger.info('Warmed users/$uid.', tag: 'REF_WARM');
    } catch (e, st) {
      AppLogger.error(
        'Failed to warm user profile',
        error: e,
        stackTrace: st,
        tag: 'REF_WARM',
      );
    }
  }

  Future<bool> _hasConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
