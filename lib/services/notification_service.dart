import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/app_logger.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> notifyUser({
    required String recipientUid,
    required String title,
    required String body,
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? details,
  }) async {
    await _createNotification(
      recipientUid: recipientUid,
      targetRole: 'user',
      title: title,
      body: body,
      action: action,
      entityType: entityType,
      entityId: entityId,
      details: details,
    );
  }

  Future<void> notifyAdmins({
    required String title,
    required String body,
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? details,
  }) async {
    await _createNotification(
      targetRole: 'admin',
      title: title,
      body: body,
      action: action,
      entityType: entityType,
      entityId: entityId,
      details: details,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchNotifications({
    required String uid,
    required bool isAdmin,
    int limit = 100,
  }) async {
    final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seenIds = <String>{};

    Future<void> addQuery(Query<Map<String, dynamic>> query) async {
      final snapshot = await query.limit(limit).get();
      for (final doc in snapshot.docs) {
        if (seenIds.add(doc.id)) {
          results.add(doc);
        }
      }
    }

    await addQuery(
      _firestore
          .collection('notifications')
          .where('recipientUid', isEqualTo: uid),
    );

    if (isAdmin) {
      await addQuery(
        _firestore
            .collection('notifications')
            .where('targetRole', isEqualTo: 'admin'),
      );
    }

    results.sort((a, b) {
      final aTs = a.data()['createdAt'];
      final bTs = b.data()['createdAt'];
      final aMillis = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
      final bMillis = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
      return bMillis.compareTo(aMillis);
    });

    return results;
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      AppLogger.error(
        'Failed to mark notification as read',
        error: e,
        stackTrace: st,
        tag: 'NOTIFICATION',
      );
    }
  }

  Future<void> markAllAsRead({
    required String uid,
    required bool isAdmin,
  }) async {
    try {
      final docs = await fetchNotifications(uid: uid, isAdmin: isAdmin);
      final batch = _firestore.batch();

      for (final doc in docs) {
        if (doc.data()['isRead'] == true) continue;
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e, st) {
      AppLogger.error(
        'Failed to mark all notifications as read',
        error: e,
        stackTrace: st,
        tag: 'NOTIFICATION',
      );
    }
  }

  Future<void> _createNotification({
    String? recipientUid,
    String? targetRole,
    required String title,
    required String body,
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? details,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('notifications').add({
        'title': title,
        'body': body,
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'details': details ?? <String, dynamic>{},
        'recipientUid': recipientUid,
        'targetRole': targetRole,
        'actorUid': user.uid,
        'actorEmail': user.email ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'readAt': null,
      });
    } catch (e, st) {
      AppLogger.error(
        'Failed to create notification',
        error: e,
        stackTrace: st,
        tag: 'NOTIFICATION',
      );
    }
  }
}
