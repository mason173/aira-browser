CREATE TABLE instance_meta (
  singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
  instance_id TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);

CREATE TABLE pairing_codes (
  code_hash TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  created_by_device_id TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE devices (
  device_id TEXT PRIMARY KEY,
  credential_id TEXT NOT NULL UNIQUE,
  token_hash TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  rotated_at INTEGER NOT NULL DEFAULT 0,
  revoked_at INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX devices_active_token ON devices(token_hash, revoked_at);

CREATE TABLE bookmark_state (
  singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
  commit_id TEXT NOT NULL,
  parent_commit_id TEXT NOT NULL DEFAULT '',
  snapshot_json TEXT NOT NULL,
  history_json TEXT NOT NULL,
  device_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE snapshot_states (
  domain TEXT PRIMARY KEY,
  revision INTEGER NOT NULL,
  snapshot_json TEXT NOT NULL,
  device_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE history_sync_heads_v1 (
  uid TEXT PRIMARY KEY,
  head_seq INTEGER NOT NULL DEFAULT 0,
  clear_before INTEGER NOT NULL DEFAULT 0,
  clear_before_seq INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE history_sync_entities_v1 (
  uid TEXT NOT NULL,
  visit_id TEXT NOT NULL,
  client_id TEXT NOT NULL DEFAULT '',
  native_visit_id TEXT NOT NULL DEFAULT '',
  url TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL DEFAULT '',
  visited_at INTEGER NOT NULL DEFAULT 0,
  transition TEXT NOT NULL DEFAULT '',
  referrer TEXT NOT NULL DEFAULT '',
  device_name TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT '',
  deleted INTEGER NOT NULL DEFAULT 0,
  deletion_kind TEXT NOT NULL DEFAULT '',
  deleted_at INTEGER NOT NULL DEFAULT 0,
  updated_seq INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(uid, visit_id)
);

CREATE INDEX history_entities_timeline ON history_sync_entities_v1(uid, deleted, visited_at DESC, visit_id DESC);
CREATE INDEX history_entities_updated ON history_sync_entities_v1(uid, updated_seq);

CREATE TABLE history_sync_delete_ranges_v1 (
  uid TEXT NOT NULL,
  range_id TEXT NOT NULL,
  url TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER NOT NULL,
  created_seq INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(uid, range_id)
);

CREATE INDEX history_ranges_match ON history_sync_delete_ranges_v1(uid, url, started_at, ended_at);

CREATE TABLE history_sync_changes_v1 (
  uid TEXT NOT NULL,
  seq INTEGER NOT NULL,
  kind TEXT NOT NULL,
  visit_id TEXT NOT NULL DEFAULT '',
  payload_json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(uid, seq)
);

CREATE INDEX history_changes_created ON history_sync_changes_v1(uid, created_at, seq);

CREATE TABLE history_sync_clients_v1 (
  uid TEXT NOT NULL,
  client_id TEXT NOT NULL,
  cursor INTEGER NOT NULL DEFAULT 0,
  last_seen_at INTEGER NOT NULL DEFAULT 0,
  expires_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(uid, client_id)
);

CREATE INDEX history_clients_lease ON history_sync_clients_v1(uid, expires_at, cursor);

CREATE TABLE history_sync_mutation_receipts_v1 (
  uid TEXT NOT NULL,
  client_id TEXT NOT NULL,
  mutation_id TEXT NOT NULL,
  accepted_seq INTEGER NOT NULL DEFAULT 0,
  applied INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(uid, client_id, mutation_id)
);

CREATE INDEX history_receipts_created ON history_sync_mutation_receipts_v1(created_at);

