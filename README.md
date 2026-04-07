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
- PDF generation and email workflows for requisitions

## Key Features

### User Workflow

- Submit sales requisitions with item lines and totals
- Review submission history with search and pagination
- Generate transaction PDFs

### Admin Workflow

- View dashboard summaries and recent activity
- Manage users and roles
- Review and edit requisitions
- Inspect audit logs with filters and CSV copy export
- Configure app settings, inventory alerts, and audit-log retention

### Operational Features

- Firestore-backed data storage
- Cloud Functions for scheduled cleanup and email operations
- Environment-based Firebase config using `.env`
- Soft-delete support for requisitions so history is preserved

## Tech Stack

- Flutter 3.8+
- Firebase Auth
- Cloud Firestore
- Firebase Cloud Functions
- Provider
- intl
- pdf and printing
- path_provider
- permission_handler

## Project Structure

- `lib/screens/` - app screens and workflows
- `lib/services/` - data access and shared services
- `lib/models/` - Firestore model mappings
- `lib/utils/` - helpers, logging, and field normalization
- `functions/` - Firebase Cloud Functions
- `test/` - unit and widget tests

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
- Scheduled Cloud Functions prune old audit logs based on the configured retention period
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

## Known Limitations

- Some advanced features from the review are still future work, such as full CI/CD automation and broader offline support
- Large data sets still depend on Firestore query performance and indexes
- PDF and email workflows should be validated on each target platform before production rollout

## Documentation Status

This README is the main entry point for setup and usage. For deeper project analysis, see `COMPREHENSIVE_README.md`.

## License

No license has been specified yet.
