const crypto = require('crypto');
const { db } = require('./db/database');
const { fail } = require('./errors');

const TASK_TTL_MS = 2 * 60 * 1000;
const LEASE_MS = 2 * 60 * 1000;
const ONLINE_WINDOW_MS = 2 * 60 * 1000;
const PHYSICAL_RETENTION_MS = 14 * 24 * 60 * 60 * 1000;
const MAX_PENDING_TASKS = 100;
const MAX_ENQUEUE_PER_MINUTE = 30;
const MAX_LONG_POLL_MS = 20 * 1000;
const EMPTY_REPOLL_MS = 500;
const waiters = new Map();

const listOnlineDesktops = db.prepare(`
  SELECT devices.device_id FROM devices
  INNER JOIN page_push_device_presence_v1 AS presence
    ON presence.device_id = devices.device_id
  WHERE devices.device_kind = 'desktop' AND devices.revoked_at = 0 AND presence.last_poll_at >= ?
  ORDER BY devices.created_at ASC, devices.device_id ASC
`);
const upsertPresence = db.prepare(`
  INSERT INTO page_push_device_presence_v1(device_id, last_poll_at) VALUES(?, ?)
  ON CONFLICT(device_id) DO UPDATE SET last_poll_at = excluded.last_poll_at
`);
const countPending = db.prepare(`
  SELECT COUNT(*) AS count FROM page_push_tasks_v1
  WHERE status IN ('queued', 'leased') AND expires_at > ?
`);
const countRecent = db.prepare('SELECT COUNT(*) AS count FROM page_push_tasks_v1 WHERE created_at >= ?');
const insertTask = db.prepare(`
  INSERT INTO page_push_tasks_v1(
    task_id, target_device_id, source_device_id, url, original_url, desktop_url, title,
    status, created_at, updated_at, expires_at
  ) VALUES(
    @task_id, @target_device_id, @source_device_id, @url, @original_url, @desktop_url, @title,
    'queued', @created_at, @created_at, @expires_at
  )
`);
const selectClaimable = db.prepare(`
  SELECT * FROM page_push_tasks_v1
  WHERE target_device_id = ? AND expires_at > ? AND (
    status = 'queued' OR (status = 'leased' AND lease_expires_at <= ?)
  )
  ORDER BY created_at ASC, task_id ASC LIMIT 1
`);
const leaseTask = db.prepare(`
  UPDATE page_push_tasks_v1 SET
    status = 'leased', updated_at = @now, leased_at = @now,
    lease_expires_at = @lease_expires_at, lease_token_hash = @lease_token_hash,
    delivered_at = CASE WHEN delivered_at = 0 THEN @now ELSE delivered_at END
  WHERE task_id = @task_id AND target_device_id = @target_device_id AND expires_at > @now AND (
    status = 'queued' OR (status = 'leased' AND lease_expires_at <= @now)
  )
`);
const getTask = db.prepare('SELECT * FROM page_push_tasks_v1 WHERE task_id = ?');
const ackTask = db.prepare(`
  UPDATE page_push_tasks_v1 SET
    status = @status, updated_at = @now, acked_at = @now,
    opened_at = CASE WHEN @status = 'opened' THEN @now ELSE opened_at END,
    last_error = @last_error
  WHERE task_id = @task_id AND target_device_id = @target_device_id
    AND status = 'leased' AND lease_token_hash = @lease_token_hash AND lease_expires_at > @now
`);
const expireTasks = db.prepare(`
  UPDATE page_push_tasks_v1 SET status = 'expired', updated_at = ?
  WHERE status IN ('queued', 'leased') AND expires_at <= ?
`);
const deleteOldTasks = db.prepare('DELETE FROM page_push_tasks_v1 WHERE created_at < ?');
const deleteOldPresence = db.prepare('DELETE FROM page_push_device_presence_v1 WHERE last_poll_at < ?');

function enqueue(body, device) {
  if (device.deviceKind !== 'phone') fail(403, 'page_push_phone_required', 'Only a paired phone may enqueue a page.');
  const now = Date.now();
  cleanup(now);
  const targets = listOnlineDesktops.all(now - ONLINE_WINDOW_MS);
  if (targets.length === 0) fail(409, 'no_online_desktop_device', 'No paired desktop is currently online.');
  if (Number(countPending.get(now).count) >= MAX_PENDING_TASKS) {
    fail(429, 'page_push_queue_full', 'The page queue is full.');
  }
  if (Number(countRecent.get(now - 60 * 1000).count) >= MAX_ENQUEUE_PER_MINUTE) {
    fail(429, 'page_push_rate_limited', 'Pages are being sent too frequently.');
  }
  const requestedUrl = normalizeHttpUrl(body.url);
  const originalUrl = normalizeOptionalHttpUrl(body.originalUrl) || requestedUrl;
  const desktopUrl = normalizeOptionalHttpUrl(body.desktopUrl);
  const url = desktopUrl || requestedUrl;
  const title = String(body.title || '').trim().slice(0, 240);
  const taskIds = [];
  db.transaction(() => {
    targets.forEach((target) => {
      const taskId = randomToken();
      taskIds.push(taskId);
      insertTask.run({
        task_id: taskId,
        target_device_id: target.device_id,
        source_device_id: device.deviceId,
        url,
        original_url: originalUrl,
        desktop_url: desktopUrl,
        title,
        created_at: now,
        expires_at: now + TASK_TTL_MS,
      });
    });
  })();
  targets.forEach((target) => wake(target.device_id));
  return {
    taskId: taskIds[0],
    status: 'queued',
    deliveryCount: taskIds.length,
    createdAt: now,
    expiresAt: now + TASK_TTL_MS,
  };
}

async function poll(body, device) {
  if (device.deviceKind !== 'desktop') fail(403, 'page_push_desktop_required', 'Only a paired desktop may poll pages.');
  const pollStartedAt = Date.now();
  upsertPresence.run(device.deviceId, pollStartedAt);
  let result = claim(device.deviceId, pollStartedAt);
  const waitMs = normalizeWait(body.waitMs);
  if (!result && waitMs > 0) {
    await wait(device.deviceId, waitMs);
    result = claim(device.deviceId, Date.now());
  }
  return result || { task: null, nextPollAfterMs: EMPTY_REPOLL_MS };
}

function acknowledge(body, device) {
  if (device.deviceKind !== 'desktop') fail(403, 'page_push_desktop_required', 'Only a paired desktop may acknowledge pages.');
  const taskId = requiredString(body.taskId, 'missing_task_id', 'Task ID is required.');
  const leaseToken = requiredString(body.leaseToken, 'missing_lease_token', 'Lease token is required.');
  const status = String(body.status || 'opened').trim();
  if (status !== 'opened' && status !== 'failed') {
    fail(400, 'invalid_page_push_ack_status', 'Acknowledgement status must be opened or failed.');
  }
  const now = Date.now();
  const row = getTask.get(taskId);
  if (!row || row.target_device_id !== device.deviceId) fail(404, 'page_push_not_found', 'Page task was not found.');
  const changed = ackTask.run({
    task_id: taskId,
    target_device_id: device.deviceId,
    lease_token_hash: hash(leaseToken),
    status,
    last_error: String(body.error || '').trim().slice(0, 512),
    now,
  }).changes;
  if (changed !== 1) fail(409, 'page_push_invalid_lease', 'Page task lease is invalid or expired.');
  return { taskId, status, ackedAt: now };
}

function claim(deviceId, now) {
  cleanup(now);
  const row = selectClaimable.get(deviceId, now, now);
  if (!row) return null;
  const leaseToken = randomToken();
  const leaseExpiresAt = now + LEASE_MS;
  if (leaseTask.run({
    task_id: row.task_id,
    target_device_id: deviceId,
    lease_token_hash: hash(leaseToken),
    lease_expires_at: leaseExpiresAt,
    now,
  }).changes !== 1) return null;
  return {
    task: toTask({ ...row, status: 'leased', leased_at: now, lease_expires_at: leaseExpiresAt }),
    leaseToken,
    leaseExpiresAt,
    nextPollAfterMs: EMPTY_REPOLL_MS,
  };
}

function cleanup(now) {
  expireTasks.run(now, now);
  deleteOldTasks.run(now - PHYSICAL_RETENTION_MS);
  deleteOldPresence.run(now - PHYSICAL_RETENTION_MS);
}

function toTask(row) {
  return {
    taskId: row.task_id,
    url: row.url,
    originalUrl: row.original_url,
    desktopUrl: row.desktop_url,
    title: row.title,
    status: row.status,
    createdAt: Number(row.created_at || 0),
    updatedAt: Number(row.updated_at || 0),
    expiresAt: Number(row.expires_at || 0),
    leasedAt: Number(row.leased_at || 0),
    leaseExpiresAt: Number(row.lease_expires_at || 0),
    deliveredAt: Number(row.delivered_at || 0),
    ackedAt: Number(row.acked_at || 0),
    openedAt: Number(row.opened_at || 0),
  };
}

function wait(deviceId, waitMs) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      if (waiters.get(deviceId) === entry) waiters.delete(deviceId);
      resolve();
    }, waitMs);
    const entry = { resolve, timer };
    const previous = waiters.get(deviceId);
    if (previous) {
      clearTimeout(previous.timer);
      previous.resolve();
    }
    waiters.set(deviceId, entry);
  });
}

function wake(deviceId) {
  const entry = waiters.get(deviceId);
  if (!entry) return;
  waiters.delete(deviceId);
  clearTimeout(entry.timer);
  entry.resolve();
}

function normalizeWait(value) {
  const number = Number(value || 0);
  if (!Number.isFinite(number) || number <= 0) return 0;
  return Math.min(MAX_LONG_POLL_MS, Math.floor(number));
}

function normalizeHttpUrl(value) {
  const result = normalizeOptionalHttpUrl(value);
  if (!result) fail(400, 'invalid_page_url', 'Only HTTP(S) page URLs are supported.');
  return result;
}

function normalizeOptionalHttpUrl(value) {
  try {
    const url = new URL(String(value || '').trim());
    if ((url.protocol !== 'http:' && url.protocol !== 'https:') || url.username || url.password) return '';
    return url.toString();
  } catch (_error) {
    return '';
  }
}

function requiredString(value, code, message) {
  const normalized = String(value || '').trim();
  if (!normalized) fail(400, code, message);
  return normalized;
}

function randomToken() {
  return crypto.randomBytes(18).toString('base64url');
}

function hash(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

module.exports = { acknowledge, enqueue, poll };
