// lib/providers/user_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_tenant.dart';
import '../services/offline_sync_worker.dart';
import '../services/reference_data_warmer.dart';
import '../utils/app_logger.dart';

class UserProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  UserModel? _currentUser;
  bool _isLoading = true;

  // Auto-sync when the network returns mid-session; debounced so a flapping
  // connection triggers a single drain rather than one attempt per flap.
  static const Duration _reconnectSyncDebounce = Duration(seconds: 2);
  StreamSubscription<bool>? _connectivitySub;
  Timer? _reconnectDebounce;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  Future<bool> canSyncCurrentSession() {
    return _authService.hasFreshCachedSession();
  }

  Future<bool> refreshSessionIfPossible() {
    return _authService.refreshSessionIfPossible();
  }

  UserProvider() {
    _initUser();
  }

  void _scheduleSync() {
    unawaited(
      Future<void>(() async {
        try {
          await OfflineSyncWorker.instance.syncPendingQueue();
        } catch (e, st) {
          AppLogger.error(
            'Background offline sync trigger failed',
            error: e,
            stackTrace: st,
            tag: 'PROVIDER',
          );
        }
      }),
    );
  }

  void _scheduleWarm() {
    unawaited(
      Future<void>(() async {
        try {
          await ReferenceDataWarmer.instance.warm();
        } catch (e, st) {
          AppLogger.error(
            'Background reference warm trigger failed',
            error: e,
            stackTrace: st,
            tag: 'PROVIDER',
          );
        }
      }),
    );
  }

  Future<void> _initUser() async {
    _isLoading = true;
    notifyListeners();

    await FirestoreTenant.instance.loadFromStorage();

    _currentUser = await _authService.getCurrentUser();
    _isLoading = false;
    notifyListeners();

    if (_currentUser != null) {
      _scheduleSync();
      _scheduleWarm();
    }

    // Listen to auth changes
    _authService.userStream.listen(
      (user) {
        _currentUser = user;
        notifyListeners();
        if (user != null) {
          _scheduleSync();
          _scheduleWarm();
        }
      },
      onError: (error, stackTrace) {
        AppLogger.error(
          'Auth user stream emitted an error',
          error: error,
          stackTrace: stackTrace is StackTrace ? stackTrace : null,
          tag: 'PROVIDER',
        );
      },
    );

    _watchReconnect();
  }

  // Drains the offline queue automatically when connectivity returns while the
  // app is open — without this, sync only runs on auth events or the manual
  // refresh button. onlineStream is distinct, so a `true` here is a genuine
  // offline->online transition; the worker's in-progress guard dedupes overlap.
  void _watchReconnect() {
    _connectivitySub = ConnectivityService.instance.onlineStream.listen((
      online,
    ) {
      if (!online) {
        _reconnectDebounce?.cancel();
        return;
      }
      _reconnectDebounce?.cancel();
      _reconnectDebounce = Timer(_reconnectSyncDebounce, () {
        if (_currentUser != null) {
          AppLogger.info(
            'Connectivity restored; triggering offline sync.',
            tag: 'PROVIDER',
          );
          _scheduleSync();
        }
      });
    });
  }

  @override
  void dispose() {
    _reconnectDebounce?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<bool> signIn(
    String email,
    String password, {
    String? companyIdentifier,
    String? databaseId,
  }) async {
    try {
      AppLogger.info(
        'Provider signIn started (company=${(companyIdentifier ?? '').trim().toLowerCase()})',
        tag: 'PROVIDER',
      );

      _isLoading = true;
      notifyListeners();

      _currentUser = await _authService.signInWithEmailAndPassword(
        email,
        password,
        companyIdentifier: companyIdentifier,
        databaseId: databaseId,
      );
      _isLoading = false;
      notifyListeners();
      if (_currentUser != null) {
        _scheduleSync();
        _scheduleWarm();
      }
      AppLogger.info(
        'Provider signIn succeeded (isLoggedIn=${_currentUser != null})',
        tag: 'PROVIDER',
      );
      return _currentUser != null;
    } catch (e, st) {
      AppLogger.error(
        'UserProvider signIn failed',
        error: e,
        stackTrace: st,
        tag: 'PROVIDER',
      );
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    await _authService.signOut();
    _currentUser = null;
    _isLoading = false;
    notifyListeners();
  }
}
