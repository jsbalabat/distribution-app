/* eslint-disable max-len */
/* eslint-disable object-curly-spacing */
"use strict";

// Dumps the contents of the Firestore emulator's (default) database for the
// `users` and `itemMaster` collections. Helps diagnose seeding mismatches.
//
// Run from functions/ directory while the emulator is running:
//   node test/dump-emulator.js

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "sales-field-app-f31a2";

const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

(async () => {
  console.log("=== Connected to:", process.env.FIRESTORE_EMULATOR_HOST, "project:", process.env.GCLOUD_PROJECT);
  console.log("");

  console.log("=== users collection (default DB) ===");
  const users = await db.collection("users").get();
  if (users.empty) {
    console.log("  (empty)");
  } else {
    users.docs.forEach((d) => console.log("  " + d.id, "→", JSON.stringify(d.data())));
  }
  console.log("");

  console.log("=== itemMaster collection (default DB) ===");
  const items = await db.collection("itemMaster").get();
  if (items.empty) {
    console.log("  (empty)");
  } else {
    items.docs.forEach((d) => console.log("  " + d.id, "→", JSON.stringify(d.data())));
  }
  console.log("");

  console.log("=== companyTenants collection (default DB) ===");
  const tenants = await db.collection("companyTenants").get();
  if (tenants.empty) {
    console.log("  (empty)");
  } else {
    tenants.docs.forEach((d) => console.log("  " + d.id, "→", JSON.stringify(d.data())));
  }

  process.exit(0);
})().catch((err) => {
  console.error("DUMP FAILED:", err);
  process.exit(1);
});
