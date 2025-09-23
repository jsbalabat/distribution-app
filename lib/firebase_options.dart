// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    // Web options
    return const FirebaseOptions(
      apiKey: 'AIzaSyBnKzY3JuVx29DlVNVP8dASNITV93ag1e4',
      appId: '1:856355013052:web:683de41e2111336f36abb9',
      messagingSenderId: '856355013052',
      projectId: 'sales-field-app-f31a2',
      authDomain: 'sales-field-app-f31a2.firebaseapp.com',
      storageBucket: 'sales-field-app-f31a2.firebasestorage.app',
      measurementId: 'G-L50M452XP5', // Optional
    );
  }
}
