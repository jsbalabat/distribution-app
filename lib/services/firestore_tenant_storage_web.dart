// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

class FirestoreTenantStorage {
  static const String _storageKey = 'selected_firestore_database_id';

  Future<String?> readDatabaseId() async {
    final value = html.window.localStorage[_storageKey]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> writeDatabaseId(String? databaseId) async {
    final value = databaseId?.trim() ?? '';
    if (value.isEmpty) {
      html.window.localStorage.remove(_storageKey);
      return;
    }

    html.window.localStorage[_storageKey] = value;
  }

  Future<void> clearDatabaseId() async {
    html.window.localStorage.remove(_storageKey);
  }
}
