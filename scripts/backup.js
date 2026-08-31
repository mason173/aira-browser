const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { dataDir, databasePath } = require('../src/config');

const destination = path.resolve(process.argv[2] || path.join(
  dataDir,
  `aira-personal-server-${new Date().toISOString().replace(/[:.]/g, '-')}.backup`
));

if (!fs.existsSync(databasePath)) {
  throw new Error(`Database does not exist: ${databasePath}`);
}
fs.mkdirSync(path.dirname(destination), { recursive: true });
const db = new Database(databasePath, { readonly: true });
db.backup(destination)
  .then(() => {
    db.close();
    console.log(destination);
  })
  .catch((error) => {
    db.close();
    console.error(error);
    process.exitCode = 1;
  });
