import 'package:connectivity_plus/connectivity_plus.dart';

import '../utils/app_logger.dart';

/// Thin wrapper over connectivity_plus exposing a boolean online/offline view —
/// a one-shot check plus a live stream — so UI and services react to
/// reconnection instead of each caller re-deriving "any result is not none".
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _isOnline(results);
    } catch (e, st) {
      // A failed probe means we can't confirm connectivity — report offline so
      // callers take the safe path (queue writes, skip warming) instead of
      // throwing out of a submission or startup flow.
      AppLogger.warning(
        'Connectivity check failed; assuming offline',
        tag: 'CONNECTIVITY',
      );
      AppLogger.error(
        'Connectivity probe failed',
        error: e,
        stackTrace: st,
        tag: 'CONNECTIVITY',
      );
      return false;
    }
  }

  /// Emits `true`/`false` as connectivity changes; distinct so listeners only
  /// rebuild on an actual online<->offline transition.
  Stream<bool> get onlineStream =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
