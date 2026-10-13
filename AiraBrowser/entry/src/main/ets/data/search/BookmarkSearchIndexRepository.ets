import { relationalStore } from '@kit.ArkData';
import { BookmarkStorageScope } from '../../common/models/BrowserModels';
import {
  BookmarkSearchIndexSnapshot, BookmarkSearchIndexSource, BookmarkSearchIndexStore, BookmarkSearchRecord
} from '../../common/models/BookmarkSearchIndexModels';

const REVISION_TABLE: string = 'bookmark_search_revision';
const CACHE_TABLE: string = 'bookmark_search_cache';
const CHUNK_TABLE: string = 'bookmark_search_chunks';
const INDEX_FORMAT: number = 1;
const SOURCE_BATCH_SIZE: number = 250;
const MAX_CHUNK_LENGTH: number = 32000;

// Installed on first use, which is the launch prewarm or the first explicit search. Triggers
// observe every writer, including sync/import, and persist the revision in the same
// transaction as the canonical bookmark change.
export const BOOKMARK_SEARCH_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${REVISION_TABLE} (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL)`,
  `INSERT OR IGNORE INTO ${REVISION_TABLE}(id, revision) VALUES(1, 0)`,
  `CREATE TABLE IF NOT EXISTS ${CACHE_TABLE} (
    scope TEXT PRIMARY KEY, revision TEXT NOT NULL, format INTEGER NOT NULL,
    snapshot_id TEXT NOT NULL, part_count INTEGER NOT NULL, checksum TEXT NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS ${CHUNK_TABLE} (
    scope TEXT NOT NULL, snapshot_id TEXT NOT NULL, part_no INTEGER NOT NULL, payload TEXT NOT NULL,
    PRIMARY KEY(scope, snapshot_id, part_no))`,
  `CREATE TRIGGER IF NOT EXISTS bookmark_search_nodes_insert AFTER INSERT ON bookmark_nodes
    BEGIN UPDATE ${REVISION_TABLE} SET revision = revision + 1 WHERE id = 1; END`,
  `CREATE TRIGGER IF NOT EXISTS bookmark_search_nodes_delete AFTER DELETE ON bookmark_nodes
    BEGIN UPDATE ${REVISION_TABLE} SET revision = revision + 1 WHERE id = 1; END`,
  `CREATE TRIGGER IF NOT EXISTS bookmark_search_nodes_update
    AFTER UPDATE OF id, scope, type, title, url, sync_source, deleted_at ON bookmark_nodes
    WHEN OLD.id IS NOT NEW.id OR OLD.scope IS NOT NEW.scope OR OLD.type IS NOT NEW.type
      OR OLD.title IS NOT NEW.title OR OLD.url IS NOT NEW.url
      OR OLD.sync_source IS NOT NEW.sync_source OR OLD.deleted_at IS NOT NEW.deleted_at
    BEGIN UPDATE ${REVISION_TABLE} SET revision = revision + 1 WHERE id = 1; END`,
  `CREATE TRIGGER IF NOT EXISTS bookmark_search_orders_insert AFTER INSERT ON bookmark_orders
    BEGIN UPDATE ${REVISION_TABLE} SET revision = revision + 1 WHERE id = 1; END`,
  `CREATE TRIGGER IF NOT EXISTS bookmark_search_orders_delete AFTER DELETE ON bookmark_orders
    BEGIN UPDATE ${REVISION_TABLE} SET revision = revision + 1 WHERE id = 1; END`,
  `CREATE TRIGGER IF NOT EXISTS bookmark_search_orders_update AFTER UPDATE ON bookmark_orders
    WHEN OLD.child_id IS NOT NEW.child_id OR OLD.parent_id IS NOT NEW.parent_id OR OLD.position IS NOT NEW.position
    BEGIN UPDATE ${REVISION_TABLE} SET revision = revision + 1 WHERE id = 1; END`
];

interface BookmarkSearchCacheHeader {
  revision: string;
  snapshotId: string;
  partCount: number;
  checksum: string;
}

export class BookmarkSearchIndexRepository implements BookmarkSearchIndexStore {
  private readonly resolveStore: () => Promise<relationalStore.RdbStore>;
  private schemaPromise?: Promise<relationalStore.RdbStore>;
  private writeTail: Promise<void> = Promise.resolve();
  private sequence: number = 0;

  constructor(resolveStore: () => Promise<relationalStore.RdbStore>) {
    this.resolveStore = resolveStore;
  }

  async readRevision(): Promise<string> {
    const store = await this.getStore();
    const rows = await store.querySql(`SELECT CAST(revision AS TEXT) AS revision FROM ${REVISION_TABLE} WHERE id = 1`);
    try {
      if (!rows.goToFirstRow()) {
        throw new Error('Bookmark search revision unavailable');
      }
      return rows.getString(0);
    } finally {
      rows.close();
    }
  }

  async load(scope: BookmarkStorageScope): Promise<BookmarkSearchIndexSnapshot | undefined> {
    const store = await this.getStore();
    const header = await this.readHeader(store, scope, true);
    if (header === undefined || header.partCount < 1) {
      return undefined;
    }
    const chunks: string[] = [];
    // One bounded TEXT value per cursor window; never store a multi-MB JSON row.
    for (let part = 0; part < header.partCount; part += 1) {
      const rows = await store.querySql(
        `SELECT payload FROM ${CHUNK_TABLE} WHERE scope = ? AND snapshot_id = ? AND part_no = ?`,
        [scope, header.snapshotId, part]
      );
      try {
        if (!rows.goToFirstRow()) {
          return undefined;
        }
        const payload = rows.getString(0);
        if (payload.length > MAX_CHUNK_LENGTH) {
          return undefined;
        }
        chunks.push(payload);
      } finally {
        rows.close();
      }
    }
    if (checksumBookmarkSearchChunks(chunks) !== header.checksum || await this.readRevision() !== header.revision) {
      return undefined;
    }
    return { revision: header.revision, chunks: chunks };
  }

  async readSource(scope: BookmarkStorageScope): Promise<BookmarkSearchIndexSource | undefined> {
    const store = await this.getStore();
    const revision = await this.readRevision();
    const records: BookmarkSearchRecord[] = [];
    for (let offset = 0; ; offset += SOURCE_BATCH_SIZE) {
      const rows = await store.querySql(`SELECT n.id, n.title, n.url FROM bookmark_nodes n
        LEFT JOIN bookmark_orders o ON o.child_id = n.id
        WHERE COALESCE(n.scope, 'regular') = ? AND n.type = 'bookmark' AND n.deleted_at IS NULL
          AND COALESCE(n.sync_source, '') <> 'seed' AND LENGTH(TRIM(COALESCE(n.url, ''))) > 0
        ORDER BY COALESCE(o.parent_id, ''), COALESCE(o.position, 0), n.id LIMIT ? OFFSET ?`,
        [scope, SOURCE_BATCH_SIZE, offset]);
      let count = 0;
      try {
        while (rows.goToNextRow()) {
          records.push({ id: rows.getString(0), title: rows.getString(1), url: rows.getString(2) });
          count += 1;
        }
      } finally {
        rows.close();
      }
      if (count < SOURCE_BATCH_SIZE) {
        break;
      }
      await pauseBookmarkSearchStorage();
    }
    return await this.readRevision() === revision ? { revision: revision, records: records } : undefined;
  }

  save(scope: BookmarkStorageScope, revision: string, chunks: string[]): Promise<boolean> {
    const operation = this.writeTail.then(() => this.writeSnapshot(scope, revision, chunks));
    this.writeTail = operation.then(() => {}, (_error: Error) => {});
    return operation;
  }

  private async writeSnapshot(scope: BookmarkStorageScope, revision: string, chunks: string[]): Promise<boolean> {
    if (chunks.length === 0 || chunks.some((chunk: string): boolean => chunk.length > MAX_CHUNK_LENGTH)) {
      return false;
    }
    const store = await this.getStore();
    if (await this.readRevision() !== revision) {
      return false;
    }
    const old = await this.readHeader(store, scope, false);
    const snapshotId = `${Date.now()}-${++this.sequence}`;
    let published = false;
    try {
      for (let part = 0; part < chunks.length; part += 1) {
        await store.executeSql(
          `INSERT INTO ${CHUNK_TABLE}(scope, snapshot_id, part_no, payload) VALUES(?, ?, ?, ?)`,
          [scope, snapshotId, part, chunks[part]]
        );
      }
      // Atomic publication only while the source revision still matches. No shared-store transaction.
      await store.executeSql(`INSERT OR REPLACE INTO ${CACHE_TABLE}
        (scope, revision, format, snapshot_id, part_count, checksum)
        SELECT ?, CAST(revision AS TEXT), ?, ?, ?, ? FROM ${REVISION_TABLE}
        WHERE id = 1 AND CAST(revision AS TEXT) = ?`,
        [scope, INDEX_FORMAT, snapshotId, chunks.length, checksumBookmarkSearchChunks(chunks), revision]);
      const current = await this.readHeader(store, scope, false);
      published = current?.snapshotId === snapshotId;
      if (published && old !== undefined && old.snapshotId !== snapshotId) {
        await this.deleteChunks(store, scope, old.snapshotId);
      }
      return published;
    } finally {
      if (!published) {
        await this.deleteChunks(store, scope, snapshotId);
      }
    }
  }

  private async deleteChunks(store: relationalStore.RdbStore, scope: BookmarkStorageScope, snapshotId: string): Promise<void> {
    await store.executeSql(`DELETE FROM ${CHUNK_TABLE} WHERE scope = ? AND snapshot_id = ?`, [scope, snapshotId]);
  }

  private async readHeader(
    store: relationalStore.RdbStore, scope: BookmarkStorageScope, requireCurrent: boolean
  ): Promise<BookmarkSearchCacheHeader | undefined> {
    const rows = await store.querySql(`SELECT c.revision, c.snapshot_id, c.part_count, c.checksum FROM ${CACHE_TABLE} c
      WHERE c.scope = ? AND c.format = ? ${requireCurrent ?
        `AND c.revision = (SELECT CAST(revision AS TEXT) FROM ${REVISION_TABLE} WHERE id = 1)` : ''}`,
      [scope, INDEX_FORMAT]);
    try {
      return rows.goToFirstRow() ? {
        revision: rows.getString(0), snapshotId: rows.getString(1), partCount: rows.getLong(2), checksum: rows.getString(3)
      } : undefined;
    } finally {
      rows.close();
    }
  }

  private getStore(): Promise<relationalStore.RdbStore> {
    if (this.schemaPromise === undefined) {
      this.schemaPromise = this.resolveStore().then(async (store: relationalStore.RdbStore) => {
        for (let index = 0; index < BOOKMARK_SEARCH_SCHEMA_SQL.length; index += 1) {
          await store.executeSql(BOOKMARK_SEARCH_SCHEMA_SQL[index]);
        }
        return store;
      }).catch((error: Error) => {
        this.schemaPromise = undefined;
        throw error;
      });
    }
    return this.schemaPromise;
  }
}

function checksumBookmarkSearchChunks(chunks: string[]): string {
  let hash = 2166136261;
  for (let part = 0; part < chunks.length; part += 1) {
    const chunk = chunks[part];
    for (let offset = 0; offset < chunk.length; offset += 1) {
      hash = Math.imul(hash ^ chunk.charCodeAt(offset), 16777619) >>> 0;
    }
    hash = Math.imul(hash ^ 0xffff, 16777619) >>> 0;
  }
  return hash.toString(16);
}

function pauseBookmarkSearchStorage(): Promise<void> {
  return new Promise<void>((resolve: () => void) => { setTimeout(resolve, 0); });
}
