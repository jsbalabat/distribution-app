/* eslint-disable object-curly-spacing */
/* eslint-disable max-len */
const admin = require("firebase-admin");
const xlsx = require("xlsx");
const {Storage} = require("@google-cloud/storage");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const os = require("os");
const path = require("path");
const nodemailer = require("nodemailer");

admin.initializeApp();
const db = admin.firestore();
const storage = new Storage();

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

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    deleted += snapshot.size;
    hasMore = snapshot.size >= 500;
  }

  return deleted;
}

/**
 * Resolves audit log retention days from Firestore settings with env fallback.
 * @return {Promise<number>} Retention period in days.
 */
async function getAuditLogRetentionDays() {
  const defaultRetentionDays = 180;
  const envValue = Number(process.env.AUDIT_LOG_RETENTION_DAYS || defaultRetentionDays);
  const envRetentionDays = Number.isFinite(envValue) ? envValue : defaultRetentionDays;

  try {
    const settingsDoc = await db.collection("settings").doc("appSettings").get();
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
 * Verifies that the calling user is an admin user.
 * @param {string} uid Firebase Auth UID.
 * @return {Promise<boolean>} Whether the user is an admin.
 */
async function isAdminUser(uid) {
  if (!uid) {
    return false;
  }

  const userDoc = await db.collection("users").doc(uid).get();
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
      if (header) obj[header.toString().trim()] = row4[i];
    });
    return obj;
  });

  return {data, data2, data3, data4};
}

/**
 * Writes parsed import rows into Firestore in batched chunks.
 * @param {{data: object[], data2: object[], data3: object[], data4: object[]}} parsed Parsed workbook rows.
 * @return {Promise<object>} Insert summary by collection.
 */
async function importParsedWorkbookData(parsed) {
  let batch = db.batch();
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
    batch = db.batch();
    operations = 0;
  }

  /**
   * Adds a single document write into the current import batch.
   * @param {string} collectionName Target Firestore collection.
   * @param {object} payload Document payload to insert.
   * @return {Promise<void>}
   */
  async function addDoc(collectionName, payload) {
    const ref = db.collection(collectionName).doc();
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
    const quantity = parseFloat(row4.quantity || row4.Quantity || row4["NET QTY AVAILABLE FOR SALE"] || 0);

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
// SCHEDULED CLEANUP FUNCTION - Runs Daily at Midnight
// Prunes old operational records while preserving live data
// ========================================

exports.deleteAllDataExceptUsersAndLogs = onSchedule(
    {
      schedule: "0 0 * * *", // Runs at 00:00 (midnight) every day
      timeZone: "Asia/Manila", // Change to your timezone
      memory: "512MiB",
    },
    async (event) => {
      console.log("Starting scheduled maintenance cleanup at midnight...");

      try {
        const now = admin.firestore.Timestamp.now();
        let totalDeleted = 0;
        const deletionDetails = {};

        const retentionDays = Number(process.env.MAINTENANCE_RETENTION_DAYS || 30);
        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - retentionDays);
        const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

        // Collections to prune when they age out.
        const collectionsToPrune = [
          {name: "dataImports", field: "requestedAt"},
          {name: "cleanupLogs", field: "executedAt"},
        ];

        // Collections to PRESERVE (never delete)
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

        console.log(`Retention days: ${retentionDays}`);
        console.log(`Collections to prune: ${collectionsToPrune.map((item) => item.name).join(", ")}`);
        console.log(`Protected collections: ${preservedCollections.join(", ")}`);

        for (const collectionConfig of collectionsToPrune) {
          console.log(`Processing collection: ${collectionConfig.name}`);
          const query = db
              .collection(collectionConfig.name)
              .where(collectionConfig.field, "<", cutoffTimestamp)
              .limit(500);

          const collectionDeleted = await deleteInBatches(query);
          deletionDetails[collectionConfig.name] = collectionDeleted;
          totalDeleted += collectionDeleted;

          console.log(`  Deleted ${collectionDeleted} documents from ${collectionConfig.name}`);
        }

        // Log cleanup operation with detailed breakdown
        await db.collection("cleanupLogs").add({
          executedAt: now,
          type: "scheduled_maintenance",
          totalDocumentsDeleted: totalDeleted,
          deletionDetails: deletionDetails,
          preservedCollections: preservedCollections,
          deletedCollections: collectionsToPrune.map((item) => item.name),
          retentionDays: retentionDays,
          status: "success",
          message: `Maintenance cleanup: ${totalDeleted} old documents deleted from ${collectionsToPrune.length} collections`,
        });

        console.log(`Maintenance cleanup finished: ${totalDeleted} total documents deleted`);
        console.log("Deletion breakdown:", deletionDetails);

        return {
          success: true,
          totalDeleted: totalDeleted,
          details: deletionDetails,
          preserved: preservedCollections,
          retentionDays: retentionDays,
        };
      } catch (error) {
        console.error("Maintenance cleanup failed:", error);

        await db.collection("cleanupLogs").add({
          executedAt: admin.firestore.Timestamp.now(),
          type: "scheduled_maintenance",
          status: "failed",
          error: error.message,
          errorStack: error.stack,
        });

        throw error;
      }
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
      const retentionDays = await getAuditLogRetentionDays();
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - retentionDays);
      const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

      console.log(
          `Starting audit log pruning. Retention: ${retentionDays} days, cutoff: ${cutoffDate.toISOString()}`,
      );

      try {
        const pruneQuery = db
            .collection("auditLogs")
            .where("timestamp", "<", cutoffTimestamp)
            .limit(500);

        const deletedCount = await deleteInBatches(pruneQuery);

        await db.collection("cleanupLogs").add({
          executedAt: admin.firestore.Timestamp.now(),
          type: "audit_log_prune",
          status: "success",
          retentionDays: retentionDays,
          cutoffTimestamp: cutoffTimestamp,
          deletedCount: deletedCount,
          message: `Pruned ${deletedCount} audit logs older than ${retentionDays} days`,
        });

        console.log(`Audit log pruning completed. Deleted: ${deletedCount}`);

        return {
          success: true,
          deletedCount: deletedCount,
          retentionDays: retentionDays,
        };
      } catch (error) {
        console.error("Audit log pruning failed:", error);

        await db.collection("cleanupLogs").add({
          executedAt: admin.firestore.Timestamp.now(),
          type: "audit_log_prune",
          status: "failed",
          retentionDays: retentionDays,
          error: error.message,
          errorStack: error.stack,
        });

        throw error;
      }
    },
);

// ========================================
// DESTRUCTIVE CLEANUP FUNCTION - Admin triggered only
// Deletes live business data on explicit confirmation
// ========================================

exports.runDestructiveCleanup = onCall(
    {
      timeoutSeconds: 540,
      memory: "512MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in to run cleanup.");
      }

      const callerUid = request.auth.uid;
      const isAdmin = await isAdminUser(callerUid);
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
              db.collection(collectionName).limit(500),
          );
          deletionDetails[collectionName] = deletedCount;
          totalDeleted += deletedCount;
        }

        await db.collection("cleanupLogs").add({
          executedAt: admin.firestore.Timestamp.now(),
          type: "destructive_cleanup",
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
        await db.collection("cleanupLogs").add({
          executedAt: admin.firestore.Timestamp.now(),
          type: "destructive_cleanup",
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
      timeoutSeconds: 540,
      memory: "1GiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "You must be signed in to import data.");
      }

      const callerUid = request.auth.uid;
      console.log(`[IMPORT][DIRECT] Request received from uid=${callerUid}`);
      const isAdmin = await isAdminUser(callerUid);
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

        const summary = await importParsedWorkbookData(parsed);
    console.log(`[IMPORT][DIRECT] Firestore write summary: ${JSON.stringify(summary)}`);

        await db.collection("dataImports").add({
          status: "completed",
          source: "directUpload",
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
      timeoutSeconds: 60,
      memory: "256MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError(
            "unauthenticated",
            "User must be authenticated to send emails",
        );
      }

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
        // Get credentials from environment variables
        const gmailEmail = process.env.GMAIL_EMAIL;
        const gmailPassword = process.env.GMAIL_PASSWORD;

        if (!gmailEmail || !gmailPassword) {
          console.error("Gmail credentials not configured");
          throw new HttpsError(
              "failed-precondition",
              "Email service is not properly configured",
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

        await db.collection("emailLogs").add({
          to: to,
          subject: mailOptions.subject,
          sorNumber: sorNumber,
          customerName: customerName,
          sentBy: request.auth.uid,
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

        // Calculate expiration date (30 days from now)
        const expirationDate = new Date();
        expirationDate.setDate(expirationDate.getDate() + 30);
        const expiresAt = admin.firestore.Timestamp.fromDate(expirationDate);

        await db.collection("emailLogs").add({
          to: to,
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
