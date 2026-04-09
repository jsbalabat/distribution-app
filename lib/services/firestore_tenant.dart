import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firestore_tenant_storage.dart';

class FirestoreTenant {
  FirestoreTenant._();

  static final FirestoreTenant instance = FirestoreTenant._();
  static const String defaultDatabaseId = '(default)';

  final FirestoreTenantStorage _storage = FirestoreTenantStorage();

  String _databaseId = defaultDatabaseId;

  String get databaseId => _databaseId;

  FirebaseFirestore get firestore {
    if (_databaseId == defaultDatabaseId) {
      return FirebaseFirestore.instance;
    }

    return FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: _databaseId,
    );
  }

  void setDatabaseId(String? databaseId) {
    final normalized = databaseId?.trim();
    _databaseId = normalized == null || normalized.isEmpty
        ? defaultDatabaseId
        : normalized;
  }

  Future<void> loadFromStorage() async {
    final databaseId = await _storage.readDatabaseId();
    setDatabaseId(databaseId);
  }

  Future<void> saveDatabaseId(String? databaseId) async {
    setDatabaseId(databaseId);
    await _storage.writeDatabaseId(_databaseId);
  }

  Future<void> clearSavedDatabaseId() async {
    _databaseId = defaultDatabaseId;
    await _storage.clearDatabaseId();
  }
}
