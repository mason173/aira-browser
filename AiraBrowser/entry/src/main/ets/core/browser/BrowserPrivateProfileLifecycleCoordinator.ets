import {
  BookmarkStorageScope,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  TabRecord
} from '../../common/models/BrowserModels';
import { BrowserPrivateModeLockReason } from '../privacy/BrowserPrivateModeLockCoordinator';
import { BrowserTabState } from '../tabs/TabManager';
import { PrivateModeCookiePreservationResult } from '../../services/web/SiteDataControlService';
import { BrowserPrivateStartupResidualCleanupRequest } from './BrowserPrivateSessionCleanupCoordinator';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';

export interface BrowserPrivateProfileBoundaryInput {
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
  sessionId?: string;
}

export interface BrowserPrivateProfileCookieLifecycleRequest extends BrowserPrivateProfileBoundaryInput {
  preserveCookiesOnClose: boolean;
}

export interface BrowserPrivateProfileCookieLifecycleHost {
  isPreserveCookiesOnCloseEnabled: () => boolean;
  restorePreservedPrivateModeCookies: () => Promise<PrivateModeCookiePreservationResult>;
  savePreservedPrivateModeCookies: () => Promise<PrivateModeCookiePreservationResult>;
  findTabById: (tabId: string) => BrowserTabState | undefined;
  getActiveTabId: () => string;
}

export interface BrowserPrivateBookmarkAccessPlan {
  scope: BookmarkStorageScope;
  shouldAuthenticate: boolean;
  authPrivacyMode: BrowserSessionPrivacyMode;
  authDataScope: BrowserDataScope;
  authReason: BrowserPrivateModeLockReason;
}

export class BrowserPrivateProfileLifecycleCoordinator {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  buildCookieRestoreRequest(
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope,
    preserveCookiesOnClose: boolean
  ): BrowserPrivateProfileCookieLifecycleRequest {
    return {
      privacyMode: privacyMode,
      dataScope: dataScope,
      preserveCookiesOnClose: preserveCookiesOnClose
    };
  }

  shouldRestoreCookieSnapshotOnEnter(request: BrowserPrivateProfileCookieLifecycleRequest): boolean {
    return request.preserveCookiesOnClose &&
      this.profileBoundaryService.isSessionEphemeral({
        profileId: request.profileId,
        privacyMode: request.privacyMode,
        dataScope: request.dataScope,
        sessionId: request.sessionId
      });
  }

  async restorePreservedCookiesOnEnterIfNeeded(
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope,
    host: BrowserPrivateProfileCookieLifecycleHost
  ): Promise<void> {
    const request = this.buildCookieRestoreRequest(
      privacyMode,
      dataScope,
      host.isPreserveCookiesOnCloseEnabled()
    );
    if (!this.shouldRestoreCookieSnapshotOnEnter(request)) {
      return;
    }
    await host.restorePreservedPrivateModeCookies();
  }

  savePreservedCookiesForTabIfNeeded(
    tabId: string,
    host: BrowserPrivateProfileCookieLifecycleHost
  ): void {
    const tab = host.findTabById(tabId);
    if (!this.shouldSaveCookieSnapshotForTab(
      tab === undefined ? undefined : {
        profileId: tab.profileId,
        privacyMode: tab.privacyMode,
        dataScope: tab.dataScope,
        sessionId: tab.id
      },
      host.isPreserveCookiesOnCloseEnabled()
    )) {
      return;
    }
    void host.savePreservedPrivateModeCookies().catch((_error: Error): void => {});
  }

  shouldSaveCookieSnapshotForTab(
    tab: BrowserPrivateProfileBoundaryInput | undefined,
    preserveCookiesOnClose: boolean
  ): boolean {
    if (!preserveCookiesOnClose || tab === undefined) {
      return false;
    }
    return this.isSessionEphemeralTab(tab);
  }

  buildStartupResidualCleanupRequest(
    records: TabRecord[],
    profileId: BrowserProfileId,
    preserveCookiesOnClose: boolean
  ): BrowserPrivateStartupResidualCleanupRequest {
    const privateRecords = records.filter((record: TabRecord): boolean => this.isSessionEphemeralTab({
      profileId: record.profileId,
      privacyMode: record.privacyMode,
      dataScope: record.dataScope,
      sessionId: record.id
    }));
    return {
      profileId: profileId,
      tabIds: privateRecords.map((record: TabRecord): string => record.id),
      snapshotPaths: this.resolveUniqueSnapshotPathsForRecords(privateRecords),
      preserveCookiesOnClose: preserveCookiesOnClose
    };
  }

  resolveSessionEphemeralSnapshotPathsForTabStates(tabs: BrowserTabState[]): string[] {
    const privateTabs = tabs.filter((tab: BrowserTabState): boolean => this.isSessionEphemeralTabState(tab));
    return this.resolveUniqueSnapshotPathsForTabStates(privateTabs);
  }

  isSessionEphemeralTab(tab: BrowserPrivateProfileBoundaryInput): boolean {
    return this.profileBoundaryService.isSessionEphemeral({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.sessionId
    });
  }

  resolveWebIncognitoMode(tab: BrowserPrivateProfileBoundaryInput | undefined): boolean {
    if (tab === undefined) {
      return false;
    }
    return this.profileBoundaryService.resolveWebIncognitoMode({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.sessionId
    });
  }

  resolveWebIncognitoModeForTabRecord(tab: TabRecord | undefined): boolean {
    if (tab === undefined) {
      return false;
    }
    return this.profileBoundaryService.resolveWebIncognitoMode({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.id
    });
  }

  resolveWebIncognitoModeForTabState(tab: BrowserTabState | undefined): boolean {
    if (tab === undefined) {
      return false;
    }
    return this.profileBoundaryService.resolveWebIncognitoMode({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.id
    });
  }

  isSessionEphemeralTabState(tab: BrowserTabState | undefined): boolean {
    if (tab === undefined) {
      return false;
    }
    return this.profileBoundaryService.isSessionEphemeral({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.id
    });
  }

  buildPrivateBookmarkAccessPlan(
    dataScope: BrowserDataScope | string,
    privacyMode: BrowserSessionPrivacyMode | string
  ): BrowserPrivateBookmarkAccessPlan {
    const scope = this.profileBoundaryService.resolveBookmarkScope({
      dataScope: dataScope,
      privacyMode: privacyMode
    });
    return {
      scope: scope,
      shouldAuthenticate: scope === 'private',
      authPrivacyMode: 'private',
      authDataScope: 'session_ephemeral',
      authReason: 'private_bookmarks'
    };
  }

  private resolveUniqueSnapshotPathsForRecords(records: TabRecord[]): string[] {
    const paths: string[] = [];
    records.forEach((record: TabRecord): void => {
      const path = (record.webStatePath ?? '').trim();
      if (path.length > 0 && !paths.includes(path)) {
        paths.push(path);
      }
    });
    return paths;
  }

  private resolveUniqueSnapshotPathsForTabStates(tabs: BrowserTabState[]): string[] {
    const paths: string[] = [];
    tabs.forEach((tab: BrowserTabState): void => {
      const path = tab.webStatePath.trim();
      if (path.length > 0 && !paths.includes(path)) {
        paths.push(path);
      }
    });
    return paths;
  }
}
