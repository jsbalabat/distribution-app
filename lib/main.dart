import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'app.dart';
import 'config/firebase_config.dart';
import 'utils/app_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize configuration from .env file
    await FirebaseConfig.initialize();

    if (kIsWeb) {
      // Use FirebaseConfig for web
      await Firebase.initializeApp(options: FirebaseConfig.getWebOptions());
    } else {
      // Use platform-specific configuration for mobile
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e, st) {
    AppLogger.error(
      'Firebase initialization failed',
      error: e,
      stackTrace: st,
      tag: 'STARTUP',
    );
  }

  runApp(
    ChangeNotifierProvider(create: (_) => UserProvider(), child: const MyApp()),
  );
}
