import 'package:flutter/material.dart';
// import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/form_screen.dart';
import 'screens/review_screen.dart';
import 'screens/confirmation_screen.dart';
import 'screens/submissions_screen.dart';
import 'screens/home_screen.dart';
import 'screens/transaction_detail_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'providers/user_provider.dart';
import 'package:provider/provider.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sales Field App',
      theme: ThemeData(primarySwatch: Colors.teal),
      initialRoute: '/',
      routes: {
        '/': (context) {
          final userProvider = Provider.of<UserProvider>(context);
          if (userProvider.isLoading) {
            return const SplashScreen();
          }
          if (!userProvider.isLoggedIn) {
            return const AuthScreen();
          }
          if (userProvider.isAdmin) {
            return const AdminDashboardScreen();
          } else {
            return const HomeScreen();
          }
        },
        '/home': (context) => const HomeScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/form': (context) => const FormScreen(),
        '/review': (context) => const ReviewScreen(),
        '/confirmation': (context) => const ConfirmationScreen(),
        '/submissions': (context) => const SubmissionsScreen(),
        '/transaction_detail': (context) => const TransactionDetailScreen(),
      },
    );
  }
}
