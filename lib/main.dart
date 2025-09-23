import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'utils/app_styles.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb) {
      // Web-specific Firebase initialization
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyBnKzY3JuVx29DlVNVP8dASNITV93ag1e4",
          authDomain: "sales-field-app-f31a2.firebaseapp.com",
          projectId: "sales-field-app-f31a2",
          storageBucket: "sales-field-app-f31a2.firebasestorage.app",
          messagingSenderId: "856355013052",
          appId: "1:856355013052:web:dbc0f63e975cf50f36abb9",
        ),
      );
    } else {
      // Mobile platform initialization
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    // print('Firebase initialization error: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserProvider(),
      child: MaterialApp(
        title: 'Sales App',
        theme: ThemeData(
          primaryColor: AppStyles.primaryColor,
          scaffoldBackgroundColor: AppStyles.backgroundColor,
          appBarTheme: const AppBarTheme(
            backgroundColor: AppStyles.primaryColor,
          ),
        ),
        home: Consumer<UserProvider>(
          builder: (context, userProvider, _) {
            if (userProvider.isLoading) {
              return const SplashScreen();
            }

            if (!userProvider.isLoggedIn) {
              return const AuthScreen();
            }

            // Route to admin dashboard or regular home screen
            if (userProvider.isAdmin) {
              return const AdminDashboardScreen();
            } else {
              return const HomeScreen();
            }
          },
        ),
      ),
    );
  }
}
