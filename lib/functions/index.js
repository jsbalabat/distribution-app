// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const xlsx = require('xlsx');
const fs = require('fs');
const path = require('path');

admin.initializeApp();
const db = admin.firestore();

// This function will be triggered when a new document is added to the dataImports collection
exports.importDataFromExcel = functions.firestore
  .document('dataImports/{importId}')
  .onCreate(async (snapshot, context) => {
    const importData = snapshot.data();
    const importId = context.params.importId;
    
    // Update status to processing
    await snapshot.ref.update({
      status: 'processing',
      startedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    try {
      // Path to the Excel file
      const filePath = path.join(__dirname, 'data_files/document_file.xlsx');
      
      // Check if file exists
      if (!fs.existsSync(filePath)) {
        throw new Error(`Excel file not found at ${filePath}`);
      }
      
      // Load Excel file
      const workbook = xlsx.readFile(filePath);
      
      // Sheet names to read from
      const sheetNames = {
        customerMaster: 'customer master',
        acctRecble: 'acct recble',
        itemMaster: 'item master',
        itemsAvailable: 'items available'
      };
      
      // Process each sheet
      await processCustomerMaster(workbook, sheetNames.customerMaster);
      await processAccountReceivable(workbook, sheetNames.acctRecble);
      await processItemMaster(workbook, sheetNames.itemMaster);
      await processItemsAvailable(workbook, sheetNames.itemsAvailable);
      
      // Update status to completed
      await snapshot.ref.update({
        status: 'completed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        message: 'Data import completed successfully'
      });
      
      return { success: true, message: 'Data imported successfully' };
    } catch (error) {
      console.error('Error importing data:', error);
      
      // Update status to error
      await snapshot.ref.update({
        status: 'error',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        error: error.message
      });
      
      return { success: false, error: error.message };
    }
  });

// Helper functions to process each sheet
async function processCustomerMaster(workbook, sheetName) {
  const sheet = workbook.Sheets[sheetName];
  if (!sheet) throw new Error(`Sheet "${sheetName}" not found`);
  
  // Convert sheet to JSON, skipping the first row (master header)
  const options = { header: 1 }; 
  const rows = xlsx.utils.sheet_to_json(sheet, options);
  
  // Validate we have enough rows
  if (rows.length < 2) {
    throw new Error(`Sheet "${sheetName}" does not contain expected headers and data.`);
  }
  
  // Use row[1] as the actual header row (skip row[0])
  const headers = rows[1];
  const dataRows = rows.slice(2); // skip first 2 rows
  
  // Convert array of arrays to array of objects using headers
  const data = dataRows.map((row) => {
    const obj = {};
    headers.forEach((header, i) => {
      if (header) obj[header.toString().trim()] = row[i];
    });
    return obj;
  });
  
  // Process data in batches
  const batch = db.batch();
  const customersRef = db.collection('customers');
  
  data.forEach((row) => {
    const name = row.name || row.Name || row['Customer Name'];
    const creditLimit = parseFloat(row.creditLimit || row['Credit Limit'] || 0);
    const accountNumber = row.accountNumber || row['Account Number'] || '';
    const postalAddress =  row.postalAddress || row['Postal Address'] || '';
    const paymentTerms = row.paymentTerms || row['Pmt. Terms'] || '';
    const priceLevel = row.priceLevel || row['Price Level'] || '';
    const deliveryRoute = row.deliveryRoute || row['Delivery Route'] || '';
    const area = row.area || row['Area'] || '';
    
    if (!name) return;
    
    const docRef = customersRef.doc(); // auto-ID
    batch.set(docRef, {
      name: name.trim(),
      creditLimit,
      accountNumber: accountNumber.toString().trim(),
      postalAddress: postalAddress.toString().trim(),
      paymentTerms: paymentTerms.toString().trim(),
      priceLevel: priceLevel.toString().trim(),
      deliveryRoute: deliveryRoute.toString().trim(),
      area: area.toString().trim(),
    });
  });
  
  await batch.commit();
  console.log(`✅ Customers from "${sheetName}" uploaded successfully.`);
}

// Implement the other processing functions similarly
// ...

// For brevity, I'm not including the other processing functions, but they would follow the same pattern
async function processAccountReceivable(workbook, sheetName) {
  // Similar implementation as processCustomerMaster
}

async function processItemMaster(workbook, sheetName) {
  // Similar implementation as processCustomerMaster
}

async function processItemsAvailable(workbook, sheetName) {
  // Similar implementation as processCustomerMaster
}