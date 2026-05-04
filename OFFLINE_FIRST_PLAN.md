# Offline-First SOR — Implementation Plan & Decision Log

**Last updated:** 2026-05-03
**Owner:** Marc
**Status:** Planning complete; Sprint 1 not yet started.

This document captures the full context, decisions, and execution plan for moving the `new_test_store` app to a robust offline-first architecture with server-authoritative submission and email handling. It exists so context survives across sessions.

When updating: append to the **Decision log** and **Sprint progress** sections, don't rewrite history.

---

## 1. App context

`new_test_store` is a Flutter multi-tenant Sales Order Requisition (SOR) and inventory app. Mobile (iOS/Android), web, and desktop. Backend is Firebase (Auth, Firestore, Cloud Functions). Multi-tenancy via per-company Firestore database IDs (`FirestoreTenant` singleton).

The defining trait is **offline-first**: sales reps queue SORs locally (Hive, AES-256-GCM encrypted), and a background worker syncs them when connectivity and a fresh session return.

**Cloud Functions region:** `asia-southeast1` (currently hardcoded in [lib/services/offline_email_dispatch_service.dart](lib/services/offline_email_dispatch_service.dart) — to be moved to [lib/config/firebase_config.dart](lib/config/firebase_config.dart) in Sprint 5).

---

## 2. Current state at planning time

Snapshot from codebase scan on 2026-05-03. Update as work progresses.

| Area | State | Notes |
|---|---|---|
| Offline contract / status enum | DONE | [lib/models/offline_sync_contract.dart](lib/models/offline_sync_contract.dart) — full enum, retry schedule, manual retry constants |
| Local offline storage | DONE | [lib/services/queue_repository.dart](lib/services/queue_repository.dart) — Hive AES-256-GCM, audit trail, 24h retention |
| Sync orchestrator | DONE | [lib/services/offline_sync_worker.dart](lib/services/offline_sync_worker.dart) — backoff with jitter, auth gate, connectivity gate |
| Connectivity gating at submission | DONE | [lib/services/offline_submission_service.dart](lib/services/offline_submission_service.dart) — `submitOrQueue()` |
| Form/review screens use gating | DONE | [lib/screens/form_screen.dart:605](lib/screens/form_screen.dart#L605), [lib/screens/review_screen.dart:45](lib/screens/review_screen.dart#L45) |
| **Backend transactional submit endpoint** | **MISSING (critical)** | No callable in [functions/index.js](functions/index.js). `FirestoreService.submitSOR` ([lib/services/firestore_service.dart:22](lib/services/firestore_service.dart#L22)) writes directly to Firestore. No idempotency, no inventory transaction. |
| Email after acceptance | IN PROGRESS (to be reverted) | In-flight branch puts email in client; Sprint 1 moves it to server. See decision D below. |
| UI for offline transparency | MISSING | No connectivity banner, queue status chips, or retry/cancel actions on dashboard/submissions screens |
| Settings: offline policy switches | MISSING | No `allowOffline`, `maxOfflineQueueAge`, `cellular` toggles in [lib/screens/settings_screen.dart](lib/screens/settings_screen.dart) |
| User activity log | PARTIAL | [lib/services/audit_service.dart](lib/services/audit_service.dart) and admin viewer exist; no per-SOR timeline, no user-scoped feed |
| Per-tenant feature flag | MISSING | Queue path is unconditional once gating service decides offline |
| Test matrix (idempotency, restart, flapping) | MISSING | Worker state machine and queue have unit tests; integration scenarios untested |

### In-flight uncommitted work (as of 2026-05-03)

**Branch:** `master` (no feature branch).

| File | State | Disposition |
|---|---|---|
| [lib/services/offline_email_dispatch_service.dart](lib/services/offline_email_dispatch_service.dart) | NEW | **TO DELETE in Sprint 2** — server will own email |
| [lib/services/offline_sync_worker.dart](lib/services/offline_sync_worker.dart) | Modified (email dispatch added) | **REVERT email parts in Sprint 2** — keep model field reads, drop dispatch + retry loop |
| [lib/services/queue_repository.dart](lib/services/queue_repository.dart) | Modified (`getPendingEmailDispatch()` added) | **TO REMOVE in Sprint 2** |
| [lib/services/offline_queue_repository.dart](lib/services/offline_queue_repository.dart) | Modified (interface method) | **TO REMOVE in Sprint 2** |
| [test/offline_sync_worker_test.dart](test/offline_sync_worker_test.dart) | Modified (4 new email tests) | **TO REPLACE in Sprint 2** with server-reported-status tests |

**Action before Sprint 1**: stash or branch-archive this work. Don't merge to master. Model fields (`emailStatus`, `correlationId`, `rollbackAvailableUntil`) on `QueuedSalesRequisition` are keepers — they'll mirror server state instead of driving it.

---

## 3. Original implementation checklist (10 items)

This was the user's original plan, kept here for reference. Statuses below are mapped against the codebase as of 2026-05-03.

| # | Item | Status |
|---|---|---|
| 1 | Define offline contract / final statuses | DONE |
| 2 | Local offline storage layer | DONE |
| 3 | Connectivity + sync orchestrator | DONE |
| 4 | Backend transactional submit endpoint | **MISSING — Sprint 1** |
| 5 | Replace direct client submit with queue + sync submit | HALF — gating done, backend call missing — Sprint 2 |
| 6 | UI/UX for offline transparency | MISSING — Sprint 3 |
| 7 | Settings + offline policy controls | MISSING — Sprint 4 |
| 8 | Observability + audit | PARTIAL — Sprint 4 |
| 9 | Testing matrix | PARTIAL — Sprint 5 |
| 10 | Rollout plan with feature flag | NOT STARTED — Sprint 5 |

---

## 4. Decision log

All decisions made on 2026-05-03 unless noted. Append new decisions below; never rewrite past ones.

### A. Authentication & security

- **A.1** Only previously authenticated sessions can continue offline. No new login attempts allowed offline. *(Firebase Auth requires internet for both login and token refresh.)*
- **A.2** Queue if `FirebaseAuth.instance.currentUser != null` regardless of token freshness. Sync attempts gate on token refresh. On revocation (password change, admin revoke) → `requiresRelogin`.
  - **Background:** Firebase ID token lives 1 hour; refresh token lives indefinitely until revoked. Both creation and refresh require internet. `currentUser` persists offline as long as refresh token is intact.
- **A.3** Local queue is encrypted at rest with device-level protection (AES-256-GCM via Hive, key in `FlutterSecureStorage` → Keychain/Keystore). **Add biometric/PIN gate at app launch in Sprint 5.**

### B. Inventory & validation

- **B.1** Cached inventory shown read-only offline. Modifications happen only when online and validated.
- **B.2** Server is always canonical. On sync inventory failure → adjust to server truth, surface as failed requisition to user with retry option.
- **B.3** **All-or-nothing rejection.** No partial line-item acceptance. If any line fails, reject the entire SOR with a structured per-line reason list. *("Partial acceptance" was defined as: server saves SOR with 3 of 5 items, rejects 2. User chose to disallow.)*

### C. Queue semantics

- **C.1** Manual retry: 3 attempts max, each consisting of 3 underlying network attempts. Cooldown 30s between manual retries (already in [lib/models/offline_sync_contract.dart:48-49](lib/models/offline_sync_contract.dart#L48-L49)).
- **C.2** **Auto-retry: 6 levels** (`0s, 30s, 2m, 10m, 30m, 2h`) with ±20% deterministic jitter. **Trim from current 9 levels** ([lib/models/offline_sync_contract.dart:51-61](lib/models/offline_sync_contract.dart#L51-L61) drops the last 3 entries). **Error-category-aware:** auto-retry only for `network`/`unknown`. `validation`, `inventory`, `auth` → immediate terminal state, no retry.
- **C.3** **Dead-letter pattern.** After max manual + auto exhausted → `failedRequiresUserAction`. Item retained, not deleted. Manual force-retry available (resets counters, requires confirmation). Admin can override.

### D. Email — RESOLVED CONFLICT

**Original plan said:** server triggers email after acceptance.
**In-flight work said:** client triggers email after sync.

**RESOLUTION: Server triggers email (Option A).** Single source of truth. Side effects belong on server. Pattern matches Stripe / Shopify / Square.

- **D.1** Email sent immediately after server acceptance. No batching.
- **D.2** Server reports `emailStatus`. Client UI exposes:
  - **Resend** button when `emailStatus: failed` → calls `resendRequisitionEmail` callable.
  - **Rollback** button when `emailStatus: failed` AND within 24h `rollbackAvailableUntil` window → calls `rollbackRequisition` callable. Confirmation dialog required.
  - Error message must be specific enough to make rollback decision meaningful.

**Implication:** in-flight email branch (see §2) gets reverted in Sprint 2.

### E. UX

- **E.1** Allow editing queued SORs before sync, while offline.
- **E.2** Allow cancelling queued SORs with confirmation dialog (existing [lib/widgets/confirmation_dialog.dart](lib/widgets/confirmation_dialog.dart)).
- **E.3** **User-facing status labels** (replace engineer-readable labels currently in [lib/models/offline_sync_contract.dart:65](lib/models/offline_sync_contract.dart#L65)):

| Internal status | User-facing label | Admin-facing label |
|---|---|---|
| `draftOffline` | Draft (offline) | Draft — offline |
| `pendingSync` | Waiting to send | Pending sync |
| `syncing` | Sending… | Syncing |
| `syncedAccepted` | Submitted | Accepted |
| `rejectedValidation` | Couldn't submit — please review | Rejected — validation |
| `rejectedInventory` | Out of stock — please review | Rejected — inventory |
| `requiresRelogin` | Sign in to continue | Auth required |
| `failedRequiresUserAction` | Action needed | Failed — manual review |
| `emailPending` | Sending email… | Email pending |
| `emailSent` | Email sent | Email delivered |
| `emailFailedRetryAvailable` | Email failed — tap to retry | Email failed (retry avail.) |
| `rollbackAvailable` | Email failed — review or roll back | Email failed (rollback elig.) |
| `rolledBack` | Rolled back | Rolled back |
| `cancelledByUser` | Cancelled | Cancelled by user |

### F. Data model & idempotency

- **F.1** **UUIDv7** for `clientGeneratedId` (RFC 9562, time-ordered for B-tree locality). Use `package:uuid` v4+ → `Uuid().v7()`. Model docstring at [lib/models/queued_sales_requisition.dart:11](lib/models/queued_sales_requisition.dart#L11) already says v7 — verify implementation matches in Sprint 2.
- **F.2** Expose `clientGeneratedId` and `correlationId` to admins only, with copy buttons. Hide from regular users.
- **F.3** Local queue retention: 1 day after successful sync (already 24h in [lib/services/queue_repository.dart](lib/services/queue_repository.dart) `clearExpiredItems()`). Will become configurable via `maxOfflineQueueAgeDays` setting in Sprint 4 (default 1, range 1–7).

### G. User activity log (added 2026-05-03)

Industry-standard event-sourcing-lite. Approved as proposed:

1. **Per-entity timeline** on SOR detail screen — chronological events from `salesRequisitions/{id}/events` subcollection (server-written).
2. **User-scoped "My activity" feed** — events where `actorUid == currentUser.uid OR sorOwnerUid == currentUser.uid`, last 90 days.
3. **Server-side event writing** — server is event source of truth; client reads via Firestore listener.
4. **Event taxonomy expansion** beyond current `OfflineEventType`: add `sor_edited`, `sor_resubmitted`, `email_resend_requested`, `email_resend_succeeded`, `inventory_corrected_by_server`, `login`, `logout`, `password_changed`.
5. **Retention:** operational events 90d, compliance events indefinite (per existing `auditLogRetentionDays`).

---

## 5. Sprint plan

Five sprints, sized for ~2 weeks each at 1–2 developers. Re-cut if team capacity differs.

### Sprint 1 — Backend foundation (CRITICAL PATH)

Goal: build the missing transactional submit endpoint. Nothing else can be properly wired until this exists.

| Task | File / location | Detail |
|---|---|---|
| Add `submitSalesRequisition` callable | [functions/index.js](functions/index.js) (new export, near line 1642) | Inputs: `clientGeneratedId`, `correlationId`, `tenantDatabaseId`, `sorPayload`. Returns: `{accepted, sorId, sorNumber, rejectionCategory?, rejectionReasons?, eventsWritten[]}` |
| Idempotency | Same function | Use `clientGeneratedId` as document ID. `db.doc(id).create(data)` — catch `ALREADY_EXISTS`, return existing doc state |
| Inventory transaction | Same function | `db.runTransaction()`: read all line stocks, verify all sufficient, decrement all, write SOR, write event. All-or-nothing |
| Auth + tenant validation | Same function | Reuse pattern from existing callables ([functions/index.js:1642](functions/index.js#L1642), [2099](functions/index.js#L2099)). Validate `actorDatabaseId` against caller's tenant claim |
| Server-side email trigger | Same function (after commit) | Extract email logic from `sendAutoRoutedRequisitionEmail` ([functions/index.js:1642](functions/index.js#L1642)) into a helper. Invoke after acceptance. On email failure: write event, set `emailStatus: failed`, do NOT rollback SOR |
| Events subcollection | Same function | Write to `salesRequisitions/{id}/events`: `sor_sync_accepted`, `email_dispatch_started/sent/failed`. Each: `{type, timestamp, actor, details, correlationId}` |
| `resendRequisitionEmail` callable | [functions/index.js](functions/index.js) | Inputs: `sorId`. Re-runs email helper, writes `email_resend_requested` event. Permission: original submitter or admin |
| `rollbackRequisition` callable | [functions/index.js](functions/index.js) | Inputs: `sorId, reason`. Reverses inventory in transaction, sets `status: rolled_back`, writes event. Gated to within 24h `rollbackAvailableUntil` |
| Cloud Function tests | [functions/](functions/) (likely needs `test/` subdir) | Idempotency, inventory rejection, auth rejection, multi-tenant, email failure path |

**Acceptance:** duplicate `submitSalesRequisition` calls with same `clientGeneratedId` produce one SOR; insufficient inventory returns structured rejection; email fires exactly once on acceptance.

### Sprint 2 — Client integration + retry tightening + revert in-flight email branch

| Task | File / location | Detail |
|---|---|---|
| Split client write responsibilities | [lib/services/firestore_service.dart:22](lib/services/firestore_service.dart#L22) | Remove direct `_firestore.collection('salesRequisitions').add(...)`. Replace with `syncSubmitQueuedSor(QueuedSalesRequisition q)` calling new callable, returning structured server response |
| Update sync worker call site | [lib/services/offline_sync_worker.dart:408](lib/services/offline_sync_worker.dart#L408) | Replace `_firestoreService!.submitSOR(payload)` with `syncSubmitQueuedSor(item)`. Map server response → internal status |
| Update gating service | [lib/services/offline_submission_service.dart:57](lib/services/offline_submission_service.dart#L57) | Online path also routes through `syncSubmitQueuedSor` (one-shot queue → sync) so server-acceptance + email path is identical online and offline |
| **DELETE** `OfflineEmailDispatchService` | [lib/services/offline_email_dispatch_service.dart](lib/services/offline_email_dispatch_service.dart) | Server owns email |
| **REMOVE** worker email dispatch | [lib/services/offline_sync_worker.dart](lib/services/offline_sync_worker.dart) lines 56, 169-199, 271-331 | Delete `DispatchEmail` typedef, `_dispatchAutoEmail()`, email retry loop, `emailSent`/`emailFailed`/`rollbackEligible` worker metrics |
| **REMOVE** `getPendingEmailDispatch()` | [lib/services/queue_repository.dart](lib/services/queue_repository.dart), [offline_queue_repository.dart](lib/services/offline_queue_repository.dart) | No longer needed |
| Update existing email tests | [test/offline_sync_worker_test.dart](test/offline_sync_worker_test.dart) | Delete the 4 new email cases. Replace with: "worker reads server-reported emailStatus", "worker does not retry email itself" |
| Tighten retry policy | [lib/models/offline_sync_contract.dart:51-61](lib/models/offline_sync_contract.dart#L51-L61) | Trim `autoRetrySchedule` from 9 → 6 entries (stop at `Duration(hours: 2)`). After exhaustion → `failedRequiresUserAction` |
| Error-category retry gating | [lib/services/offline_sync_worker.dart](lib/services/offline_sync_worker.dart) | If `errorCategory ∈ {validation, inventory, auth}` → no auto-retry, immediate terminal state. Only `network`/`unknown` get backoff |
| Confirm UUIDv7 generator | [lib/services/queue_repository.dart](lib/services/queue_repository.dart) (wherever `clientGeneratedId` is generated) | Verify `package:uuid` v4+, use `Uuid().v7()`. Update model docstring if mismatched |

**Acceptance:** client never writes to `salesRequisitions` directly; sync goes through callable; sync worker has zero email logic; auto-retries only fire for network failures.

### Sprint 3 — UX surface

| Task | File / location | Detail |
|---|---|---|
| Connectivity banner widget | [lib/widgets/](lib/widgets/) (new `connectivity_banner.dart`) | Listens to `connectivity_plus`. Red banner when offline; dismissible info banner when reconnected. Wrap in [dashboard_screen.dart](lib/screens/dashboard_screen.dart), [form_screen.dart](lib/screens/form_screen.dart), [review_screen.dart](lib/screens/review_screen.dart) |
| Queue status chip widget | [lib/widgets/](lib/widgets/) (new `queue_status_chip.dart`) | Maps `OfflineSorStatus` → user-facing label + color. Uses E.3 label table |
| Submissions screen tabs | [lib/screens/submissions_screen.dart](lib/screens/submissions_screen.dart) | Tabs: "Submitted" / "In progress" / "Failed". Chips on every row |
| Retry-now action | [lib/screens/submissions_screen.dart](lib/screens/submissions_screen.dart) | Button on `rejected*` / `failedRequiresUserAction` rows. Calls `OfflineSyncWorker.instance.manualRetry(item)`. Honors `manualRetryLimit` and `manualRetryCooldown` from [queued_sales_requisition.dart:150](lib/models/queued_sales_requisition.dart#L150) |
| Edit-and-resubmit | [lib/screens/edit_requisition_screen.dart](lib/screens/edit_requisition_screen.dart) | Allow editing in `draftOffline`, `pendingSync`, `rejected*`, `failedRequiresUserAction`. On save, reset retry counters, re-enqueue. Block editing `syncing` / `syncedAccepted` |
| Cancel queued SOR | [lib/screens/submissions_screen.dart](lib/screens/submissions_screen.dart) | Confirmation dialog. Sets status to `cancelledByUser`. Only pre-`syncing` |
| Resend email button | [lib/widgets/pdf_email_section.dart](lib/widgets/pdf_email_section.dart) or new SOR-detail section | Visible on `emailStatus: failed`. Calls `resendRequisitionEmail` callable |
| Rollback button | [lib/screens/transaction_detail_screen.dart](lib/screens/transaction_detail_screen.dart) | Visible on `emailStatus: failed` AND within `rollbackAvailableUntil`. Confirmation dialog. Calls `rollbackRequisition` callable |
| Render structured rejection reasons | All UX touch points | E.g., "Item ABC: insufficient stock — 5 requested, 2 available" |

**Acceptance:** user always knows from chip whether item is queued or accepted; rejection messages actionable; cancel/edit/retry/resend/rollback all work end-to-end.

### Sprint 4 — Settings, observability, activity log

| Task | File / location | Detail |
|---|---|---|
| Offline policy settings | [lib/screens/settings_screen.dart](lib/screens/settings_screen.dart) | `allowOfflineSubmission` (default true), `autoSyncOnCellular` (default true), `maxOfflineQueueAgeDays` slider 1–7 (default 1). Persist to existing app-settings doc |
| Wire policy to worker/gating | [lib/services/offline_sync_worker.dart](lib/services/offline_sync_worker.dart), [offline_submission_service.dart](lib/services/offline_submission_service.dart) | Honor `allowOfflineSubmission` in gating; check `connectivity_plus` connection type for `autoSyncOnCellular`; use `maxOfflineQueueAgeDays` in `clearExpiredItems()` |
| Per-SOR activity timeline | [lib/widgets/](lib/widgets/) (new `sor_activity_timeline.dart`) | Streams from `salesRequisitions/{id}/events`. Embed in [transaction_detail_screen.dart](lib/screens/transaction_detail_screen.dart) |
| "My activity" tab | [lib/screens/dashboard_screen.dart](lib/screens/dashboard_screen.dart) or new screen | Server query: events where `actorUid == currentUser.uid OR sorOwnerUid == currentUser.uid`, last 90 days, paginated |
| Expand event taxonomy | [functions/index.js](functions/index.js), [lib/models/offline_sync_contract.dart](lib/models/offline_sync_contract.dart) | Add `sor_edited`, `sor_resubmitted`, `email_resend_succeeded`, `inventory_corrected_by_server`, `login`, `logout` |
| Admin queue health tile | [lib/screens/admin_dashboard_screen.dart](lib/screens/admin_dashboard_screen.dart) | Counts by status, oldest pending age, rejection rate (24h) |
| Expose IDs in admin views | [lib/screens/transaction_detail_screen.dart](lib/screens/transaction_detail_screen.dart), [audit_logs_screen.dart](lib/screens/audit_logs_screen.dart) | Show `clientGeneratedId` + `correlationId` admin-only with copy buttons |
| Backend correlation logging | [functions/index.js](functions/index.js) — every callable | Add `correlationId`, `clientGeneratedId`, `tenant`, `rejectionCategory` as structured fields in every log line for every SOR-touching callable |
| Retention cron | [functions/index.js:1184](functions/index.js#L1184) (extend `pruneAuditLogs`) | Operational events 90d, compliance indefinite |

**Acceptance:** every failed sync has one searchable backend log line and one user-facing reason; admin can pull queue health at a glance; user has timeline view of every SOR.

### Sprint 5 — Hardening + rollout

| Task | File / location | Detail |
|---|---|---|
| Test: idempotency | [test/](test/) + [functions/test/](functions/) | Repeated `submitSalesRequisition` with same `clientGeneratedId`: one SOR, one email, identical response |
| Test: app restart mid-queue | [test/offline_sync_worker_test.dart](test/offline_sync_worker_test.dart) | Kill worker mid-sync; restart; `syncing` items resume cleanly without duplicate writes |
| Test: partial connectivity flapping | [test/offline_sync_worker_test.dart](test/offline_sync_worker_test.dart) | online → offline → online during sync. Verify backoff state, no double-submits |
| Test: multi-tenant routing | [test/](test/) + [functions/test/](functions/) | Reject if `actorDatabaseId` mismatches caller's tenant claim |
| Test: auth expired mid-queue | [test/offline_sync_worker_test.dart](test/offline_sync_worker_test.dart) | Refresh token revoked between attempts → `requiresRelogin`, no further sync until re-auth |
| Per-tenant feature flag | [lib/services/firestore_tenant.dart](lib/services/firestore_tenant.dart) + tenant settings doc | `offlineQueueEnabled: bool`. Honored in [OfflineSubmissionService](lib/services/offline_submission_service.dart) — when false, fall back to online-only, fail closed when offline |
| Pilot tenant cutover | runtime config | Enable for one tenant; monitor rejection rate, sync latency, dead-letter accumulation for 1–2 weeks |
| Biometric/PIN gate | [lib/main.dart](lib/main.dart), new `lib/services/biometric_gate.dart` | `local_auth` package. Gate queue access on app launch. Failure → password sign-in |
| Monitoring dashboard | Cloud Function or Firestore query | Rejection rate by category, p50/p95 sync latency, dead-letter count, email failure rate |
| Lint cleanup | [lib/services/queue_repository.dart](lib/services/queue_repository.dart) lines 38, 114, 120, 160, 202, 265, 282, 316 | Add missing `@override` annotations |
| Hardcoded region cleanup | [lib/config/firebase_config.dart](lib/config/firebase_config.dart) | Move `'asia-southeast1'` from email dispatch service into config |

**Acceptance:** full test matrix passes; pilot tenant runs stable for 2 weeks; metrics dashboard shows acceptable rejection/latency rates.

---

## 6. Critical path & dependencies

```
Sprint 1 (backend) ─┬─→ Sprint 2 (client refactor) ─┬─→ Sprint 3 (UX)
                    │                                │
                    └─→ Sprint 4 (server events) ────┴─→ Sprint 5 (rollout)
```

- Sprint 2 is **blocked** until Sprint 1's `submitSalesRequisition` callable is usable.
- Sprints 3 and 4 can run **in parallel** after Sprint 2.
- Sprint 5 is **sequential** — needs everything in place to test and roll out.

---

## 7. Outstanding immediate actions

- [ ] **Stash or branch-archive the in-flight email work** (don't merge to master). Files listed in §2.
- [ ] **Confirm sprint sizing** matches team capacity. Currently sized for 1–2 devs at ~2 weeks/sprint.
- [ ] **Decide which sprint to draft tickets for first.** Sprint 1 is the critical path.

---

## 8. Sprint progress log

Append entries here as work completes. Format: `YYYY-MM-DD — Sprint N — what shipped — what's next`.

(No entries yet.)

---

## 9. Decision changelog

Append entries here when decisions get revised. Don't edit §4 — record the change here so the trail is intact.

### 2026-05-03 — Sprint 1 design decisions (additions, not revisions)

- **Server-triggered email needs a PDF.** Client passes pre-generated base64 PDF as part of `submitSalesRequisition` payload. Matches the existing `sendAutoRoutedRequisitionEmail` pattern (which already takes `pdfData`). Avoids porting Dart `generateSalesPDF` logic to Node.js. Tradeoff: payload is larger (PDF can be 50–500 KB base64) — acceptable since callables support up to 10 MB.
- **`sorNumber` stays client-generated for now.** The new callable accepts whatever `sorNumber` the client provides. Idempotency comes from `clientGeneratedId` (used as the document ID). Risk: if two offline reps independently generate the same `sorNumber`, both SORs are accepted with that same display number but different `clientGeneratedId` — they're distinct records but visually conflict. **Future work**: move `sorNumber` assignment to the server (atomic counter per tenant). Logged as a follow-up.
- **New inventory enforcement.** Existing `FirestoreService.submitSOR` did not decrement stock. The new `submitSalesRequisition` callable will. Existing SORs created via the old path may have left stock counts "untouched" — verify whether stock counts in `itemMaster` / `itemsAvailable` are currently accurate or manually maintained. **Flag for Marc**: confirm before Sprint 2 cuts over.
- **Doc ID convention diverges between old and new.** Existing SORs use Firestore auto-IDs. New SORs (via callable) use `clientGeneratedId` (UUIDv7). Forward-only migration; no rename needed.
- **Inventory item lookup**: items resolved by `id` first (Firestore doc ID in `itemMaster`), falling back to `code` field. Stock decrement writes to `itemMaster.stock` (canonical) — `itemsAvailable` is treated as a denormalized read view that the existing import job rebuilds.
