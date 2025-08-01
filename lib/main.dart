import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart'; // we’ll make this next

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}