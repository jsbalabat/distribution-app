import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/queued_sales_requisition.dart';
import '../models/requisition_status.dart';
import '../styles/app_styles.dart';
import '../utils/requisition_fields.dart';
import 'status_badge.dart';

/// Dashboard card for a submission still sitting in the local offline queue.
/// Styled with an info-tinted outline so it reads as "saved on this device,
/// not yet uploaded" — distinct from the synced records below it.
class OfflineQueueCard extends StatelessWidget {
  final QueuedSalesRequisition item;
  final NumberFormat currencyFormat;

  const OfflineQueueCard({
    super.key,
    required this.item,
    required this.currencyFormat,
  });

  @override
  Widget build(BuildContext context) {
    final payload = item.sorDraftPayload;
    final status = RequisitionStatus.fromOfflineStatus(
      item.status,
      lastError: item.lastError,
    );
    final customerName = (payload['customerName'] ?? 'Unknown Customer')
        .toString();
    final sorNumber = RequisitionFields.sorNumber(payload);
    final totalAmount = RequisitionFields.totalAmount(payload);
    // The queue only holds local creation time, so that is what we show.
    final queuedAt = DateFormat(
      'MMM d, yyyy • h:mm a',
    ).format(item.createdTimestamp);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: AppStyles.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppStyles.statusInfo.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppStyles.statusInfo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.cloud_upload_outlined,
                    color: AppStyles.statusInfo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'SOR #: $sorNumber',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusBadge(status: status, dense: true),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  queuedAt,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const Spacer(),
                Text(
                  currencyFormat.format(totalAmount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppStyles.primaryColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              status.detail,
              style: const TextStyle(
                color: AppStyles.textSecondaryColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
