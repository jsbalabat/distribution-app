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

// ========================================
// SCHEDULED CLEANUP FUNCTION - Runs Daily at Midnight
// ========================================

exports.cleanupExpiredDocuments = onSchedule(
    {
      schedule: "0 0 * * *", // Runs at 00:00 (midnight) every day
      timeZone: "Asia/Manila", // Change to your timezone
      memory: "256MiB",
    },
    async (event) => {
      console.log("🗑️ Starting daily cleanup at midnight...");

      try {
        const now = admin.firestore.Timestamp.now();
        let totalDeleted = 0;

        // Collections to clean up
        const collectionsToClean = [
          "customers",
          "accountReceivable",
          "itemMaster",
          "itemsAvailable",
          "salesRequisitions",
          "emailLogs",
        ];

        // Delete documents from each collection where expiresAt <= now
        for (const collectionName of collectionsToClean) {
          let hasMore = true;

          while (hasMore) {
            const snapshot = await db.collection(collectionName)
                .where("expiresAt", "<=", now)
                .limit(500) // Process in batches of 500
                .get();

            if (snapshot.empty) {
              console.log(`✓ No expired documents in ${collectionName}`);
              hasMore = false;
              break;
            }

            const batch = db.batch();
            let batchCount = 0;

            snapshot.docs.forEach((doc) => {
              batch.delete(doc.ref);
              batchCount++;
            });

            await batch.commit();
            totalDeleted += batchCount;

            console.log(`✓ Deleted ${batchCount} documents from ${collectionName}`);

            // If we got less than 500, we're done with this collection
            if (snapshot.size < 500) {
              hasMore = false;
            }
          }
        }

        // Log cleanup operation
        await db.collection("cleanupLogs").add({
          executedAt: now,
          documentsDeleted: totalDeleted,
          status: "success",
          message: `Cleaned up ${totalDeleted} expired documents`,
        });

        console.log(`Cleanup completed: ${totalDeleted} documents deleted`);

        return {
          success: true,
          deletedCount: totalDeleted,
        };
      } catch (error) {
        console.error("Cleanup failed:", error);

        await db.collection("cleanupLogs").add({
          executedAt: admin.firestore.Timestamp.now(),
          status: "failed",
          error: error.message,
          errorStack: error.stack,
        });

        throw error;
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

      try {
        const bucketName = process.env.FIREBASE_STORAGE_BUCKET || "sales-field-app-f31a2.firebasestorage.app";
        const filePathInBucket = "data_files/document_file.xlsx";
        const tempFilePath = path.join(os.tmpdir(), "document_file.xlsx");

        await storage.bucket(bucketName).file(filePathInBucket).download({destination: tempFilePath});

        const workbook = xlsx.readFile(tempFilePath);
        const sheetName = "customer master";
        const sheetName2 = "acct recble";
        const sheetName3 = "item master";
        const sheetName4 = "items available";

        const sheet = workbook.Sheets[sheetName];
        const sheet2 = workbook.Sheets[sheetName2];
        const sheet3 = workbook.Sheets[sheetName3];
        const sheet4 = workbook.Sheets[sheetName4];

        if (!sheet && !sheet2 && !sheet3 && !sheet4) {
          throw new Error("Sheets not found in customers.xlsx");
        }

        const options = {header: 1};
        const rows = xlsx.utils.sheet_to_json(sheet, options);
        const rows2 = xlsx.utils.sheet_to_json(sheet2, options);
        const rows3 = xlsx.utils.sheet_to_json(sheet3, options);
        const rows4 = xlsx.utils.sheet_to_json(sheet4, options);

        if (rows.length < 2) {
          throw new Error("Sheet does not contain expected headers and data.");
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

        // Calculate expiration date (next day at midnight)
        const expirationDate = new Date();
        expirationDate.setDate(expirationDate.getDate() + 1);
        expirationDate.setHours(0, 0, 0, 0);
        const expiresAt = admin.firestore.Timestamp.fromDate(expirationDate);

        const batch = db.batch();
        const customersRef = db.collection("customers");
        const acctRcble = db.collection("accountReceivable");
        const itemMaster = db.collection("itemMaster");
        const itemsAvailable = db.collection("itemsAvailable");

        data.forEach((row) => {
          const name = row.name || row.Name || row["Customer Name"];
          const creditLimit = parseFloat(row.creditLimit || row["Credit Limit"] || 0);
          const accountNumber = row.accountNumber || row["Account Number"] || "";
          const postalAddress = row.postalAddress || row["Postal Address"] || "";
          const paymentTerms = row.paymentTerms || row["Pmt. Terms"] || "";
          const priceLevel = row.priceLevel || row["Price Level"] || "";
          const deliveryRoute = row.deliveryRoute || row["Delivery Route"] || "";
          const area = row.area || row["Area"] || "";

          if (!name) return;

          const docRef = customersRef.doc();
          batch.set(docRef, {
            name: name.trim(),
            creditLimit,
            accountNumber: accountNumber.toString().trim(),
            postalAddress: postalAddress.toString().trim(),
            paymentTerms: paymentTerms.toString().trim(),
            priceLevel: priceLevel.toString().trim(),
            deliveryRoute: deliveryRoute.toString().trim(),
            area: area.toString().trim(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: expiresAt, // Add TTL field
          });
        });

        data2.forEach((row2) => {
          const name = row2.name || row2.Name || row2["Customer"];
          const accountNumber = row2.accountNumber || row2["Customer ID"] || "";
          const amountDue = parseFloat(row2.amountDue || row2["Amount Due"] || 0);
          const overThirtyDays = parseFloat(row2.overThirtyDays || row2["Over 30 Days"] || 0);
          const unsecured = parseFloat(row2.unsecured || row2["Unsecured"] || 0);

          if (!name) return;

          const docRef2 = acctRcble.doc();
          batch.set(docRef2, {
            name: name.trim(),
            accountNumber: accountNumber.toString().trim(),
            amountDue,
            overThirtyDays,
            unsecured,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: expiresAt, // Add TTL field
          });
        });

        data3.forEach((row3) => {
          const productGroup = row3.productGroup || row3["Product Group"] || "";
          const description = row3.description || row3.Description || row3["Description"];
          const itemCode = row3.itemCode || row3["Item Code"] || "";
          const itemType = row3.itemType || row3["ITEM TYPE"] || "";
          const conversionFactor = parseFloat(row3.conversionFactor || row3["CONVERSION FACTOR"] || 0);
          const regularPrice = parseFloat(row3.regular || row3["REGULAR"] || 0);
          const rmlInclusivePrice = parseFloat(row3["RML INCLUSIVE"] || 0);
          const specialOD = parseFloat(row3["SPECIAL OD"] || 0);

          if (!productGroup) return;

          const docRef3 = itemMaster.doc();
          batch.set(docRef3, {
            productGroup: productGroup.toString().trim(),
            description: description.toString().trim(),
            itemCode: itemCode.toString().trim(),
            conversionFactor,
            regularPrice,
            rmlInclusivePrice,
            specialOD,
            itemType: itemType.toString().trim(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: expiresAt, // Add TTL field
          });
        });

        data4.forEach((row4) => {
          const date = row4.date || row4.Date || row4["Date"] || "";
          const area = row4.area || row4.Area || row4["Area"] || "";
          const productGroup = row4.productGroup || row4["Product Group"] || "";
          const itemCode = row4.itemCode || row4["Item Code"] || "";
          const description = row4.description || row4.Description || row4["Description"];
          const quantity = parseFloat(row4.quantity || row4.Quantity || row4["NET QTY AVAILABLE FOR SALE"] || 0);

          if (!date) return;

          const docRef4 = itemsAvailable.doc();
          batch.set(docRef4, {
            date: date.toString().trim(),
            area: area.toString().trim(),
            productGroup: productGroup.toString().trim(),
            itemCode: itemCode.toString().trim(),
            description: description.toString().trim(),
            quantity,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: expiresAt, // Add TTL field
          });
        });

        await batch.commit();

        await snapshot.ref.update({
          status: "completed",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log("Data import completed successfully");
      } catch (error) {
        await snapshot.ref.update({
          status: "error",
          error: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.error("Import failed:", error);
      }
    },
);
