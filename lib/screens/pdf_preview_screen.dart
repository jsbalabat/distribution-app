import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class PdfPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;

  const PdfPreviewScreen({super.key, required this.pdfBytes});

  Future<void> _savePdf(BuildContext context) async {
    // Ask for permission if not granted
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Storage permission denied.")),
        );
        return;
      }
    }

    try {
      final directory = await getExternalStorageDirectory();
      final path = '${directory!.path}/sales_requisition.pdf';
      final file = File(path);
      await file.writeAsBytes(pdfBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved to: $path')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Preview'),
      ),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: false,
        allowSharing: false,
        actions: const [],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text("Save PDF"),
                onPressed: () => _savePdf(context),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.share),
                label: const Text("Share PDF"),
                onPressed: () async => await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: 'sales_requisition.pdf',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}