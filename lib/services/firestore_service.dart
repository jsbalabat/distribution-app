import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/item_model.dart';
import '../models/user_model.dart';
import 'audit_service.dart';
import 'firestore_tenant.dart';
import 'notification_service.dart';
import '../utils/app_logger.dart';
import '../utils/error_mapper.dart';
import '../utils/remark_evaluator.dart';

/// Outcome of writing a requisition: the new doc id plus the server-assigned SOR
/// number and the remarks computed at write time, so callers can use them for the
/// PDF/email without trusting any client-side value.
class SubmissionResult {
  final String requisitionId;
  final String sorNumber;
  final String? remark1;
  final String? remark2;
  // Email dispatch outcome reported by the submit callable ('sent', 'skipped',
  // 'failed', ...); null when unknown. The offline queue mirrors it as its
  // email substatus.
  final String? emailStatus;

  const SubmissionResult({
    required this.requisitionId,
    required this.sorNumber,
    this.remark1,
    this.remark2,
    this.emailStatus,
  });
}

/// Why the server refused a submission, mapped from the callable's
/// rejectionCategory so callers react without string-matching.
enum SubmissionRejectionCategory { inventory, validation, unknown }

/// Thrown when submitSalesRequisition returns accepted:false. Carries the
/// structured reasons so the form can show which items failed and the sync
/// worker can categorize the queue outcome.
class SubmissionRejectedException implements Exception {
  final SubmissionRejectionCategory category;
  final List<Map<String, dynamic>> reasons;
  final String message;

  const SubmissionRejectedException(this.category, this.reasons, this.message);

  @override
  String toString() => message;
}

/// A customer's current receivable position, used to derive credit remarks.
class AccountReceivableSnapshot {
  final double amountDue;
  final double over30Days;
  final double unsecuredFunds;

  const AccountReceivableSnapshot({
    required this.amountDue,
    required this.over30Days,
    required this.unsecuredFunds,
  });

  static const AccountReceivableSnapshot empty = AccountReceivableSnapshot(
    amountDue: 0,
    over30Days: 0,
    unsecuredFunds: 0,
  );
}

class FirestoreService {
  static const int defaultSubmissionLimit = 100;
  // Must match submitSalesRequisition's deployed region in functions/index.js.
  static const String _callableRegion = 'asia-southeast1';

  final _tenant = FirestoreTenant.instance;
  final _auth = FirebaseAuth.instance;
  final _auditService = AuditService();
  final _notificationService = NotificationService.instance;

  FirebaseFirestore get _firestore => _tenant.firestore;

  // Submit an SOR through the server-authoritative callable — the sole write
  // path: it allocates the SOR number, atomically decrements itemsAvailable,
  // writes the requisition, and renders and emails the PDF server-side. Throws
  // SubmissionRejectedException when the server refuses (stock / bad items).
  Future<SubmissionResult> submitSOR(Map<String, dynamic> formData) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not authenticated");

    try {
      // Remarks are still computed client-side this phase; they move into the
      // callable when approval routing goes server-side.
      final remarks = await _evaluateRemarks(formData);

      // Stable idempotency key: reuse the id a queued draft already carries,
      // otherwise mint a UUID v7 so retries and lost acks dedupe server-side.
      final clientGeneratedId = _resolveSubmissionId(formData);
      final correlationId = _resolveCorrelationId(formData, uid);

      final finalizedData = {
        ...formData,
        'userID': formData['userID'] ?? uid,
        'uid': formData['uid'] ?? uid,
        'remark1': remarks.remark1,
        'remark2': remarks.remark2,
        'totalAmount': formData['totalAmount'] ?? formData['amount'] ?? 0,
        'amount': formData['amount'] ?? formData['totalAmount'] ?? 0,
      };

      final response = await _invokeSubmitCallable(
        clientGeneratedId: clientGeneratedId,
        correlationId: correlationId,
        sorPayload: _toCallableSorPayload(finalizedData),
      );

      if (response['accepted'] != true) {
        throw _rejectionFromResponse(response);
      }

      final sorId = (response['sorId'] ?? clientGeneratedId).toString();
      // The number exists only on the server; there is no local value to fall
      // back to, so an absent one means the response contract broke.
      final serverSorNumber = (response['sorNumber'] ?? clientGeneratedId)
          .toString();

      // Audit + notifications remain client-side until the rules lockdown phase
      // moves them server-side.
      await _auditService.logAction(
        action: 'create',
        entityType: 'salesRequisition',
        entityId: sorId,
        details: {
          'sorNumber': serverSorNumber,
          'totalAmount': finalizedData['totalAmount'],
          'itemCount': (finalizedData['items'] as List<dynamic>? ?? []).length,
        },
      );

      final customerName = (finalizedData['customerName'] ?? 'your requisition')
          .toString();

      await _notificationService.notifyUser(
        recipientUid: uid,
        title: 'Submission received',
        body:
            'Your requisition $serverSorNumber for $customerName was submitted.',
        action: 'create',
        entityType: 'salesRequisition',
        entityId: sorId,
        details: {'sorNumber': serverSorNumber},
      );

      await _notificationService.notifyAdmins(
        title: 'New requisition submitted',
        body: '$customerName submitted requisition $serverSorNumber.',
        action: 'create',
        entityType: 'salesRequisition',
        entityId: sorId,
        details: {'sorNumber': serverSorNumber, 'submittedBy': uid},
      );

      return SubmissionResult(
        requisitionId: sorId,
        sorNumber: serverSorNumber,
        remark1: remarks.remark1,
        remark2: remarks.remark2,
        emailStatus: response['emailStatus']?.toString(),
      );
    } on SubmissionRejectedException {
      rethrow;
    } on FirebaseFunctionsException catch (e, st) {
      AppLogger.error(
        'submitSalesRequisition callable failed (${e.code})',
        error: e,
        stackTrace: st,
        tag: 'FIRESTORE',
      );
      throw Exception(
        ErrorMapper.mapFirestoreError(e.code, action: 'Submitting requisition'),
      );
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

  // Single generator instance; the uuid package's constructor is not const.
  static final Uuid _uuidGen = Uuid();

  String _resolveSubmissionId(Map<String, dynamic> formData) {
    final existing = formData['clientGeneratedId']?.toString().trim();
    if (existing != null && existing.isNotEmpty) return existing;
    // UUID v7 is time-ordered and the format the callable requires as its id.
    return _uuidGen.v7();
  }

  String _resolveCorrelationId(Map<String, dynamic> formData, String uid) {
    final existing = formData['correlationId']?.toString().trim();
    if (existing != null && existing.isNotEmpty) return existing;
    return 'corr-$uid-${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<Map<String, dynamic>> _invokeSubmitCallable({
    required String clientGeneratedId,
    required String correlationId,
    required Map<String, dynamic> sorPayload,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: _callableRegion,
    ).httpsCallable('submitSalesRequisition');

    final result = await callable.call(<String, dynamic>{
      'clientGeneratedId': clientGeneratedId,
      'correlationId': correlationId,
      'actorDatabaseId': _tenant.databaseId,
      'sorPayload': sorPayload,
    });

    return Map<String, dynamic>.from(result.data as Map);
  }

  // Flattens a requisition map for the JSON callable boundary: the server
  // stamps submission-time fields, so they're dropped here, and user-chosen
  // dates travel as epoch millis since Timestamp/DateTime can't be serialized.
  Map<String, dynamic> _toCallableSorPayload(Map<String, dynamic> data) {
    final payload = Map<String, dynamic>.from(data);
    for (final key in const [
      'timeStamp',
      'timestamp',
      'requestDate',
      'createdAt',
      'updatedAt',
      'queuedAt',
    ]) {
      payload.remove(key);
    }
    payload['dispatchDate'] = _toEpochMillis(data['dispatchDate']);
    payload['invoiceDate'] = _toEpochMillis(data['invoiceDate']);
    return payload;
  }

  int? _toEpochMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    if (value is String) return DateTime.tryParse(value)?.millisecondsSinceEpoch;
    return null;
  }

  SubmissionRejectedException _rejectionFromResponse(
    Map<String, dynamic> response,
  ) {
    final categoryRaw = (response['rejectionCategory'] ?? '')
        .toString()
        .toLowerCase();
    final category = categoryRaw.contains('inventory')
        ? SubmissionRejectionCategory.inventory
        : categoryRaw.contains('validation')
        ? SubmissionRejectionCategory.validation
        : SubmissionRejectionCategory.unknown;

    final rawReasons = response['rejectionReasons'];
    final reasons = <Map<String, dynamic>>[];
    if (rawReasons is List) {
      for (final reason in rawReasons) {
        if (reason is Map) reasons.add(Map<String, dynamic>.from(reason));
      }
    }

    return SubmissionRejectedException(
      category,
      reasons,
      _rejectionMessage(category, reasons),
    );
  }

  String _rejectionMessage(
    SubmissionRejectionCategory category,
    List<Map<String, dynamic>> reasons,
  ) {
    final detail = reasons
        .map((r) => (r['message'] ?? '').toString())
        .where((m) => m.isNotEmpty)
        .join('\n');
    if (detail.isNotEmpty) return detail;
    switch (category) {
      case SubmissionRejectionCategory.inventory:
        return 'Some items no longer have enough stock. Please review and try again.';
      case SubmissionRejectionCategory.validation:
        return 'The requisition could not be validated. Please review the items.';
      case SubmissionRejectionCategory.unknown:
        return 'The submission was rejected. Please try again.';
    }
  }

  /// Reads a customer's receivable position. An absent record is a legitimate
  /// "no balance" (empty); a read failure propagates so we never silently
  /// under-flag credit on a transient error.
  Future<AccountReceivableSnapshot> fetchAccountReceivable(
    String accountNumber,
  ) async {
    if (accountNumber.isEmpty) {
      return AccountReceivableSnapshot.empty;
    }

    final snapshot = await _firestore
        .collection('accountReceivable')
        .where('accountNumber', isEqualTo: accountNumber)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return AccountReceivableSnapshot.empty;
    }

    final data = snapshot.docs.first.data();
    return AccountReceivableSnapshot(
      amountDue: (data['amountDue'] ?? 0).toDouble(),
      over30Days: (data['overThirtyDays'] ?? 0).toDouble(),
      unsecuredFunds: (data['unsecured'] ?? 0).toDouble(),
    );
  }

  Future<RemarkEvaluation> _evaluateRemarks(
    Map<String, dynamic> formData,
  ) async {
    final accountNumber = (formData['accountNumber'] ?? '').toString();
    final creditLimit = (formData['creditLimit'] as num?)?.toDouble() ?? 0;
    final orderTotal =
        ((formData['totalAmount'] ?? formData['amount'] ?? 0) as num).toDouble();

    final receivable = await fetchAccountReceivable(accountNumber);
    return RemarkEvaluator.evaluate(
      creditLimit: creditLimit,
      amountDue: receivable.amountDue,
      over30Days: receivable.over30Days,
      unsecuredFunds: receivable.unsecuredFunds,
      orderTotal: orderTotal,
    );
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
