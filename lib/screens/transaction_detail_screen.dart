import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Color scheme matching the dashboard
const Color primaryColor = Color(0xFF5E4BA6);
const Color secondaryColor = Color(0xFFE55986);
const Color backgroundColor = Color(0xFFF2EDFF);
const Color cardColor = Colors.white;
const Color textColor = Color(0xFF333333);
const Color subtitleColor = Color(0xFF666666);

Future<void> _generateAndPrintPDF(Map<String, dynamic> data) async {
  final pdf = pw.Document();

  final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

  pdf.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text(
          'Sales Requisition Report',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text('SOR #: ${data['sorNumber']}'),
        pw.Text('Customer: ${data['customerName']}'),
        pw.Text('Account #: ${data['accountNumber']}'),
        pw.Text(
          'Date: ${data['timestamp']?.toDate().toString().split(' ')[0]}',
        ),
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

class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'All Item Transactions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: primaryColor,
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
                  backgroundColor: secondaryColor,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.all(10),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () {
              // Refresh functionality would go here
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header/Summary section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: primaryColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: primaryColor.withValues(alpha: 0.1),
                  radius: 24,
                  child: const Icon(
                    Icons.receipt_long,
                    color: primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Transaction Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('salesRequisitions')
                            .where('userID', isEqualTo: uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          int totalTransactions = snapshot.hasData
                              ? snapshot.data!.docs.length
                              : 0;
                          return Text(
                            'Showing all $totalTransactions transaction records',
                            style: const TextStyle(color: subtitleColor),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search bar (optional)
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(Icons.search, color: primaryColor),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'Transaction Items',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),

          // Table (preserved as is)
          Expanded(
            child: Card(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('salesRequisitions')
                    .where('userID', isEqualTo: uid)
                    .orderBy('timeStamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: primaryColor),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 64,
                            color: primaryColor.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No transactions available.',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final rows = <DataRow>[];

                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final items = data['items'] as List<dynamic>? ?? [];

                    // Format the timestamp for better display
                    // final timestamp = data['timeStamp'] as Timestamp?;
                    // final date = timestamp?.toDate();
                    // final formattedDate = date != null
                    //     ? DateFormat('MMM d, yyyy').format(date)
                    //     : 'Unknown Date';

                    for (var item in items) {
                      rows.add(
                        DataRow(
                          cells: [
                            DataCell(Text(data['sorNumber'] ?? '')),
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
                                  color:
                                      secondaryColor, // Changed from red to match theme
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

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.resolveWith(
                          (_) => primaryColor.withValues(
                            alpha: 0.1,
                          ), // Changed from grey to theme color
                        ),
                        columns: const [
                          DataColumn(
                            label: Text(
                              'SOR Number',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Customer',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Account #',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Item',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Qty',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Unit Price',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Subtotal',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'PDF',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                        rows: rows,
                        // Core table styling preserved
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      // Optional: Add a floating action button for quick actions
      floatingActionButton: FloatingActionButton(
        backgroundColor: secondaryColor,
        onPressed: () {
          // Export to Excel or perform other actions
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Export feature coming soon!'),
              backgroundColor: secondaryColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              margin: const EdgeInsets.all(10),
            ),
          );
        },
        child: const Icon(Icons.file_download, color: Colors.white),
      ),
    );
  }
}
