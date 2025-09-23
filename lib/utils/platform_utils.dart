// lib/utils/platform_utils.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

class PlatformUtils {
  static Future<String> getApplicationDocumentsPath() async {
    if (kIsWeb) {
      // For web, return a default path or use browser storage
      return '/web_documents';
    } else {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    }
  }

  static Future<String> getTemporaryPath() async {
    if (kIsWeb) {
      return '/web_temp';
    } else {
      final directory = await getTemporaryDirectory();
      return directory.path;
    }
  }

  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isWeb => kIsWeb;
}
