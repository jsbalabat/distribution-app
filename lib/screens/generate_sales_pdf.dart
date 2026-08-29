import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../utils/requisition_fields.dart';

/// On-device copy used for the pre-submit preview and dashboard re-downloads.
/// The emailed PDF is rendered by buildRequisitionPdf in functions/index.js —
/// keep the two layouts in sync.
Future<Uint8List> generateSalesPDF(Map<String, dynamic> data) async {
  final pdf = pw.Document();

  final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
  final ts = RequisitionFields.timestamp(data);

  pdf.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text(
          'Sales Requisition',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text('SOR #: ${RequisitionFields.sorNumber(data)}'),
        pw.Text('Customer: ${data['customerName']}'),
        pw.Text('Account #: ${data['accountNumber']}'),
        pw.Text('Date: ${ts?.toString().split(' ')[0] ?? ''}'),
        pw.Text('Sender: ${data['accountNumber']}'),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: [
            'Item Description',
            'Item Code',
            'Quantity',
            'Unit Price',
            'Amount (in pesos)',
          ],
          data: items.map((item) {
            final quantity = (item['quantity'] ?? 0).toDouble();
            final unitPrice = (item['unitPrice'] ?? 0).toDouble();
            final subtotal = quantity * unitPrice;

            return [
              item['name'] ?? '',
              item['code'] ?? '',
              quantity.toStringAsFixed(2),
              unitPrice.toStringAsFixed(2),
              subtotal.toStringAsFixed(2),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Remarks: ${_remarksOrNone(data)}'),
        pw.SizedBox(height: 10),
        pw.Text(
          'Total Amount (in pesos): ${RequisitionFields.totalAmount(data).toStringAsFixed(2)}',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  return pdf.save();
}

String _remarksOrNone(Map<String, dynamic> data) {
  final line = RequisitionFields.remarksLine(data);
  return line.isEmpty ? 'No remarks' : line;
}
