import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' show Random;
import '../models/queued_sales_requisition.dart';
import '../models/offline_sync_contract.dart';
import '../models/offline_sync_adapters.dart';

/// Manages local encrypted storage of queued Sales Requisitions.
///
/// Uses Hive with AES-256-GCM encryption for sensitive data at rest.
/// Encryption key is secured using platform-specific secure storage.
///
/// Responsibilities:
/// 1. Initialize encryption and Hive
/// 2. Store/retrieve/delete queued SORs
/// 3. Track retry state (auto and manual)
/// 4. Enforce retention policies (1-day history)
/// 5. Maintain audit log of queue operations
class QueueRepository {
  static const String _boxName = 'offline_sor_queue';
  static const String _auditBoxName = 'offline_queue_audit';
  static const String _encryptionKeyName = 'offline_queue_encryption_key';
  static const String _secureStorageService = 'offline_queue_storage';
  static const Duration _queueRetentionDuration = Duration(days: 1);

  late final Box<QueuedSalesRequisition> _queueBox;
  late final Box<String> _auditBox;
  final FlutterSecureStorage _secureStorage;
  bool _initialized = false;

  QueueRepository({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Initializes Hive, loads or generates encryption key, and opens boxes.
  /// Must be called once during app startup before any queue operations.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Register adapters for custom types
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(OfflineSorStatusAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(OfflineErrorCategoryAdapter());
      }

      // Initialize Hive
      await Hive.initFlutter();

      // Get or create encryption key
      final encryptionKey = await _getOrCreateEncryptionKey();

      // Open encrypted box for queue items
      _queueBox = await Hive.openBox<QueuedSalesRequisition>(
        _boxName,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );

      // Open unencrypted audit log (timestamps and IDs only, no sensitive data)
      _auditBox = await Hive.openBox<String>(_auditBoxName);

      _initialized = true;
      await _auditLog('QUEUE_INITIALIZED', {
        'timestamp': DateTime.now().toIso8601String(),
        'queueItemCount': _queueBox.length.toString(),
      });
    } catch (e) {
      debugPrint('QueueRepository initialization error: $e');
      rethrow;
    }
  }

  /// Returns the current initialization status
  bool get isInitialized => _initialized;

  /// Enqueues a new Sales Requisition for offline sync.
  /// Returns the clientGeneratedId for reference.
  Future<String> enqueueSalesRequisition({
    required String clientGeneratedId,
    required String tenantDatabaseId,
    required String userId,
    required Map<String, dynamic> sorDraftPayload,
    required String correlationId,
  }) async {
    _ensureInitialized();

    final queued = QueuedSalesRequisition(
      clientGeneratedId: clientGeneratedId,
      tenantDatabaseId: tenantDatabaseId,
      userId: userId,
      sorDraftPayload: sorDraftPayload,
      status: OfflineSorStatus.draftOffline,
      correlationId: correlationId,
    );

    await _queueBox.put(clientGeneratedId, queued);
    await _auditLog('SOR_ENQUEUED', {
      'clientGeneratedId': clientGeneratedId,
      'tenantDatabaseId': tenantDatabaseId,
      'userId': userId,
      'correlationId': correlationId,
    });

    return clientGeneratedId;
  }

  /// Retrieves a queued SOR by clientGeneratedId
  QueuedSalesRequisition? getSalesRequisition(String clientGeneratedId) {
    _ensureInitialized();
    return _queueBox.get(clientGeneratedId);
  }

  /// Updates status and related fields for a queued SOR
  Future<void> updateStatus(
    String clientGeneratedId, {
    required OfflineSorStatus newStatus,
    String? lastError,
    OfflineErrorCategory? errorCategory,
    String? rejectionReasons,
    int? autoRetryCount,
    int? manualRetryCount,
    DateTime? rollbackAvailableUntil,
    OfflineSorStatus? emailStatus,
  }) async {
    _ensureInitialized();

    final existing = _queueBox.get(clientGeneratedId);
    if (existing == null) {
      throw Exception('SOR not found: $clientGeneratedId');
    }

    final updated = existing.copyWith(
      status: newStatus,
      lastError: lastError,
      errorCategory: errorCategory,
      rejectionReasons: rejectionReasons,
      autoRetryCount: autoRetryCount,
      manualRetryCount: manualRetryCount,
      lastSyncAttemptTimestamp: DateTime.now(),
      rollbackAvailableUntil: rollbackAvailableUntil,
      emailStatus: emailStatus,
    );

    await _queueBox.put(clientGeneratedId, updated);
    await _auditLog('STATUS_UPDATED', {
      'clientGeneratedId': clientGeneratedId,
      'previousStatus': existing.status.label,
      'newStatus': newStatus.label,
      'errorCategory': errorCategory?.name,
    });
  }

  /// Increments auto retry count for a queued SOR
  Future<void> incrementAutoRetry(String clientGeneratedId) async {
    _ensureInitialized();

    final existing = _queueBox.get(clientGeneratedId);
    if (existing == null) {
      throw Exception('SOR not found: $clientGeneratedId');
    }

    existing.incrementAutoRetryCount();
    existing.lastSyncAttemptTimestamp = DateTime.now();
    await _queueBox.put(clientGeneratedId, existing);
    await _auditLog('AUTO_RETRY_INCREMENTED', {
      'clientGeneratedId': clientGeneratedId,
      'newCount': existing.autoRetryCount.toString(),
    });
  }

  /// Increments manual retry count (user-triggered)
  Future<void> incrementManualRetry(String clientGeneratedId) async {
    _ensureInitialized();

    final existing = _queueBox.get(clientGeneratedId);
    if (existing == null) {
      throw Exception('SOR not found: $clientGeneratedId');
    }

    if (!existing.canManualRetry(DateTime.now())) {
      throw Exception(
        'Manual retry not available for $clientGeneratedId (at limit or cooldown active)',
      );
    }

    existing.incrementManualRetryCount();
    existing.lastManualRetryTimestamp = DateTime.now();
    await _queueBox.put(clientGeneratedId, existing);
    await _auditLog('MANUAL_RETRY_INCREMENTED', {
      'clientGeneratedId': clientGeneratedId,
      'newCount': existing.manualRetryCount.toString(),
    });
  }

  /// Marks a SOR as accepted and eligible for rollback (24-hour window)
  Future<void> markSyncAccepted(String clientGeneratedId) async {
    _ensureInitialized();

    final existing = _queueBox.get(clientGeneratedId);
    if (existing == null) {
      throw Exception('SOR not found: $clientGeneratedId');
    }

    final rollbackWindow = DateTime.now().add(const Duration(hours: 24));
    final updated = existing.copyWith(
      status: OfflineSorStatus.syncedAccepted,
      rollbackAvailableUntil: rollbackWindow,
      emailStatus: OfflineSorStatus.emailPending,
      lastError: null,
      errorCategory: null,
    );

    await _queueBox.put(clientGeneratedId, updated);
    await _auditLog('SYNC_ACCEPTED', {
      'clientGeneratedId': clientGeneratedId,
      'rollbackAvailableUntil': rollbackWindow.toIso8601String(),
    });
  }

  /// Marks a SOR as rolled back (after sync accepted but within 24-hour window)
  Future<void> markRolledBack(String clientGeneratedId, String reason) async {
    _ensureInitialized();

    final existing = _queueBox.get(clientGeneratedId);
    if (existing == null) {
      throw Exception('SOR not found: $clientGeneratedId');
    }

    if (!existing.canRollback(DateTime.now())) {
      throw Exception('Rollback window expired for $clientGeneratedId');
    }

    final updated = existing.copyWith(
      status: OfflineSorStatus.rolledBack,
      lastError: reason,
    );

    await _queueBox.put(clientGeneratedId, updated);
    await _auditLog('ROLLED_BACK', {
      'clientGeneratedId': clientGeneratedId,
      'reason': reason,
    });
  }

  /// Gets all queued SORs with optional filtering by status
  List<QueuedSalesRequisition> getAllQueued({
    OfflineSorStatus? filterByStatus,
  }) {
    _ensureInitialized();

    final all = _queueBox.values.toList();
    if (filterByStatus != null) {
      return all.where((sor) => sor.status == filterByStatus).toList();
    }
    return all;
  }

  /// Gets all SORs pending sync (not yet successfully synced)
  List<QueuedSalesRequisition> getPendingSync() {
    _ensureInitialized();

    final pendingStatuses = [
      OfflineSorStatus.draftOffline,
      OfflineSorStatus.pendingSync,
      OfflineSorStatus.syncing,
      OfflineSorStatus.requiresRelogin,
      OfflineSorStatus.failedRequiresUserAction,
    ];

    return _queueBox.values
        .where((sor) => pendingStatuses.contains(sor.status))
        .toList();
  }

  /// Gets all SORs eligible for manual retry (not at limit, not on cooldown)
  List<QueuedSalesRequisition> getAvailableForManualRetry() {
    _ensureInitialized();
    final now = DateTime.now();

    return _queueBox.values.where((sor) => sor.canManualRetry(now)).toList();
  }

  /// Deletes a queued SOR (typically after successful sync + email)
  Future<void> deleteSalesRequisition(String clientGeneratedId) async {
    _ensureInitialized();

    await _queueBox.delete(clientGeneratedId);
    await _auditLog('SOR_DELETED', {
      'clientGeneratedId': clientGeneratedId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Clears old queue items based on retention policy (1-day history)
  Future<int> clearExpiredItems() async {
    _ensureInitialized();

    final cutoff = DateTime.now().subtract(_queueRetentionDuration);
    final keysToDelete = <String>[];

    for (final entry in _queueBox.toMap().entries) {
      final sor = entry.value as QueuedSalesRequisition;
      // Delete if created before cutoff AND (final state reached OR cancelled)
      final finalStates = [
        OfflineSorStatus.syncedAccepted,
        OfflineSorStatus.rolledBack,
        OfflineSorStatus.cancelledByUser,
      ];

      if (sor.createdTimestamp.isBefore(cutoff) &&
          finalStates.contains(sor.status)) {
        keysToDelete.add(entry.key as String);
      }
    }

    for (final key in keysToDelete) {
      await _queueBox.delete(key);
    }

    await _auditLog('EXPIRED_ITEMS_CLEARED', {
      'count': keysToDelete.length.toString(),
      'cutoff': cutoff.toIso8601String(),
    });

    return keysToDelete.length;
  }

  /// Gets count of queued items (useful for UI indicators)
  int get queueCount {
    _ensureInitialized();
    return _queueBox.length;
  }

  /// Gets count of items pending sync
  int get pendingSyncCount {
    _ensureInitialized();
    return getPendingSync().length;
  }

  /// Internal: Retrieves or generates the AES-256 encryption key
  /// Key is generated once and stored securely using FlutterSecureStorage
  Future<Uint8List> _getOrCreateEncryptionKey() async {
    try {
      // Attempt to retrieve existing key from secure storage
      final existingKey = await _secureStorage.read(key: _encryptionKeyName);
      if (existingKey != null) {
        return Uint8List.fromList(base64.decode(existingKey));
      }

      // Generate new 32-byte (256-bit) encryption key
      final newKey = _generateSecureRandomBytes(32);
      final encodedKey = base64.encode(newKey);

      // Store in secure storage
      await _secureStorage.write(
        key: _encryptionKeyName,
        value: encodedKey,
        aOptions: _getAndroidOptions(),
        iOptions: _getIOSOptions(),
      );

      return newKey;
    } catch (e) {
      debugPrint('Error managing encryption key: $e');
      rethrow;
    }
  }

  /// Generates cryptographically secure random bytes
  Uint8List _generateSecureRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Android-specific secure storage options
  AndroidOptions _getAndroidOptions() {
    return const AndroidOptions(
      keyCipherAlgorithm:
          KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
      resetOnError: true,
    );
  }

  /// iOS-specific secure storage options
  IOSOptions _getIOSOptions() {
    return const IOSOptions(
      accessibility:
          KeychainAccessibility.first_available_when_unlocked_this_device_only,
    );
  }

  /// Ensures repository is initialized before operations
  void _ensureInitialized() {
    if (!_initialized) {
      throw Exception(
        'QueueRepository not initialized. Call initialize() first.',
      );
    }
  }

  /// Writes an audit log entry (timestamps and non-sensitive data only)
  Future<void> _auditLog(String eventType, Map<String, String> details) async {
    try {
      final logEntry = jsonEncode({
        'eventType': eventType,
        'timestamp': DateTime.now().toIso8601String(),
        'details': details,
      });

      final key = 'audit_${DateTime.now().millisecondsSinceEpoch}';
      await _auditBox.put(key, logEntry);

      // Debug log for development
      debugPrint('[QueueAudit] $eventType: $details');
    } catch (e) {
      debugPrint('Error writing audit log: $e');
      // Don't throw - logging failures should not block operations
    }
  }

  /// Retrieves audit log entries (for debugging/admin)
  List<Map<String, dynamic>> getAuditLog({int maxEntries = 100}) {
    _ensureInitialized();

    final entries = _auditBox.values.toList().reversed.take(maxEntries);
    return entries.map((entry) {
      try {
        return jsonDecode(entry) as Map<String, dynamic>;
      } catch (e) {
        return {'error': 'Failed to parse audit entry', 'raw': entry};
      }
    }).toList();
  }

  /// Closes Hive boxes (typically during logout or app shutdown)
  Future<void> close() async {
    if (_initialized) {
      await _queueBox.close();
      await _auditBox.close();
      _initialized = false;
    }
  }
}
