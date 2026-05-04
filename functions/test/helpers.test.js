/* eslint-disable max-len */
/* eslint-disable object-curly-spacing */
"use strict";

// Pure-logic unit tests for SOR submission helpers exposed via index.js
// `exports.__internal`. These tests run with Node's built-in test runner
// (`node --test`) — no extra dev dependencies required. Run via `npm test`
// from the functions/ directory.

const test = require("node:test");
const assert = require("node:assert/strict");
const {HttpsError} = require("firebase-functions/v2/https");

const {__internal} = require("../index.js");
const {
  isValidRequisitionUuid,
  validateSubmitRequisitionPayload,
  evaluateRollbackEligibility,
  buildIdempotentReplayResponse,
} = __internal;

// ===========================================================================
// isValidRequisitionUuid
// ===========================================================================

test("isValidRequisitionUuid accepts a UUIDv4", () => {
  assert.equal(isValidRequisitionUuid("550e8400-e29b-41d4-a716-446655440000"), true);
});

test("isValidRequisitionUuid accepts a UUIDv7", () => {
  assert.equal(isValidRequisitionUuid("018f7c0e-9e9d-7a3a-8a3c-446655440000"), true);
});

test("isValidRequisitionUuid trims whitespace", () => {
  assert.equal(isValidRequisitionUuid("  550e8400-e29b-41d4-a716-446655440000  "), true);
});

test("isValidRequisitionUuid is case-insensitive", () => {
  assert.equal(isValidRequisitionUuid("550E8400-E29B-41D4-A716-446655440000"), true);
});

test("isValidRequisitionUuid rejects empty string", () => {
  assert.equal(isValidRequisitionUuid(""), false);
});

test("isValidRequisitionUuid rejects non-string inputs", () => {
  assert.equal(isValidRequisitionUuid(null), false);
  assert.equal(isValidRequisitionUuid(undefined), false);
  assert.equal(isValidRequisitionUuid(12345), false);
  assert.equal(isValidRequisitionUuid({}), false);
  assert.equal(isValidRequisitionUuid([]), false);
});

test("isValidRequisitionUuid rejects truncated UUID", () => {
  assert.equal(isValidRequisitionUuid("550e8400-e29b-41d4-a716"), false);
});

test("isValidRequisitionUuid rejects garbage strings", () => {
  assert.equal(isValidRequisitionUuid("not-a-uuid"), false);
  assert.equal(isValidRequisitionUuid("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"), false);
});

test("isValidRequisitionUuid rejects unsupported version digits", () => {
  // We accept v1..v7. v8/v9/v0 should fail.
  assert.equal(isValidRequisitionUuid("550e8400-e29b-81d4-a716-446655440000"), false);
  assert.equal(isValidRequisitionUuid("550e8400-e29b-91d4-a716-446655440000"), false);
  assert.equal(isValidRequisitionUuid("550e8400-e29b-01d4-a716-446655440000"), false);
});

test("isValidRequisitionUuid rejects bad RFC variant bits", () => {
  // Position 17 must be 8/9/a/b. Anything else is non-RFC.
  assert.equal(isValidRequisitionUuid("550e8400-e29b-41d4-c716-446655440000"), false);
  assert.equal(isValidRequisitionUuid("550e8400-e29b-41d4-7716-446655440000"), false);
});

// ===========================================================================
// validateSubmitRequisitionPayload
// ===========================================================================

const VALID_UUID = "018f7c0e-9e9d-7a3a-8a3c-446655440000";

const validPayload = () => ({
  clientGeneratedId: VALID_UUID,
  correlationId: "corr-abc-123",
  sorPayload: {
    sorNumber: "SOR-0001",
    customerName: "ACME Corp",
    items: [{
      id: "item-1",
      code: "WIDGET-A",
      name: "Widget A",
      quantity: 5,
      unitPrice: 100,
      subtotal: 500,
    }],
  },
  pdfData: "JVBERi0=",
  fileName: "SOR-0001.pdf",
});

const expectInvalid = (data, msgFragment) => {
  let thrown;
  try {
    validateSubmitRequisitionPayload(data);
  } catch (err) {
    thrown = err;
  }
  assert.ok(thrown, "Expected validateSubmitRequisitionPayload to throw");
  assert.ok(
      thrown instanceof HttpsError,
      `Expected HttpsError, got ${thrown && thrown.constructor && thrown.constructor.name}`,
  );
  assert.equal(thrown.code, "invalid-argument");
  if (msgFragment) {
    assert.match(thrown.message, new RegExp(msgFragment, "i"));
  }
};

test("validateSubmitRequisitionPayload accepts a well-formed payload", () => {
  const result = validateSubmitRequisitionPayload(validPayload());
  assert.equal(result.clientGeneratedId, VALID_UUID);
  assert.equal(result.correlationId, "corr-abc-123");
  assert.equal(result.lineItems.length, 1);
  assert.equal(result.lineItems[0].quantity, 5);
  assert.equal(result.lineItems[0].unitPrice, 100);
  assert.equal(result.lineItems[0].subtotal, 500);
  assert.equal(result.fileName, "SOR-0001.pdf");
  assert.equal(result.pdfData, "JVBERi0=");
});

test("validateSubmitRequisitionPayload defaults fileName from clientGeneratedId when omitted", () => {
  const data = validPayload();
  delete data.fileName;
  const result = validateSubmitRequisitionPayload(data);
  assert.match(result.fileName, /^SOR-018f7c0e-9e9d-7a3a-8a3c-446655440000\.pdf$/);
});

test("validateSubmitRequisitionPayload defaults numeric line-item fields to 0 when missing", () => {
  const data = {
    clientGeneratedId: VALID_UUID,
    correlationId: "c",
    sorPayload: {items: [{code: "A", quantity: 2}]},
  };
  const result = validateSubmitRequisitionPayload(data);
  assert.equal(result.lineItems[0].unitPrice, 0);
  assert.equal(result.lineItems[0].subtotal, 0);
  assert.equal(result.pdfData, "");
});

test("validateSubmitRequisitionPayload rejects null data", () => {
  expectInvalid(null);
});

test("validateSubmitRequisitionPayload rejects non-object data", () => {
  expectInvalid("string");
  expectInvalid(42);
  expectInvalid(true);
});

test("validateSubmitRequisitionPayload rejects missing clientGeneratedId", () => {
  const data = validPayload();
  delete data.clientGeneratedId;
  expectInvalid(data, "clientGeneratedId");
});

test("validateSubmitRequisitionPayload rejects malformed clientGeneratedId", () => {
  const data = validPayload();
  data.clientGeneratedId = "not-a-uuid";
  expectInvalid(data, "clientGeneratedId");
});

test("validateSubmitRequisitionPayload rejects empty clientGeneratedId", () => {
  const data = validPayload();
  data.clientGeneratedId = "   ";
  expectInvalid(data, "clientGeneratedId");
});

test("validateSubmitRequisitionPayload rejects missing correlationId", () => {
  const data = validPayload();
  delete data.correlationId;
  expectInvalid(data, "correlationId");
});

test("validateSubmitRequisitionPayload rejects empty correlationId", () => {
  const data = validPayload();
  data.correlationId = "";
  expectInvalid(data, "correlationId");
});

test("validateSubmitRequisitionPayload rejects missing sorPayload", () => {
  const data = validPayload();
  delete data.sorPayload;
  expectInvalid(data, "sorPayload");
});

test("validateSubmitRequisitionPayload rejects sorPayload that's a string", () => {
  const data = validPayload();
  data.sorPayload = "oops";
  expectInvalid(data, "sorPayload");
});

test("validateSubmitRequisitionPayload rejects sorPayload that's an array", () => {
  const data = validPayload();
  data.sorPayload = [];
  expectInvalid(data, "sorPayload");
});

test("validateSubmitRequisitionPayload rejects empty items array", () => {
  const data = validPayload();
  data.sorPayload.items = [];
  expectInvalid(data, "items");
});

test("validateSubmitRequisitionPayload rejects missing items field", () => {
  const data = validPayload();
  delete data.sorPayload.items;
  expectInvalid(data, "items");
});

test("validateSubmitRequisitionPayload rejects line item with neither id nor code", () => {
  const data = validPayload();
  data.sorPayload.items = [{name: "Mystery", quantity: 1}];
  expectInvalid(data, "id or code");
});

test("validateSubmitRequisitionPayload rejects line item that's not an object", () => {
  const data = validPayload();
  data.sorPayload.items = ["string"];
  expectInvalid(data, "must be an object");
});

test("validateSubmitRequisitionPayload rejects line item with zero quantity", () => {
  const data = validPayload();
  data.sorPayload.items[0].quantity = 0;
  expectInvalid(data, "positive number");
});

test("validateSubmitRequisitionPayload rejects line item with negative quantity", () => {
  const data = validPayload();
  data.sorPayload.items[0].quantity = -3;
  expectInvalid(data, "positive number");
});

test("validateSubmitRequisitionPayload rejects line item with non-numeric quantity", () => {
  const data = validPayload();
  data.sorPayload.items[0].quantity = "abc";
  expectInvalid(data, "positive number");
});

test("validateSubmitRequisitionPayload accepts a line item with code only", () => {
  const data = validPayload();
  data.sorPayload.items = [{code: "ABC", quantity: 2}];
  const result = validateSubmitRequisitionPayload(data);
  assert.equal(result.lineItems[0].code, "ABC");
  assert.equal(result.lineItems[0].id, "");
});

// ===========================================================================
// evaluateRollbackEligibility
// ===========================================================================

const NOW = 1714780800000; // arbitrary fixed epoch ms (2024-05-04, plenty of headroom)
const tsFromMillis = (ms) => ({toMillis: () => ms});

const rollbackBase = (overrides = {}) => ({
  status: "accepted",
  emailStatus: "failed",
  autoEmailAttemptCount: 2,
  createdAt: tsFromMillis(NOW - 60 * 60 * 1000), // 1 hour ago
  ...overrides,
});

test("evaluateRollbackEligibility accepts a well-formed eligible SOR", () => {
  const result = evaluateRollbackEligibility(rollbackBase(), NOW);
  assert.equal(result.eligible, true);
  assert.equal(result.reason, null);
  assert.equal(result.detail, null);
});

test("evaluateRollbackEligibility rejects when status is rejected", () => {
  const result = evaluateRollbackEligibility(rollbackBase({status: "rejected"}), NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "not_accepted");
});

test("evaluateRollbackEligibility rejects when status is already rolled_back", () => {
  const result = evaluateRollbackEligibility(rollbackBase({status: "rolled_back"}), NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "not_accepted");
});

test("evaluateRollbackEligibility rejects when status is missing", () => {
  const data = rollbackBase();
  delete data.status;
  const result = evaluateRollbackEligibility(data, NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "not_accepted");
});

test("evaluateRollbackEligibility rejects when emailStatus is sent", () => {
  const result = evaluateRollbackEligibility(rollbackBase({emailStatus: "sent"}), NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "email_not_failed");
});

test("evaluateRollbackEligibility rejects when emailStatus is queued", () => {
  const result = evaluateRollbackEligibility(rollbackBase({emailStatus: "queued"}), NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "email_not_failed");
});

test("evaluateRollbackEligibility rejects when both emailStatus and autoEmailStatus are missing", () => {
  const data = rollbackBase();
  delete data.emailStatus;
  const result = evaluateRollbackEligibility(data, NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "email_not_failed");
});

test("evaluateRollbackEligibility falls back to autoEmailStatus when emailStatus missing", () => {
  const data = rollbackBase();
  delete data.emailStatus;
  data.autoEmailStatus = "failed";
  const result = evaluateRollbackEligibility(data, NOW);
  assert.equal(result.eligible, true);
});

test("evaluateRollbackEligibility rejects when autoEmailAttemptCount < 2", () => {
  const result = evaluateRollbackEligibility(rollbackBase({autoEmailAttemptCount: 1}), NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "insufficient_email_attempts");
});

test("evaluateRollbackEligibility rejects when autoEmailAttemptCount is 0", () => {
  const result = evaluateRollbackEligibility(rollbackBase({autoEmailAttemptCount: 0}), NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "insufficient_email_attempts");
});

test("evaluateRollbackEligibility rejects when window expired via createdAt fallback", () => {
  const data = rollbackBase({createdAt: tsFromMillis(NOW - 25 * 60 * 60 * 1000)}); // 25h ago
  const result = evaluateRollbackEligibility(data, NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "window_expired");
});

test("evaluateRollbackEligibility honors explicit rollbackAvailableUntil in the future", () => {
  const data = rollbackBase({
    createdAt: tsFromMillis(NOW - 25 * 60 * 60 * 1000), // expired by createdAt fallback
    rollbackAvailableUntil: tsFromMillis(NOW + 60 * 1000), // but explicit field still in future
  });
  const result = evaluateRollbackEligibility(data, NOW);
  // Explicit field wins over the fallback computation.
  assert.equal(result.eligible, true);
});

test("evaluateRollbackEligibility rejects when explicit rollbackAvailableUntil is in past", () => {
  const data = rollbackBase({
    createdAt: tsFromMillis(NOW - 60 * 1000), // recent, fallback would allow
    rollbackAvailableUntil: tsFromMillis(NOW - 1), // but explicit field is past
  });
  const result = evaluateRollbackEligibility(data, NOW);
  assert.equal(result.eligible, false);
  assert.equal(result.reason, "window_expired");
});

test("evaluateRollbackEligibility allows missing createdAt and missing rollbackAvailableUntil", () => {
  // No window data at all — eligibility check skips the window enforcement.
  // (This is a conservative permissive behavior; the data is malformed but we
  //  still allow rollback because we have no basis to reject.)
  const data = rollbackBase();
  delete data.createdAt;
  const result = evaluateRollbackEligibility(data, NOW);
  assert.equal(result.eligible, true);
});

test("evaluateRollbackEligibility uses Date.now() when no `now` argument provided", () => {
  // Should not throw. Eligibility decision depends on real wall clock,
  // but with createdAt 1h ago we're safely inside the window.
  const result = evaluateRollbackEligibility({
    status: "accepted",
    emailStatus: "failed",
    autoEmailAttemptCount: 2,
    createdAt: tsFromMillis(Date.now() - 60 * 60 * 1000),
  });
  assert.equal(result.eligible, true);
});

// ===========================================================================
// buildIdempotentReplayResponse
// ===========================================================================

const fakeDoc = (id, data) => ({id, data: () => data});

test("buildIdempotentReplayResponse marks accepted SOR with replay flag", () => {
  const doc = fakeDoc(VALID_UUID, {
    status: "accepted",
    sorNumber: "SOR-0001",
    emailStatus: "sent",
    correlationId: "corr-1",
  });
  const result = buildIdempotentReplayResponse(doc);
  assert.equal(result.accepted, true);
  assert.equal(result.sorId, VALID_UUID);
  assert.equal(result.sorNumber, "SOR-0001");
  assert.equal(result.emailStatus, "sent");
  assert.equal(result.idempotentReplay, true);
  assert.equal(result.correlationId, "corr-1");
  assert.deepEqual(result.rejectionReasons, []);
  assert.equal(result.rejectionCategory, null);
});

test("buildIdempotentReplayResponse marks rejected SOR with replay flag and reasons", () => {
  const reasons = [{code: "INSUFFICIENT_STOCK", itemCode: "X"}];
  const doc = fakeDoc(VALID_UUID, {
    status: "rejected",
    sorNumber: "SOR-0002",
    rejectionCategory: "inventory",
    rejectionReasons: reasons,
  });
  const result = buildIdempotentReplayResponse(doc);
  assert.equal(result.accepted, false);
  assert.equal(result.rejectionCategory, "inventory");
  assert.deepEqual(result.rejectionReasons, reasons);
  assert.equal(result.idempotentReplay, true);
});

test("buildIdempotentReplayResponse falls back to autoEmailStatus when emailStatus missing", () => {
  const doc = fakeDoc(VALID_UUID, {
    status: "accepted",
    autoEmailStatus: "sent",
  });
  const result = buildIdempotentReplayResponse(doc);
  assert.equal(result.emailStatus, "sent");
});

test("buildIdempotentReplayResponse uses doc id as sorNumber fallback", () => {
  const doc = fakeDoc(VALID_UUID, {status: "accepted"});
  const result = buildIdempotentReplayResponse(doc);
  assert.equal(result.sorNumber, VALID_UUID);
});

test("buildIdempotentReplayResponse handles empty data gracefully", () => {
  // Doc.data() returning null — helper should default safely without throwing.
  const result = buildIdempotentReplayResponse({id: VALID_UUID, data: () => null});
  assert.equal(result.sorId, VALID_UUID);
  assert.equal(result.accepted, false);
  assert.equal(result.idempotentReplay, true);
});
