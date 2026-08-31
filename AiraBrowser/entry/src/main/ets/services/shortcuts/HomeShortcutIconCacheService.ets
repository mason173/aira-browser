import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

interface HomeShortcutIconCacheInFlightEntry {
  key: string;
  promise: Promise<string>;
}

interface HomeShortcutIconCacheCleanupEntry {
  shortcutId: string;
  retainedPath: string;
  previousPath: string;
}

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'HomeShortcutIconCache';
const ICON_CACHE_DIR_NAME: string = 'home-shortcut-icons';
const MANAGED_ICON_FILE_PREFIX: string = 'aira_home_shortcut_icon_';
const ICON_CACHE_VERSION: string = 'raw-v1';
const SUPERSEDED_ICON_CLEANUP_DELAY_MS: number = 5000;

export class HomeShortcutIconCacheService {
  private static sharedInFlightEntries: HomeShortcutIconCacheInFlightEntry[] = [];
  private static sharedCleanupEntries: HomeShortcutIconCacheCleanupEntry[] = [];

  isManagedIconUri(uri: string): boolean {
    const path = this.toLocalFilePath(uri);
    return path.includes(`/${ICON_CACHE_DIR_NAME}/${MANAGED_ICON_FILE_PREFIX}`);
  }

  async cacheIconUri(
    shortcutId: string,
    sourceUri: string,
    previousManagedUri: string = ''
  ): Promise<string> {
    const sourcePath = this.toLocalFilePath(sourceUri);
    if (sourcePath.length === 0 || !AppRuntimeContext.hasApplicationContext()) {
      return '';
    }

    const sourceVersion = await this.resolveSourceVersion(sourcePath);
    if (sourceVersion.length === 0) {
      return '';
    }
    const targetPath = this.buildCachedIconPath(shortcutId, sourcePath, sourceVersion);
    const targetUri = this.toImageUri(targetPath);
    if (this.normalizePath(sourcePath) === this.normalizePath(targetPath)) {
      return await this.isUsableFile(targetPath) ? targetUri : '';
    }
    if (await this.isUsableFile(targetPath)) {
      return targetUri;
    }

    const key = `${this.sanitizeShortcutId(shortcutId)}|${sourcePath}|${sourceVersion}`;
    const inFlight = HomeShortcutIconCacheService.sharedInFlightEntries
      .find((entry: HomeShortcutIconCacheInFlightEntry) => entry.key === key);
    if (inFlight !== undefined) {
      return inFlight.promise;
    }

    const promise = this.cacheIconUriInternal(shortcutId, sourcePath, targetPath, previousManagedUri)
      .finally(() => {
        HomeShortcutIconCacheService.sharedInFlightEntries =
          HomeShortcutIconCacheService.sharedInFlightEntries
            .filter((entry: HomeShortcutIconCacheInFlightEntry) => entry.key !== key);
      });
    HomeShortcutIconCacheService.sharedInFlightEntries =
      HomeShortcutIconCacheService.sharedInFlightEntries.concat([{
        key: key,
        promise: promise
      }]);
    return promise;
  }

  private async cacheIconUriInternal(
    shortcutId: string,
    sourcePath: string,
    targetPath: string,
    previousManagedUri: string
  ): Promise<string> {
    const startedAt = Date.now();
    try {
      const targetUri = this.toImageUri(targetPath);
      await this.ensureDirectory(this.getIconCacheDir());
      await fileIo.copyFile(sourcePath, targetPath);
      this.scheduleSupersededIconCleanup(shortcutId, targetPath, previousManagedUri);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'cache result=ok target=%{public}s durationMs=%{public}d',
        targetUri, Date.now() - startedAt);
      return targetUri;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'cache result=failed durationMs=%{public}d error=%{public}s',
        Date.now() - startedAt, JSON.stringify(error));
      return '';
    }
  }

  private async resolveSourceVersion(sourcePath: string): Promise<string> {
    try {
      const sourceStat = await fileIo.stat(sourcePath);
      if (sourceStat.isDirectory() || sourceStat.size <= 0) {
        return '';
      }
      return `${Math.max(0, Math.floor(sourceStat.mtime))}-${Math.max(0, Math.floor(sourceStat.size))}`;
    } catch (_error) {
      return '';
    }
  }

  private async isUsableFile(path: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(path);
      return !stat.isDirectory() && stat.size > 0;
    } catch (_error) {
      return false;
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

  private buildCachedIconPath(shortcutId: string, sourcePath: string, sourceVersion: string): string {
    return `${this.getIconCacheDir()}/${this.buildManagedIconPrefix(shortcutId)}` +
      `${this.hashSourcePath(sourcePath)}-${sourceVersion}-${ICON_CACHE_VERSION}`;
  }

  private getIconCacheDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${ICON_CACHE_DIR_NAME}`;
  }

  private sanitizeShortcutId(shortcutId: string): string {
    const normalized = shortcutId.trim().replace(/[^A-Za-z0-9._-]/g, '_');
    return normalized.length > 0 ? normalized : 'unknown';
  }

  private hashSourcePath(sourcePath: string): string {
    let hash = 2166136261;
    for (let index = 0; index < sourcePath.length; index += 1) {
      hash = hash ^ sourcePath.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(36);
  }

  private buildManagedIconPrefix(shortcutId: string): string {
    return `${MANAGED_ICON_FILE_PREFIX}${this.sanitizeShortcutId(shortcutId)}-`;
  }

  private scheduleSupersededIconCleanup(
    shortcutId: string,
    retainedPath: string,
    previousManagedUri: string
  ): void {
    const normalizedShortcutId = this.sanitizeShortcutId(shortcutId);
    const previousPath = this.isManagedIconUri(previousManagedUri)
      ? this.toLocalFilePath(previousManagedUri)
      : '';
    HomeShortcutIconCacheService.sharedCleanupEntries =
      HomeShortcutIconCacheService.sharedCleanupEntries
        .filter((entry: HomeShortcutIconCacheCleanupEntry) => entry.shortcutId !== normalizedShortcutId)
        .concat([{
          shortcutId: normalizedShortcutId,
          retainedPath: retainedPath,
          previousPath: previousPath
        }]);
    setTimeout(() => {
      const cleanupEntry = HomeShortcutIconCacheService.sharedCleanupEntries
        .find((entry: HomeShortcutIconCacheCleanupEntry) => entry.shortcutId === normalizedShortcutId);
      if (cleanupEntry === undefined || cleanupEntry.retainedPath !== retainedPath) {
        return;
      }
      HomeShortcutIconCacheService.sharedCleanupEntries =
        HomeShortcutIconCacheService.sharedCleanupEntries
          .filter((entry: HomeShortcutIconCacheCleanupEntry) => entry.shortcutId !== normalizedShortcutId);
      void this.removeSupersededIcons(normalizedShortcutId, retainedPath, cleanupEntry.previousPath);
    }, SUPERSEDED_ICON_CLEANUP_DELAY_MS);
  }

  private async removeSupersededIcons(
    shortcutId: string,
    retainedPath: string,
    previousPath: string
  ): Promise<void> {
    try {
      const directory = this.getIconCacheDir();
      const prefix = this.buildManagedIconPrefix(shortcutId);
      const files = await fileIo.listFile(directory);
      for (let index = 0; index < files.length; index += 1) {
        const fileName = files[index];
        const path = `${directory}/${fileName}`;
        if (path === retainedPath || path === previousPath || !fileName.startsWith(prefix)) {
          continue;
        }
        try {
          await fileIo.unlink(path);
        } catch (_error) {
        }
      }
    } catch (_error) {
    }
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
