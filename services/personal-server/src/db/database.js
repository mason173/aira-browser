const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { dataDir, databasePath } = require('../config');

fs.mkdirSync(dataDir, { recursive: true, mode: 0o700 });
const db = new Database(databasePath);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');
db.pragma('busy_timeout = 5000');

db.exec(`
  CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at INTEGER NOT NULL
  )
`);

const migrationDir = path.join(__dirname, '..', '..', 'migrations');
const applied = new Set(db.prepare('SELECT version FROM schema_migrations').all().map((row) => row.version));
const applyMigration = db.transaction((version, sql) => {
  db.exec(sql);
  db.prepare('INSERT INTO schema_migrations(version, applied_at) VALUES(?, ?)').run(version, Date.now());
});

fs.readdirSync(migrationDir)
  .filter((name) => name.endsWith('.sql'))
  .sort()
  .forEach((name) => {
    if (!applied.has(name)) {
      applyMigration(name, fs.readFileSync(path.join(migrationDir, name), 'utf8'));
    }
  });

module.exports = { db, databasePath };
