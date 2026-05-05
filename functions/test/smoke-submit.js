/* eslint-disable max-len */
/* eslint-disable object-curly-spacing */
"use strict";

// Manual smoke test for submitSalesRequisition. Bypasses Functions Shell's
// Gen2 incompatibility by invoking the callable in-process via
// firebase-functions-test. Still talks to the running Firestore emulator for
// real read/write behavior.
//
// Prerequisite:
//   1. Emulators running: firebase emulators:start --only functions,firestore
//   2. Seed data in the (default) Firestore database:
//      - users/test-user-001 (any contents)
//      - itemMaster/<any> with code: "TEST-001", stock: 10
//
// Run from functions/ directory:
//   node test/smoke-submit.js
//
// Not auto-run by `npm test` (filename omits the .test.js pattern).

const PROJECT_ID = "sales-field-app-f31a2";

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || PROJECT_ID;
// FIREBASE_CONFIG is what admin.initializeApp() reads when called without
// args (which is what index.js does at module load). Without this, ftest may
// initialize admin with a different/undefined project, putting reads/writes
// in a different emulator namespace than the seed script.
process.env.FIREBASE_CONFIG = process.env.FIREBASE_CONFIG || JSON.stringify({
  projectId: PROJECT_ID,
});

const ftest = require("firebase-functions-test")({projectId: PROJECT_ID});
const fns = require("../index.js");

(async () => {
  try {
    const wrapped = ftest.wrap(fns.submitSalesRequisition);
    const result = await wrapped({
      data: {
        clientGeneratedId: "018f7c0e-9e9d-7a3a-8a3c-446655440001",
        correlationId: "smoke-1",
        actorDatabaseId: "(default)",
        sorPayload: {
          sorNumber: "SMOKE-001",
          customerName: "Smoke Test",
          items: [{
            code: "TEST-001",
            quantity: 1,
            unitPrice: 100,
            subtotal: 100,
          }],
        },
        pdfData: "JVBERi0xLjQK",
        fileName: "smoke-test.pdf",
      },
      auth: {
        uid: "test-user-001",
        token: {email: "smoketest@example.com"},
      },
    });
    console.log("RESULT:");
    console.log(JSON.stringify(result, null, 2));
  } catch (err) {
    console.error("ERROR running submitSalesRequisition:");
    console.error(err);
    process.exitCode = 1;
  } finally {
    ftest.cleanup();
  }
})();
