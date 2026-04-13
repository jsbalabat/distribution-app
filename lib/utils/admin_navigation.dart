import 'package:flutter/material.dart';

import '../screens/admin_dashboard_screen.dart';
import '../screens/audit_logs_screen.dart';
import '../screens/manage_users_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/view_reports_screen.dart';
import '../widgets/admin_desktop_shell.dart';

void navigateToAdminSection(
  BuildContext context,
  AdminShellSection section, {
  required AdminShellSection currentSection,
}) {
  if (section == currentSection) return;

  Widget? destination;
  switch (section) {
    case AdminShellSection.dashboard:
      destination = const AdminDashboardScreen();
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
