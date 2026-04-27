import 'package:hive/hive.dart';
import 'offline_sync_contract.dart';

part 'queued_sales_requisition.g.dart';

/// Represents a Sales Requisition that is queued for offline sync.
/// This is stored locally in encrypted Hive storage until connectivity is restored.
///
/// Fields map directly to the offline sync contract:
/// - clientGeneratedId: UUIDv7-based idempotency key unique per submission
/// - tenantDatabaseId: Firebase Firestore database ID for this company
/// - userId: Firebase Auth UID of the submitting user
/// - sorDraftPayload: Complete SOR JSON data (all form fields)
/// - status: Current lifecycle state (from OfflineSorStatus enum)
/// - autoRetryCount: Number of automatic retry attempts already consumed (0-9 from backoff schedule)
/// - manualRetryCount: Number of manual retry attempts this submission (capped at 3)
/// - lastSyncAttemptTimestamp: When the last sync was attempted (null = never attempted)
/// - createdTimestamp: When the SOR was created offline
/// - lastManualRetryTimestamp: When user last manually triggered a retry (for cooldown enforcement)
/// - lastError: Error message from the last failed sync attempt
/// - errorCategory: Enum categorizing the error type (auth, network, validation, inventory, email, unknown)
/// - correlationId: Unique trace ID for this submission across logs
/// - rejectionReasons: Per-line rejection details if validation failed (JSON list)
/// - emailStatus: Secondary status tracking email delivery independent of sync status
/// - rollbackAvailableUntil: Timestamp cutoff for rollback eligibility (24 hours after acceptance)
@HiveType(typeId: 0)
class QueuedSalesRequisition {
  @HiveField(0)
  final String clientGeneratedId;

  @HiveField(1)
  final String tenantDatabaseId;

  @HiveField(2)
  final String userId;

  @HiveField(3)
  final Map<String, dynamic> sorDraftPayload;

  @HiveField(4)
  OfflineSorStatus status;

  @HiveField(5)
  int autoRetryCount;

  @HiveField(6)
  int manualRetryCount;

  @HiveField(7)
  DateTime? lastSyncAttemptTimestamp;

  @HiveField(8)
  final DateTime createdTimestamp;

  @HiveField(9)
  DateTime? lastManualRetryTimestamp;

  @HiveField(10)
  String? lastError;

  @HiveField(11)
  OfflineErrorCategory? errorCategory;

  @HiveField(12)
  final String correlationId;

  @HiveField(13)
  String? rejectionReasons;

  @HiveField(14)
  OfflineSorStatus? emailStatus;

  @HiveField(15)
  DateTime? rollbackAvailableUntil;

  QueuedSalesRequisition({
    required this.clientGeneratedId,
    required this.tenantDatabaseId,
    required this.userId,
    required this.sorDraftPayload,
    required this.status,
    required this.correlationId,
    this.autoRetryCount = 0,
    this.manualRetryCount = 0,
    this.lastSyncAttemptTimestamp,
    DateTime? createdTimestamp,
    this.lastManualRetryTimestamp,
    this.lastError,
    this.errorCategory,
    this.rejectionReasons,
    this.emailStatus,
    this.rollbackAvailableUntil,
  }) : createdTimestamp = createdTimestamp ?? DateTime.now();

  /// Creates a copy with updated fields (immutable pattern)
  QueuedSalesRequisition copyWith({
    String? clientGeneratedId,
    String? tenantDatabaseId,
    String? userId,
    Map<String, dynamic>? sorDraftPayload,
    OfflineSorStatus? status,
    int? autoRetryCount,
    int? manualRetryCount,
    DateTime? lastSyncAttemptTimestamp,
    DateTime? createdTimestamp,
    DateTime? lastManualRetryTimestamp,
    String? lastError,
    OfflineErrorCategory? errorCategory,
    String? correlationId,
    String? rejectionReasons,
    OfflineSorStatus? emailStatus,
    DateTime? rollbackAvailableUntil,
  }) {
    return QueuedSalesRequisition(
      clientGeneratedId: clientGeneratedId ?? this.clientGeneratedId,
      tenantDatabaseId: tenantDatabaseId ?? this.tenantDatabaseId,
      userId: userId ?? this.userId,
      sorDraftPayload: sorDraftPayload ?? this.sorDraftPayload,
      status: status ?? this.status,
      correlationId: correlationId ?? this.correlationId,
      autoRetryCount: autoRetryCount ?? this.autoRetryCount,
      manualRetryCount: manualRetryCount ?? this.manualRetryCount,
      lastSyncAttemptTimestamp:
          lastSyncAttemptTimestamp ?? this.lastSyncAttemptTimestamp,
      createdTimestamp: createdTimestamp ?? this.createdTimestamp,
      lastManualRetryTimestamp:
          lastManualRetryTimestamp ?? this.lastManualRetryTimestamp,
      lastError: lastError ?? this.lastError,
      errorCategory: errorCategory ?? this.errorCategory,
      rejectionReasons: rejectionReasons ?? this.rejectionReasons,
      emailStatus: emailStatus ?? this.emailStatus,
      rollbackAvailableUntil:
          rollbackAvailableUntil ?? this.rollbackAvailableUntil,
    );
  }

  /// Increments auto retry count (used by sync worker during backoff schedule)
  void incrementAutoRetryCount() {
    autoRetryCount = (autoRetryCount + 1).clamp(0, 9);
  }

  /// Increments manual retry count (user-triggered, capped at 3)
  void incrementManualRetryCount() {
    if (manualRetryCount < manualRetryLimit) {
      manualRetryCount++;
    }
  }

  /// Checks if manual retry is available (not at limit, not on cooldown)
  bool canManualRetry(DateTime now) {
    if (manualRetryCount >= manualRetryLimit) {
      return false;
    }
    if (lastManualRetryTimestamp != null) {
      final cooldownElapsed = now.difference(lastManualRetryTimestamp!);
      if (cooldownElapsed.inSeconds < manualRetryCooldown.inSeconds) {
        return false;
      }
    }
    return true;
  }

  /// Checks if SOR can still be rolled back (within 24-hour window)
  bool canRollback(DateTime now) {
    if (rollbackAvailableUntil == null) return false;
    return now.isBefore(rollbackAvailableUntil!);
  }

  /// Resets retry counts (useful for manual retry action)
  void resetRetryCounters() {
    autoRetryCount = 0;
    manualRetryCount = 0;
  }

  @override
  String toString() =>
      'QueuedSalesRequisition(clientGeneratedId: $clientGeneratedId, '
      'tenantDatabaseId: $tenantDatabaseId, userId: $userId, '
      'status: ${status.label}, autoRetryCount: $autoRetryCount, '
      'manualRetryCount: $manualRetryCount, correlationId: $correlationId)';
}
