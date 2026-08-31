import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface SiteIconPixelMapCacheEntry {
  uri: string;
  pixelMap: image.PixelMap;
  decodeSize: number;
  lastUsedAt: number;
}

interface SiteIconPixelMapInFlightEntry {
  uri: string;
  decodeSize: number;
  generation: number;
  promise: Promise<image.PixelMap | undefined>;
}

interface SiteIconPixelMapGenerationEntry {
  uri: string;
  generation: number;
}

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'SiteIconPixelMapCache';
const MAX_ICON_PAYLOAD_BYTES: number = 1024 * 1024;
const MAX_MEMORY_PIXEL_MAPS: number = 160;
const DEFAULT_ICON_DECODE_SIZE: number = 72;

export class SiteIconPixelMapCacheService {
  private static sharedEntries: SiteIconPixelMapCacheEntry[] = [];
  private static sharedInFlightEntries: SiteIconPixelMapInFlightEntry[] = [];
  private static sharedGenerationEntries: SiteIconPixelMapGenerationEntry[] = [];

  getCachedPixelMap(uri: string): image.PixelMap | undefined {
    return this.getCachedPixelMapByUri(this.normalizeIconUri(uri));
  }

  invalidateIconUri(uri: string): void {
    const normalizedUri = this.normalizeIconUri(uri);
    if (normalizedUri.length === 0) {
      return;
    }
    const existing = SiteIconPixelMapCacheService.sharedEntries
      .find((entry: SiteIconPixelMapCacheEntry) => entry.uri === normalizedUri);
    if (existing !== undefined) {
      this.releasePixelMap(existing.pixelMap);
      SiteIconPixelMapCacheService.sharedEntries = SiteIconPixelMapCacheService.sharedEntries
        .filter((entry: SiteIconPixelMapCacheEntry) => entry.uri !== normalizedUri);
    }
    if (SiteIconPixelMapCacheService.sharedInFlightEntries
      .some((entry: SiteIconPixelMapInFlightEntry) => entry.uri === normalizedUri)) {
      this.bumpGeneration(normalizedUri);
    } else {
      this.clearGeneration(normalizedUri);
    }
  }

  async prewarmIconUri(uri: string, decodeSize: number = DEFAULT_ICON_DECODE_SIZE): Promise<image.PixelMap | undefined> {
    const normalizedUri = this.normalizeIconUri(uri);
    if (normalizedUri.length === 0) {
      return undefined;
    }
    const targetSize = this.normalizeDecodeSize(decodeSize);
    const generation = this.getGeneration(normalizedUri);

    const cached = this.getCachedPixelMapByUri(normalizedUri, targetSize);
    if (cached !== undefined) {
      return cached;
    }

    const inFlight = SiteIconPixelMapCacheService.sharedInFlightEntries
      .find((entry: SiteIconPixelMapInFlightEntry) => (
        entry.uri === normalizedUri && entry.generation === generation && entry.decodeSize >= targetSize
      ));
    if (inFlight !== undefined) {
      return inFlight.promise;
    }

    const startedAt = Date.now();
    const promise = this.decodeIconUri(normalizedUri, targetSize)
      .then((pixelMap: image.PixelMap | undefined) => {
        if (pixelMap === undefined) {
          return undefined;
        }
        if (this.getGeneration(normalizedUri) !== generation) {
          this.releasePixelMap(pixelMap);
          return undefined;
        }
        const retainedPixelMap = this.putPixelMap(normalizedUri, pixelMap, targetSize);
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'prewarm uri=%{public}s size=%{public}d result=decoded durationMs=%{public}d',
          normalizedUri, targetSize, Date.now() - startedAt);
        return retainedPixelMap;
      })
      .catch((error: Error) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'prewarm uri=%{public}s result=failed durationMs=%{public}d error=%{public}s',
          normalizedUri, Date.now() - startedAt, JSON.stringify(error));
        return undefined;
      })
      .finally(() => {
        SiteIconPixelMapCacheService.sharedInFlightEntries =
          SiteIconPixelMapCacheService.sharedInFlightEntries
            .filter((entry: SiteIconPixelMapInFlightEntry) => !(
              entry.uri === normalizedUri && entry.generation === generation && entry.decodeSize === targetSize
            ));
        this.clearGenerationWhenIdle(normalizedUri);
      });

    SiteIconPixelMapCacheService.sharedInFlightEntries =
      SiteIconPixelMapCacheService.sharedInFlightEntries.concat([{
        uri: normalizedUri,
        decodeSize: targetSize,
        generation: generation,
        promise: promise
      }]);
    return promise;
  }

  private getCachedPixelMapByUri(uri: string, minimumDecodeSize: number = 0): image.PixelMap | undefined {
    if (uri.length === 0) {
      return undefined;
    }
    const index = SiteIconPixelMapCacheService.sharedEntries
      .findIndex((entry: SiteIconPixelMapCacheEntry) => entry.uri === uri);
    if (index < 0) {
      return undefined;
    }
    const entry = SiteIconPixelMapCacheService.sharedEntries[index];
    if (minimumDecodeSize > 0 && entry.decodeSize < minimumDecodeSize) {
      return undefined;
    }
    entry.lastUsedAt = Date.now();
    if (index < SiteIconPixelMapCacheService.sharedEntries.length - 1) {
      SiteIconPixelMapCacheService.sharedEntries =
        SiteIconPixelMapCacheService.sharedEntries
          .filter((item: SiteIconPixelMapCacheEntry) => item.uri !== uri)
          .concat([entry]);
    }
    return entry.pixelMap;
  }

  private putPixelMap(uri: string, pixelMap: image.PixelMap, decodeSize: number): image.PixelMap {
    const existing = SiteIconPixelMapCacheService.sharedEntries
      .find((entry: SiteIconPixelMapCacheEntry) => entry.uri === uri);
    if (existing !== undefined) {
      if (existing.decodeSize >= decodeSize) {
        if (existing.pixelMap !== pixelMap) {
          this.releasePixelMap(pixelMap);
        }
        existing.lastUsedAt = Date.now();
        return existing.pixelMap;
      }
      if (existing.pixelMap !== pixelMap) {
        this.releasePixelMap(existing.pixelMap);
      }
      SiteIconPixelMapCacheService.sharedEntries =
        SiteIconPixelMapCacheService.sharedEntries
          .filter((entry: SiteIconPixelMapCacheEntry) => entry.uri !== uri);
    }
    SiteIconPixelMapCacheService.sharedEntries =
      SiteIconPixelMapCacheService.sharedEntries.concat([{
      uri: uri,
      pixelMap: pixelMap,
      decodeSize: decodeSize,
      lastUsedAt: Date.now()
    }]);
    this.trimMemoryCache();
    return pixelMap;
  }

  private trimMemoryCache(): void {
    if (SiteIconPixelMapCacheService.sharedEntries.length <= MAX_MEMORY_PIXEL_MAPS) {
      return;
    }
    const sorted = SiteIconPixelMapCacheService.sharedEntries.slice()
      .sort((left: SiteIconPixelMapCacheEntry, right: SiteIconPixelMapCacheEntry) => {
        return right.lastUsedAt - left.lastUsedAt;
      });
    const retained = sorted.slice(0, MAX_MEMORY_PIXEL_MAPS);
    const retainedUris: Record<string, boolean> = {};
    retained.forEach((entry: SiteIconPixelMapCacheEntry) => {
      retainedUris[entry.uri] = true;
    });
    SiteIconPixelMapCacheService.sharedEntries.forEach((entry: SiteIconPixelMapCacheEntry) => {
      if (retainedUris[entry.uri] !== true) {
        this.releasePixelMap(entry.pixelMap);
      }
    });
    SiteIconPixelMapCacheService.sharedEntries = retained;
  }

  private async decodeIconUri(uri: string, decodeSize: number): Promise<image.PixelMap | undefined> {
    const path = this.toLocalFilePath(uri);
    if (path.length === 0) {
      return undefined;
    }
    const payload = await this.readIconPayload(path);
    if (payload.byteLength === 0) {
      return undefined;
    }
    let imageSource: image.ImageSource | undefined = undefined;
    try {
      imageSource = image.createImageSource(payload);
      const targetSize = this.normalizeDecodeSize(decodeSize);
      return await imageSource.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: targetSize,
          height: targetSize
        }
      });
    } finally {
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error) => {});
      }
    }
  }

  private async readIconPayload(path: string): Promise<ArrayBuffer> {
    const stat = await fileIo.stat(path);
    const size = Math.max(0, Math.floor(stat.size));
    if (stat.isDirectory() || size <= 0 || size > MAX_ICON_PAYLOAD_BYTES) {
      return new ArrayBuffer(0);
    }
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(size);
      const readLength = await fileIo.read(file.fd, data);
      if (readLength !== size) {
        return data.slice(0, Math.max(0, readLength));
      }
      return data;
    } finally {
      await fileIo.close(file);
    }
  }

  private normalizeIconUri(uri: string): string {
    return uri.trim();
  }

  private normalizeDecodeSize(size: number): number {
    return Math.max(24, Math.min(160, Math.round(size)));
  }

  private getGeneration(uri: string): number {
    const entry = SiteIconPixelMapCacheService.sharedGenerationEntries
      .find((item: SiteIconPixelMapGenerationEntry) => item.uri === uri);
    return entry?.generation ?? 0;
  }

  private bumpGeneration(uri: string): void {
    const currentGeneration = this.getGeneration(uri);
    SiteIconPixelMapCacheService.sharedGenerationEntries =
      SiteIconPixelMapCacheService.sharedGenerationEntries
        .filter((entry: SiteIconPixelMapGenerationEntry) => entry.uri !== uri)
        .concat([{
          uri: uri,
          generation: currentGeneration + 1
        }]);
  }

  private clearGenerationWhenIdle(uri: string): void {
    if (SiteIconPixelMapCacheService.sharedInFlightEntries
      .some((entry: SiteIconPixelMapInFlightEntry) => entry.uri === uri)) {
      return;
    }
    this.clearGeneration(uri);
  }

  private clearGeneration(uri: string): void {
    SiteIconPixelMapCacheService.sharedGenerationEntries =
      SiteIconPixelMapCacheService.sharedGenerationEntries
        .filter((entry: SiteIconPixelMapGenerationEntry) => entry.uri !== uri);
  }

  private toLocalFilePath(uri: string): string {
    const normalizedUri = uri.trim();
    if (normalizedUri.startsWith('file://')) {
      return normalizedUri.substring(7);
    }
    if (normalizedUri.startsWith('/')) {
      return normalizedUri;
    }
    return '';
  }

  private releasePixelMap(pixelMap: image.PixelMap): void {
    void pixelMap.release().catch((_error: Error) => {});
  }
}
