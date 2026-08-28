/* eslint-disable max-len */
/* eslint-disable object-curly-spacing */
"use strict";

// Seeds a test user that can actually LOG IN against a chosen tenant database.
//
// Logging in needs THREE records to line up (see lib/services/auth_service.dart):
//   1. A Firebase Auth account (email + password)      — project-wide
//   2. companyTenants/<identifier> in the (default) DB — maps the typed company
//      identifier to a tenant database (this collection is read from the
//      (default) database, NOT the tenant one)
//   3. users/<uid> in the tenant database              — the profile, incl. role;
//      its absence is what triggers "not assigned to this company"
// Miss any one and login fails with "Unknown company identifier" or the
// "not assigned" error. This script writes all three, idempotently.
//
// Auth target — PRODUCTION by default, via Application Default Credentials.
// Run this once on the machine first:
//   gcloud auth application-default login
// (or set GOOGLE_APPLICATION_CREDENTIALS to a service-account key file path).
// To target the local emulators instead, export FIREBASE_AUTH_EMULATOR_HOST and
// FIRESTORE_EMULATOR_HOST before running — the Admin SDK auto-detects them and
// needs no real credentials.
//
// Run from the functions/ directory:
//   node test/seed-test-user.js
// Override any field via env (all optional):
//   TEST_EMAIL=you@example.com TEST_PASSWORD='S3cret!pw' TEST_IDENTIFIER=company-b \
//   TEST_DATABASE_ID=company-b TEST_ROLE=admin node test/seed-test-user.js

const admin = require("firebase-admin");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "sales-field-app-f31a2";

// The company code typed on the login screen; auth_service lowercases input,
// so we normalize here too to keep the doc id and the typed value in sync.
const IDENTIFIER = (process.env.TEST_IDENTIFIER || "company-b").toLowerCase();
const DATABASE_ID = process.env.TEST_DATABASE_ID || "company-b";
const EMAIL = process.env.TEST_EMAIL || "test.admin@companyb.example.com";
const PASSWORD = process.env.TEST_PASSWORD || "Test123!pass";
const DISPLAY_NAME = process.env.TEST_NAME || "Company B Test Admin";
// 'admin' so the dashboard's Retry-Email button (gated on isAdmin) is visible.
const ROLE = process.env.TEST_ROLE || "admin";
const COMPANY_NAME = process.env.TEST_COMPANY_NAME || "Company B";

admin.initializeApp({projectId: PROJECT_ID});

(async () => {
  const auth = getAuth();
  const defaultDb = getFirestore(admin.app()); // companyTenants lives in (default)
  const tenantDb = getFirestore(admin.app(), DATABASE_ID); // users/<uid> lives here

  // 1. Auth account — reuse the existing one when the email is already taken so
  //    re-running the seed resets the password instead of erroring out.
  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(EMAIL);
    await auth.updateUser(userRecord.uid, {password: PASSWORD, displayName: DISPLAY_NAME});
    console.log(`✓ reused Auth user ${EMAIL} (uid=${userRecord.uid}); password reset`);
  } catch (err) {
    if (err.code === "auth/user-not-found") {
      userRecord = await auth.createUser({email: EMAIL, password: PASSWORD, displayName: DISPLAY_NAME});
      console.log(`✓ created Auth user ${EMAIL} (uid=${userRecord.uid})`);
    } else {
      throw err;
    }
  }
  const uid = userRecord.uid;

  // 2. Tenant mapping in (default) so the login screen resolves the identifier.
  await defaultDb.collection("companyTenants").doc(IDENTIFIER).set({
    firestoreDatabaseId: DATABASE_ID,
    isActive: true,
    companyName: COMPANY_NAME,
  }, {merge: true});
  console.log(`✓ companyTenants/${IDENTIFIER} -> ${DATABASE_ID} (isActive: true)`);

  // 3. Profile in the tenant database — must live in DATABASE_ID, not (default).
  await tenantDb.collection("users").doc(uid).set({
    email: EMAIL,
    name: DISPLAY_NAME,
    role: ROLE,
    companyId: IDENTIFIER,
    companyName: COMPANY_NAME,
    firestoreDatabaseId: DATABASE_ID,
    isDisabled: false,
    disabled: false,
  }, {merge: true});
  console.log(`✓ users/${uid} in ${DATABASE_ID} (role: ${ROLE})`);

  console.log("\n--- log in with ---");
  console.log(`  company identifier : ${IDENTIFIER}`);
  console.log(`  email              : ${EMAIL}`);
  console.log(`  password           : ${PASSWORD}`);
  process.exit(0);
})().catch((err) => {
  console.error("SEED FAILED:", err);
  process.exit(1);
});
