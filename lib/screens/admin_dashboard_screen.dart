// lib/screens/admin_dashboard_screen.dart
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../services/firestore_tenant.dart';
import '../styles/app_styles.dart';
import '../utils/admin_navigation.dart';
import '../utils/app_logger.dart';
import '../utils/excel_file_picker.dart';
import '../widgets/admin_desktop_shell.dart';
import '../widgets/admin_screen_guard.dart';
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

  // Live tenant-wide totals for the overview cards; null = not yet loaded/failed.
  final Map<String, int?> _counts = {
    'users': null,
    'customers': null,
    'itemMaster': null,
    'salesRequisitions': null,
  };
  bool _loadingCounts = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  // Uses count() aggregation rather than reading documents, so the overview stays
  // cheap on large collections; a failed count degrades to an em dash, not an error.
  Future<void> _loadCounts() async {
    if (mounted) setState(() => _loadingCounts = true);
    final db = FirestoreTenant.instance.firestore;

    Future<int?> countOf(String collection) async {
      try {
        final snapshot = await db.collection(collection).count().get();
        return snapshot.count;
      } catch (error) {
        AppLogger.error('Failed to count $collection', error: error, tag: 'ADMIN');
        return null;
      }
    }

    final keys = _counts.keys.toList();
    final results = await Future.wait(keys.map(countOf));
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < keys.length; i++) {
        _counts[keys[i]] = results[i];
      }
      _loadingCounts = false;
    });
  }

  void _navigateDesktop(AdminShellSection section) {
    navigateToAdminSection(
      context,
      section,
      currentSection: AdminShellSection.dashboard,
    );
  }

  void _openSection(AdminShellSection section) {
    final isDesktop =
        MediaQuery.of(context).size.width >=
        AdminDesktopShell.desktopBreakpoint;
    if (isDesktop) {
      _navigateDesktop(section);
      return;
    }

    switch (section) {
      case AdminShellSection.dashboard:
        return;
      case AdminShellSection.users:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ManageUsersScreen()),
        );
      case AdminShellSection.reports:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ViewReportsScreen()),
        );
      case AdminShellSection.settings:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      case AdminShellSection.auditLogs:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AuditLogsScreen()),
        );
      case AdminShellSection.notifications:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const NotificationsScreen()),
        );
    }
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

      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('importDataFromExcelDirect');
      final response = await callable.call(<String, dynamic>{
        'fileName': pickedFile.name,
        'fileBase64': base64Encode(bytes),
      });

      if (!context.mounted) return;
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final summary = data['summary'] is Map
          ? Map<String, dynamic>.from(data['summary'] as Map)
          : const <String, dynamic>{};
      _showImportSummary(context, pickedFile.name, summary);
      await _loadCounts();
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

  // Surfaces the server's per-collection write counts so an admin can confirm an
  // import actually landed. Note the import appends rather than replaces, so the
  // dialog flags that re-importing the same file duplicates rows.
  void _showImportSummary(
    BuildContext context,
    String fileName,
    Map<String, dynamic> summary,
  ) {
    int countOf(String key) => (summary[key] as num?)?.toInt() ?? 0;
    final rows = <({String label, int value})>[
      (label: 'Customers', value: countOf('customers')),
      (label: 'Account receivable', value: countOf('accountReceivable')),
      (label: 'Item master', value: countOf('itemMaster')),
      (label: 'Items available', value: countOf('itemsAvailable')),
    ];
    final total = rows.fold<int>(0, (sum, row) => sum + row.value);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.borderRadiusMedium),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppStyles.successColor),
            SizedBox(width: 12),
            Text('Import complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppStyles.textColor,
              ),
            ),
            const SizedBox(height: AppStyles.spacingM),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(row.label),
                    Text(
                      '${row.value}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: AppStyles.spacingL),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total records',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '$total',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppStyles.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppStyles.spacingM),
            Text(
              'Records are added, not replaced. Re-importing the same file '
              'duplicates rows; run a destructive cleanup first for a fresh load.',
              style: TextStyle(
                fontSize: 12,
                color: AppStyles.textSecondaryColor,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppStyles.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _runDestructiveCleanup(BuildContext context) async {
    final typedConfirmation = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String confirmationInput = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canRun = confirmationInput == 'DELETE';

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppStyles.borderRadiusMedium,
                ),
              ),
              title: const Text('Confirm destructive cleanup'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This will permanently delete customers, inventory, requisitions, import requests, and notifications.',
                  ),
                  const SizedBox(height: AppStyles.spacingM),
                  const Text(
                    'Type DELETE to confirm:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppStyles.spacingS),
                  TextField(
                    autofocus: true,
                    onChanged: (value) {
                      setDialogState(() {
                        confirmationInput = value.trim();
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'DELETE',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyles.errorColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: canRun
                      ? () => Navigator.of(dialogContext).pop(confirmationInput)
                      : null,
                  child: const Text('Run cleanup'),
                ),
              ],
            );
          },
        );
      },
    );

    if (typedConfirmation != 'DELETE' || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Running destructive cleanup...'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('runDestructiveCleanup');
      final result = await callable.call(<String, dynamic>{
        'confirmText': typedConfirmation,
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
      await _loadCounts();
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
    final isDesktop =
        MediaQuery.of(context).size.width >=
        AdminDesktopShell.desktopBreakpoint;

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
        _buildStatsOverview(),
        const SizedBox(height: AppStyles.spacingL),
        ..._buildSections(context, isDesktop: false),
      ],
    );

    final screen = isDesktop
        ? AdminDesktopShell(
            title: 'Admin Dashboard',
            selectedSection: AdminShellSection.dashboard,
            onNavigate: _navigateDesktop,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white),
                onPressed: () => _openSection(AdminShellSection.notifications),
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
                  _buildStatsOverview(),
                  const SizedBox(height: 20),
                  ..._buildSections(context, isDesktop: true),
                ],
              ),
            ),
          )
        : Scaffold(
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
                    icon: const Icon(
                      Icons.notifications_none,
                      color: Colors.white,
                    ),
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
                    icon: const Icon(
                      Icons.logout_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () =>
                        _showLogoutConfirmation(context, userProvider),
                    tooltip: 'Sign Out',
                  ),
                ),
              ],
            ),
            body: mobileBody,
          );

    return AdminScreenGuard(title: 'Admin Dashboard', child: screen);
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

  Widget _buildStatsOverview() {
    final stats = <({String label, String key, IconData icon})>[
      (label: 'Users', key: 'users', icon: Icons.people_alt_outlined),
      (label: 'Customers', key: 'customers', icon: Icons.badge_outlined),
      (label: 'Items', key: 'itemMaster', icon: Icons.inventory_2_outlined),
      (
        label: 'Requisitions',
        key: 'salesRequisitions',
        icon: Icons.receipt_long_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        // Four across on wide layouts, two across on phones.
        final perRow = constraints.maxWidth >= 520 ? 4 : 2;
        final cardWidth =
            (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: cardWidth,
                  child: _buildStatCard(stat.label, _counts[stat.key], stat.icon),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildStatCard(String label, int? value, IconData icon) {
    return Container(
      decoration: AppStyles.cardDecoration,
      padding: const EdgeInsets.all(AppStyles.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppStyles.primaryColor),
              const Spacer(),
              if (_loadingCounts)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value == null ? '—' : NumberFormat.decimalPattern().format(value),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppStyles.textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppStyles.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool danger = false}) {
    return Row(
      children: [
        if (danger) ...[
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppStyles.errorColor,
          ),
          const SizedBox(width: 6),
        ],
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: danger ? AppStyles.errorColor : AppStyles.textSecondaryColor,
          ),
        ),
      ],
    );
  }

  List<({String title, bool danger, List<Widget> cards})> _sections(
    BuildContext context,
  ) {
    return [
      (
        title: 'Management',
        danger: false,
        cards: [
          _buildActionCard(
            label: 'Manage Users',
            subtitle: 'Create, edit, disable, and delete users',
            icon: Icons.people_outline,
            onTap: () => _openSection(AdminShellSection.users),
          ),
          _buildActionCard(
            label: 'View Reports',
            subtitle: 'Analytics and insights',
            icon: Icons.bar_chart_rounded,
            onTap: () => _openSection(AdminShellSection.reports),
          ),
          _buildActionCard(
            label: 'Settings',
            subtitle: 'System configuration',
            icon: Icons.settings_outlined,
            onTap: () => _openSection(AdminShellSection.settings),
          ),
          _buildActionCard(
            label: 'Audit Logs',
            subtitle: 'View tracked admin and data actions',
            icon: Icons.history_edu_outlined,
            onTap: () => _openSection(AdminShellSection.auditLogs),
          ),
        ],
      ),
      (
        title: 'Data',
        danger: false,
        cards: [
          _buildActionCard(
            label: 'Import Data (Excel)',
            subtitle: _isImportingCustomers
                ? 'Import currently running...'
                : 'Customers, receivables & inventory',
            icon: Icons.upload_file_outlined,
            isBusy: _isImportingCustomers,
            onTap: () => _handleUploadCustomers(context),
          ),
        ],
      ),
      (
        title: 'Danger Zone',
        danger: true,
        cards: [
          _buildActionCard(
            label: 'Destructive Cleanup',
            subtitle: 'Permanently remove live data collections',
            icon: Icons.delete_forever_outlined,
            accentColor: AppStyles.errorColor,
            onTap: () => _runDestructiveCleanup(context),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildSections(
    BuildContext context, {
    required bool isDesktop,
  }) {
    final widgets = <Widget>[];
    for (final section in _sections(context)) {
      widgets.add(_buildSectionHeader(section.title, danger: section.danger));
      widgets.add(const SizedBox(height: AppStyles.spacingS));

      Widget body;
      if (isDesktop) {
        body = LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 16) / 2;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: section.cards
                  .map((card) => SizedBox(width: cardWidth, child: card))
                  .toList(),
            );
          },
        );
      } else {
        body = Column(
          children: [
            for (final card in section.cards)
              Padding(
                padding: const EdgeInsets.only(bottom: AppStyles.spacingS),
                child: card,
              ),
          ],
        );
      }

      if (section.danger) {
        body = Container(
          padding: const EdgeInsets.all(AppStyles.spacingS),
          decoration: BoxDecoration(
            color: AppStyles.errorColor.withValues(alpha: 0.04),
            border: Border.all(
              color: AppStyles.errorColor.withValues(alpha: 0.25),
            ),
            borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
          ),
          child: body,
        );
      }

      widgets.add(body);
      widgets.add(const SizedBox(height: AppStyles.spacingL));
    }
    return widgets;
  }
}
