import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { BrowserProfileId, DEFAULT_BROWSER_PROFILE_ID } from '../../common/models/BrowserModels';
import {
  SAVED_SITE_SETTING_OVERRIDES_SCHEMA_VERSION,
  SavedSiteSettingEntry,
  SavedSiteSettingOverrides,
  SavedSiteSettingOverridesDocument,
  SiteSettingTarget
} from '../../common/models/SiteSettingModels';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { SiteIdentityService } from '../../services/web/SiteIdentityService';

const DATABASE_NAME: string = 'aira_site_settings.db';
const TABLE_NAME: string = 'saved_site_setting_entries';
const SCHEMA_SQL: string = `CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
  canonical_origin TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  revision INTEGER NOT NULL,
  overrides_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (canonical_origin, profile_id)
)`;

export type SiteSettingCommitStatus = 'saved' | 'deleted' | 'conflict' | 'invalid';

export interface SiteSettingCommitResult {
  status: SiteSettingCommitStatus;
  entry?: SavedSiteSettingEntry;
  current?: SavedSiteSettingEntry;
}

export type SavedSiteSettingUnreadableReason =
  'invalid_target' |
  'invalid_revision' |
  'unsupported_schema' |
  'invalid_overrides' |
  'empty_overrides' |
  'malformed_json';

export interface SavedSiteSettingUnreadableEntry {
  canonicalOrigin: string;
  profileId: BrowserProfileId;
  updatedAt: number;
  reason: SavedSiteSettingUnreadableReason;
}

interface StoredUnreadableEntry extends SavedSiteSettingUnreadableEntry {
  revision: number;
  rawOverrides: string;
}

export interface SavedSiteSettingStorageAdapter {
  load(): Promise<SavedSiteSettingEntry[]>;
  compareAndSwap(
    target: SiteSettingTarget,
    profileId: BrowserProfileId,
    expectedRevision: number,
    next: SavedSiteSettingEntry | undefined
  ): Promise<'saved' | 'conflict'>;
  replaceIdentityReferences?: (identityId: string) => Promise<boolean>;
}

export class InMemorySavedSiteSettingStorageAdapter implements SavedSiteSettingStorageAdapter {
  private entries: SavedSiteSettingEntry[] = [];

  async load(): Promise<SavedSiteSettingEntry[]> {
    return this.entries.map((entry: SavedSiteSettingEntry) => cloneEntry(entry));
  }

  async compareAndSwap(
    target: SiteSettingTarget,
    profileId: BrowserProfileId,
    expectedRevision: number,
    next: SavedSiteSettingEntry | undefined
  ): Promise<'saved' | 'conflict'> {
    const index = this.entries.findIndex((entry: SavedSiteSettingEntry) => {
      return entry.profileId === profileId && entry.target.canonicalOrigin === target.canonicalOrigin;
    });
    const currentRevision = index < 0 ? 0 : this.entries[index].revision;
    if (currentRevision !== expectedRevision) {
      return 'conflict';
    }
    if (next === undefined) {
      if (index >= 0) {
        this.entries.splice(index, 1);
      }
      return 'saved';
    }
    if (index >= 0) {
      this.entries[index] = cloneEntry(next);
    } else {
      this.entries.push(cloneEntry(next));
    }
    return 'saved';
  }

  async replaceIdentityReferences(identityId: string): Promise<boolean> {
    const normalizedIdentityId = identityId.trim();
    this.entries = this.entries
      .map((entry: SavedSiteSettingEntry) => {
        if (entry.overrides.userAgentIdentityId !== normalizedIdentityId) {
          return entry;
        }
        const nextOverrides = cloneOverrides(entry.overrides);
        nextOverrides.userAgentIdentityId = undefined;
        if (!hasNonDefaultOverrides(nextOverrides)) {
          return undefined;
        }
        return {
          profileId: entry.profileId,
          target: entry.target,
          revision: entry.revision + 1,
          overrides: nextOverrides,
          updatedAt: Date.now()
        } as SavedSiteSettingEntry;
      })
      .filter((entry: SavedSiteSettingEntry | undefined) => entry !== undefined)
      .map((entry: SavedSiteSettingEntry | undefined) => entry as SavedSiteSettingEntry);
    return true;
  }
}

export class SavedSiteSettingRepository {
  private readonly identityService: SiteIdentityService = new SiteIdentityService();
  private readonly adapter?: SavedSiteSettingStorageAdapter;
  private store?: relationalStore.RdbStore;
  private storePromise?: Promise<relationalStore.RdbStore>;
  private entries: SavedSiteSettingEntry[] = [];
  private unreadableEntries: StoredUnreadableEntry[] = [];
  private initialized: boolean = false;

  constructor(adapter?: SavedSiteSettingStorageAdapter) {
    this.adapter = adapter;
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (this.adapter !== undefined) {
      this.entries = await this.adapter.load();
      this.unreadableEntries = [];
      this.initialized = true;
      return;
    }
    const store = await this.getStore();
    await store.executeSql(SCHEMA_SQL);
    this.entries = await this.readEntries(store);
    this.initialized = true;
  }

  listEntries(profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID): SavedSiteSettingEntry[] {
    return this.entries
      .filter((entry: SavedSiteSettingEntry) => entry.profileId === profileId)
      .map((entry: SavedSiteSettingEntry) => cloneEntry(entry));
  }

  listUnreadableEntries(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): SavedSiteSettingUnreadableEntry[] {
    return this.unreadableEntries
      .filter((entry: StoredUnreadableEntry) => entry.profileId === profileId)
      .map((entry: StoredUnreadableEntry) => this.copyUnreadableEntry(entry));
  }

  findUnreadableEntry(
    target: SiteSettingTarget | string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): SavedSiteSettingUnreadableEntry | undefined {
    const canonicalOrigin = this.resolveStoredOrigin(target);
    const entry = this.unreadableEntries.find((candidate: StoredUnreadableEntry) => {
      return candidate.profileId === profileId && candidate.canonicalOrigin === canonicalOrigin;
    });
    return entry === undefined ? undefined : this.copyUnreadableEntry(entry);
  }

  async resetUnreadableEntry(
    target: SiteSettingTarget | string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<boolean> {
    if (this.adapter !== undefined) {
      return false;
    }
    const canonicalOrigin = this.resolveStoredOrigin(target);
    const entry = this.unreadableEntries.find((candidate: StoredUnreadableEntry) => {
      return candidate.profileId === profileId && candidate.canonicalOrigin === canonicalOrigin;
    });
    if (entry === undefined) {
      return false;
    }
    const store = await this.getStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('canonical_origin', entry.canonicalOrigin);
    predicates.equalTo('profile_id', entry.profileId);
    predicates.equalTo('revision', entry.revision);
    predicates.equalTo('overrides_json', entry.rawOverrides);
    const affected = await store.delete(predicates);
    if (affected !== 1) {
      return false;
    }
    this.unreadableEntries = this.unreadableEntries.filter((candidate: StoredUnreadableEntry) => {
      return candidate.profileId !== entry.profileId || candidate.canonicalOrigin !== entry.canonicalOrigin;
    });
    return true;
  }

  findEntry(
    target: SiteSettingTarget | string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): SavedSiteSettingEntry | undefined {
    const normalizedTarget = this.normalizeTarget(target);
    if (normalizedTarget === undefined) {
      return undefined;
    }
    const entry = this.entries.find((candidate: SavedSiteSettingEntry) => {
      return candidate.profileId === profileId &&
        candidate.target.canonicalOrigin === normalizedTarget.canonicalOrigin;
    });
    return entry === undefined ? undefined : cloneEntry(entry);
  }

  async commit(
    target: SiteSettingTarget | string,
    profileId: BrowserProfileId,
    overrides: SavedSiteSettingOverrides,
    expectedRevision: number
  ): Promise<SiteSettingCommitResult> {
    const normalizedTarget = this.normalizeTarget(target);
    if (normalizedTarget === undefined || expectedRevision < 0 || !this.areOverridesValid(overrides)) {
      return { status: 'invalid' };
    }
    const current = this.findEntry(normalizedTarget, profileId);
    if ((current?.revision ?? 0) !== expectedRevision) {
      return { status: 'conflict', current: current };
    }
    const normalizedOverrides = normalizeOverrides(overrides);
    const next = this.hasOverrides(normalizedOverrides)
      ? {
        profileId: profileId,
        target: normalizedTarget,
        revision: expectedRevision + 1,
        overrides: normalizedOverrides,
        updatedAt: Date.now()
      } as SavedSiteSettingEntry
      : undefined;
    const status = await this.compareAndSwap(normalizedTarget, profileId, expectedRevision, next);
    if (status === 'conflict') {
      const refreshed = this.findEntry(normalizedTarget, profileId);
      return { status: 'conflict', current: refreshed };
    }
    return {
      status: next === undefined ? 'deleted' : 'saved',
      entry: next === undefined ? undefined : cloneEntry(next)
    };
  }

  async reset(
    target: SiteSettingTarget | string,
    profileId: BrowserProfileId,
    expectedRevision: number
  ): Promise<SiteSettingCommitResult> {
    return this.commit(target, profileId, {}, expectedRevision);
  }

  hasNonDefaultOverrides(overrides: SavedSiteSettingOverrides): boolean {
    return this.hasOverrides(normalizeOverrides(overrides));
  }

  countIdentityReferences(identityId: string, profileId?: BrowserProfileId): number {
    const normalizedIdentityId = identityId.trim();
    return this.entries.filter((entry: SavedSiteSettingEntry) => {
      return entry.overrides.userAgentIdentityId === normalizedIdentityId &&
        (profileId === undefined || entry.profileId === profileId);
    }).length;
  }

  async replaceIdentityReferences(identityId: string): Promise<boolean> {
    const normalizedIdentityId = identityId.trim();
    if (normalizedIdentityId.length <= 0) {
      return false;
    }
    const references = this.entries.filter((entry: SavedSiteSettingEntry) => {
      return entry.overrides.userAgentIdentityId === normalizedIdentityId;
    });
    if (references.length === 0) {
      return true;
    }
    if (this.adapter?.replaceIdentityReferences !== undefined) {
      const saved = await this.adapter.replaceIdentityReferences(normalizedIdentityId);
      if (saved) {
        references.forEach((entry: SavedSiteSettingEntry) => {
          const nextOverrides = cloneOverrides(entry.overrides);
          nextOverrides.userAgentIdentityId = undefined;
          this.replaceCachedEntry(
            entry.target,
            entry.profileId,
            hasNonDefaultOverrides(nextOverrides) ? {
              profileId: entry.profileId,
              target: entry.target,
              revision: entry.revision + 1,
              overrides: nextOverrides,
              updatedAt: Date.now()
            } as SavedSiteSettingEntry : undefined
          );
        });
      }
      return saved;
    }
    const store = await this.getStore();
    store.beginTransaction();
    try {
      const nextEntries: Array<SavedSiteSettingEntry | undefined> = [];
      for (let index = 0; index < references.length; index += 1) {
        const entry = references[index];
        const nextOverrides = cloneOverrides(entry.overrides);
        nextOverrides.userAgentIdentityId = undefined;
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('canonical_origin', entry.target.canonicalOrigin);
        predicates.equalTo('profile_id', entry.profileId);
        predicates.equalTo('revision', entry.revision);
        const nextEntry = hasNonDefaultOverrides(nextOverrides) ? {
          profileId: entry.profileId,
          target: entry.target,
          revision: entry.revision + 1,
          overrides: nextOverrides,
          updatedAt: Date.now()
        } as SavedSiteSettingEntry : undefined;
        const affected = nextEntry === undefined
          ? await store.delete(predicates)
          : await store.update(this.toValues(nextEntry), predicates);
        if (affected !== 1) {
          store.rollBack();
          return false;
        }
        nextEntries.push(nextEntry);
      }
      store.commit();
      references.forEach((entry: SavedSiteSettingEntry, index: number) => {
        this.replaceCachedEntry(entry.target, entry.profileId, nextEntries[index]);
      });
      return true;
    } catch (error) {
      try {
        store.rollBack();
      } catch (_rollbackError) {
      }
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(message);
    }
  }

  private async compareAndSwap(
    target: SiteSettingTarget,
    profileId: BrowserProfileId,
    expectedRevision: number,
    next: SavedSiteSettingEntry | undefined
  ): Promise<'saved' | 'conflict'> {
    if (this.adapter !== undefined) {
      const result = await this.adapter.compareAndSwap(target, profileId, expectedRevision, next);
      if (result === 'saved') {
        this.replaceCachedEntry(target, profileId, next);
      }
      return result;
    }
    const store = await this.getStore();
    store.beginTransaction();
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('canonical_origin', target.canonicalOrigin);
      predicates.equalTo('profile_id', profileId);
      predicates.equalTo('revision', expectedRevision);
      let affected = 0;
      if (next === undefined) {
        affected = await store.delete(predicates);
      } else if (expectedRevision > 0) {
        affected = await store.update(this.toValues(next), predicates);
      } else {
        affected = await store.insert(TABLE_NAME, this.toValues(next));
      }
      if (affected <= 0) {
        store.rollBack();
        return 'conflict';
      }
      store.commit();
      this.replaceCachedEntry(target, profileId, next);
      return 'saved';
    } catch (error) {
      try {
        store.rollBack();
      } catch (_rollbackError) {
      }
      const message = error instanceof Error ? error.message : String(error);
      if (message.toLowerCase().indexOf('constraint') >= 0 || message.toLowerCase().indexOf('unique') >= 0) {
        return 'conflict';
      }
      throw new Error(message);
    }
  }

  private normalizeTarget(target: SiteSettingTarget | string): SiteSettingTarget | undefined {
    if (typeof target === 'string') {
      return this.identityService.resolveSiteSettingTarget(target);
    }
    return this.identityService.resolveSiteSettingTarget(target.canonicalOrigin);
  }

  private resolveStoredOrigin(target: SiteSettingTarget | string): string {
    if (typeof target !== 'string') {
      return target.canonicalOrigin;
    }
    return this.identityService.resolveSiteSettingTarget(target)?.canonicalOrigin ?? target.trim();
  }

  private areOverridesValid(overrides: SavedSiteSettingOverrides): boolean {
    if (overrides === undefined || overrides === null) {
      return false;
    }
    return (overrides.userAgentIdentityId === undefined || typeof overrides.userAgentIdentityId === 'string') &&
      (overrides.javaScriptEnabled === undefined || typeof overrides.javaScriptEnabled === 'boolean') &&
      (overrides.clearOnClose === undefined || typeof overrides.clearOnClose === 'boolean') &&
      (overrides.preserveCookiesOnClose === undefined || typeof overrides.preserveCookiesOnClose === 'boolean') &&
      (overrides.externalNavigationPolicy === undefined || typeof overrides.externalNavigationPolicy === 'string') &&
      (overrides.camera === undefined || typeof overrides.camera === 'string') &&
      (overrides.microphone === undefined || typeof overrides.microphone === 'string') &&
      (overrides.location === undefined || typeof overrides.location === 'string') &&
      (overrides.sensor === undefined || typeof overrides.sensor === 'string') &&
      (overrides.clipboard === undefined || typeof overrides.clipboard === 'string');
  }

  private hasOverrides(overrides: SavedSiteSettingOverrides): boolean {
    return (overrides.userAgentIdentityId?.trim().length ?? 0) > 0 &&
      overrides.userAgentIdentityId !== 'follow_global' ||
      typeof overrides.javaScriptEnabled === 'boolean' ||
      overrides.clearOnClose === true ||
      overrides.preserveCookiesOnClose === true ||
      (overrides.externalNavigationPolicy?.trim().length ?? 0) > 0 ||
      (overrides.camera?.trim().length ?? 0) > 0 ||
      (overrides.microphone?.trim().length ?? 0) > 0 ||
      (overrides.location?.trim().length ?? 0) > 0 ||
      (overrides.sensor?.trim().length ?? 0) > 0 ||
      (overrides.clipboard?.trim().length ?? 0) > 0;
  }

  private replaceCachedEntry(
    target: SiteSettingTarget,
    profileId: BrowserProfileId,
    next: SavedSiteSettingEntry | undefined
  ): void {
    this.entries = this.entries.filter((entry: SavedSiteSettingEntry) => {
      return entry.profileId !== profileId || entry.target.canonicalOrigin !== target.canonicalOrigin;
    });
    if (next !== undefined) {
      this.entries.push(cloneEntry(next));
    }
  }

  private toValues(entry: SavedSiteSettingEntry): relationalStore.ValuesBucket {
    const document: SavedSiteSettingOverridesDocument = {
      schemaVersion: SAVED_SITE_SETTING_OVERRIDES_SCHEMA_VERSION,
      overrides: entry.overrides
    };
    return {
      canonical_origin: entry.target.canonicalOrigin,
      profile_id: entry.profileId,
      revision: entry.revision,
      overrides_json: JSON.stringify(document),
      updated_at: entry.updatedAt
    };
  }

  private async readEntries(store: relationalStore.RdbStore): Promise<SavedSiteSettingEntry[]> {
    const resultSet = await store.query(
      new relationalStore.RdbPredicates(TABLE_NAME),
      ['canonical_origin', 'profile_id', 'revision', 'overrides_json', 'updated_at']
    );
    const entries: SavedSiteSettingEntry[] = [];
    this.unreadableEntries = [];
    try {
      while (resultSet.goToNextRow()) {
        const origin = resultSet.getString(resultSet.getColumnIndex('canonical_origin'));
        const profileId = resultSet.getString(resultSet.getColumnIndex('profile_id')) as BrowserProfileId;
        const revision = resultSet.getLong(resultSet.getColumnIndex('revision'));
        const rawOverrides = resultSet.getString(resultSet.getColumnIndex('overrides_json'));
        const updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
        const target = this.identityService.resolveSiteSettingTarget(origin);
        if (target === undefined) {
          this.rememberUnreadableEntry(origin, profileId, revision, rawOverrides, updatedAt, 'invalid_target');
          continue;
        }
        if (!Number.isInteger(revision) || revision <= 0) {
          this.rememberUnreadableEntry(origin, profileId, revision, rawOverrides, updatedAt, 'invalid_revision');
          continue;
        }
        try {
          const document = JSON.parse(rawOverrides) as SavedSiteSettingOverridesDocument;
          if (document === undefined || document === null ||
            document.schemaVersion !== SAVED_SITE_SETTING_OVERRIDES_SCHEMA_VERSION) {
            this.rememberUnreadableEntry(origin, profileId, revision, rawOverrides, updatedAt, 'unsupported_schema');
            continue;
          }
          if (document.overrides === undefined || !this.areOverridesValid(document.overrides)) {
            this.rememberUnreadableEntry(origin, profileId, revision, rawOverrides, updatedAt, 'invalid_overrides');
            continue;
          }
          const overrides = normalizeOverrides(document.overrides);
          if (!this.hasOverrides(overrides)) {
            this.rememberUnreadableEntry(origin, profileId, revision, rawOverrides, updatedAt, 'empty_overrides');
            continue;
          }
          entries.push({
            profileId: profileId,
            target: target,
            revision: revision,
            overrides: overrides,
            updatedAt: updatedAt
          });
        } catch (_error) {
          this.rememberUnreadableEntry(origin, profileId, revision, rawOverrides, updatedAt, 'malformed_json');
        }
      }
    } finally {
      try {
        resultSet.close();
      } catch (_error) {
      }
    }
    return entries;
  }

  private rememberUnreadableEntry(
    canonicalOrigin: string,
    profileId: BrowserProfileId,
    revision: number,
    rawOverrides: string,
    updatedAt: number,
    reason: SavedSiteSettingUnreadableReason
  ): void {
    this.unreadableEntries.push({
      canonicalOrigin: canonicalOrigin,
      profileId: profileId,
      revision: revision,
      rawOverrides: rawOverrides,
      updatedAt: updatedAt,
      reason: reason
    });
  }

  private copyUnreadableEntry(entry: StoredUnreadableEntry): SavedSiteSettingUnreadableEntry {
    return {
      canonicalOrigin: entry.canonicalOrigin,
      profileId: entry.profileId,
      updatedAt: entry.updatedAt,
      reason: entry.reason
    };
  }

  private async getStore(): Promise<relationalStore.RdbStore> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      const context: common.ApplicationContext = AppRuntimeContext.getApplicationContext();
      const config: relationalStore.StoreConfig = {
        name: DATABASE_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      this.storePromise = relationalStore.getRdbStore(context, config).then((store: relationalStore.RdbStore) => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }
}

export const sharedSavedSiteSettingRepository: SavedSiteSettingRepository =
  new SavedSiteSettingRepository();

function normalizeOverrides(overrides: SavedSiteSettingOverrides): SavedSiteSettingOverrides {
  const next: SavedSiteSettingOverrides = {};
  if (typeof overrides.userAgentIdentityId === 'string' && overrides.userAgentIdentityId.trim().length > 0 &&
    overrides.userAgentIdentityId !== 'follow_global') {
    next.userAgentIdentityId = overrides.userAgentIdentityId.trim();
  }
  if (typeof overrides.javaScriptEnabled === 'boolean') {
    next.javaScriptEnabled = overrides.javaScriptEnabled;
  }
  if (overrides.clearOnClose === true) {
    next.clearOnClose = true;
  }
  if (overrides.preserveCookiesOnClose === true) {
    next.preserveCookiesOnClose = true;
  }
  if (typeof overrides.externalNavigationPolicy === 'string' && overrides.externalNavigationPolicy.trim().length > 0) {
    next.externalNavigationPolicy = overrides.externalNavigationPolicy.trim();
  }
  if (typeof overrides.camera === 'string' && overrides.camera.trim().length > 0) {
    next.camera = overrides.camera.trim();
  }
  if (typeof overrides.microphone === 'string' && overrides.microphone.trim().length > 0) {
    next.microphone = overrides.microphone.trim();
  }
  if (typeof overrides.location === 'string' && overrides.location.trim().length > 0) {
    next.location = overrides.location.trim();
  }
  if (typeof overrides.sensor === 'string' && overrides.sensor.trim().length > 0) {
    next.sensor = overrides.sensor.trim();
  }
  if (typeof overrides.clipboard === 'string' && overrides.clipboard.trim().length > 0) {
    next.clipboard = overrides.clipboard.trim();
  }
  return next;
}

function hasNonDefaultOverrides(overrides: SavedSiteSettingOverrides): boolean {
  return (overrides.userAgentIdentityId?.trim().length ?? 0) > 0 &&
      overrides.userAgentIdentityId !== 'follow_global' ||
    typeof overrides.javaScriptEnabled === 'boolean' ||
    overrides.clearOnClose === true ||
    overrides.preserveCookiesOnClose === true ||
    (overrides.externalNavigationPolicy?.trim().length ?? 0) > 0 ||
    (overrides.camera?.trim().length ?? 0) > 0 ||
    (overrides.microphone?.trim().length ?? 0) > 0 ||
    (overrides.location?.trim().length ?? 0) > 0 ||
    (overrides.sensor?.trim().length ?? 0) > 0 ||
    (overrides.clipboard?.trim().length ?? 0) > 0;
}

function cloneOverrides(overrides: SavedSiteSettingOverrides): SavedSiteSettingOverrides {
  return {
    userAgentIdentityId: overrides.userAgentIdentityId,
    javaScriptEnabled: overrides.javaScriptEnabled,
    clearOnClose: overrides.clearOnClose,
    preserveCookiesOnClose: overrides.preserveCookiesOnClose,
    externalNavigationPolicy: overrides.externalNavigationPolicy,
    camera: overrides.camera,
    microphone: overrides.microphone,
    location: overrides.location,
    sensor: overrides.sensor,
    clipboard: overrides.clipboard
  };
}

function cloneEntry(entry: SavedSiteSettingEntry): SavedSiteSettingEntry {
  return {
    profileId: entry.profileId,
    target: {
      scheme: entry.target.scheme,
      host: entry.target.host,
      effectivePort: entry.target.effectivePort,
      canonicalOrigin: entry.target.canonicalOrigin,
      displayOrigin: entry.target.displayOrigin,
      displayHost: entry.target.displayHost
    },
    revision: entry.revision,
    overrides: normalizeOverrides(entry.overrides),
    updatedAt: entry.updatedAt
  };
}
