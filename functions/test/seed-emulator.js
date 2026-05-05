/* eslint-disable max-len */
/* eslint-disable object-curly-spacing */
"use strict";

// Seeds the Firestore emulator (default database) with the minimum data the
// SOR submission smoke test needs. Idempotent — safe to re-run.
//
// Prerequisite: emulators running on 127.0.0.1:8080.
//
// Run from functions/ directory:
//   node test/seed-emulator.js

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "sales-field-app-f31a2";

const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

(async () => {
  // 1. Test user with admin role (so resend/rollback callable tests would also pass).
  await db.collection("users").doc("test-user-001").set({
    role: "admin",
    email: "smoketest@example.com",
    displayName: "Smoke Test User",
  });
  console.log("✓ users/test-user-001 seeded");

  // 2. Test item with sufficient stock for the smoke submit (qty=1).
  await db.collection("itemMaster").doc("item-test-001").set({
    code: "TEST-001",
    itemCode: "TEST-001",
    name: "Smoke Test Widget",
    description: "Used for SOR submission smoke tests.",
    stock: 10,
    quantity: 10,
    unitPrice: 100,
  });
  console.log("✓ itemMaster/item-test-001 seeded (stock: 10, code: TEST-001)");

  // 3. Optional: dump back to confirm.
  console.log("");
  console.log("--- verification ---");
  const userSnap = await db.collection("users").doc("test-user-001").get();
  console.log("users/test-user-001:", userSnap.exists ? userSnap.data() : "MISSING");
  const itemSnap = await db.collection("itemMaster").doc("item-test-001").get();
  console.log("itemMaster/item-test-001:", itemSnap.exists ? itemSnap.data() : "MISSING");

  process.exit(0);
})().catch((err) => {
  console.error("SEED FAILED:", err);
  process.exit(1);
});
