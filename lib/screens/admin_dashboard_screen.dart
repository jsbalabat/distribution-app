// lib/screens/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../styles/app_styles.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'manage_users_screen.dart';
import 'view_reports_screen.dart';
import 'settings_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
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
              icon: const Icon(Icons.logout_outlined, color: Colors.white),
              onPressed: () => _showLogoutConfirmation(context, userProvider),
              tooltip: 'Sign Out',
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppStyles.adminPrimaryColor, AppStyles.primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppStyles.spacingL,
                AppStyles.spacingL,
                AppStyles.spacingL,
                AppStyles.spacingXL,
              ),
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

            Transform.translate(
              offset: const Offset(0, -20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppStyles.spacingM,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: AppStyles.spacingM,
                      mainAxisSpacing: AppStyles.spacingM,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.5,
                      children: [
                        _buildStatCard(
                          title: 'Total Users',
                          value: '124',
                          icon: Icons.people_outline,
                          gradientColors: AppStyles.statCardGradients[0],
                        ),
                        _buildStatCard(
                          title: 'Total Sales',
                          value: '₱245K',
                          icon: Icons.trending_up_rounded,
                          gradientColors: AppStyles.statCardGradients[1],
                        ),
                        _buildStatCard(
                          title: 'Pending Orders',
                          value: '12',
                          icon: Icons.pending_actions_rounded,
                          gradientColors: AppStyles.statCardGradients[2],
                        ),
                        _buildStatCard(
                          title: 'Products',
                          value: '48',
                          icon: Icons.inventory_2_outlined,
                          gradientColors: AppStyles.statCardGradients[3],
                        ),
                      ],
                    ),

                    const SizedBox(height: AppStyles.spacingXL),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppStyles.primaryColor.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppStyles.borderRadiusSmall,
                            ),
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
                    ),
                    const SizedBox(height: AppStyles.spacingM),

                    _buildActionCard(
                      label: 'Manage Users',
                      subtitle: 'View and edit user accounts',
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
                      label: 'Inventory',
                      subtitle: 'Manage product inventory',
                      icon: Icons.inventory_2_outlined,
                      onTap: () {},
                    ),
                    const SizedBox(height: AppStyles.spacingS),

                    _buildActionCard(
                      label: 'Upload Customers',
                      subtitle: 'Import customer data',
                      icon: Icons.upload_file_outlined,
                      onTap: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Starting upload...'),
                            backgroundColor: AppStyles.infoColor,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        try {
                          await FirebaseFirestore.instance
                              .collection('dataImports')
                              .add({
                                'requestedAt': FieldValue.serverTimestamp(),
                                'status': 'pending',
                                'requestedBy':
                                    userProvider.currentUser?.email ??
                                    'unknown',
                              });
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Import triggered! Check status in Firestore.',
                              ),
                              backgroundColor: AppStyles.successColor,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to trigger import: $e'),
                              backgroundColor: AppStyles.errorColor,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: AppStyles.spacingS),

                    _buildActionCard(
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

                    const SizedBox(height: AppStyles.spacingXL),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required List<Color> gradientColors,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: gradientColors[0].withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: Colors.white.withValues(alpha: 0.9)),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: AppStyles.cardDecoration,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppStyles.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(
                    AppStyles.borderRadiusMedium,
                  ),
                ),
                child: Icon(icon, size: 24, color: AppStyles.primaryColor),
              ),
              const SizedBox(width: AppStyles.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppStyles.textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppStyles.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
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
}
