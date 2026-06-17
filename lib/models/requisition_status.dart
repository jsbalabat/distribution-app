import '../utils/requisition_fields.dart';

/// Visual severity bucket for an invoice status; the badge widget maps this to a tint.
enum RequisitionStatusSeverity { success, warning, danger, info, neutral }

/// The single unified status shown for a sales requisition (invoice).
enum RequisitionStatusKind {
  archived,
  deliveryFailed,
  sending,
  awaitingApproval,
  cleared,
  emailOff,
  notSent,
}

/// One status that collapses a requisition's three real status dimensions
/// (approval routing, email delivery, soft-delete) into something a user can act on.
class RequisitionStatus {
  final RequisitionStatusKind kind;
  final String label;
  final String detail;
  final RequisitionStatusSeverity severity;

  const RequisitionStatus({
    required this.kind,
    required this.label,
    required this.detail,
    required this.severity,
  });

  /// Evaluated most-urgent-first so the badge always surfaces the state that
  /// needs attention (a failed delivery outranks "needs approval", and so on).
  factory RequisitionStatus.fromRequisition(Map<String, dynamic> data) {
    if (RequisitionFields.isDeleted(data)) {
      return const RequisitionStatus(
        kind: RequisitionStatusKind.archived,
        label: 'Archived',
        detail: 'This requisition was archived and is kept for history.',
        severity: RequisitionStatusSeverity.neutral,
      );
    }

    final email = RequisitionFields.emailStatus(data);
    final needsApproval =
        RequisitionFields.approvalRoute(data) == 'approval_required';

    if (email == 'failed') {
      return RequisitionStatus(
        kind: RequisitionStatusKind.deliveryFailed,
        label: 'Delivery failed',
        detail: needsApproval
            ? 'Needs approval, but the notification email failed. Retry available.'
            : 'The notification email failed to send. Retry available.',
        severity: RequisitionStatusSeverity.danger,
      );
    }

    if (email == 'queued' || email == 'pending' || email == 'sending') {
      return const RequisitionStatus(
        kind: RequisitionStatusKind.sending,
        label: 'Sending…',
        detail: 'The notification email is being sent.',
        severity: RequisitionStatusSeverity.info,
      );
    }

    if (email == 'sent') {
      if (needsApproval) {
        return const RequisitionStatus(
          kind: RequisitionStatusKind.awaitingApproval,
          label: 'Awaiting approval',
          detail: 'Sent to the approver — waiting on their decision.',
          severity: RequisitionStatusSeverity.warning,
        );
      }
      return const RequisitionStatus(
        kind: RequisitionStatusKind.cleared,
        label: 'Cleared',
        detail: 'No issues flagged — recorded and the email was sent.',
        severity: RequisitionStatusSeverity.success,
      );
    }

    if (email == 'skipped') {
      return const RequisitionStatus(
        kind: RequisitionStatusKind.emailOff,
        label: 'Email off',
        detail: 'Auto-email is disabled in settings, so no email was sent.',
        severity: RequisitionStatusSeverity.neutral,
      );
    }

    return const RequisitionStatus(
      kind: RequisitionStatusKind.notSent,
      label: 'Not sent',
      detail: 'No email has been dispatched for this requisition yet.',
      severity: RequisitionStatusSeverity.neutral,
    );
  }
}
