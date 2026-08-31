import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { SiteIconPixelMapCacheService } from './SiteIconPixelMapCacheService';

interface HomeRecentlyClosedPreparedIconInFlightEntry {
  key: string;
  promise: Promise<HomeRecentlyClosedPreparedIconResult | undefined>;
}

export interface HomeRecentlyClosedPreparedIconResult {
  uri: string;
  pixelMap?: image.PixelMap;
}

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'HomeRecentlyClosedPreparedIcon';
const PREPARED_ICON_DIR_NAME: string = 'home-recently-closed-icons';
const PREPARED_ICON_FILE_PREFIX: string = 'aira_recently_closed_icon_';
const PREPARED_ICON_DECODE_SIZE: number = 72;
const PREPARED_ICON_PACK_BUFFER_SIZE: number = 512 * 1024;

export class HomeRecentlyClosedPreparedIconService {
  private static sharedInFlightEntries: HomeRecentlyClosedPreparedIconInFlightEntry[] = [];
  private readonly pixelMapCacheService: SiteIconPixelMapCacheService;

  constructor(pixelMapCacheService: SiteIconPixelMapCacheService = new SiteIconPixelMapCacheService()) {
    this.pixelMapCacheService = pixelMapCacheService;
  }

  isPreparedIconUri(uri: string): boolean {
    const path = this.toLocalFilePath(uri);
    return path.includes(`/${PREPARED_ICON_DIR_NAME}/${PREPARED_ICON_FILE_PREFIX}`);
  }

  async prepareIconUri(sourceUri: string): Promise<HomeRecentlyClosedPreparedIconResult | undefined> {
    const sourcePath = this.toLocalFilePath(sourceUri);
    if (sourcePath.length === 0 || !AppRuntimeContext.hasApplicationContext()) {
      return undefined;
    }

    const targetPath = this.buildPreparedIconPath(sourceUri);
    const targetUri = this.toImageUri(targetPath);
    if (this.normalizePath(sourcePath) === this.normalizePath(targetPath)) {
      const existingPixelMap = await this.pixelMapCacheService.prewarmIconUri(targetUri, PREPARED_ICON_DECODE_SIZE);
      return existingPixelMap === undefined ? undefined : {
        uri: targetUri,
        pixelMap: existingPixelMap
      };
    }
    if (await this.exists(targetPath)) {
      const existingPixelMap = await this.pixelMapCacheService.prewarmIconUri(targetUri, PREPARED_ICON_DECODE_SIZE);
      return {
        uri: targetUri,
        pixelMap: existingPixelMap
      };
    }

    const key = `${sourcePath}|${targetPath}`;
    const inFlight = HomeRecentlyClosedPreparedIconService.sharedInFlightEntries
      .find((entry: HomeRecentlyClosedPreparedIconInFlightEntry) => entry.key === key);
    if (inFlight !== undefined) {
      return inFlight.promise;
    }

    const promise = this.prepareIconUriInternal(sourcePath, targetPath)
      .finally(() => {
        HomeRecentlyClosedPreparedIconService.sharedInFlightEntries =
          HomeRecentlyClosedPreparedIconService.sharedInFlightEntries
            .filter((entry: HomeRecentlyClosedPreparedIconInFlightEntry) => entry.key !== key);
      });
    HomeRecentlyClosedPreparedIconService.sharedInFlightEntries =
      HomeRecentlyClosedPreparedIconService.sharedInFlightEntries.concat([{
        key: key,
        promise: promise
      }]);
    return promise;
  }

  private async prepareIconUriInternal(
    sourcePath: string,
    targetPath: string
  ): Promise<HomeRecentlyClosedPreparedIconResult | undefined> {
    const startedAt = Date.now();
    try {
      if (!await this.exists(sourcePath)) {
        return undefined;
      }
      const sourcePixelMap = await this.pixelMapCacheService.prewarmIconUri(
        this.toImageUri(sourcePath),
        PREPARED_ICON_DECODE_SIZE
      );
      if (sourcePixelMap === undefined) {
        return undefined;
      }

      await this.ensureDirectory(this.getPreparedIconDir());
      const data = await this.packPixelMap(sourcePixelMap);
      if (data.byteLength === 0) {
        return undefined;
      }
      await this.writeBytes(targetPath, data);
      const targetUri = this.toImageUri(targetPath);
      const targetPixelMap = await this.pixelMapCacheService.prewarmIconUri(targetUri, PREPARED_ICON_DECODE_SIZE);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'prepare result=ok target=%{public}s durationMs=%{public}d',
        targetUri, Date.now() - startedAt);
      return {
        uri: targetUri,
        pixelMap: targetPixelMap
      };
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'prepare result=failed durationMs=%{public}d error=%{public}s',
        Date.now() - startedAt, JSON.stringify(error));
      return undefined;
    }
  }

  private async packPixelMap(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    const packer = image.createImagePacker();
    try {
      return await packer.packToData(pixelMap, {
        format: 'image/png',
        quality: 100,
        bufferSize: PREPARED_ICON_PACK_BUFFER_SIZE
      });
    } finally {
      try {
        await packer.release();
      } catch (_error) {
      }
    }
  }

  private async writeBytes(path: string, data: ArrayBuffer): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, data);
    } finally {
      await fileIo.close(file);
    }
  }

  private async ensureDirectory(path: string): Promise<void> {
    if (await this.exists(path)) {
      return;
    }
    await fileIo.mkdir(path, true);
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (_error) {
      return false;
    }
  }

  private buildPreparedIconPath(sourceUri: string): string {
    return `${this.getPreparedIconDir()}/${PREPARED_ICON_FILE_PREFIX}${this.hashSourceUri(sourceUri)}.png`;
  }

  private getPreparedIconDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${PREPARED_ICON_DIR_NAME}`;
  }

  private hashSourceUri(sourceUri: string): string {
    const normalized = sourceUri.trim();
    let hash = 2166136261;
    for (let index = 0; index < normalized.length; index += 1) {
      hash = hash ^ normalized.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(36);
  }

  private toImageUri(path: string): string {
    if (path.startsWith('file://')) {
      return path;
    }
    return `file://${path}`;
  }

  private toLocalFilePath(uri: string): string {
    const normalized = uri.trim();
    if (normalized.startsWith('file://')) {
      return normalized.substring(7);
    }
    if (normalized.startsWith('/')) {
      return normalized;
    }
    return '';
  }

  private normalizePath(path: string): string {
    return this.toLocalFilePath(path).trim();
  }
}
