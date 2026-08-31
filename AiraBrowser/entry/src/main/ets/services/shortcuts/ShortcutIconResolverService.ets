import { image } from '@kit.ImageKit';
import { ShortcutRecord } from '../../common/models/BrowserModels';
import { SiteIconUriCacheEntry } from '../../common/models/SiteIconModels';
import { SiteIconService } from '../siteicons/SiteIconService';
import { SiteIconPixelMapCacheService } from '../siteicons/SiteIconPixelMapCacheService';
import { HomeShortcutIconCacheService } from './HomeShortcutIconCacheService';
import { isHomeSystemShortcut } from './HomeSystemShortcutCatalog';

interface ShortcutIconCacheEntry {
  shortcutId: string;
  signature: string;
  icon: ResolvedShortcutIcon;
}

interface ShortcutIconInFlightEntry {
  shortcutId: string;
  signature: string;
  promise: Promise<ResolvedShortcutIcon | undefined>;
}

export interface ResolvedShortcutIcon {
  path: string;
  pixelMap?: image.PixelMap;
}

export interface ResolvedShortcutIconEntry {
  shortcutId: string;
  icon: ResolvedShortcutIcon;
}

export class ShortcutIconResolverService {
  private siteIconService: SiteIconService;
  private iconPixelMapCacheService: SiteIconPixelMapCacheService;
  private homeIconCacheService: HomeShortcutIconCacheService;
  private iconCache: ShortcutIconCacheEntry[] = [];
  private inFlightEntries: ShortcutIconInFlightEntry[] = [];

  constructor(
    siteIconService: SiteIconService = new SiteIconService(),
    iconPixelMapCacheService: SiteIconPixelMapCacheService = new SiteIconPixelMapCacheService(),
    homeIconCacheService?: HomeShortcutIconCacheService
  ) {
    this.siteIconService = siteIconService;
    this.iconPixelMapCacheService = iconPixelMapCacheService;
    this.homeIconCacheService = homeIconCacheService ?? new HomeShortcutIconCacheService();
  }

  async resolveShortcutIcon(shortcut: ShortcutRecord): Promise<ResolvedShortcutIcon | undefined> {
    if (isHomeSystemShortcut(shortcut)) {
      return undefined;
    }
    const signature = this.buildShortcutSignature(shortcut);
    const cached = this.iconCache.find((item: ShortcutIconCacheEntry) => (
      item.shortcutId === shortcut.id && item.signature === signature
    ));
    if (cached !== undefined) {
      return cached.icon;
    }

    const inFlight = this.inFlightEntries.find((item: ShortcutIconInFlightEntry) => (
      item.shortcutId === shortcut.id && item.signature === signature
    ));
    if (inFlight !== undefined) {
      return inFlight.promise;
    }

    const promise = (async (): Promise<ResolvedShortcutIcon | undefined> => {
      try {
        const resolved = await this.resolveShortcutIconInternal(shortcut);
        if (resolved !== undefined) {
          this.setCachedIcon(shortcut.id, signature, resolved);
        }
        return resolved;
      } finally {
        this.inFlightEntries = this.inFlightEntries.filter((item: ShortcutIconInFlightEntry) => (
          !(item.shortcutId === shortcut.id && item.signature === signature)
        ));
      }
    })();

    this.inFlightEntries = this.inFlightEntries
      .filter((item: ShortcutIconInFlightEntry) => item.shortcutId !== shortcut.id)
      .concat([{
        shortcutId: shortcut.id,
        signature: signature,
        promise: promise
      }]);

    return promise;
  }

  getPersistedShortcutIcon(shortcut: ShortcutRecord): ResolvedShortcutIcon | undefined {
    if (this.shouldUsePersistedShortcutIcon(shortcut)) {
      const iconPath = (shortcut.icon ?? '').trim();
      const resolved = this.createResolvedIcon(iconPath);
      this.setCachedIcon(shortcut.id, this.buildShortcutSignature(shortcut), resolved);
      return resolved;
    }
    return undefined;
  }

  getCachedShortcutIcon(shortcut: ShortcutRecord): ResolvedShortcutIcon | undefined {
    const signature = this.buildShortcutSignature(shortcut);
    const cached = this.iconCache.find((item: ShortcutIconCacheEntry) => (
      item.shortcutId === shortcut.id && item.signature === signature
    ));
    return cached?.icon;
  }

  shouldResolveShortcutIcon(shortcut: ShortcutRecord): boolean {
    return !isHomeSystemShortcut(shortcut) &&
      this.normalizeShortcutVisualMode(shortcut.iconRendering) !== 'letter' &&
      (!this.shouldUsePersistedShortcutIcon(shortcut) ||
        this.shouldRefreshPersistedShortcutIcon(shortcut) ||
        this.shouldPrewarmPersistedShortcutIcon(shortcut));
  }

  shouldRefreshPersistedShortcutIcon(shortcut: ShortcutRecord): boolean {
    return !isHomeSystemShortcut(shortcut) &&
      this.normalizeShortcutVisualMode(shortcut.iconRendering) !== 'letter' &&
      this.homeIconCacheService.isManagedIconUri((shortcut.icon ?? '').trim());
  }

  private shouldCacheShortcutIcon(shortcut: ShortcutRecord, iconPath: string): boolean {
    return !isHomeSystemShortcut(shortcut) &&
      this.normalizeShortcutVisualMode(shortcut.iconRendering) !== 'letter' &&
      iconPath.trim().length > 0 &&
      !this.homeIconCacheService.isManagedIconUri(iconPath);
  }

  private async cacheShortcutIcon(
    shortcut: ShortcutRecord,
    sourceIconPath: string
  ): Promise<ResolvedShortcutIcon | undefined> {
    if (!this.shouldCacheShortcutIcon(shortcut, sourceIconPath)) {
      return undefined;
    }
    const cachedUri = await this.homeIconCacheService.cacheIconUri(
      shortcut.id,
      sourceIconPath,
      shortcut.icon ?? ''
    );
    if (cachedUri.length === 0) {
      return undefined;
    }
    const icon = await this.createResolvedIconWithPrewarm(cachedUri);
    this.setCachedIcon(shortcut.id, this.buildShortcutSignature(shortcut), icon);
    return icon;
  }

  async resolveCachedShortcutIcons(shortcuts: ShortcutRecord[]): Promise<ResolvedShortcutIconEntry[]> {
    const resolvedEntries: ResolvedShortcutIconEntry[] = [];
    const pendingShortcuts: ShortcutRecord[] = [];
    shortcuts.forEach((shortcut: ShortcutRecord) => {
      if (!this.shouldResolveShortcutIcon(shortcut)) {
        const persistedIcon = this.getPersistedShortcutIcon(shortcut);
        if (persistedIcon !== undefined) {
          resolvedEntries.push({
            shortcutId: shortcut.id,
            icon: persistedIcon
          });
        }
        return;
      }
      if (!this.shouldRefreshPersistedShortcutIcon(shortcut)) {
        const memoryIcon = this.getCachedShortcutIcon(shortcut);
        if (memoryIcon?.pixelMap !== undefined) {
          resolvedEntries.push({
            shortcutId: shortcut.id,
            icon: memoryIcon
          });
          return;
        }
      }
      pendingShortcuts.push(shortcut);
    });

    if (pendingShortcuts.length <= 0) {
      return resolvedEntries;
    }

    const urls = pendingShortcuts.map((shortcut: ShortcutRecord) => shortcut.url);
    const cachedIcons = await this.siteIconService.resolveCachedUris(urls);
    for (let index = 0; index < pendingShortcuts.length; index += 1) {
      const shortcut = pendingShortcuts[index];
      const uri = this.findCachedIconUri(shortcut.url, cachedIcons);
      const persistedIconPath = (shortcut.icon ?? '').trim();
      if (uri.length <= 0 && persistedIconPath.length <= 0) {
        continue;
      }
      const resolvedIcon = uri.length > 0 ?
        await this.createCachedOrResolvedIcon(shortcut, uri) :
        await this.createResolvedIconWithPrewarm(persistedIconPath);
      this.setCachedIcon(shortcut.id, this.buildShortcutSignature(shortcut), resolvedIcon);
      resolvedEntries.push({
        shortcutId: shortcut.id,
        icon: resolvedIcon
      });
    }
    return resolvedEntries;
  }

  async resolveSharedShortcutIconUpdate(
    shortcut: ShortcutRecord,
    sourceIconPath: string
  ): Promise<ResolvedShortcutIcon | undefined> {
    const normalizedSourceIconPath = sourceIconPath.trim();
    if (!this.shouldResolveShortcutIcon(shortcut) || normalizedSourceIconPath.length === 0) {
      return undefined;
    }
    const resolvedIcon = await this.createCachedOrResolvedIcon(shortcut, normalizedSourceIconPath);
    this.setCachedIcon(shortcut.id, this.buildShortcutSignature(shortcut), resolvedIcon);
    return resolvedIcon;
  }

  resolveShortcutDomain(url: string): string {
    return this.siteIconService.resolveDomain(url);
  }

  private async resolveShortcutIconInternal(shortcut: ShortcutRecord): Promise<ResolvedShortcutIcon | undefined> {
    if (this.normalizeShortcutVisualMode(shortcut.iconRendering) === 'letter') {
      return undefined;
    }

    const faviconPath = this.siteIconService.peekUri(shortcut.url);
    if (faviconPath.length > 0) {
      return await this.createCachedOrResolvedIcon(shortcut, faviconPath);
    }

    const resolvedFavicon = await this.siteIconService.resolve(shortcut.url, {
      networkPolicy: 'remoteAllowed'
    });
    const resolvedFaviconPath = resolvedFavicon?.uri ?? '';
    if (resolvedFaviconPath.length === 0) {
      return undefined;
    }
    return await this.createCachedOrResolvedIcon(shortcut, resolvedFaviconPath);
  }

  private findCachedIconUri(url: string, cachedIcons: SiteIconUriCacheEntry[]): string {
    const normalizedUrl = url.trim();
    const entry = cachedIcons.find((item: SiteIconUriCacheEntry) => item.url === normalizedUrl);
    return entry?.uri ?? '';
  }

  private createResolvedIcon(path: string): ResolvedShortcutIcon {
    return {
      path: path,
      pixelMap: this.iconPixelMapCacheService.getCachedPixelMap(path)
    };
  }

  private async createCachedOrResolvedIcon(
    shortcut: ShortcutRecord,
    path: string
  ): Promise<ResolvedShortcutIcon> {
    const cachedIcon = await this.cacheShortcutIcon(shortcut, path);
    if (cachedIcon !== undefined) {
      return cachedIcon;
    }
    return await this.createResolvedIconWithPrewarm(path);
  }

  private async createResolvedIconWithPrewarm(path: string): Promise<ResolvedShortcutIcon> {
    const resolvedIcon = this.createResolvedIcon(path);
    if (resolvedIcon.pixelMap === undefined) {
      resolvedIcon.pixelMap = await this.iconPixelMapCacheService.prewarmIconUri(path);
    }
    return resolvedIcon;
  }

  private normalizeShortcutVisualMode(value?: string): string {
    return value === 'letter' ? 'letter' : 'favicon';
  }

  private shouldUsePersistedShortcutIcon(shortcut: ShortcutRecord): boolean {
    return this.normalizeShortcutVisualMode(shortcut.iconRendering) !== 'letter' &&
      (shortcut.icon ?? '').trim().length > 0;
  }

  private shouldPrewarmPersistedShortcutIcon(shortcut: ShortcutRecord): boolean {
    const persistedIconPath = (shortcut.icon ?? '').trim();
    return persistedIconPath.length > 0 &&
      this.iconPixelMapCacheService.getCachedPixelMap(persistedIconPath) === undefined;
  }

  private buildShortcutSignature(shortcut: ShortcutRecord): string {
    return [
      shortcut.kind ?? 'web',
      shortcut.url.trim(),
      shortcut.iconRendering ?? '',
      (shortcut.icon ?? '').trim()
    ].join('|');
  }

  private setCachedIcon(shortcutId: string, signature: string, icon: ResolvedShortcutIcon): void {
    this.iconCache = this.iconCache.filter((item: ShortcutIconCacheEntry) => item.shortcutId !== shortcutId);
    this.iconCache = this.iconCache.concat([{
      shortcutId: shortcutId,
      signature: signature,
      icon: icon
    }]);
  }
}
