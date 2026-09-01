const crypto = require('crypto');
const { db } = require('./db/database');
const { fail } = require('./errors');

const getBookmark = db.prepare('SELECT * FROM bookmark_state WHERE singleton = 1');
const upsertBookmark = db.prepare(`
  INSERT INTO bookmark_state(
    singleton, commit_id, parent_commit_id, snapshot_json, history_json, device_id, created_at, updated_at
  ) VALUES(1, @commit_id, @parent_commit_id, @snapshot_json, @history_json, @device_id, @created_at, @updated_at)
  ON CONFLICT(singleton) DO UPDATE SET
    commit_id = excluded.commit_id,
    parent_commit_id = excluded.parent_commit_id,
    snapshot_json = excluded.snapshot_json,
    history_json = excluded.history_json,
    device_id = excluded.device_id,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at
`);
const getSnapshot = db.prepare('SELECT * FROM snapshot_states WHERE domain = ?');
const upsertSnapshot = db.prepare(`
  INSERT INTO snapshot_states(domain, revision, snapshot_json, device_id, created_at, updated_at)
  VALUES(@domain, @revision, @snapshot_json, @device_id, @created_at, @updated_at)
  ON CONFLICT(domain) DO UPDATE SET
    revision = excluded.revision,
    snapshot_json = excluded.snapshot_json,
    device_id = excluded.device_id,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at
`);

function readBookmark() {
  const row = getBookmark.get();
  if (!row) return { snapshot: null, history: null, commitId: null, updatedAt: 0 };
  return {
    snapshot: parseStored(row.snapshot_json),
    history: parseStored(row.history_json),
    commitId: row.commit_id,
    updatedAt: row.updated_at,
  };
}

function readBookmarkHead() {
  const state = readBookmark();
  const folders = state.snapshot && Array.isArray(state.snapshot.bookmarkFolders)
    ? state.snapshot.bookmarkFolders.length : 0;
  const items = state.snapshot && Array.isArray(state.snapshot.bookmarkItems)
    ? state.snapshot.bookmarkItems.length : 0;
  return { commitId: state.commitId, updatedAt: state.updatedAt, bookmarkFolders: folders, bookmarkItems: items };
}

function writeBookmark(body, device) {
  const snapshot = requireObject(body.snapshot, 'invalid_bookmark_snapshot');
  const history = requireObject(body.history, 'invalid_bookmark_history');
  const current = getBookmark.get();
  const expected = body.parentCommitId === null || body.parentCommitId === undefined
    ? '' : String(body.parentCommitId).trim();
  const actual = current ? current.commit_id : '';
  if (expected !== actual) fail(409, 'sync_conflict', 'Remote bookmarks changed; read before writing again.');
  const snapshotJson = JSON.stringify(snapshot);
  const historyJson = JSON.stringify(history);
  if (Buffer.byteLength(snapshotJson) > 10 * 1024 * 1024) {
    fail(413, 'bookmark_snapshot_too_large', 'Bookmark snapshot exceeds 10 MiB.');
  }
  const now = Date.now();
  const createdAt = String(body.createdAt || snapshot.meta && snapshot.meta.generatedAt || new Date(now).toISOString());
  const commitId = `cmt_${now.toString(36)}_${crypto.randomBytes(8).toString('hex')}`;
  upsertBookmark.run({
    commit_id: commitId,
    parent_commit_id: actual,
    snapshot_json: snapshotJson,
    history_json: historyJson,
    device_id: device.deviceId,
    created_at: createdAt,
    updated_at: now,
  });
  return { commitId, writtenAt: createdAt, updatedAt: now };
}

function readSnapshot(domain) {
  const row = getSnapshot.get(domain);
  if (!row) return { snapshot: null, revision: '', updatedAt: 0 };
  return { snapshot: parseStored(row.snapshot_json), revision: String(row.revision), updatedAt: row.updated_at };
}

function writeSnapshot(domain, body, device) {
  const snapshot = requireObject(body.snapshot, `invalid_${domain}_snapshot`);
  const current = getSnapshot.get(domain);
  const actualRevision = current ? Number(current.revision) : 0;
  const expectedRevision = normalizeRevision(body.expectedRevision);
  if (expectedRevision !== actualRevision) {
    fail(409, `${domain}_sync_write_conflict`, `${domain} snapshot changed; read before writing again.`);
  }
  const snapshotJson = JSON.stringify(snapshot);
  const limit = domain === 'novel_bookshelf' ? 1024 * 1024 : 4 * 1024 * 1024;
  if (Buffer.byteLength(snapshotJson) > limit) fail(413, `${domain}_snapshot_too_large`, 'Snapshot is too large.');
  const now = Date.now();
  const createdAt = String(snapshot.meta && snapshot.meta.generatedAt || new Date(now).toISOString());
  const revision = actualRevision + 1;
  upsertSnapshot.run({
    domain,
    revision,
    snapshot_json: snapshotJson,
    device_id: device.deviceId,
    created_at: createdAt,
    updated_at: now,
  });
  return { revision: String(revision), writtenAt: createdAt, updatedAt: now };
}

function requireObject(value, code) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(400, code, 'Snapshot must be a JSON object.');
  }
  return value;
}

function normalizeRevision(value) {
  const number = Number(String(value || '').trim() || 0);
  if (!Number.isSafeInteger(number) || number < 0) fail(400, 'invalid_revision', 'Revision is invalid.');
  return number;
}

function parseStored(value) {
  try {
    return JSON.parse(value);
  } catch (_error) {
    fail(500, 'stored_state_invalid', 'Stored state is invalid. Restore a valid backup.');
  }
}

module.exports = { readBookmark, readBookmarkHead, readSnapshot, writeBookmark, writeSnapshot };

