import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class AppLogger {
  static void info(String message, {String tag = 'APP'}) {
    developer.log(message, name: tag, level: 800);

    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  static void warning(String message, {String tag = 'APP'}) {
    developer.log(message, name: tag, level: 900);

    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String tag = 'APP',
  }) {
    developer.log(
      message,
      name: tag,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );

    if (kDebugMode) {
      debugPrint('[$tag] $message');
      if (error != null) {
        debugPrint('[$tag] Error: $error');
      }
    }
  }
}
