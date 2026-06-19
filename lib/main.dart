import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'app.dart';
import 'config/firebase_config.dart';
import 'screens/startup_error_screen.dart';
import 'utils/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StartupGate());
}

/// Holds back the real app until Firebase has initialized. `UserProvider` and the
/// services it builds grab `FirebaseAuth`/`Firestore` instances eagerly, so creating
/// them before init finishes throws `[core/no-app]` on first build; gating here means
/// that only ever happens after a successful init.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<void> _bootstrap = _initializeFirebase();

  Future<void> _initializeFirebase() async {
    // A genuine config failure here propagates to the retry screen on its own.
    await FirebaseConfig.initialize();

    // A Firebase app already present needs no re-init; re-initializing a live app
    // triggers a FlutterFire hot-restart crash, so skip when one exists.
    if (Firebase.apps.isNotEmpty) return;

    try {
      if (kIsWeb) {
        await Firebase.initializeApp(options: FirebaseConfig.getWebOptions());
      } else {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (e, st) {
      // The [DEFAULT] app already exists and is usable in these known cases:
      //  - duplicate-app: Android's FirebaseInitProvider created it before Dart ran
      //  - a hot restart that threw inside the Firestore plugin's re-init hook
      // Treat them as success; surface only a genuine failure to the retry screen.
      final appAlreadyExists =
          (e is FirebaseException && e.code == 'duplicate-app') ||
          Firebase.apps.isNotEmpty;
      if (appAlreadyExists) return;
      AppLogger.error(
        'Firebase initialization failed',
        error: e,
        stackTrace: st,
        tag: 'STARTUP',
      );
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _bootstrap = _initializeFirebase();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: StartupErrorScreen(onRetry: _retry),
          );
        }

        // Init succeeded — only now is it safe to build Firebase-backed providers.
        return ChangeNotifierProvider(
          create: (_) => UserProvider(),
          child: const MyApp(),
        );
      },
    );
  }
}
