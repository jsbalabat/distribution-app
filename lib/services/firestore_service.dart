import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/item_model.dart';
import '../models/user_model.dart';
import '../utils/app_logger.dart';
import '../utils/error_mapper.dart';

class FirestoreService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Save a new SOR form
  Future<void> submitSOR(Map<String, dynamic> formData) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    try {
      await _firestore.collection('salesRequisitions').add({...formData});
    } on FirebaseException catch (e, st) {
      AppLogger.error(
        'Failed to submit sales requisition',
        error: e,
        stackTrace: st,
        tag: 'FIRESTORE',
      );
      throw Exception(
        ErrorMapper.mapFirestoreError(e.code, action: 'Submitting requisition'),
      );
    } catch (e, st) {
      AppLogger.error(
        'Unexpected error while submitting sales requisition',
        error: e,
        stackTrace: st,
        tag: 'FIRESTORE',
      );
      throw Exception('Unable to submit requisition right now.');
    }
  }

  Future<Map<String, dynamic>?> fetchItemPrice(String itemCode) async {
    try {
      final snapshot = await _firestore
          .collection('itemMaster')
          .where('itemCode', isEqualTo: itemCode)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data();
      }
      return null;
    } on FirebaseException catch (e, st) {
      AppLogger.error(
        'Failed to fetch item price for code: $itemCode',
        error: e,
        stackTrace: st,
        tag: 'FIRESTORE',
      );
      return null;
    } catch (e, st) {
      AppLogger.error(
        'Unexpected error while fetching item price for code: $itemCode',
        error: e,
        stackTrace: st,
        tag: 'FIRESTORE',
      );
      return null;
    }
  }

  Future<List<Item>> fetchItems() async {
    final snapshot = await _firestore.collection('itemsAvailable').get();
    return snapshot.docs
        .map((doc) => Item.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<void> updateItemStock(String id, int quantity) async {
    try {
      await _firestore.collection('itemsAvailable').doc(id).update({
        'quantity': quantity,
      });
    } on FirebaseException catch (e, st) {
      AppLogger.error(
        'Failed to update item stock for item: $id',
        error: e,
        stackTrace: st,
        tag: 'FIRESTORE',
      );
      throw Exception(
        ErrorMapper.mapFirestoreError(e.code, action: 'Updating item stock'),
      );
    } catch (e, st) {
      AppLogger.error(
        'Unexpected error while updating item stock for item: $id',
        error: e,
        stackTrace: st,
        tag: 'FIRESTORE',
      );
      throw Exception('Unable to update stock right now.');
    }
  }

  // Stream user’s submissions
  Stream<QuerySnapshot> getUserSubmissions() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    return _firestore
        .collection('salesRequisitions')
        .where('userID', isEqualTo: uid)
        .orderBy('timeStamp', descending: true)
        .snapshots();
  }

  // Optional: Fetch customer or item lists
  Stream<QuerySnapshot> getCustomers() =>
      _firestore.collection('customers').snapshots();

  Stream<QuerySnapshot> getItems() =>
      _firestore.collection('items').snapshots();

  // Get all users (stream)
  Stream<List<UserModel>> getUsersStream() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return UserModel.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  // Update user role
  Future<void> updateUserRole(String uid, String newRole) async {
    await _firestore.collection('users').doc(uid).update({'role': newRole});
  }

  // Admin: Get all submissions for reports
  Stream<QuerySnapshot> getAllSubmissionsStream() {
    return _firestore
        .collection('salesRequisitions')
        .orderBy('timeStamp', descending: true)
        .snapshots();
  }
}
