import { DesktopWebEntryRecord } from '../../data/webapps/WebAppInstallModels';

export interface WebAppSettingsListItemState {
  shortcutId: string;
  title: string;
  subtitle: string;
  iconPath: string;
  defaultFullscreen: boolean;
}

export interface WebAppSettingsListState {
  items: WebAppSettingsListItemState[];
  emptyTitle: string;
  emptyMessage: string;
}

export interface WebAppSettingsDetailState {
  shortcutId: string;
  title: string;
  subtitle: string;
  iconPath: string;
  defaultFullscreen: boolean;
  siteHost: string;
  siteOrigin: string;
  canOpenSiteSettings: boolean;
  exists: boolean;
}

export class WebAppSettingsViewModel {
  buildListState(
    records: DesktopWebEntryRecord[],
    pinnedShortcutIds: string[] = [],
    isPinnedShortcutStateTrusted: boolean = false
  ): WebAppSettingsListState {
    const installedRecords = records
      .filter((record: DesktopWebEntryRecord) => record.installState === 'installed')
      .filter((record: DesktopWebEntryRecord) => {
        return !isPinnedShortcutStateTrusted || pinnedShortcutIds.indexOf(record.shortcutId) >= 0;
      })
      .sort((left: DesktopWebEntryRecord, right: DesktopWebEntryRecord) => right.updatedAt - left.updatedAt);
    return {
      items: this.dedupeRecords(installedRecords).map((record: DesktopWebEntryRecord) => this.buildListItem(record)),
      emptyTitle: '还没有网页应用',
      emptyMessage: '添加后会显示在这里。'
    };
  }

  buildDetailState(record: DesktopWebEntryRecord | undefined, shortcutId: string = ''): WebAppSettingsDetailState {
    if (record === undefined) {
      return {
        shortcutId: shortcutId.trim(),
        title: '网页应用',
        subtitle: '',
        iconPath: '',
        defaultFullscreen: false,
        siteHost: '',
        siteOrigin: '',
        canOpenSiteSettings: false,
        exists: false
      };
    }
    const siteTarget = this.resolveSiteTarget(record);
    return {
      shortcutId: record.shortcutId,
      title: this.resolveTitle(record),
      subtitle: this.resolveSubtitle(record),
      iconPath: this.resolveImageUri(record.iconPath),
      defaultFullscreen: record.settings.defaultFullscreen,
      siteHost: siteTarget.host,
      siteOrigin: siteTarget.origin,
      canOpenSiteSettings: siteTarget.host.length > 0 && siteTarget.origin.length > 0,
      exists: true
    };
  }

  private buildListItem(record: DesktopWebEntryRecord): WebAppSettingsListItemState {
    return {
      shortcutId: record.shortcutId,
      title: this.resolveTitle(record),
      subtitle: this.resolveSubtitle(record),
      iconPath: this.resolveImageUri(record.iconPath),
      defaultFullscreen: record.settings.defaultFullscreen
    };
  }

  private dedupeRecords(records: DesktopWebEntryRecord[]): DesktopWebEntryRecord[] {
    const byIdentity: Record<string, DesktopWebEntryRecord> = {};
    const orderedKeys: string[] = [];
    records.forEach((record: DesktopWebEntryRecord) => {
      const key = this.resolveIdentityKey(record);
      const existing = byIdentity[key];
      if (existing === undefined) {
        orderedKeys.push(key);
        byIdentity[key] = record;
        return;
      }
      if (record.updatedAt >= existing.updatedAt) {
        byIdentity[key] = record;
      }
    });
    return orderedKeys.map((key: string) => byIdentity[key]);
  }

  private resolveIdentityKey(record: DesktopWebEntryRecord): string {
    const manifestUrl = record.manifestUrl.trim();
    if (manifestUrl.length > 0) {
      return `manifest:${manifestUrl}`;
    }
    const scope = record.scope.trim();
    const origin = record.origin.trim();
    if (origin.length > 0 && scope.length > 0) {
      return `scope:${origin}|${scope}`;
    }
    const launchUrl = record.launchUrl.trim();
    if (launchUrl.length > 0) {
      return `launch:${launchUrl}`;
    }
    return `shortcut:${record.shortcutId}`;
  }

  private resolveTitle(record: DesktopWebEntryRecord): string {
    const title = record.title.trim();
    if (title.length > 0) {
      return title;
    }
    const launchUrl = record.launchUrl.trim();
    return launchUrl.length > 0 ? launchUrl : '网页应用';
  }

  private resolveSubtitle(record: DesktopWebEntryRecord): string {
    const origin = record.origin.trim();
    if (origin.length > 0) {
      return origin;
    }
    const launchUrl = record.launchUrl.trim();
    return launchUrl.length > 0 ? launchUrl : record.currentUrl.trim();
  }

  private resolveImageUri(iconPath: string): string {
    const normalized = iconPath.trim();
    if (normalized.length === 0 ||
      normalized.startsWith('file://') ||
      normalized.startsWith('http://') ||
      normalized.startsWith('https://') ||
      normalized.startsWith('data:')) {
      return normalized;
    }
    return `file://${normalized}`;
  }

  private resolveSiteTarget(record: DesktopWebEntryRecord): WebAppSiteSettingsTarget {
    const origin = record.origin.trim();
    const originTarget = this.parseSiteTarget(origin);
    if (originTarget.host.length > 0 && originTarget.origin.length > 0) {
      return originTarget;
    }
    const launchTarget = this.parseSiteTarget(record.launchUrl);
    if (launchTarget.host.length > 0 && launchTarget.origin.length > 0) {
      return launchTarget;
    }
    return this.parseSiteTarget(record.currentUrl);
  }

  private parseSiteTarget(rawUrl: string): WebAppSiteSettingsTarget {
    const normalized = rawUrl.trim();
    if (normalized.length === 0) {
      return { host: '', origin: '' };
    }
    const protocolMarker = normalized.indexOf('://');
    if (protocolMarker <= 0) {
      return { host: '', origin: '' };
    }
    const protocol = normalized.substring(0, protocolMarker + 1).toLowerCase();
    if (protocol !== 'http:' && protocol !== 'https:') {
      return { host: '', origin: '' };
    }
    const hostStart = protocolMarker + 3;
    const hostEnd = this.findHostEnd(normalized, hostStart);
    const hostWithPort = normalized.substring(hostStart, hostEnd).trim();
    if (hostWithPort.length === 0) {
      return { host: '', origin: '' };
    }
    const host = this.stripPort(hostWithPort);
    if (host.length === 0) {
      return { host: '', origin: '' };
    }
    return {
      host: host,
      origin: `${protocol}//${hostWithPort}`
    };
  }

  private findHostEnd(url: string, hostStart: number): number {
    const slashIndex = url.indexOf('/', hostStart);
    const queryIndex = url.indexOf('?', hostStart);
    const hashIndex = url.indexOf('#', hostStart);
    let end = url.length;
    if (slashIndex >= 0 && slashIndex < end) {
      end = slashIndex;
    }
    if (queryIndex >= 0 && queryIndex < end) {
      end = queryIndex;
    }
    if (hashIndex >= 0 && hashIndex < end) {
      end = hashIndex;
    }
    return end;
  }

  private stripPort(hostWithPort: string): string {
    const bracketEnd = hostWithPort.indexOf(']');
    if (hostWithPort.startsWith('[') && bracketEnd > 0) {
      return hostWithPort.substring(1, bracketEnd).trim();
    }
    const colonIndex = hostWithPort.indexOf(':');
    if (colonIndex < 0) {
      return hostWithPort.trim();
    }
    return hostWithPort.substring(0, colonIndex).trim();
  }
}

interface WebAppSiteSettingsTarget {
  host: string;
  origin: string;
}
