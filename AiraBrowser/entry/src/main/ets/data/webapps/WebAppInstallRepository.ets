import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  DesktopWebEntryRecord,
  DesktopWebEntrySettings,
  DesktopWebEntryUpsertInput,
  buildDesktopWebEntryRecord,
  normalizeDesktopWebEntryInstallState,
  normalizeDesktopWebEntrySettings
} from './WebAppInstallModels';

const PREFERENCES_NAME: string = 'aira_webapps';
const INSTALLS_KEY: string = 'webapp_installs_v1';

type RawRecordMap = Record<string, DesktopWebEntryRecord>;

export interface WebAppInstallRepositorySnapshot {
  records: DesktopWebEntryRecord[];
  byShortcutId: Record<string, DesktopWebEntryRecord>;
  byOriginAndScope: Record<string, DesktopWebEntryRecord>;
}

export class WebAppInstallRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private cache: Record<string, DesktopWebEntryRecord> = {};
  private cacheLoaded: boolean = false;
  private cachePromise?: Promise<Record<string, DesktopWebEntryRecord>>;

  async getAll(): Promise<DesktopWebEntryRecord[]> {
    const cache = await this.ensureLoaded();
    return Object.keys(cache).map((key: string) => cache[key]);
  }

  async findByShortcutId(shortcutId: string): Promise<DesktopWebEntryRecord | undefined> {
    const trimmed = shortcutId.trim();
    if (trimmed.length === 0) {
      return undefined;
    }
    const cache = await this.ensureLoaded();
    return cache[trimmed];
  }

  async upsert(input: DesktopWebEntryUpsertInput): Promise<DesktopWebEntryRecord> {
    const cache = await this.ensureLoaded();
    const now = Date.now();
    const existing = cache[input.shortcutId];
    const next: DesktopWebEntryRecord = existing === undefined
      ? buildDesktopWebEntryRecord(input, now)
      : this.mergeRecord(existing, input, now);
    cache[input.shortcutId] = next;
    await this.persist(cache);
    return next;
  }

  async replace(record: DesktopWebEntryRecord): Promise<DesktopWebEntryRecord> {
    const cache = await this.ensureLoaded();
    cache[record.shortcutId] = record;
    await this.persist(cache);
    return record;
  }

  async updateSettings(shortcutId: string, settings: DesktopWebEntrySettings): Promise<DesktopWebEntryRecord | undefined> {
    const normalizedShortcutId = shortcutId.trim();
    if (normalizedShortcutId.length === 0) {
      return undefined;
    }
    const cache = await this.ensureLoaded();
    const record = cache[normalizedShortcutId];
    if (record === undefined) {
      return undefined;
    }
    const next: DesktopWebEntryRecord = {
      shortcutId: record.shortcutId,
      installState: record.installState,
      title: record.title,
      iconPath: record.iconPath,
      launchUrl: record.launchUrl,
      currentUrl: record.currentUrl,
      origin: record.origin,
      manifestUrl: record.manifestUrl,
      scope: record.scope,
      display: record.display,
      themeColor: record.themeColor,
      backgroundColor: record.backgroundColor,
      settings: normalizeDesktopWebEntrySettings(settings),
      createdAt: record.createdAt,
      updatedAt: Date.now()
    };
    cache[normalizedShortcutId] = next;
    await this.persist(cache);
    return next;
  }

  async updateCurrentUrl(shortcutId: string, currentUrl: string): Promise<DesktopWebEntryRecord | undefined> {
    const normalizedShortcutId = shortcutId.trim();
    const normalizedCurrentUrl = currentUrl.trim();
    if (normalizedShortcutId.length === 0 || normalizedCurrentUrl.length === 0) {
      return undefined;
    }
    const cache = await this.ensureLoaded();
    const record = cache[normalizedShortcutId];
    if (record === undefined) {
      return undefined;
    }
    const next: DesktopWebEntryRecord = {
      shortcutId: record.shortcutId,
      installState: record.installState,
      title: record.title,
      iconPath: record.iconPath,
      launchUrl: record.launchUrl,
      currentUrl: normalizedCurrentUrl,
      origin: record.origin,
      manifestUrl: record.manifestUrl,
      scope: record.scope,
      display: record.display,
      themeColor: record.themeColor,
      backgroundColor: record.backgroundColor,
      settings: normalizeDesktopWebEntrySettings(record.settings),
      createdAt: record.createdAt,
      updatedAt: Date.now()
    };
    cache[normalizedShortcutId] = next;
    await this.persist(cache);
    return next;
  }

  async remove(shortcutId: string): Promise<boolean> {
    const cache = await this.ensureLoaded();
    if (cache[shortcutId] === undefined) {
      return false;
    }
    const next: Record<string, DesktopWebEntryRecord> = {};
    const keys = Object.keys(cache);
    for (let index = 0; index < keys.length; index++) {
      const key = keys[index];
      if (key !== shortcutId) {
        next[key] = cache[key];
      }
    }
    this.cache = next;
    await this.persist(next);
    return true;
  }

  async refresh(): Promise<DesktopWebEntryRecord[]> {
    this.cacheLoaded = false;
    this.cachePromise = undefined;
    this.cache = {};
    return this.getAll();
  }

  async snapshot(): Promise<WebAppInstallRepositorySnapshot> {
    const cache = await this.ensureLoaded();
    const records: DesktopWebEntryRecord[] = [];
    const byShortcutId: Record<string, DesktopWebEntryRecord> = {};
    const byOriginAndScope: Record<string, DesktopWebEntryRecord> = {};
    Object.keys(cache).forEach((key: string) => {
      const record = cache[key];
      records.push(record);
      byShortcutId[record.shortcutId] = record;
      if (record.origin.length > 0) {
        byOriginAndScope[`${record.origin}|${record.scope}`] = record;
      }
    });
    return { records, byShortcutId, byOriginAndScope };
  }

  private mergeRecord(
    existing: DesktopWebEntryRecord,
    input: DesktopWebEntryUpsertInput,
    now: number
  ): DesktopWebEntryRecord {
    return {
      shortcutId: existing.shortcutId,
      installState: input.installState ?? existing.installState,
      title: input.title.length > 0 ? input.title : existing.title,
      iconPath: input.iconPath.length > 0 ? input.iconPath : existing.iconPath,
      launchUrl: input.launchUrl.length > 0 ? input.launchUrl : existing.launchUrl,
      currentUrl: input.currentUrl.length > 0 ? input.currentUrl : existing.currentUrl,
      origin: input.origin.length > 0 ? input.origin : existing.origin,
      manifestUrl: (input.manifestUrl ?? '').length > 0 ? (input.manifestUrl ?? '') : existing.manifestUrl,
      scope: (input.scope ?? '').length > 0 ? (input.scope ?? '') : existing.scope,
      display: (input.display ?? '').length > 0 ? (input.display ?? '') : existing.display,
      themeColor: (input.themeColor ?? '').length > 0 ? (input.themeColor ?? '') : existing.themeColor,
      backgroundColor: (input.backgroundColor ?? '').length > 0 ? (input.backgroundColor ?? '') : existing.backgroundColor,
      settings: input.settings !== undefined ? normalizeDesktopWebEntrySettings(input.settings) :
        normalizeDesktopWebEntrySettings(existing.settings),
      createdAt: existing.createdAt,
      updatedAt: now
    };
  }

  private async ensureLoaded(): Promise<Record<string, DesktopWebEntryRecord>> {
    if (this.cacheLoaded) {
      return this.cache;
    }
    if (this.cachePromise === undefined) {
      this.cachePromise = this.loadFromStore().then((records: Record<string, DesktopWebEntryRecord>) => {
        this.cache = records;
        this.cacheLoaded = true;
        return this.cache;
      });
    }
    return this.cachePromise;
  }

  private async loadFromStore(): Promise<Record<string, DesktopWebEntryRecord>> {
    const store = await this.getStore();
    if (store === undefined) {
      return {};
    }
    const raw = String(await store.get(INSTALLS_KEY, '{}') ?? '{}');
    return this.parseStoredRecords(raw);
  }

  private parseStoredRecords(raw: string): Record<string, DesktopWebEntryRecord> {
    const trimmed = raw.trim();
    if (trimmed.length === 0 || trimmed === '{}') {
      return {};
    }
    try {
      const parsed = JSON.parse(trimmed) as RawRecordMap;
      const result: Record<string, DesktopWebEntryRecord> = {};
      Object.keys(parsed).forEach((shortcutId: string) => {
        const record = parsed[shortcutId];
        if (record === undefined || record === null) {
          return;
        }
        const normalized: DesktopWebEntryRecord = {
          shortcutId: String(record.shortcutId ?? shortcutId),
          installState: normalizeDesktopWebEntryInstallState(String(record.installState ?? 'installed')),
          title: String(record.title ?? ''),
          iconPath: String(record.iconPath ?? ''),
          launchUrl: String(record.launchUrl ?? ''),
          currentUrl: String(record.currentUrl ?? ''),
          origin: String(record.origin ?? ''),
          manifestUrl: String(record.manifestUrl ?? ''),
          scope: String(record.scope ?? ''),
          display: String(record.display ?? ''),
          themeColor: String(record.themeColor ?? ''),
          backgroundColor: String(record.backgroundColor ?? ''),
          settings: normalizeDesktopWebEntrySettings(record.settings),
          createdAt: Number(record.createdAt ?? Date.now()),
          updatedAt: Number(record.updatedAt ?? Date.now())
        };
        result[normalized.shortcutId] = normalized;
      });
      return result;
    } catch (_error) {
      return {};
    }
  }

  private async persist(records: Record<string, DesktopWebEntryRecord>): Promise<void> {
    const store = await this.getStore();
    if (store === undefined) {
      return;
    }
    await store.put(INSTALLS_KEY, JSON.stringify(records));
    await store.flush();
  }

  private async getStore(): Promise<preferences.Preferences | undefined> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      if (!AppRuntimeContext.hasApplicationContext()) {
        return undefined;
      }
      const context = AppRuntimeContext.getApplicationContext();
      this.storePromise = preferences.getPreferences(context, PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

export const sharedWebAppInstallRepository: WebAppInstallRepository = new WebAppInstallRepository();
