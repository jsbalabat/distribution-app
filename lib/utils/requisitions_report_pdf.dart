import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/requisition_status.dart';
import 'requisition_fields.dart';

/// Builds a combined report PDF of the caller's requisitions — a paginated table
/// (SOR No., Date, Customer, Total, Status, Remarks), newest first, with a count
/// header and a total-value footer. Rendered on-device: it only ever covers the
/// signed-in user's own records, so there is no need to involve the server.
Future<Uint8List> generateRequisitionsReportPDF(
  List<Map<String, dynamic>> requisitions, {
  String? heading,
}) async {
  final pdf = pw.Document();
  final dateFmt = DateFormat('yyyy-MM-dd');
  final money = NumberFormat('#,##0.00');

  // Newest first, matching the dashboard's order.
  final rows = [...requisitions]..sort((a, b) {
      final ta = RequisitionFields.timestamp(a);
      final tb = RequisitionFields.timestamp(b);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

  final totalValue = rows.fold<double>(
    0,
    (sum, r) => sum + RequisitionFields.totalAmount(r),
  );

  pdf.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text(
          heading ?? 'My Sales Requisitions',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated ${dateFmt.format(DateTime.now())}  -  '
          '${rows.length} requisition(s)',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: const {3: pw.Alignment.centerRight},
          headers: const [
            'SOR No.',
            'Date',
            'Customer',
            'Total (pesos)',
            'Status',
            'Remarks',
          ],
          data: rows.map((r) {
            final ts = RequisitionFields.timestamp(r);
            final status = RequisitionStatus.fromRequisition(r);
            final remarks = [r['remark1'], r['remark2']]
                .where((v) => v != null && v.toString().trim().isNotEmpty)
                .map((v) => v.toString())
                .join(', ');
            return [
              RequisitionFields.sorNumber(r),
              ts != null ? dateFmt.format(ts) : '',
              (r['customerName'] ?? '').toString(),
              money.format(RequisitionFields.totalAmount(r)),
              // Standard-14 Helvetica has no ellipsis glyph; keep labels ASCII.
              status.label.replaceAll('…', '...'),
              remarks.isEmpty ? '-' : remarks,
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              'Total value (pesos): ${money.format(totalValue)}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    ),
  );

  return pdf.save();
}
