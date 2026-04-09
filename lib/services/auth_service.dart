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

  Future<String> _resolveDatabaseId({
    String? companyIdentifier,
    String? databaseId,
  }) async {
    final explicitDatabaseId = databaseId?.trim();
    if (explicitDatabaseId != null && explicitDatabaseId.isNotEmpty) {
      return explicitDatabaseId;
    }

    final identifier = companyIdentifier?.trim().toLowerCase() ?? '';
    if (identifier.isEmpty) {
      throw Exception('Please enter your company identifier.');
    }

    final directoryDoc = await FirebaseFirestore.instance
        .collection('companyTenants')
        .doc(identifier)
        .get();

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
    try {
      final resolvedDatabaseId = await _resolveDatabaseId(
        companyIdentifier: companyIdentifier,
        databaseId: databaseId,
      );
      await _tenant.saveDatabaseId(resolvedDatabaseId);

      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        final profileDoc = await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .get();

        if (!profileDoc.exists) {
          await _auth.signOut();
          throw Exception(
            'Your account is not assigned to this company. Contact your admin.',
          );
        }

        final profileData = profileDoc.data() ?? <String, dynamic>{};
        final identifier = companyIdentifier?.trim().toLowerCase();
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
        }

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
    } catch (e, st) {
      AppLogger.error(
        'Unexpected sign-in error',
        error: e,
        stackTrace: st,
        tag: 'AUTH',
      );
      throw Exception('Unable to sign in right now. Please try again.');
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
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
