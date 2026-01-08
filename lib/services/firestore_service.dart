import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/item_model.dart';

class FirestoreService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Save a new SOR form
  Future<void> submitSOR(Map<String, dynamic> formData) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    await _firestore.collection('salesRequisitions').add({...formData});
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
    } catch (e) {
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
    await _firestore.collection('itemsAvailable').doc(id).update({
      'quantity': quantity,
    });
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
}
