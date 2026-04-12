import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../styles/app_styles.dart';

enum AdminShellSection {
  dashboard,
  users,
  reports,
  settings,
  auditLogs,
  notifications,
}

class AdminDesktopShell extends StatelessWidget {
  static const double desktopBreakpoint = 1100;

  const AdminDesktopShell({
    super.key,
    required this.title,
    required this.selectedSection,
    required this.content,
    required this.onNavigate,
    this.actions = const [],
  });

  final String title;
  final AdminShellSection selectedSection;
  final Widget content;
  final ValueChanged<AdminShellSection> onNavigate;
  final List<Widget> actions;

  Future<void> _showLogoutConfirmation(BuildContext context) async {
    final userProvider = context.read<UserProvider>();
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
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
          content: const Text('Are you sure you want to log out?'),
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
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      userProvider.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final userName = userProvider.currentUser?.name ?? 'Admin';
    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : 'A';

    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 250,
              decoration: const BoxDecoration(
                color: AppStyles.cardColor,
                border: Border(
                  right: BorderSide(color: Color(0xFFE5E5E5), width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppStyles.primaryColor,
                                AppStyles.secondaryColor,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.dashboard_customize_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Admin Panel',
                            style: TextStyle(
                              color: AppStyles.textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        _buildSidebarItem(
                          icon: Icons.home_outlined,
                          label: 'Dashboard',
                          selected:
                              selectedSection == AdminShellSection.dashboard,
                          onTap: () => onNavigate(AdminShellSection.dashboard),
                        ),
                        _buildSidebarItem(
                          icon: Icons.people_outline,
                          label: 'Manage Users',
                          selected: selectedSection == AdminShellSection.users,
                          onTap: () => onNavigate(AdminShellSection.users),
                        ),
                        _buildSidebarItem(
                          icon: Icons.bar_chart_rounded,
                          label: 'View Reports',
                          selected:
                              selectedSection == AdminShellSection.reports,
                          onTap: () => onNavigate(AdminShellSection.reports),
                        ),
                        _buildSidebarItem(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          selected:
                              selectedSection == AdminShellSection.settings,
                          onTap: () => onNavigate(AdminShellSection.settings),
                        ),
                        _buildSidebarItem(
                          icon: Icons.history_edu_outlined,
                          label: 'Audit Logs',
                          selected:
                              selectedSection == AdminShellSection.auditLogs,
                          onTap: () => onNavigate(AdminShellSection.auditLogs),
                        ),
                        _buildSidebarItem(
                          icon: Icons.notifications_none,
                          label: 'Notifications',
                          selected:
                              selectedSection ==
                              AdminShellSection.notifications,
                          onTap: () =>
                              onNavigate(AdminShellSection.notifications),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _buildSidebarItem(
                      icon: Icons.logout_outlined,
                      label: 'Logout',
                      onTap: () => _showLogoutConfirmation(context),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 68,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: const BoxDecoration(
                      color: AppStyles.adminPrimaryColor,
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE5E5E5), width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        ...actions,
                        if (actions.isNotEmpty) const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: AppStyles.primaryColor,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Logout',
                          onPressed: () => _showLogoutConfirmation(context),
                          icon: const Icon(
                            Icons.logout_outlined,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? AppStyles.primaryColor.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? AppStyles.primaryColor
                      : AppStyles.textLightColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? AppStyles.primaryColor
                          : AppStyles.textSecondaryColor,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppStyles.primaryColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
