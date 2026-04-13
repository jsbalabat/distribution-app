/* eslint-disable object-curly-spacing */
/* eslint-disable max-len */
const admin = require("firebase-admin");
const {getFirestore} = require("firebase-admin/firestore");
const xlsx = require("xlsx");
const {Storage} = require("@google-cloud/storage");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const fs = require("fs");
const os = require("os");
const path = require("path");
const nodemailer = require("nodemailer");

admin.initializeApp();
const db = getFirestore();
const storage = new Storage();

const DEFAULT_DATABASE_ID = "(default)";
const CALLABLE_REGION = "asia-southeast1";
const MAX_AUTO_EMAIL_RETRIES = 3;
const DEFAULT_APPROVAL_EMAIL_PRIMARY = "";
const DEFAULT_APPROVAL_EMAIL_SECONDARY = "";
const LEGACY_PLACEHOLDER_APPROVAL_EMAIL_PRIMARY = "approval@example.com";
const LEGACY_PLACEHOLDER_APPROVAL_EMAIL_SECONDARY = "operations@example.com";
let yamlFallbackLoaded = false;

/**
 * Normalizes email settings and strips legacy placeholders.
 * @param {any} value Raw email field value.
 * @return {string} Normalized email or empty when placeholder/invalid input.
 */
function sanitizeApprovalEmailSetting(value) {
  const normalized = (value || "").toString().trim().toLowerCase();
  if (!normalized) {
    return "";
  }

  if (
    normalized === LEGACY_PLACEHOLDER_APPROVAL_EMAIL_PRIMARY ||
    normalized === LEGACY_PLACEHOLDER_APPROVAL_EMAIL_SECONDARY
  ) {
    return "";
  }

  return normalized;
}

/**
 * Returns first non-empty string from values.
 * @param {Array<any>} values Candidate values.
 * @return {string} First non-empty trimmed value.
 */
function pickFirstNonEmpty(values) {
  for (const value of values) {
    const text = (value || "").toString().trim();
    if (text) return text;
  }
  return "";
}

/**
 * Loads .env.yaml keys into process.env as a local fallback.
 */
function loadYamlCredentialFallback() {
  if (yamlFallbackLoaded) {
    return;
  }
  yamlFallbackLoaded = true;

  try {
    const envYamlPath = path.join(__dirname, ".env.yaml");
    if (!fs.existsSync(envYamlPath)) {
      return;
    }

    const content = fs.readFileSync(envYamlPath, "utf8");
    const lines = content.split(/\r?\n/);
    const loadedKeys = [];

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line || line.startsWith("#")) {
        continue;
      }

      const match = line.match(/^([A-Z0-9_]+)\s*:\s*(.*)$/);
      if (!match) {
        continue;
      }

      const key = match[1];
      const valueRaw = (match[2] || "").trim();
      const value = valueRaw.replace(/^['"]|['"]$/g, "");

      if (!process.env[key] && value) {
        process.env[key] = value;
        loadedKeys.push(key);
      }
    }

    if (loadedKeys.length > 0) {
      console.log(`[EMAIL] Loaded fallback env keys from .env.yaml: ${loadedKeys.join(",")}`);
    }
  } catch (error) {
    console.warn("[EMAIL] Failed to parse .env.yaml fallback", error);
  }
}

/**
 * Resolves email credentials from secrets first, then env fallbacks.
 * @return {{gmailEmail: string, gmailPassword: string, source: string}} Resolved credentials and source.
 */
function getConfiguredEmailCredentials() {
  loadYamlCredentialFallback();

  const envEmail = pickFirstNonEmpty([
    process.env.GMAIL_EMAIL,
    process.env.GMAIL_USER,
    process.env.EMAIL_USER,
    process.env.SMTP_USER,
  ]);
  const envPassword = pickFirstNonEmpty([
    process.env.GMAIL_PASSWORD,
    process.env.GMAIL_PASS,
    process.env.EMAIL_PASSWORD,
    process.env.SMTP_PASS,
  ]);

  const gmailEmail = pickFirstNonEmpty([envEmail]);
  const gmailPassword = pickFirstNonEmpty([envPassword]);
  const source = "env";

  return {gmailEmail, gmailPassword, source};
}

/**
 * Logs failed-precondition checkpoints with correlation id.
 * @param {string} scope Logical operation scope.
 * @param {string} reason Failure reason.
 * @param {object} meta Non-sensitive metadata for debugging.
 * @return {string} Checkpoint id.
 */
function logPreconditionCheckpoint(scope, reason, meta = {}) {
  const checkpointId = `${scope}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  console.error(
      `[CHECKPOINT][PRECONDITION] scope=${scope} checkpoint=${checkpointId} reason=${reason} meta=${JSON.stringify(meta)}`,
  );
  return checkpointId;
}

/**
 * Throws failed-precondition with checkpoint id in the message.
 * @param {string} scope Logical operation scope.
 * @param {string} reason Failure reason.
 * @param {object} meta Non-sensitive metadata for debugging.
 */
function throwFailedPreconditionWithCheckpoint(scope, reason, meta = {}) {
  const checkpointId = logPreconditionCheckpoint(scope, reason, meta);
  throw new HttpsError("failed-precondition", `${reason} [checkpoint:${checkpointId}]`);
}

/**
 * Returns a Firestore client for a target database id.
 * @param {string} databaseId Firestore database id.
 * @return {FirebaseFirestore.Firestore} Firestore client.
 */
function getTenantDb(databaseId) {
  if (!databaseId || databaseId === DEFAULT_DATABASE_ID) {
    return db;
  }
  return getFirestore(databaseId);
}

/**
 * Returns active company tenant mappings from default database.
 * @return {Promise<Array<{companyId: string, databaseId: string}>>} Active tenant mappings.
 */
async function getActiveTenants() {
  const snapshot = await db.collection("companyTenants").where("isActive", "!=", false).get();

  if (snapshot.empty) {
    return [{companyId: "default", databaseId: DEFAULT_DATABASE_ID}];
  }

  const seen = new Set();
  const tenants = [];

  snapshot.docs.forEach((doc) => {
    const data = doc.data() || {};
    const mappedDatabaseId = (data.firestoreDatabaseId || data.databaseId || DEFAULT_DATABASE_ID)
        .toString()
        .trim();
    const databaseId = mappedDatabaseId || DEFAULT_DATABASE_ID;

    if (!seen.has(databaseId)) {
      seen.add(databaseId);
      tenants.push({companyId: doc.id, databaseId: databaseId});
    }
  });

  return tenants;
}

/**
 * Resolves tenant details from callable request data.
 * Falls back to scanning active tenants for the authenticated user.
 * @param {object} data Request payload.
 * @param {string} uid Authenticated uid.
 * @return {Promise<{companyId: string, databaseId: string}>} Resolved tenant mapping.
 */
async function resolveTenantForCallable(data, uid) {
  const actorCompanyIdentifier = ((data && (data.actorCompanyIdentifier || data.actorCompanyId)) || "")
      .toString()
      .trim()
      .toLowerCase();
  const actorDatabaseId = ((data && data.actorDatabaseId) || "").toString().trim();

  const companyIdentifier = ((data && (data.companyIdentifier || data.companyId)) || "")
      .toString()
      .trim()
      .toLowerCase();
  const providedDatabaseId = ((data && data.databaseId) || "").toString().trim();

  const preferredIdentifier = actorCompanyIdentifier || companyIdentifier;
  if (preferredIdentifier) {
    const tenantDoc = await db.collection("companyTenants").doc(preferredIdentifier).get();
    if (!tenantDoc.exists) {
      throw new HttpsError("invalid-argument", `Unknown company identifier: ${preferredIdentifier}`);
    }

    const tenantData = tenantDoc.data() || {};
    if (tenantData.isActive === false) {
      throw new HttpsError("permission-denied", "Selected company is inactive.");
    }

    const databaseId = (tenantData.firestoreDatabaseId || tenantData.databaseId || DEFAULT_DATABASE_ID)
        .toString()
        .trim() || DEFAULT_DATABASE_ID;
    return {companyId: preferredIdentifier, databaseId: databaseId};
  }

  if (actorDatabaseId) {
    return {companyId: "actor_direct", databaseId: actorDatabaseId};
  }

  if (providedDatabaseId) {
    return {companyId: "direct", databaseId: providedDatabaseId};
  }

  const tenants = await getActiveTenants();
  for (const tenant of tenants) {
    const tenantDb = getTenantDb(tenant.databaseId);
    const userDoc = await tenantDb.collection("users").doc(uid).get();
    if (userDoc.exists) {
      return tenant;
    }
  }

  return {companyId: "default", databaseId: DEFAULT_DATABASE_ID};
}

/**
 * Validates company tenant identifier format.
 * @param {string} identifier Tenant identifier.
 * @return {string} Normalized identifier.
 */
function normalizeCompanyIdentifier(identifier) {
  const normalized = (identifier || "").toString().trim().toLowerCase();
  if (!/^[a-z0-9-]{2,50}$/.test(normalized)) {
    throw new HttpsError(
        "invalid-argument",
        "Company identifier must be 2-50 chars using lowercase letters, numbers, or hyphens.",
    );
  }
  return normalized;
}

/**
 * Validates user role value for admin user management callables.
 * @param {string} role User role value.
 * @return {string} Normalized role.
 */
function normalizeUserRole(role) {
  const normalized = (role || "user").toString().trim().toLowerCase();
  if (normalized !== "admin" && normalized !== "user") {
    throw new HttpsError("invalid-argument", "role must be either admin or user.");
  }
  return normalized;
}

/**
 * Deletes query results in batches of up to 500 documents.
 * @param {FirebaseFirestore.Query<FirebaseFirestore.DocumentData>} query Firestore query with batch limit applied.
 * @return {Promise<number>} Total number of deleted documents.
 */
async function deleteInBatches(query) {
  let deleted = 0;
  let hasMore = true;

  while (hasMore) {
    const snapshot = await query.get();
    if (snapshot.empty) {
      hasMore = false;
      break;
    }

    const batch = query.firestore.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    deleted += snapshot.size;
    hasMore = snapshot.size >= 500;
  }

  return deleted;
}

/**
 * Resolves audit log retention days from Firestore settings with env fallback.
 * @param {FirebaseFirestore.Firestore} firestoreDb Firestore client.
 * @return {Promise<number>} Retention period in days.
 */
async function getAuditLogRetentionDays(firestoreDb = db) {
  const defaultRetentionDays = 180;
  const envValue = Number(process.env.AUDIT_LOG_RETENTION_DAYS || defaultRetentionDays);
  const envRetentionDays = Number.isFinite(envValue) ? envValue : defaultRetentionDays;

  try {
    const settingsDoc = await firestoreDb.collection("settings").doc("appSettings").get();
    if (!settingsDoc.exists) {
      return envRetentionDays;
    }

    const configuredValue = Number(settingsDoc.get("auditLogRetentionDays"));
    const retentionDays = Number.isFinite(configuredValue) ? configuredValue : envRetentionDays;

    if (retentionDays < 30) return 30;
    if (retentionDays > 3650) return 3650;
    return Math.floor(retentionDays);
  } catch (error) {
    console.error("Failed to load auditLogRetentionDays from settings, using env/default", error);
    return envRetentionDays;
  }
}

/**
 * Reads scheduled maintenance settings from Firestore with sane defaults.
 * @param {FirebaseFirestore.Firestore} firestoreDb Firestore client.
 * @return {Promise<{enabled: boolean, hour: number, minute: number, retentionDays: number, timeZone: string}>}
 */
async function getMaintenanceScheduleSettings(firestoreDb = db) {
  const defaults = {
    enabled: true,
    hour: 0,
    minute: 0,
    retentionDays: 30,
    timeZone: process.env.MAINTENANCE_TIMEZONE || "Asia/Manila",
  };

  try {
    const settingsDoc = await firestoreDb.collection("settings").doc("appSettings").get();
    if (!settingsDoc.exists) {
      return defaults;
    }

    const data = settingsDoc.data() || {};

    const hourValue = Number(data.scheduledCleanupHour);
    const minuteValue = Number(data.scheduledCleanupMinute);
    const retentionValue = Number(data.maintenanceRetentionDays);

    const hour = Number.isFinite(hourValue) ? Math.min(23, Math.max(0, Math.floor(hourValue))) : defaults.hour;
    const minute = Number.isFinite(minuteValue) ? Math.min(59, Math.max(0, Math.floor(minuteValue))) : defaults.minute;
    const retentionDays = Number.isFinite(retentionValue) ? Math.min(3650, Math.max(1, Math.floor(retentionValue))) : defaults.retentionDays;

    const timeZone =
      typeof data.maintenanceTimeZone === "string" && data.maintenanceTimeZone.trim().length > 0 ?
      data.maintenanceTimeZone.trim() : defaults.timeZone;

    return {
      enabled: data.scheduledMaintenanceEnabled !== false,
      hour,
      minute,
      retentionDays,
      timeZone,
    };
  } catch (error) {
    console.error("Failed to load maintenance schedule settings, using defaults", error);
    return defaults;
  }
}

/**
 * Resolves date parts for a given timezone.
 * @param {Date} date Date instance in system timezone.
 * @param {string} timeZone IANA timezone string.
 * @return {{year: number, month: number, day: number, hour: number, minute: number}}
 */
function getDatePartsInTimeZone(date, timeZone) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });

  const parts = formatter.formatToParts(date);
  const values = {};
  for (const part of parts) {
    if (part.type !== "literal") {
      values[part.type] = Number(part.value);
    }
  }

  return {
    year: typeof values.year === "number" ? values.year : date.getUTCFullYear(),
    month: typeof values.month === "number" ? values.month : (date.getUTCMonth() + 1),
    day: typeof values.day === "number" ? values.day : date.getUTCDate(),
    hour: typeof values.hour === "number" ? values.hour : date.getUTCHours(),
    minute: typeof values.minute === "number" ? values.minute : date.getUTCMinutes(),
  };
}

/**
 * Verifies that the calling user is an admin user.
 * @param {string} uid Firebase Auth UID.
 * @param {FirebaseFirestore.Firestore} firestoreDb Firestore client.
 * @return {Promise<boolean>} Whether the user is an admin.
 */
async function isAdminUser(uid, firestoreDb = db) {
  if (!uid) {
    return false;
  }

  const userDoc = await firestoreDb.collection("users").doc(uid).get();
  return userDoc.exists && userDoc.data().role === "admin";
}

/**
 * Parses and validates workbook sheets used for customer import.
 * @param {xlsx.WorkBook} workbook Parsed xlsx workbook.
 * @return {{data: object[], data2: object[], data3: object[], data4: object[]}} Parsed rows per sheet.
 */
function parseWorkbookData(workbook) {
  const sheetName = "customer master";
  const sheetName2 = "acct recble";
  const sheetName3 = "item master";
  const sheetName4 = "items available";

  const sheet = workbook.Sheets[sheetName];
  const sheet2 = workbook.Sheets[sheetName2];
  const sheet3 = workbook.Sheets[sheetName3];
  const sheet4 = workbook.Sheets[sheetName4];

  if (!sheet || !sheet2 || !sheet3 || !sheet4) {
    throw new Error("Required sheets not found in the import workbook");
  }

  const options = {header: 1};
  const rows = xlsx.utils.sheet_to_json(sheet, options);
  const rows2 = xlsx.utils.sheet_to_json(sheet2, options);
  const rows3 = xlsx.utils.sheet_to_json(sheet3, options);
  const rows4 = xlsx.utils.sheet_to_json(sheet4, options);

  if (rows.length < 2 || rows2.length < 2 || rows3.length < 2 || rows4.length < 2) {
    throw new Error("One or more sheets do not contain expected headers and data.");
  }

  const headers = rows[1];
  const dataRows = rows.slice(2);
  const headers2 = rows2[1];
  const dataRows2 = rows2.slice(2);
  const headers3 = rows3[1];
  const dataRows3 = rows3.slice(2);
  const headers4 = rows4[1];
  const dataRows4 = rows4.slice(2);

  const data = dataRows.map((row) => {
    const obj = {};
    headers.forEach((header, i) => {
      if (header) obj[header.toString().trim()] = row[i];
    });
    return obj;
  });

  const data2 = dataRows2.map((row2) => {
    const obj = {};
    headers2.forEach((header, i) => {
      if (header) obj[header.toString().trim()] = row2[i];
    });
    return obj;
  });

  const data3 = dataRows3.map((row3) => {
    const obj = {};
    headers3.forEach((header, i) => {
      if (header) obj[header.toString().trim()] = row3[i];
    });
    return obj;
  });

  const data4 = dataRows4.map((row4) => {
    const obj = {};
    headers4.forEach((header, i) => {
      if (!header) return;

      const key = header.toString().trim();
      const incomingValue = row4[i];
      const existingValue = obj[key];

      const isExistingEmpty =
        existingValue === undefined ||
        existingValue === null ||
        existingValue === "";
      const isIncomingEmpty =
        incomingValue === undefined ||
        incomingValue === null ||
        incomingValue === "";

      if (isExistingEmpty) {
        obj[key] = incomingValue;
        return;
      }

      if (isIncomingEmpty) {
        return;
      }

      // Duplicate header names are possible in this workbook.
      // Preserve both values so quantity resolution can still find a non-empty cell.
      if (Array.isArray(existingValue)) {
        existingValue.push(incomingValue);
        obj[key] = existingValue;
      } else {
        obj[key] = [existingValue, incomingValue];
      }
    });
    return obj;
  });

  return {data, data2, data3, data4};
}

/**
 * Normalizes an import header or lookup key for flexible matching.
 * @param {unknown} value Key value from the workbook row.
 * @return {string} Normalized key string.
 */
function normalizeImportKey(value) {
  const normalizedValue = value === undefined || value === null ? "" : value;
  return normalizedValue
      .toString()
      .trim()
      .toLowerCase()
      .replace(/\s+/g, " ");
}

/**
 * Reads the first non-empty matching value from a workbook row.
 * @param {object} row Parsed workbook row.
 * @param {string[]} preferredKeys Candidate keys to match.
 * @return {unknown} Matched cell value.
 */
function readImportValue(row, preferredKeys) {
  if (!row || typeof row !== "object") {
    return undefined;
  }

  for (const key of preferredKeys) {
    if (
      Object.prototype.hasOwnProperty.call(row, key) &&
      row[key] !== undefined &&
      row[key] !== null &&
      row[key] !== ""
    ) {
      return row[key];
    }
  }

  const entries = Object.entries(row);
  for (const key of preferredKeys) {
    const normalizedKey = normalizeImportKey(key);
    const match = entries.find(([rowKey, rowValue]) => {
      return (
        normalizeImportKey(rowKey) === normalizedKey &&
        rowValue !== undefined &&
        rowValue !== null &&
        rowValue !== ""
      );
    });

    if (match) {
      return match[1];
    }
  }

  return undefined;
}

/**
 * Parses workbook cell content into a number.
 * @param {unknown} value Cell value from Excel.
 * @param {number} fallback Value to use when parsing fails.
 * @return {number} Parsed numeric value.
 */
function parseImportNumber(value, fallback = 0) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      const parsed = parseImportNumber(entry, Number.NaN);
      if (!Number.isNaN(parsed)) {
        return parsed;
      }
    }
    return fallback;
  }

  if (typeof value === "number") {
    return Number.isFinite(value) ? value : fallback;
  }

  if (typeof value === "string") {
    const normalized = value.replace(/[\s,]+/g, "").trim();
    if (!normalized) {
      return fallback;
    }

    const parsed = Number(normalized);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/**
 * Reads tenant auto-email settings with sensible defaults.
 * @param {FirebaseFirestore.Firestore} tenantDb Tenant Firestore client.
 * @return {Promise<{autoEmailEnabled: boolean, approvalEmailPrimary: string, approvalEmailSecondary: string, approvalEmailsLocked: boolean}>}
 */
async function getAutoEmailSettings(tenantDb) {
  const defaults = {
    autoEmailEnabled: false,
    approvalEmailPrimary: DEFAULT_APPROVAL_EMAIL_PRIMARY,
    approvalEmailSecondary: DEFAULT_APPROVAL_EMAIL_SECONDARY,
    approvalEmailsLocked: false,
  };

  try {
    const settingsDoc = await tenantDb.collection("settings").doc("appSettings").get();
    if (!settingsDoc.exists) {
      return defaults;
    }

    const data = settingsDoc.data() || {};
    const approvalEmailPrimary = sanitizeApprovalEmailSetting(data.approvalEmailPrimary);
    const approvalEmailSecondary = sanitizeApprovalEmailSetting(data.approvalEmailSecondary);

    return {
      autoEmailEnabled: data.autoEmailEnabled === true,
      approvalEmailPrimary: approvalEmailPrimary,
      approvalEmailSecondary: approvalEmailSecondary,
      approvalEmailsLocked: data.approvalEmailsLocked === true,
    };
  } catch (error) {
    console.error("Failed to load auto-email settings, using defaults", error);
    return defaults;
  }
}

/**
 * Determines approval routing based on requisition remarks.
 * @param {object} requisitionData Requisition document data.
 * @return {{route: string, reasons: string[]}}
 */
function evaluateApprovalRoute(requisitionData) {
  const reasons = [];
  const remark1 = ((requisitionData && requisitionData.remark1) || "").toString().trim();
  const remark2 = ((requisitionData && requisitionData.remark2) || "").toString().trim();

  if (remark1) reasons.push("remark1");
  if (remark2) reasons.push("remark2");

  return {
    route: reasons.length > 0 ? "approval_required" : "auto_clear",
    reasons: reasons,
  };
}

/**
 * Builds placeholder email content for auto-routing notifications.
 * @param {object} params Template parameters.
 * @return {{subject: string, html: string}}
 */
function buildAutoRouteEmailTemplate(params) {
  const route = params.route;
  const sorNumber = (params.sorNumber || "N/A").toString();
  const customerName = (params.customerName || "N/A").toString();
  const reasons = Array.isArray(params.reasons) ? params.reasons : [];
  const reasonText = reasons.length ? reasons.join(", ") : "none";

  if (route === "approval_required") {
    return {
      subject: `[Approval Required] Sales Requisition ${sorNumber}`,
      html: `
        <p>This is a placeholder approval email template.</p>
        <p>Sales requisition <strong>${sorNumber}</strong> for <strong>${customerName}</strong> requires review.</p>
        <p>Detected notices: <strong>${reasonText}</strong>.</p>
        <p>Please review the attached invoice PDF.</p>
      `,
    };
  }

  return {
    subject: `[No Issues] Sales Requisition ${sorNumber}`,
    html: `
      <p>This is a placeholder no-issues email template.</p>
      <p>Sales requisition <strong>${sorNumber}</strong> for <strong>${customerName}</strong> was submitted without notices.</p>
      <p>Please see attached invoice PDF for reference.</p>
    `,
  };
}

/**
 * Validates email format for settings-managed recipient addresses.
 * @param {string} email Email address.
 * @return {boolean} Whether format is valid.
 */
function isValidEmailAddress(email) {
  const normalized = (email || "").toString().trim();
  if (!normalized) return false;
  const emailRegex = /^[\w-.]+@([\w-]+\.)+[\w-]{2,}$/;
  return emailRegex.test(normalized);
}

/**
 * Finds the tenant database that contains the requisition document.
 * @param {string} requisitionId Requisition document id.
 * @return {Promise<{companyId: string, databaseId: string, tenantDb: FirebaseFirestore.Firestore}|null>}
 */
async function findTenantForRequisitionId(requisitionId) {
  if (!requisitionId) return null;

  const tenants = await getActiveTenants();
  for (const tenant of tenants) {
    const tenantDb = getTenantDb(tenant.databaseId);
    const requisitionDoc = await tenantDb.collection("salesRequisitions").doc(requisitionId).get();
    if (requisitionDoc.exists) {
      return {
        companyId: tenant.companyId,
        databaseId: tenant.databaseId,
        tenantDb: tenantDb,
      };
    }
  }

  return null;
}

/**
 * Writes a routed email log entry with defensive error handling.
 * @param {FirebaseFirestore.Firestore} tenantDb Tenant Firestore client.
 * @param {object} payload Log payload.
 * @return {Promise<void>}
 */
async function writeAutoEmailLog(tenantDb, payload) {
  try {
    await tenantDb.collection("emailLogs").add({
      type: "requisition_auto_route",
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      ...payload,
    });
  } catch (error) {
    console.error("[AUTO-EMAIL] Failed to write emailLogs record", error);
  }
}

/**
 * Sums numeric quantities in columns named like "area 1", "area 2", etc.
 * @param {object} row Parsed workbook row.
 * @return {number} Summed area quantity.
 */
function sumAreaQuantities(row) {
  if (!row || typeof row !== "object") {
    return 0;
  }

  let total = 0;
  for (const [key, value] of Object.entries(row)) {
    if (!/^area\s*\d+$/i.test(normalizeImportKey(key))) {
      continue;
    }

    const parsed = parseImportNumber(value, Number.NaN);
    if (!Number.isNaN(parsed)) {
      total += parsed;
    }
  }

  return total;
}

/**
 * Writes parsed import rows into Firestore in batched chunks.
 * @param {{data: object[], data2: object[], data3: object[], data4: object[]}} parsed Parsed workbook rows.
 * @param {FirebaseFirestore.Firestore} firestoreDb Firestore client.
 * @return {Promise<object>} Insert summary by collection.
 */
async function importParsedWorkbookData(parsed, firestoreDb = db) {
  let batch = firestoreDb.batch();
  let operations = 0;

  const summary = {
    customers: 0,
    accountReceivable: 0,
    itemMaster: 0,
    itemsAvailable: 0,
  };

  /**
   * Commits current batch when threshold is reached or forced.
   * @param {boolean} force Whether to force commit regardless of operation count.
   * @return {Promise<void>}
   */
  async function flushBatchIfNeeded(force = false) {
    if (operations === 0) return;
    if (!force && operations < 450) return;
    await batch.commit();
    batch = firestoreDb.batch();
    operations = 0;
  }

  /**
   * Adds a single document write into the current import batch.
   * @param {string} collectionName Target Firestore collection.
   * @param {object} payload Document payload to insert.
   * @return {Promise<void>}
   */
  async function addDoc(collectionName, payload) {
    const ref = firestoreDb.collection(collectionName).doc();
    batch.set(ref, {
      ...payload,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    operations += 1;
    summary[collectionName] += 1;
    await flushBatchIfNeeded();
  }

  for (const row of parsed.data) {
    const name = row.name || row.Name || row["Customer Name"];
    if (!name) continue;

    const creditLimit = parseFloat(row.creditLimit || row["Credit Limit"] || 0);
    const accountNumber = row.accountNumber || row["Account Number"] || "";
    const postalAddress = row.postalAddress || row["Postal Address"] || "";
    const paymentTerms = row.paymentTerms || row["Pmt. Terms"] || "";
    const priceLevel = row.priceLevel || row["Price Level"] || "";
    const deliveryRoute = row.deliveryRoute || row["Delivery Route"] || "";
    const area = row.area || row["Area"] || "";

    await addDoc("customers", {
      name: name.toString().trim(),
      creditLimit,
      accountNumber: accountNumber.toString().trim(),
      postalAddress: postalAddress.toString().trim(),
      paymentTerms: paymentTerms.toString().trim(),
      priceLevel: priceLevel.toString().trim(),
      deliveryRoute: deliveryRoute.toString().trim(),
      area: area.toString().trim(),
    });
  }

  for (const row2 of parsed.data2) {
    const name = row2.name || row2.Name || row2["Customer"];
    if (!name) continue;

    const accountNumber = row2.accountNumber || row2["Customer ID"] || "";
    const amountDue = parseFloat(row2.amountDue || row2["Amount Due"] || 0);
    const overThirtyDays = parseFloat(row2.overThirtyDays || row2["Over 30 Days"] || 0);
    const unsecured = parseFloat(row2.unsecured || row2["Unsecured"] || 0);

    await addDoc("accountReceivable", {
      name: name.toString().trim(),
      accountNumber: accountNumber.toString().trim(),
      amountDue,
      overThirtyDays,
      unsecured,
    });
  }

  for (const row3 of parsed.data3) {
    const productGroup = row3.productGroup || row3["Product Group"] || "";
    if (!productGroup) continue;

    const description = row3.description || row3.Description || row3["Description"];
    const itemCode = row3.itemCode || row3["Item Code"] || "";
    const itemType = row3.itemType || row3["ITEM TYPE"] || "";
    const conversionFactor = parseFloat(row3.conversionFactor || row3["CONVERSION FACTOR"] || 0);
    const regularPrice = parseFloat(row3.regular || row3["REGULAR"] || 0);
    const rmlInclusivePrice = parseFloat(row3["RML INCLUSIVE"] || 0);
    const specialOD = parseFloat(row3["SPECIAL OD"] || 0);

    await addDoc("itemMaster", {
      productGroup: productGroup.toString().trim(),
      description: (description || "").toString().trim(),
      itemCode: itemCode.toString().trim(),
      conversionFactor,
      regularPrice,
      rmlInclusivePrice,
      specialOD,
      itemType: itemType.toString().trim(),
    });
  }

  for (const row4 of parsed.data4) {
    const date = row4.date || row4.Date || row4["Date"] || "";
    if (!date) continue;

    const area = row4.area || row4.Area || row4["Area"] || "";
    const productGroup = row4.productGroup || row4["Product Group"] || "";
    const itemCode = row4.itemCode || row4["Item Code"] || "";
    const description = row4.description || row4.Description || row4["Description"];
    const rawQuantity = readImportValue(row4, [
      "quantity",
      "Quantity",
      "NET QTY AVAILABLE FOR SALE",
      "NET QTY AVAILBALE FOR SALE",
    ]);
    let quantity = parseImportNumber(rawQuantity, Number.NaN);
    if (Number.isNaN(quantity)) {
      quantity = sumAreaQuantities(row4);
    }
    if (!Number.isFinite(quantity)) {
      quantity = 0;
    }

    await addDoc("itemsAvailable", {
      date: date.toString().trim(),
      area: area.toString().trim(),
      productGroup: productGroup.toString().trim(),
      itemCode: itemCode.toString().trim(),
      description: (description || "").toString().trim(),
      quantity,
    });
  }

  await flushBatchIfNeeded(true);
  return summary;
}

// ========================================
// SCHEDULED CLEANUP FUNCTION
// Runs every 5 minutes and executes only at configured daily time
// Prunes old operational records while preserving live data
// ========================================

exports.deleteAllDataExceptUsersAndLogs = onSchedule(
    {
      schedule: "*/5 * * * *", // Poll every 5 minutes; run only at configured time
      memory: "512MiB",
    },
    async (event) => {
      const nowDate = new Date();
      const tenants = await getActiveTenants();
      const tenantResults = [];

      for (const tenant of tenants) {
        const tenantDb = getTenantDb(tenant.databaseId);
        const scheduleSettings = await getMaintenanceScheduleSettings(tenantDb);
        const now = getDatePartsInTimeZone(nowDate, scheduleSettings.timeZone);

        if (!scheduleSettings.enabled) {
          tenantResults.push({
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            skipped: true,
            reason: "disabled",
          });
          continue;
        }

        const withinMinuteWindow =
          now.hour === scheduleSettings.hour &&
          now.minute >= scheduleSettings.minute &&
          now.minute < (scheduleSettings.minute + 5);

        if (!withinMinuteWindow) {
          tenantResults.push({
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            skipped: true,
            reason: "outside_scheduled_window",
          });
          continue;
        }

        try {
          const runTimestamp = admin.firestore.Timestamp.now();
          let totalDeleted = 0;
          const deletionDetails = {};

          const retentionDays = scheduleSettings.retentionDays;
          const cutoffDate = new Date();
          cutoffDate.setDate(cutoffDate.getDate() - retentionDays);
          const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

          const collectionsToPrune = [
            {name: "dataImports", field: "requestedAt"},
            {name: "cleanupLogs", field: "executedAt"},
          ];

          const preservedCollections = [
            "customers",
            "accountReceivable",
            "itemMaster",
            "itemsAvailable",
            "salesRequisitions",
            "users",
            "emailLogs",
            "auditLogs",
            "notifications",
          ];

          for (const collectionConfig of collectionsToPrune) {
            const query = tenantDb
                .collection(collectionConfig.name)
                .where(collectionConfig.field, "<", cutoffTimestamp)
                .limit(500);

            const collectionDeleted = await deleteInBatches(query);
            deletionDetails[collectionConfig.name] = collectionDeleted;
            totalDeleted += collectionDeleted;
          }

          await tenantDb.collection("cleanupLogs").add({
            executedAt: runTimestamp,
            type: "scheduled_maintenance",
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            totalDocumentsDeleted: totalDeleted,
            deletionDetails: deletionDetails,
            preservedCollections: preservedCollections,
            deletedCollections: collectionsToPrune.map((item) => item.name),
            retentionDays: retentionDays,
            scheduledHour: scheduleSettings.hour,
            scheduledMinute: scheduleSettings.minute,
            scheduleTimeZone: scheduleSettings.timeZone,
            status: "success",
            message: `Maintenance cleanup: ${totalDeleted} old documents deleted from ${collectionsToPrune.length} collections`,
          });

          tenantResults.push({
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            success: true,
            totalDeleted: totalDeleted,
            details: deletionDetails,
          });
        } catch (error) {
          await tenantDb.collection("cleanupLogs").add({
            executedAt: admin.firestore.Timestamp.now(),
            type: "scheduled_maintenance",
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            scheduledHour: scheduleSettings.hour,
            scheduledMinute: scheduleSettings.minute,
            scheduleTimeZone: scheduleSettings.timeZone,
            status: "failed",
            error: error.message,
            errorStack: error.stack,
          });

          tenantResults.push({
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            success: false,
            error: error.message,
          });
        }
      }

      return {
        success: true,
        tenantResults: tenantResults,
      };
    },
);

// ========================================
// SCHEDULED AUDIT LOG RETENTION CLEANUP
// Keeps recent audit logs, prunes old entries
// ========================================

exports.pruneAuditLogs = onSchedule(
    {
      schedule: "30 1 * * *", // Runs daily at 01:30
      timeZone: "Asia/Manila",
      memory: "256MiB",
    },
    async (event) => {
      const tenants = await getActiveTenants();
      const tenantResults = [];

      for (const tenant of tenants) {
        const tenantDb = getTenantDb(tenant.databaseId);
        const retentionDays = await getAuditLogRetentionDays(tenantDb);
        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - retentionDays);
        const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

        try {
          const pruneQuery = tenantDb
              .collection("auditLogs")
              .where("timestamp", "<", cutoffTimestamp)
              .limit(500);

          const deletedCount = await deleteInBatches(pruneQuery);

          await tenantDb.collection("cleanupLogs").add({
            executedAt: admin.firestore.Timestamp.now(),
            type: "audit_log_prune",
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            status: "success",
            retentionDays: retentionDays,
            cutoffTimestamp: cutoffTimestamp,
            deletedCount: deletedCount,
            message: `Pruned ${deletedCount} audit logs older than ${retentionDays} days`,
          });

          tenantResults.push({
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            success: true,
            deletedCount: deletedCount,
          });
        } catch (error) {
          await tenantDb.collection("cleanupLogs").add({
            executedAt: admin.firestore.Timestamp.now(),
            type: "audit_log_prune",
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            status: "failed",
            retentionDays: retentionDays,
            error: error.message,
            errorStack: error.stack,
          });

          tenantResults.push({
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            success: false,
            error: error.message,
          });
        }
      }

      return {
        success: true,
        tenantResults: tenantResults,
      };
    },
);

// ========================================
// DESTRUCTIVE CLEANUP FUNCTION - Admin triggered only
// Deletes live business data on explicit confirmation
// ========================================

exports.runDestructiveCleanup = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 540,
      memory: "512MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in to run cleanup.");
      }

      const callerUid = request.auth.uid;
      const tenant = await resolveTenantForCallable(request.data, callerUid);
      const tenantDb = getTenantDb(tenant.databaseId);
      const isAdmin = await isAdminUser(callerUid, tenantDb);
      if (!isAdmin) {
        throw new HttpsError("permission-denied", "Admin access is required.");
      }

      const confirmText = (request.data && request.data.confirmText) || "";
      if (confirmText !== "DELETE") {
        throw new HttpsError(
            "invalid-argument",
            "Confirmation text must be \"DELETE\".",
        );
      }

      const reason = (request.data && request.data.reason) || "manual admin cleanup";
      const collectionsToDelete = [
        "customers",
        "accountReceivable",
        "itemMaster",
        "itemsAvailable",
        "salesRequisitions",
        "dataImports",
        "notifications",
      ];

      try {
        const deletionDetails = {};
        let totalDeleted = 0;

        for (const collectionName of collectionsToDelete) {
          const deletedCount = await deleteInBatches(
              tenantDb.collection(collectionName).limit(500),
          );
          deletionDetails[collectionName] = deletedCount;
          totalDeleted += deletedCount;
        }

        await tenantDb.collection("cleanupLogs").add({
          executedAt: admin.firestore.Timestamp.now(),
          type: "destructive_cleanup",
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          status: "success",
          triggeredBy: callerUid,
          reason: reason,
          deletedCollections: collectionsToDelete,
          deletionDetails: deletionDetails,
          totalDocumentsDeleted: totalDeleted,
          message: `Destructive cleanup deleted ${totalDeleted} documents from ${collectionsToDelete.length} collections`,
        });

        return {
          success: true,
          totalDeleted: totalDeleted,
          deletedCollections: collectionsToDelete,
          details: deletionDetails,
        };
      } catch (error) {
        await tenantDb.collection("cleanupLogs").add({
          executedAt: admin.firestore.Timestamp.now(),
          type: "destructive_cleanup",
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          status: "failed",
          triggeredBy: callerUid,
          reason: reason,
          error: error.message,
          errorStack: error.stack,
        });

        throw new HttpsError(
            "internal",
            `Destructive cleanup failed: ${error.message}`,
        );
      }
    },
);

// ========================================
// DIRECT EXCEL IMPORT - Admin upload via callable
// ========================================

exports.importDataFromExcelDirect = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 540,
      memory: "1GiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in to import data.");
      }

      const callerUid = request.auth.uid;
      const tenant = await resolveTenantForCallable(request.data, callerUid);
      const tenantDb = getTenantDb(tenant.databaseId);
      console.log(
          `[IMPORT][DIRECT] Request received from uid=${callerUid}, ` +
          `company=${tenant.companyId}, database=${tenant.databaseId}`,
      );
      const isAdmin = await isAdminUser(callerUid, tenantDb);
      if (!isAdmin) {
        console.warn(`[IMPORT][DIRECT] Permission denied for uid=${callerUid}`);
        throw new HttpsError("permission-denied", "Admin access is required.");
      }

      const fileName = (request.data && request.data.fileName) || "upload.xlsx";
      const fileBase64 = (request.data && request.data.fileBase64) || "";

      if (!fileBase64) {
        throw new HttpsError("invalid-argument", "Missing file content.");
      }

      try {
        const fileBuffer = Buffer.from(fileBase64, "base64");
        console.log(`[IMPORT][DIRECT] Decoded file ${fileName} (${fileBuffer.length} bytes)`);
        if (fileBuffer.length === 0) {
          throw new HttpsError("invalid-argument", "Uploaded file is empty.");
        }

        const maxBytes = 8 * 1024 * 1024;
        if (fileBuffer.length > maxBytes) {
          throw new HttpsError(
              "invalid-argument",
              "Uploaded file is too large. Please keep it under 8 MB.",
          );
        }

        const workbook = xlsx.read(fileBuffer, {type: "buffer"});
        const parsed = parseWorkbookData(workbook);
    console.log(
      `[IMPORT][DIRECT] Parsed workbook rows: ` +
      `customer master=${parsed.data.length}, acct recble=${parsed.data2.length}, ` +
      `item master=${parsed.data3.length}, items available=${parsed.data4.length}`,
    );

        const summary = await importParsedWorkbookData(parsed, tenantDb);
    console.log(`[IMPORT][DIRECT] Firestore write summary: ${JSON.stringify(summary)}`);

        await tenantDb.collection("dataImports").add({
          status: "completed",
          source: "directUpload",
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          fileName: fileName,
          requestedByUid: callerUid,
          requestedByEmail: request.auth.token.email || "unknown",
          requestedAt: admin.firestore.FieldValue.serverTimestamp(),
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          summary: summary,
        });

        console.log(`[IMPORT][DIRECT] Import completed successfully for ${fileName}`);

        return {
          success: true,
          message: "Import completed successfully.",
          summary: summary,
        };
      } catch (error) {
        console.error(`[IMPORT][DIRECT] Import failed for ${fileName}:`, error);
        throw new HttpsError(
            "internal",
            `Direct upload import failed: ${error.message}`,
        );
      }
    },
);

// ========================================
// EMAIL SENDING FUNCTION
// ========================================

exports.sendSalesRequisitionEmail = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 60,
      memory: "128MiB",
      cpu: "gcf_gen1",
      maxInstances: 1,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "User must be authenticated to send emails",
        );
      }

      const callerUid = request.auth.uid;
      const tenant = await resolveTenantForCallable(request.data, callerUid);
      const tenantDb = getTenantDb(tenant.databaseId);

      const {to, subject, pdfData, fileName, customerName, sorNumber} = request.data;

      if (!to || !pdfData || !fileName) {
        throw new HttpsError(
            "invalid-argument",
            "Missing required fields: to, pdfData, or fileName",
        );
      }

      const emailRegex = /^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$/;
      if (!emailRegex.test(to)) {
        throw new HttpsError(
            "invalid-argument",
            "Invalid email address",
        );
      }

      try {
        const {gmailEmail, gmailPassword, source} = getConfiguredEmailCredentials();

        if (!gmailEmail || !gmailPassword) {
          const envYamlPath = path.join(__dirname, ".env.yaml");
          throwFailedPreconditionWithCheckpoint(
              "sendSalesRequisitionEmail.credentials",
              "Email service is not properly configured. Missing GMAIL_EMAIL or GMAIL_PASSWORD.",
              {
                hasEmail: Boolean(gmailEmail),
                hasPassword: Boolean(gmailPassword),
                source: source,
                hasEnvGmailEmail: Boolean(process.env.GMAIL_EMAIL),
                hasEnvGmailPassword: Boolean(process.env.GMAIL_PASSWORD),
                hasEnvGmailUser: Boolean(process.env.GMAIL_USER),
                hasEnvSmtpUser: Boolean(process.env.SMTP_USER),
                hasEnvYamlFile: fs.existsSync(envYamlPath),
              },
          );
        }

        const gmailTransporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: gmailEmail,
            pass: gmailPassword,
          },
        });

        const pdfBuffer = Buffer.from(pdfData, "base64");

        const mailOptions = {
          from: `Sales Team <${gmailEmail}>`,
          to: to,
          subject: subject || `Sales Requisition Order - ${sorNumber}`,
          html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <div style="background-color: #5E4BA6; padding: 20px; border-radius: 8px 8px 0 0;">
              <h2 style="color: white; margin: 0;">Sales Requisition Order</h2>
            </div>
            
            <div style="background-color: #f9f9f9; padding: 20px; border: 1px solid #ddd; border-top: none;">
              <p style="font-size: 16px; color: #333;">Dear ${customerName || "Valued Customer"},</p>
              
              <p style="font-size: 14px; color: #666; line-height: 1.6;">
                Please find attached your Sales Requisition Order (SOR #${sorNumber}).
              </p>
              
              <div style="background-color: #f2edff; padding: 15px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #5E4BA6;">
                <h3 style="color: #5E4BA6; margin-top: 0; font-size: 16px;">Order Details</h3>
                <table style="width: 100%; font-size: 14px; color: #333;">
                  <tr>
                    <td style="padding: 5px 0;"><strong>SOR Number:</strong></td>
                    <td style="padding: 5px 0;">${sorNumber}</td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;"><strong>Customer:</strong></td>
                    <td style="padding: 5px 0;">${customerName}</td>
                  </tr>
                  <tr>
                    <td style="padding: 5px 0;"><strong>Date:</strong></td>
                    <td style="padding: 5px 0;">${new Date().toLocaleDateString()}</td>
                  </tr>
                </table>
              </div>
              
              <p style="font-size: 14px; color: #666; line-height: 1.6;">
                If you have any questions or concerns regarding this order, please don't hesitate to contact us.
              </p>
              
              <p style="margin-top: 30px; font-size: 14px; color: #333;">
                Best regards,<br>
                <strong style="color: #5E4BA6;">Sales Team</strong>
              </p>
            </div>
            
            <div style="background-color: #f0f0f0; padding: 15px; text-align: center; border-radius: 0 0 8px 8px;">
              <p style="color: #666; font-size: 12px; margin: 0;">
                This is an automated email. Please do not reply to this message.
              </p>
            </div>
          </div>
        `,
          attachments: [
            {
              filename: fileName,
              content: pdfBuffer,
              contentType: "application/pdf",
            },
          ],
        };

        await gmailTransporter.sendMail(mailOptions);

        // Calculate expiration date (30 days from now)
        const expirationDate = new Date();
        expirationDate.setDate(expirationDate.getDate() + 30);
        const expiresAt = admin.firestore.Timestamp.fromDate(expirationDate);

        await tenantDb.collection("emailLogs").add({
          to: to,
          subject: mailOptions.subject,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          sorNumber: sorNumber,
          customerName: customerName,
          sentBy: callerUid,
          sentByEmail: request.auth.token.email || "unknown",
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          status: "success",
          expiresAt: expiresAt, // Add TTL field
        });

        console.log(`Email sent successfully to ${to} for SOR #${sorNumber}`);

        return {
          success: true,
          message: `Email sent successfully to ${to}`,
          timestamp: new Date().toISOString(),
        };
      } catch (error) {
        console.error("Error sending email:", error);

        if (error instanceof HttpsError) {
          throw error;
        }

        // Calculate expiration date (30 days from now)
        const expirationDate = new Date();
        expirationDate.setDate(expirationDate.getDate() + 30);
        const expiresAt = admin.firestore.Timestamp.fromDate(expirationDate);

        await tenantDb.collection("emailLogs").add({
          to: to,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          sorNumber: sorNumber,
          customerName: customerName,
          sentBy: request.auth && request.auth.uid ? request.auth.uid : null,
          sentByEmail: request.auth && request.auth.token ? request.auth.token.email || "unknown" : "unknown",
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          status: "failed",
          error: error.message,
          errorStack: error.stack,
          expiresAt: expiresAt, // Add TTL field
        });

        throw new HttpsError(
            "internal",
            `Failed to send email: ${error.message}`,
        );
      }
    },
);

// ========================================
// AUTO-ROUTED REQUISITION EMAIL (remark-based)
// ========================================

exports.sendAutoRoutedRequisitionEmail = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 120,
      memory: "512MiB",
    },
    async (request) => {
      if (!request.auth) {
        console.warn("[AUTO-EMAIL] Rejected unauthenticated request");
        throw new HttpsError("unauthenticated", "User must be authenticated to send routed emails");
      }

      const callerUid = request.auth.uid;
      let tenant = await resolveTenantForCallable(request.data, callerUid);
      let tenantDb = getTenantDb(tenant.databaseId);

      const requisitionId = ((request.data && request.data.requisitionId) || "").toString().trim();
      const pdfData = ((request.data && request.data.pdfData) || "").toString();
      const fileName = ((request.data && request.data.fileName) || "invoice.pdf").toString().trim();
      const manualRetry = request.data && request.data.manualRetry === true;

      console.log(
          `[AUTO-EMAIL] Request received: requisitionId=${requisitionId || "(missing)"}, ` +
          `manualRetry=${manualRetry}, callerUid=${callerUid}, company=${tenant.companyId}, database=${tenant.databaseId}, ` +
          `pdfBase64Length=${pdfData.length}`,
      );

      if (!requisitionId) {
        console.warn("[AUTO-EMAIL] Missing requisitionId in request payload");
        throw new HttpsError("invalid-argument", "requisitionId is required.");
      }

      if (!pdfData) {
        console.warn(`[AUTO-EMAIL] Missing pdfData for requisitionId=${requisitionId}`);
        throw new HttpsError("invalid-argument", "pdfData is required.");
      }

      if (manualRetry) {
        console.log(`[AUTO-EMAIL] Manual retry requested for requisitionId=${requisitionId}`);
        const adminAllowed = await isAdminUser(callerUid, tenantDb);
        if (!adminAllowed) {
          console.warn(`[AUTO-EMAIL] Manual retry denied (not admin): callerUid=${callerUid}`);
          throw new HttpsError("permission-denied", "Admin access is required for manual retry.");
        }
      }

      let requisitionRef = tenantDb.collection("salesRequisitions").doc(requisitionId);
      let requisitionDoc = await requisitionRef.get();
      if (!requisitionDoc.exists) {
        console.warn(
            `[AUTO-EMAIL] Requisition not found in resolved tenant; trying fallback lookup. ` +
            `requisitionId=${requisitionId}, resolvedDatabase=${tenant.databaseId}`,
        );

        const fallbackTenant = await findTenantForRequisitionId(requisitionId);
        if (!fallbackTenant) {
          await writeAutoEmailLog(tenantDb, {
            requisitionId: requisitionId,
            companyId: tenant.companyId,
            databaseId: tenant.databaseId,
            status: "failed",
            error: "Requisition not found in resolved or fallback tenant databases.",
          });
          throw new HttpsError("not-found", "Requisition not found.");
        }

        tenant = {
          companyId: fallbackTenant.companyId,
          databaseId: fallbackTenant.databaseId,
        };
        tenantDb = fallbackTenant.tenantDb;
        requisitionRef = tenantDb.collection("salesRequisitions").doc(requisitionId);
        requisitionDoc = await requisitionRef.get();

        console.log(
            `[AUTO-EMAIL] Fallback tenant resolved for requisitionId=${requisitionId}: ` +
            `company=${tenant.companyId}, database=${tenant.databaseId}`,
        );
      }

      const requisitionData = requisitionDoc.data() || {};
      const currentStatus = (requisitionData.autoEmailStatus || "").toString();
      const currentAttempts = Number(requisitionData.autoEmailAttemptCount || 0);

      console.log(
          `[AUTO-EMAIL] Loaded requisition state: requisitionId=${requisitionId}, ` +
          `currentStatus=${currentStatus || "(empty)"}, currentAttempts=${currentAttempts}`,
      );

      if (!manualRetry && currentStatus === "sent") {
        console.log(`[AUTO-EMAIL] Skipping already-sent requisitionId=${requisitionId}`);
        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: (requisitionData.approvalRoute || "").toString(),
          reasons: requisitionData.approvalReasons || [],
          status: "skipped",
          error: "Skipped because requisition is already marked sent.",
        });
        return {
          success: true,
          skipped: true,
          message: "Auto email already sent.",
          requisitionId: requisitionId,
        };
      }

      if (!manualRetry && currentAttempts >= MAX_AUTO_EMAIL_RETRIES) {
        console.warn(
            `[AUTO-EMAIL] Automatic retry limit reached for requisitionId=${requisitionId}, ` +
            `currentAttempts=${currentAttempts}, limit=${MAX_AUTO_EMAIL_RETRIES}`,
        );
        await requisitionRef.set({
          autoEmailStatus: "failed",
          autoEmailLastError: `Automatic retry limit (${MAX_AUTO_EMAIL_RETRIES}) reached.`,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: (requisitionData.approvalRoute || "").toString(),
          reasons: requisitionData.approvalReasons || [],
          status: "failed",
          error: `Automatic retry limit (${MAX_AUTO_EMAIL_RETRIES}) reached.`,
        });

        return {
          success: false,
          skipped: true,
          message: "Automatic retry limit reached.",
          requisitionId: requisitionId,
        };
      }

      const settings = await getAutoEmailSettings(tenantDb);
      console.log(
          `[AUTO-EMAIL] Loaded settings for requisitionId=${requisitionId}: ` +
          `autoEmailEnabled=${settings.autoEmailEnabled}, approvalEmailsLocked=${settings.approvalEmailsLocked}, ` +
          `primaryConfigured=${Boolean(settings.approvalEmailPrimary)}, secondaryConfigured=${Boolean(settings.approvalEmailSecondary)}`,
      );
      if (!settings.autoEmailEnabled && !manualRetry) {
        console.warn(`[AUTO-EMAIL] Auto-email disabled by settings for requisitionId=${requisitionId}`);
        await requisitionRef.set({
          autoEmailStatus: "skipped",
          autoEmailLastError: "Auto-email is disabled in tenant settings.",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: (requisitionData.approvalRoute || "").toString(),
          reasons: requisitionData.approvalReasons || [],
          status: "skipped",
          error: "Auto-email disabled in settings.",
        });

        return {
          success: true,
          skipped: true,
          message: "Auto-email disabled in settings.",
          requisitionId: requisitionId,
        };
      }

      const routeResult = evaluateApprovalRoute(requisitionData);
      const targetEmail = routeResult.route === "approval_required" ?
        settings.approvalEmailPrimary : settings.approvalEmailSecondary;

      console.log(
          `[AUTO-EMAIL] Route evaluated for requisitionId=${requisitionId}: ` +
          `route=${routeResult.route}, reasons=${JSON.stringify(routeResult.reasons)}, targetEmail=${targetEmail || "(missing)"}`,
      );

      if (!targetEmail) {
        const checkpointId = logPreconditionCheckpoint(
            "sendAutoRoutedRequisitionEmail.missingRecipient",
            "Recipient email is not configured.",
            {
              requisitionId: requisitionId,
              route: routeResult.route,
              companyId: tenant.companyId,
              databaseId: tenant.databaseId,
            },
        );
        await requisitionRef.set({
          approvalRoute: routeResult.route,
          approvalReasons: routeResult.reasons,
          autoEmailStatus: "failed",
          autoEmailAttemptCount: currentAttempts + 1,
          autoEmailLastError: `No recipient email configured. checkpoint=${checkpointId}`,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: routeResult.route,
          reasons: routeResult.reasons,
          status: "failed",
          error: `No recipient email configured. checkpoint=${checkpointId}`,
        });

        throw new HttpsError(
            "failed-precondition",
            `Recipient email is not configured. [checkpoint:${checkpointId}]`,
        );
      }

      if (!isValidEmailAddress(targetEmail)) {
        const checkpointId = logPreconditionCheckpoint(
            "sendAutoRoutedRequisitionEmail.invalidRecipient",
            "Recipient email format is invalid.",
            {
              requisitionId: requisitionId,
              targetEmail: targetEmail,
              route: routeResult.route,
              companyId: tenant.companyId,
              databaseId: tenant.databaseId,
            },
        );
        await requisitionRef.set({
          approvalRoute: routeResult.route,
          approvalReasons: routeResult.reasons,
          autoEmailStatus: "failed",
          autoEmailAttemptCount: currentAttempts + 1,
          autoEmailLastError: `Invalid recipient email configured: ${targetEmail}. checkpoint=${checkpointId}`,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: routeResult.route,
          reasons: routeResult.reasons,
          to: targetEmail,
          status: "failed",
          error: `Invalid recipient email configured: ${targetEmail}. checkpoint=${checkpointId}`,
        });

        throw new HttpsError(
            "failed-precondition",
            `Recipient email format is invalid. [checkpoint:${checkpointId}]`,
        );
      }

      const {gmailEmail, gmailPassword, source} = getConfiguredEmailCredentials();
      if (!gmailEmail || !gmailPassword) {
        const envYamlPath = path.join(__dirname, ".env.yaml");
        const checkpointId = logPreconditionCheckpoint(
            "sendAutoRoutedRequisitionEmail.credentials",
            "Email service is not properly configured. Missing GMAIL_EMAIL or GMAIL_PASSWORD.",
            {
              requisitionId: requisitionId,
              hasEmail: Boolean(gmailEmail),
              hasPassword: Boolean(gmailPassword),
              source: source,
              hasEnvGmailEmail: Boolean(process.env.GMAIL_EMAIL),
              hasEnvGmailPassword: Boolean(process.env.GMAIL_PASSWORD),
              hasEnvGmailUser: Boolean(process.env.GMAIL_USER),
              hasEnvSmtpUser: Boolean(process.env.SMTP_USER),
              hasEnvYamlFile: fs.existsSync(envYamlPath),
              companyId: tenant.companyId,
              databaseId: tenant.databaseId,
            },
        );

        await requisitionRef.set({
          autoEmailStatus: "failed",
          autoEmailAttemptCount: currentAttempts + 1,
          autoEmailLastError:
            `Email service is not properly configured. Missing GMAIL_EMAIL or GMAIL_PASSWORD. checkpoint=${checkpointId}`,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: routeResult.route,
          reasons: routeResult.reasons,
          status: "failed",
          error:
            `Email service is not properly configured. Missing GMAIL_EMAIL or GMAIL_PASSWORD. checkpoint=${checkpointId}`,
        });

        throw new HttpsError(
            "failed-precondition",
            `Email service is not properly configured. Missing GMAIL_EMAIL or GMAIL_PASSWORD. [checkpoint:${checkpointId}]`,
        );
      }

      const template = buildAutoRouteEmailTemplate({
        route: routeResult.route,
        sorNumber: requisitionData.sorNumber,
        customerName: requisitionData.customerName,
        reasons: routeResult.reasons,
      });

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: gmailEmail,
          pass: gmailPassword,
        },
      });

      try {
        console.log(
            `[AUTO-EMAIL] Sending email for requisitionId=${requisitionId}: ` +
            `to=${targetEmail}, subject=${template.subject}, fileName=${fileName || "(auto)"}`,
        );
        const pdfBuffer = Buffer.from(pdfData, "base64");
        if (!pdfBuffer.length) {
          throw new HttpsError("invalid-argument", "PDF attachment payload is empty after decoding.");
        }

        const maxAttachmentBytes = 20 * 1024 * 1024;
        if (pdfBuffer.length > maxAttachmentBytes) {
          throw new HttpsError(
              "failed-precondition",
              `PDF attachment exceeds size limit (${pdfBuffer.length} bytes).`,
          );
        }

        console.log(
            `[AUTO-EMAIL] PDF decoded for requisitionId=${requisitionId}, bytes=${pdfBuffer.length}`,
        );

        await transporter.verify();
        console.log(`[AUTO-EMAIL] SMTP verification succeeded for requisitionId=${requisitionId}`);

        const info = await transporter.sendMail({
          from: `Sales Team <${gmailEmail}>`,
          to: targetEmail,
          subject: template.subject,
          html: template.html,
          attachments: [
            {
              filename: fileName || `SOR-${(requisitionData.sorNumber || requisitionId)}.pdf`,
              content: pdfBuffer,
              contentType: "application/pdf",
            },
          ],
        });

        await requisitionRef.set({
          approvalRoute: routeResult.route,
          approvalReasons: routeResult.reasons,
          autoEmailStatus: "sent",
          autoEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
          autoEmailAttemptCount: currentAttempts + 1,
          autoEmailLastError: null,
          autoEmailMessageId: info && info.messageId ? info.messageId : null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: routeResult.route,
          reasons: routeResult.reasons,
          to: targetEmail,
          subject: template.subject,
          status: "success",
        });

        console.log(
            `[AUTO-EMAIL] Email sent successfully for requisitionId=${requisitionId}, ` +
            `messageId=${info && info.messageId ? info.messageId : "(none)"}`,
        );

        return {
          success: true,
          requisitionId: requisitionId,
          route: routeResult.route,
          sentTo: targetEmail,
        };
      } catch (error) {
        const isHttpsError = error instanceof HttpsError;
        const errorMessage = error && error.message ? error.message : String(error);
        const errorCode = isHttpsError ? String(error.code) : (error && error.code ? String(error.code) : "unknown");
        const smtpResponse = error && error.response ? String(error.response) : null;
        const smtpResponseCode =
          error && Object.prototype.hasOwnProperty.call(error, "responseCode") ?
            String(error.responseCode) :
            null;
        const smtpCommand = error && error.command ? String(error.command) : null;

        await requisitionRef.set({
          approvalRoute: routeResult.route,
          approvalReasons: routeResult.reasons,
          autoEmailStatus: "failed",
          autoEmailAttemptCount: currentAttempts + 1,
          autoEmailLastError: `${errorCode}: ${errorMessage}`,
          autoEmailLastErrorCode: errorCode,
          autoEmailLastSmtpResponseCode: smtpResponseCode,
          autoEmailLastSmtpCommand: smtpCommand,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: routeResult.route,
          reasons: routeResult.reasons,
          to: targetEmail,
          subject: template.subject,
          status: "failed",
          error: `${errorCode}: ${errorMessage}`,
          errorCode: errorCode,
          smtpResponse: smtpResponse,
          smtpResponseCode: smtpResponseCode,
          smtpCommand: smtpCommand,
          errorStack: error && error.stack ? error.stack : null,
        });

        console.error(
            `[AUTO-EMAIL] Email send failed for requisitionId=${requisitionId}: ` +
            `code=${errorCode}, message=${errorMessage}, responseCode=${smtpResponseCode || "(none)"}, command=${smtpCommand || "(none)"}`,
            error,
        );

        if (isHttpsError && error.code === "failed-precondition") {
          logPreconditionCheckpoint(
              "sendAutoRoutedRequisitionEmail.sendBlock",
              errorMessage,
              {
                requisitionId: requisitionId,
                route: routeResult.route,
                companyId: tenant.companyId,
                databaseId: tenant.databaseId,
                smtpResponseCode: smtpResponseCode,
                smtpCommand: smtpCommand,
              },
          );
        }

        if (isHttpsError) {
          throw error;
        }

        throw new HttpsError("internal", `Failed to send auto-routed email: ${errorCode}: ${errorMessage}`);
      }
    },
);

exports.updateAutoEmailSettings = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 60,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in.");
      }

      const callerUid = request.auth.uid;
      const tenant = await resolveTenantForCallable(request.data, callerUid);
      const tenantDb = getTenantDb(tenant.databaseId);
      const adminAllowed = await isAdminUser(callerUid, tenantDb);

      if (!adminAllowed) {
        throw new HttpsError("permission-denied", "Admin access is required.");
      }

      const approvalEmailPrimary = ((request.data && request.data.approvalEmailPrimary) || "")
          .toString()
          .trim()
          .toLowerCase();
      const approvalEmailSecondary = ((request.data && request.data.approvalEmailSecondary) || "")
          .toString()
          .trim()
          .toLowerCase();
      const autoEmailEnabled = request.data && request.data.autoEmailEnabled === true;
      const approvalEmailsLocked = request.data && request.data.approvalEmailsLocked === true;

      if (
        approvalEmailPrimary === LEGACY_PLACEHOLDER_APPROVAL_EMAIL_PRIMARY ||
        approvalEmailSecondary === LEGACY_PLACEHOLDER_APPROVAL_EMAIL_SECONDARY
      ) {
        throw new HttpsError(
            "failed-precondition",
            "Replace placeholder recipient emails with real addresses before saving.",
        );
      }

      if (!isValidEmailAddress(approvalEmailPrimary)) {
        throw new HttpsError("invalid-argument", "approvalEmailPrimary must be a valid email.");
      }

      if (!isValidEmailAddress(approvalEmailSecondary)) {
        throw new HttpsError("invalid-argument", "approvalEmailSecondary must be a valid email.");
      }

      const settingsRef = tenantDb.collection("settings").doc("appSettings");
      const existingDoc = await settingsRef.get();
      const existingData = existingDoc.data() || {};
      const wasLocked = existingData.approvalEmailsLocked === true;

      const existingPrimary = (existingData.approvalEmailPrimary || "").toString().trim();
      const existingSecondary = (existingData.approvalEmailSecondary || "").toString().trim();
      const recipientChanged =
        approvalEmailPrimary !== existingPrimary ||
        approvalEmailSecondary !== existingSecondary;
      const staysLocked = wasLocked && approvalEmailsLocked;

      if (staysLocked && recipientChanged) {
        throw new HttpsError(
            "failed-precondition",
            "Recipient emails are locked. Disable lock before editing recipients.",
        );
      }

      await settingsRef.set({
        autoEmailEnabled: autoEmailEnabled,
        approvalEmailPrimary: approvalEmailPrimary,
        approvalEmailSecondary: approvalEmailSecondary,
        approvalEmailsLocked: approvalEmailsLocked,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: callerUid,
      }, {merge: true});

      await tenantDb.collection("auditLogs").add({
        action: "updateAutoEmailSettings",
        entityType: "settings",
        entityId: "appSettings",
        details: {
          autoEmailEnabled: autoEmailEnabled,
          approvalEmailPrimary: approvalEmailPrimary,
          approvalEmailSecondary: approvalEmailSecondary,
          approvalEmailsLocked: approvalEmailsLocked,
          recipientChanged: recipientChanged,
          previouslyLocked: wasLocked,
        },
        actorUid: callerUid,
        actorEmail: request.auth.token.email || "unknown",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        autoEmailEnabled: autoEmailEnabled,
        approvalEmailPrimary: approvalEmailPrimary,
        approvalEmailSecondary: approvalEmailSecondary,
        approvalEmailsLocked: approvalEmailsLocked,
      };
    },
);

// ========================================
// COMPANY TENANT MANAGEMENT (default DB directory)
// ========================================

exports.upsertCompanyTenant = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 60,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in.");
      }

      const callerUid = request.auth.uid;
      const callerTenant = await resolveTenantForCallable(request.data, callerUid);
      const callerDb = getTenantDb(callerTenant.databaseId);

      const adminAllowed = await isAdminUser(callerUid, callerDb);
      if (!adminAllowed) {
        throw new HttpsError("permission-denied", "Admin access is required.");
      }

      const tenantIdentifier = normalizeCompanyIdentifier(
          (request.data && (request.data.companyIdentifier || request.data.companyId)) || "",
      );
      const companyName = ((request.data && request.data.companyName) || "")
          .toString()
          .trim();
      const firestoreDatabaseId = ((request.data && request.data.firestoreDatabaseId) || "")
          .toString()
          .trim();
      const isActive = request.data && request.data.isActive !== false;

      if (!companyName) {
        throw new HttpsError("invalid-argument", "companyName is required.");
      }

      if (!firestoreDatabaseId) {
        throw new HttpsError("invalid-argument", "firestoreDatabaseId is required.");
      }

      const tenantRef = db.collection("companyTenants").doc(tenantIdentifier);
      const existing = await tenantRef.get();

      await tenantRef.set({
        companyId: tenantIdentifier,
        companyName: companyName,
        firestoreDatabaseId: firestoreDatabaseId,
        databaseId: firestoreDatabaseId,
        isActive: isActive,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: callerUid,
        ...(existing.exists ? {} : {
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: callerUid,
        }),
      }, {merge: true});

      return {
        success: true,
        companyId: tenantIdentifier,
        firestoreDatabaseId: firestoreDatabaseId,
        isActive: isActive,
        operation: existing.exists ? "updated" : "created",
      };
    },
);

// ========================================
// TENANT USER MANAGEMENT (admin only)
// ========================================

exports.adminCreateUserInTenant = onCall(
    {
  region: CALLABLE_REGION,
      timeoutSeconds: 60,
      memory: "128MiB",
      cpu: "gcf_gen1",
      maxInstances: 1,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in.");
      }

      const callerUid = request.auth.uid;
      const tenant = await resolveTenantForCallable(request.data, callerUid);
      const tenantDb = getTenantDb(tenant.databaseId);
      const adminAllowed = await isAdminUser(callerUid, tenantDb);

      if (!adminAllowed) {
        throw new HttpsError("permission-denied", "Admin access is required.");
      }

      const email = ((request.data && request.data.email) || "").toString().trim().toLowerCase();
      const password = ((request.data && request.data.password) || "").toString();
      const name = ((request.data && request.data.name) || "").toString().trim();
      const role = normalizeUserRole((request.data && request.data.role) || "user");
      const isDisabled = request.data && request.data.isDisabled === true;
      const companyId = ((request.data && request.data.actorCompanyIdentifier) || tenant.companyId || "")
          .toString()
          .trim()
          .toLowerCase();

      if (!email || !password || !name) {
        throw new HttpsError("invalid-argument", "email, password, and name are required.");
      }

      if (password.length < 6) {
        throw new HttpsError("invalid-argument", "Password must be at least 6 characters.");
      }

      try {
        let authUser;
        let attachedExistingAuthUser = false;

        try {
          authUser = await admin.auth().getUserByEmail(email);
          attachedExistingAuthUser = true;
        } catch (error) {
          if (!error || error.code !== "auth/user-not-found") {
            throw error;
          }

          authUser = await admin.auth().createUser({
            email: email,
            password: password,
            displayName: name,
            disabled: isDisabled,
          });
        }

        const authUpdate = {
          displayName: name,
          disabled: isDisabled,
          ...(attachedExistingAuthUser && password ? {password: password} : {}),
        };

        await admin.auth().updateUser(authUser.uid, authUpdate);

        await tenantDb.collection("users").doc(authUser.uid).set({
          email: email,
          name: name,
          role: role,
          companyId: companyId,
          firestoreDatabaseId: tenant.databaseId,
          isDisabled: isDisabled,
          disabled: isDisabled,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: callerUid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        await tenantDb.collection("auditLogs").add({
          action: "createUser",
          entityType: "user",
          entityId: authUser.uid,
          details: {
            email: email,
            role: role,
            isDisabled: isDisabled,
          },
          actorUid: callerUid,
          actorEmail: request.auth.token.email || "unknown",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
          success: true,
          uid: authUser.uid,
          email: email,
          role: role,
          attachedExistingAuthUser: attachedExistingAuthUser,
        };
      } catch (error) {
        throw new HttpsError("internal", `Failed to create user: ${error.message}`);
      }
    },
);

exports.adminUpdateUserInTenant = onCall(
    {
  region: CALLABLE_REGION,
      timeoutSeconds: 60,
      memory: "128MiB",
      cpu: "gcf_gen1",
      maxInstances: 1,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in.");
      }

      const callerUid = request.auth.uid;
      const tenant = await resolveTenantForCallable(request.data, callerUid);
      const tenantDb = getTenantDb(tenant.databaseId);
      const adminAllowed = await isAdminUser(callerUid, tenantDb);

      if (!adminAllowed) {
        throw new HttpsError("permission-denied", "Admin access is required.");
      }

      const targetUid = ((request.data && request.data.targetUid) || "").toString().trim();
      const name = ((request.data && request.data.name) || "").toString().trim();
      const email = ((request.data && request.data.email) || "").toString().trim().toLowerCase();
      const role = normalizeUserRole((request.data && request.data.role) || "user");
      const password = ((request.data && request.data.password) || "").toString();
      const isDisabled = request.data && request.data.isDisabled === true;
      const companyId = ((request.data && request.data.actorCompanyIdentifier) || tenant.companyId || "")
          .toString()
          .trim()
          .toLowerCase();

      if (!targetUid || !name || !email) {
        throw new HttpsError("invalid-argument", "targetUid, email, and name are required.");
      }

      if (targetUid === callerUid && role !== "admin") {
        throw new HttpsError("invalid-argument", "You cannot remove your own admin role.");
      }

      const userRef = tenantDb.collection("users").doc(targetUid);
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "Target user profile was not found in this tenant.");
      }

      const authUpdate = {
        email: email,
        displayName: name,
        disabled: isDisabled,
        ...(password ? {password: password} : {}),
      };

      try {
        await admin.auth().updateUser(targetUid, authUpdate);

        await userRef.set({
          email: email,
          name: name,
          role: role,
          companyId: companyId,
          firestoreDatabaseId: tenant.databaseId,
          isDisabled: isDisabled,
          disabled: isDisabled,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: callerUid,
        }, {merge: true});

        await tenantDb.collection("auditLogs").add({
          action: "updateUser",
          entityType: "user",
          entityId: targetUid,
          details: {
            email: email,
            role: role,
            isDisabled: isDisabled,
            passwordUpdated: Boolean(password),
          },
          actorUid: callerUid,
          actorEmail: request.auth.token.email || "unknown",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
          success: true,
          uid: targetUid,
        };
      } catch (error) {
        if (error && error.code === "auth/user-not-found") {
          throw new HttpsError("not-found", "Target Firebase Auth user does not exist.");
        }
        if (error && error.code === "auth/email-already-exists") {
          throw new HttpsError("already-exists", "Another account already uses that email.");
        }
        throw new HttpsError("internal", `Failed to update user: ${error.message}`);
      }
    },
);

exports.adminDeleteUserInTenant = onCall(
    {
  region: CALLABLE_REGION,
      timeoutSeconds: 60,
      memory: "128MiB",
      cpu: "gcf_gen1",
      maxInstances: 1,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in.");
      }

      const callerUid = request.auth.uid;
      const tenant = await resolveTenantForCallable(request.data, callerUid);
      const tenantDb = getTenantDb(tenant.databaseId);
      const adminAllowed = await isAdminUser(callerUid, tenantDb);

      if (!adminAllowed) {
        throw new HttpsError("permission-denied", "Admin access is required.");
      }

      const targetUid = ((request.data && request.data.targetUid) || "").toString().trim();
      if (!targetUid) {
        throw new HttpsError("invalid-argument", "targetUid is required.");
      }

      if (targetUid === callerUid) {
        throw new HttpsError("invalid-argument", "You cannot delete your own account.");
      }

      try {
        await admin.auth().deleteUser(targetUid);
      } catch (error) {
        if (!error || error.code !== "auth/user-not-found") {
          throw new HttpsError("internal", `Failed to delete auth user: ${error.message}`);
        }
      }

      await tenantDb.collection("users").doc(targetUid).delete();

      await tenantDb.collection("auditLogs").add({
        action: "deleteUser",
        entityType: "user",
        entityId: targetUid,
        details: {},
        actorUid: callerUid,
        actorEmail: request.auth.token.email || "unknown",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        uid: targetUid,
      };
    },
);

// ========================================
// IMPORT DATA FUNCTION
// ========================================

exports.importDataFromExcelV2 = onDocumentCreated(
    "dataImports/{importId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No data associated with the event");
        return;
      }

      await snapshot.ref.update({
        status: "processing",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(
          `[IMPORT][STORAGE] Processing importId=${snapshot.id}, requestedBy=${snapshot.data().requestedBy || "unknown"}`,
      );

      try {
        const bucketName = process.env.FIREBASE_STORAGE_BUCKET || admin.storage().bucket().name;
        const tempFilePath = path.join(os.tmpdir(), "document_file.xlsx");

        const candidatePaths = [
          snapshot.data().filePathInBucket,
          process.env.CUSTOMER_IMPORT_FILE_PATH,
          "data_files/document_file.xlsx",
          "document_file.xlsx",
        ].filter(Boolean);

        let downloaded = false;

        for (const filePathInBucket of candidatePaths) {
          try {
            console.log(`Downloading customer import from gs://${bucketName}/${filePathInBucket}`);
            await storage.bucket(bucketName).file(filePathInBucket).download({destination: tempFilePath});
            downloaded = true;
            break;
          } catch (downloadError) {
            console.warn(
                `Unable to download import file from gs://${bucketName}/${filePathInBucket}: ${downloadError.message}`,
            );
          }
        }

        if (!downloaded) {
          throw new Error(
              `Customer import workbook not found in bucket ${bucketName}. ` +
              `Checked paths: ${candidatePaths.join(", ")}`,
          );
        }

        const workbook = xlsx.readFile(tempFilePath);
        const parsed = parseWorkbookData(workbook);
        console.log(
          `[IMPORT][STORAGE] Parsed workbook rows: ` +
          `customer master=${parsed.data.length}, acct recble=${parsed.data2.length}, ` +
          `item master=${parsed.data3.length}, items available=${parsed.data4.length}`,
        );

        const summary = await importParsedWorkbookData(parsed);
        console.log(`[IMPORT][STORAGE] Firestore write summary: ${JSON.stringify(summary)}`);

        await snapshot.ref.update({
          status: "completed",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          summary: summary,
        });

        console.log(`[IMPORT][STORAGE] Import completed successfully for importId=${snapshot.id}`);
      } catch (error) {
        await snapshot.ref.update({
          status: "error",
          error: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.error(`[IMPORT][STORAGE] Import failed for importId=${snapshot.id}:`, error);
      }
    },
);
