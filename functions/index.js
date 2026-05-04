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
const ROLLBACK_WINDOW_MS = 24 * 60 * 60 * 1000;
const ROLLBACK_MIN_EMAIL_ATTEMPTS = 2;
const DEFAULT_APPROVAL_EMAIL_PRIMARY = "";
const DEFAULT_APPROVAL_EMAIL_SECONDARY = "";
const DEFAULT_APPROVAL_EMAIL_BODY_PRIMARY =
  "Sales requisition {{sorNumber}} for {{customerName}} requires review.\n" +
  "Detected notices: {{reasonText}}.\n" +
  "Please review the attached invoice PDF.";
const DEFAULT_APPROVAL_EMAIL_BODY_SECONDARY =
  "Sales requisition {{sorNumber}} for {{customerName}} was submitted without notices.\n" +
  "Please see attached invoice PDF for reference.";
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
 * Normalizes a stored body template.
 * @param {any} value Raw body template.
 * @param {string} fallback Fallback template.
 * @return {string} Normalized body template.
 */
function sanitizeBodyTemplateSetting(value, fallback) {
  const normalized = (value || "").toString().trim();
  return normalized || fallback;
}

/**
 * Escapes basic HTML entities for safe email template insertion.
 * @param {string} text Raw text.
 * @return {string} Escaped text.
 */
function escapeHtml(text) {
  return (text || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
}

/**
 * Applies placeholders to a body template and converts new lines to <br>.
 * @param {string} template Editable template from settings.
 * @param {{sorNumber: string, customerName: string, reasonText: string}} context Placeholder context.
 * @return {string} Rendered safe HTML.
 */
function renderBodyTemplateAsHtml(template, context) {
  const replacements = {
    "{{sorNumber}}": context.sorNumber,
    "{{customerName}}": context.customerName,
    "{{reasonText}}": context.reasonText,
  };

  let rendered = template || "";
  for (const [token, value] of Object.entries(replacements)) {
    rendered = rendered.split(token).join(value || "");
  }

  return escapeHtml(rendered).replace(/\r?\n/g, "<br>");
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
 * @return {Promise<{autoEmailEnabled: boolean, approvalEmailPrimary: string, approvalEmailSecondary: string, approvalEmailBodyPrimary: string, approvalEmailBodySecondary: string, approvalEmailsLocked: boolean}>}
 */
async function getAutoEmailSettings(tenantDb) {
  const defaults = {
    autoEmailEnabled: false,
    approvalEmailPrimary: DEFAULT_APPROVAL_EMAIL_PRIMARY,
    approvalEmailSecondary: DEFAULT_APPROVAL_EMAIL_SECONDARY,
    approvalEmailBodyPrimary: DEFAULT_APPROVAL_EMAIL_BODY_PRIMARY,
    approvalEmailBodySecondary: DEFAULT_APPROVAL_EMAIL_BODY_SECONDARY,
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
    const approvalEmailBodyPrimary = sanitizeBodyTemplateSetting(
        data.approvalEmailBodyPrimary,
        defaults.approvalEmailBodyPrimary,
    );
    const approvalEmailBodySecondary = sanitizeBodyTemplateSetting(
        data.approvalEmailBodySecondary,
        defaults.approvalEmailBodySecondary,
    );

    return {
      autoEmailEnabled: data.autoEmailEnabled === true,
      approvalEmailPrimary: approvalEmailPrimary,
      approvalEmailSecondary: approvalEmailSecondary,
      approvalEmailBodyPrimary: approvalEmailBodyPrimary,
      approvalEmailBodySecondary: approvalEmailBodySecondary,
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
  const bodyPrimary = sanitizeBodyTemplateSetting(
      params.approvalEmailBodyPrimary,
      DEFAULT_APPROVAL_EMAIL_BODY_PRIMARY,
  );
  const bodySecondary = sanitizeBodyTemplateSetting(
      params.approvalEmailBodySecondary,
      DEFAULT_APPROVAL_EMAIL_BODY_SECONDARY,
  );

  if (route === "approval_required") {
    const bodyHtml = renderBodyTemplateAsHtml(bodyPrimary, {
      sorNumber: sorNumber,
      customerName: customerName,
      reasonText: reasonText,
    });

    return {
      subject: `[Approval Required] Sales Requisition ${sorNumber}`,
      html: `
        <p>${bodyHtml}</p>
        <p>Please review the attached invoice PDF.</p>
      `,
    };
  }

  const bodyHtml = renderBodyTemplateAsHtml(bodySecondary, {
    sorNumber: sorNumber,
    customerName: customerName,
    reasonText: reasonText,
  });

  return {
    subject: `[No Issues] Sales Requisition ${sorNumber}`,
    html: `
      <p>${bodyHtml}</p>
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
// SOR SUBMISSION (server-authoritative, transactional)
// ========================================

const SOR_UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-7][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SOR_REJECTION_CATEGORIES = Object.freeze({
  VALIDATION: "validation",
  INVENTORY: "inventory",
  AUTH: "auth",
});

/**
 * Validates a UUID string (v1–v7, RFC variant). Clients are expected to send v7.
 * @param {unknown} value Candidate UUID.
 * @return {boolean} Whether the value is a syntactically valid UUID.
 */
function isValidRequisitionUuid(value) {
  if (typeof value !== "string") return false;
  return SOR_UUID_REGEX.test(value.trim());
}

/**
 * Loads the caller's profile from the resolved tenant database.
 * @param {string} callerUid Authenticated uid.
 * @param {FirebaseFirestore.Firestore} tenantDb Tenant Firestore client.
 * @return {Promise<{exists: boolean, role: string}>} Caller profile snapshot.
 */
async function loadCallerProfile(callerUid, tenantDb) {
  const userDoc = await tenantDb.collection("users").doc(callerUid).get();
  if (!userDoc.exists) {
    return {exists: false, role: ""};
  }
  const data = userDoc.data() || {};
  return {exists: true, role: (data.role || "user").toString()};
}

/**
 * Validates and normalizes the inbound submitSalesRequisition payload.
 * Throws HttpsError("invalid-argument") on any structural problem.
 * @param {unknown} data Raw request data.
 * @return {{
 *   clientGeneratedId: string,
 *   correlationId: string,
 *   sorPayload: object,
 *   pdfData: string,
 *   fileName: string,
 *   lineItems: Array<{id: string, code: string, name: string, quantity: number, unitPrice: number, subtotal: number}>,
 * }} Validated payload.
 */
function validateSubmitRequisitionPayload(data) {
  if (!data || typeof data !== "object") {
    throw new HttpsError("invalid-argument", "Request payload is required.");
  }

  const clientGeneratedId = (data.clientGeneratedId || "").toString().trim();
  if (!isValidRequisitionUuid(clientGeneratedId)) {
    throw new HttpsError("invalid-argument", "clientGeneratedId must be a valid UUID (v7 expected).");
  }

  const correlationId = (data.correlationId || "").toString().trim();
  if (!correlationId) {
    throw new HttpsError("invalid-argument", "correlationId is required.");
  }

  const sorPayload = data.sorPayload;
  if (!sorPayload || typeof sorPayload !== "object" || Array.isArray(sorPayload)) {
    throw new HttpsError("invalid-argument", "sorPayload must be an object.");
  }

  const rawItems = Array.isArray(sorPayload.items) ? sorPayload.items : [];
  if (rawItems.length === 0) {
    throw new HttpsError("invalid-argument", "sorPayload.items must contain at least one line item.");
  }

  const lineItems = rawItems.map((item, index) => {
    if (!item || typeof item !== "object") {
      throw new HttpsError("invalid-argument", `sorPayload.items[${index}] must be an object.`);
    }
    const id = (item.id || "").toString().trim();
    const code = (item.code || "").toString().trim();
    if (!id && !code) {
      throw new HttpsError("invalid-argument", `sorPayload.items[${index}] must include id or code.`);
    }
    const quantity = Number(item.quantity);
    if (!Number.isFinite(quantity) || quantity <= 0) {
      throw new HttpsError("invalid-argument", `sorPayload.items[${index}].quantity must be a positive number.`);
    }
    const unitPrice = Number(item.unitPrice);
    const subtotal = Number(item.subtotal);
    return {
      id: id,
      code: code,
      name: (item.name || "").toString(),
      quantity: quantity,
      unitPrice: Number.isFinite(unitPrice) ? unitPrice : 0,
      subtotal: Number.isFinite(subtotal) ? subtotal : 0,
    };
  });

  const pdfData = (data.pdfData || "").toString();
  const fileName = (data.fileName || `SOR-${clientGeneratedId}.pdf`).toString().trim();

  return {clientGeneratedId, correlationId, sorPayload, pdfData, fileName, lineItems};
}

/**
 * Resolves an itemMaster document reference by id (preferred) or code (fallback).
 * Queries are performed outside any transaction (Firestore txns disallow queries).
 * @param {FirebaseFirestore.Firestore} tenantDb Tenant Firestore client.
 * @param {{id: string, code: string}} lineItem Validated line item.
 * @return {Promise<FirebaseFirestore.DocumentReference|null>} Reference or null when not found.
 */
async function resolveItemRef(tenantDb, lineItem) {
  if (lineItem.id) {
    const byId = tenantDb.collection("itemMaster").doc(lineItem.id);
    const snap = await byId.get();
    if (snap.exists) return byId;
  }
  if (lineItem.code) {
    const byCode = await tenantDb.collection("itemMaster").where("code", "==", lineItem.code).limit(1).get();
    if (!byCode.empty) return byCode.docs[0].ref;
    const byItemCode = await tenantDb.collection("itemMaster").where("itemCode", "==", lineItem.code).limit(1).get();
    if (!byItemCode.empty) return byItemCode.docs[0].ref;
  }
  return null;
}

/**
 * Appends an event document to salesRequisitions/{sorId}/events. Best-effort:
 * never throws, never blocks the caller. Failures are logged.
 * @param {FirebaseFirestore.Firestore} tenantDb Tenant Firestore client.
 * @param {string} sorId Sales requisition document id.
 * @param {string} eventType Event type key (snake_case, matches OfflineEventType keys).
 * @param {object} context Event context with optional actor, details, and correlationId fields.
 * @return {Promise<void>}
 */
async function appendSorEvent(tenantDb, sorId, eventType, context = {}) {
  try {
    await tenantDb.collection("salesRequisitions").doc(sorId).collection("events").add({
      type: eventType,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      actor: context.actor || null,
      details: context.details || {},
      correlationId: context.correlationId || null,
    });
  } catch (error) {
    console.error(`[SOR-SUBMIT] Failed to append event ${eventType} for sor=${sorId}:`, error);
  }
}

/**
 * Builds the response payload returned for an idempotent replay (the SOR
 * already exists from a prior call with the same clientGeneratedId).
 * @param {FirebaseFirestore.DocumentSnapshot} existingDoc Existing SOR snapshot.
 * @return {object} Response shape mirroring a fresh submission.
 */
function buildIdempotentReplayResponse(existingDoc) {
  const data = existingDoc.data() || {};
  const accepted = data.status === "accepted";
  return {
    accepted: accepted,
    sorId: existingDoc.id,
    sorNumber: (data.sorNumber || data.sorNo || existingDoc.id).toString(),
    emailStatus: (data.emailStatus || data.autoEmailStatus || "unknown").toString(),
    rejectionCategory: data.rejectionCategory || null,
    rejectionReasons: Array.isArray(data.rejectionReasons) ? data.rejectionReasons : [],
    idempotentReplay: true,
    correlationId: (data.correlationId || "").toString(),
  };
}

exports.submitSalesRequisition = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 60,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        console.warn("[SOR-SUBMIT] Rejected unauthenticated request");
        throw new HttpsError("unauthenticated", "User must be authenticated to submit a sales requisition.");
      }

      const callerUid = request.auth.uid;
      const validated = validateSubmitRequisitionPayload(request.data);
      const {clientGeneratedId, correlationId, sorPayload, lineItems} = validated;

      const tenant = await resolveTenantForCallable(request.data, callerUid);
      const tenantDb = getTenantDb(tenant.databaseId);

      console.log(
          `[SOR-SUBMIT] Request: sor=${clientGeneratedId} correlationId=${correlationId} ` +
          `callerUid=${callerUid} tenant=${tenant.companyId}/${tenant.databaseId} lineItems=${lineItems.length}`,
      );

      const callerProfile = await loadCallerProfile(callerUid, tenantDb);
      if (!callerProfile.exists) {
        console.warn(`[SOR-SUBMIT] Caller ${callerUid} not registered in tenant ${tenant.databaseId}`);
        throw new HttpsError("permission-denied", "Caller does not belong to the requested tenant.");
      }

      const sorRef = tenantDb.collection("salesRequisitions").doc(clientGeneratedId);

      // Cheap idempotency pre-check (avoids spinning a transaction on the common replay case).
      const preCheckSnap = await sorRef.get();
      if (preCheckSnap.exists) {
        console.log(`[SOR-SUBMIT] Idempotent replay (pre-check) sor=${clientGeneratedId}`);
        return buildIdempotentReplayResponse(preCheckSnap);
      }

      // Resolve item refs outside the transaction. Queries cannot run inside Firestore txns.
      const resolvedRefs = [];
      const unresolvedReasons = [];
      for (let i = 0; i < lineItems.length; i++) {
        const lineItem = lineItems[i];
        const ref = await resolveItemRef(tenantDb, lineItem);
        if (!ref) {
          unresolvedReasons.push({
            lineIndex: i,
            itemId: lineItem.id,
            itemCode: lineItem.code,
            itemName: lineItem.name,
            code: "ITEM_NOT_FOUND",
            message: `Item not found: code=${lineItem.code || "(none)"} id=${lineItem.id || "(none)"}`,
          });
        } else {
          resolvedRefs.push({lineItem: lineItem, ref: ref});
        }
      }

      const sorNumberOut = (sorPayload.sorNumber || sorPayload.sorNo || clientGeneratedId).toString();
      const baseSorFields = {
        ...sorPayload,
        submittedBy: callerUid,
        tenantDatabaseId: tenant.databaseId,
        tenantCompanyId: tenant.companyId,
        correlationId: correlationId,
        clientGeneratedId: clientGeneratedId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      let outcome;
      try {
        outcome = await tenantDb.runTransaction(async (txn) => {
          // Race-safe idempotency check inside the transaction.
          const insideSnap = await txn.get(sorRef);
          if (insideSnap.exists) {
            return {kind: "idempotent", snap: insideSnap};
          }

          if (unresolvedReasons.length > 0) {
            txn.set(sorRef, {
              ...baseSorFields,
              status: "rejected",
              rejectionCategory: SOR_REJECTION_CATEGORIES.VALIDATION,
              rejectionReasons: unresolvedReasons,
            });
            return {kind: "validation_rejected", reasons: unresolvedReasons};
          }

          const stockSnaps = await Promise.all(resolvedRefs.map((entry) => txn.get(entry.ref)));

          const inventoryRejections = [];
          const stockMutations = [];
          for (let i = 0; i < resolvedRefs.length; i++) {
            const entry = resolvedRefs[i];
            const snap = stockSnaps[i];
            if (!snap.exists) {
              inventoryRejections.push({
                lineIndex: i,
                itemId: entry.lineItem.id,
                itemCode: entry.lineItem.code,
                itemName: entry.lineItem.name,
                code: "ITEM_VANISHED",
                message: "Item document was deleted between resolution and transaction.",
              });
              continue;
            }
            const itemData = snap.data() || {};
            const availableRaw = itemData.stock !== undefined ? itemData.stock : itemData.quantity;
            const available = Number(availableRaw);
            const requested = entry.lineItem.quantity;
            if (!Number.isFinite(available) || available < requested) {
              inventoryRejections.push({
                lineIndex: i,
                itemId: entry.lineItem.id,
                itemCode: entry.lineItem.code,
                itemName: entry.lineItem.name,
                code: "INSUFFICIENT_STOCK",
                requested: requested,
                available: Number.isFinite(available) ? available : 0,
                message:
                  `Insufficient stock for ${entry.lineItem.name || entry.lineItem.code}: ` +
                  `${requested} requested, ${Number.isFinite(available) ? available : 0} available.`,
              });
              continue;
            }
            stockMutations.push({ref: entry.ref, newStock: available - requested});
          }

          if (inventoryRejections.length > 0) {
            // All-or-nothing: write rejection record, do NOT decrement any stock.
            txn.set(sorRef, {
              ...baseSorFields,
              status: "rejected",
              rejectionCategory: SOR_REJECTION_CATEGORIES.INVENTORY,
              rejectionReasons: inventoryRejections,
            });
            return {kind: "inventory_rejected", reasons: inventoryRejections};
          }

          for (const mutation of stockMutations) {
            txn.update(mutation.ref, {
              stock: mutation.newStock,
              quantity: mutation.newStock,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          txn.set(sorRef, {
            ...baseSorFields,
            status: "accepted",
            emailStatus: "queued",
          });
          return {kind: "accepted"};
        });
      } catch (error) {
        console.error(`[SOR-SUBMIT] Transaction failed for sor=${clientGeneratedId}:`, error);
        throw new HttpsError("internal", "Submission transaction failed; please retry.");
      }

      if (outcome.kind === "idempotent") {
        console.log(`[SOR-SUBMIT] Idempotent replay (in-txn) sor=${clientGeneratedId}`);
        return buildIdempotentReplayResponse(outcome.snap);
      }

      const actor = {uid: callerUid, role: callerProfile.role};

      if (outcome.kind === "validation_rejected") {
        await appendSorEvent(tenantDb, clientGeneratedId, "sor_sync_rejected_validation", {
          actor: actor, details: {reasons: outcome.reasons}, correlationId: correlationId,
        });
        console.warn(`[SOR-SUBMIT] Validation rejection sor=${clientGeneratedId}: ${outcome.reasons.length} unresolved`);
        return {
          accepted: false,
          sorId: clientGeneratedId,
          sorNumber: sorNumberOut,
          rejectionCategory: SOR_REJECTION_CATEGORIES.VALIDATION,
          rejectionReasons: outcome.reasons,
          idempotentReplay: false,
          correlationId: correlationId,
        };
      }

      if (outcome.kind === "inventory_rejected") {
        await appendSorEvent(tenantDb, clientGeneratedId, "sor_sync_rejected_inventory", {
          actor: actor, details: {reasons: outcome.reasons}, correlationId: correlationId,
        });
        console.warn(`[SOR-SUBMIT] Inventory rejection sor=${clientGeneratedId}: ${outcome.reasons.length} insufficient`);
        return {
          accepted: false,
          sorId: clientGeneratedId,
          sorNumber: sorNumberOut,
          rejectionCategory: SOR_REJECTION_CATEGORIES.INVENTORY,
          rejectionReasons: outcome.reasons,
          idempotentReplay: false,
          correlationId: correlationId,
        };
      }

      await appendSorEvent(tenantDb, clientGeneratedId, "sor_sync_accepted", {
        actor: actor,
        details: {sorNumber: sorNumberOut, lineItemCount: lineItems.length},
        correlationId: correlationId,
      });

      console.log(
          `[SOR-SUBMIT] Accepted sor=${clientGeneratedId} sorNumber=${sorNumberOut} ` +
          `tenant=${tenant.companyId}/${tenant.databaseId}`,
      );

      // Server-triggered email after acceptance. Email failure does NOT roll back
      // the SOR — the dispatch helper updates the requisition doc with email status
      // and returns a structured result. Sync acceptance and email outcome are
      // surfaced independently in the response.
      const callerEmail =
        request.auth.token && request.auth.token.email ? request.auth.token.email : null;
      const dispatchResult = await dispatchAutoRoutedEmailForRequisition({
        tenantDb,
        tenant,
        requisitionRef: sorRef,
        requisitionData: {
          ...sorPayload,
          sorNumber: sorNumberOut,
          correlationId: correlationId,
        },
        pdfData: validated.pdfData,
        fileName: validated.fileName,
        currentAttempts: 0,
        callerUid,
        callerEmail,
        invocationContext: "sync_post_accept",
        correlationId,
      });

      return {
        accepted: true,
        sorId: clientGeneratedId,
        sorNumber: sorNumberOut,
        emailStatus: dispatchResult.status,
        emailRoute: dispatchResult.route,
        emailSentTo: dispatchResult.sentTo,
        emailError: dispatchResult.error,
        emailErrorCode: dispatchResult.errorCode,
        emailMessageId: dispatchResult.messageId,
        idempotentReplay: false,
        correlationId: correlationId,
      };
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

/**
 * Dispatches an auto-routed approval email for a sales requisition. Pure
 * side-effect helper that loads tenant settings, evaluates the approval route,
 * validates recipient and SMTP credentials, sends the email with the supplied
 * PDF, and updates the requisition doc + emailLogs + per-SOR events with the
 * outcome. Does NOT throw on email failure — returns a structured result so
 * callers can map it to their own response shape.
 *
 * Used by: submitSalesRequisition (post-accept dispatch) and the legacy
 * sendAutoRoutedRequisitionEmail callable (manual retry / first-send).
 *
 * @param {object} args Helper arguments.
 * @param {FirebaseFirestore.Firestore} args.tenantDb Tenant Firestore client.
 * @param {object} args.tenant Resolved tenant {companyId, databaseId}.
 * @param {FirebaseFirestore.DocumentReference} args.requisitionRef Sales requisition doc ref.
 * @param {object} args.requisitionData Sales requisition document data.
 * @param {string} args.pdfData Base64-encoded PDF payload.
 * @param {string} args.fileName Attachment filename.
 * @param {number} args.currentAttempts Attempts consumed BEFORE this call.
 * @param {string} args.callerUid Caller uid (for logging).
 * @param {string} args.callerEmail Caller email (for logging).
 * @param {string} args.invocationContext Context label e.g. "sync_post_accept", "manual_retry".
 * @param {string=} args.correlationId Trace id for cross-system correlation.
 * @return {Promise<object>} Structured result with status, route, sentTo, error fields.
 */
async function dispatchAutoRoutedEmailForRequisition(args) {
  const {
    tenantDb,
    tenant,
    requisitionRef,
    requisitionData,
    pdfData,
    fileName,
    currentAttempts,
    callerUid,
    callerEmail,
    invocationContext,
    correlationId,
  } = args;

  const requisitionId = requisitionRef.id;
  const sorNumber = (requisitionData.sorNumber || requisitionData.sorNo || requisitionId).toString();
  const customerName = (requisitionData.customerName || "").toString();
  const eventActor = {uid: callerUid || null, email: callerEmail || null};
  const traceCorrelationId = correlationId || (requisitionData.correlationId || "").toString() || null;

  const buildResult = (overrides) => ({
    status: "failed",
    route: null,
    sentTo: null,
    error: null,
    errorCode: null,
    smtpResponseCode: null,
    checkpointId: null,
    messageId: null,
    attemptCountAfter: currentAttempts,
    ...overrides,
  });

  await appendSorEvent(tenantDb, requisitionId, "email_dispatch_started", {
    actor: eventActor,
    details: {invocationContext, sorNumber, customerName, currentAttempts},
    correlationId: traceCorrelationId,
  });

  const settings = await getAutoEmailSettings(tenantDb);
  console.log(
      `[EMAIL-DISPATCH] Settings loaded for requisitionId=${requisitionId}: ` +
      `autoEmailEnabled=${settings.autoEmailEnabled}, ` +
      `primaryConfigured=${Boolean(settings.approvalEmailPrimary)}, ` +
      `secondaryConfigured=${Boolean(settings.approvalEmailSecondary)}`,
  );

  if (!settings.autoEmailEnabled) {
    const reason = "Auto-email disabled in settings.";
    await requisitionRef.set({
      emailStatus: "skipped",
      autoEmailStatus: "skipped",
      autoEmailLastError: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    await writeAutoEmailLog(tenantDb, {
      requisitionId, companyId: tenant.companyId, databaseId: tenant.databaseId,
      status: "skipped", error: reason,
    });
    await appendSorEvent(tenantDb, requisitionId, "email_dispatch_skipped", {
      actor: eventActor, details: {reason: "auto_email_disabled"}, correlationId: traceCorrelationId,
    });
    return buildResult({status: "skipped", error: reason, errorCode: "auto_email_disabled"});
  }

  const routeResult = evaluateApprovalRoute(requisitionData);
  const targetEmail = routeResult.route === "approval_required" ?
    settings.approvalEmailPrimary : settings.approvalEmailSecondary;

  console.log(
      `[EMAIL-DISPATCH] Route evaluated for requisitionId=${requisitionId}: ` +
      `route=${routeResult.route}, reasons=${JSON.stringify(routeResult.reasons)}, ` +
      `targetEmail=${targetEmail || "(missing)"}`,
  );

  if (!targetEmail) {
    const checkpointId = logPreconditionCheckpoint(
        "dispatchAutoRoutedEmailForRequisition.missingRecipient",
        "Recipient email is not configured.",
        {requisitionId, route: routeResult.route, companyId: tenant.companyId, databaseId: tenant.databaseId},
    );
    const reason = `No recipient email configured. checkpoint=${checkpointId}`;
    await requisitionRef.set({
      emailStatus: "failed",
      autoEmailStatus: "failed",
      approvalRoute: routeResult.route,
      approvalReasons: routeResult.reasons,
      autoEmailAttemptCount: currentAttempts + 1,
      autoEmailLastError: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    await writeAutoEmailLog(tenantDb, {
      requisitionId, companyId: tenant.companyId, databaseId: tenant.databaseId,
      routeChosen: routeResult.route, reasons: routeResult.reasons,
      status: "failed", error: reason,
    });
    await appendSorEvent(tenantDb, requisitionId, "email_dispatch_failed", {
      actor: eventActor,
      details: {reason: "no_recipient", checkpointId, route: routeResult.route},
      correlationId: traceCorrelationId,
    });
    return buildResult({
      status: "failed", route: routeResult.route, error: reason, errorCode: "no_recipient",
      checkpointId, attemptCountAfter: currentAttempts + 1,
    });
  }

  if (!isValidEmailAddress(targetEmail)) {
    const checkpointId = logPreconditionCheckpoint(
        "dispatchAutoRoutedEmailForRequisition.invalidRecipient",
        "Recipient email format is invalid.",
        {requisitionId, targetEmail, route: routeResult.route, companyId: tenant.companyId, databaseId: tenant.databaseId},
    );
    const reason = `Invalid recipient email configured: ${targetEmail}. checkpoint=${checkpointId}`;
    await requisitionRef.set({
      emailStatus: "failed",
      autoEmailStatus: "failed",
      approvalRoute: routeResult.route,
      approvalReasons: routeResult.reasons,
      autoEmailAttemptCount: currentAttempts + 1,
      autoEmailLastError: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    await writeAutoEmailLog(tenantDb, {
      requisitionId, companyId: tenant.companyId, databaseId: tenant.databaseId,
      routeChosen: routeResult.route, reasons: routeResult.reasons, to: targetEmail,
      status: "failed", error: reason,
    });
    await appendSorEvent(tenantDb, requisitionId, "email_dispatch_failed", {
      actor: eventActor,
      details: {reason: "invalid_recipient", checkpointId, targetEmail, route: routeResult.route},
      correlationId: traceCorrelationId,
    });
    return buildResult({
      status: "failed", route: routeResult.route, sentTo: targetEmail,
      error: reason, errorCode: "invalid_recipient",
      checkpointId, attemptCountAfter: currentAttempts + 1,
    });
  }

  const {gmailEmail, gmailPassword, source} = getConfiguredEmailCredentials();
  if (!gmailEmail || !gmailPassword) {
    const envYamlPath = path.join(__dirname, ".env.yaml");
    const checkpointId = logPreconditionCheckpoint(
        "dispatchAutoRoutedEmailForRequisition.credentials",
        "Email service is not properly configured. Missing GMAIL_EMAIL or GMAIL_PASSWORD.",
        {
          requisitionId,
          hasEmail: Boolean(gmailEmail),
          hasPassword: Boolean(gmailPassword),
          source,
          hasEnvGmailEmail: Boolean(process.env.GMAIL_EMAIL),
          hasEnvGmailPassword: Boolean(process.env.GMAIL_PASSWORD),
          hasEnvGmailUser: Boolean(process.env.GMAIL_USER),
          hasEnvSmtpUser: Boolean(process.env.SMTP_USER),
          hasEnvYamlFile: fs.existsSync(envYamlPath),
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
        },
    );
    const reason =
      `Email service is not properly configured. Missing GMAIL_EMAIL or GMAIL_PASSWORD. checkpoint=${checkpointId}`;
    await requisitionRef.set({
      emailStatus: "failed",
      autoEmailStatus: "failed",
      autoEmailAttemptCount: currentAttempts + 1,
      autoEmailLastError: reason,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    await writeAutoEmailLog(tenantDb, {
      requisitionId, companyId: tenant.companyId, databaseId: tenant.databaseId,
      routeChosen: routeResult.route, reasons: routeResult.reasons,
      status: "failed", error: reason,
    });
    await appendSorEvent(tenantDb, requisitionId, "email_dispatch_failed", {
      actor: eventActor,
      details: {reason: "no_credentials", checkpointId},
      correlationId: traceCorrelationId,
    });
    return buildResult({
      status: "failed", route: routeResult.route, sentTo: targetEmail,
      error: reason, errorCode: "no_credentials",
      checkpointId, attemptCountAfter: currentAttempts + 1,
    });
  }

  const template = buildAutoRouteEmailTemplate({
    route: routeResult.route,
    sorNumber: requisitionData.sorNumber,
    customerName: requisitionData.customerName,
    reasons: routeResult.reasons,
    approvalEmailBodyPrimary: settings.approvalEmailBodyPrimary,
    approvalEmailBodySecondary: settings.approvalEmailBodySecondary,
  });

  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {user: gmailEmail, pass: gmailPassword},
  });

  try {
    const pdfBuffer = Buffer.from(pdfData || "", "base64");
    if (!pdfBuffer.length) {
      throw new Error("PDF attachment payload is empty after decoding.");
    }

    const maxAttachmentBytes = 20 * 1024 * 1024;
    if (pdfBuffer.length > maxAttachmentBytes) {
      throw new Error(`PDF attachment exceeds size limit (${pdfBuffer.length} bytes).`);
    }

    console.log(
        `[EMAIL-DISPATCH] Sending email for requisitionId=${requisitionId}: ` +
        `to=${targetEmail}, subject=${template.subject}, fileName=${fileName || "(auto)"}, ` +
        `pdfBytes=${pdfBuffer.length}`,
    );

    await transporter.verify();

    const info = await transporter.sendMail({
      from: `Sales Team <${gmailEmail}>`,
      to: targetEmail,
      subject: template.subject,
      html: template.html,
      attachments: [{
        filename: fileName || `SOR-${(requisitionData.sorNumber || requisitionId)}.pdf`,
        content: pdfBuffer,
        contentType: "application/pdf",
      }],
    });

    await requisitionRef.set({
      emailStatus: "sent",
      autoEmailStatus: "sent",
      approvalRoute: routeResult.route,
      approvalReasons: routeResult.reasons,
      autoEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
      autoEmailAttemptCount: currentAttempts + 1,
      autoEmailLastError: null,
      autoEmailMessageId: info && info.messageId ? info.messageId : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    await writeAutoEmailLog(tenantDb, {
      requisitionId, companyId: tenant.companyId, databaseId: tenant.databaseId,
      routeChosen: routeResult.route, reasons: routeResult.reasons,
      to: targetEmail, subject: template.subject,
      status: "success",
    });

    await appendSorEvent(tenantDb, requisitionId, "email_dispatch_sent", {
      actor: eventActor,
      details: {
        sentTo: targetEmail,
        route: routeResult.route,
        messageId: info && info.messageId ? info.messageId : null,
        invocationContext,
      },
      correlationId: traceCorrelationId,
    });

    console.log(
        `[EMAIL-DISPATCH] Email sent successfully for requisitionId=${requisitionId}, ` +
        `messageId=${info && info.messageId ? info.messageId : "(none)"}`,
    );

    return buildResult({
      status: "sent", route: routeResult.route, sentTo: targetEmail,
      messageId: info && info.messageId ? info.messageId : null,
      attemptCountAfter: currentAttempts + 1,
    });
  } catch (error) {
    const errorMessage = error && error.message ? error.message : String(error);
    const errorCode = error && error.code ? String(error.code) : "send_error";
    const smtpResponse = error && error.response ? String(error.response) : null;
    const smtpResponseCode = error && Object.prototype.hasOwnProperty.call(error, "responseCode") ?
      String(error.responseCode) : null;
    const smtpCommand = error && error.command ? String(error.command) : null;

    await requisitionRef.set({
      emailStatus: "failed",
      autoEmailStatus: "failed",
      approvalRoute: routeResult.route,
      approvalReasons: routeResult.reasons,
      autoEmailAttemptCount: currentAttempts + 1,
      autoEmailLastError: `${errorCode}: ${errorMessage}`,
      autoEmailLastErrorCode: errorCode,
      autoEmailLastSmtpResponseCode: smtpResponseCode,
      autoEmailLastSmtpCommand: smtpCommand,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    await writeAutoEmailLog(tenantDb, {
      requisitionId, companyId: tenant.companyId, databaseId: tenant.databaseId,
      routeChosen: routeResult.route, reasons: routeResult.reasons,
      to: targetEmail, subject: template.subject,
      status: "failed",
      error: `${errorCode}: ${errorMessage}`,
      errorCode, smtpResponse, smtpResponseCode, smtpCommand,
      errorStack: error && error.stack ? error.stack : null,
    });

    await appendSorEvent(tenantDb, requisitionId, "email_dispatch_failed", {
      actor: eventActor,
      details: {
        reason: "send_error",
        errorCode,
        errorMessage,
        smtpResponseCode,
        smtpCommand,
        invocationContext,
      },
      correlationId: traceCorrelationId,
    });

    console.error(
        `[EMAIL-DISPATCH] Email send failed for requisitionId=${requisitionId}: ` +
        `code=${errorCode}, message=${errorMessage}, responseCode=${smtpResponseCode || "(none)"}, ` +
        `command=${smtpCommand || "(none)"}`,
        error,
    );

    return buildResult({
      status: "failed", route: routeResult.route, sentTo: targetEmail,
      error: `${errorCode}: ${errorMessage}`, errorCode, smtpResponseCode,
      attemptCountAfter: currentAttempts + 1,
    });
  }
}

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
      const callerEmail =
        request.auth.token && request.auth.token.email ? request.auth.token.email : "unknown";
      let tenant = await resolveTenantForCallable(request.data, callerUid);
      let tenantDb = getTenantDb(tenant.databaseId);

      const requisitionId = ((request.data && request.data.requisitionId) || "").toString().trim();
      const pdfData = ((request.data && request.data.pdfData) || "").toString();
      const fileName = ((request.data && request.data.fileName) || "invoice.pdf").toString().trim();
      const manualRetry = request.data && request.data.manualRetry === true;

      console.log(
          `[AUTO-EMAIL] Request received: requisitionId=${requisitionId || "(missing)"}, ` +
          `manualRetry=${manualRetry}, callerUid=${callerUid}, company=${tenant.companyId}, ` +
          `database=${tenant.databaseId}, pdfBase64Length=${pdfData.length}`,
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
        tenant = {companyId: fallbackTenant.companyId, databaseId: fallbackTenant.databaseId};
        tenantDb = fallbackTenant.tenantDb;
        requisitionRef = tenantDb.collection("salesRequisitions").doc(requisitionId);
        requisitionDoc = await requisitionRef.get();
        console.log(
            `[AUTO-EMAIL] Fallback tenant resolved for requisitionId=${requisitionId}: ` +
            `company=${tenant.companyId}, database=${tenant.databaseId}`,
        );
      }

      const requisitionData = requisitionDoc.data() || {};
      // Accept either field name during transition: emailStatus (new canonical) or
      // autoEmailStatus (legacy). Both are written by the helper.
      const currentStatus =
        (requisitionData.emailStatus || requisitionData.autoEmailStatus || "").toString();
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
        const reason = `Automatic retry limit (${MAX_AUTO_EMAIL_RETRIES}) reached.`;
        await requisitionRef.set({
          emailStatus: "failed",
          autoEmailStatus: "failed",
          autoEmailLastError: reason,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        await writeAutoEmailLog(tenantDb, {
          requisitionId: requisitionId,
          companyId: tenant.companyId,
          databaseId: tenant.databaseId,
          routeChosen: (requisitionData.approvalRoute || "").toString(),
          reasons: requisitionData.approvalReasons || [],
          status: "failed",
          error: reason,
        });
        return {
          success: false,
          skipped: true,
          message: "Automatic retry limit reached.",
          requisitionId: requisitionId,
        };
      }

      // Manual retries leave a per-SOR audit event before the dispatch fires.
      if (manualRetry) {
        await appendSorEvent(tenantDb, requisitionId, "email_resend_requested", {
          actor: {uid: callerUid, email: callerEmail},
          details: {currentStatus, currentAttempts},
        });
      }

      const dispatchResult = await dispatchAutoRoutedEmailForRequisition({
        tenantDb,
        tenant,
        requisitionRef,
        requisitionData,
        pdfData,
        fileName,
        currentAttempts,
        callerUid,
        callerEmail,
        invocationContext: manualRetry ? "manual_retry" : "callable_first_send",
        correlationId: (requisitionData.correlationId || "").toString() || null,
      });

      if (dispatchResult.status === "skipped") {
        return {
          success: true,
          skipped: true,
          requisitionId: requisitionId,
          message: dispatchResult.error || "Skipped.",
        };
      }

      if (dispatchResult.status === "failed") {
        const checkpointSuffix =
          dispatchResult.checkpointId ? ` [checkpoint:${dispatchResult.checkpointId}]` : "";
        // Preserve the legacy contract: precondition-style errors throw with checkpoint;
        // SMTP send errors throw "internal".
        if (
          dispatchResult.errorCode === "no_recipient" ||
          dispatchResult.errorCode === "invalid_recipient" ||
          dispatchResult.errorCode === "no_credentials"
        ) {
          throw new HttpsError(
              "failed-precondition",
              `${dispatchResult.error || "Email blocked."}${checkpointSuffix}`,
          );
        }
        throw new HttpsError(
            "internal",
            `Failed to send auto-routed email: ${dispatchResult.error || "unknown"}`,
        );
      }

      // Success.
      return {
        success: true,
        requisitionId: requisitionId,
        route: dispatchResult.route,
        sentTo: dispatchResult.sentTo,
      };
    },
);

// ========================================
// EMAIL RESEND (user-initiated)
// ========================================

/**
 * User-initiated resend of the auto-routed requisition email. Differs from the
 * legacy sendAutoRoutedRequisitionEmail manual-retry mode in:
 *   - permission gate is "original submitter OR admin" (not admin-only)
 *   - bypasses MAX_AUTO_EMAIL_RETRIES (the user explicitly chose to resend)
 *   - writes user-action events email_resend_requested + email_resend_succeeded
 *     /email_resend_failed in addition to the helper's lower-level events
 *   - returns the structured helper result directly (no legacy response shape)
 *
 * Inputs (in request.data):
 *   requisitionId — required, SOR document id
 *   pdfData — required, base64-encoded PDF payload
 *   fileName — optional, attachment filename (defaults to invoice.pdf)
 *   actorDatabaseId / actorCompanyIdentifier — optional tenant resolution hints
 */
exports.resendRequisitionEmail = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 120,
      memory: "512MiB",
    },
    async (request) => {
      if (!request.auth) {
        console.warn("[EMAIL-RESEND] Rejected unauthenticated request");
        throw new HttpsError(
            "unauthenticated",
            "User must be authenticated to resend requisition emails.",
        );
      }

      const callerUid = request.auth.uid;
      const callerEmail =
        request.auth.token && request.auth.token.email ? request.auth.token.email : "unknown";
      let tenant = await resolveTenantForCallable(request.data, callerUid);
      let tenantDb = getTenantDb(tenant.databaseId);

      const requisitionId = ((request.data && request.data.requisitionId) || "").toString().trim();
      const pdfData = ((request.data && request.data.pdfData) || "").toString();
      const fileName = ((request.data && request.data.fileName) || "invoice.pdf").toString().trim();

      console.log(
          `[EMAIL-RESEND] Request received: requisitionId=${requisitionId || "(missing)"}, ` +
          `callerUid=${callerUid}, tenant=${tenant.companyId}/${tenant.databaseId}, ` +
          `pdfBase64Length=${pdfData.length}`,
      );

      if (!requisitionId) {
        throw new HttpsError("invalid-argument", "requisitionId is required.");
      }
      if (!pdfData) {
        throw new HttpsError("invalid-argument", "pdfData is required.");
      }

      // Resolve requisition with fallback tenant lookup (mirrors legacy callable).
      let requisitionRef = tenantDb.collection("salesRequisitions").doc(requisitionId);
      let requisitionDoc = await requisitionRef.get();
      if (!requisitionDoc.exists) {
        console.warn(
            `[EMAIL-RESEND] Requisition not found in resolved tenant; trying fallback. ` +
            `requisitionId=${requisitionId}, resolvedDatabase=${tenant.databaseId}`,
        );
        const fallbackTenant = await findTenantForRequisitionId(requisitionId);
        if (!fallbackTenant) {
          throw new HttpsError("not-found", "Requisition not found.");
        }
        tenant = {companyId: fallbackTenant.companyId, databaseId: fallbackTenant.databaseId};
        tenantDb = fallbackTenant.tenantDb;
        requisitionRef = tenantDb.collection("salesRequisitions").doc(requisitionId);
        requisitionDoc = await requisitionRef.get();
        console.log(
            `[EMAIL-RESEND] Fallback tenant resolved: requisitionId=${requisitionId}, ` +
            `tenant=${tenant.companyId}/${tenant.databaseId}`,
        );
      }

      const requisitionData = requisitionDoc.data() || {};

      // Permission gate: original submitter OR admin in the resolved tenant.
      // submittedBy is the new canonical field; userID/uid are legacy aliases.
      const submittedBy = (
        requisitionData.submittedBy ||
        requisitionData.userID ||
        requisitionData.uid ||
        ""
      ).toString();
      const isSubmitter = submittedBy && submittedBy === callerUid;
      const isAdmin = await isAdminUser(callerUid, tenantDb);
      if (!isSubmitter && !isAdmin) {
        console.warn(
            `[EMAIL-RESEND] Permission denied: callerUid=${callerUid} is neither submitter ` +
            `(${submittedBy || "unknown"}) nor admin in tenant ${tenant.databaseId}`,
        );
        throw new HttpsError(
            "permission-denied",
            "Only the original submitter or an admin can resend a requisition email.",
        );
      }

      const currentStatus =
        (requisitionData.emailStatus || requisitionData.autoEmailStatus || "").toString();
      const currentAttempts = Number(requisitionData.autoEmailAttemptCount || 0);
      const correlationId = (requisitionData.correlationId || "").toString() || null;
      const callerRole = isAdmin ? "admin" : "user";

      console.log(
          `[EMAIL-RESEND] Loaded requisition state: requisitionId=${requisitionId}, ` +
          `currentStatus=${currentStatus || "(empty)"}, currentAttempts=${currentAttempts}, ` +
          `submitter=${submittedBy || "(unknown)"}, callerRole=${callerRole}`,
      );

      // User-action audit event, distinct from the helper's lower-level
      // email_dispatch_started event that fires inside the dispatch.
      await appendSorEvent(tenantDb, requisitionId, "email_resend_requested", {
        actor: {uid: callerUid, email: callerEmail, role: callerRole},
        details: {currentStatus, currentAttempts, submitter: submittedBy || null},
        correlationId,
      });

      const dispatchResult = await dispatchAutoRoutedEmailForRequisition({
        tenantDb,
        tenant,
        requisitionRef,
        requisitionData,
        pdfData,
        fileName,
        currentAttempts,
        callerUid,
        callerEmail,
        invocationContext: "user_resend",
        correlationId,
      });

      // Wrapper-level outcome event — captures the user-initiated lifecycle
      // separately from the helper's email_dispatch_sent/_failed/_skipped.
      const followupEvent =
        dispatchResult.status === "sent" ? "email_resend_succeeded" :
        dispatchResult.status === "skipped" ? "email_dispatch_skipped" :
        "email_resend_failed";
      await appendSorEvent(tenantDb, requisitionId, followupEvent, {
        actor: {uid: callerUid, email: callerEmail, role: callerRole},
        details: {
          status: dispatchResult.status,
          route: dispatchResult.route,
          sentTo: dispatchResult.sentTo,
          errorCode: dispatchResult.errorCode,
          attemptCountAfter: dispatchResult.attemptCountAfter,
        },
        correlationId,
      });

      console.log(
          `[EMAIL-RESEND] Outcome: requisitionId=${requisitionId}, ` +
          `status=${dispatchResult.status}, attemptCountAfter=${dispatchResult.attemptCountAfter}`,
      );

      return {
        success: dispatchResult.status === "sent",
        requisitionId: requisitionId,
        emailStatus: dispatchResult.status,
        emailRoute: dispatchResult.route,
        emailSentTo: dispatchResult.sentTo,
        emailError: dispatchResult.error,
        emailErrorCode: dispatchResult.errorCode,
        emailMessageId: dispatchResult.messageId,
        attemptCountAfter: dispatchResult.attemptCountAfter,
        correlationId: correlationId,
      };
    },
);

// ========================================
// SOR ROLLBACK (post-acceptance, user-initiated)
// ========================================

/**
 * Determines whether a SOR is eligible for rollback right now. Per decision
 * D.2 in OFFLINE_FIRST_PLAN.md: rollback activates only after at least one
 * email retry beyond the initial send (autoEmailAttemptCount >= 2), is gated
 * to the 24h window after acceptance, and requires emailStatus === "failed".
 *
 * @param {object} requisitionData Sales requisition document data.
 * @param {number} now Current epoch ms (defaults to Date.now()).
 * @return {object} Eligibility verdict with eligible/reason/detail fields.
 */
function evaluateRollbackEligibility(requisitionData, now) {
  const nowMs = typeof now === "number" ? now : Date.now();
  const status = (requisitionData.status || "").toString();
  const emailStatus = (requisitionData.emailStatus || requisitionData.autoEmailStatus || "").toString();
  const attempts = Number(requisitionData.autoEmailAttemptCount || 0);

  if (status !== "accepted") {
    return {
      eligible: false,
      reason: "not_accepted",
      detail: `SOR is not in an accepted state (current: ${status || "unknown"}); rollback only applies to accepted SORs.`,
    };
  }
  if (emailStatus !== "failed") {
    return {
      eligible: false,
      reason: "email_not_failed",
      detail: `Rollback is only available after email failure (current emailStatus: ${emailStatus || "(none)"}).`,
    };
  }
  if (attempts < ROLLBACK_MIN_EMAIL_ATTEMPTS) {
    return {
      eligible: false,
      reason: "insufficient_email_attempts",
      detail:
        `Rollback requires at least ${ROLLBACK_MIN_EMAIL_ATTEMPTS} email attempts ` +
        `(current: ${attempts}). Resend the email at least once before rolling back.`,
    };
  }

  let cutoffMs = null;
  if (requisitionData.rollbackAvailableUntil) {
    const tsRaw = requisitionData.rollbackAvailableUntil;
    cutoffMs = tsRaw && typeof tsRaw.toMillis === "function" ?
      tsRaw.toMillis() : (Number(tsRaw) || null);
  }
  if (!cutoffMs) {
    const createdRaw = requisitionData.createdAt;
    const createdMs = createdRaw && typeof createdRaw.toMillis === "function" ?
      createdRaw.toMillis() : (Number(createdRaw) || null);
    if (createdMs) {
      cutoffMs = createdMs + ROLLBACK_WINDOW_MS;
    }
  }
  if (cutoffMs && nowMs > cutoffMs) {
    return {
      eligible: false,
      reason: "window_expired",
      detail: `Rollback window expired at ${new Date(cutoffMs).toISOString()}.`,
    };
  }

  return {eligible: true, reason: null, detail: null};
}

/**
 * Reverses inventory decrement for an accepted SOR and marks it rolled_back.
 * User-initiated, gated to within the 24h post-acceptance window and to SORs
 * whose email dispatch has failed at least once after retry. Permission:
 * original submitter or admin in the resolved tenant. Eligibility is checked
 * twice — once outside the transaction (cheap fail-fast) and once inside the
 * transaction (race-safe).
 *
 * Inputs (in request.data):
 *   requisitionId — required, SOR document id
 *   reason — required, free text explaining why the rollback is being requested
 *   actorDatabaseId / actorCompanyIdentifier — optional tenant resolution hints
 */
exports.rollbackRequisition = onCall(
    {
      region: CALLABLE_REGION,
      timeoutSeconds: 60,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        console.warn("[ROLLBACK] Rejected unauthenticated request");
        throw new HttpsError(
            "unauthenticated",
            "User must be authenticated to roll back a requisition.",
        );
      }

      const callerUid = request.auth.uid;
      const callerEmail =
        request.auth.token && request.auth.token.email ? request.auth.token.email : "unknown";
      let tenant = await resolveTenantForCallable(request.data, callerUid);
      let tenantDb = getTenantDb(tenant.databaseId);

      const requisitionId = ((request.data && request.data.requisitionId) || "").toString().trim();
      const reason = ((request.data && request.data.reason) || "").toString().trim();

      console.log(
          `[ROLLBACK] Request received: requisitionId=${requisitionId || "(missing)"}, ` +
          `callerUid=${callerUid}, tenant=${tenant.companyId}/${tenant.databaseId}, ` +
          `reasonLength=${reason.length}`,
      );

      if (!requisitionId) {
        throw new HttpsError("invalid-argument", "requisitionId is required.");
      }
      if (!reason) {
        throw new HttpsError(
            "invalid-argument",
            "reason is required (explain why the rollback is being requested).",
        );
      }

      // Resolve requisition with fallback tenant lookup (mirrors other callables).
      let requisitionRef = tenantDb.collection("salesRequisitions").doc(requisitionId);
      let requisitionDoc = await requisitionRef.get();
      if (!requisitionDoc.exists) {
        console.warn(
            `[ROLLBACK] Requisition not found in resolved tenant; trying fallback. ` +
            `requisitionId=${requisitionId}, resolvedDatabase=${tenant.databaseId}`,
        );
        const fallbackTenant = await findTenantForRequisitionId(requisitionId);
        if (!fallbackTenant) {
          throw new HttpsError("not-found", "Requisition not found.");
        }
        tenant = {companyId: fallbackTenant.companyId, databaseId: fallbackTenant.databaseId};
        tenantDb = fallbackTenant.tenantDb;
        requisitionRef = tenantDb.collection("salesRequisitions").doc(requisitionId);
        requisitionDoc = await requisitionRef.get();
        console.log(
            `[ROLLBACK] Fallback tenant resolved: requisitionId=${requisitionId}, ` +
            `tenant=${tenant.companyId}/${tenant.databaseId}`,
        );
      }

      const requisitionData = requisitionDoc.data() || {};

      // Permission gate: original submitter OR admin.
      const submittedBy = (
        requisitionData.submittedBy ||
        requisitionData.userID ||
        requisitionData.uid ||
        ""
      ).toString();
      const isSubmitter = submittedBy && submittedBy === callerUid;
      const isAdmin = await isAdminUser(callerUid, tenantDb);
      if (!isSubmitter && !isAdmin) {
        console.warn(
            `[ROLLBACK] Permission denied: callerUid=${callerUid} is neither submitter ` +
            `(${submittedBy || "unknown"}) nor admin in tenant ${tenant.databaseId}`,
        );
        throw new HttpsError(
            "permission-denied",
            "Only the original submitter or an admin can roll back a requisition.",
        );
      }

      // Cheap fail-fast eligibility check.
      const eligibility = evaluateRollbackEligibility(requisitionData);
      if (!eligibility.eligible) {
        console.warn(
            `[ROLLBACK] Not eligible: requisitionId=${requisitionId}, ` +
            `reason=${eligibility.reason}, detail=${eligibility.detail}`,
        );
        throw new HttpsError("failed-precondition", eligibility.detail);
      }

      const callerRole = isAdmin ? "admin" : "user";
      const correlationId = (requisitionData.correlationId || "").toString() || null;
      const lineItems = Array.isArray(requisitionData.items) ? requisitionData.items : [];

      await appendSorEvent(tenantDb, requisitionId, "rollback_requested", {
        actor: {uid: callerUid, email: callerEmail, role: callerRole},
        details: {reason, lineItemCount: lineItems.length, submitter: submittedBy || null},
        correlationId,
      });

      // Resolve item refs OUTSIDE the transaction (queries can't run inside).
      const resolvedRefs = [];
      const preTxnMissingItems = [];
      for (let i = 0; i < lineItems.length; i++) {
        const rawItem = lineItems[i] || {};
        const lineItem = {
          id: (rawItem.id || "").toString().trim(),
          code: (rawItem.code || "").toString().trim(),
          name: (rawItem.name || "").toString(),
          quantity: Number(rawItem.quantity) || 0,
        };
        if (!lineItem.quantity) {
          // Zero/non-numeric quantity — no inventory to restore.
          continue;
        }
        const ref = await resolveItemRef(tenantDb, lineItem);
        if (!ref) {
          preTxnMissingItems.push({
            lineIndex: i,
            itemId: lineItem.id,
            itemCode: lineItem.code,
            itemName: lineItem.name,
            quantity: lineItem.quantity,
            reason: "item_not_found",
          });
          continue;
        }
        resolvedRefs.push({lineItem, ref});
      }

      let outcome;
      try {
        outcome = await tenantDb.runTransaction(async (txn) => {
          const insideSnap = await txn.get(requisitionRef);
          if (!insideSnap.exists) {
            return {kind: "vanished"};
          }
          const insideData = insideSnap.data() || {};
          const insideEligibility = evaluateRollbackEligibility(insideData);
          if (!insideEligibility.eligible) {
            return {
              kind: "ineligible",
              detail: insideEligibility.detail,
              reason: insideEligibility.reason,
            };
          }

          const stockSnaps = await Promise.all(resolvedRefs.map((entry) => txn.get(entry.ref)));

          const restoredItems = [];
          const txnMissingItems = preTxnMissingItems.slice();
          for (let i = 0; i < resolvedRefs.length; i++) {
            const entry = resolvedRefs[i];
            const snap = stockSnaps[i];
            if (!snap.exists) {
              txnMissingItems.push({
                itemId: entry.lineItem.id,
                itemCode: entry.lineItem.code,
                itemName: entry.lineItem.name,
                quantity: entry.lineItem.quantity,
                reason: "item_vanished_in_txn",
              });
              continue;
            }
            const itemData = snap.data() || {};
            const currentRaw = itemData.stock !== undefined ? itemData.stock : itemData.quantity;
            const current = Number(currentRaw);
            const restored = (Number.isFinite(current) ? current : 0) + entry.lineItem.quantity;
            txn.update(entry.ref, {
              stock: restored,
              quantity: restored,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            restoredItems.push({
              itemId: entry.lineItem.id,
              itemCode: entry.lineItem.code,
              itemName: entry.lineItem.name,
              quantity: entry.lineItem.quantity,
              newStock: restored,
            });
          }

          txn.set(requisitionRef, {
            status: "rolled_back",
            rolledBackAt: admin.firestore.FieldValue.serverTimestamp(),
            rollbackReason: reason,
            rollbackRequestedBy: callerUid,
            rollbackRequestedByRole: callerRole,
            rollbackInventoryRestored: restoredItems,
            rollbackInventorySkipped: txnMissingItems,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          return {kind: "rolled_back", restoredItems, missingItems: txnMissingItems};
        });
      } catch (error) {
        console.error(`[ROLLBACK] Transaction failed for requisitionId=${requisitionId}:`, error);
        await appendSorEvent(tenantDb, requisitionId, "rollback_completed", {
          actor: {uid: callerUid, email: callerEmail, role: callerRole},
          details: {reason, status: "error", error: error && error.message ? error.message : String(error)},
          correlationId,
        });
        throw new HttpsError("internal", "Rollback transaction failed; please retry.");
      }

      if (outcome.kind === "vanished") {
        console.warn(`[ROLLBACK] Requisition vanished mid-transaction: ${requisitionId}`);
        throw new HttpsError("not-found", "Requisition disappeared during rollback.");
      }
      if (outcome.kind === "ineligible") {
        console.warn(
            `[ROLLBACK] Lost race — no longer eligible: requisitionId=${requisitionId}, ` +
            `reason=${outcome.reason}, detail=${outcome.detail}`,
        );
        throw new HttpsError("failed-precondition", outcome.detail);
      }

      await appendSorEvent(tenantDb, requisitionId, "rollback_completed", {
        actor: {uid: callerUid, email: callerEmail, role: callerRole},
        details: {
          reason,
          status: "rolled_back",
          restoredCount: outcome.restoredItems.length,
          skippedCount: outcome.missingItems.length,
          restored: outcome.restoredItems,
          skipped: outcome.missingItems,
        },
        correlationId,
      });

      console.log(
          `[ROLLBACK] Completed: requisitionId=${requisitionId}, ` +
          `restored=${outcome.restoredItems.length}, skipped=${outcome.missingItems.length}`,
      );

      return {
        success: true,
        requisitionId: requisitionId,
        status: "rolled_back",
        inventoryRestored: outcome.restoredItems,
        inventorySkipped: outcome.missingItems,
        correlationId: correlationId,
      };
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
        const approvalEmailBodyPrimary = ((request.data && request.data.approvalEmailBodyPrimary) || "")
          .toString()
          .trim();
        const approvalEmailBodySecondary = ((request.data && request.data.approvalEmailBodySecondary) || "")
          .toString()
          .trim();
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

      if (!approvalEmailBodyPrimary || !approvalEmailBodySecondary) {
        throw new HttpsError(
            "invalid-argument",
            "approvalEmailBodyPrimary and approvalEmailBodySecondary are required.",
        );
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
        approvalEmailBodyPrimary: approvalEmailBodyPrimary,
        approvalEmailBodySecondary: approvalEmailBodySecondary,
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
          approvalEmailBodyPrimary: approvalEmailBodyPrimary,
          approvalEmailBodySecondary: approvalEmailBodySecondary,
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
        approvalEmailBodyPrimary: approvalEmailBodyPrimary,
        approvalEmailBodySecondary: approvalEmailBodySecondary,
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

// ========================================
// TEST-ONLY INTERNAL EXPORTS
// ========================================
// Pure helpers exposed for unit testing. Firebase deploys functions via
// `onCall`/`onRequest`/etc. wrappers — plain object exports are ignored, so
// nothing here ships as a callable. Do NOT import from client code.
exports.__internal = {
  isValidRequisitionUuid,
  validateSubmitRequisitionPayload,
  evaluateRollbackEligibility,
  buildIdempotentReplayResponse,
};
