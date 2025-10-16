import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'providers/user_provider.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb) {
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
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    // Handle error if needed
  }

  runApp(
    ChangeNotifierProvider(create: (_) => UserProvider(), child: const MyApp()),
  );
}
