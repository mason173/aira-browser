import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserProfileId,
  normalizeBrowserProfileId
} from '../../common/models/BrowserModels';
import {
  BrowserWebSecuritySettings,
  copyBrowserWebSecuritySettings,
  DEFAULT_BROWSER_WEB_SECURITY_SETTINGS,
  normalizeBrowserWebSecuritySettings
} from '../../common/models/BrowserWebSecurityModels';

const PREFERENCES_NAME: string = 'aira_browser_web_security';
const SETTINGS_KEY: string = 'settings_v1';
const HTTP_FALLBACK_EXCEPTIONS_KEY: string = 'http_fallback_exceptions_v1';
const HTTPS_FIRST_DECLINED_RETRIES_KEY: string = 'https_first_declined_retries_v1';
const HTTPS_FIRST_HTTP_SESSION_GRANTS_KEY: string = 'https_first_http_session_grants_v1';
const HTTP_FALLBACK_EXCEPTIONS_VERSION: number = 1;
const HTTPS_FIRST_DECLINED_RETRIES_VERSION: number = 1;
const HTTPS_FIRST_HTTP_SESSION_GRANTS_VERSION: number = 1;
const MAX_HTTP_FALLBACK_EXCEPTIONS: number = 256;
const MAX_HTTPS_FIRST_DECLINED_RETRIES: number = 64;
const MAX_HTTPS_FIRST_HTTP_SESSION_GRANTS: number = 64;

interface BrowserHttpFallbackSiteExceptionRecord {
  profileId: BrowserProfileId;
  siteKey: string;
  expiresAt: number;
}

interface BrowserHttpFallbackSiteExceptionPayload {
  version: number;
  records: BrowserHttpFallbackSiteExceptionRecord[];
}

export interface BrowserHttpsFirstDeclinedRetryRecord {
  tabId: string;
  profileId: BrowserProfileId;
  originalUrl: string;
  upgradedUrl: string;
  source: string;
  expiresAt: number;
}

interface BrowserHttpsFirstDeclinedRetryPayload {
  version: number;
  records: BrowserHttpsFirstDeclinedRetryRecord[];
}

export interface BrowserHttpsFirstHttpSessionGrantRecord {
  tabId: string;
  profileId: BrowserProfileId;
  anchorHost: string;
  effectivePort: number;
  expiresAt: number;
}

interface BrowserHttpsFirstHttpSessionGrantPayload {
  version: number;
  records: BrowserHttpsFirstHttpSessionGrantRecord[];
}

export interface BrowserHttpsFirstHttpSessionGrantStorageState {
  records: BrowserHttpsFirstHttpSessionGrantRecord[];
  serialized: string;
  requiresRewrite: boolean;
}

export class BrowserHttpsFirstHttpSessionGrantCodec {
  decodeStorage(value: string, now: number = Date.now()): BrowserHttpsFirstHttpSessionGrantStorageState {
    const normalizedValue = value.trim();
    const records = this.normalizeRecords(this.parsePayload(normalizedValue)?.records ?? [], now);
    const serialized = this.encode(records, now);
    return {
      records: records,
      serialized: serialized,
      requiresRewrite: normalizedValue.length > 0 && normalizedValue !== serialized
    };
  }

  encode(records: BrowserHttpsFirstHttpSessionGrantRecord[], now: number = Date.now()): string {
    const payload: BrowserHttpsFirstHttpSessionGrantPayload = {
      version: HTTPS_FIRST_HTTP_SESSION_GRANTS_VERSION,
      records: this.normalizeRecords(records, now)
    };
    return JSON.stringify(payload);
  }

  normalizeRecords(
    records: BrowserHttpsFirstHttpSessionGrantRecord[],
    now: number
  ): BrowserHttpsFirstHttpSessionGrantRecord[] {
    const normalizedRecords: BrowserHttpsFirstHttpSessionGrantRecord[] = [];
    records.forEach((record: BrowserHttpsFirstHttpSessionGrantRecord): void => {
      try {
        const normalized = this.normalizeRecord(record, now);
        if (normalized !== undefined) {
          normalizedRecords.push(normalized);
        }
      } catch (_error) {
        // Preferences payloads are untrusted at runtime; one malformed record must not block startup.
      }
    });
    return normalizedRecords
      .sort((left: BrowserHttpsFirstHttpSessionGrantRecord,
        right: BrowserHttpsFirstHttpSessionGrantRecord): number => right.expiresAt - left.expiresAt)
      .slice(0, MAX_HTTPS_FIRST_HTTP_SESSION_GRANTS);
  }

  normalizeRecord(
    record: BrowserHttpsFirstHttpSessionGrantRecord,
    now: number
  ): BrowserHttpsFirstHttpSessionGrantRecord | undefined {
    const tabId = String(record.tabId ?? '').trim();
    const anchorHost = String(record.anchorHost ?? '').trim().toLowerCase();
    const effectivePort = this.normalizeEffectivePort(record.effectivePort);
    const expiresAt = this.normalizeTimestamp(record.expiresAt);
    if (tabId.length === 0 || anchorHost.length === 0 || /[\s\/?#@]/.test(anchorHost) ||
      effectivePort <= 0 || expiresAt <= now) {
      return undefined;
    }
    return {
      tabId: tabId,
      profileId: normalizeBrowserProfileId(record.profileId),
      anchorHost: anchorHost,
      effectivePort: effectivePort,
      expiresAt: expiresAt
    };
  }

  private parsePayload(value: string): BrowserHttpsFirstHttpSessionGrantPayload | undefined {
    if (value.length === 0) {
      return undefined;
    }
    try {
      const payload = JSON.parse(value) as BrowserHttpsFirstHttpSessionGrantPayload;
      return payload.version === HTTPS_FIRST_HTTP_SESSION_GRANTS_VERSION && Array.isArray(payload.records)
        ? payload
        : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  private normalizeEffectivePort(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && Number.isInteger(value) && value > 0 && value <= 65535
      ? value
      : 0;
  }
}

export class BrowserWebSecuritySettingsRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: BrowserWebSecuritySettings =
    copyBrowserWebSecuritySettings(DEFAULT_BROWSER_WEB_SECURITY_SETTINGS);
  private httpFallbackExceptionsByKey: Record<string, BrowserHttpFallbackSiteExceptionRecord | undefined> = {};
  private httpsFirstDeclinedRetriesByTabId:
    Record<string, BrowserHttpsFirstDeclinedRetryRecord | undefined> = {};
  private httpsFirstHttpSessionGrantsByTabId:
    Record<string, BrowserHttpsFirstHttpSessionGrantRecord | undefined> = {};
  private readonly httpsFirstHttpSessionGrantCodec: BrowserHttpsFirstHttpSessionGrantCodec =
    new BrowserHttpsFirstHttpSessionGrantCodec();

  async initialize(): Promise<BrowserWebSecuritySettings> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(SETTINGS_KEY, ''));
    this.settings = normalizeBrowserWebSecuritySettings(this.parseSettings(rawSettings));
    const rawHttpFallbackExceptions = String(store.getSync(HTTP_FALLBACK_EXCEPTIONS_KEY, ''));
    this.httpFallbackExceptionsByKey = this.normalizeHttpFallbackExceptionPayload(
      this.parseHttpFallbackExceptionPayload(rawHttpFallbackExceptions),
      Date.now()
    );
    const rawHttpsFirstDeclinedRetries = String(store.getSync(HTTPS_FIRST_DECLINED_RETRIES_KEY, ''));
    this.httpsFirstDeclinedRetriesByTabId = this.normalizeHttpsFirstDeclinedRetryPayload(
      this.parseHttpsFirstDeclinedRetryPayload(rawHttpsFirstDeclinedRetries),
      Date.now()
    );
    const rawHttpsFirstHttpSessionGrants = String(store.getSync(HTTPS_FIRST_HTTP_SESSION_GRANTS_KEY, ''));
    const httpSessionGrantStorage = this.httpsFirstHttpSessionGrantCodec.decodeStorage(
      rawHttpsFirstHttpSessionGrants,
      Date.now()
    );
    this.httpsFirstHttpSessionGrantsByTabId = this.mapHttpsFirstHttpSessionGrantRecords(
      httpSessionGrantStorage.records
    );
    if (httpSessionGrantStorage.requiresRewrite) {
      store.putSync(HTTPS_FIRST_HTTP_SESSION_GRANTS_KEY, httpSessionGrantStorage.serialized);
      await store.flush();
    }
    if (rawSettings.trim().length === 0) {
      await this.persistSettings(this.settings);
    }
    return this.getSettings();
  }

  getSettings(): BrowserWebSecuritySettings {
    return copyBrowserWebSecuritySettings(this.settings);
  }

  async updateSettings(settings: BrowserWebSecuritySettings): Promise<BrowserWebSecuritySettings> {
    return this.persistSettings(settings);
  }

  isHttpFallbackSiteAllowed(
    profileId: BrowserProfileId,
    siteKey: string,
    now: number = Date.now()
  ): boolean {
    return this.readHttpFallbackSiteExpiration(profileId, siteKey, now) > 0;
  }

  readHttpFallbackSiteExpiration(
    profileId: BrowserProfileId,
    siteKey: string,
    now: number = Date.now()
  ): number {
    const storageKey = this.buildHttpFallbackExceptionStorageKey(profileId, siteKey);
    if (storageKey.length === 0) {
      return 0;
    }
    const record = this.httpFallbackExceptionsByKey[storageKey];
    if (record === undefined) {
      return 0;
    }
    if (record.expiresAt <= now) {
      this.httpFallbackExceptionsByKey[storageKey] = undefined;
      this.persistHttpFallbackExceptions();
      return 0;
    }
    return record.expiresAt;
  }

  rememberHttpFallbackSite(
    profileId: BrowserProfileId,
    siteKey: string,
    expiresAt: number
  ): void {
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    const normalizedSiteKey = this.normalizeHttpFallbackSiteKey(siteKey);
    const normalizedExpiresAt = this.normalizeTimestamp(expiresAt);
    if (normalizedSiteKey.length === 0 || normalizedExpiresAt <= Date.now()) {
      return;
    }
    const record: BrowserHttpFallbackSiteExceptionRecord = {
      profileId: normalizedProfileId,
      siteKey: normalizedSiteKey,
      expiresAt: normalizedExpiresAt
    };
    this.httpFallbackExceptionsByKey[
      this.buildHttpFallbackExceptionStorageKey(normalizedProfileId, normalizedSiteKey)
    ] = record;
    this.persistHttpFallbackExceptions();
  }

  readHttpsFirstDeclinedRetry(
    tabId: string,
    now: number = Date.now()
  ): BrowserHttpsFirstDeclinedRetryRecord | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return undefined;
    }
    const record = this.httpsFirstDeclinedRetriesByTabId[normalizedTabId];
    if (record === undefined) {
      return undefined;
    }
    if (record.expiresAt <= now) {
      this.httpsFirstDeclinedRetriesByTabId[normalizedTabId] = undefined;
      this.persistHttpsFirstDeclinedRetries();
      return undefined;
    }
    return this.copyHttpsFirstDeclinedRetryRecord(record);
  }

  rememberHttpsFirstDeclinedRetry(
    tabId: string,
    profileId: BrowserProfileId,
    originalUrl: string,
    upgradedUrl: string,
    source: string,
    expiresAt: number
  ): void {
    const record = this.normalizeHttpsFirstDeclinedRetryRecord({
      tabId: tabId,
      profileId: profileId,
      originalUrl: originalUrl,
      upgradedUrl: upgradedUrl,
      source: source,
      expiresAt: expiresAt
    }, Date.now());
    if (record === undefined) {
      return;
    }
    this.httpsFirstDeclinedRetriesByTabId[record.tabId] = record;
    this.persistHttpsFirstDeclinedRetries();
  }

  clearHttpsFirstDeclinedRetry(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0 || this.httpsFirstDeclinedRetriesByTabId[normalizedTabId] === undefined) {
      return;
    }
    this.httpsFirstDeclinedRetriesByTabId[normalizedTabId] = undefined;
    this.persistHttpsFirstDeclinedRetries();
  }

  readHttpsFirstHttpSessionGrant(
    tabId: string,
    now: number = Date.now()
  ): BrowserHttpsFirstHttpSessionGrantRecord | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return undefined;
    }
    const record = this.httpsFirstHttpSessionGrantsByTabId[normalizedTabId];
    if (record === undefined) {
      return undefined;
    }
    if (record.expiresAt <= now) {
      this.httpsFirstHttpSessionGrantsByTabId[normalizedTabId] = undefined;
      this.persistHttpsFirstHttpSessionGrants();
      return undefined;
    }
    return this.copyHttpsFirstHttpSessionGrantRecord(record);
  }

  rememberHttpsFirstHttpSessionGrant(
    tabId: string,
    profileId: BrowserProfileId,
    anchorHost: string,
    effectivePort: number,
    expiresAt: number
  ): void {
    const record = this.httpsFirstHttpSessionGrantCodec.normalizeRecord({
      tabId: tabId,
      profileId: profileId,
      anchorHost: anchorHost,
      effectivePort: effectivePort,
      expiresAt: expiresAt
    }, Date.now());
    if (record === undefined) {
      return;
    }
    this.httpsFirstHttpSessionGrantsByTabId[record.tabId] = record;
    this.persistHttpsFirstHttpSessionGrants();
  }

  clearHttpsFirstHttpSessionGrant(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0 || this.httpsFirstHttpSessionGrantsByTabId[normalizedTabId] === undefined) {
      return;
    }
    this.httpsFirstHttpSessionGrantsByTabId[normalizedTabId] = undefined;
    this.persistHttpsFirstHttpSessionGrants();
  }

  async clearHttpsFirstSiteDecisions(profileId: BrowserProfileId): Promise<void> {
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    Object.keys(this.httpFallbackExceptionsByKey).forEach((storageKey: string): void => {
      const record = this.httpFallbackExceptionsByKey[storageKey];
      if (record !== undefined && record.profileId === normalizedProfileId) {
        this.httpFallbackExceptionsByKey[storageKey] = undefined;
      }
    });
    Object.keys(this.httpsFirstDeclinedRetriesByTabId).forEach((tabId: string): void => {
      const record = this.httpsFirstDeclinedRetriesByTabId[tabId];
      if (record !== undefined && record.profileId === normalizedProfileId) {
        this.httpsFirstDeclinedRetriesByTabId[tabId] = undefined;
      }
    });
    Object.keys(this.httpsFirstHttpSessionGrantsByTabId).forEach((tabId: string): void => {
      const record = this.httpsFirstHttpSessionGrantsByTabId[tabId];
      if (record !== undefined && record.profileId === normalizedProfileId) {
        this.httpsFirstHttpSessionGrantsByTabId[tabId] = undefined;
      }
    });
    const now = Date.now();
    const httpFallbackRecords = this.listHttpFallbackExceptionRecords(now);
    const declinedRetryRecords = this.listHttpsFirstDeclinedRetryRecords(now);
    const httpSessionGrantRecords = this.listHttpsFirstHttpSessionGrantRecords(now);
    const store = await this.getStore();
    const httpFallbackPayload: BrowserHttpFallbackSiteExceptionPayload = {
      version: HTTP_FALLBACK_EXCEPTIONS_VERSION,
      records: httpFallbackRecords
    };
    const declinedRetryPayload: BrowserHttpsFirstDeclinedRetryPayload = {
      version: HTTPS_FIRST_DECLINED_RETRIES_VERSION,
      records: declinedRetryRecords
    };
    store.putSync(HTTP_FALLBACK_EXCEPTIONS_KEY, JSON.stringify(httpFallbackPayload));
    store.putSync(HTTPS_FIRST_DECLINED_RETRIES_KEY, JSON.stringify(declinedRetryPayload));
    store.putSync(
      HTTPS_FIRST_HTTP_SESSION_GRANTS_KEY,
      this.httpsFirstHttpSessionGrantCodec.encode(httpSessionGrantRecords, now)
    );
    await store.flush();
  }

  private async persistSettings(settings: BrowserWebSecuritySettings): Promise<BrowserWebSecuritySettings> {
    this.settings = normalizeBrowserWebSecuritySettings(settings);
    const store = await this.getStore();
    store.putSync(SETTINGS_KEY, JSON.stringify(this.settings));
    await store.flush();
    return this.getSettings();
  }

  private parseSettings(value: string): BrowserWebSecuritySettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as BrowserWebSecuritySettings;
    } catch (_error) {
      return undefined;
    }
  }

  private parseHttpFallbackExceptionPayload(
    value: string
  ): BrowserHttpFallbackSiteExceptionPayload | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as BrowserHttpFallbackSiteExceptionPayload;
    } catch (_error) {
      return undefined;
    }
  }

  private parseHttpsFirstDeclinedRetryPayload(
    value: string
  ): BrowserHttpsFirstDeclinedRetryPayload | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as BrowserHttpsFirstDeclinedRetryPayload;
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeHttpFallbackExceptionPayload(
    payload: BrowserHttpFallbackSiteExceptionPayload | undefined,
    now: number
  ): Record<string, BrowserHttpFallbackSiteExceptionRecord | undefined> {
    const result: Record<string, BrowserHttpFallbackSiteExceptionRecord | undefined> = {};
    if (payload === undefined || payload.version !== HTTP_FALLBACK_EXCEPTIONS_VERSION ||
      !Array.isArray(payload.records)) {
      return result;
    }
    this.normalizeHttpFallbackExceptionRecords(payload.records, now)
      .forEach((record: BrowserHttpFallbackSiteExceptionRecord): void => {
        const storageKey = this.buildHttpFallbackExceptionStorageKey(record.profileId, record.siteKey);
        if (result[storageKey] === undefined) {
          result[storageKey] = record;
        }
      });
    return result;
  }

  private normalizeHttpFallbackExceptionRecords(
    records: BrowserHttpFallbackSiteExceptionRecord[],
    now: number
  ): BrowserHttpFallbackSiteExceptionRecord[] {
    const normalizedRecords: BrowserHttpFallbackSiteExceptionRecord[] = [];
    records.forEach((record: BrowserHttpFallbackSiteExceptionRecord): void => {
      const siteKey = this.normalizeHttpFallbackSiteKey(record.siteKey);
      const expiresAt = this.normalizeTimestamp(record.expiresAt);
      if (siteKey.length === 0 || expiresAt <= now) {
        return;
      }
      normalizedRecords.push({
        profileId: normalizeBrowserProfileId(record.profileId),
        siteKey: siteKey,
        expiresAt: expiresAt
      });
    });
    return normalizedRecords
      .sort((left: BrowserHttpFallbackSiteExceptionRecord, right: BrowserHttpFallbackSiteExceptionRecord): number => {
        return right.expiresAt - left.expiresAt;
      })
      .slice(0, MAX_HTTP_FALLBACK_EXCEPTIONS);
  }

  private normalizeHttpsFirstDeclinedRetryPayload(
    payload: BrowserHttpsFirstDeclinedRetryPayload | undefined,
    now: number
  ): Record<string, BrowserHttpsFirstDeclinedRetryRecord | undefined> {
    const result: Record<string, BrowserHttpsFirstDeclinedRetryRecord | undefined> = {};
    if (payload === undefined || payload.version !== HTTPS_FIRST_DECLINED_RETRIES_VERSION ||
      !Array.isArray(payload.records)) {
      return result;
    }
    this.normalizeHttpsFirstDeclinedRetryRecords(payload.records, now)
      .forEach((record: BrowserHttpsFirstDeclinedRetryRecord): void => {
        if (result[record.tabId] === undefined) {
          result[record.tabId] = record;
        }
      });
    return result;
  }

  private normalizeHttpsFirstDeclinedRetryRecords(
    records: BrowserHttpsFirstDeclinedRetryRecord[],
    now: number
  ): BrowserHttpsFirstDeclinedRetryRecord[] {
    const normalizedRecords: BrowserHttpsFirstDeclinedRetryRecord[] = [];
    records.forEach((record: BrowserHttpsFirstDeclinedRetryRecord): void => {
      const normalized = this.normalizeHttpsFirstDeclinedRetryRecord(record, now);
      if (normalized !== undefined) {
        normalizedRecords.push(normalized);
      }
    });
    return normalizedRecords
      .sort((left: BrowserHttpsFirstDeclinedRetryRecord, right: BrowserHttpsFirstDeclinedRetryRecord): number => {
        return right.expiresAt - left.expiresAt;
      })
      .slice(0, MAX_HTTPS_FIRST_DECLINED_RETRIES);
  }

  private normalizeHttpsFirstDeclinedRetryRecord(
    record: BrowserHttpsFirstDeclinedRetryRecord,
    now: number
  ): BrowserHttpsFirstDeclinedRetryRecord | undefined {
    const tabId = String(record.tabId ?? '').trim();
    const originalUrl = String(record.originalUrl ?? '').trim();
    const upgradedUrl = String(record.upgradedUrl ?? '').trim();
    const source = String(record.source ?? '').trim();
    const expiresAt = this.normalizeTimestamp(record.expiresAt);
    if (tabId.length === 0 || originalUrl.length === 0 || upgradedUrl.length === 0 || expiresAt <= now ||
      (source !== 'browser_generated' && source !== 'intercepted_http')) {
      return undefined;
    }
    return {
      tabId: tabId,
      profileId: normalizeBrowserProfileId(record.profileId),
      originalUrl: originalUrl,
      upgradedUrl: upgradedUrl,
      source: source,
      expiresAt: expiresAt
    };
  }

  private mapHttpsFirstHttpSessionGrantRecords(
    records: BrowserHttpsFirstHttpSessionGrantRecord[]
  ): Record<string, BrowserHttpsFirstHttpSessionGrantRecord | undefined> {
    const result: Record<string, BrowserHttpsFirstHttpSessionGrantRecord | undefined> = {};
    records.forEach((record: BrowserHttpsFirstHttpSessionGrantRecord): void => {
      if (result[record.tabId] === undefined) {
        result[record.tabId] = record;
      }
    });
    return result;
  }

  private listHttpFallbackExceptionRecords(now: number): BrowserHttpFallbackSiteExceptionRecord[] {
    const records: BrowserHttpFallbackSiteExceptionRecord[] = [];
    Object.keys(this.httpFallbackExceptionsByKey).forEach((storageKey: string): void => {
      const record = this.httpFallbackExceptionsByKey[storageKey];
      if (record !== undefined) {
        records.push(record);
      }
    });
    return this.normalizeHttpFallbackExceptionRecords(records, now);
  }

  private persistHttpFallbackExceptions(): void {
    const now = Date.now();
    const records = this.listHttpFallbackExceptionRecords(now);
    this.httpFallbackExceptionsByKey = this.normalizeHttpFallbackExceptionPayload({
      version: HTTP_FALLBACK_EXCEPTIONS_VERSION,
      records: records
    }, now);
    void this.getStore().then((store: preferences.Preferences): void => {
      const payload: BrowserHttpFallbackSiteExceptionPayload = {
        version: HTTP_FALLBACK_EXCEPTIONS_VERSION,
        records: records
      };
      store.putSync(HTTP_FALLBACK_EXCEPTIONS_KEY, JSON.stringify(payload));
      store.flushSync();
    }).catch((_error: Error): void => {});
  }

  private persistHttpsFirstDeclinedRetries(): void {
    const now = Date.now();
    const normalizedRecords = this.listHttpsFirstDeclinedRetryRecords(now);
    this.httpsFirstDeclinedRetriesByTabId = this.normalizeHttpsFirstDeclinedRetryPayload({
      version: HTTPS_FIRST_DECLINED_RETRIES_VERSION,
      records: normalizedRecords
    }, now);
    void this.getStore().then((store: preferences.Preferences): void => {
      const payload: BrowserHttpsFirstDeclinedRetryPayload = {
        version: HTTPS_FIRST_DECLINED_RETRIES_VERSION,
        records: normalizedRecords
      };
      store.putSync(HTTPS_FIRST_DECLINED_RETRIES_KEY, JSON.stringify(payload));
      store.flushSync();
    }).catch((_error: Error): void => {});
  }

  private persistHttpsFirstHttpSessionGrants(): void {
    const now = Date.now();
    const normalizedRecords = this.listHttpsFirstHttpSessionGrantRecords(now);
    this.httpsFirstHttpSessionGrantsByTabId = this.mapHttpsFirstHttpSessionGrantRecords(normalizedRecords);
    void this.getStore().then((store: preferences.Preferences): void => {
      store.putSync(
        HTTPS_FIRST_HTTP_SESSION_GRANTS_KEY,
        this.httpsFirstHttpSessionGrantCodec.encode(normalizedRecords, now)
      );
      store.flushSync();
    }).catch((_error: Error): void => {});
  }

  private listHttpsFirstDeclinedRetryRecords(now: number): BrowserHttpsFirstDeclinedRetryRecord[] {
    const records: BrowserHttpsFirstDeclinedRetryRecord[] = [];
    Object.keys(this.httpsFirstDeclinedRetriesByTabId).forEach((tabId: string): void => {
      const record = this.httpsFirstDeclinedRetriesByTabId[tabId];
      if (record !== undefined) {
        records.push(record);
      }
    });
    const normalizedRecords = this.normalizeHttpsFirstDeclinedRetryRecords(records, now);
    this.httpsFirstDeclinedRetriesByTabId = this.normalizeHttpsFirstDeclinedRetryPayload({
      version: HTTPS_FIRST_DECLINED_RETRIES_VERSION,
      records: normalizedRecords
    }, now);
    return normalizedRecords;
  }

  private listHttpsFirstHttpSessionGrantRecords(now: number): BrowserHttpsFirstHttpSessionGrantRecord[] {
    const records: BrowserHttpsFirstHttpSessionGrantRecord[] = [];
    Object.keys(this.httpsFirstHttpSessionGrantsByTabId).forEach((tabId: string): void => {
      const record = this.httpsFirstHttpSessionGrantsByTabId[tabId];
      if (record !== undefined) {
        records.push(record);
      }
    });
    const normalizedRecords = this.httpsFirstHttpSessionGrantCodec.normalizeRecords(records, now);
    this.httpsFirstHttpSessionGrantsByTabId = this.mapHttpsFirstHttpSessionGrantRecords(normalizedRecords);
    return normalizedRecords;
  }

  private copyHttpsFirstDeclinedRetryRecord(
    record: BrowserHttpsFirstDeclinedRetryRecord
  ): BrowserHttpsFirstDeclinedRetryRecord {
    return {
      tabId: record.tabId,
      profileId: record.profileId,
      originalUrl: record.originalUrl,
      upgradedUrl: record.upgradedUrl,
      source: record.source,
      expiresAt: record.expiresAt
    };
  }

  private copyHttpsFirstHttpSessionGrantRecord(
    record: BrowserHttpsFirstHttpSessionGrantRecord
  ): BrowserHttpsFirstHttpSessionGrantRecord {
    return {
      tabId: record.tabId,
      profileId: record.profileId,
      anchorHost: record.anchorHost,
      effectivePort: record.effectivePort,
      expiresAt: record.expiresAt
    };
  }

  private buildHttpFallbackExceptionStorageKey(profileId: BrowserProfileId, siteKey: string): string {
    const normalizedSiteKey = this.normalizeHttpFallbackSiteKey(siteKey);
    if (normalizedSiteKey.length === 0) {
      return '';
    }
    return `${normalizeBrowserProfileId(profileId)}|${normalizedSiteKey}`;
  }

  private normalizeHttpFallbackSiteKey(siteKey: string): string {
    return String(siteKey ?? '').trim().toLowerCase();
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences): preferences.Preferences => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

export const sharedBrowserWebSecuritySettingsRepository: BrowserWebSecuritySettingsRepository =
  new BrowserWebSecuritySettingsRepository();
