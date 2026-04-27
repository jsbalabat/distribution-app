import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:convert';
import '../services/offline_submission_service.dart';
import '../services/firestore_tenant.dart';
import 'generate_sales_pdf.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  Future<void> _sendAutoRoutedEmailWithRetries({
    required String requisitionId,
    required Map<String, dynamic> requisitionData,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).httpsCallable('sendAutoRoutedRequisitionEmail');
    final pdfBytes = await generateSalesPDF(requisitionData);
    final pdfBase64 = base64Encode(pdfBytes);

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await callable.call(<String, dynamic>{
          'requisitionId': requisitionId,
          'pdfData': pdfBase64,
          'fileName':
              'SOR-${requisitionData['sorNumber'] ?? requisitionId}.pdf',
          'actorDatabaseId': FirestoreTenant.instance.databaseId,
        });
        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('Auto-email failed after 3 attempts: $lastError');
  }

  Future<void> _submitData(
    BuildContext context,
    Map<String, dynamic> formData,
  ) async {
    try {
      final submissionResult = await OfflineSubmissionService.instance
          .submitOrQueue(formData);

      if (submissionResult.wasQueued) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              submissionResult.requiresRelogin
                  ? 'Saved offline. Sign in again before it can sync.'
                  : 'Saved offline. It will sync when connectivity returns.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pushReplacementNamed(context, '/confirmation');
        return;
      }

      await _sendAutoRoutedEmailWithRetries(
        requisitionId: submissionResult.requisitionId,
        requisitionData: formData,
      );
      if (!context.mounted) return;
      Navigator.pushReplacementNamed(context, '/confirmation');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> formData =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    return Scaffold(
      appBar: AppBar(title: const Text("Review Submission")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ...formData.entries.map(
              (entry) => ListTile(
                title: Text(entry.key),
                subtitle: Text(entry.value.toString()),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _submitData(context, formData),
              child: const Text("Submit"),
            ),
          ],
        ),
      ),
    );
  }
}
