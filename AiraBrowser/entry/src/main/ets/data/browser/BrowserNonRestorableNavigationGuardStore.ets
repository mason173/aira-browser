import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const NON_RESTORABLE_NAVIGATION_GUARD_STORE_NAME = 'aira_browser_non_restorable_navigation_guard';
const NON_RESTORABLE_NAVIGATION_GUARD_KEY = 'non_restorable_navigation_sources';

export type BrowserNonRestorableNavigationDecision = 'download_candidate';

export interface BrowserNonRestorableNavigationGuardRecord {
  sourceKey: string;
  decision: BrowserNonRestorableNavigationDecision;
  fallbackUrl: string;
  updatedAt: number;
}

export interface BrowserNonRestorableNavigationGuardStore {
  loadRecords(): Promise<BrowserNonRestorableNavigationGuardRecord[]>;
  saveRecords(records: BrowserNonRestorableNavigationGuardRecord[]): Promise<void>;
}

export class ArkBrowserNonRestorableNavigationGuardStore implements BrowserNonRestorableNavigationGuardStore {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async loadRecords(): Promise<BrowserNonRestorableNavigationGuardRecord[]> {
    const store = await this.getStore();
    const rawValue = store.getSync(NON_RESTORABLE_NAVIGATION_GUARD_KEY, '[]');
    return this.parseRecords(String(rawValue));
  }

  async saveRecords(records: BrowserNonRestorableNavigationGuardRecord[]): Promise<void> {
    const store = await this.getStore();
    store.putSync(NON_RESTORABLE_NAVIGATION_GUARD_KEY, JSON.stringify(records));
    store.flushSync();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        NON_RESTORABLE_NAVIGATION_GUARD_STORE_NAME
      ).then((store: preferences.Preferences) => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }

  private parseRecords(value: string): BrowserNonRestorableNavigationGuardRecord[] {
    try {
      const parsed = JSON.parse(value) as BrowserNonRestorableNavigationGuardRecord[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .map((record: BrowserNonRestorableNavigationGuardRecord) => this.normalizeRecord(record))
        .filter((record?: BrowserNonRestorableNavigationGuardRecord) => {
          return record !== undefined;
        }) as BrowserNonRestorableNavigationGuardRecord[];
    } catch {
      return [];
    }
  }

  private normalizeRecord(
    record: BrowserNonRestorableNavigationGuardRecord
  ): BrowserNonRestorableNavigationGuardRecord | undefined {
    const sourceKey = String(record.sourceKey ?? '').trim();
    if (sourceKey.length <= 0 || record.decision !== 'download_candidate') {
      return undefined;
    }
    const updatedAt = Number(record.updatedAt);
    return {
      sourceKey: sourceKey,
      decision: 'download_candidate',
      fallbackUrl: String(record.fallbackUrl ?? '').trim(),
      updatedAt: Number.isFinite(updatedAt) && updatedAt > 0 ? updatedAt : Date.now()
    };
  }
}
