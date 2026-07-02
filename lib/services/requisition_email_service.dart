import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

import '../screens/generate_sales_pdf.dart';
import '../utils/app_logger.dart';

/// Builds the requisition PDF and invokes the server-side approval-email
/// callable. Shared by the online submit path (form) and the offline sync
/// worker so both send the identical email through one code path.
class RequisitionEmailService {
  RequisitionEmailService._();

  static final RequisitionEmailService instance = RequisitionEmailService._();

  // Must match the deployed function's region in functions/index.js.
  static const String _region = 'asia-southeast1';
  // Client-side attempts before giving up; the queue's emailStatus lets a
  // failed send be retried later via the resend path.
  static const int _maxAttempts = 3;

  /// Generates the PDF from [requisitionData] and calls
  /// `sendAutoRoutedRequisitionEmail`, retrying transient failures. Throws if
  /// every attempt fails so the caller can record the outcome.
  /// [invocationContext] tags the origin ('form_submit' vs 'sync_post_accept')
  /// for server-side logging.
  Future<void> sendAutoRoutedEmail({
    required String requisitionId,
    required Map<String, dynamic> requisitionData,
    required String actorDatabaseId,
    required String invocationContext,
  }) async {
    final callable = FirebaseFunctions.instanceFor(
      region: _region,
    ).httpsCallable('sendAutoRoutedRequisitionEmail');

    final pdfBytes = await generateSalesPDF(requisitionData);
    final pdfBase64 = base64Encode(pdfBytes);
    final fileName = 'SOR-${requisitionData['sorNumber'] ?? requisitionId}.pdf';

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        await callable.call(<String, dynamic>{
          'requisitionId': requisitionId,
          'pdfData': pdfBase64,
          'fileName': fileName,
          'actorDatabaseId': actorDatabaseId,
          'invocationContext': invocationContext,
        });
        return;
      } catch (error) {
        lastError = error;
        AppLogger.warning(
          'Auto-email attempt $attempt/$_maxAttempts failed for $requisitionId',
          tag: 'AUTO_EMAIL',
        );
      }
    }

    throw Exception('Auto-email failed after $_maxAttempts attempts: $lastError');
  }
}
