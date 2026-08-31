import { TabRecord } from '../../common/models/BrowserModels';

export interface BrowserTabSessionRuntimeSnapshot {
  windowId: string;
  profileId: string;
  records: TabRecord[];
}

export class BrowserTabSessionRuntime {
  private static snapshots: Record<string, BrowserTabSessionRuntimeSnapshot> = {};

  static remember(windowId: string, profileId: string, records: TabRecord[]): void {
    const normalizedWindowId = windowId.trim().length > 0 ? windowId.trim() : 'window-main';
    const normalizedProfileId = profileId.trim().length > 0 ? profileId.trim() : 'profile-main';
    BrowserTabSessionRuntime.snapshots[normalizedWindowId] = {
      windowId: normalizedWindowId,
      profileId: normalizedProfileId,
      records: records.map((record: TabRecord): TabRecord => BrowserTabSessionRuntime.copyRecord(record))
    };
  }

  static getSnapshot(windowId: string): BrowserTabSessionRuntimeSnapshot | undefined {
    const normalizedWindowId = windowId.trim().length > 0 ? windowId.trim() : 'window-main';
    const snapshot = BrowserTabSessionRuntime.snapshots[normalizedWindowId];
    if (snapshot === undefined) {
      return undefined;
    }
    return {
      windowId: snapshot.windowId,
      profileId: snapshot.profileId,
      records: snapshot.records.map((record: TabRecord): TabRecord => BrowserTabSessionRuntime.copyRecord(record))
    };
  }

  private static copyRecord(record: TabRecord): TabRecord {
    return {
      id: record.id,
      windowId: record.windowId,
      profileId: record.profileId,
      title: record.title,
      url: record.url,
      isActive: record.isActive,
      isPinned: record.isPinned,
      lastActiveAt: record.lastActiveAt,
      tabOrder: record.tabOrder,
      isHome: record.isHome,
      pendingUrl: record.pendingUrl,
      navigationHistory: record.navigationHistory === undefined ? undefined : record.navigationHistory.slice(),
      navigationIndex: record.navigationIndex,
      runtimeState: record.runtimeState,
      lastError: record.lastError,
      lastRestoreReason: record.lastRestoreReason,
      lastDiscardReason: record.lastDiscardReason,
      lastCrashReason: record.lastCrashReason,
      lastLoadedAt: record.lastLoadedAt,
      webStatePath: record.webStatePath,
      webStateUpdatedAt: record.webStateUpdatedAt,
      scrollOffsetY: record.scrollOffsetY,
      lastGoodUrl: record.lastGoodUrl,
      lastGoodTitle: record.lastGoodTitle,
      lastRestoreType: record.lastRestoreType,
      privacyMode: record.privacyMode,
      dataScope: record.dataScope,
      launchSourceType: record.launchSourceType,
      launchSourceId: record.launchSourceId,
      launchSourceUrl: record.launchSourceUrl,
      launchKey: record.launchKey
    };
  }
}
