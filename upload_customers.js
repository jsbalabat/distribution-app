const admin = require('firebase-admin');
const xlsx = require('xlsx');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();

// Load Excel file
const workbook = xlsx.readFile('./data_files/document_file.xlsx');

// Sheet name to read from
const sheetName = 'customer master';
const sheetName2 = 'acct recble'
const sheetName3 = 'item master';
const sheetName4 = 'items available';
const sheet = workbook.Sheets[sheetName];
const sheet2 = workbook.Sheets[sheetName2];
const sheet3 = workbook.Sheets[sheetName3];
const sheet4 = workbook.Sheets[sheetName4];


if (!sheet && !sheet2 && !sheet3 && !sheet4) {
  console.error(`❌ Sheets not found in customers.xlsx`);
  process.exit(1);
}

// Convert sheet to JSON, skipping the first row (master header)
const options = { header: 1 }; // raw array format
const rows = xlsx.utils.sheet_to_json(sheet, options);
const rows2 = xlsx.utils.sheet_to_json(sheet2, options);
const rows3 = xlsx.utils.sheet_to_json(sheet3, options);
const rows4 = xlsx.utils.sheet_to_json(sheet4, options);

// Validate we have enough rows
if (rows.length < 2) {
  console.error('❌ Sheet does not contain expected headers and data.');
  process.exit(1);
}

// 1
// Use row[1] as the actual header row (skip row[0])
const headers = rows[1];
const dataRows = rows.slice(2); // skip first 2 rows (0: master, 1: column names)

const headers2 = rows2[1];
const dataRows2 = rows2.slice(2); // skip first 2 rows (0: master, 1: column names)

const headers3 = rows3[1];
const dataRows3 = rows3.slice(2); // skip first 2 rows (0: master, 1: column names)

const headers4 = rows4[1];
const dataRows4 = rows4.slice(2); // skip first 2 rows (0: master, 1: column names)

// customers
// Convert array of arrays to array of objects using headers
const data = dataRows.map((row) => {
  const obj = {};
  headers.forEach((header, i) => {
    if (header) obj[header.toString().trim()] = row[i];
  });
  return obj;
});

// 2
// Convert array of arrays to array of objects using headers
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

(async () => {
  console.log(`Uploading customer records...`);

  const batch = db.batch();
  const customersRef = db.collection('customers');
//  const customersGeneral = db.collection('customersGeneral');
//  const customersContact = db.collection('customersContact');
//  const customersTerms = db.collection('customersTerms');
  const acctRcble = db.collection('accountReceivable');
  const itemMaster = db.collection('itemMaster');
  const itemsAvailable = db.collection('itemsAvailable');

  data.forEach((row) => {
    const name = row.name || row.Name || row['Customer Name'];
    const creditLimit = parseFloat(row.creditLimit || row['Credit Limit'] || 0);
    const accountNumber = row.accountNumber || row['Account Number'] || '';
    const postalAddress =  row.postalAddress || row['Postal Address'] || '';
    const paymentTerms = row.paymentTerms || row['Pmt. Terms'] || '';
    const priceLevel = row.priceLevel || row['Price Level'] || '';
    const deliveryRoute = row.deliveryRoute || row['Delivery Route'] || '';
    const area = row.area || row['Area'] || '';
    const locality = row.locality || row['Locality'] || '';

    if (!name) return;

    // customers
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

  data2.forEach((row2) => {
    const name = row2.name || row2.Name || row2['Customer'];
    const accountNumber = row2.accountNumber || row2['Customer ID'] || '';
    const amountDue = parseFloat(row2.amountDue || row2['Amount Due'] || 0);
    const overThirtyDays = parseFloat(row2.overThirtyDays || row2['Over 30 Days'] || 0);
    const unsecured = parseFloat(row2.unsecured || row2['Unsecured'] || 0);

    if (!name) return;

    const docRef2 = acctRcble.doc(); // auto-ID
    batch.set(docRef2, {
      name: name.trim(),
      accountNumber: accountNumber.toString().trim(),
      amountDue,
      overThirtyDays,
      unsecured,
    });
  });

  data3.forEach((row3) => {
    const productGroup = row3.productGroup || row3['Product Group'] || '';
    const description = row3.description || row3.Description || row3['Description'];
    const itemCode = row3.itemCode || row3['Item Code'] || '';
    const itemType = row3.itemType || row3['ITEM TYPE'] || '';
    const conversionFactor = parseFloat(row3.conversionFactor || row3['CONVERSION FACTOR'] || 0);
    const regularPrice = parseFloat(row3.regular || row3['REGULAR'] || 0);
    const rmlInclusivePrice = parseFloat(row3['RML INCLUSIVE'] || 0);
    const specialOD = parseFloat(row3['SPECIAL OD'] || 0);

    if (!productGroup) return;

    const docRef3 = itemMaster.doc(); // auto-ID
    batch.set(docRef3, {
      productGroup: productGroup.toString().trim(),
      description: description.toString().trim(),
      itemCode: itemCode.toString().trim(),
      conversionFactor,
      regularPrice,
      rmlInclusivePrice,
      specialOD,
      itemType: itemType.toString().trim()
    });
  });

  data4.forEach((row4) => {
    const date = row4.date || row4.Date || row4['Date'] || '';
    const area = row4.area || row4.Area || row4['Area'] || '';
    const productGroup = row4.productGroup || row4['Product Group'] || '';
    const itemCode = row4.itemCode || row4['Item Code'] || '';
    const description = row4.description || row4.Description || row4['Description'];
    const quantity = parseFloat(row4.quantity || row4.Quantity || row4['NET QTY AVAILABLE FOR SALE'] || 0);

    if (!date) return;

    const docRef4 = itemsAvailable.doc(); // auto-ID
    batch.set(docRef4, {
      date: date.toString().trim(),
      area: area.toString().trim(),
      productGroup: productGroup.toString().trim(),
      itemCode: itemCode.toString().trim(),
      description: description.toString().trim(),
      quantity,
    });
  });

  await batch.commit();
  console.log('✅ Customers from "CUSTOMER LIST" uploaded successfully.');
})();

