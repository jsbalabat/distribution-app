import 'package:web/web.dart' as web;

class FirestoreTenantStorage {
  static const String _storageKey = 'selected_firestore_database_id';

  Future<String?> readDatabaseId() async {
    final value = web.window.localStorage.getItem(_storageKey)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> writeDatabaseId(String? databaseId) async {
    final value = databaseId?.trim() ?? '';
    if (value.isEmpty) {
      web.window.localStorage.removeItem(_storageKey);
      return;
    }

    web.window.localStorage.setItem(_storageKey, value);
  }

  Future<void> clearDatabaseId() async {
    web.window.localStorage.removeItem(_storageKey);
  }
}
