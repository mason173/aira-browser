import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { RecentlyClosedTabRecord } from '../../common/models/BrowserModels';

const PREFERENCES_NAME: string = 'aira_browser_recently_closed_snapshot';
const RECORDS_KEY_PREFIX: string = 'records';
const DEFAULT_WINDOW_ID: string = 'window-main';
const SNAPSHOT_LIMIT: number = 25;

interface RecentlyClosedTabSnapshotPayload {
  version: number;
  updatedAt: number;
  windowId: string;
  profileId: string;
  records: RecentlyClosedTabRecord[];
}

export class RecentlyClosedTabSnapshotStore {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async readRecords(windowId: string = DEFAULT_WINDOW_ID, profileId?: string): Promise<RecentlyClosedTabRecord[]> {
    if (!AppRuntimeContext.hasApplicationContext()) {
      return [];
    }
    const store = await this.getStore();
    const rawPayload = String(store.getSync(this.buildRecordsKey(windowId, profileId), ''));
    return this.parseRecords(rawPayload, windowId, profileId);
  }

  async writeRecords(
    records: RecentlyClosedTabRecord[],
    windowId: string = DEFAULT_WINDOW_ID,
    profileId?: string
  ): Promise<void> {
    if (!AppRuntimeContext.hasApplicationContext()) {
      return;
    }
    const normalizedWindowId = this.normalizeWindowId(windowId);
    const normalizedProfileId = this.normalizeProfileId(profileId);
    const payload: RecentlyClosedTabSnapshotPayload = {
      version: 1,
      updatedAt: Date.now(),
      windowId: normalizedWindowId,
      profileId: normalizedProfileId,
      records: this.normalizeRecords(records, normalizedWindowId, normalizedProfileId)
    };
    const store = await this.getStore();
    store.putSync(this.buildRecordsKey(normalizedWindowId, normalizedProfileId), JSON.stringify(payload));
    store.flushSync();
  }

  async clearRecords(windowId: string = DEFAULT_WINDOW_ID, profileId?: string): Promise<void> {
    if (!AppRuntimeContext.hasApplicationContext()) {
      return;
    }
    const store = await this.getStore();
    store.deleteSync(this.buildRecordsKey(windowId, profileId));
    store.flushSync();
  }

  async clearAllRecords(): Promise<void> {
    if (!AppRuntimeContext.hasApplicationContext()) {
      return;
    }
    const store = await this.getStore();
    store.clearSync();
    store.flushSync();
  }

  private parseRecords(rawPayload: string, windowId: string, profileId?: string): RecentlyClosedTabRecord[] {
    const trimmedPayload = rawPayload.trim();
    if (trimmedPayload.length === 0) {
      return [];
    }
    try {
      const payload = JSON.parse(trimmedPayload) as RecentlyClosedTabSnapshotPayload;
      return this.normalizeRecords(
        Array.isArray(payload.records) ? payload.records : [],
        this.normalizeWindowId(windowId),
        this.normalizeProfileId(profileId)
      );
    } catch (_error) {
      return [];
    }
  }

  private normalizeRecords(
    records: RecentlyClosedTabRecord[],
    windowId: string,
    profileId: string
  ): RecentlyClosedTabRecord[] {
    return records
      .filter((record: RecentlyClosedTabRecord) => this.isRecordForBoundary(record, windowId, profileId))
      .sort((left: RecentlyClosedTabRecord, right: RecentlyClosedTabRecord) => right.closedAt - left.closedAt)
      .slice(0, SNAPSHOT_LIMIT);
  }

  private isRecordForBoundary(record: RecentlyClosedTabRecord, windowId: string, profileId: string): boolean {
    if (record.windowId !== windowId) {
      return false;
    }
    const recordProfileId = typeof record.profileId === 'string' && record.profileId.trim().length > 0
      ? record.profileId.trim()
      : record.tab.profileId;
    return this.normalizeProfileId(recordProfileId) === profileId;
  }

  private buildRecordsKey(windowId: string, profileId?: string): string {
    return `${RECORDS_KEY_PREFIX}_${this.normalizeWindowId(windowId)}_${this.normalizeProfileId(profileId)}`;
  }

  private normalizeWindowId(windowId: string): string {
    const normalizedWindowId = windowId.trim();
    return normalizedWindowId.length > 0 ? normalizedWindowId : DEFAULT_WINDOW_ID;
  }

  private normalizeProfileId(profileId?: string): string {
    const normalizedProfileId = profileId?.trim() ?? '';
    return normalizedProfileId.length > 0 ? normalizedProfileId : 'profile-main';
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
