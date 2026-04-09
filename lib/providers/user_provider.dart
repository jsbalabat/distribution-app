// lib/providers/user_provider.dart
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_tenant.dart';
import '../utils/app_logger.dart';

class UserProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  UserModel? _currentUser;
  bool _isLoading = true;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  UserProvider() {
    _initUser();
  }

  Future<void> _initUser() async {
    _isLoading = true;
    notifyListeners();

    await FirestoreTenant.instance.loadFromStorage();

    _currentUser = await _authService.getCurrentUser();
    _isLoading = false;
    notifyListeners();

    // Listen to auth changes
    _authService.userStream.listen(
      (user) {
        _currentUser = user;
        notifyListeners();
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
