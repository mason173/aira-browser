import { BrowserProfileId } from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { DownloadRuntimeService } from '../../services/download/DownloadRuntimeService';
import { SiteDataControlService } from '../../services/web/SiteDataControlService';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import {
  sharedBrowserHttpsFirstNavigationService
} from '../../services/web/BrowserHttpsFirstNavigationService';
import { BrowserTabState } from '../tabs/TabManager';
import { WebStateSnapshotStore } from '../web/WebStateSnapshotStore';
import { BrowserDownloadConfirmOverlayCoordinator } from './BrowserDownloadConfirmOverlayCoordinator';
import {
  BrowserExternalNavigationRuntimeStateCoordinator
} from './BrowserExternalNavigationRuntimeStateCoordinator';
import { BrowserPrivateProfileLifecycleCoordinator } from './BrowserPrivateProfileLifecycleCoordinator';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';
import { BrowserPageFindCoordinator } from './BrowserPageFindCoordinator';
import { BrowserSiteControlsRuntimeCoordinator } from './BrowserSiteControlsRuntimeCoordinator';
import { BrowserTabPreviewCoordinator } from './BrowserTabPreviewCoordinator';
import {
  BrowserWebCapabilityPromptApplicationCoordinator
} from './BrowserWebCapabilityPromptApplicationCoordinator';

export interface BrowserPrivateSessionCleanupRequest {
  tabs: BrowserTabState[];
  closingTabId: string;
  profileId: BrowserProfileId;
  pendingJsPrompt: boolean;
  pendingHttpAuth: boolean;
  pendingDownloadPrompt: boolean;
  activeDownloadPromptLease: boolean;
  externalNavigationUrl: string;
  sitePermissionRelatedOriginCount: number;
  persistedEphemeralSnapshotPaths: string[];
}

export interface BrowserPrivateSessionCleanupPlan {
  shouldCleanup: boolean;
  profileId: BrowserProfileId;
  remainingPrivateTabIds: string[];
}

export interface BrowserPrivateSessionCleanupFacts {
  tabs: BrowserTabState[];
  pendingDownloadPrompt: boolean;
  currentWindowId: string;
}

export interface BrowserPrivateSessionCleanupDependencies {
  resolveWebCapabilityPromptApplicationCoordinator: () => BrowserWebCapabilityPromptApplicationCoordinator;
  resolveDownloadConfirmOverlayCoordinator: () => BrowserDownloadConfirmOverlayCoordinator;
  resolveExternalNavigationRuntimeStateCoordinator: () => BrowserExternalNavigationRuntimeStateCoordinator;
  resolveSiteControlsRuntimeCoordinator: () => BrowserSiteControlsRuntimeCoordinator;
  privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator;
  preferencesRepository: PreferencesRepository;
  resolveSiteDataControlService: () => SiteDataControlService;
  resolveDownloadRuntimeService: () => DownloadRuntimeService;
  resolveTabPreviewCoordinator: () => BrowserTabPreviewCoordinator;
  resolveSnapshotStore: () => WebStateSnapshotStore;
  resolveSitePolicyService: () => SitePolicyService;
  resolvePageFindCoordinator: () => BrowserPageFindCoordinator;
}

export interface BrowserPrivateSessionCleanupShell {
  readFacts: () => BrowserPrivateSessionCleanupFacts;
  notifyTabPreviewChanged: () => void;
}

export interface BrowserPrivateStartupResidualCleanupRequest {
  profileId: BrowserProfileId;
  tabIds: string[];
  snapshotPaths: string[];
  preserveCookiesOnClose: boolean;
}

export class BrowserPrivateSessionCleanupCoordinator {
  private readonly dependencies: BrowserPrivateSessionCleanupDependencies;
  private readonly shell: BrowserPrivateSessionCleanupShell;
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  constructor(
    dependencies: BrowserPrivateSessionCleanupDependencies,
    shell: BrowserPrivateSessionCleanupShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
  }

  buildCleanupPlan(request: BrowserPrivateSessionCleanupRequest): BrowserPrivateSessionCleanupPlan {
    const remainingPrivateTabIds = request.tabs
      .filter((tab: BrowserTabState) => tab.id !== request.closingTabId)
      .filter((tab: BrowserTabState) => {
        return this.profileBoundaryService.isSessionEphemeral({
          profileId: tab.profileId,
          privacyMode: tab.privacyMode,
          dataScope: tab.dataScope,
          sessionId: tab.id
        });
      })
      .map((tab: BrowserTabState) => tab.id);
    const shouldCleanup = remainingPrivateTabIds.length === 0;
    return {
      shouldCleanup: shouldCleanup,
      profileId: request.profileId,
      remainingPrivateTabIds: remainingPrivateTabIds
    };
  }

  async runLastPrivateTabClosedCleanup(profileId: BrowserProfileId, tabId: string): Promise<void> {
    const cleanupRequest = this.buildCleanupRequest(profileId, tabId);
    const cleanupPlan = this.buildCleanupPlan(cleanupRequest);
    const privateTabIds = cleanupPlan.remainingPrivateTabIds.concat([tabId]);
    await this.executeCleanupPlan(
      cleanupPlan,
      cleanupRequest,
      privateTabIds,
      this.dependencies.preferencesRepository.getPreferences().general.privateModePreserveCookiesOnClose
    );
    this.clearSessionPermissions(profileId);
  }

  async runExplicitPrivateModeExitCleanup(
    profileId: BrowserProfileId,
    privateTabIds: string[]
  ): Promise<void> {
    const normalizedPrivateTabIds = this.normalizeTabIds(privateTabIds);
    const tabId = normalizedPrivateTabIds[0] ?? '';
    const currentTabs = this.shell.readFacts().tabs;
    const privateSnapshotPaths =
      this.dependencies.privateProfileLifecycleCoordinator.resolveSessionEphemeralSnapshotPathsForTabStates(currentTabs);
    const remainingTabs = currentTabs.filter((tab: BrowserTabState): boolean => {
      return !normalizedPrivateTabIds.includes(tab.id);
    });
    const cleanupRequest = this.buildCleanupRequest(profileId, tabId, remainingTabs, privateSnapshotPaths);
    const cleanupPlan = this.buildCleanupPlan(cleanupRequest);
    await this.executeCleanupPlan(
      cleanupPlan,
      cleanupRequest,
      normalizedPrivateTabIds,
      false
    );
    this.clearSessionPermissions(profileId);
  }

  async runStartupResidualCleanup(request: BrowserPrivateStartupResidualCleanupRequest): Promise<void> {
    await this.dependencies.resolveSiteDataControlService().clearPrivateSessionData(request.preserveCookiesOnClose);
    this.clearPrivateDownloads(request.profileId);
    const previewRemoved = await this.dependencies.resolveTabPreviewCoordinator()
      .removeSessionEphemeralPreviews(request.tabIds);
    if (previewRemoved) {
      this.shell.notifyTabPreviewChanged();
    }
    await this.clearPrivateSnapshots(request.snapshotPaths);
    this.dependencies.resolveSitePolicyService().clearSessionSitePermissionSettings(request.profileId);
    this.dependencies.resolveSiteControlsRuntimeCoordinator().clearPrivateProtectionSession(request.profileId);
    sharedBrowserHttpsFirstNavigationService.clearPrivateSessionExceptions(request.profileId);
  }

  private async clearPrivateSessionRuntimeData(
    profileId: BrowserProfileId,
    privateTabIds: string[],
    snapshotPaths: string[],
    preserveCookiesOnClose: boolean
  ): Promise<void> {
    await this.dependencies.resolveSiteDataControlService().clearPrivateSessionData(preserveCookiesOnClose);
    this.clearPrivateDownloads(profileId);
    const previewCleanupRemoved = await this.dependencies.resolveTabPreviewCoordinator()
      .removeSessionEphemeralPreviews(privateTabIds);
    if (previewCleanupRemoved) {
      this.shell.notifyTabPreviewChanged();
    }
    await this.clearPrivateSnapshots(snapshotPaths);
  }

  private async executeCleanupPlan(
    cleanupPlan: BrowserPrivateSessionCleanupPlan,
    cleanupRequest: BrowserPrivateSessionCleanupRequest,
    privateTabIds: string[],
    preserveCookiesOnClose: boolean
  ): Promise<void> {
    if (!cleanupPlan.shouldCleanup) {
      return;
    }
    this.dependencies.resolvePageFindCoordinator().clearPrivateTabs(privateTabIds);
    const capabilityPromptCoordinator =
      this.dependencies.resolveWebCapabilityPromptApplicationCoordinator();
    const downloadConfirmOverlayCoordinator = this.dependencies.resolveDownloadConfirmOverlayCoordinator();
    if (cleanupRequest.pendingJsPrompt) {
      capabilityPromptCoordinator.clearPendingJavaScriptPrompt();
    }
    if (cleanupRequest.pendingHttpAuth) {
      capabilityPromptCoordinator.clearPendingHttpAuthState();
    }
    if (cleanupRequest.activeDownloadPromptLease) {
      downloadConfirmOverlayCoordinator.releaseActiveLease('dismiss');
    }
    if (cleanupRequest.pendingDownloadPrompt) {
      downloadConfirmOverlayCoordinator.clearForPrivateSessionCleanup();
    }
    if (cleanupRequest.externalNavigationUrl.trim().length > 0) {
      this.dependencies.resolveExternalNavigationRuntimeStateCoordinator().clearDuplicatePromptRecord();
    }
    if (cleanupRequest.sitePermissionRelatedOriginCount > 0) {
      this.dependencies.resolveSiteControlsRuntimeCoordinator().clearRelatedOrigins();
    }
    this.dependencies.resolveSiteControlsRuntimeCoordinator().clearPrivateProtectionSession(cleanupPlan.profileId);
    sharedBrowserHttpsFirstNavigationService.clearPrivateSessionExceptions(cleanupPlan.profileId);
    await this.clearPrivateSessionRuntimeData(
      cleanupPlan.profileId,
      privateTabIds,
      cleanupRequest.persistedEphemeralSnapshotPaths,
      preserveCookiesOnClose
    );
  }

  private clearSessionPermissions(profileId: BrowserProfileId): void {
    this.dependencies.resolveSitePolicyService().clearSessionSitePermissionSettings(profileId);
  }

  private buildCleanupRequest(
    profileId: BrowserProfileId,
    tabId: string,
    tabs?: BrowserTabState[],
    snapshotPaths?: string[]
  ): BrowserPrivateSessionCleanupRequest {
    const facts = this.shell.readFacts();
    const sourceTabs = tabs ?? facts.tabs;
    const persistedEphemeralSnapshotPaths = snapshotPaths ??
      this.dependencies.privateProfileLifecycleCoordinator.resolveSessionEphemeralSnapshotPathsForTabStates(sourceTabs);
    const capabilityPromptCoordinator =
      this.dependencies.resolveWebCapabilityPromptApplicationCoordinator();
    const downloadConfirmOverlayCoordinator = this.dependencies.resolveDownloadConfirmOverlayCoordinator();
    return {
      tabs: sourceTabs,
      closingTabId: tabId,
      profileId: profileId,
      pendingJsPrompt: capabilityPromptCoordinator.hasPendingJavaScriptPrompt(),
      pendingHttpAuth: capabilityPromptCoordinator.hasPendingHttpAuth(),
      pendingDownloadPrompt: facts.pendingDownloadPrompt,
      activeDownloadPromptLease: downloadConfirmOverlayCoordinator.hasActiveLease(),
      externalNavigationUrl:
        this.dependencies.resolveExternalNavigationRuntimeStateCoordinator().resolveDuplicateUrl(),
      sitePermissionRelatedOriginCount:
        this.dependencies.resolveSiteControlsRuntimeCoordinator().getRelatedOriginCount(),
      persistedEphemeralSnapshotPaths: persistedEphemeralSnapshotPaths
    };
  }

  private clearPrivateDownloads(profileId: BrowserProfileId): void {
    const facts = this.shell.readFacts();
    this.dependencies.resolveDownloadRuntimeService().clearPrivateDownloadSessionForWindow(
      facts.currentWindowId,
      profileId,
      'private',
      'session_ephemeral'
    );
  }

  private async clearPrivateSnapshots(snapshotPaths: string[]): Promise<void> {
    const snapshotStore = this.dependencies.resolveSnapshotStore();
    for (let index = 0; index < snapshotPaths.length; index++) {
      await snapshotStore.deleteSnapshotIfExists(snapshotPaths[index]);
    }
  }

  private normalizeTabIds(tabIds: string[]): string[] {
    const normalizedTabIds: string[] = [];
    tabIds.forEach((tabId: string): void => {
      const normalizedTabId = tabId.trim();
      if (normalizedTabId.length > 0 && !normalizedTabIds.includes(normalizedTabId)) {
        normalizedTabIds.push(normalizedTabId);
      }
    });
    return normalizedTabIds;
  }
}
