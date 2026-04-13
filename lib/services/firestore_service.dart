import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/item_model.dart';
import '../models/user_model.dart';
import 'audit_service.dart';
import 'firestore_tenant.dart';
import 'notification_service.dart';
import '../utils/app_logger.dart';
import '../utils/error_mapper.dart';

class FirestoreService {
  static const int defaultSubmissionLimit = 100;

  final _tenant = FirestoreTenant.instance;
  final _auth = FirebaseAuth.instance;
  final _auditService = AuditService();
  final _notificationService = NotificationService.instance;

  FirebaseFirestore get _firestore => _tenant.firestore;

  // Save a new SOR form
  Future<String> submitSOR(Map<String, dynamic> formData) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    final now = Timestamp.now();
    final normalized = {
      ...formData,
      'userID': formData['userID'] ?? uid,
      'uid': formData['uid'] ?? uid,
      'sorNumber': formData['sorNumber'] ?? formData['sorNo'],
      'sorNo': formData['sorNo'] ?? formData['sorNumber'],
      'totalAmount': formData['totalAmount'] ?? formData['amount'] ?? 0,
      'amount': formData['amount'] ?? formData['totalAmount'] ?? 0,
      'timeStamp': formData['timeStamp'] ?? formData['timestamp'] ?? now,
      'timestamp': formData['timestamp'] ?? formData['timeStamp'] ?? now,
      'createdAt': formData['createdAt'] ?? now,
    };

    try {
      final docRef = await _firestore
          .collection('salesRequisitions')
          .add(normalized);
      await _auditService.logAction(
        action: 'create',
        entityType: 'salesRequisition',
        entityId: docRef.id,
        details: {
          'sorNumber': normalized['sorNumber'],
          'totalAmount': normalized['totalAmount'],
          'itemCount': (normalized['items'] as List<dynamic>? ?? []).length,
        },
      );

      final sorNumber = (normalized['sorNumber'] ?? docRef.id).toString();
      final customerName = (normalized['customerName'] ?? 'your requisition')
          .toString();

      await _notificationService.notifyUser(
        recipientUid: uid,
        title: 'Submission received',
        body: 'Your requisition $sorNumber for $customerName was submitted.',
        action: 'create',
        entityType: 'salesRequisition',
        entityId: docRef.id,
        details: {'sorNumber': sorNumber},
      );

      await _notificationService.notifyAdmins(
        title: 'New requisition submitted',
        body: '$customerName submitted requisition $sorNumber.',
        action: 'create',
        entityType: 'salesRequisition',
        entityId: docRef.id,
        details: {'sorNumber': sorNumber, 'submittedBy': uid},
      );

      return docRef.id;
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
      final current = await _firestore
          .collection('itemsAvailable')
          .doc(id)
          .get();
      final previousQuantity =
          (current.data()?['quantity'] ?? current.data()?['stock'] ?? 0) as num;

      await _firestore.collection('itemsAvailable').doc(id).update({
        'quantity': quantity,
      });

      await _auditService.logAction(
        action: 'update',
        entityType: 'inventory',
        entityId: id,
        details: {
          'previousQuantity': previousQuantity.toInt(),
          'newQuantity': quantity,
        },
      );
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
  Stream<QuerySnapshot> getUserSubmissions({
    int limit = defaultSubmissionLimit,
  }) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    return _firestore
        .collection('salesRequisitions')
        .where('userID', isEqualTo: uid)
        .limit(limit)
        .snapshots();
  }

  // Cursor-based pagination for user submissions
  Future<QuerySnapshot<Map<String, dynamic>>> fetchUserSubmissionsPage({
    int limit = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    Query<Map<String, dynamic>> query = _firestore
        .collection('salesRequisitions')
        .where('userID', isEqualTo: uid)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    return query.get();
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
    final userDoc = await _firestore.collection('users').doc(uid).get();
    final previousRole = (userDoc.data()?['role'] ?? 'unknown').toString();
    final userName = (userDoc.data()?['name'] ?? 'your account').toString();

    await _firestore.collection('users').doc(uid).update({'role': newRole});

    await _auditService.logAction(
      action: 'updateRole',
      entityType: 'user',
      entityId: uid,
      details: {'previousRole': previousRole, 'newRole': newRole},
    );

    await _notificationService.notifyUser(
      recipientUid: uid,
      title: 'Role updated',
      body:
          'Your account role for $userName changed from $previousRole to $newRole.',
      action: 'updateRole',
      entityType: 'user',
      entityId: uid,
      details: {'previousRole': previousRole, 'newRole': newRole},
    );
  }

  Future<void> deleteSalesRequisition(String docId) async {
    final docRef = _firestore.collection('salesRequisitions').doc(docId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      throw Exception('Sales requisition not found.');
    }

    await docRef.update({
      'isDeleted': true,
      'deletedAt': Timestamp.now(),
      'deletedBy': _auth.currentUser?.uid,
      'deletedByEmail': _auth.currentUser?.email,
      'updatedAt': Timestamp.now(),
    });

    await _auditService.logAction(
      action: 'delete',
      entityType: 'salesRequisition',
      entityId: docId,
      details: {'softDelete': true},
    );

    final data = snapshot.data() ?? <String, dynamic>{};
    final ownerUid = (data['userID'] ?? data['uid'] ?? '').toString();
    final sorNumber = (data['sorNumber'] ?? data['sorNo'] ?? docId).toString();

    if (ownerUid.isNotEmpty) {
      await _notificationService.notifyUser(
        recipientUid: ownerUid,
        title: 'Requisition archived',
        body: 'Your requisition $sorNumber was archived.',
        action: 'delete',
        entityType: 'salesRequisition',
        entityId: docId,
        details: {'softDelete': true},
      );
    }
  }

  Future<void> updateSalesRequisition(
    String docId,
    Map<String, dynamic> updates,
  ) async {
    final docRef = _firestore.collection('salesRequisitions').doc(docId);
    final snapshot = await docRef.get();
    final data = snapshot.data() ?? <String, dynamic>{};
    final ownerUid = (data['userID'] ?? data['uid'] ?? '').toString();
    final sorNumber = (data['sorNumber'] ?? data['sorNo'] ?? docId).toString();

    await docRef.update(updates);

    await _auditService.logAction(
      action: 'update',
      entityType: 'salesRequisition',
      entityId: docId,
      details: {'updatedFields': updates.keys.toList()},
    );

    if (ownerUid.isNotEmpty) {
      await _notificationService.notifyUser(
        recipientUid: ownerUid,
        title: 'Requisition updated',
        body: 'Your requisition $sorNumber was updated.',
        action: 'update',
        entityType: 'salesRequisition',
        entityId: docId,
        details: {'updatedFields': updates.keys.toList()},
      );
    }
  }

  // Admin: Get all submissions for reports
  Stream<QuerySnapshot> getAllSubmissionsStream({int? limit}) {
    Query query = _firestore
        .collection('salesRequisitions')
        .orderBy('timeStamp', descending: true);

    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }

    return query.snapshots();
  }
}
