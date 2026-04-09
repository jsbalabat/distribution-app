import 'dart:io';

import 'package:path_provider/path_provider.dart';

class FirestoreTenantStorage {
  static const String _fileName = 'selected_firestore_database_id.txt';

  Future<File> _getStorageFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<String?> readDatabaseId() async {
    try {
      final file = await _getStorageFile();
      if (!await file.exists()) {
        return null;
      }

      final contents = await file.readAsString();
      final value = contents.trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDatabaseId(String? databaseId) async {
    try {
      final file = await _getStorageFile();
      final value = databaseId?.trim() ?? '';
      await file.writeAsString(value);
    } catch (_) {}
  }

  Future<void> clearDatabaseId() async {
    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
