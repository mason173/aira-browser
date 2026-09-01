const path = require('path');

const dataDir = path.resolve(process.env.AIRA_DATA_DIR || path.join(process.cwd(), 'data'));

module.exports = Object.freeze({
  host: String(process.env.AIRA_HOST || '0.0.0.0'),
  port: normalizePort(process.env.AIRA_PORT || '8787'),
  dataDir,
  databasePath: path.join(dataDir, 'aira-personal-server.db'),
  setupCodePath: path.join(dataDir, 'setup-code'),
  publicBaseUrl: String(process.env.AIRA_PUBLIC_URL || '').trim().replace(/\/+$/, ''),
  pairingCodeTtlMs: normalizePositiveInteger(process.env.AIRA_PAIRING_CODE_TTL_MS, 10 * 60 * 1000),
  bodyLimitBytes: normalizePositiveInteger(process.env.AIRA_BODY_LIMIT_BYTES, 12 * 1024 * 1024),
});

function normalizePort(value) {
  const port = Number(value);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error('AIRA_PORT must be an integer between 1 and 65535.');
  }
  return port;
}

function normalizePositiveInteger(value, fallback) {
  const number = Number(value || fallback);
  if (!Number.isSafeInteger(number) || number <= 0) {
    return fallback;
  }
  return number;
}

