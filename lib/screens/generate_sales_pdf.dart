import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> generateSalesPDF(Map<String, dynamic> data) async {
  final pdf = pw.Document();

  final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

  pdf.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text('Sales Requisition Report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Text('SOR #: ${data['sorNumber']}'),
        pw.Text('Customer: ${data['customerName']}'),
        pw.Text('Account #: ${data['accountNumber']}'),
        pw.Text('Date: ${data['timeStamp']?.toDate().toString().split(' ')[0] ?? ''}'),
        pw.SizedBox(height: 20),
        pw.Table.fromTextArray(
          headers: ['Item', 'Quantity', 'Unit Price', 'Subtotal'],
          data: items.map((item) {
            return [
              item['name'] ?? '',
              item['quantity'].toString(),
              '₱${item['unitPrice']}',
              '₱${item['subtotal']}'
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Remarks: ${data['remarks'] ?? ''}'),
      ],
    ),
  );

  return pdf.save();
}