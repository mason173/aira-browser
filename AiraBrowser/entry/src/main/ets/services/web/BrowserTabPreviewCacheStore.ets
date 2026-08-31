import { fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserTabPreviewCaptureScope,
  BrowserTabPreviewCaptureSource,
  BrowserTabPreviewSourceRect,
  BrowserTabPreviewTransitionFrame,
  BrowserTabPreviewTransitionSource
} from './BrowserTabPreviewTypes';
import { sharedBrowserTabPreviewMetrics } from '../../core/browser/BrowserTabPreviewMetricsService';

const PREVIEW_IMAGE_CACHE_DIR_NAME: string = 'tab-preview-images';
const PREVIEW_IMAGE_CACHE_QUALITY: number = 80;
const PREVIEW_IMAGE_CACHE_BUFFER_SIZE: number = 8 * 1024 * 1024;
const SHARED_SNAPSHOT_METADATA_FILE_SUFFIX: string = '-shared-meta.json';
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TabPreviewCache';
export const DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID: string = 'window-main';

export interface BrowserTabPreviewCachedImageInfo {
  uri: string;
  width: number;
  height: number;
  transitionSource?: BrowserTabPreviewTransitionSource;
}

interface BrowserTabPreviewCachedImageSize {
  width: number;
  height: number;
  transitionSource?: BrowserTabPreviewTransitionSource;
}

interface BrowserTabPreviewSharedSnapshotMetadata {
  imageTimestamp: number;
  width: number;
  height: number;
  transitionSource?: BrowserTabPreviewTransitionSource;
}

export interface BrowserTabPreviewPersistedImageStats {
  uri?: string;
  bytes: number;
  packDurationMs?: number;
  writeDurationMs?: number;
  totalDurationMs?: number;
}

export interface BrowserTabPreviewCacheDirectoryStats {
  totalFiles: number;
  sharedFiles: number;
  totalBytes: number;
  sharedBytes: number;
}

export interface BrowserTabPreviewCacheRestoreIndex {
  infosByTabId: Record<string, BrowserTabPreviewCachedImageInfo | undefined>;
}

export interface BrowserTabPreviewIndexedImagePath {
  tabId: string;
  path: string;
  timestamp: number;
}

export interface BrowserTabPreviewCacheRestorePathIndex {
  latestPathsByTabId: Record<string, BrowserTabPreviewIndexedImagePath | undefined>;
}

export class BrowserTabPreviewCacheStore {
  private textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private scopeId: string = DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID;

  setScopeId(scopeId: string): void {
    const normalizedScopeId = this.sanitizeCacheSegment(scopeId);
    this.scopeId = normalizedScopeId.length > 0 ? normalizedScopeId : DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID;
  }

  async restoreSharedSnapshotImageInfo(tabId: string): Promise<BrowserTabPreviewCachedImageInfo | undefined> {
    const path = await this.findLatestPreviewImagePath(`${tabId}-shared`);
    if (path.length <= 0) {
      return undefined;
    }
    const imageTimestamp = this.parsePreviewTimestampFromPath(`${tabId}-shared`, path);
    const metadataSize = await this.readSharedSnapshotMetadata(tabId, imageTimestamp);
    const size = metadataSize ?? await this.readJpegImageSize(path);
    if (size === undefined) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'shared preview restore metadata missing tab=%{public}s path=%{public}s',
        tabId, path);
      return undefined;
    }
    return {
      uri: fileUri.getUriFromPath(path),
      width: size.width,
      height: size.height,
      transitionSource: size.transitionSource
    };
  }

  async buildSharedSnapshotRestoreIndex(tabIds: string[]): Promise<BrowserTabPreviewCacheRestoreIndex> {
    const pathIndex = await this.buildSharedSnapshotRestorePathIndex(tabIds);
    return await this.readSharedSnapshotRestoreIndex(pathIndex, tabIds);
  }

  async buildSharedSnapshotRestorePathIndex(tabIds: string[]): Promise<BrowserTabPreviewCacheRestorePathIndex> {
    const activeTabIds = this.buildActiveTabIdMap(tabIds);
    return {
      latestPathsByTabId: await this.findLatestSharedPreviewImagePaths(activeTabIds)
    };
  }

  async readSharedSnapshotRestoreIndex(
    pathIndex: BrowserTabPreviewCacheRestorePathIndex,
    tabIds: string[]
  ): Promise<BrowserTabPreviewCacheRestoreIndex> {
    const infosByTabId: Record<string, BrowserTabPreviewCachedImageInfo | undefined> = {};
    const activeTabIds = this.buildActiveTabIdMap(tabIds);
    const tabKeys = Object.keys(activeTabIds);
    for (let index = 0; index < tabKeys.length; index += 1) {
      const tabId = tabKeys[index];
      const indexedPath = pathIndex.latestPathsByTabId[tabId];
      const path = indexedPath?.path ?? '';
      if (path.length <= 0) {
        continue;
      }
      const metadataSize = await this.readSharedSnapshotMetadata(tabId, indexedPath?.timestamp ?? -1);
      const size = metadataSize ?? await this.readJpegImageSize(path);
      if (size === undefined) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'shared preview restore metadata missing tab=%{public}s path=%{public}s',
          tabId, path);
        continue;
      }
      infosByTabId[tabId] = {
        uri: fileUri.getUriFromPath(path),
        width: size.width,
        height: size.height,
        transitionSource: size.transitionSource
      };
    }
    return {
      infosByTabId: infosByTabId
    };
  }

  private buildActiveTabIdMap(tabIds: string[]): Record<string, boolean> {
    const activeTabIds: Record<string, boolean> = {};
    tabIds.forEach((tabId: string) => {
      const normalizedTabId = tabId.trim();
      if (normalizedTabId.length > 0) {
        activeTabIds[normalizedTabId] = true;
      }
    });
    return activeTabIds;
  }

  async removePreviewImage(tabId: string): Promise<boolean> {
    const dir = this.getPreviewImageCacheDir();
    let removed = false;
    let removedFileCount = 0;
    try {
      const files = await fileIo.listFile(dir);
      for (let index = 0; index < files.length; index += 1) {
        const fileName = files[index];
        if (!this.isPreviewImageFileForTab(fileName, tabId) &&
          !this.isPreviewImageFileForTab(fileName, `${tabId}-shared`)) {
          continue;
        }
        try {
          await fileIo.unlink(`${dir}/${fileName}`);
          removed = true;
          removedFileCount += 1;
        } catch (_error) {
        }
      }
    } catch (_error) {
    }
    const removedMetadata = await this.removeSharedSnapshotMetadata(tabId);
    if (removedMetadata) {
      removed = true;
    }
    if (removed) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'preview image cleanup tab=%{public}s removedFiles=%{public}d metadata=%{public}s',
        tabId, removedFileCount, `${removedMetadata}`);
    }
    return removed;
  }

  async clearAllPreviewImages(): Promise<boolean> {
    const dir = this.getPreviewImageCacheDir();
    let removed = false;
    let removedFileCount = 0;
    try {
      const files = await fileIo.listFile(dir);
      for (let index = 0; index < files.length; index += 1) {
        const fileName = files[index];
        if (!fileName.endsWith('.jpg') && !fileName.endsWith('.json')) {
          continue;
        }
        try {
          await fileIo.unlink(`${dir}/${fileName}`);
          removed = true;
          removedFileCount += 1;
        } catch (_error) {
        }
      }
    } catch (_error) {
    }
    if (removed) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'preview image cleanup all removedFiles=%{public}d', removedFileCount);
    }
    return removed;
  }

  async savePreviewImageWithStats(
    pixelMap: image.PixelMap,
    tabId: string,
    transitionSource: BrowserTabPreviewTransitionSource
  ): Promise<BrowserTabPreviewPersistedImageStats> {
    const startedAt = Date.now();
    const source = transitionSource.captureSource;
    try {
      await this.ensurePreviewImageCacheDir();
      const path = this.buildPreviewImagePath(tabId);
      const currentTimestamp = this.parsePreviewTimestampFromPath(tabId, path);
      const packStartedAt = Date.now();
      const packedData = await this.packPreviewImage(pixelMap);
      const packDurationMs = Date.now() - packStartedAt;
      const writeStartedAt = Date.now();
      const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, packedData);
      } finally {
        await fileIo.close(file);
      }
      const writeDurationMs = Date.now() - writeStartedAt;
      const uri = fileUri.getUriFromPath(path);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'preview image persisted tab=%{public}s source=%{public}s path=%{public}s uri=%{public}s bytes=%{public}d packMs=%{public}d writeMs=%{public}d totalMs=%{public}d',
        tabId, source, path, uri, packedData.byteLength, packDurationMs, writeDurationMs, Date.now() - startedAt);
      const sharedSnapshotMetadata = this.buildSharedSnapshotMetadataIfNeeded(
        tabId,
        pixelMap,
        currentTimestamp,
        transitionSource
      );
      if (sharedSnapshotMetadata !== undefined) {
        await this.persistSharedSnapshotMetadataIfNeeded(tabId, sharedSnapshotMetadata);
      }
      this.schedulePreviewImageCleanup(tabId, path, currentTimestamp);
      return {
        uri: uri,
        bytes: packedData.byteLength,
        packDurationMs: packDurationMs,
        writeDurationMs: writeDurationMs,
        totalDurationMs: Date.now() - startedAt
      };
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'preview image persist failed tab=%{public}s source=%{public}s error=%{public}s',
        tabId, source, JSON.stringify(error));
      return {
        bytes: 0,
        totalDurationMs: Date.now() - startedAt
      };
    }
  }

  async duplicateSharedSnapshotImage(
    sourceTabId: string,
    targetTabId: string,
    transitionSource: BrowserTabPreviewTransitionSource
  ): Promise<BrowserTabPreviewCachedImageInfo | undefined> {
    const sourcePath = await this.findLatestPreviewImagePath(`${sourceTabId}-shared`);
    if (sourcePath.length <= 0) {
      return undefined;
    }
    try {
      await this.ensurePreviewImageCacheDir();
      const targetCacheKey = `${targetTabId}-shared`;
      const targetPath = this.buildPreviewImagePath(targetCacheKey);
      const currentTimestamp = this.parsePreviewTimestampFromPath(targetCacheKey, targetPath);
      await fileIo.copyFile(sourcePath, targetPath);
      const sourceTimestamp = this.parsePreviewTimestampFromPath(`${sourceTabId}-shared`, sourcePath);
      const size = await this.readSharedSnapshotMetadata(sourceTabId, sourceTimestamp) ??
        await this.readJpegImageSize(sourcePath);
      if (size === undefined) {
        return undefined;
      }
      const metadata: BrowserTabPreviewSharedSnapshotMetadata = {
        imageTimestamp: currentTimestamp,
        width: size.width,
        height: size.height,
        transitionSource: this.normalizeTransitionSource({
          captureSource: transitionSource.captureSource,
          captureScope: transitionSource.captureScope,
          transitionFrame: transitionSource.transitionFrame,
          sourceRect: transitionSource.sourceRect ?? size.transitionSource?.sourceRect
        })
      };
      await this.persistSharedSnapshotMetadataIfNeeded(targetCacheKey, metadata);
      this.schedulePreviewImageCleanup(targetCacheKey, targetPath, currentTimestamp);
      return {
        uri: fileUri.getUriFromPath(targetPath),
        width: size.width,
        height: size.height,
        transitionSource: metadata.transitionSource
      };
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'shared preview duplicate failed sourceTab=%{public}s targetTab=%{public}s error=%{public}s',
        sourceTabId, targetTabId, JSON.stringify(error));
      return undefined;
    }
  }

  async captureCacheDirectoryStats(): Promise<BrowserTabPreviewCacheDirectoryStats> {
    const dir = this.getPreviewImageCacheDir();
    const stats: BrowserTabPreviewCacheDirectoryStats = {
      totalFiles: 0,
      sharedFiles: 0,
      totalBytes: 0,
      sharedBytes: 0
    };
    try {
      const files = await fileIo.listFile(dir);
      for (let index = 0; index < files.length; index += 1) {
        const fileName = files[index];
        if (!fileName.endsWith('.jpg')) {
          continue;
        }
        const path = `${dir}/${fileName}`;
        const size = await this.readFileSize(path);
        if (!this.isSharedPreviewImageFile(fileName)) {
          continue;
        }
        stats.totalFiles += 1;
        stats.totalBytes += size;
        stats.sharedFiles += 1;
        stats.sharedBytes += size;
      }
    } catch (_error) {
    }
    sharedBrowserTabPreviewMetrics.recordCacheSnapshot({
      totalFiles: stats.totalFiles,
      sharedFiles: stats.sharedFiles,
      totalBytes: stats.totalBytes,
      sharedBytes: stats.sharedBytes
    });
    return stats;
  }

  private async packPreviewImage(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    const packer = image.createImagePacker();
    try {
      const packedData = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: PREVIEW_IMAGE_CACHE_QUALITY,
        bufferSize: PREVIEW_IMAGE_CACHE_BUFFER_SIZE
      });
      return packedData;
    } catch (error) {
      const message = JSON.stringify(error);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'preview image pack failed error=%{public}s', message);
      throw new Error(message);
    } finally {
      try {
        await packer.release();
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'preview image packer release failed error=%{public}s',
          JSON.stringify(error));
      }
    }
  }

  private async ensurePreviewImageCacheDir(): Promise<void> {
    const dir = this.getPreviewImageCacheDir();
    try {
      if (await fileIo.access(dir)) {
        return;
      }
    } catch (_error) {
    }
    try {
      await fileIo.mkdir(dir, true);
    } catch (_error) {
    }
  }

  private async removePreviousPreviewImages(
    tabId: string,
    currentPath: string,
    currentTimestamp: number
  ): Promise<void> {
    const dir = this.getPreviewImageCacheDir();
    const targetCacheKey = this.sanitizeTabId(tabId);
    const prefix = `${targetCacheKey}-`;
    try {
      const files = await fileIo.listFile(dir);
      for (let index = 0; index < files.length; index += 1) {
        const fileName = files[index];
        const path = `${dir}/${fileName}`;
        if (path === currentPath) {
          continue;
        }
        if (this.resolvePreviewImageCacheKey(fileName) !== targetCacheKey) {
          continue;
        }
        const timestamp = this.parsePreviewTimestamp(fileName, prefix);
        if (currentTimestamp >= 0 && timestamp >= currentTimestamp) {
          continue;
        }
        try {
          await fileIo.unlink(path);
        } catch (_error) {
        }
      }
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'preview image cleanup failed tab=%{public}s error=%{public}s',
        tabId, JSON.stringify(error));
    }
  }

  private schedulePreviewImageCleanup(
    tabId: string,
    currentPath: string,
    currentTimestamp: number
  ): void {
    setTimeout(() => {
      void this.removePreviousPreviewImages(tabId, currentPath, currentTimestamp);
    }, 0);
  }

  private buildSharedSnapshotMetadataIfNeeded(
    tabId: string,
    pixelMap: image.PixelMap,
    imageTimestamp: number,
    transitionSource: BrowserTabPreviewTransitionSource
  ): BrowserTabPreviewSharedSnapshotMetadata | undefined {
    if (!tabId.endsWith('-shared')) {
      return undefined;
    }
    const imageInfo = this.resolvePixelMapSize(pixelMap);
    return {
      imageTimestamp: imageTimestamp,
      width: imageInfo.width,
      height: imageInfo.height,
      transitionSource: this.normalizeTransitionSource(transitionSource)
    };
  }

  private async persistSharedSnapshotMetadataIfNeeded(
    tabId: string,
    imageInfo: BrowserTabPreviewSharedSnapshotMetadata
  ): Promise<void> {
    if (!tabId.endsWith('-shared')) {
      return;
    }
    const tabKey = tabId.slice(0, tabId.length - '-shared'.length);
    const metadataPath = this.buildSharedSnapshotMetadataPath(tabKey);
    try {
      const payload = this.textEncoder.encodeInto(JSON.stringify({
        imageTimestamp: imageInfo.imageTimestamp,
        width: imageInfo.width,
        height: imageInfo.height,
        transitionSource: this.normalizeTransitionSource(imageInfo.transitionSource)
      } as BrowserTabPreviewSharedSnapshotMetadata));
      const file = await fileIo.open(metadataPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, payload.buffer as ArrayBuffer);
      } finally {
        await fileIo.close(file);
      }
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'shared snapshot metadata persist failed tab=%{public}s error=%{public}s',
        tabId, JSON.stringify(error));
    }
  }

  private resolvePixelMapSize(pixelMap: image.PixelMap): BrowserTabPreviewCachedImageSize {
    try {
      const imageInfo = pixelMap.getImageInfoSync();
      return {
        width: Math.max(1, Math.floor(imageInfo.size.width)),
        height: Math.max(1, Math.floor(imageInfo.size.height))
      };
    } catch (_error) {
      return {
        width: 1,
        height: 1
      };
    }
  }

  private async readSharedSnapshotMetadata(
    tabId: string,
    expectedImageTimestamp: number
  ): Promise<BrowserTabPreviewCachedImageSize | undefined> {
    const path = this.buildSharedSnapshotMetadataPath(tabId);
    try {
      if (!await fileIo.access(path)) {
        return undefined;
      }
    } catch (_error) {
      return undefined;
    }
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = await fileIo.stat(path);
        const size = Math.max(0, Math.floor(stat.size));
        if (size <= 0) {
          return undefined;
        }
        const buffer = new ArrayBuffer(size);
        const readLength = await fileIo.read(file.fd, buffer);
        if (readLength <= 0) {
          return undefined;
        }
        const text = this.textDecoder.decodeToString(
          new Uint8Array(buffer, 0, readLength)
        ).trim();
        if (text.length <= 0) {
          return undefined;
        }
        const parsed = JSON.parse(text) as BrowserTabPreviewSharedSnapshotMetadata;
        const imageTimestamp = Math.floor(parsed.imageTimestamp ?? -1);
        const width = Math.floor(parsed.width ?? 0);
        const height = Math.floor(parsed.height ?? 0);
        if (expectedImageTimestamp < 0 || imageTimestamp !== expectedImageTimestamp || width <= 0 || height <= 0) {
          return undefined;
        }
        return {
          width: Math.max(1, width),
          height: Math.max(1, height),
          transitionSource: this.normalizeTransitionSource(parsed.transitionSource)
        };
      } finally {
        await fileIo.close(file);
      }
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeCaptureSource(source?: string): BrowserTabPreviewCaptureSource | undefined {
    switch (source) {
      case 'window':
        return 'window';
      case 'surface':
        return 'surface';
      case 'surface-region':
        return 'surface-region';
      case 'surface-transform':
        return 'surface-transform';
      case 'web':
        return 'web';
      case 'component':
        return 'component';
      case 'visible-shell':
        return 'visible-shell';
      case 'visible-tab-surface':
        return 'visible-tab-surface';
      case 'web-page-container':
        return 'web-page-container';
      case 'none':
        return 'none';
      default:
        return undefined;
    }
  }

  private normalizeCaptureScope(scope?: string): BrowserTabPreviewCaptureScope | undefined {
    if (scope === 'web-content' || scope === 'full-surface') {
      return scope;
    }
    return undefined;
  }

  private normalizeTransitionFrame(frame?: string): BrowserTabPreviewTransitionFrame | undefined {
    if (frame === 'captured-surface' || frame === 'current-web') {
      return frame;
    }
    return undefined;
  }

  private normalizeTransitionSource(
    transitionSource?: BrowserTabPreviewTransitionSource
  ): BrowserTabPreviewTransitionSource | undefined {
    if (transitionSource === undefined) {
      return undefined;
    }
    const captureSource = this.normalizeCaptureSource(transitionSource.captureSource);
    const captureScope = this.normalizeCaptureScope(transitionSource.captureScope);
    const transitionFrame = this.normalizeTransitionFrame(transitionSource.transitionFrame);
    if (captureSource === undefined || captureSource === 'none' || captureScope === undefined ||
      transitionFrame === undefined) {
      return undefined;
    }
    return {
      captureSource: captureSource,
      captureScope: captureScope,
      transitionFrame: transitionFrame,
      sourceRect: this.normalizeSourceRect(transitionSource.sourceRect)
    };
  }

  private normalizeSourceRect(sourceRect?: BrowserTabPreviewSourceRect): BrowserTabPreviewSourceRect | undefined {
    if (sourceRect === undefined) {
      return undefined;
    }
    const width = Math.max(1, Math.round(sourceRect.width));
    const height = Math.max(1, Math.round(sourceRect.height));
    if (width <= 1 || height <= 1) {
      return undefined;
    }
    return {
      left: Math.round(sourceRect.left),
      top: Math.round(sourceRect.top),
      width: width,
      height: height
    };
  }

  private async removeSharedSnapshotMetadata(tabId: string): Promise<boolean> {
    const path = this.buildSharedSnapshotMetadataPath(tabId);
    try {
      if (!await fileIo.access(path)) {
        return false;
      }
    } catch (_error) {
      return false;
    }
    try {
      await fileIo.unlink(path);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private async readJpegImageSize(path: string): Promise<BrowserTabPreviewCachedImageSize | undefined> {
    const buffer = await this.readFilePrefix(path, 64 * 1024);
    if (buffer.byteLength < 4) {
      return undefined;
    }
    const bytes = new Uint8Array(buffer);
    if (bytes[0] !== 0xFF || bytes[1] !== 0xD8) {
      return undefined;
    }
    let offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] !== 0xFF) {
        offset += 1;
        continue;
      }
      while (offset < bytes.length && bytes[offset] === 0xFF) {
        offset += 1;
      }
      if (offset >= bytes.length) {
        return undefined;
      }
      const marker = bytes[offset];
      offset += 1;
      if (marker === 0xD9 || marker === 0xDA) {
        return undefined;
      }
      if (offset + 1 >= bytes.length) {
        return undefined;
      }
      const segmentLength = (bytes[offset] << 8) + bytes[offset + 1];
      if (segmentLength < 2 || offset + segmentLength > bytes.length) {
        return undefined;
      }
      if (this.isJpegStartOfFrameMarker(marker) && segmentLength >= 7) {
        const height = (bytes[offset + 3] << 8) + bytes[offset + 4];
        const width = (bytes[offset + 5] << 8) + bytes[offset + 6];
        if (width > 0 && height > 0) {
          return {
            width: width,
            height: height
          };
        }
        return undefined;
      }
      offset += segmentLength;
    }
    return undefined;
  }

  private isJpegStartOfFrameMarker(marker: number): boolean {
    return (marker >= 0xC0 && marker <= 0xC3) ||
      (marker >= 0xC5 && marker <= 0xC7) ||
      (marker >= 0xC9 && marker <= 0xCB) ||
      (marker >= 0xCD && marker <= 0xCF);
  }

  private async readFilePrefix(path: string, maxBytes: number): Promise<ArrayBuffer> {
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const buffer = new ArrayBuffer(maxBytes);
        const readLength = await fileIo.read(file.fd, buffer);
        if (readLength <= 0) {
          return new ArrayBuffer(0);
        }
        return buffer.slice(0, readLength);
      } finally {
        await fileIo.close(file);
      }
    } catch (_error) {
      return new ArrayBuffer(0);
    }
  }

  private async readFileSize(path: string): Promise<number> {
    try {
      const stat = await fileIo.stat(path);
      return Math.max(0, Math.floor(stat.size));
    } catch (_error) {
      return 0;
    }
  }

  private async findLatestPreviewImagePath(tabId: string): Promise<string> {
    return await this.findLatestPreviewImagePathInDir(tabId, this.getPreviewImageCacheDir());
  }

  private async findLatestSharedPreviewImagePaths(
    activeTabIds: Record<string, boolean>
  ): Promise<Record<string, BrowserTabPreviewIndexedImagePath | undefined>> {
    const dir = this.getPreviewImageCacheDir();
    const latestPaths: Record<string, BrowserTabPreviewIndexedImagePath | undefined> = {};
    try {
      const files = await fileIo.listFile(dir);
      for (let index = 0; index < files.length; index += 1) {
        const fileName = files[index];
        const imagePath = this.resolveSharedPreviewIndexedImagePath(fileName, dir, activeTabIds);
        if (imagePath === undefined) {
          continue;
        }
        const existing = latestPaths[imagePath.tabId];
        if (existing === undefined || imagePath.timestamp >= existing.timestamp) {
          latestPaths[imagePath.tabId] = imagePath;
        }
      }
    } catch (_error) {
    }
    return latestPaths;
  }

  private resolveSharedPreviewIndexedImagePath(
    fileName: string,
    dir: string,
    activeTabIds: Record<string, boolean>
  ): BrowserTabPreviewIndexedImagePath | undefined {
    if (!fileName.endsWith('.jpg')) {
      return undefined;
    }
    const marker = '-shared-';
    const markerIndex = fileName.lastIndexOf(marker);
    if (markerIndex <= 0) {
      return undefined;
    }
    const sanitizedTabId = fileName.substring(0, markerIndex);
    const tabId = this.resolveOriginalTabIdFromSanitized(sanitizedTabId, activeTabIds);
    if (tabId.length <= 0) {
      return undefined;
    }
    const rawTimestamp = fileName.slice(markerIndex + marker.length, fileName.length - 4);
    const timestamp = Number(rawTimestamp);
    if (!Number.isFinite(timestamp) || timestamp < 0) {
      return undefined;
    }
    return {
      tabId: tabId,
      path: `${dir}/${fileName}`,
      timestamp: timestamp
    };
  }

  private async findLatestPreviewImagePathInDir(tabId: string, dir: string): Promise<string> {
    const prefix = `${this.sanitizeTabId(tabId)}-`;
    let latestFileName: string = '';
    let latestTimestamp: number = -1;
    try {
      const files = await fileIo.listFile(dir);
      for (let index = 0; index < files.length; index += 1) {
        const fileName = files[index];
        if (!fileName.startsWith(prefix) || !fileName.endsWith('.jpg')) {
          continue;
        }
        const timestamp = this.parsePreviewTimestamp(fileName, prefix);
        if (timestamp < 0) {
          continue;
        }
        if (timestamp >= latestTimestamp) {
          latestTimestamp = timestamp;
          latestFileName = fileName;
        }
      }
    } catch (_error) {
      return '';
    }
    return latestFileName.length > 0 ? `${dir}/${latestFileName}` : '';
  }

  private parsePreviewTimestamp(fileName: string, prefix: string): number {
    const rawValue = fileName.slice(prefix.length, fileName.length - 4);
    const parsedValue = Number(rawValue);
    return Number.isFinite(parsedValue) ? parsedValue : -1;
  }

  private parsePreviewTimestampFromPath(tabId: string, path: string): number {
    const marker = '/';
    const markerIndex = path.lastIndexOf(marker);
    const fileName = markerIndex >= 0 ? path.slice(markerIndex + marker.length) : path;
    return this.parsePreviewTimestamp(fileName, `${this.sanitizeTabId(tabId)}-`);
  }

  private isPreviewImageFileForTab(fileName: string, tabId: string): boolean {
    if (!fileName.endsWith('.jpg')) {
      return false;
    }
    const prefix = `${this.sanitizeTabId(tabId)}-`;
    if (!fileName.startsWith(prefix)) {
      return false;
    }
    return this.parsePreviewTimestamp(fileName, prefix) >= 0;
  }

  private buildPreviewImagePath(tabId: string): string {
    return `${this.getPreviewImageCacheDir()}/${this.sanitizeTabId(tabId)}-${Date.now()}.jpg`;
  }

  private buildSharedSnapshotMetadataPath(tabId: string): string {
    return `${this.getPreviewImageCacheDir()}/${this.sanitizeTabId(tabId)}${SHARED_SNAPSHOT_METADATA_FILE_SUFFIX}`;
  }

  private isSharedPreviewImageFile(fileName: string): boolean {
    return fileName.indexOf('-shared-') >= 0;
  }

  private resolvePreviewImageCacheKey(fileName: string): string {
    if (!fileName.endsWith('.jpg')) {
      return '';
    }
    const withoutExtension = fileName.substring(0, fileName.length - 4);
    const lastDashIndex = withoutExtension.lastIndexOf('-');
    if (lastDashIndex <= 0) {
      return '';
    }
    return withoutExtension.substring(0, lastDashIndex);
  }

  private getPreviewImageCacheDir(): string {
    return `${AppRuntimeContext.getApplicationContext().cacheDir}/${PREVIEW_IMAGE_CACHE_DIR_NAME}/${this.scopeId}`;
  }

  private sanitizeTabId(tabId: string): string {
    return tabId.trim().replace(/[^a-zA-Z0-9._-]/g, '_');
  }

  private resolveOriginalTabIdFromSanitized(sanitizedTabId: string, activeTabIds: Record<string, boolean>): string {
    if (activeTabIds[sanitizedTabId] === true) {
      return sanitizedTabId;
    }
    const activeIds = Object.keys(activeTabIds);
    for (let index = 0; index < activeIds.length; index += 1) {
      const tabId = activeIds[index];
      if (this.sanitizeTabId(tabId) === sanitizedTabId) {
        return tabId;
      }
    }
    return '';
  }

  private sanitizeCacheSegment(value: string): string {
    return value.trim().replace(/[^a-zA-Z0-9._-]/g, '_');
  }
}
