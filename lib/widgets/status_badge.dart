import 'package:flutter/material.dart';
import '../models/requisition_status.dart';
import '../styles/app_styles.dart';

/// Compact pill that visualises a [RequisitionStatus] with a semantic tint, an
/// icon, and a label so the status reads even in the app's monochrome theme.
class StatusBadge extends StatelessWidget {
  final RequisitionStatus status;

  /// Slightly smaller variant for dense list rows.
  final bool dense;

  const StatusBadge({super.key, required this.status, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(status.severity);
    final fontSize = dense ? 11.0 : 12.0;
    final iconSize = dense ? 13.0 : 15.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppStyles.borderRadiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(status.kind), size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(RequisitionStatusSeverity severity) {
    switch (severity) {
      case RequisitionStatusSeverity.success:
        return AppStyles.statusSuccess;
      case RequisitionStatusSeverity.warning:
        return AppStyles.statusWarning;
      case RequisitionStatusSeverity.danger:
        return AppStyles.statusDanger;
      case RequisitionStatusSeverity.info:
        return AppStyles.statusInfo;
      case RequisitionStatusSeverity.neutral:
        return AppStyles.statusNeutral;
    }
  }

  static IconData _iconFor(RequisitionStatusKind kind) {
    switch (kind) {
      case RequisitionStatusKind.cleared:
        return Icons.check_circle;
      case RequisitionStatusKind.awaitingApproval:
        return Icons.hourglass_top;
      case RequisitionStatusKind.deliveryFailed:
        return Icons.error_outline;
      case RequisitionStatusKind.sending:
        return Icons.schedule;
      case RequisitionStatusKind.emailOff:
        return Icons.do_not_disturb_on_outlined;
      case RequisitionStatusKind.notSent:
        return Icons.radio_button_unchecked;
      case RequisitionStatusKind.archived:
        return Icons.archive_outlined;
      case RequisitionStatusKind.queuedOffline:
        return Icons.cloud_upload_outlined;
      case RequisitionStatusKind.uploading:
        return Icons.sync;
      case RequisitionStatusKind.needsRelogin:
        return Icons.lock_outline;
      case RequisitionStatusKind.syncRejected:
        return Icons.report_gmailerrorred;
      case RequisitionStatusKind.uploadFailed:
        return Icons.cloud_off;
    }
  }
}
