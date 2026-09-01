const { db } = require('./db/database');
const { fail } = require('./errors');

const ONLINE_WINDOW_MS = 2 * 60 * 1000;
const PHYSICAL_RETENTION_MS = 10 * 60 * 1000;
const MAX_TABS = 100;
const MAX_FUTURE_SKEW_MS = 24 * 60 * 60 * 1000;

const upsertSnapshot = db.prepare(`
  INSERT INTO cross_device_tab_snapshots_v1(
    device_id, device_kind, device_name, platform, model, browser_name, browser_version,
    tabs_json, updated_at, expires_at
  ) VALUES(
    @device_id, @device_kind, @device_name, @platform, @model, @browser_name, @browser_version,
    @tabs_json, @updated_at, @expires_at
  )
  ON CONFLICT(device_id) DO UPDATE SET
    device_kind = excluded.device_kind,
    device_name = excluded.device_name,
    platform = excluded.platform,
    model = excluded.model,
    browser_name = excluded.browser_name,
    browser_version = excluded.browser_version,
    tabs_json = excluded.tabs_json,
    updated_at = excluded.updated_at,
    expires_at = excluded.expires_at
`);
const listOnlineSnapshots = db.prepare(`
  SELECT snapshots.* FROM cross_device_tab_snapshots_v1 AS snapshots
  INNER JOIN devices ON devices.device_id = snapshots.device_id
  WHERE snapshots.device_kind = ? AND snapshots.device_id <> ? AND snapshots.expires_at > ?
    AND devices.device_kind = snapshots.device_kind AND devices.revoked_at = 0
  ORDER BY snapshots.updated_at DESC, snapshots.device_id ASC
`);
const deleteSnapshot = db.prepare('DELETE FROM cross_device_tab_snapshots_v1 WHERE device_id = ?');
const deleteExpiredSnapshots = db.prepare(
  'DELETE FROM cross_device_tab_snapshots_v1 WHERE expires_at < ?'
);

function publish(body, device) {
  const now = Date.now();
  const metadata = normalizeDevice(body.device, device);
  const tabs = normalizeTabs(body.tabs, now);
  cleanup(now);
  upsertSnapshot.run({
    device_id: device.deviceId,
    device_kind: device.deviceKind,
    device_name: metadata.deviceName,
    platform: metadata.platform,
    model: metadata.model,
    browser_name: metadata.browserName,
    browser_version: metadata.browserVersion,
    tabs_json: JSON.stringify(tabs),
    updated_at: now,
    expires_at: now + ONLINE_WINDOW_MS,
  });
  return {
    deviceId: device.deviceId,
    tabCount: tabs.length,
    updatedAt: now,
    expiresAt: now + ONLINE_WINDOW_MS,
    onlineWindowMs: ONLINE_WINDOW_MS,
  };
}

function list(device) {
  const now = Date.now();
  cleanup(now);
  const targetKind = device.deviceKind === 'desktop' ? 'phone' : 'desktop';
  return {
    serverTime: now,
    onlineWindowMs: ONLINE_WINDOW_MS,
    devices: listOnlineSnapshots.all(targetKind, device.deviceId, now).map((row) => ({
      deviceId: row.device_id,
      deviceKind: row.device_kind,
      deviceName: row.device_name,
      platform: row.platform,
      model: row.model,
      browserName: row.browser_name,
      browserVersion: row.browser_version,
      tabs: parseTabs(row.tabs_json),
      tabCount: parseTabs(row.tabs_json).length,
      updatedAt: Number(row.updated_at || 0),
      expiresAt: Number(row.expires_at || 0),
      freshnessMs: Math.max(0, now - Number(row.updated_at || 0)),
    })),
  };
}

function clear(device) {
  return { deviceId: device.deviceId, removed: deleteSnapshot.run(device.deviceId).changes > 0 };
}

function cleanup(now) {
  deleteExpiredSnapshots.run(now - PHYSICAL_RETENTION_MS);
}

function normalizeDevice(value, authenticated) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(400, 'invalid_cross_device_tabs_device', 'Device metadata is invalid.');
  }
  if (String(value.deviceId || '').trim() !== authenticated.deviceId) {
    fail(400, 'cross_device_tabs_device_mismatch', 'Device metadata does not match the credential.');
  }
  return {
    deviceName: optionalString(value.deviceName || authenticated.name, 120),
    platform: optionalString(value.platform, 80),
    model: optionalString(value.model, 120),
    browserName: optionalString(value.browserName, 80),
    browserVersion: optionalString(value.browserVersion, 64),
  };
}

function normalizeTabs(value, now) {
  if (!Array.isArray(value) || value.length > MAX_TABS) {
    fail(400, 'invalid_cross_device_tabs', `A device may publish at most ${MAX_TABS} tabs.`);
  }
  return value.map((raw, index) => normalizeTab(raw, index, now)).sort(compareTabs);
}

function normalizeTab(value, fallbackOrder, now) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(400, 'invalid_cross_device_tab', 'Tab metadata is invalid.');
  }
  return {
    title: optionalString(value.title, 512),
    url: normalizeHttpUrl(value.url),
    active: value.active === true,
    lastActiveAt: normalizeTimestamp(value.lastActiveAt, now),
    windowOrder: normalizeOrder(value.windowOrder, fallbackOrder),
    tabOrder: normalizeOrder(value.tabOrder, fallbackOrder),
  };
}

function compareTabs(left, right) {
  if (left.active !== right.active) return left.active ? -1 : 1;
  if (left.lastActiveAt !== right.lastActiveAt) return right.lastActiveAt - left.lastActiveAt;
  if (left.windowOrder !== right.windowOrder) return left.windowOrder - right.windowOrder;
  return left.tabOrder - right.tabOrder;
}

function normalizeHttpUrl(value) {
  try {
    const url = new URL(String(value || '').trim());
    if ((url.protocol !== 'http:' && url.protocol !== 'https:') || url.username || url.password) throw new Error();
    return url.toString();
  } catch (_error) {
    fail(400, 'invalid_cross_device_tab_url', 'Only HTTP(S) tab URLs without embedded credentials are supported.');
  }
}

function normalizeTimestamp(value, now) {
  if (value === undefined || value === null || value === '') return 0;
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0 || number > now + MAX_FUTURE_SKEW_MS) {
    fail(400, 'invalid_cross_device_tab_timestamp', 'Tab activity timestamp is invalid.');
  }
  return number;
}

function normalizeOrder(value, fallback) {
  if (value === undefined || value === null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0 || number > 100000) {
    fail(400, 'invalid_cross_device_tab_order', 'Tab order is invalid.');
  }
  return number;
}

function optionalString(value, maxLength) {
  const normalized = String(value || '').trim();
  if (normalized.length > maxLength) fail(400, 'cross_device_tabs_field_too_long', 'A metadata field is too long.');
  return normalized;
}

function parseTabs(value) {
  try {
    const tabs = JSON.parse(value);
    return Array.isArray(tabs) ? tabs : [];
  } catch (_error) {
    fail(500, 'stored_state_invalid', 'Stored tab state is invalid. Restore a valid backup.');
  }
}

module.exports = { clear, list, publish };
