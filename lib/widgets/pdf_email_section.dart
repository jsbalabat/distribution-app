import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:convert';
import '../styles/app_styles.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
            // Title
            pw.Text(
              'Sales Requisition Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),

            // Header Information
            pw.Text('SOR #: ${widget.sorNumber}'),
            pw.Text('Customer: ${widget.selectedCustomer?['name'] ?? ''}'),
            pw.Text(
              'Account #: ${widget.selectedCustomer?['accountNumber'] ?? ''}',
            ),
            pw.Text('Date: $formattedDate'),
            pw.SizedBox(height: 20),

            // Items Table
            pw.TableHelper.fromTextArray(
              headers: [
                'Item Description',
                'Item Code',
                'Quantity',
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
                  subtotal.toStringAsFixed(2),
                ];
              }).toList(),
            ),

            pw.SizedBox(height: 10),

            // Remarks
            pw.Text('Remarks: ${widget.remarks ?? 'No remarks'}'),

            pw.SizedBox(height: 10),

            // Total Amount
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
        // Web download using dart:html (if you add it back)
        // For now, show message that download is not available
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PDF download not available on web. Use email instead.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        // Mobile: Save to downloads (implement with path_provider)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF download not implemented for mobile yet'),
            backgroundColor: Colors.orange,
          ),
        );
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
      // Check if user is authenticated
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Convert PDF bytes to base64
      final base64Pdf = base64Encode(_pdfBytes!);

      // Prepare file name
      final fileName =
          'SOR_${widget.sorNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // Call Firebase Cloud Function
      final callable = FirebaseFunctions.instance.httpsCallable(
        'sendSalesRequisitionEmail',
      );

      final result = await callable.call({
        'to': _emailController.text.trim(),
        'subject': 'Sales Requisition Order - ${widget.sorNumber}',
        'pdfData': base64Pdf,
        'fileName': fileName,
        'customerName': widget.selectedCustomer?['name'] ?? 'Valued Customer',
        'sorNumber': widget.sorNumber ?? 'N/A',
      });

      // Check if email was sent successfully
      if (result.data['success'] == true) {
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
      } else {
        throw Exception('Failed to send email: ${result.data['message']}');
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _isGeneratingPdf = false;
      });

      String errorMessage = 'Error sending email';

      switch (e.code) {
        case 'unauthenticated':
          errorMessage = 'You must be logged in to send emails';
          break;
        case 'invalid-argument':
          errorMessage = 'Invalid email address or missing data';
          break;
        case 'failed-precondition':
          errorMessage = 'Email service is not configured properly';
          break;
        case 'internal':
          errorMessage = 'Server error: ${e.message}';
          break;
        default:
          errorMessage = 'Error: ${e.message}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
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
            duration: const Duration(seconds: 5),
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
                if (!kIsWeb)
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
