# New Test Store - Sales Requisition Application

## Project Overview

**New Test Store** is a Flutter-based mobile and web application designed to facilitate sales requisition management and order processing. It integrates with Firebase/Firestore for backend services and provides both user and administrator interfaces for managing sales orders, customer data, inventory, and reporting.

**Target Platform**: Android, iOS, Web, Windows  
**Backend**: Firebase (Authentication, Cloud Firestore, Cloud Functions)  
**Architecture**: Multi-layered Flutter app with Provider for state management

---

## 📋 FEATURES

### 1. **Authentication & Authorization**
- Firebase-based email/password authentication
- Role-based access control (Admin vs. Regular User)
- Automatic user profile creation on first login
- Session persistence and logout functionality
- Secure logout with confirmation dialogs

### 2. **User Roles & Permissions**

#### Regular User Features:
- Create new sales requisitions (Sales Order Requisitions - SOR)
- View their own submissions
- Edit/update pending requisitions
- Generate PDF reports of requisitions
- Submit for review and confirmation
- Track transaction history

#### Admin Features:
- Comprehensive admin dashboard with key metrics
- Manage all users and assign roles
- View all submissions across the system
- Generate system-wide reports and analytics
- Manage customer data
- Manage inventory and item master
- User role management interface
- Access to settings and configuration

### 3. **Sales Requisition Management**
- **Multi-step form workflow** for creating sales requisitions:
  - Step 1: Customer Selection
  - Step 2: Item Selection & Quantity Entry
  - Step 3: Review & Confirmation
  - Step 4: Final Submission
- **Customer Data Integration**:
  - Search and select customers from Firestore
  - Access customer account numbers and credit information
  - Track account receivables in real-time
- **Item Management**:
  - Browse available items with stock information
  - Item code and pricing lookup
  - Inventory quantity validation
  - Automatic stock updates upon requisition
- **Dynamic Form Validation**:
  - Step-by-step validation before proceeding
  - Field-level error handling
  - Required field enforcement
- **Edit Requisitions**: Users can edit their own pending requisitions

### 4. **PDF Generation & Preview**
- Generate professional PDF documents of sales requisitions
- PDF includes:
  - SOR number and date
  - Customer details
  - Item descriptions, codes, quantities
  - Unit prices and totals
  - Remarks and special instructions
- **PDF Preview Screen**: Preview before printing/sharing
- PDF printing support through native print dialogs

### 5. **Real-time Data Synchronization**
- Firestore real-time snapshots for:
  - User submissions
  - Customer lists
  - Inventory data
  - Admin reports
- Automatic updates when data changes in the database
- Real-time status tracking of submissions

### 6. **Admin Dashboard**
- Welcome banner with user greeting
- Quick action tiles for:
  - User management
  - Report generation
  - Settings access
- Real-time statistics (number of users, submissions, etc.)
- Navigation to specialized admin screens

### 7. **Transaction Management**
- Transaction detail view with comprehensive information
- Timestamp tracking on all transactions
- Historical submission viewing
- Transaction amount tracking

### 8. **Responsive Design**
- Adaptive layouts for mobile and web
- Tablet-optimized interfaces
- Desktop web support
- Consistent styling across platforms

### 9. **Data Import/Export**
- Admin dashboard supports direct Excel file upload
- Admin-only callable import (`importDataFromExcelDirect`) processes workbook uploads
- Import summaries are persisted in Firestore (`dataImports`) for traceability

### 10. **Scheduled Data Management**
- Scheduled maintenance cleanup and dedicated audit-log retention pruning
- Admin-triggered destructive cleanup is available as a separate explicit action
- Cleanup outcomes are written to Firestore (`cleanupLogs`) for visibility

### 11. **Notifications & Audit Visibility**
- In-app notifications screen for users and admins
- Notification read-state management (`mark as read`, `mark all as read`)
- Soft-delete workflow for requisitions to preserve history
- Audit logs screen supports filtered CSV copy export

### 12. **Planned Stability Improvements (April 2026)**
- Direct upload flow hardened for web and Android file providers
- Upload logging added in UI and Cloud Functions (`[IMPORT][UI]`, `[IMPORT][DIRECT]`)
- Notifications query path adjusted to avoid composite-index runtime failures
- Focused unit/widget test coverage added for core model and utility behavior

### 13. **Multi-Company Firestore Support**
- The app can target separate Firestore databases per company
- Users select the company database ID during sign-in
- The selected database ID is persisted locally for subsequent launches
- App data, notifications, logs, and settings are resolved from the active tenant database

---

## 💪 STRENGTHS

### 1. **Well-Organized Architecture**
- Clean separation of concerns:
  - **Models** layer: `UserModel`, `Item` for type-safe data
  - **Services** layer: `AuthService`, `FirestoreService` for Firebase operations
  - **Providers** layer: `UserProvider` for state management
  - **Screens** layer: UI components and pages
  - **Widgets** layer: Reusable components (dialogs, sections)
  - **Styles** layer: Centralized theming and design system

### 2. **Robust State Management**
- Uses `Provider` package for predictable state management
- `UserProvider` handles authentication state elegantly
- Proper `ChangeNotifier` implementation with `listen: false` optimization
- Efficient state propagation without unnecessary rebuilds

### 3. **Comprehensive Firebase Security Rules**
- Well-defined Firestore rules with role-based access:
  - Users can only read/write their own data
  - Admins have elevated permissions
  - Explicit deny for collections and operations
  - Helper functions for reusable logic (`isSignedIn()`, `isAdmin()`, `isOwner()`)
- Protects sensitive admin-only collections

### 4. **Modern UI/UX Design**
- Consistent design language with `AppStyles` system:
  - Centralized color palette
  - Standardized spacing and padding
  - Reusable text styles
  - Border radius and elevation constants
- Professional monochromatic (black/white) color scheme
- Material Design 3 compliance
- Smooth animations and transitions
- Clear visual hierarchy
- Proper error messaging with user-friendly dialogs

### 5. **Production-Ready Flutter Setup**
- Proper Firebase initialization for both web and mobile
- Platform-specific optimizations (kIsWeb checks)
- Dependency management with version locking
- Flutter launcher icons configured
- Web-specific Firebase configuration

### 6. **Form Handling & Validation**
- Multi-step form with step validation
- Input validation at field level
- Error state handling
- Clear user guidance through the form process
- Confirmation dialogs for critical actions

### 7. **Error Handling Framework**
- Try-catch blocks in critical sections
- Proper exception re-throwing
- User-friendly error messages
- Graceful error recovery
- Loading state management

### 8. **Scalable Backend Infrastructure**
- Cloud Functions for server-side logic
- Scheduled tasks capability
- Excel/XLSX support for data imports
- Email integration ready (Nodemailer setup)
- Batch data operations for performance

### 9. **Accessibility & Polish**
- Proper loading states with `CircularProgressIndicator`
- Confirmation dialogs for destructive actions (logout)
- Tooltips on UI elements
- Mounted widget checks to prevent memory leaks
- Proper resource cleanup (TextEditingControllers disposal)

### 10. **Multi-Language & Localization Ready**
- `intl` package integrated for date/time formatting
- Currency formatting support (₱ symbol usage)
- Foundation for multi-language support

---

## ⚠️ WEAKNESSES

### 1. **Insufficient Error Handling & Recovery**
- **Firebase initialization error** (main.dart line 29): Silent catch-all that doesn't log or notify user
- **Network errors not handled**: No retry logic or offline support
- **Firestore exceptions** (FirestoreService): Minimal error context returned to UI
- **Missing error logs**: No logging framework (Crashlytics, custom logger)
- **User-facing errors**: Generic exception messages that don't guide users
- **Recommendation**: Implement a robust logging system and specific error handling for network failures

### 2. **Security Concerns**
- **Hardcoded Firebase API Key** in main.dart (line 14-22): Should use environment variables
- **Plaintext secrets** in web config: API keys, domains exposed
- **No input sanitization**: User inputs not validated against injection attacks
- **Missing rate limiting**: Vulnerable to brute force authentication attempts
- **No secure storage** on mobile: Could use `flutter_secure_storage` for sensitive data
- **Recommendation**: Use `.env` files, secrets management, input validation, rate limiting

### 3. **Performance Issues**
- **N+1 Query Problem**: `getCurrentUser()` called in `userStream` - could cause multiple Firestore reads
- **No pagination**: Lists load all documents at once (e.g., `getAllSubmissionsStream()`)
- **Inefficient item loading**: `fetchItems()` loads all items without filtering/pagination
- **No caching**: Repeatedly fetches same data (customers, items) without memoization
- **Large dataset handling**: No pagination in ListView/GridView builders
- **Missing indexes**: Firestore queries may scan large collections
- **Recommendation**: Implement pagination, caching, query optimization, and Firestore indexing

### 4. **Limited Error Messages & User Feedback**
- **Generic "Exception: " prefix** in error display (auth_screen.dart line 59)
- **No specific error codes**: Firebase errors not mapped to user-friendly messages
- **Missing loading states**: Some async operations lack UI feedback
- **No offline indication**: User doesn't know when offline vs. server error
- **Recommendation**: Implement error code mapping and specific user-facing messages

### 5. **Data Validation Gaps**
- **Item model inconsistency**: `Item` constructor accepts `name`, but `fromMap` expects `description` (line 6 vs 20 in item_model.dart)
- **Missing null checks**: Several places assume data exists without validation
- **No type safety**: Many `Map<String, dynamic>` without compile-time type checking
- **Timestamp issues**: `timeStamp` field used inconsistently across code
- **Recommendation**: Fix data model consistency, add null coalescing, use strong typing

### 6. **Feature Incompleteness**
- **Email functionality commented out**: PDF email feature disabled (form_screen.dart lines 18, 38)
- **Incomplete utils**: `utils/error_types.dart` imported but not fully utilized
- **No transaction rollback**: Some destructive operations are still non-transactional
- **Limited export scope**: Audit logs support CSV copy export, but broader export workflows are still limited
- **No bulk operations**: Admin bulk update/delete flows are still minimal
- **Recommendation**: Complete email integration, expand export options, and add safe bulk-operation tooling

### 7. **Testing Gaps**
- **Limited unit tests**: Basic coverage exists for models/utilities and a widget smoke test, but not service-heavy flows
- **No integration tests**: End-to-end test scenarios are still missing
- **No Firebase mocking**: Tests would require actual Firebase project
- **No UI tests**: No golden tests or widget tests
- **Recommendation**: Add service-layer unit tests, Firebase-emulator integration tests, and richer UI tests

### 8. **Database Design Issues**
- **Inconsistent naming**: Mix of camelCase and snake_case in Firestore (e.g., `timeStamp` vs `timestamp`, `userID` vs `uid`)
- **Missing timestamps**: Not all collections track creation/update times
- **No soft deletes**: Permanent deletions could cause data loss issues
- **Duplicate data**: Customer info duplicated in SOR records
- **No data versioning**: Changes to documents aren't tracked
- **Recommendation**: Standardize naming, add timestamps to all collections, implement soft deletes

### 9. **UI/UX Limitations**
- **No dark mode**: Only light theme implemented
- **Limited responsiveness**: Some widgets may overflow on small screens
- **No empty state handling**: Some screens show unclear feedback for empty lists
- **Missing search/filter**: Large lists aren't filterable
- **No sorting options**: Lists can't be sorted by different criteria
- **Navigation state**: No proper deep linking or navigation stack management
- **Recommendation**: Implement theme support, better responsive design, empty states, search/filter

### 10. **Documentation & Code Quality**
- **Minimal inline documentation**: Few comments explaining complex logic
- **No API documentation**: Services don't have JSDoc-style comments
- **Missing architecture documentation**: No design pattern explanations
- **Unused imports**: Several files import unused dependencies
- **Inconsistent code style**: Variable naming conventions vary
- **No CHANGELOG**: Version history not documented
- **Recommendation**: Add comprehensive documentation, enforce code style with linting

### 11. **Missing Advanced Features**
- **No push/device notifications**: In-app notifications exist, but push notifications are not yet implemented
- **No real-time collaboration**: Only single-user edits per requisition
- **No undo/redo**: Can't revert accidental changes
- **No versioning**: Can't compare historical versions of requisitions
- **No templates**: Can't save and reuse form templates
- **No integrations**: No third-party API integrations (accounting software, payment, etc.)

### 12. **Dependency & Configuration Issues**
- **Dependency conflicts**: `cloud_firestore` has overrides - potential version conflicts
- **Outdated flutter_lints**: May have deprecated rules
- **Dependency drift risk**: Keep `pubspec.lock` and functions lockfiles updated during upgrades
- **Android min SDK**: Set to 21 but web might need different compatibility considerations
- **Recommendation**: Resolve dependency conflicts, update linting rules, use version pinning

### 13. **Performance of PDF Generation**
- **Synchronous PDF creation**: Could block UI on large requisitions
- **No progress indication**: User doesn't see PDF generation progress
- **Memory overhead**: Large PDFs could cause memory issues
- **Recommendation**: Use async PDF generation with progress callbacks

### 14. **Backend Function Issues**
- **Destructive cleanup risk remains**: Admin-triggered destructive cleanup is available and should remain tightly controlled
- **No automatic backup before destructive cleanup**: Still a data loss risk if run accidentally
- **Timezone hardcoded**: Manila timezone only, not configurable
- **Cleanup logs not yet surfaced in dedicated UI**: Logs are written to Firestore but lack a full dashboard view
- **Recommendation**: Add backup strategy, configurable scheduling/timezone, and cleanup-log reporting screens

---

## 🔧 TECHNICAL STACK

| Layer | Technology | Version |
|-------|-----------|---------|
| **Frontend Framework** | Flutter | ^3.8.1 |
| **State Management** | Provider | ^6.1.2 |
| **Backend** | Firebase | Multiple versions |
| **Authentication** | Firebase Auth | ^5.7.0 |
| **Database** | Cloud Firestore | ^4.15.8 |
| **Cloud Functions** | Node.js | 20 |
| **PDF Generation** | pdf | ^3.10.6 |
| **Printing** | printing | ^5.13.2 |
| **Data Parsing** | XLSX (Node.js) | - |
| **Email** | Nodemailer | - |
| **Localization** | intl | ^0.20.2 |
| **Permissions** | permission_handler | ^11.0.0 |
| **File Storage** | path_provider | ^2.1.1 |

---

## 📊 SUGGESTED PRIORITY IMPROVEMENTS

### Critical (Security & Data Loss Prevention)
1. Remove hardcoded API keys and use environment-based configuration
2. Implement comprehensive error logging (Firebase Crashlytics)
3. Add input validation and sanitization
4. Fix data model inconsistencies (timestamps, field names)

### High (User Experience & Performance)
5. Implement pagination for large lists
6. Add proper caching strategy
7. Complete email integration for PDFs
8. Add proper offline support with sync queue

### Medium (Features & Testing)
9. Implement comprehensive unit and integration tests
10. Add push notifications and notification preference controls
11. Expand audit and cleanup log reporting UX
12. Add search and filter capabilities

### Low (Polish & Advanced Features)
13. Add dark mode support
14. Implement undo/redo functionality
15. Add data export capabilities (CSV, Excel)
16. Improve documentation

---

## 🚀 DEPLOYMENT CONSIDERATIONS

### Before Production Deploy:
- [ ] Run security audit on Firestore rules
- [ ] Remove all hardcoded secrets and use secret management
- [ ] Set up error logging (Crashlytics, Sentry, etc.)
- [ ] Implement monitoring and alerting
- [ ] Load test the application
- [ ] Set up staging environment with test data
- [ ] Review and optimize database indexes
- [ ] Test on all target platforms (iOS, Android, Web, Windows)
- [ ] Set up CI/CD pipeline
- [ ] Create comprehensive user documentation

---

## 📝 CONCLUSION

**Overall Assessment**: The application demonstrates solid fundamentals with good architecture, state management, and UI design. However, it requires significant security hardening, error handling improvements, and performance optimization before production deployment.

**Recommendation**: Address critical security issues first, then focus on error handling and performance improvements. The codebase has a strong foundation and should scale well with these improvements implemented.

---

**Last Updated**: April 2026  
**Version**: 1.0.0+1
