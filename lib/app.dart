import 'package:flutter/material.dart';
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
import 'styles/app_styles.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sales Field App',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppStyles.primaryColor,
          brightness: Brightness.light,
          primary: AppStyles.primaryColor,
          secondary: AppStyles.secondaryColor,
          surface: AppStyles.cardColor,
          background: AppStyles.scaffoldBackgroundColor,
        ),
        scaffoldBackgroundColor: AppStyles.scaffoldBackgroundColor,
        appBarTheme: AppBarTheme(
          backgroundColor: AppStyles.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: AppStyles.appBarTitleStyle.copyWith(
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppStyles.cardColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppStyles.primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppStyles.primaryColor,
            side: const BorderSide(color: AppStyles.primaryColor, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppStyles.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
            borderSide: const BorderSide(
              color: AppStyles.primaryColor,
              width: 2.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.grey.shade300,
          thickness: 1,
          space: 1,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppStyles.textColor,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppStyles.textColor,
            letterSpacing: -0.5,
          ),
          displaySmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppStyles.textColor,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppStyles.textColor,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppStyles.textColor,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppStyles.textColor,
          ),
          bodyLarge: TextStyle(fontSize: 16, color: AppStyles.textColor),
          bodyMedium: TextStyle(fontSize: 14, color: AppStyles.textColor),
          bodySmall: TextStyle(fontSize: 12, color: AppStyles.subtitleColor),
        ),
      ),
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
