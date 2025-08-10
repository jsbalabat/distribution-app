import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pdf_preview_screen.dart';
import 'generate_sales_pdf.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _logout(BuildContext context) async {
    final bool? didRequestLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
            ),
            ElevatedButton(
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

  // void _navigateToEditForm(BuildContext context, String docId, Map<String, dynamic> data) {
  //   Navigator.pushNamed(
  //     context,
  //     '/editForm',
  //     arguments: {'docId': docId, 'data': data},
  //   );
  // }

  void _confirmDelete(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('salesRequisitions')
                  .doc(docId)
                  .delete();
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Record deleted.')));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('salesRequisitions')
            .where('userID', isEqualTo: uid)
            .orderBy('timeStamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong.'));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'There are no entries here yet.',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['timeStamp'] as Timestamp?;
              final date = timestamp?.toDate();
              final formattedDate = date != null
                  ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                  : 'Unknown Date';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: ExpansionTile(
                  title: Text(data['customerName'] ?? 'Unknown Customer'),
                  subtitle: Text('Date: $formattedDate'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SOR #: ${data['sorNumber'] ?? ''}'),
                          Text('Account #: ${data['accountNumber'] ?? ''}'),
                          Text('Area: ${data['area'] ?? ''}'),
                          Text('Payment Terms: ${data['paymentTerms'] ?? ''}'),
                          Text(
                            'Delivery Instruction: ${data['deliveryInstruction'] ?? ''}',
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Items:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          ...List<Widget>.from(
                            (data['items'] as List<dynamic>? ?? []).map((item) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${item['name']} - Qty: ${item['quantity']} @ ₱${item['unitPrice']} = ₱${item['subtotal']}',
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total Amount: ₱${data['totalAmount']?.toStringAsFixed(2) ?? '0.00'}',
                          ),
                          Text('Remark 1: ${data['remark1'] ?? ''}'),
                          Text('Remark 2: ${data['remark2'] ?? ''}'),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('Preview PDF'),
                                onPressed: () async {
                                  final pdfBytes = await generateSalesPDF(data);
                                  if (!context.mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PdfPreviewScreen(pdfBytes: pdfBytes),
                                    ),
                                  );
                                },
                              ),
                              // IconButton(
                              //   icon: const Icon(Icons.edit),
                              //   tooltip: 'Edit',
                              //   onPressed: () => _navigateToEditForm(context, doc.id, data),
                              // ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                tooltip: 'Delete',
                                onPressed: () =>
                                    _confirmDelete(context, doc.id),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
