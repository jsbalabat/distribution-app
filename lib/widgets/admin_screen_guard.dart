import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../styles/app_styles.dart';

class AdminScreenGuard extends StatelessWidget {
  const AdminScreenGuard({super.key, required this.child, required this.title});

  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    if (userProvider.isLoading) {
      return const Scaffold(
        backgroundColor: AppStyles.scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!userProvider.isAdmin) {
      return Scaffold(
        backgroundColor: AppStyles.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(title, style: AppStyles.appBarTitleStyle),
          backgroundColor: AppStyles.adminPrimaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppStyles.spacingL),
            child: Container(
              decoration: AppStyles.cardDecoration,
              padding: const EdgeInsets.all(AppStyles.spacingL),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 40,
                    color: AppStyles.errorColor,
                  ),
                  SizedBox(height: AppStyles.spacingS),
                  Text(
                    'Access denied',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Administrator role is required to view this page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppStyles.textSecondaryColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return child;
  }
}
