import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  NovelReadingCheckpointPort,
  NovelReadingCheckpointRecord
} from '../../features/novel/NovelReaderModels';
import {
  isValidNovelHttpUrl,
  normalizeNovelDetailUrl
} from '../../features/novel/NovelLibraryModels';

const PREFERENCES_NAME: string = 'aira_novel_reading_checkpoint';
const PREFERENCES_KEY: string = 'checkpoints_by_book';
const MAX_URL_LENGTH: number = 4096;
const MAX_ID_LENGTH: number = 512;
const MAX_TITLE_LENGTH: number = 240;
const MAX_CHECKPOINTS: number = 200;

export type NovelReadingCheckpointChangeOrigin = 'local' | 'sync';
export type NovelReadingCheckpointChangeHandler = (origin: NovelReadingCheckpointChangeOrigin) => void;

/** 只保存可重新校验的恢复锚点，不缓存正文。 */
export class NovelReadingCheckpointRepository implements NovelReadingCheckpointPort {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private mutationTask: Promise<void> = Promise.resolve();
  private changeHandler?: NovelReadingCheckpointChangeHandler;

  setChangeHandler(handler?: NovelReadingCheckpointChangeHandler): void {
    this.changeHandler = handler;
  }

  async load(bookId: string): Promise<NovelReadingCheckpointRecord | undefined> {
    if (bookId.length === 0) {
      return undefined;
    }
    await this.waitForMutations();
    const records: NovelReadingCheckpointRecord[] = await this.readRecords();
    for (let index: number = 0; index < records.length; index += 1) {
      if (records[index].bookId === bookId) {
        return this.cloneRecord(records[index]);
      }
    }
    return undefined;
  }

  async loadByBookDetailUrl(bookDetailUrl: string): Promise<NovelReadingCheckpointRecord | undefined> {
    const normalizedUrl: string = normalizeNovelDetailUrl(bookDetailUrl);
    if (normalizedUrl.length === 0) {
      return undefined;
    }
    await this.waitForMutations();
    const records: NovelReadingCheckpointRecord[] = await this.readRecords();
    let selected: NovelReadingCheckpointRecord | undefined = undefined;
    for (let index: number = 0; index < records.length; index += 1) {
      const record: NovelReadingCheckpointRecord = records[index];
      if (record.bookDetailUrl === normalizedUrl &&
        (selected === undefined || this.compareRecords(record, selected) > 0)) {
        selected = record;
      }
    }
    return selected === undefined ? undefined : this.cloneRecord(selected);
  }

  async listSyncable(): Promise<NovelReadingCheckpointRecord[]> {
    await this.waitForMutations();
    const records: NovelReadingCheckpointRecord[] = await this.readRecords();
    return records
      .filter((record: NovelReadingCheckpointRecord): boolean =>
        record.bookDetailUrl.length > 0 && record.updatedAt > 0)
      .map((record: NovelReadingCheckpointRecord): NovelReadingCheckpointRecord => this.cloneRecord(record));
  }

  save(value: NovelReadingCheckpointRecord): Promise<void> {
    const normalized: NovelReadingCheckpointRecord | undefined = this.normalize(value);
    if (normalized === undefined) {
      return Promise.resolve();
    }
    return this.enqueueMutation('local', (records: NovelReadingCheckpointRecord[]): NovelReadingCheckpointRecord[] | undefined => {
      const existing: NovelReadingCheckpointRecord | undefined = records.find(
        (record: NovelReadingCheckpointRecord): boolean => record.bookId === normalized.bookId ||
          (normalized.bookDetailUrl.length > 0 && record.bookDetailUrl === normalized.bookDetailUrl)
      );
      if (existing !== undefined && this.compareRecords(normalized, existing) <= 0) {
        return undefined;
      }
      const next: NovelReadingCheckpointRecord[] = records.filter(
        (record: NovelReadingCheckpointRecord): boolean => record.bookId !== normalized.bookId &&
          (normalized.bookDetailUrl.length === 0 || record.bookDetailUrl !== normalized.bookDetailUrl)
      );
      next.push(normalized);
      if (JSON.stringify(this.sortAndLimit(records)) === JSON.stringify(this.sortAndLimit(next))) {
        return undefined;
      }
      return next;
    });
  }

  applySynced(values: NovelReadingCheckpointRecord[]): Promise<void> {
    const normalizedValues: NovelReadingCheckpointRecord[] = [];
    for (let index: number = 0; index < values.length; index += 1) {
      const normalized: NovelReadingCheckpointRecord | undefined = this.normalize(values[index]);
      if (normalized === undefined || normalized.bookDetailUrl.length === 0 || normalized.updatedAt <= 0) {
        return Promise.reject(new Error('novel-reading-progress-sync-local-invalid'));
      }
      normalizedValues.push(normalized);
    }
    return this.enqueueMutation('sync', (records: NovelReadingCheckpointRecord[]): NovelReadingCheckpointRecord[] | undefined => {
      const next: NovelReadingCheckpointRecord[] = records.slice();
      let changed: boolean = false;
      for (let index: number = 0; index < normalizedValues.length; index += 1) {
        const incoming: NovelReadingCheckpointRecord = normalizedValues[index];
        const existingIndex: number = next.findIndex(
          (record: NovelReadingCheckpointRecord): boolean => record.bookDetailUrl === incoming.bookDetailUrl
        );
        if (existingIndex < 0) {
          next.push(incoming);
          changed = true;
        } else if (this.compareRecords(incoming, next[existingIndex]) > 0) {
          next[existingIndex] = incoming;
          changed = true;
        }
      }
      return changed ? next : undefined;
    });
  }

  clear(bookId: string): Promise<void> {
    if (bookId.length === 0) {
      return Promise.resolve();
    }
    return this.enqueueMutation('local', (records: NovelReadingCheckpointRecord[]): NovelReadingCheckpointRecord[] | undefined => {
      const next: NovelReadingCheckpointRecord[] = records.filter(
        (record: NovelReadingCheckpointRecord): boolean => record.bookId !== bookId
      );
      return next.length === records.length ? undefined : next;
    });
  }

  private enqueueMutation(
    origin: NovelReadingCheckpointChangeOrigin,
    mutation: (records: NovelReadingCheckpointRecord[]) => NovelReadingCheckpointRecord[] | undefined
  ): Promise<void> {
    const operation: Promise<void> = this.mutationTask
      .catch((_error: Error): void => {})
      .then(async (): Promise<void> => {
        const records: NovelReadingCheckpointRecord[] = await this.readRecords();
        const next: NovelReadingCheckpointRecord[] | undefined = mutation(records);
        if (next === undefined) {
          return;
        }
        await this.writeRecords(next);
        this.changeHandler?.(origin);
      });
    this.mutationTask = operation.catch((_error: Error): void => {});
    return operation;
  }

  private async waitForMutations(): Promise<void> {
    await this.mutationTask.catch((_error: Error): void => {});
  }

  private async readRecords(): Promise<NovelReadingCheckpointRecord[]> {
    const store = await this.getStore();
    const rawValue: string = String(store.getSync(PREFERENCES_KEY, ''));
    if (rawValue.length === 0) {
      return [];
    }
    try {
      const parsed: NovelReadingCheckpointRecord[] = JSON.parse(rawValue) as NovelReadingCheckpointRecord[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const records: NovelReadingCheckpointRecord[] = [];
      for (let index: number = 0; index < parsed.length; index += 1) {
        const normalized: NovelReadingCheckpointRecord | undefined = this.normalize(parsed[index]);
        if (normalized !== undefined) {
          records.push(normalized);
        }
      }
      return this.sortAndLimit(records);
    } catch (_error) {
      store.deleteSync(PREFERENCES_KEY);
      await store.flush();
      return [];
    }
  }

  private async writeRecords(records: NovelReadingCheckpointRecord[]): Promise<void> {
    const store = await this.getStore();
    const normalized: NovelReadingCheckpointRecord[] = this.sortAndLimit(records);
    if (normalized.length === 0) {
      store.deleteSync(PREFERENCES_KEY);
    } else {
      store.putSync(PREFERENCES_KEY, JSON.stringify(normalized));
    }
    await store.flush();
  }

  private sortAndLimit(records: NovelReadingCheckpointRecord[]): NovelReadingCheckpointRecord[] {
    return records
      .map((record: NovelReadingCheckpointRecord): NovelReadingCheckpointRecord => this.cloneRecord(record))
      .sort((left: NovelReadingCheckpointRecord, right: NovelReadingCheckpointRecord): number => {
        if (left.updatedAt !== right.updatedAt) {
          return right.updatedAt - left.updatedAt;
        }
        return left.bookId.localeCompare(right.bookId);
      })
      .slice(0, MAX_CHECKPOINTS);
  }

  private compareRecords(left: NovelReadingCheckpointRecord, right: NovelReadingCheckpointRecord): number {
    if (left.updatedAt !== right.updatedAt) {
      return left.updatedAt - right.updatedAt;
    }
    return this.portableFingerprint(left).localeCompare(this.portableFingerprint(right));
  }

  private portableFingerprint(value: NovelReadingCheckpointRecord): string {
    return JSON.stringify({
      bookId: value.bookDetailUrl,
      sessionBookId: value.bookId,
      chapterId: value.chapterId,
      chapterUrl: value.canonicalUrl,
      chapterTitle: value.chapterTitle,
      characterOffset: value.characterOffset,
      updatedAt: value.updatedAt
    });
  }

  private normalize(value: NovelReadingCheckpointRecord): NovelReadingCheckpointRecord | undefined {
    const bookDetailUrl: string = normalizeNovelDetailUrl(String(value?.bookDetailUrl ?? ''));
    if (typeof value?.bookId !== 'string' || value.bookId.length === 0 || value.bookId.length > MAX_ID_LENGTH ||
      typeof value.chapterId !== 'string' || value.chapterId.length === 0 || value.chapterId.length > MAX_ID_LENGTH ||
      typeof value.canonicalUrl !== 'string' || value.canonicalUrl.length === 0 ||
      value.canonicalUrl.length > MAX_URL_LENGTH || !isValidNovelHttpUrl(value.canonicalUrl) ||
      (bookDetailUrl.length > 0 && (!isValidNovelHttpUrl(bookDetailUrl) || bookDetailUrl.length > MAX_URL_LENGTH))) {
      return undefined;
    }
    return {
      bookId: value.bookId,
      bookDetailUrl: bookDetailUrl,
      chapterId: value.chapterId,
      canonicalUrl: value.canonicalUrl,
      chapterTitle: typeof value.chapterTitle === 'string'
        ? value.chapterTitle.trim().substring(0, MAX_TITLE_LENGTH)
        : '',
      characterOffset: Math.max(0, Math.floor(Number.isFinite(value.characterOffset) ? value.characterOffset : 0)),
      updatedAt: Math.max(0, Math.floor(Number.isFinite(value.updatedAt) ? value.updatedAt : 0))
    };
  }

  private cloneRecord(value: NovelReadingCheckpointRecord): NovelReadingCheckpointRecord {
    return {
      bookId: value.bookId,
      bookDetailUrl: value.bookDetailUrl,
      chapterId: value.chapterId,
      canonicalUrl: value.canonicalUrl,
      chapterTitle: value.chapterTitle,
      characterOffset: value.characterOffset,
      updatedAt: value.updatedAt
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

export const sharedNovelReadingCheckpointRepository: NovelReadingCheckpointRepository =
  new NovelReadingCheckpointRepository();
