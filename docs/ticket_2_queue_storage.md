# Ticket 2: Secure Local Queue Storage Implementation

## Status: COMPLETED ✓

Ticket 2 implements encrypted local storage for queued Sales Requisitions using Hive with AES-256-GCM encryption and secure key management via Flutter Secure Storage.

## Deliverables

### 1. **QueuedSalesRequisition Model** (`lib/models/queued_sales_requisition.dart`)
   - Hive-persisted model representing a single queued SOR
   - Fields tied to offline sync contract (status, retry counts, timestamps, error tracking)
   - Immutable copyWith pattern for safe updates
   - Helper methods: `canManualRetry()`, `canRollback()`, `incrementAutoRetryCount()`, `incrementManualRetryCount()`
   - **Key design**: Maps to 14 offline states + error categories defined in offline_sync_contract.dart

### 2. **Hive Adapters** (`lib/models/offline_sync_adapters.dart`)
   - Custom TypeAdapters for OfflineSorStatus enum (TypeId: 1)
   - Custom TypeAdapter for OfflineErrorCategory enum (TypeId: 2)
   - Enables serialization/deserialization of enums in encrypted Hive boxes

### 3. **QueueRepository Service** (`lib/services/queue_repository.dart`)
   - Core service managing all queue operations
   - **Encryption**: AES-256-GCM via Hive; key stored securely in platform-specific secure storage
   - **Public methods**:
     - `initialize()`: One-time setup, generates/retrieves encryption key
     - `enqueueSalesRequisition()`: Adds new SOR to queue
     - `getSalesRequisition(clientId)`: Retrieves single queued SOR
     - `updateStatus()`: Transitions SOR state with error tracking
     - `incrementAutoRetry()`: For automatic backoff schedule execution
     - `incrementManualRetry()`: For user-initiated retries (capped at 3)
     - `markSyncAccepted()`: Marks SOR as accepted, opens 24-hour rollback window
     - `markRolledBack()`: Reverts accepted SOR if within window
     - `getPendingSync()`: Returns all non-final SORs (for sync worker)
     - `getAvailableForManualRetry()`: Returns eligible-for-retry SORs
     - `deleteSalesRequisition()`: Removes SOR after successful sync + email
     - `clearExpiredItems()`: Retention policy enforcement (1-day history)
   - **Audit logging**: All operations logged to unencrypted audit box for compliance/debugging

### 4. **Acceptance Tests** (`test/queue_repository_test.dart`)
   - Comprehensive test suite covering 12 major scenarios:
     - Initialization with encryption key generation
     - Enqueue with correct initial state
     - Status transitions through lifecycle
     - Manual retry capped at 3 attempts with 30-second cooldown
     - Auto retry count clamped at 9
     - Rollback window (24 hours) enforcement
     - Pending sync filtering
     - Expired item cleanup based on retention policy
     - Audit log captures all operations
   - Mock secure storage for deterministic testing
   - In-memory Hive for fast test execution

### 5. **Dependencies Added** to `pubspec.yaml`
   - `hive: ^2.2.3` — Local encrypted key-value storage
   - `hive_flutter: ^1.1.0` — Flutter integration with platform support
   - `flutter_secure_storage: ^9.0.0` — Secure encryption key management (iOS Keychain, Android Keystore)

## Integration Points

### Next Step: Ticket 3 (Auth + Connectivity Gate)
The queue repository is standalone and ready for use. Ticket 3 will integrate this into the auth flow:
- Lock queue operations to previously authenticated sessions only
- Block sync if auth token is invalid/expired (transition to `requiresRelogin`)
- Reuse `AuthService` + `UserProvider` as gate points

### Later: Sync Worker (Ticket 4)
The queue repository feeds the sync worker:
- Sync worker calls `getPendingSync()` to get eligible SORs
- Calls `incrementAutoRetry()` per backoff schedule
- Calls `markSyncAccepted()` or `updateStatus(...rejectedValidation)` on server response
- Calls `deleteSalesRequisition()` after email sent

## Architectural Guarantees

**Data Security**:
- All queue data encrypted at rest (AES-256-GCM)
- Encryption key secured in device's secure storage (iOS Keychain, Android Keystore)
- No credentials stored locally; auth handled by AppService

**State Machine Compliance**:
- `enqueueSalesRequisition()` creates SOR in `draftOffline` state (no sync attempted)
- Manual retry: capped at 3, enforced 30-second cooldown
- Auto retry: capped per backoff schedule slot (0, 30s, 2m, 10m, 30m, 2h, 6h, 12h, 24h)
- Rollback: only offered within 24 hours of acceptance, enforced via `rollbackAvailableUntil` timestamp

**Retention & Cleanup**:
- Queue items kept for 1 day post-completion (accepted, rolled back, or cancelled)
- `clearExpiredItems()` called periodically (Ticket 4: by sync worker hourly)
- Audit log kept separately, subject to same retention

**Idempotency**:
- `clientGeneratedId` is primary key (UUIDv7)
- Enqueue is idempotent if same clientId used (updates existing)
- Manual/auto retry operations preserve idempotency key for server

## Testing Approach

All acceptance tests in `test/queue_repository_test.dart`:
- Run against in-memory Hive (no disk I/O, fast)
- Use MockSecureStorage for deterministic key management
- Cover happy path + edge cases (cooldown, window expiry, limits)
- Verify audit trail is captured

To run tests:
```bash
flutter test test/queue_repository_test.dart
```

## Verification Checklist

- ✅ QueuedSalesRequisition model created with all required fields
- ✅ Hive adapters for status and error enums registered
- ✅ QueueRepository handles encryption key generation and secure storage
- ✅ All CRUD operations (enqueue, get, update, delete) implemented
- ✅ Manual retry logic enforces 3-attempt limit + 30-second cooldown
- ✅ Auto retry increment enforces 9-operation cap
- ✅ Rollback window enforces 24-hour cutoff
- ✅ Audit logging for all operations
- ✅ Expired item cleanup respects retention policy
- ✅ Acceptance test suite covers 12+ scenarios
- ✅ No external dependencies beyond Flutter packages

## No Breaking Changes

The queue repository is a new service and does not modify existing code paths. Integration into form submission happens in Ticket 3 when AuthGate is implemented.
