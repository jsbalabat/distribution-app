import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('All Item Transactions')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('salesRequisitions')
            .orderBy('timeStamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No transactions available.'));
          }

          final rows = <DataRow>[];

          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final items = data['items'] as List<dynamic>? ?? [];

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
                          color: Colors.red,
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
            child: DataTable(
              headingRowColor: WidgetStateColor.resolveWith(
                (_) => Colors.grey.shade200,
              ),
              columns: const [
                DataColumn(label: Text('SOR Number')),
                DataColumn(label: Text('Customer')),
                DataColumn(label: Text('Account #')),
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Unit Price')),
                DataColumn(label: Text('Subtotal')),
                DataColumn(label: Text('PDF')),
              ],
              rows: rows,
            ),
          );
        },
      ),
    );
  }
}
