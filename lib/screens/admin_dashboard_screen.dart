// lib/screens/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../styles/app_styles.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.logout_outlined),
              onPressed: () => userProvider.signOut(),
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
                      childAspectRatio: 1.3,
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
                          icon: Icons.attach_money,
                          gradientColors: AppStyles.statCardGradients[1],
                        ),
                        _buildStatCard(
                          title: 'Pending Orders',
                          value: '12',
                          icon: Icons.shopping_cart_outlined,
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

                    Text('Quick Actions', style: AppStyles.headingStyle),
                    const SizedBox(height: AppStyles.spacingM),

                    _buildActionCard(
                      label: 'Manage Users',
                      subtitle: 'View and edit user accounts',
                      icon: Icons.people_outline,
                      color: Colors.blue,
                      onTap: () {},
                    ),
                    const SizedBox(height: AppStyles.spacingM),

                    _buildActionCard(
                      label: 'View Reports',
                      subtitle: 'Analytics and insights',
                      icon: Icons.bar_chart_rounded,
                      color: Colors.green,
                      onTap: () {},
                    ),
                    const SizedBox(height: AppStyles.spacingM),

                    _buildActionCard(
                      label: 'Inventory',
                      subtitle: 'Manage product inventory',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.purple,
                      onTap: () {},
                    ),
                    const SizedBox(height: AppStyles.spacingM),

                    _buildActionCard(
                      label: 'Upload Customers',
                      subtitle: 'Import customer data',
                      icon: Icons.upload_file_outlined,
                      color: Colors.orange,
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
                    const SizedBox(height: AppStyles.spacingM),

                    _buildActionCard(
                      label: 'Settings',
                      subtitle: 'System configuration',
                      icon: Icons.settings_outlined,
                      color: Colors.grey,
                      onTap: () {},
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
        padding: const EdgeInsets.all(AppStyles.spacingM),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: Colors.white.withValues(alpha: 0.9)),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
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
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        child: Padding(
          padding: const EdgeInsets.all(AppStyles.spacingM),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(
                    AppStyles.borderRadiusMedium,
                  ),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(width: AppStyles.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
