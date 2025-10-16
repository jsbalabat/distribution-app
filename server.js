const express = require('express');
const { exec } = require('child_process');
const app = express();
const PORT = process.env.PORT || 3000;

// POST endpoint to trigger upload_customers.js
app.post('/upload-customers', (req, res) => {
  exec('node upload_customers.js', (error, stdout, stderr) => {
    if (error) {
      console.error(`Error: ${error.message}`);
      return res.status(500).send('Upload failed.');
    }
    if (stderr) {
      console.error(`Stderr: ${stderr}`);
      // You can choose to treat stderr as a failure or not
    }
    console.log(`Stdout: ${stdout}`);
    res.send('Upload complete!');
  });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});