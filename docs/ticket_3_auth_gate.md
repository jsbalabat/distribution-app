# Ticket 3: Auth + Connectivity Gate

## Status: COMPLETED ✓

Ticket 3 introduces a reusable submission gate that decides whether a Sales Requisition should be submitted online or queued locally based on connectivity and auth session freshness.

## Deliverables

### 1. **Auth session helpers** (`lib/services/auth_service.dart`)
- `hasFreshCachedSession()` checks the current Firebase ID token expiration without forcing a refresh
- `refreshSessionIfPossible()` attempts to refresh the token when connectivity is available
- Supports the rule that only previously authenticated sessions can continue offline

### 2. **Provider gate helpers** (`lib/providers/user_provider.dart`)
- `canSyncCurrentSession()` exposes token freshness checks to the UI
- `refreshSessionIfPossible()` exposes refresh attempts for future sync worker use

### 3. **Offline submission gate** (`lib/services/offline_submission_service.dart`)
- Checks connectivity with `connectivity_plus`
- Routes submissions to online Firestore writes when the session is fresh and refresh succeeds
- Queues submissions locally when offline or when the session needs re-login
- Marks queued submissions as `pendingSync` or `requiresRelogin`
- Generates client IDs and correlation IDs when the form payload does not already contain them

### 4. **Screen integration**
- `lib/screens/form_screen.dart` now routes through the gate before sending email or updating inventory
- `lib/screens/review_screen.dart` now routes through the gate and skips email when queued locally

## Behavioral Rules

- Online submission path remains unchanged when auth and connectivity are valid
- Offline queue path is used when connectivity is unavailable but the user still has a usable session
- `requiresRelogin` is used when the cached session is no longer fresh and sync should be blocked until re-authentication
- Email dispatch still only happens after successful online submission

## Validation

- Analyzer checks passed on all touched files
- Queue adapter registration is in place for encrypted Hive persistence
- No existing submission screens were removed; only the submission entry path was redirected

## Next Ticket

Ticket 4 can now focus on the sync worker:
- read queued items from the repository
- retry on backoff schedule
- transition queue states as online validation succeeds or fails
