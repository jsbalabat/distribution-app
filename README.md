# new_test_store

Sales requisition and inventory management app built with Flutter, Firebase, and Cloud Functions.

## Overview

`new_test_store` helps teams manage sales requisitions, inventory, customers, user roles, and operational audit logs across mobile, web, and desktop targets.

The app supports:

- Sales requisition creation and review
- Inventory quantity updates and low-stock controls
- Admin dashboards and reports
- User and role management
- Audit logging for major create, update, and delete actions
- In-app notifications for users and admins
- Admin Excel upload with direct callable import
- PDF generation and email workflows for requisitions

## Key Features

### User Workflow

- Submit sales requisitions with item lines and totals
- Review submission history with search and pagination
- Generate transaction PDFs
- Receive in-app notifications for key requisition status changes

### Admin Workflow

- View dashboard summaries and recent activity
- Manage users and roles
- Review and edit requisitions
- Inspect audit logs with filters and CSV copy export
- Upload Excel files directly from the dashboard to import customers and item data
- Trigger explicit destructive cleanup (admin-only, confirmation-required)
- Configure app settings, inventory alerts, and audit-log retention

### Operational Features

- Firestore-backed data storage
- Cloud Functions for scheduled maintenance, retention pruning, direct import, and email operations
- Environment-based Firebase config using `.env`
- Soft-delete support for requisitions so history is preserved
- Structured import and cleanup logging through Firestore and Cloud Function logs
- Multi-company support via tenant-specific Firestore database IDs selected at sign-in

## Tech Stack

- Flutter 3.8+
- Firebase Auth
- Cloud Firestore
- Firebase Cloud Functions
- Cloud Functions callable client (`cloud_functions`)
- Provider
- intl
- pdf and printing
- path_provider
- permission_handler
- file_picker

## Project Structure

- `lib/screens/` - app screens and workflows
- `lib/services/` - data access and shared services
  - `queue_repository.dart` - encrypted local queue storage for offline (Ticket 2)
  - `offline_submission_service.dart` - auth/connectivity gate and routing (Ticket 3)
- `lib/models/` - Firestore model mappings and offline sync contract enums
  - `offline_sync_contract.dart` - shared offline enums and constants (Ticket 1)
  - `queued_sales_requisition.dart` - local queue item model (Ticket 2)
  - `offline_sync_adapters.dart` - Hive serialization adapters (Ticket 2)
- `lib/utils/` - helpers, logging, and field normalization
- `lib/providers/` - state management using Provider
- `lib/widgets/` - reusable UI components
- `lib/styles/` - app-wide styling constants
- `functions/` - Firebase Cloud Functions
- `docs/` - architecture and implementation baselines
  - `offline_architecture_baseline.md` - offline contract, states, retry/rollback policy (Ticket 1)
  - `ticket_2_queue_storage.md` - queue storage implementation details (Ticket 2)
  - `ticket_3_auth_gate.md` - auth/connectivity gate and submission routing (Ticket 3)
- `test/` - unit and widget tests
  - `queue_repository_test.dart` - acceptance tests for queue storage (Ticket 2)

## Getting Started

### Prerequisites

- Flutter SDK installed
- Firebase project configured
- Node.js 20 for Cloud Functions

### Install Dependencies

```bash
flutter pub get
cd functions
npm install
```

### Environment Setup

Create a `.env` file at the project root and provide the Firebase web config values used by the app.

An example template is available in `.env.example`.

For multi-company deployments, sign in with the target company Firestore database ID in the login screen. Use `(default)` for the primary database.

### Run the App

```bash
flutter run
```

### Run Tests

```bash
flutter test
```

### Analyze the Codebase

```bash
flutter analyze
cd functions
npm run lint
```

## Firebase Notes

- Firestore rules enforce role-based access and inventory constraints
- Audit logs are stored in the `auditLogs` collection
- Notifications are stored in the `notifications` collection and can be marked as read
- Import execution summaries are stored in the `dataImports` collection
- Cleanup run summaries are stored in the `cleanupLogs` collection
- Scheduled Cloud Functions prune old audit logs based on configured retention
- Destructive cleanup is available only through an admin callable with explicit `DELETE` confirmation
- Some screens rely on Firestore indexes for ordered and filtered queries

## Configuration

Important settings live in Firestore under `settings/appSettings`:

- `autoApproveOrders`
- `lowStockAlerts`
- `emailNotifications`
- `lowStockThreshold`
- `auditLogRetentionDays`
- company contact fields

## Testing

Current test coverage includes:

- Requisition field normalization helpers
- Item model mapping
- User model defaults and admin checks
- A basic widget smoke test

Recommended next test additions:

- Firestore service tests with emulator-backed mocks
- Widget tests for dashboard and forms
- Integration tests for requisition submission and audit logging

## Deployment Notes

Before production deployment:

1. Verify Firestore rules and indexes
2. Deploy Cloud Functions
3. Confirm `.env` values are not committed
4. Run the app on all supported targets
5. Review retention and cleanup settings in admin configuration
6. Validate admin direct Excel upload in web and Android builds

## Known Limitations

- Some advanced features from the review are still future work, such as full CI/CD automation and broader offline support
- Large data sets still depend on Firestore query performance and indexes
- PDF and email workflows should be validated on each target platform before production rollout
- Direct Excel import requires the expected workbook sheet names and currently enforces an upload size limit in Cloud Functions

## Documentation Status

This README is the main entry point for setup and usage. For deeper project analysis, see `COMPREHENSIVE_README.md`.

Offline-first design baseline for Ticket 1 is documented in `docs/offline_architecture_baseline.md`.

## License

No license has been specified yet.
