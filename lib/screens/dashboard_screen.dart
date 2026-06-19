import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../styles/app_styles.dart';
import '../services/firestore_service.dart';
import '../services/firestore_tenant.dart';
import '../services/queue_repository.dart';
import '../services/offline_sync_worker.dart';
import '../providers/user_provider.dart';
import 'pdf_preview_screen.dart';
import 'generate_sales_pdf.dart';
import 'edit_requisition_screen.dart';
import 'notifications_screen.dart';
import '../models/requisition_status.dart';
import '../models/queued_sales_requisition.dart';
import '../widgets/status_badge.dart';
import '../widgets/offline_queue_card.dart';
import '../utils/requisition_fields.dart';
import '../utils/app_logger.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const int _maxDashboardRecords = 100;

  final FirestoreService _firestoreService = FirestoreService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final int _currentIndex = 0;

  // Local offline queue, read reactively so submissions that were saved while
  // offline appear here before they sync. Rides the app-wide encrypted Hive box.
  final QueueRepository _queueRepository = QueueRepository();
  bool _queueReady = false;
  bool _isSyncing = false;
  // Active server-status filter for the synced list; null = show all.
  RequisitionStatusKind? _statusFilter;

  @override
  void initState() {
    super.initState();
    _initOfflineQueue();
  }

  Future<void> _initOfflineQueue() async {
    try {
      await _queueRepository.initialize();
      if (!mounted) return;
      setState(() => _queueReady = true);
    } catch (e, st) {
      // The dashboard must still work server-only if the queue can't open, so
      // a failure here just leaves the pending-upload section off.
      AppLogger.error(
        'Dashboard could not open the offline queue; showing server records only',
        error: e,
        stackTrace: st,
        tag: 'DASHBOARD',
      );
    }
  }

  void _logout(BuildContext context) async {
    final bool? didRequestLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Confirm Logout',
            style: TextStyle(
              color: AppStyles.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Are you sure you want to log out?',
            style: TextStyle(color: AppStyles.subtitleColor),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppStyles.primaryColor),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyles.secondaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Logout'),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (didRequestLogout == true) {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  void _navigateToEditForm(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EditRequisitionScreen(docId: docId, formData: data),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        ),
        title: const Text(
          'Confirm Delete',
          style: TextStyle(
            color: AppStyles.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to archive this record? It will be hidden from normal views but kept for recovery and audit.',
          style: TextStyle(color: AppStyles.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppStyles.primaryColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppStyles.borderRadiusMedium,
                ),
              ),
            ),
            onPressed: () async {
              await _firestoreService.deleteSalesRequisition(docId);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Record archived.'),
                  backgroundColor: AppStyles.secondaryColor,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.all(10),
                ),
              );
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  DateTime _extractDashboardTimestamp(Map<String, dynamic> data) {
    final value = data['timeStamp'] ?? data['timestamp'] ?? data['createdAt'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<QueryDocumentSnapshot<Object?>> _sortDashboardDocs(
    List<QueryDocumentSnapshot<Object?>> docs,
  ) {
    final sortedDocs = [...docs];
    sortedDocs.sort((left, right) {
      final leftData = (left.data() as Map<String, dynamic>? ?? {});
      final rightData = (right.data() as Map<String, dynamic>? ?? {});
      final rightTimestamp = _extractDashboardTimestamp(rightData);
      final leftTimestamp = _extractDashboardTimestamp(leftData);
      return rightTimestamp.compareTo(leftTimestamp);
    });

    if (sortedDocs.length > _maxDashboardRecords) {
      return sortedDocs.sublist(0, _maxDashboardRecords);
    }

    return sortedDocs;
  }

  String _dashboardErrorMessage(Object? error) {
    final text = error?.toString() ?? 'Unknown error';
    if (text.contains('permission-denied')) {
      return 'Dashboard access was denied for this tenant. Check Firestore rules for company B.';
    }
    if (text.contains('failed-precondition') || text.contains('index')) {
      return 'Dashboard data is not indexed for this tenant. The page is now using a safer query path.';
    }
    return 'Something went wrong loading your dashboard.';
  }

  Future<void> _retryAutoEmail({
    required String requisitionId,
    required Map<String, dynamic> requisitionData,
    required String? actorCompanyId,
  }) async {
    try {
      final pdfBytes = await generateSalesPDF(requisitionData);
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('sendAutoRoutedRequisitionEmail');
      await callable.call(<String, dynamic>{
        'requisitionId': requisitionId,
        'pdfData': base64Encode(pdfBytes),
        'fileName':
            'SOR-${requisitionData['sorNumber'] ?? requisitionId}-retry.pdf',
        'manualRetry': true,
        'actorCompanyIdentifier': actorCompanyId,
        'actorDatabaseId': FirestoreTenant.instance.databaseId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retry email sent successfully.'),
          backgroundColor: AppStyles.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry email failed: $error'),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Manually drains the offline queue so a reconnected user can push pending
  // uploads without restarting — auto-sync otherwise only fires on auth events.
  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final report = await OfflineSyncWorker.instance.syncPendingQueue(
        ignoreBackoff: true,
      );
      if (!mounted) return;
      final message = report.blockedByConnectivity
          ? 'Still offline — pending uploads will sync when you reconnect.'
          : report.syncedAccepted > 0
          ? '${report.syncedAccepted} upload(s) synced.'
          : 'Up to date.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (e, st) {
      AppLogger.error(
        'Manual sync failed',
        error: e,
        stackTrace: st,
        tag: 'DASHBOARD',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync failed. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userProvider = context.watch<UserProvider>();
    final isAdmin = userProvider.isAdmin;
    final actorCompanyId = userProvider.currentUser?.companyId;
    final currencyFormat = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppStyles.primaryColor,
        title: Row(
          children: [
            Icon(
              _currentIndex == 0 ? Icons.dashboard_rounded : Icons.receipt_long,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              _currentIndex == 0 ? 'Sales Dashboard' : 'My Submissions',
              style: AppStyles.appBarTitleStyle,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Sync pending uploads',
            onPressed: _isSyncing ? null : _triggerSync,
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            tooltip: 'Notifications',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      // Only wrap in the queue listener once the box is open; otherwise fall back
      // to the unchanged server-only view.
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _queueReady
                ? ValueListenableBuilder(
                    valueListenable: _queueRepository.listenable(),
                    builder: (context, _, _) {
                      final offlineItems = _queueRepository.getDashboardVisible(
                        userId: uid ?? '',
                        tenantDatabaseId: FirestoreTenant.instance.databaseId,
                      );
                      return _dashboardStream(
                        uid: uid,
                        actorCompanyId: actorCompanyId,
                        isAdmin: isAdmin,
                        currencyFormat: currencyFormat,
                        offlineItems: offlineItems,
                      );
                    },
                  )
                : _dashboardStream(
                    uid: uid,
                    actorCompanyId: actorCompanyId,
                    isAdmin: isAdmin,
                    currencyFormat: currencyFormat,
                    offlineItems: const [],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppStyles.secondaryColor,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          Navigator.pushNamed(context, '/form');
        },
      ),
    );
  }

  // Chips mirror the server-side kinds RequisitionStatus.fromRequisition can
  // return; the null chip clears the filter. Offline/queue kinds aren't here —
  // the pending-upload tray stays visible regardless of the active filter.
  static const List<({RequisitionStatusKind? kind, String label})>
  _statusFilterOptions = [
    (kind: null, label: 'All'),
    (kind: RequisitionStatusKind.awaitingApproval, label: 'Awaiting approval'),
    (kind: RequisitionStatusKind.cleared, label: 'Cleared'),
    (kind: RequisitionStatusKind.deliveryFailed, label: 'Delivery failed'),
    (kind: RequisitionStatusKind.sending, label: 'Sending'),
    (kind: RequisitionStatusKind.notSent, label: 'Not sent'),
    (kind: RequisitionStatusKind.emailOff, label: 'Email off'),
    (kind: RequisitionStatusKind.archived, label: 'Archived'),
  ];

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      color: AppStyles.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statusFilterOptions.map((option) {
            final selected = _statusFilter == option.kind;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(option.label),
                selected: selected,
                showCheckmark: false,
                backgroundColor: AppStyles.backgroundColor,
                selectedColor: AppStyles.primaryColor,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppStyles.textColor,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                onSelected: (_) => setState(() => _statusFilter = option.kind),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Keeps only synced records whose unified status matches the active chip.
  List<QueryDocumentSnapshot<Object?>> _filterDocsByStatus(
    List<QueryDocumentSnapshot<Object?>> docs,
  ) {
    final filter = _statusFilter;
    if (filter == null) return docs;
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return RequisitionStatus.fromRequisition(data).kind == filter;
    }).toList();
  }

  Widget _buildNoMatchState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.filter_alt_off_outlined,
            size: 48,
            color: AppStyles.textSecondaryColor,
          ),
          const SizedBox(height: 12),
          const Text(
            'No requisitions match this filter.',
            style: TextStyle(
              color: AppStyles.textSecondaryColor,
              fontSize: 14,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _statusFilter = null),
            child: const Text('Show all'),
          ),
        ],
      ),
    );
  }

  Widget _dashboardStream({
    required String? uid,
    required String? actorCompanyId,
    required bool isAdmin,
    required NumberFormat currencyFormat,
    required List<QueuedSalesRequisition> offlineItems,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreTenant.instance.firestore
          .collection('salesRequisitions')
          .where('userID', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState == ConnectionState.waiting;
        final hasOffline = offlineItems.isNotEmpty;

        // Nothing local to show yet — keep the original full-screen spinner.
        if (waiting && !hasOffline) {
          return const Center(
            child: CircularProgressIndicator(color: AppStyles.primaryColor),
          );
        }

        if (snapshot.hasError) {
          if (!hasOffline) {
            return _buildServerError(snapshot.error);
          }
          // Offline records are exactly what the user needs when the server is
          // unreachable, so show them above a non-blocking error banner.
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildOfflineSection(offlineItems, currencyFormat),
              const SizedBox(height: 16),
              _buildServerErrorBanner(snapshot.error),
            ],
          );
        }

        final docs = _filterDocsByStatus(
          _sortDashboardDocs(snapshot.data?.docs ?? []),
        );

        if (docs.isEmpty && !hasOffline) {
          return _statusFilter == null
              ? _buildEmptyState()
              : _buildNoMatchState();
        }

        final headerCount = hasOffline ? 1 : 0;
        final loaderCount = waiting ? 1 : 0;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: headerCount + docs.length + loaderCount,
          itemBuilder: (context, index) {
            if (hasOffline && index == 0) {
              return _buildOfflineSection(offlineItems, currencyFormat);
            }

            final syncedIndex = index - headerCount;

            // Trailing loader while the server list streams in beneath the
            // already-visible offline section.
            if (waiting && syncedIndex == docs.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppStyles.primaryColor,
                  ),
                ),
              );
            }

            final doc = docs[syncedIndex];
            return _buildSyncedCard(
              context,
              doc,
              isAdmin,
              actorCompanyId,
              currencyFormat,
            );
          },
        );
      },
    );
  }

  Widget _buildOfflineSection(
    List<QueuedSalesRequisition> items,
    NumberFormat currencyFormat,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 18,
                color: AppStyles.statusInfo,
              ),
              const SizedBox(width: 6),
              Text(
                'Pending upload (${items.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppStyles.textColor,
                ),
              ),
            ],
          ),
        ),
        ...items.map(
          (item) =>
              OfflineQueueCard(item: item, currencyFormat: currencyFormat),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildServerError(Object? error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(
            _dashboardErrorMessage(error),
            style: TextStyle(fontSize: 18, color: Colors.grey[800]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppStyles.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              setState(() {});
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildServerErrorBanner(Object? error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, color: Colors.redAccent),
          const SizedBox(height: 8),
          Text(
            _dashboardErrorMessage(error),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {}),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long,
              size: 80,
              color: AppStyles.primaryColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No sales requisitions yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your sales records will appear here',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppStyles.secondaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'Create New Requisition',
              style: TextStyle(fontSize: 16),
            ),
            onPressed: () {
              // Navigate to create form
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncedCard(
    BuildContext context,
    QueryDocumentSnapshot<Object?> doc,
    bool isAdmin,
    String? actorCompanyId,
    NumberFormat currencyFormat,
  ) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});
    final timestamp = data['timeStamp'] as Timestamp?;
    final date = timestamp?.toDate();

    // Use DateFormat for more flexible formatting
    final formattedDate = date != null
        ? DateFormat('MMM d, yyyy').format(date)
        : 'Unknown Date';

    final totalAmount = data['totalAmount'] ?? 0.0;
    final items = (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final status = RequisitionStatus.fromRequisition(data);
    final emailSent = RequisitionFields.emailStatus(data) == 'sent';
    final emailLastError = (data['autoEmailLastError'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 2,
      color: AppStyles.cardColor,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 8,
        ),
        childrenPadding: const EdgeInsets.all(0),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppStyles.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.shopping_bag,
                color: AppStyles.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['customerName'] ?? 'Unknown Customer',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'SOR #: ${data['sorNumber'] ?? ''}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(status: status, dense: true),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 44, top: 4),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 14,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                formattedDate,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                currencyFormat.format(totalAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppStyles.primaryColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        children: [
          // Details section
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8F7FC),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order details
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order Details',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppStyles.textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        'Account #:',
                        data['accountNumber'] ?? '',
                      ),
                      _buildDetailRow('Area:', data['area'] ?? ''),
                      _buildDetailRow(
                        'Payment Terms:',
                        data['paymentTerms'] ?? '',
                      ),
                      if (data['deliveryInstruction'] != null &&
                          data['deliveryInstruction']
                              .toString()
                              .isNotEmpty)
                        _buildDetailRow(
                          'Delivery Instruction:',
                          data['deliveryInstruction'],
                        ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Items section
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Items',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppStyles.textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...List<Widget>.from(
                        items.map((item) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppStyles.primaryColor
                                        .withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${item['quantity']}x',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppStyles.primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['name'] ??
                                            'Unknown Item',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'Code: ${item['code'] ?? ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  currencyFormat.format(
                                    item['subtotal'] ?? 0,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),

                      // Total and Remarks
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppStyles.primaryColor.withValues(
                            alpha: 0.05,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Status:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                StatusBadge(status: status),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                status.detail,
                                style: const TextStyle(
                                  color: AppStyles.textSecondaryColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (status.kind ==
                                    RequisitionStatusKind.deliveryFailed &&
                                emailLastError.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  emailLastError,
                                  style: const TextStyle(
                                    color: AppStyles.textLightColor,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total Amount:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  currencyFormat.format(totalAmount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppStyles.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                            if (data['remark1'] != null &&
                                data['remark1']
                                    .toString()
                                    .isNotEmpty) ...[
                              const Divider(),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: Colors.orangeAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Remark 1: ${data['remark1']}',
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (data['remark2'] != null &&
                                data['remark2']
                                    .toString()
                                    .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: Colors.orangeAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Remark 2: ${data['remark2']}',
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Action buttons
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildActionButton(
                        icon: Icons.picture_as_pdf,
                        label: 'PDF',
                        color: Colors.blue,
                        onPressed: () async {
                          final pdfBytes = await generateSalesPDF(
                            data,
                          );
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PdfPreviewScreen(
                                pdfBytes: pdfBytes,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildActionButton(
                        icon: Icons.edit,
                        label: 'Edit',
                        color: AppStyles.primaryColor,
                        onPressed: () => _navigateToEditForm(
                          context,
                          doc.id,
                          data,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildActionButton(
                        icon: Icons.delete,
                        label: 'Delete',
                        color: AppStyles.secondaryColor,
                        onPressed: () =>
                            _confirmDelete(context, doc.id),
                      ),
                      if (isAdmin && !emailSent)
                        _buildActionButton(
                          icon: Icons.refresh_outlined,
                          label: 'Retry Email',
                          color: Colors.deepOrange,
                          onPressed: () => _retryAutoEmail(
                            requisitionId: doc.id,
                            requisitionData: data,
                            actorCompanyId: actorCompanyId,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppStyles.textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 90, // Set a fixed width to make buttons smaller
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: color, size: 18), // Smaller icon
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13, // Smaller text
          ),
        ),
        style: TextButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(
            vertical: 6, // Smaller vertical padding
            horizontal: 4, // Smaller horizontal padding
          ),
          minimumSize: const Size(0, 36), // Smaller minimum height
        ),
      ),
    );
  }
}
