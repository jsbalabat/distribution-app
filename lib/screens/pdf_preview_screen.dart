import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PdfPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;

  const PdfPreviewScreen({super.key, required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async => await Printing.sharePdf(
              bytes: pdfBytes,
              filename: 'sales_requisition.pdf',
            ),
            tooltip: 'Share PDF',
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: false,
        allowSharing: false,
        actions: const [], // Remove default bottom bar buttons
      ),
    );
  }
}