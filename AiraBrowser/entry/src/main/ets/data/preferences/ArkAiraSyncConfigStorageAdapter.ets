import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AIRA_BOOKMARK_HISTORY_VERSION,
  AiraBookmarkHistoryDescriptor,
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkItemEntity,
  AiraSyncBaselineRecord,
  AiraSyncBookmarkOrder,
  AiraSyncSettings,
  AiraSyncSnapshot,
  AiraSyncSnapshotMeta,
  AiraSyncTombstone
} from '../../common/models/AiraSyncModels';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  createDefaultAiraSyncSettings,
  AiraSyncConfigStorageAdapter
} from '../../services/sync/AiraSyncConfigStore';

const PREFERENCES_NAME = 'aira_aira_sync_config_g2';
const SETTINGS_KEY = 'settings';
const BASELINE_PREFIX = 'baseline_';
const BASELINE_CHUNK_YIELD_MS = 0;
const BASELINE_SLOW_FLUSH_WARN_MS = 50;
const BASELINE_STRUCTURED_MANIFEST_SUFFIX = '__structured_manifest';
const BASELINE_STRUCTURED_PART_PREFIX_SUFFIX = '__structured_part_';
const BASELINE_STRUCTURED_VERSION = 3;
const BASELINE_STRUCTURED_ARRAY_ITEM_LIMIT = 64;
const DOMAIN = 0x0000;
const TAG = 'ArkAiraSyncConfigStorageAdapter';

interface AiraStructuredBaselineManifest {
  version: number;
  generation: string;
  commitId: string;
  updatedAt: number;
  hasSnapshot: boolean;
  history: AiraBookmarkHistoryDescriptor;
  snapshotMeta?: AiraSyncSnapshotMeta;
  folderPartCount: number;
  itemPartCount: number;
  orderPartCount: number;
  tombstonePartCount: number;
  privateFolderPartCount?: number;
  privateItemPartCount?: number;
  privateOrderPartCount?: number;
  privateTombstonePartCount?: number;
}

type AiraStructuredBaselinePartKind =
  'folders' |
  'items' |
  'orders' |
  'tombstones' |
  'private-folders' |
  'private-items' |
  'private-orders' |
  'private-tombstones';

interface AiraStructuredWriteResult {
  partCount: number;
  payloadLength: number;
}

export class ArkAiraSyncConfigStorageAdapter implements AiraSyncConfigStorageAdapter {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private baselineCache: Map<string, AiraSyncBaselineRecord | null> = new Map<string, AiraSyncBaselineRecord | null>();

  async readSettings(defaultValue: AiraSyncSettings): Promise<AiraSyncSettings> {
    const store = await this.getStore();
    const payload = String(store.getSync(SETTINGS_KEY, ''));
    if (payload.length === 0) {
      return defaultValue;
    }
    try {
      return JSON.parse(payload) as AiraSyncSettings;
    } catch (_error) {
      return createDefaultAiraSyncSettings();
    }
  }

  async writeSettings(settings: AiraSyncSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(SETTINGS_KEY, JSON.stringify(settings));
    await store.flush();
  }

  async readBaseline(providerId: string): Promise<AiraSyncBaselineRecord | undefined> {
    if (this.baselineCache.has(providerId)) {
      const cached = this.baselineCache.get(providerId);
      return cached === null ? undefined : cached;
    }
    const store = await this.getStore();
    const structuredRecord = await this.readStructuredBaselineRecord(store, providerId);
    if (structuredRecord !== undefined) {
      this.baselineCache.set(providerId, structuredRecord);
      return structuredRecord;
    }
    this.baselineCache.set(providerId, null);
    return undefined;
  }

  async writeBaseline(record: AiraSyncBaselineRecord): Promise<void> {
    const store = await this.getStore();
    const startedAt = Date.now();
    await this.yieldAfterBaselineChunk();
    const payloadLength = await this.writeStructuredBaselineRecord(store, record);
    await store.flush();
    this.baselineCache.set(record.providerId, record);
    this.logSlowBaselineFlushIfNeeded(record.providerId, startedAt, payloadLength);
  }

  private async readStructuredBaselineRecord(
    store: preferences.Preferences,
    providerId: string
  ): Promise<AiraSyncBaselineRecord | undefined> {
    const manifest = this.readStructuredManifest(store, providerId);
    if (manifest === undefined) {
      return undefined;
    }

    let snapshot: AiraSyncSnapshot | null = null;
    if (manifest.hasSnapshot) {
      const snapshotMeta = manifest.snapshotMeta;
      if (snapshotMeta === undefined) {
        return undefined;
      }
      const folders = await this.readStructuredArrayParts<AiraSyncBookmarkFolderEntity>(
        store,
        providerId,
        manifest.generation,
        'folders',
        manifest.folderPartCount
      );
      const items = await this.readStructuredArrayParts<AiraSyncBookmarkItemEntity>(
        store,
        providerId,
        manifest.generation,
        'items',
        manifest.itemPartCount
      );
      const orders = await this.readStructuredArrayParts<AiraSyncBookmarkOrder>(
        store,
        providerId,
        manifest.generation,
        'orders',
        manifest.orderPartCount
      );
      const tombstones = await this.readStructuredArrayParts<AiraSyncTombstone>(
        store,
        providerId,
        manifest.generation,
        'tombstones',
        manifest.tombstonePartCount
      );
      const privateFolders = await this.readStructuredArrayParts<AiraSyncBookmarkFolderEntity>(
        store,
        providerId,
        manifest.generation,
        'private-folders',
        manifest.privateFolderPartCount ?? 0
      );
      const privateItems = await this.readStructuredArrayParts<AiraSyncBookmarkItemEntity>(
        store,
        providerId,
        manifest.generation,
        'private-items',
        manifest.privateItemPartCount ?? 0
      );
      const privateOrders = await this.readStructuredArrayParts<AiraSyncBookmarkOrder>(
        store,
        providerId,
        manifest.generation,
        'private-orders',
        manifest.privateOrderPartCount ?? 0
      );
      const privateTombstones = await this.readStructuredArrayParts<AiraSyncTombstone>(
        store,
        providerId,
        manifest.generation,
        'private-tombstones',
        manifest.privateTombstonePartCount ?? 0
      );
      if (folders === undefined || items === undefined || orders === undefined || tombstones === undefined) {
        return undefined;
      }
      snapshot = {
        meta: snapshotMeta,
        bookmarkFolders: folders,
        bookmarkItems: items,
        bookmarkOrders: orders,
        tombstones: tombstones,
        appPrivateBookmarks: {
          bookmarkFolders: privateFolders ?? [],
          bookmarkItems: privateItems ?? [],
          bookmarkOrders: privateOrders ?? [],
          tombstones: privateTombstones ?? []
        }
      };
    }

    const record: AiraSyncBaselineRecord = {
      providerId,
      commitId: manifest.commitId,
      snapshot,
      history: manifest.history,
      updatedAt: manifest.updatedAt
    };
    return record;
  }

  private readStructuredManifest(
    store: preferences.Preferences,
    providerId: string
  ): AiraStructuredBaselineManifest | undefined {
    const payload = String(store.getSync(this.buildStructuredManifestKey(providerId), ''));
    if (payload.length === 0) {
      return undefined;
    }
    try {
      const manifest = JSON.parse(payload) as AiraStructuredBaselineManifest;
      if (!this.isStructuredManifestValid(manifest)) {
        return undefined;
      }
      return manifest;
    } catch (_error) {
      return undefined;
    }
  }

  private isStructuredManifestValid(manifest: AiraStructuredBaselineManifest): boolean {
    if (manifest.version !== BASELINE_STRUCTURED_VERSION) {
      return false;
    }
    if (typeof manifest.generation !== 'string' || manifest.generation.length === 0) {
      return false;
    }
    if (typeof manifest.commitId !== 'string') {
      return false;
    }
    if (!Number.isFinite(manifest.updatedAt) || manifest.updatedAt < 0) {
      return false;
    }
    if (typeof manifest.hasSnapshot !== 'boolean') {
      return false;
    }
    if (manifest.history === undefined || manifest.history === null ||
      manifest.history.version !== AIRA_BOOKMARK_HISTORY_VERSION ||
      typeof manifest.history.epochId !== 'string' || manifest.history.epochId.trim().length <= 0 ||
      typeof manifest.history.retainedFrom !== 'string' ||
      !Number.isFinite(Date.parse(manifest.history.retainedFrom))) {
      return false;
    }
    return this.isValidPartCount(manifest.folderPartCount) &&
      this.isValidPartCount(manifest.itemPartCount) &&
      this.isValidPartCount(manifest.orderPartCount) &&
      this.isValidPartCount(manifest.tombstonePartCount) &&
      this.isValidPartCount(manifest.privateFolderPartCount ?? 0) &&
      this.isValidPartCount(manifest.privateItemPartCount ?? 0) &&
      this.isValidPartCount(manifest.privateOrderPartCount ?? 0) &&
      this.isValidPartCount(manifest.privateTombstonePartCount ?? 0);
  }

  private isValidPartCount(value: number): boolean {
    return Number.isFinite(value) && value >= 0 && Math.floor(value) === value;
  }

  private async readStructuredArrayParts<T>(
    store: preferences.Preferences,
    providerId: string,
    generation: string,
    kind: AiraStructuredBaselinePartKind,
    partCount: number
  ): Promise<T[] | undefined> {
    const result: T[] = [];
    for (let index = 0; index < partCount; index += 1) {
      const payload = String(store.getSync(this.buildStructuredPartKey(providerId, generation, kind, index), ''));
      if (payload.length === 0) {
        return undefined;
      }
      try {
        const values = JSON.parse(payload) as T[];
        if (!Array.isArray(values)) {
          return undefined;
        }
        for (let valueIndex = 0; valueIndex < values.length; valueIndex += 1) {
          result.push(values[valueIndex]);
        }
      } catch (_error) {
        return undefined;
      }
      await this.yieldAfterBaselineChunk();
    }
    return result;
  }

  private async writeStructuredBaselineRecord(
    store: preferences.Preferences,
    record: AiraSyncBaselineRecord
  ): Promise<number> {
    const previousManifest = this.readStructuredManifest(store, record.providerId);
    const generation = this.buildBaselineGeneration();
    const snapshot = record.snapshot;
    let payloadLength = 0;
    let folderPartCount = 0;
    let itemPartCount = 0;
    let orderPartCount = 0;
    let tombstonePartCount = 0;
    let privateFolderPartCount = 0;
    let privateItemPartCount = 0;
    let privateOrderPartCount = 0;
    let privateTombstonePartCount = 0;

    if (snapshot !== null) {
      const folderResult = await this.writeStructuredArrayParts<AiraSyncBookmarkFolderEntity>(
        store,
        record.providerId,
        generation,
        'folders',
        snapshot.bookmarkFolders
      );
      folderPartCount = folderResult.partCount;
      payloadLength += folderResult.payloadLength;

      const itemResult = await this.writeStructuredArrayParts<AiraSyncBookmarkItemEntity>(
        store,
        record.providerId,
        generation,
        'items',
        snapshot.bookmarkItems
      );
      itemPartCount = itemResult.partCount;
      payloadLength += itemResult.payloadLength;

      const orderResult = await this.writeStructuredArrayParts<AiraSyncBookmarkOrder>(
        store,
        record.providerId,
        generation,
        'orders',
        snapshot.bookmarkOrders
      );
      orderPartCount = orderResult.partCount;
      payloadLength += orderResult.payloadLength;

      const tombstoneResult = await this.writeStructuredArrayParts<AiraSyncTombstone>(
        store,
        record.providerId,
        generation,
        'tombstones',
        snapshot.tombstones
      );
      tombstonePartCount = tombstoneResult.partCount;
      payloadLength += tombstoneResult.payloadLength;

      const privateDataSet = snapshot.appPrivateBookmarks;
      if (privateDataSet !== undefined) {
        const privateFolderResult = await this.writeStructuredArrayParts<AiraSyncBookmarkFolderEntity>(
          store,
          record.providerId,
          generation,
          'private-folders',
          privateDataSet.bookmarkFolders
        );
        privateFolderPartCount = privateFolderResult.partCount;
        payloadLength += privateFolderResult.payloadLength;

        const privateItemResult = await this.writeStructuredArrayParts<AiraSyncBookmarkItemEntity>(
          store,
          record.providerId,
          generation,
          'private-items',
          privateDataSet.bookmarkItems
        );
        privateItemPartCount = privateItemResult.partCount;
        payloadLength += privateItemResult.payloadLength;

        const privateOrderResult = await this.writeStructuredArrayParts<AiraSyncBookmarkOrder>(
          store,
          record.providerId,
          generation,
          'private-orders',
          privateDataSet.bookmarkOrders
        );
        privateOrderPartCount = privateOrderResult.partCount;
        payloadLength += privateOrderResult.payloadLength;

        const privateTombstoneResult = await this.writeStructuredArrayParts<AiraSyncTombstone>(
          store,
          record.providerId,
          generation,
          'private-tombstones',
          privateDataSet.tombstones
        );
        privateTombstonePartCount = privateTombstoneResult.partCount;
        payloadLength += privateTombstoneResult.payloadLength;
      }
    }

    const manifest: AiraStructuredBaselineManifest = {
      version: BASELINE_STRUCTURED_VERSION,
      generation,
      commitId: record.commitId,
      updatedAt: record.updatedAt,
      hasSnapshot: snapshot !== null,
      history: record.history,
      folderPartCount,
      itemPartCount,
      orderPartCount,
      tombstonePartCount,
      privateFolderPartCount,
      privateItemPartCount,
      privateOrderPartCount,
      privateTombstonePartCount
    };
    if (snapshot !== null) {
      manifest.snapshotMeta = snapshot.meta;
    }

    const manifestPayload = JSON.stringify(manifest);
    payloadLength += manifestPayload.length;
    store.putSync(this.buildStructuredManifestKey(record.providerId), manifestPayload);
    await this.yieldAfterBaselineChunk();
    await this.clearPreviousStructuredParts(store, record.providerId, previousManifest, generation);
    return payloadLength;
  }

  private async writeStructuredArrayParts<T>(
    store: preferences.Preferences,
    providerId: string,
    generation: string,
    kind: AiraStructuredBaselinePartKind,
    values: T[]
  ): Promise<AiraStructuredWriteResult> {
    const partCount = Math.ceil(values.length / BASELINE_STRUCTURED_ARRAY_ITEM_LIMIT);
    let payloadLength = 0;
    for (let index = 0; index < partCount; index += 1) {
      const start = index * BASELINE_STRUCTURED_ARRAY_ITEM_LIMIT;
      const payload = JSON.stringify(values.slice(start, start + BASELINE_STRUCTURED_ARRAY_ITEM_LIMIT));
      payloadLength += payload.length;
      store.putSync(this.buildStructuredPartKey(providerId, generation, kind, index), payload);
      await this.yieldAfterBaselineChunk();
    }
    const result: AiraStructuredWriteResult = {
      partCount,
      payloadLength
    };
    return result;
  }

  private async clearPreviousStructuredParts(
    store: preferences.Preferences,
    providerId: string,
    manifest: AiraStructuredBaselineManifest | undefined,
    currentGeneration: string
  ): Promise<void> {
    if (manifest === undefined || manifest.generation === currentGeneration) {
      return;
    }
    await this.clearStructuredParts(store, providerId, manifest);
  }

  private async clearStructuredParts(
    store: preferences.Preferences,
    providerId: string,
    manifest: AiraStructuredBaselineManifest
  ): Promise<void> {
    await this.clearStructuredPartKind(store, providerId, manifest.generation, 'folders', manifest.folderPartCount);
    await this.clearStructuredPartKind(store, providerId, manifest.generation, 'items', manifest.itemPartCount);
    await this.clearStructuredPartKind(store, providerId, manifest.generation, 'orders', manifest.orderPartCount);
    await this.clearStructuredPartKind(store, providerId, manifest.generation, 'tombstones', manifest.tombstonePartCount);
    await this.clearStructuredPartKind(store, providerId, manifest.generation, 'private-folders', manifest.privateFolderPartCount ?? 0);
    await this.clearStructuredPartKind(store, providerId, manifest.generation, 'private-items', manifest.privateItemPartCount ?? 0);
    await this.clearStructuredPartKind(store, providerId, manifest.generation, 'private-orders', manifest.privateOrderPartCount ?? 0);
    await this.clearStructuredPartKind(store, providerId, manifest.generation, 'private-tombstones', manifest.privateTombstonePartCount ?? 0);
  }

  private async clearStructuredPartKind(
    store: preferences.Preferences,
    providerId: string,
    generation: string,
    kind: AiraStructuredBaselinePartKind,
    partCount: number
  ): Promise<void> {
    for (let index = 0; index < partCount; index += 1) {
      store.deleteSync(this.buildStructuredPartKey(providerId, generation, kind, index));
      await this.yieldAfterBaselineChunk();
    }
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }

    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }

    return this.storePromise;
  }

  private logSlowBaselineFlushIfNeeded(providerId: string, startedAt: number, payloadLength: number): void {
    const elapsedMs = Date.now() - startedAt;
    if (elapsedMs < BASELINE_SLOW_FLUSH_WARN_MS) {
      return;
    }
    hilog.warn(
      DOMAIN,
      TAG,
      'Aira sync baseline flush took %{public}dms provider=%{public}s payloadChars=%{public}d',
      elapsedMs,
      providerId,
      payloadLength
    );
  }

  private yieldAfterBaselineChunk(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), BASELINE_CHUNK_YIELD_MS);
    });
  }

  private buildBaselineKey(providerId: string): string {
    return `${BASELINE_PREFIX}${providerId}`;
  }

  private buildStructuredManifestKey(providerId: string): string {
    return `${this.buildBaselineKey(providerId)}${BASELINE_STRUCTURED_MANIFEST_SUFFIX}`;
  }

  private buildStructuredPartKey(
    providerId: string,
    generation: string,
    kind: AiraStructuredBaselinePartKind,
    index: number
  ): string {
    return `${this.buildBaselineKey(providerId)}${BASELINE_STRUCTURED_PART_PREFIX_SUFFIX}${generation}_${kind}_${index}`;
  }

  private buildBaselineGeneration(): string {
    return `${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
  }
}
