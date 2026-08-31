import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserProfileId,
  TabRecord
} from '../../common/models/BrowserModels';

const PREFERENCES_NAME: string = 'aira_site_clear_on_close_pending';
const PENDING_RECORDS_KEY_PREFIX: string = 'pending_records';
const MAX_PENDING_RECORDS: number = 80;

export class SiteClearOnClosePendingRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async replaceRecords(windowId: string, profileId: BrowserProfileId, records: TabRecord[]): Promise<void> {
    const store = await this.getStore();
    const key = this.buildKey(windowId, profileId);
    const payload = JSON.stringify(records.slice(-MAX_PENDING_RECORDS));
    store.putSync(key, payload);
    store.flushSync();
  }

  async consumeRecords(windowId: string, profileId: BrowserProfileId): Promise<TabRecord[]> {
    const store = await this.getStore();
    const key = this.buildKey(windowId, profileId);
    const records = this.parseRecords(String(store.getSync(key, '')));
    store.deleteSync(key);
    store.flushSync();
    return records;
  }

  private parseRecords(value: string): TabRecord[] {
    if (value.trim().length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as TabRecord[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .filter((record: TabRecord) => record !== undefined && record.id !== undefined && record.id.length > 0)
        .slice(-MAX_PENDING_RECORDS);
    } catch (_error) {
      return [];
    }
  }

  private buildKey(windowId: string, profileId: BrowserProfileId): string {
    return `${PENDING_RECORDS_KEY_PREFIX}_${this.normalizeKeyPart(windowId)}_${this.normalizeKeyPart(profileId)}`;
  }

  private normalizeKeyPart(value: string): string {
    return value.trim().replace(/[^a-zA-Z0-9_-]/g, '_');
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
