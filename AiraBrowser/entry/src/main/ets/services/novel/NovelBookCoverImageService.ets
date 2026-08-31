import { image } from '@kit.ImageKit';
import {
  NovelBookCoverCacheStore,
  NOVEL_BOOK_COVER_CACHE_MAX_FILE_BYTES,
  sharedNovelBookCoverCacheStore
} from '../../data/novel/NovelBookCoverCacheStore';
import {
  NovelBookCoverRequestService,
  sharedNovelBookCoverRequestService
} from './NovelBookCoverRequestService';

interface NovelBookCoverMemoryEntry {
  key: string;
  payload: ArrayBuffer;
  lastUsedAt: number;
  persisted: boolean;
}

interface NovelBookCoverInFlightEntry {
  key: string;
  promise: Promise<ArrayBuffer | undefined>;
}

const BOOKSHELF_COVER_DECODE_WIDTH: number = 216;
const BOOKSHELF_COVER_DECODE_HEIGHT: number = 300;
const BOOKSHELF_COVER_PACK_QUALITY: number = 84;
const BOOKSHELF_COVER_MEMORY_MAX_ENTRIES: number = 32;

export class NovelBookCoverImageService {
  private readonly requestService: NovelBookCoverRequestService;
  private readonly cacheStore: NovelBookCoverCacheStore;
  private memoryEntries: NovelBookCoverMemoryEntry[] = [];
  private inFlightEntries: NovelBookCoverInFlightEntry[] = [];

  constructor(
    requestService: NovelBookCoverRequestService = sharedNovelBookCoverRequestService,
    cacheStore: NovelBookCoverCacheStore = sharedNovelBookCoverCacheStore
  ) {
    this.requestService = requestService;
    this.cacheStore = cacheStore;
  }

  async load(
    coverUrl: string,
    detailUrl: string,
    persistentlyCached: boolean = false
  ): Promise<image.PixelMap | undefined> {
    const normalizedCoverUrl: string = coverUrl.trim();
    if (normalizedCoverUrl.length === 0) {
      return undefined;
    }
    let payload: ArrayBuffer | undefined = await this.resolvePayload(
      normalizedCoverUrl,
      detailUrl,
      persistentlyCached
    );
    if (payload === undefined) {
      return undefined;
    }
    let decoded: image.PixelMap | undefined = await this.decode(payload);
    if (decoded !== undefined) {
      return decoded;
    }

    this.forgetMemoryEntry(normalizedCoverUrl);
    if (persistentlyCached) {
      await this.cacheStore.remove(normalizedCoverUrl).catch((_error: Error): void => {});
    }
    payload = await this.resolvePayload(normalizedCoverUrl, detailUrl, persistentlyCached);
    if (payload === undefined) {
      return undefined;
    }
    decoded = await this.decode(payload);
    return decoded;
  }

  async warm(coverUrl: string, detailUrl: string): Promise<boolean> {
    const normalizedCoverUrl: string = coverUrl.trim();
    if (normalizedCoverUrl.length === 0) {
      return false;
    }
    return (await this.resolvePayload(normalizedCoverUrl, detailUrl, true)) !== undefined;
  }

  private async resolvePayload(
    coverUrl: string,
    detailUrl: string,
    persistentlyCached: boolean
  ): Promise<ArrayBuffer | undefined> {
    const memoryEntry: NovelBookCoverMemoryEntry | undefined = this.readMemoryEntry(coverUrl);
    if (memoryEntry !== undefined) {
      if (persistentlyCached && !memoryEntry.persisted) {
        await this.persistPayload(coverUrl, memoryEntry.payload);
      }
      return memoryEntry.payload;
    }
    const inFlight: NovelBookCoverInFlightEntry | undefined = this.inFlightEntries
      .find((entry: NovelBookCoverInFlightEntry): boolean => entry.key === coverUrl);
    if (inFlight !== undefined) {
      const payload: ArrayBuffer | undefined = await inFlight.promise;
      if (persistentlyCached && payload !== undefined) {
        await this.persistPayload(coverUrl, payload);
      }
      return payload;
    }
    const promise: Promise<ArrayBuffer | undefined> = this.loadPersistedOrRemote(
      coverUrl,
      detailUrl,
      persistentlyCached
    )
      .finally((): void => {
        this.inFlightEntries = this.inFlightEntries
          .filter((entry: NovelBookCoverInFlightEntry): boolean => entry.key !== coverUrl);
      });
    this.inFlightEntries = this.inFlightEntries.concat([{
      key: coverUrl,
      promise: promise
    }]);
    return promise;
  }

  private async loadPersistedOrRemote(
    coverUrl: string,
    detailUrl: string,
    persistentlyCached: boolean
  ): Promise<ArrayBuffer | undefined> {
    if (persistentlyCached) {
      const persisted: ArrayBuffer | undefined = await this.cacheStore.read(coverUrl)
        .catch((_error: Error): undefined => undefined);
      if (persisted !== undefined) {
        this.rememberPayload(coverUrl, persisted, true);
        return persisted;
      }
    }
    const candidates: string[] = this.requestService.resolveCoverCandidates(coverUrl, detailUrl);
    for (let index: number = 0; index < candidates.length; index += 1) {
      try {
        const payload: ArrayBuffer = await this.requestService.downloadCandidate(candidates[index], detailUrl);
        const thumbnail: ArrayBuffer | undefined = await this.createThumbnailPayload(payload);
        if (thumbnail !== undefined) {
          let persisted: boolean = false;
          if (persistentlyCached) {
            try {
              await this.cacheStore.write(coverUrl, thumbnail);
              persisted = true;
            } catch (_error) {
            }
          }
          this.rememberPayload(coverUrl, thumbnail, persisted);
          return thumbnail;
        }
      } catch (_error) {
        // 继续尝试下一个安全候选。
      }
    }
    return undefined;
  }

  private async createThumbnailPayload(payload: ArrayBuffer): Promise<ArrayBuffer | undefined> {
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    const packer = image.createImagePacker();
    try {
      imageSource = image.createImageSource(payload);
      pixelMap = await imageSource.createPixelMap({
        index: 0,
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: BOOKSHELF_COVER_DECODE_WIDTH,
          height: BOOKSHELF_COVER_DECODE_HEIGHT
        }
      });
      const packed: ArrayBuffer = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: BOOKSHELF_COVER_PACK_QUALITY,
        bufferSize: NOVEL_BOOK_COVER_CACHE_MAX_FILE_BYTES
      });
      return packed.byteLength > 0 && packed.byteLength <= NOVEL_BOOK_COVER_CACHE_MAX_FILE_BYTES
        ? packed
        : undefined;
    } catch (_error) {
      return undefined;
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release().catch((_error: Error): void => {});
      }
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error): void => {});
      }
      await packer.release().catch((_error: Error): void => {});
    }
  }

  private async decode(payload: ArrayBuffer): Promise<image.PixelMap | undefined> {
    let imageSource: image.ImageSource | undefined = undefined;
    try {
      imageSource = image.createImageSource(payload);
      return await imageSource.createPixelMap({
        index: 0,
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: BOOKSHELF_COVER_DECODE_WIDTH,
          height: BOOKSHELF_COVER_DECODE_HEIGHT
        }
      });
    } catch (_error) {
      return undefined;
    } finally {
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error): void => {});
      }
    }
  }

  private async persistPayload(key: string, payload: ArrayBuffer): Promise<void> {
    try {
      await this.cacheStore.write(key, payload);
      const entry: NovelBookCoverMemoryEntry | undefined = this.memoryEntries
        .find((candidate: NovelBookCoverMemoryEntry): boolean => candidate.key === key);
      if (entry !== undefined) {
        entry.persisted = true;
      }
    } catch (_error) {
    }
  }

  private readMemoryEntry(key: string): NovelBookCoverMemoryEntry | undefined {
    const entry: NovelBookCoverMemoryEntry | undefined = this.memoryEntries
      .find((candidate: NovelBookCoverMemoryEntry): boolean => candidate.key === key);
    if (entry === undefined) {
      return undefined;
    }
    entry.lastUsedAt = Date.now();
    return entry;
  }

  private rememberPayload(key: string, payload: ArrayBuffer, persisted: boolean): void {
    this.forgetMemoryEntry(key);
    this.memoryEntries.push({
      key: key,
      payload: payload,
      lastUsedAt: Date.now(),
      persisted: persisted
    });
    this.memoryEntries.sort((left: NovelBookCoverMemoryEntry, right: NovelBookCoverMemoryEntry): number =>
      right.lastUsedAt - left.lastUsedAt);
    if (this.memoryEntries.length > BOOKSHELF_COVER_MEMORY_MAX_ENTRIES) {
      this.memoryEntries.splice(BOOKSHELF_COVER_MEMORY_MAX_ENTRIES);
    }
  }

  private forgetMemoryEntry(key: string): void {
    this.memoryEntries = this.memoryEntries
      .filter((entry: NovelBookCoverMemoryEntry): boolean => entry.key !== key);
  }
}

export const sharedNovelBookCoverImageService: NovelBookCoverImageService =
  new NovelBookCoverImageService();
