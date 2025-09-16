import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> generateSalesPDF(Map<String, dynamic> data) async {
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
          'Date: ${data['timeStamp']?.toDate().toString().split(' ')[0] ?? ''}',
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: [
            'Item Description',
            'Item Code',
            'Quantity',
            'Unit Price (in pesos)',
          ],
          data: items.map((item) {
            return [
              item['name'] ?? '',
              item['code'] ?? '',
              item['quantity'].toString(),
              '${item['unitPrice']}',
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Remarks: ${data['remarks'] ?? 'No remarks'}'),
        pw.SizedBox(height: 10),
        pw.Text(
          'Total Amount (in pesos): ${data['totalAmount'] ?? '0.00'}',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  return pdf.save();
}
