// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'firestore_tenant.dart';
import '../utils/app_logger.dart';
import '../utils/error_mapper.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreTenant _tenant = FirestoreTenant.instance;

  FirebaseFirestore get _firestore => _tenant.firestore;

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final local = parts.first;
    final domain = parts.last;
    if (local.length <= 2) {
      return '$local@$domain';
    }
    return '${local.substring(0, 2)}***@$domain';
  }

  Future<String> _resolveDatabaseId({
    String? companyIdentifier,
    String? databaseId,
  }) async {
    final explicitDatabaseId = databaseId?.trim();
    if (explicitDatabaseId != null && explicitDatabaseId.isNotEmpty) {
      AppLogger.info(
        'Using explicit databaseId for login: $explicitDatabaseId',
        tag: 'AUTH',
      );
      return explicitDatabaseId;
    }

    final identifier = companyIdentifier?.trim().toLowerCase() ?? '';
    if (identifier.isEmpty) {
      throw Exception('Please enter your company identifier.');
    }

    AppLogger.info('Resolving company identifier: $identifier', tag: 'AUTH');

    DocumentSnapshot<Map<String, dynamic>> directoryDoc;
    try {
      directoryDoc = await FirebaseFirestore.instance
          .collection('companyTenants')
          .doc(identifier)
          .get();
    } on FirebaseException catch (e, st) {
      AppLogger.error(
        'Failed reading companyTenants/$identifier while resolving login tenant',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      if (e.code == 'permission-denied') {
        throw Exception(
          'Company lookup is blocked by Firestore rules. Deploy the latest rules and try again.',
        );
      }
      throw Exception(
        ErrorMapper.mapFirestoreError(
          e.code,
          action: 'Resolving company identifier',
        ),
      );
    }

    if (!directoryDoc.exists) {
      throw Exception('Unknown company identifier: $identifier');
    }

    final data = directoryDoc.data() ?? <String, dynamic>{};
    final isActive = data['isActive'] != false;
    if (!isActive) {
      throw Exception('This company is currently inactive.');
    }

    final resolvedDatabaseId =
        (data['firestoreDatabaseId'] ?? data['databaseId'] ?? '')
            .toString()
            .trim();
    if (resolvedDatabaseId.isEmpty) {
      throw Exception(
        'Company identifier is missing a Firestore database mapping.',
      );
    }

    AppLogger.info(
      'Resolved company $identifier to Firestore database $resolvedDatabaseId',
      tag: 'AUTH',
    );

    return resolvedDatabaseId;
  }

  // Get current user with role
  Future<UserModel?> getCurrentUser() async {
    final User? user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!, user.uid);
      } else {
        AppLogger.warning(
          'Signed-in user has no profile in the selected tenant database.',
          tag: 'AUTH',
        );
        await _auth.signOut();
        return null;
      }
    } on FirebaseException catch (e, st) {
      AppLogger.error(
        'Failed to load current user profile due to Firestore permission issue '
        '(database=${_tenant.databaseId})',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      return null;
    } catch (e, st) {
      AppLogger.error(
        'Failed to load current user profile',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      return null;
    }
  }

  // Sign in with email and password
  Future<UserModel?> signInWithEmailAndPassword(
    String email,
    String password, {
    String? companyIdentifier,
    String? databaseId,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedCompanyIdentifier = companyIdentifier?.trim().toLowerCase();

    if (trimmedEmail.isEmpty) {
      throw Exception('Please enter your email.');
    }
    if (password.isEmpty) {
      throw Exception('Please enter your password.');
    }
    if ((databaseId == null || databaseId.trim().isEmpty) &&
        (trimmedCompanyIdentifier == null ||
            trimmedCompanyIdentifier.isEmpty)) {
      throw Exception('Please enter your company identifier.');
    }

    AppLogger.info(
      'Login attempt started for ${_maskEmail(trimmedEmail)} with company identifier '
      '${trimmedCompanyIdentifier ?? '(none)'}',
      tag: 'AUTH',
    );

    String? activeDatabaseId;

    try {
      final resolvedDatabaseId = await _resolveDatabaseId(
        companyIdentifier: trimmedCompanyIdentifier,
        databaseId: databaseId,
      );
      await _tenant.saveDatabaseId(resolvedDatabaseId);
      activeDatabaseId = resolvedDatabaseId;
      AppLogger.info(
        'Saved active tenant database: $resolvedDatabaseId',
        tag: 'AUTH',
      );

      final result = await _auth.signInWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      AppLogger.info(
        'FirebaseAuth sign-in succeeded for uid=${result.user?.uid ?? 'unknown'}',
        tag: 'AUTH',
      );

      if (result.user != null) {
        final profileDoc = await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .get();

        if (!profileDoc.exists) {
          AppLogger.warning(
            'User profile missing in tenant database $resolvedDatabaseId for uid=${result.user!.uid}',
            tag: 'AUTH',
          );
          await _auth.signOut();
          throw Exception(
            'Your account is not assigned to this company. Contact your admin.',
          );
        }

        final profileData = profileDoc.data() ?? <String, dynamic>{};
        final identifier = trimmedCompanyIdentifier;
        final needsBackfill =
            (profileData['firestoreDatabaseId'] ?? '').toString().isEmpty ||
            (identifier != null &&
                identifier.isNotEmpty &&
                (profileData['companyId'] ?? '').toString().isEmpty);

        if (needsBackfill) {
          await profileDoc.reference.set({
            if (identifier != null && identifier.isNotEmpty)
              'companyId': identifier,
            'firestoreDatabaseId': resolvedDatabaseId,
          }, SetOptions(merge: true));

          AppLogger.info(
            'Backfilled tenant fields for uid=${result.user!.uid} in database $resolvedDatabaseId',
            tag: 'AUTH',
          );
        }

        AppLogger.info(
          'Login completed for uid=${result.user!.uid} in database $resolvedDatabaseId',
          tag: 'AUTH',
        );

        return UserModel.fromMap({
          ...profileData,
          if (identifier != null && identifier.isNotEmpty)
            'companyId': profileData['companyId'] ?? identifier,
          'firestoreDatabaseId':
              profileData['firestoreDatabaseId'] ?? resolvedDatabaseId,
        }, result.user!.uid);
      }
      return null;
    } on FirebaseAuthException catch (e, st) {
      AppLogger.error(
        'Sign-in failed for email/password flow',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      throw Exception(ErrorMapper.mapAuthError(e.code));
    } on FirebaseException catch (e, st) {
      AppLogger.error(
        'Firestore failure during sign-in flow',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      if (e.code == 'permission-denied') {
        throw Exception(
          'Login failed because Firestore rules denied access in database '
          '${activeDatabaseId ?? _tenant.databaseId}. Deploy/update rules for this tenant DB.',
        );
      }
      throw Exception(
        ErrorMapper.mapFirestoreError(e.code, action: 'Loading user profile'),
      );
    } on Exception {
      rethrow;
    } catch (e, st) {
      AppLogger.error(
        'Unexpected sign-in error',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      throw Exception('Unexpected login error. Please try again.');
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<bool> hasFreshCachedSession({
    Duration refreshSkew = const Duration(minutes: 5),
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      final tokenResult = await user.getIdTokenResult(false);
      final expirationTime = tokenResult.expirationTime;
      if (expirationTime == null) {
        return false;
      }

      final safeExpiry = expirationTime.subtract(refreshSkew);
      final isFresh = DateTime.now().isBefore(safeExpiry);
      AppLogger.info(
        'Cached auth session freshness checked: $isFresh',
        tag: 'AUTH',
      );
      return isFresh;
    } on FirebaseAuthException catch (e, st) {
      AppLogger.warning(
        'Unable to inspect cached auth session freshness (${e.code})',
        tag: 'AUTH',
      );
      AppLogger.error(
        'Session freshness inspection failed',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      return false;
    } catch (e, st) {
      AppLogger.error(
        'Unexpected error while checking cached auth session freshness',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      return false;
    }
  }

  Future<bool> refreshSessionIfPossible() async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      await user.getIdToken(true);
      return true;
    } on FirebaseAuthException catch (e, st) {
      AppLogger.warning(
        'Token refresh failed during submission gate (${e.code})',
        tag: 'AUTH',
      );
      AppLogger.error(
        'Session refresh failed',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      return false;
    } catch (e, st) {
      AppLogger.error(
        'Unexpected error while refreshing auth session',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      return false;
    }
  }

  // Stream of user changes with role information
  Stream<UserModel?> get userStream {
    return _auth.authStateChanges().asyncMap((User? user) async {
      if (user == null) return null;

      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          return UserModel.fromMap(doc.data()!, user.uid);
        } else {
          AppLogger.warning(
            'Auth state changed but user profile is missing in tenant database.',
            tag: 'AUTH',
          );
          await _auth.signOut();
          return null;
        }
      } on FirebaseException catch (e, st) {
        AppLogger.error(
          'Failed to process auth state change user profile due to Firestore access '
          '(database=${_tenant.databaseId})',
          error: e,
          stackTrace: st,
          tag: 'AUTH',
        );
        return null;
      } catch (e, st) {
        AppLogger.error(
          'Failed to process auth state change user profile',
          error: e,
          stackTrace: st,
          tag: 'AUTH',
        );
        return null;
      }
    });
  }
}
