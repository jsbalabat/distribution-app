import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';
import '../styles/app_styles.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'package:intl/intl.dart';

class PdfEmailSection extends StatefulWidget {
  final Map<String, dynamic>? selectedCustomer;
  final List<Map<String, dynamic>> selectedItems;
  final String? sorNumber;
  final DateTime? requestDate;
  final DateTime? dispatchDate;
  final DateTime? invoiceDate;
  final double totalAmount;
  final String? remarks;
  final Function(bool) onEmailSent;

  const PdfEmailSection({
    super.key,
    required this.selectedCustomer,
    required this.selectedItems,
    required this.sorNumber,
    required this.requestDate,
    required this.dispatchDate,
    required this.invoiceDate,
    required this.totalAmount,
    this.remarks,
    required this.onEmailSent,
  });

  @override
  State<PdfEmailSection> createState() => _PdfEmailSectionState();
}

class _PdfEmailSectionState extends State<PdfEmailSection> {
  bool _isGeneratingPdf = false;
  bool _isPdfGenerated = false;
  bool _isEmailSent = false;
  Uint8List? _pdfBytes;
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill email if available
    _emailController.text = widget.selectedCustomer?['email'] ?? '';
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      // Generate PDF using the same format as generate_sales_pdf.dart
      final pdf = pw.Document();
      final items = widget.selectedItems;

      // Format date
      final dateFormat = DateFormat('yyyy-MM-dd');
      final formattedDate = widget.requestDate != null
          ? dateFormat.format(widget.requestDate!)
          : '';

      pdf.addPage(
        pw.MultiPage(
          build: (context) => [
            // Title - matching generate_sales_pdf.dart
            pw.Text(
              'Sales Requisition Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),

            // Header Information - matching generate_sales_pdf.dart
            pw.Text('SOR #: ${widget.sorNumber}'),
            pw.Text('Customer: ${widget.selectedCustomer?['name'] ?? ''}'),
            pw.Text(
              'Account #: ${widget.selectedCustomer?['accountNumber'] ?? ''}',
            ),
            pw.Text('Date: $formattedDate'),

            pw.SizedBox(height: 20),

            // Items Table - matching generate_sales_pdf.dart format exactly
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

            // Remarks - matching generate_sales_pdf.dart
            pw.Text('Remarks: ${widget.remarks ?? 'No remarks'}'),

            pw.SizedBox(height: 10),

            // Total Amount - matching generate_sales_pdf.dart
            pw.Text(
              'Total Amount (in pesos): ${widget.totalAmount.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();

      setState(() {
        _pdfBytes = bytes;
        _isPdfGenerated = true;
        _isGeneratingPdf = false;
      });
    } catch (e) {
      setState(() {
        _isGeneratingPdf = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadPdf() async {
    if (_pdfBytes == null) return;

    try {
      if (kIsWeb) {
        final fileName =
            'SOR_${widget.sorNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final blob = web.Blob(
          [_pdfBytes!.toJS].toJS,
          web.BlobPropertyBag(type: 'application/pdf'),
        );
        final url = web.URL.createObjectURL(blob);

        final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
        anchor.href = url;
        anchor.download = fileName;
        anchor.style.display = 'none';

        web.document.body?.appendChild(anchor);
        anchor.click();
        web.document.body?.removeChild(anchor);

        web.URL.revokeObjectURL(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF downloaded successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendEmail() async {
    if (_pdfBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please generate PDF first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Email validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(_emailController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 2));

      // TODO: Implement actual email sending here
      // Example integration points:
      //
      // Firebase Cloud Functions:
      // await FirebaseFunctions.instance
      //     .httpsCallable('sendSalesRequisitionEmail')
      //     .call({
      //       'to': _emailController.text,
      //       'subject': 'Sales Requisition Order - ${widget.sorNumber}',
      //       'pdfData': base64.encode(_pdfBytes!),
      //       'fileName': 'SOR_${widget.sorNumber}.pdf',
      //       'customerName': widget.selectedCustomer?['name'],
      //       'sorNumber': widget.sorNumber,
      //     });
      //
      // Or your backend API:
      // final response = await http.post(
      //   Uri.parse('https://your-api.com/send-email'),
      //   headers: {'Content-Type': 'application/json'},
      //   body: jsonEncode({
      //     'email': _emailController.text,
      //     'subject': 'Sales Requisition Order - ${widget.sorNumber}',
      //     'pdfBase64': base64.encode(_pdfBytes!),
      //     'fileName': 'SOR_${widget.sorNumber}.pdf',
      //   }),
      // );

      setState(() {
        _isEmailSent = true;
        _isGeneratingPdf = false;
      });

      widget.onEmailSent(true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Email sent successfully to ${_emailController.text}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isGeneratingPdf = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppStyles.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppStyles.primaryColor.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppStyles.primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Generate and email the PDF to proceed to the next step',
                  style: TextStyle(color: AppStyles.textColor, fontSize: 14),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Generate PDF Button
        if (!_isPdfGenerated)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGeneratingPdf ? null : _generatePdf,
              icon: _isGeneratingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_isGeneratingPdf ? 'Generating...' : 'Generate PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyles.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

        // PDF Generated Success
        if (_isPdfGenerated) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'PDF generated successfully!',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _downloadPdf,
                  icon: const Icon(Icons.download, color: Colors.green),
                  tooltip: 'Download PDF',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Email section
          const Text(
            'Send PDF via Email',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppStyles.textColor,
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: 'Email Address',
              hintText: 'Enter recipient email',
              prefixIcon: const Icon(Icons.email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            keyboardType: TextInputType.emailAddress,
            enabled: !_isEmailSent,
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isEmailSent || _isGeneratingPdf ? null : _sendEmail,
              icon: _isGeneratingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(_isEmailSent ? Icons.check : Icons.send),
              label: Text(
                _isGeneratingPdf
                    ? 'Sending...'
                    : (_isEmailSent ? 'Email Sent' : 'Send Email'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isEmailSent
                    ? Colors.green
                    : AppStyles.secondaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          if (_isEmailSent) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mark_email_read, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Email sent successfully!',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Sent to: ${_emailController.text}',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
