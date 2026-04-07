import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/firestore_service.dart';
import '../styles/app_styles.dart';
import '../utils/requisition_fields.dart';

Future<void> _generateAndPrintPDF(Map<String, dynamic> data) async {
  final pdf = pw.Document();

  final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
  final ts = RequisitionFields.timestamp(data);

  pdf.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text(
          'Sales Requisition Report',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text('SOR #: ${RequisitionFields.sorNumber(data)}'),
        pw.Text('Customer: ${data['customerName']}'),
        pw.Text('Account #: ${data['accountNumber']}'),
        pw.Text('Date: ${ts?.toString().split(' ')[0] ?? ''}'),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: ['Item', 'Quantity', 'Unit Price', 'Subtotal'],
          data: items.map((item) {
            return [
              item['name'] ?? '',
              item['quantity'].toString(),
              '₱${item['unitPrice']}',
              '₱${item['subtotal']}',
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Remarks: ${data['remarks'] ?? ''}'),
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => pdf.save());
}

class TransactionDetailScreen extends StatefulWidget {
  static const int _pageSize = 20;

  const TransactionDetailScreen({super.key});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final List<DocumentSnapshot<Map<String, dynamic>>> _docs = [];

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isInitialLoading = true;
      _error = null;
      _hasMore = true;
      _lastDoc = null;
      _docs.clear();
    });

    try {
      final snapshot = await _firestoreService.fetchUserSubmissionsPage(
        limit: TransactionDetailScreen._pageSize,
      );

      if (!mounted) return;
      setState(() {
        _docs.addAll(snapshot.docs);
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == TransactionDetailScreen._pageSize;
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final snapshot = await _firestoreService.fetchUserSubmissionsPage(
        limit: TransactionDetailScreen._pageSize,
        startAfter: _lastDoc,
      );

      if (!mounted) return;
      setState(() {
        _docs.addAll(snapshot.docs);
        _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastDoc;
        _hasMore = snapshot.docs.length == TransactionDetailScreen._pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        title: Text('All Item Transactions', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppStyles.primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            tooltip: 'Filter',
            onPressed: () {
              // Filter functionality would go here
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Filtering coming soon!'),
                  backgroundColor: AppStyles.secondaryColor,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppStyles.borderRadiusMedium,
                    ),
                  ),
                  margin: const EdgeInsets.all(AppStyles.paddingMedium),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _loadInitial,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header/Summary section
          Container(
            width: double.infinity,
            padding: AppStyles.cardPadding,
            decoration: BoxDecoration(
              color: AppStyles.primaryColor.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: AppStyles.primaryColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppStyles.primaryColor.withValues(
                    alpha: 0.1,
                  ),
                  radius: 24,
                  child: const Icon(
                    Icons.receipt_long,
                    color: AppStyles.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppStyles.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Transaction Details', style: AppStyles.titleStyle),
                      const SizedBox(height: AppStyles.spacingXS),
                      Text(
                        'Loaded ${_docs.length} transactions',
                        style: AppStyles.subtitleStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search bar (optional)
          Padding(
            padding: AppStyles.cardPadding,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppStyles.primaryColor,
                ),
                filled: true,
                fillColor: AppStyles.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppStyles.borderRadiusLarge,
                  ),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                // Search functionality would go here
              },
            ),
          ),

          // Table header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppStyles.spacingM,
              vertical: AppStyles.spacingS,
            ),
            child: Text('Transaction Items', style: AppStyles.titleStyle),
          ),

          Expanded(
            child: Card(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              child: _isInitialLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppStyles.primaryColor,
                      ),
                    )
                  : _error != null && _docs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadInitial,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _docs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 64,
                            color: AppStyles.primaryColor.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: AppStyles.spacingM),
                          Text(
                            'No transactions available.',
                            style: AppStyles.subtitleStyle.copyWith(
                              fontSize: AppStyles.fontSizeMedium,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                headingRowColor:
                                    WidgetStateProperty.resolveWith(
                                      (_) => AppStyles.primaryColor.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                columns: const [
                                  DataColumn(
                                    label: Text(
                                      'SOR Number',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Customer',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Account #',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Item',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Qty',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Unit Price',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Subtotal',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'PDF',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: _buildRows(),
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: _isLoadingMore
                              ? const CircularProgressIndicator(
                                  color: AppStyles.primaryColor,
                                )
                              : _hasMore
                              ? OutlinedButton(
                                  onPressed: _loadMore,
                                  child: const Text('Load More'),
                                )
                              : const Text(
                                  'End of transactions',
                                  style: TextStyle(color: Colors.grey),
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      // Optional: Add a floating action button for quick actions
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppStyles.secondaryColor,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Export feature coming soon!'),
              backgroundColor: AppStyles.secondaryColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppStyles.borderRadiusMedium,
                ),
              ),
              margin: const EdgeInsets.all(AppStyles.paddingMedium),
            ),
          );
        },
        child: const Icon(Icons.file_download, color: Colors.white),
      ),
    );
  }

  List<DataRow> _buildRows() {
    final rows = <DataRow>[];

    for (final doc in _docs) {
      final data = doc.data() ?? <String, dynamic>{};
      final items = data['items'] as List<dynamic>? ?? [];

      for (final item in items) {
        rows.add(
          DataRow(
            cells: [
              DataCell(Text(RequisitionFields.sorNumber(data))),
              DataCell(Text(data['customerName'] ?? '')),
              DataCell(Text(data['accountNumber'] ?? '')),
              DataCell(Text(item['name'] ?? '')),
              DataCell(Text(item['quantity'].toString())),
              DataCell(Text('₱${item['unitPrice'] ?? 0}')),
              DataCell(Text('₱${item['subtotal'] ?? 0}')),
              DataCell(
                IconButton(
                  icon: const Icon(
                    Icons.picture_as_pdf,
                    color: AppStyles.secondaryColor,
                  ),
                  tooltip: 'Download PDF',
                  onPressed: () {
                    _generateAndPrintPDF(data);
                  },
                ),
              ),
            ],
          ),
        );
      }
    }

    return rows;
  }
}
