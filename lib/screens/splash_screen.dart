// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import '../styles/app_styles.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo or icon
            Icon(Icons.shopping_cart, size: 80, color: AppStyles.primaryColor),
            const SizedBox(height: 24),

            // App name
            const Text(
              'Sales App',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppStyles.textColor,
              ),
            ),
            const SizedBox(height: 48),

            // Loading indicator
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppStyles.primaryColor),
            ),
            const SizedBox(height: 24),

            // Loading text
            const Text(
              'Loading...',
              style: TextStyle(
                fontSize: 16,
                color: AppStyles.textSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
