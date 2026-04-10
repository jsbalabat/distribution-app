// lib/screens/admin_dashboard_screen.dart
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../styles/app_styles.dart';
import '../utils/app_logger.dart';
import '../utils/excel_file_picker.dart';
import '../widgets/admin_desktop_shell.dart';
import 'audit_logs_screen.dart';
import 'manage_users_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'view_reports_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isImportingCustomers = false;

  void _navigateDesktop(AdminShellSection section) {
    Widget? destination;
    switch (section) {
      case AdminShellSection.dashboard:
        return;
      case AdminShellSection.users:
        destination = const ManageUsersScreen();
      case AdminShellSection.reports:
        destination = const ViewReportsScreen();
      case AdminShellSection.settings:
        destination = const SettingsScreen();
      case AdminShellSection.auditLogs:
        destination = const AuditLogsScreen();
      case AdminShellSection.notifications:
        destination = const NotificationsScreen();
    }

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination!));
  }

  Future<void> _handleUploadCustomers(BuildContext context) async {
    if (_isImportingCustomers) return;

    setState(() {
      _isImportingCustomers = true;
    });

    try {
      final pickedFile = await pickExcelFile();
      if (pickedFile == null) return;

      final bytes = pickedFile.bytes;
      if (bytes.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected file could not be read.'),
            backgroundColor: AppStyles.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'importDataFromExcelDirect',
      );
      await callable.call(<String, dynamic>{
        'fileName': pickedFile.name,
        'fileBase64': base64Encode(bytes),
      });
    } catch (error) {
      AppLogger.error(
        '[IMPORT][UI] Upload failed via callable importDataFromExcelDirect',
        error: error,
        tag: 'IMPORT',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to trigger import: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImportingCustomers = false;
        });
      }
    }
  }

  Future<void> _runDestructiveCleanup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
          ),
          title: const Text('Confirm destructive cleanup'),
          content: const Text(
            'This will permanently delete customers, inventory, requisitions, import requests, and notifications. Type DELETE in the prompt sent to the function and press Run only if you are certain.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyles.errorColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Run cleanup'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Running destructive cleanup...'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'runDestructiveCleanup',
      );
      final result = await callable.call(<String, dynamic>{
        'confirmText': 'DELETE',
        'reason': 'Triggered from admin dashboard',
      });

      if (!context.mounted) return;
      final data = Map<String, dynamic>.from(result.data as Map);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cleanup completed. Deleted ${data['totalDeleted'] ?? 0} documents.',
          ),
          backgroundColor: AppStyles.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cleanup failed: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showLogoutConfirmation(
    BuildContext context,
    UserProvider userProvider,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout, color: AppStyles.errorColor),
              SizedBox(width: 12),
              Text('Confirm Logout'),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppStyles.textSecondaryColor),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                userProvider.signOut();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyles.errorColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final userName = userProvider.currentUser?.name ?? 'Admin';
    final isDesktop = MediaQuery.of(context).size.width >= 1100;

    final mobileBody = ListView(
      padding: const EdgeInsets.all(AppStyles.spacingM),
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppStyles.adminPrimaryColor, AppStyles.primaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
          ),
          padding: const EdgeInsets.all(AppStyles.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back,',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                userProvider.currentUser?.email ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppStyles.spacingL),
        _buildQuickActionsHeader(),
        const SizedBox(height: AppStyles.spacingM),
        _buildActionCard(
          label: 'Manage Users',
          subtitle: 'Create, edit, disable, and delete users',
          icon: Icons.people_outline,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ManageUsersScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: AppStyles.spacingS),
        _buildActionCard(
          label: 'View Reports',
          subtitle: 'Analytics and insights',
          icon: Icons.bar_chart_rounded,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ViewReportsScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: AppStyles.spacingS),
        _buildActionCard(
          label: 'Upload Customers',
          subtitle: _isImportingCustomers
              ? 'Import currently running...'
              : 'Upload and import Excel workbook',
          icon: Icons.upload_file_outlined,
          isBusy: _isImportingCustomers,
          onTap: () => _handleUploadCustomers(context),
        ),
        const SizedBox(height: AppStyles.spacingS),
        _buildActionCard(
          label: 'Settings',
          subtitle: 'System configuration',
          icon: Icons.settings_outlined,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            );
          },
        ),
        const SizedBox(height: AppStyles.spacingS),
        _buildActionCard(
          label: 'Audit Logs',
          subtitle: 'View tracked admin and data actions',
          icon: Icons.history_edu_outlined,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AuditLogsScreen()),
            );
          },
        ),
        const SizedBox(height: AppStyles.spacingS),
        _buildActionCard(
          label: 'Destructive Cleanup',
          subtitle: 'Permanently remove live data collections',
          icon: Icons.delete_forever_outlined,
          accentColor: AppStyles.errorColor,
          onTap: () => _runDestructiveCleanup(context),
        ),
      ],
    );

    if (isDesktop) {
      return AdminDesktopShell(
        title: 'Admin Dashboard',
        selectedSection: AdminShellSection.dashboard,
        onNavigate: _navigateDesktop,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationsScreen(),
                ),
              );
            },
            tooltip: 'Notifications',
          ),
        ],
        content: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: TextStyle(
                  color: AppStyles.textColor,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                userName,
                style: TextStyle(
                  color: AppStyles.textSecondaryColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - 16) / 2;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _buildActionCard(
                          label: 'Manage Users',
                          subtitle: 'Create, edit, disable, and delete users',
                          icon: Icons.people_outline,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ManageUsersScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildActionCard(
                          label: 'View Reports',
                          subtitle: 'Analytics and insights',
                          icon: Icons.bar_chart_rounded,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ViewReportsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildActionCard(
                          label: 'Upload Customers',
                          subtitle: _isImportingCustomers
                              ? 'Import currently running...'
                              : 'Upload and import Excel workbook',
                          icon: Icons.upload_file_outlined,
                          isBusy: _isImportingCustomers,
                          onTap: () => _handleUploadCustomers(context),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildActionCard(
                          label: 'Settings',
                          subtitle: 'System configuration',
                          icon: Icons.settings_outlined,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildActionCard(
                          label: 'Audit Logs',
                          subtitle: 'View tracked admin and data actions',
                          icon: Icons.history_edu_outlined,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AuditLogsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildActionCard(
                          label: 'Destructive Cleanup',
                          subtitle: 'Permanently remove live data collections',
                          icon: Icons.delete_forever_outlined,
                          accentColor: AppStyles.errorColor,
                          onTap: () => _runDestructiveCleanup(context),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppStyles.adminPrimaryColor,
        title: Text('Admin Dashboard', style: AppStyles.appBarTitleStyle),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.notifications_none, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  ),
                );
              },
              tooltip: 'Notifications',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.logout_outlined, color: Colors.white),
              onPressed: () => _showLogoutConfirmation(context, userProvider),
              tooltip: 'Sign Out',
            ),
          ),
        ],
      ),
      body: mobileBody,
    );
  }

  Widget _buildActionCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color accentColor = AppStyles.primaryColor,
    bool isBusy = false,
  }) {
    return Container(
      decoration: AppStyles.cardDecoration,
      child: InkWell(
        onTap: isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(
                    AppStyles.borderRadiusMedium,
                  ),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: AppStyles.spacingS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppStyles.textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppStyles.textSecondaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: AppStyles.textLightColor,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppStyles.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusSmall),
          ),
          child: const Icon(
            Icons.dashboard_customize_rounded,
            color: AppStyles.primaryColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text('Quick Actions', style: AppStyles.headingStyle),
      ],
    );
  }
}
