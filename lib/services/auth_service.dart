// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user with role
  Future<UserModel?> getCurrentUser() async {
    final User? user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!, user.uid);
      } else {
        // Create a default user document if it doesn't exist
        final defaultUser = UserModel(
          uid: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? '',
          role: 'user', // Default role
        );

        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(defaultUser.toMap());
        return defaultUser;
      }
    } catch (e) {
      // print('Error getting user data: $e');
      return null;
    }
  }

  // Sign in with email and password
  Future<UserModel?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        return await getCurrentUser();
      }
      return null;
    } catch (e) {
      // print('Error signing in: $e');
      rethrow;
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
          // Create default user document
          final defaultUser = UserModel(
            uid: user.uid,
            email: user.email ?? '',
            name: user.displayName ?? '',
            role: 'user',
          );

          await _firestore
              .collection('users')
              .doc(user.uid)
              .set(defaultUser.toMap());
          return defaultUser;
        }
      } catch (e) {
        // print('Error in user stream: $e');
        return null;
      }
    });
  }
}
