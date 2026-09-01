ALTER TABLE devices ADD COLUMN device_kind TEXT NOT NULL DEFAULT 'phone';

CREATE TABLE page_push_tasks_v1 (
  task_id TEXT PRIMARY KEY,
  target_device_id TEXT NOT NULL,
  source_device_id TEXT NOT NULL,
  url TEXT NOT NULL,
  original_url TEXT NOT NULL,
  desktop_url TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'queued',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  leased_at INTEGER NOT NULL DEFAULT 0,
  lease_expires_at INTEGER NOT NULL DEFAULT 0,
  lease_token_hash TEXT NOT NULL DEFAULT '',
  delivered_at INTEGER NOT NULL DEFAULT 0,
  acked_at INTEGER NOT NULL DEFAULT 0,
  opened_at INTEGER NOT NULL DEFAULT 0,
  last_error TEXT NOT NULL DEFAULT ''
);

CREATE INDEX page_push_tasks_target_queue_v1
  ON page_push_tasks_v1(target_device_id, status, expires_at, created_at);
CREATE INDEX page_push_tasks_created_v1 ON page_push_tasks_v1(created_at);

CREATE TABLE page_push_device_presence_v1 (
  device_id TEXT PRIMARY KEY,
  last_poll_at INTEGER NOT NULL
);

CREATE INDEX page_push_device_presence_last_poll_v1
  ON page_push_device_presence_v1(last_poll_at);

CREATE TABLE cross_device_tab_snapshots_v1 (
  device_id TEXT PRIMARY KEY,
  device_kind TEXT NOT NULL,
  device_name TEXT NOT NULL DEFAULT '',
  platform TEXT NOT NULL DEFAULT '',
  model TEXT NOT NULL DEFAULT '',
  browser_name TEXT NOT NULL DEFAULT '',
  browser_version TEXT NOT NULL DEFAULT '',
  tabs_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX cross_device_tabs_online_v1
  ON cross_device_tab_snapshots_v1(device_kind, expires_at, updated_at);
