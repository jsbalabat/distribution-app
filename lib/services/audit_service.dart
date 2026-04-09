import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_tenant.dart';
import '../utils/app_logger.dart';

class AuditService {
  final FirestoreTenant _tenant = FirestoreTenant.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  FirebaseFirestore get _firestore => _tenant.firestore;

  Future<void> logAction({
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? details,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('auditLogs').add({
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'details': details ?? <String, dynamic>{},
        'actorUid': user.uid,
        'actorEmail': user.email ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      AppLogger.error(
        'Failed to write audit log for action: $action',
        error: e,
        stackTrace: st,
        tag: 'AUDIT',
      );
    }
  }
}
