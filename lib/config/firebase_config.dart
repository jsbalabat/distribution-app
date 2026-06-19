// lib/config/firebase_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/app_logger.dart';

/// Firebase configuration loaded from environment variables
class FirebaseConfig {
  static late final String apiKey;
  static late final String authDomain;
  static late final String projectId;
  static late final String storageBucket;
  static late final String messagingSenderId;
  static late final String appId;
  static late final String environment;

  static bool _initialized = false;

  /// Initialize Firebase configuration from .env file
  /// Call this before Firebase.initializeApp()
  static Future<void> initialize() async {
    // Idempotent: the write-once fields below can only be set once, so a repeat
    // call (e.g. a hot restart that kept static state) must no-op.
    if (_initialized) return;

    try {
      await dotenv.load(fileName: ".env");

      final loadedApiKey = dotenv.env['FIREBASE_API_KEY'] ?? '';
      final loadedProjectId = dotenv.env['FIREBASE_PROJECT_ID'] ?? '';

      // Validate before assigning the write-once fields so a failed load stays retryable.
      if (loadedApiKey.isEmpty || loadedProjectId.isEmpty) {
        throw Exception(
          'Missing required Firebase configuration. '
          'Please ensure .env file is properly configured.',
        );
      }

      apiKey = loadedApiKey;
      authDomain = dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? '';
      projectId = loadedProjectId;
      storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '';
      messagingSenderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '';
      appId = dotenv.env['FIREBASE_APP_ID'] ?? '';
      environment = dotenv.env['ENVIRONMENT'] ?? 'development';

      _initialized = true;
    } catch (e, st) {
      AppLogger.error(
        'Failed to initialize FirebaseConfig from .env',
        error: e,
        stackTrace: st,
        tag: 'CONFIG',
      );
      throw Exception('Failed to load Firebase configuration: $e');
    }
  }

  /// Get Firebase options for web initialization
  static FirebaseOptions getWebOptions() {
    return FirebaseOptions(
      apiKey: apiKey,
      authDomain: authDomain,
      projectId: projectId,
      storageBucket: storageBucket,
      messagingSenderId: messagingSenderId,
      appId: appId,
    );
  }

  /// Check if app is in development mode
  static bool isDevelopment() => environment == 'development';

  /// Check if app is in staging mode
  static bool isStaging() => environment == 'staging';

  /// Check if app is in production mode
  static bool isProduction() => environment == 'production';
}
