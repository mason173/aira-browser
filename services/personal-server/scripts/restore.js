const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { dataDir, databasePath } = require('../src/config');

const sourceArgument = String(process.argv[2] || '').trim();
if (!sourceArgument) {
  throw new Error('Usage: npm run restore -- /absolute/path/to/aira-personal-server.backup');
}

const source = path.resolve(sourceArgument);
if (!fs.existsSync(source) || !fs.statSync(source).isFile()) {
  throw new Error(`Backup file does not exist: ${source}`);
}
if (source === databasePath) {
  throw new Error('Backup source must not be the active database.');
}

verifyDatabase(source);
fs.mkdirSync(dataDir, { recursive: true, mode: 0o700 });
const suffix = new Date().toISOString().replace(/[:.]/g, '-');
const staged = path.join(dataDir, `.restore-${process.pid}-${suffix}.db`);
const previous = `${databasePath}.pre-restore-${suffix}`;

fs.copyFileSync(source, staged, fs.constants.COPYFILE_EXCL);
try {
  verifyDatabase(staged);
  if (fs.existsSync(databasePath)) {
    fs.renameSync(databasePath, previous);
  }
  fs.renameSync(staged, databasePath);
  fs.chmodSync(databasePath, 0o600);
  console.log(`Restored database: ${databasePath}`);
  if (fs.existsSync(previous)) {
    console.log(`Previous database retained at: ${previous}`);
  }
} catch (error) {
  if (fs.existsSync(staged)) fs.unlinkSync(staged);
  throw error;
}

function verifyDatabase(filename) {
  const db = new Database(filename, { readonly: true, fileMustExist: true });
  try {
    const integrity = db.pragma('integrity_check', { simple: true });
    if (integrity !== 'ok') throw new Error(`SQLite integrity check failed: ${integrity}`);
    const tables = new Set(db.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table'"
    ).all().map((row) => row.name));
    for (const required of ['schema_migrations', 'instance_meta', 'devices']) {
      if (!tables.has(required)) throw new Error(`Backup is missing required table: ${required}`);
    }
  } finally {
    db.close();
  }
}
