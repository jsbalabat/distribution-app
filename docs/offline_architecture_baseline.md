# Offline Architecture Baseline (Ticket 1)

This document defines the baseline contract for offline SOR behavior.
It is the single source of truth for lifecycle states, transition rules, and error/event naming.

## Scope

- Mobile app offline SOR creation and queueing
- Reconnect-time server validation and sync
- Post-acceptance email dispatch

## Authoritative Principles

1. Server is always authoritative.
2. Validation and commit are all-or-nothing.
3. Offline users can only continue with previously authenticated sessions.
4. Email is sent only after successful server acceptance.
5. Failed items remain visible to users for correction and retry.

## Lifecycle States

- `draftOffline`: SOR draft exists locally and is editable.
- `pendingSync`: User submitted offline, queued for upload.
- `syncing`: Background worker is attempting sync.
- `syncedAccepted`: Server accepted and committed SOR.
- `rejectedValidation`: Server rejected due to business or field validation.
- `rejectedInventory`: Server rejected due to insufficient inventory.
- `requiresRelogin`: Sync blocked due to invalid/expired session.
- `emailPending`: SOR accepted; email dispatch queued/in-progress.
- `emailSent`: Email dispatched successfully.
- `emailFailedRetryAvailable`: Email failed; resend available.
- `rollbackAvailable`: Rollback allowed after resend failure and guard checks.
- `rolledBack`: Accepted SOR was reversed server-side.
- `failedRequiresUserAction`: Automatic retries exhausted; manual intervention required.
- `cancelledByUser`: User cancelled queued SOR before sync.

## Transition Rules

- `draftOffline -> pendingSync`
  - User submits while offline.
- `pendingSync -> syncing`
  - Connectivity restored and worker acquires item lock.
- `syncing -> syncedAccepted`
  - Server auth + validation + inventory checks pass and commit succeeds.
- `syncing -> rejectedValidation`
  - Any field/business rule fails.
- `syncing -> rejectedInventory`
  - Any inventory check fails.
- `syncing -> requiresRelogin`
  - Auth refresh or session validity fails.
- `syncing -> failedRequiresUserAction`
  - Automatic retry window exhausted.
- `syncedAccepted -> emailPending`
  - Email flow starts immediately after acceptance.
- `emailPending -> emailSent`
  - Email provider confirms success.
- `emailPending -> emailFailedRetryAvailable`
  - Email provider failure.
- `emailFailedRetryAvailable -> rollbackAvailable`
  - One resend attempt has failed and rollback guards are satisfied.
- `rollbackAvailable -> rolledBack`
  - Admin/user confirms rollback and server executes atomic reversal.
- `draftOffline|pendingSync -> cancelledByUser`
  - User confirms cancellation before sync starts.

## Validation and Commit Contract

- Validation and inventory checks run only server-side during sync.
- No partial line acceptance is permitted.
- If any line fails, the full SOR is rejected and no inventory mutation occurs.

## Retry Policy

### Automatic (background)

- `0s`, `30s`, `2m`, `10m`, `30m`, `2h`, `6h`, `12h`, `24h`
- Jitter: +/-20 percent
- Automatic retries pause on `requiresRelogin`.

### Manual (user initiated)

- Maximum manual retries per item: `3`
- Cooldown between manual retries: `30s`

## Rollback Guard Rules

Rollback is allowed only when all are true:

1. SOR is in accepted state and email path failed after resend.
2. Less than 24 hours since acceptance timestamp.
3. SOR has not entered downstream fulfilled/locked business flow.
4. Inventory reversal can be applied atomically.

## Idempotency Contract

- Client sends `clientGeneratedId` (UUIDv7) per submission event.
- Backend enforces uniqueness for tenant + user + key.
- Duplicate sync requests must return the same accepted/rejected outcome without duplicate creation.

## User-Facing Error Categories

- `auth`: re-login required
- `network`: connectivity/timeout
- `validation`: rule/field violation
- `inventory`: stock conflict
- `email`: dispatch provider failure
- `unknown`: unclassified

## Event Naming Standard

- `sor_created_offline`
- `sor_queued_for_sync`
- `sor_sync_started`
- `sor_sync_accepted`
- `sor_sync_rejected_validation`
- `sor_sync_rejected_inventory`
- `sor_sync_requires_relogin`
- `sor_sync_retry_scheduled`
- `sor_sync_exhausted`
- `sor_cancelled_by_user`
- `email_dispatch_started`
- `email_dispatch_sent`
- `email_dispatch_failed`
- `email_resend_requested`
- `email_resend_failed`
- `rollback_eligible`
- `rollback_requested`
- `rollback_completed`

## Logging Requirements

Each event should include:

- `timestampClient`
- `timestampServer` (when available)
- `tenantId`
- `userId`
- `deviceId`
- `clientGeneratedId`
- `correlationId`
- `statusFrom`
- `statusTo`
- `errorCode`
- `errorMessage`

## Current Code Mapping

- Submit paths:
  - `lib/screens/form_screen.dart`
  - `lib/screens/review_screen.dart`
- Data service:
  - `lib/services/firestore_service.dart`
- Auth/session source:
  - `lib/services/auth_service.dart`
  - `lib/providers/user_provider.dart`
- Email callables:
  - `functions/index.js` (`sendAutoRoutedRequisitionEmail`, `sendSalesRequisitionEmail`)
- Settings callable:
  - `functions/index.js` (`updateAutoEmailSettings`)

## Out of Scope for Ticket 1

- Actual queue storage implementation
- Sync worker implementation
- New callable implementation for transactional sync
- UI status rendering integration
