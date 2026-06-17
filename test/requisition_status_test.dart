import 'package:flutter_test/flutter_test.dart';
import 'package:new_test_store/models/requisition_status.dart';

void main() {
  group('RequisitionStatus.fromRequisition', () {
    test('archived wins over every other dimension when isDeleted', () {
      final status = RequisitionStatus.fromRequisition({
        'isDeleted': true,
        'emailStatus': 'sent',
        'approvalRoute': 'approval_required',
      });

      expect(status.kind, RequisitionStatusKind.archived);
      expect(status.severity, RequisitionStatusSeverity.neutral);
    });

    test('delivery failure outranks approval routing', () {
      final status = RequisitionStatus.fromRequisition({
        'emailStatus': 'failed',
        'approvalRoute': 'approval_required',
      });

      expect(status.kind, RequisitionStatusKind.deliveryFailed);
      expect(status.severity, RequisitionStatusSeverity.danger);
      expect(status.detail, contains('Needs approval'));
    });

    test('queued and pending both map to sending', () {
      expect(
        RequisitionStatus.fromRequisition({'emailStatus': 'queued'}).kind,
        RequisitionStatusKind.sending,
      );
      expect(
        RequisitionStatus.fromRequisition({'emailStatus': 'pending'}).kind,
        RequisitionStatusKind.sending,
      );
    });

    test('sent + approval_required maps to awaiting approval', () {
      final status = RequisitionStatus.fromRequisition({
        'emailStatus': 'sent',
        'approvalRoute': 'approval_required',
      });

      expect(status.kind, RequisitionStatusKind.awaitingApproval);
      expect(status.severity, RequisitionStatusSeverity.warning);
    });

    test('sent + auto_clear maps to cleared', () {
      final status = RequisitionStatus.fromRequisition({
        'emailStatus': 'sent',
        'approvalRoute': 'auto_clear',
      });

      expect(status.kind, RequisitionStatusKind.cleared);
      expect(status.severity, RequisitionStatusSeverity.success);
    });

    test('falls back to legacy autoEmailStatus when emailStatus is absent', () {
      final status = RequisitionStatus.fromRequisition({
        'autoEmailStatus': 'sent',
        'approvalRoute': 'auto_clear',
      });

      expect(status.kind, RequisitionStatusKind.cleared);
    });

    test('skipped maps to email off', () {
      final status = RequisitionStatus.fromRequisition({
        'emailStatus': 'skipped',
      });

      expect(status.kind, RequisitionStatusKind.emailOff);
      expect(status.severity, RequisitionStatusSeverity.neutral);
    });

    test('missing status maps to not sent', () {
      final status = RequisitionStatus.fromRequisition({});

      expect(status.kind, RequisitionStatusKind.notSent);
      expect(status.severity, RequisitionStatusSeverity.neutral);
    });

    test('uppercase and padded values are normalised', () {
      final status = RequisitionStatus.fromRequisition({
        'emailStatus': '  SENT  ',
        'approvalRoute': '  APPROVAL_REQUIRED ',
      });

      expect(status.kind, RequisitionStatusKind.awaitingApproval);
    });
  });
}
