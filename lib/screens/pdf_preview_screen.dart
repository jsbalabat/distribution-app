import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../styles/app_styles.dart';

class PdfPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;

  const PdfPreviewScreen({super.key, required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'PDF Preview',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppStyles.primaryColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt, color: Colors.white),
            tooltip: 'Print document',
            onPressed: () async {
              await Printing.layoutPdf(onLayout: (format) => pdfBytes);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppStyles.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf,
                    color: AppStyles.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sales Requisition Document',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppStyles.textColor,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Pinch or double-tap to zoom',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppStyles.subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // PDF Preview
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppStyles.cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PdfPreview(
                  build: (format) async => pdfBytes,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  allowPrinting: false,
                  allowSharing: false,
                  pdfFileName: 'sales_requisition.pdf',
                  scrollViewDecoration: const BoxDecoration(
                    color: AppStyles.backgroundColor,
                  ),
                  padding: EdgeInsets.zero,
                  previewPageMargin: const EdgeInsets.all(8),
                  actions: const [],
                  maxPageWidth: 700,
                  canDebug: false,
                  pdfPreviewPageDecoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  // Maintain scroll position across rebuilds
                  shouldRepaint: false,
                  onError: (context, error) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 50,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load PDF document',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppStyles.textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppStyles.primaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      foregroundColor: AppStyles.primaryColor,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppStyles.secondaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      await Printing.sharePdf(
                        bytes: pdfBytes,
                        filename: 'sales_requisition.pdf',
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
