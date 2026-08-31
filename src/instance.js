const crypto = require('crypto');
const fs = require('fs');
const { db } = require('./db/database');
const { pairingCodeTtlMs, setupCodePath } = require('./config');
const { fail } = require('./errors');

const DEVICE_ID_PATTERN = /^[A-Za-z0-9._-]{1,160}$/;
const getInstanceStatement = db.prepare('SELECT instance_id, created_at FROM instance_meta WHERE singleton = 1');
const insertInstanceStatement = db.prepare(
  'INSERT INTO instance_meta(singleton, instance_id, created_at) VALUES(1, ?, ?)'
);
const insertPairingCodeStatement = db.prepare(`
  INSERT INTO pairing_codes(code_hash, kind, created_by_device_id, created_at, expires_at, used_at)
  VALUES(@code_hash, @kind, @created_by_device_id, @created_at, @expires_at, 0)
`);
const consumePairingCodeStatement = db.prepare(`
  UPDATE pairing_codes SET used_at = @used_at
  WHERE code_hash = @code_hash AND used_at = 0 AND expires_at >= @used_at
`);
const getPairingCodeStatement = db.prepare(
  'SELECT kind FROM pairing_codes WHERE code_hash = ? AND used_at = 0 AND expires_at >= ?'
);
const insertDeviceStatement = db.prepare(`
  INSERT INTO devices(device_id, credential_id, token_hash, name, created_at, last_seen_at, rotated_at, revoked_at)
  VALUES(@device_id, @credential_id, @token_hash, @name, @created_at, @last_seen_at, 0, 0)
`);
const authenticateStatement = db.prepare(`
  SELECT device_id, credential_id, name, created_at, last_seen_at, rotated_at
  FROM devices WHERE token_hash = ? AND revoked_at = 0
`);
const touchDeviceStatement = db.prepare('UPDATE devices SET last_seen_at = ? WHERE device_id = ? AND revoked_at = 0');
const listDevicesStatement = db.prepare(`
  SELECT device_id, credential_id, name, created_at, last_seen_at, rotated_at, revoked_at
  FROM devices ORDER BY created_at ASC, device_id ASC
`);
const revokeDeviceStatement = db.prepare(
  'UPDATE devices SET revoked_at = ? WHERE device_id = ? AND revoked_at = 0'
);
const rotateDeviceStatement = db.prepare(`
  UPDATE devices SET credential_id = @credential_id, token_hash = @token_hash, rotated_at = @rotated_at
  WHERE device_id = @device_id AND revoked_at = 0
`);

function initializeInstance() {
  const existing = getInstanceStatement.get();
  if (existing) return existing;
  const now = Date.now();
  const instanceId = `aira_${crypto.randomUUID()}`;
  const setupCode = createReadableCode();
  db.transaction(() => {
    insertInstanceStatement.run(instanceId, now);
    insertPairingCodeStatement.run({
      code_hash: hashSecret(setupCode),
      kind: 'bootstrap',
      created_by_device_id: '',
      created_at: now,
      expires_at: now + 24 * 60 * 60 * 1000,
    });
  })();
  fs.writeFileSync(setupCodePath, `${setupCode}\n`, { encoding: 'utf8', mode: 0o600, flag: 'wx' });
  return { instance_id: instanceId, created_at: now, setupCode };
}

function exchangePairingCode(body) {
  const code = requireString(body.code, 'missing_pairing_code', 'Pairing code is required.', 128);
  const deviceId = requireDeviceId(body.deviceId);
  const deviceName = requireString(body.deviceName, 'missing_device_name', 'Device name is required.', 128);
  const now = Date.now();
  const codeHash = hashSecret(code);
  const pairing = getPairingCodeStatement.get(codeHash, now);
  if (!pairing) fail(401, 'invalid_pairing_code', 'Pairing code is invalid, expired, or already used.');
  const token = crypto.randomBytes(32).toString('base64url');
  const credentialId = crypto.randomUUID();
  try {
    db.transaction(() => {
      if (consumePairingCodeStatement.run({ code_hash: codeHash, used_at: now }).changes !== 1) {
        fail(409, 'pairing_code_used', 'Pairing code was already used.');
      }
      insertDeviceStatement.run({
        device_id: deviceId,
        credential_id: credentialId,
        token_hash: hashSecret(token),
        name: deviceName,
        created_at: now,
        last_seen_at: now,
      });
    })();
  } catch (error) {
    if (String(error && error.code || '').startsWith('SQLITE_CONSTRAINT')) {
      fail(409, 'device_already_paired', 'This device ID is already paired.');
    }
    throw error;
  }
  if (pairing.kind === 'bootstrap' && fs.existsSync(setupCodePath)) fs.unlinkSync(setupCodePath);
  return {
    instanceId: getInstance().instanceId,
    protocolVersion: 1,
    deviceId,
    credentialId,
    token,
  };
}

function authenticate(request) {
  const value = String(request.headers.authorization || '').trim();
  if (!value.startsWith('Bearer ')) fail(401, 'missing_device_credential', 'Device credential is required.');
  const token = value.slice('Bearer '.length).trim();
  if (!token) fail(401, 'missing_device_credential', 'Device credential is required.');
  const device = authenticateStatement.get(hashSecret(token));
  if (!device) fail(401, 'invalid_device_credential', 'Device credential is invalid or revoked.');
  touchDeviceStatement.run(Date.now(), device.device_id);
  return toDevice(device);
}

function createPairingCode(device) {
  const now = Date.now();
  const code = createReadableCode();
  insertPairingCodeStatement.run({
    code_hash: hashSecret(code),
    kind: 'device',
    created_by_device_id: device.deviceId,
    created_at: now,
    expires_at: now + pairingCodeTtlMs,
  });
  return { code, expiresAt: now + pairingCodeTtlMs };
}

function listDevices() {
  return listDevicesStatement.all().map(toDevice);
}

function revokeDevice(deviceId) {
  const normalized = requireDeviceId(deviceId);
  if (revokeDeviceStatement.run(Date.now(), normalized).changes !== 1) {
    fail(404, 'device_not_found', 'Active device was not found.');
  }
}

function rotateCredential(device) {
  const token = crypto.randomBytes(32).toString('base64url');
  const credentialId = crypto.randomUUID();
  const now = Date.now();
  if (rotateDeviceStatement.run({
    credential_id: credentialId,
    token_hash: hashSecret(token),
    rotated_at: now,
    device_id: device.deviceId,
  }).changes !== 1) {
    fail(404, 'device_not_found', 'Active device was not found.');
  }
  return { deviceId: device.deviceId, credentialId, token, rotatedAt: now };
}

function getInstance() {
  const row = getInstanceStatement.get();
  return { instanceId: row.instance_id, createdAt: row.created_at };
}

function hashSecret(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function createReadableCode() {
  return crypto.randomBytes(18).toString('base64url').toUpperCase();
}

function requireDeviceId(value) {
  const normalized = String(value || '').trim();
  if (!DEVICE_ID_PATTERN.test(normalized)) {
    fail(400, 'invalid_device_id', 'Device ID must use 1-160 letters, numbers, dots, underscores, or hyphens.');
  }
  return normalized;
}

function requireString(value, code, message, maxLength) {
  const normalized = String(value || '').trim();
  if (!normalized || normalized.length > maxLength) fail(400, code, message);
  return normalized;
}

function toDevice(row) {
  return {
    deviceId: row.device_id,
    credentialId: row.credential_id,
    name: row.name,
    createdAt: Number(row.created_at || 0),
    lastSeenAt: Number(row.last_seen_at || 0),
    rotatedAt: Number(row.rotated_at || 0),
    revokedAt: Number(row.revoked_at || 0),
  };
}

module.exports = {
  authenticate,
  createPairingCode,
  exchangePairingCode,
  getInstance,
  initializeInstance,
  listDevices,
  revokeDevice,
  rotateCredential,
};

