import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  NovelReadingRecoveryMarkerPort,
  NovelReadingRecoveryMarkerRecord
} from '../../features/novel/NovelReaderModels';

const PREFERENCES_NAME: string = 'aira_novel_reading_recovery';
const PREFERENCES_KEY_PREFIX: string = 'regular_suspended_session:';
const MAX_ID_LENGTH: number = 1024;
const MAX_TITLE_LENGTH: number = 240;
const MAX_URL_LENGTH: number = 4096;

/** Regular-profile-only marker. It stores identity and destination, never extracted body content. */
export class NovelReadingRecoveryMarkerRepository implements NovelReadingRecoveryMarkerPort {
  private readonly markerKey: string;
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  constructor(windowId: string) {
    const normalizedWindowId = windowId.trim();
    if (normalizedWindowId.length === 0) {
      throw new Error('Novel reading recovery marker requires a Browser Window Session id.');
    }
    this.markerKey = `${PREFERENCES_KEY_PREFIX}${normalizedWindowId}`;
  }

  async load(): Promise<NovelReadingRecoveryMarkerRecord | undefined> {
    const store = await this.getStore();
    const rawValue = String(store.getSync(this.markerKey, ''));
    if (rawValue.length === 0) {
      return undefined;
    }
    try {
      const marker = this.normalize(JSON.parse(rawValue) as NovelReadingRecoveryMarkerRecord);
      if (marker !== undefined) {
        return marker;
      }
    } catch (_error) {
    }
    store.deleteSync(this.markerKey);
    await store.flush();
    return undefined;
  }

  async save(value: NovelReadingRecoveryMarkerRecord): Promise<void> {
    const marker = this.normalize(value);
    if (marker === undefined) {
      return;
    }
    const store = await this.getStore();
    store.putSync(this.markerKey, JSON.stringify(marker));
    await store.flush();
  }

  async clear(): Promise<void> {
    const store = await this.getStore();
    store.deleteSync(this.markerKey);
    await store.flush();
  }

  private normalize(value: NovelReadingRecoveryMarkerRecord): NovelReadingRecoveryMarkerRecord | undefined {
    if (typeof value.bookIdentity !== 'string' || value.bookIdentity.length === 0 ||
      value.bookIdentity.length > MAX_ID_LENGTH || typeof value.sourcePageUrl !== 'string' ||
      value.sourcePageUrl.length === 0 || value.sourcePageUrl.length > MAX_URL_LENGTH ||
      !value.sourcePageUrl.startsWith('http')) {
      return undefined;
    }
    return {
      bookIdentity: value.bookIdentity,
      bookTitle: typeof value.bookTitle === 'string'
        ? value.bookTitle.trim().substring(0, MAX_TITLE_LENGTH)
        : '',
      sourceTabId: typeof value.sourceTabId === 'string'
        ? value.sourceTabId.trim().substring(0, MAX_ID_LENGTH)
        : '',
      sourcePageUrl: value.sourcePageUrl,
      updatedAt: Math.max(0, Math.floor(Number.isFinite(value.updatedAt) ? value.updatedAt : 0))
    };
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getUIAbilityContext(),
        PREFERENCES_NAME
      ).then((store: preferences.Preferences): preferences.Preferences => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }
}
