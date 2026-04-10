import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../services/notification_service.dart';
import '../styles/app_styles.dart';
import '../widgets/admin_desktop_shell.dart';
import 'admin_dashboard_screen.dart';
import 'audit_logs_screen.dart';
import 'manage_users_screen.dart';
import 'settings_screen.dart';
import 'view_reports_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService.instance;
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;
    _initialized = true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAdmin = context.read<UserProvider>().isAdmin;

    if (uid != null) {
      _future = _notificationService.fetchNotifications(
        uid: uid,
        isAdmin: isAdmin,
      );
    }
  }

  Future<void> _refresh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAdmin = context.read<UserProvider>().isAdmin;

    if (uid == null) return;

    setState(() {
      _future = _notificationService.fetchNotifications(
        uid: uid,
        isAdmin: isAdmin,
      );
    });

    await _future;
  }

  Future<void> _markAllAsRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isAdmin = context.read<UserProvider>().isAdmin;

    if (uid == null) return;

    await _notificationService.markAllAsRead(uid: uid, isAdmin: isAdmin);
    await _refresh();
  }

  Future<void> _markAsRead(String notificationId) async {
    await _notificationService.markAsRead(notificationId);
    await _refresh();
  }

  void _navigateDesktop(AdminShellSection section) {
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
        return;
    }

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination!));
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy • HH:mm');
    final isDesktop = MediaQuery.of(context).size.width >= 1100;

    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(child: Text('Error: ${snapshot.error}')),
              ],
            );
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No notifications yet.')),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data();
              final title = (data['title'] ?? 'Notification').toString();
              final body = (data['body'] ?? '').toString();
              final entityType = (data['entityType'] ?? 'general').toString();
              final isRead = data['isRead'] == true;
              final timestamp = data['createdAt'];
              final createdAt = timestamp is Timestamp
                  ? dateFormat.format(timestamp.toDate())
                  : 'Pending';

              return Card(
                elevation: 1,
                child: ListTile(
                  onTap: isRead ? null : () => _markAsRead(doc.id),
                  leading: CircleAvatar(
                    backgroundColor: isRead
                        ? Colors.grey.shade300
                        : AppStyles.primaryColor.withValues(alpha: 0.1),
                    child: Icon(
                      isRead ? Icons.notifications_none : Icons.notifications,
                      color: isRead
                          ? Colors.grey.shade700
                          : AppStyles.primaryColor,
                    ),
                  ),
                  title: Text(
                    title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w700,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(body),
                        const SizedBox(height: 4),
                        Text(
                          '$entityType • $createdAt',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: isRead
                      ? null
                      : Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppStyles.secondaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
              );
            },
          );
        },
      ),
    );

    if (isDesktop) {
      return AdminDesktopShell(
        title: 'Notifications',
        selectedSection: AdminShellSection.notifications,
        onNavigate: _navigateDesktop,
        actions: [
          IconButton(
            onPressed: _markAllAsRead,
            icon: const Icon(Icons.done_all_outlined, color: Colors.white),
            tooltip: 'Mark all as read',
          ),
        ],
        content: body,
      );
    }

    return Scaffold(
      backgroundColor: AppStyles.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notifications', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppStyles.primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _markAllAsRead,
            icon: const Icon(Icons.done_all_outlined),
            tooltip: 'Mark all as read',
          ),
        ],
      ),
      body: body,
    );
  }
}
