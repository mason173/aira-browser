import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

export interface PrivateModeCookieSnapshotRecord {
  name: string;
  value: string;
  domain: string;
  path: string;
  expiresDate: string;
  isSessionCookie: boolean;
  isHttpOnly: boolean;
  isSecure: boolean;
  samesitePolicy: number;
  updatedAt: number;
}

export interface PrivateModeCookieSnapshot {
  updatedAt: number;
  cookies: PrivateModeCookieSnapshotRecord[];
}

const PREFERENCES_NAME: string = 'aira_private_mode_cookie_snapshot';
const SNAPSHOT_KEY: string = 'cookie_snapshot';
const MAX_COOKIE_SNAPSHOT_COUNT: number = 600;

export class PrivateModeCookieSnapshotRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async saveSnapshot(cookies: PrivateModeCookieSnapshotRecord[]): Promise<PrivateModeCookieSnapshot> {
    const snapshot: PrivateModeCookieSnapshot = {
      updatedAt: Date.now(),
      cookies: cookies.slice(-MAX_COOKIE_SNAPSHOT_COUNT)
    };
    const store = await this.getStore();
    store.putSync(SNAPSHOT_KEY, JSON.stringify(snapshot));
    store.flushSync();
    return this.copySnapshot(snapshot);
  }

  async readSnapshot(): Promise<PrivateModeCookieSnapshot> {
    const store = await this.getStore();
    return this.parseSnapshot(String(store.getSync(SNAPSHOT_KEY, '')));
  }

  async clearSnapshot(): Promise<void> {
    const store = await this.getStore();
    store.deleteSync(SNAPSHOT_KEY);
    store.flushSync();
  }

  private parseSnapshot(value: string): PrivateModeCookieSnapshot {
    if (value.trim().length === 0) {
      return this.buildEmptySnapshot();
    }
    try {
      const parsed = JSON.parse(value) as PrivateModeCookieSnapshot;
      if (!Array.isArray(parsed.cookies)) {
        return this.buildEmptySnapshot();
      }
      const normalizedCookies: PrivateModeCookieSnapshotRecord[] = [];
      parsed.cookies.forEach((cookie: PrivateModeCookieSnapshotRecord) => {
        const normalizedCookie = this.normalizeCookie(cookie);
        if (normalizedCookie !== undefined) {
          normalizedCookies.push(normalizedCookie);
        }
      });
      return {
        updatedAt: this.normalizeTimestamp(parsed.updatedAt),
        cookies: normalizedCookies.slice(-MAX_COOKIE_SNAPSHOT_COUNT)
      };
    } catch (_error) {
      return this.buildEmptySnapshot();
    }
  }

  private normalizeCookie(cookie: PrivateModeCookieSnapshotRecord | undefined): PrivateModeCookieSnapshotRecord | undefined {
    if (cookie === undefined) {
      return undefined;
    }
    const name = String(cookie.name ?? '').trim();
    const domain = String(cookie.domain ?? '').trim();
    if (name.length <= 0 || domain.length <= 0) {
      return undefined;
    }
    return {
      name: name,
      value: String(cookie.value ?? ''),
      domain: domain,
      path: String(cookie.path ?? '/').trim().length > 0 ? String(cookie.path ?? '/').trim() : '/',
      expiresDate: String(cookie.expiresDate ?? ''),
      isSessionCookie: cookie.isSessionCookie === true,
      isHttpOnly: cookie.isHttpOnly === true,
      isSecure: cookie.isSecure === true,
      samesitePolicy: typeof cookie.samesitePolicy === 'number' ? cookie.samesitePolicy : 0,
      updatedAt: this.normalizeTimestamp(cookie.updatedAt)
    };
  }

  private buildEmptySnapshot(): PrivateModeCookieSnapshot {
    return {
      updatedAt: 0,
      cookies: []
    };
  }

  private copySnapshot(snapshot: PrivateModeCookieSnapshot): PrivateModeCookieSnapshot {
    return {
      updatedAt: snapshot.updatedAt,
      cookies: snapshot.cookies.map((cookie: PrivateModeCookieSnapshotRecord) => {
        const copiedCookie: PrivateModeCookieSnapshotRecord = {
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          path: cookie.path,
          expiresDate: cookie.expiresDate,
          isSessionCookie: cookie.isSessionCookie,
          isHttpOnly: cookie.isHttpOnly,
          isSecure: cookie.isSecure,
          samesitePolicy: cookie.samesitePolicy,
          updatedAt: cookie.updatedAt
        };
        return copiedCookie;
      })
    };
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0;
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
}
