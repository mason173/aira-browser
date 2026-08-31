import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  CreateHistoryVisitCommand,
  TabCrashReason,
  buildBrowserDataBoundary
} from '../../common/models/BrowserModels';
import { BrowserTabRuntimePatch, BrowserTabState, BrowserTabManagerPort } from '../tabs/TabManager';
import { WebPageEventRoute } from '../web/WebEventRouter';
import { WebRecoveryManager } from '../web/WebRecoveryManager';
import { WebPagePresentation } from '../web/WebRuntimeBridge';
import { WebSessionStatePatch } from '../web/WebSessionStateStore';
import { WebStateSnapshotRecord } from '../web/WebStateSnapshotStore';
import { BrowserFaultClassifier, BrowserFaultDescriptor } from './BrowserFaultClassifier';
import {
  BrowserWebActiveSurfaceScrollSource
} from './BrowserWebActiveSurfaceCoordinator';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';

export interface BrowserWebEventCommit {
  tabPatch: BrowserTabRuntimePatch;
  shouldApplyActivePresentation: boolean;
  shouldSyncEventContext: boolean;
  shouldReleaseEventContext: boolean;
  shouldRecordNavigationHistory: boolean;
  navigationUrl: string;
  navigationTitle: string;
  shouldPersistActiveSnapshot: boolean;
  snapshotReason: string;
  activeSurfacePlan: BrowserWebActiveSurfacePlan;
}

export interface BrowserWebRuntimeEventCommit {
  type: string;
  message: string;
}

export type BrowserWebCertificateRefreshAction = 'none' | 'set_loading' | 'refresh';

export interface BrowserWebActiveSurfacePlan {
  shouldApplyVisualState: boolean;
  shouldRefreshPermissions: boolean;
  certificateAction: BrowserWebCertificateRefreshAction;
  shouldRefreshTracking: boolean;
  shouldSyncNavigationState: boolean;
  shouldPersistActiveSnapshot: boolean;
  snapshotReason: string;
}

export interface BrowserWebHistoryVisitCommit {
  shouldRecord: boolean;
  historyKey: string;
  skipReason?: BrowserHistoryVisitSkipReason;
  command?: CreateHistoryVisitCommand;
}

export type BrowserHistoryVisitSkipReason =
  'privacy_boundary' |
  'internal_url' |
  'duplicate_window';

export interface BrowserWebNavigationHistoryCommitInput {
  tabManager: BrowserTabManagerPort;
  tabs: BrowserTabState[];
  activeTabId: string;
  tabId: string;
  url: string;
  title: string;
}

export interface BrowserWebNavigationHistoryMetadataHost {
  resolveTabs: () => BrowserTabState[];
  resolveActiveTabId: () => string;
  applyTabs: (tabs: BrowserTabState[]) => void;
  shouldSkipDownloadTabStatePersistence: (tabId: string, url: string, source: string) => boolean;
  refreshRuntimeTab: (tabId: string) => void;
  syncNavigationState: () => void;
  persistTabs: () => void;
}

export interface BrowserWebNavigationHistoryCommit {
  handled: boolean;
  tabs: BrowserTabState[];
  shouldSyncActiveNavigation: boolean;
}

export interface BrowserWebFollowupCommit {
  shouldHandleActiveTab: boolean;
  shouldSyncNavigationState: boolean;
  shouldUpdateProgress: boolean;
  pageProgress: number;
}

export interface BrowserWebSnapshotPersistCommit {
  tabPatch: BrowserTabRuntimePatch;
  runtimeEvent: BrowserWebRuntimeEventCommit;
  restoreTraceBreadcrumb: string;
}

export interface BrowserWebSnapshotRestoreSuccessCommit {
  runtimeEvent: BrowserWebRuntimeEventCommit;
  restoreTraceBreadcrumb: string;
  activeSurfacePlan: BrowserWebActiveSurfacePlan;
}

export interface BrowserWebPageBeginCommitInput {
  route: WebPageEventRoute;
  presentation: WebPagePresentation;
}

export interface BrowserWebPageEndCommitInput {
  route: WebPageEventRoute;
  presentation: WebPagePresentation;
  sessionPatch: WebSessionStatePatch;
  isRestorableNavigation?: boolean;
  shouldPromoteRestorableState?: boolean;
}

export interface BrowserWebLoadFailureSideEffectInput {
  tabId: string;
  errorMessage: string;
  tab?: BrowserTabState;
  shouldHandleActiveTab: boolean;
  recoveryManager: WebRecoveryManager;
  faultClassifier: BrowserFaultClassifier;
}

export interface BrowserWebLoadFailureSideEffect {
  fault: BrowserFaultDescriptor;
  shouldFallbackToHome: boolean;
  degradedReason: string;
  tabPatch: BrowserTabRuntimePatch;
  activeSurfacePlan: BrowserWebActiveSurfacePlan;
}

export interface BrowserWebPageCommitHost {
  rememberTabNavigation: (tabId: string, url: string) => void;
  rememberProvisionalTabNavigation: (tabId: string, url: string) => void;
  applyTabPatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
  syncEventContext: (tabId: string, resolvedUrl: string) => void;
  updateControllerAttachedFromRuntime: (tabId: string) => void;
  applyPagePresentation: (
    tabId: string,
    plan: BrowserWebActiveSurfacePlan,
    presentation: WebPagePresentation,
    scrollSource: BrowserWebActiveSurfaceScrollSource
  ) => void;
  recordHistoryVisit: (tabId: string, url: string, title: string) => void;
  recordTabNavigationMetadata: (tabId: string, url: string, title: string) => void;
  shouldSkipTabStatePersistence: (tabId: string, url: string) => boolean;
  syncNavigationState: () => void;
  syncNavigationStateSoon: () => void;
  releaseEventContext: (tabId: string) => void;
}

export interface BrowserWebLoadFailureHost {
  markTabCrashed: (tabId: string, degradedReason: string, crashReason: TabCrashReason) => void;
  applyTabPatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
  applyLoadFailurePresentation: (
    tabId: string,
    plan: BrowserWebActiveSurfacePlan,
    userMessage: string,
    degradedReason: string
  ) => void;
  degradeBrokenActiveTabToHome: () => void;
}

export interface BrowserWebFollowupEventHost {
  syncNavigationState: () => void;
  syncNavigationStateSoon: () => void;
  setPageProgress: (pageProgress: number) => void;
  rememberTabNavigation: (tabId: string, url: string) => void;
  rememberProvisionalTabNavigation: (tabId: string, url: string) => void;
  applyNavigationCommittedPatch: (tabId: string, url: string) => void;
  updateActiveCommittedUrl: (url: string) => void;
  shouldSkipTabStatePersistence: (tabId: string, url: string) => boolean;
  applyTabTitle: (tabId: string, title: string) => void;
  updateActiveTitle: (title: string) => void;
}

export class BrowserWebEventCommitCoordinator {
  private lastRecordedHistoryKeyBySessionId: Record<string, string | undefined> = {};
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;

  constructor(privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService()) {
    this.privacyEffectPolicy = privacyEffectPolicy;
  }

  buildPageBeginCommit(input: BrowserWebPageBeginCommitInput): BrowserWebEventCommit {
    const resolvedUrl = input.route.resolvedUrl;
    return {
      tabPatch: {
        isHome: false,
        runtimeState: 'loading',
        lastError: '',
        lastCrashReason: '',
        webStatePath: '',
        webStateUpdatedAt: 0
      },
      shouldApplyActivePresentation: input.route.shouldHandleActiveTab,
      shouldSyncEventContext: input.route.shouldSyncEventContext,
      shouldReleaseEventContext: false,
      shouldRecordNavigationHistory: false,
      navigationUrl: resolvedUrl,
      navigationTitle: input.presentation.currentTitle,
      shouldPersistActiveSnapshot: false,
      snapshotReason: '',
      activeSurfacePlan: {
        shouldApplyVisualState: input.route.shouldHandleActiveTab,
        shouldRefreshPermissions: input.route.shouldHandleActiveTab,
        certificateAction: input.route.shouldHandleActiveTab ? 'set_loading' : 'none',
        shouldRefreshTracking: input.route.shouldHandleActiveTab,
        shouldSyncNavigationState: false,
        shouldPersistActiveSnapshot: false,
        snapshotReason: ''
      }
    };
  }

  buildPageEndCommit(input: BrowserWebPageEndCommitInput): BrowserWebEventCommit {
    const resolvedUrl = input.route.resolvedUrl;
    const shouldPromoteRestorableState = input.shouldPromoteRestorableState ?? true;
    const shouldRecordNavigationHistory = input.isRestorableNavigation ?? shouldPromoteRestorableState;
    return {
      tabPatch: {
        title: input.presentation.currentTitle,
        url: shouldPromoteRestorableState ? resolvedUrl : undefined,
        pendingUrl: shouldPromoteRestorableState ? resolvedUrl : undefined,
        isHome: false,
        runtimeState: 'active',
        lastError: '',
        lastRestoreReason: '',
        lastDiscardReason: '',
        lastCrashReason: '',
        lastLoadedAt: input.sessionPatch.lastLoadedAt,
        lastGoodUrl: shouldPromoteRestorableState ? input.sessionPatch.lastGoodUrl : undefined,
        lastGoodTitle: shouldPromoteRestorableState ? input.sessionPatch.lastGoodTitle : undefined,
        lastRestorableUrl: shouldPromoteRestorableState ? input.sessionPatch.lastRestorableUrl : undefined,
        lastRestorableTitle: shouldPromoteRestorableState ? input.sessionPatch.lastRestorableTitle : undefined
      },
      shouldApplyActivePresentation: input.route.shouldHandleActiveTab,
      shouldSyncEventContext: false,
      shouldReleaseEventContext: input.route.shouldReleaseEventContext,
      shouldRecordNavigationHistory: shouldRecordNavigationHistory,
      navigationUrl: resolvedUrl,
      navigationTitle: input.presentation.currentTitle,
      shouldPersistActiveSnapshot: shouldPromoteRestorableState && input.route.shouldHandleActiveTab,
      snapshotReason: 'page-end',
      activeSurfacePlan: {
        shouldApplyVisualState: input.route.shouldHandleActiveTab,
        shouldRefreshPermissions: input.route.shouldHandleActiveTab,
        certificateAction: input.route.shouldHandleActiveTab ? 'refresh' : 'none',
        shouldRefreshTracking: input.route.shouldHandleActiveTab,
        shouldSyncNavigationState: false,
        shouldPersistActiveSnapshot: shouldPromoteRestorableState && input.route.shouldHandleActiveTab,
        snapshotReason: shouldPromoteRestorableState ? 'page-end' : ''
      }
    };
  }

  applyPageBeginCommit(
    tabId: string,
    resolvedUrl: string,
    presentation: WebPagePresentation,
    commit: BrowserWebEventCommit,
    host: BrowserWebPageCommitHost
  ): void {
    host.rememberProvisionalTabNavigation(tabId, resolvedUrl);
    host.applyTabPatch(tabId, commit.tabPatch);
    if (!commit.shouldApplyActivePresentation) {
      return;
    }
    if (commit.shouldSyncEventContext) {
      host.syncEventContext(tabId, resolvedUrl);
    }
    host.updateControllerAttachedFromRuntime(tabId);
    host.applyPagePresentation(tabId, commit.activeSurfacePlan, presentation, 'navigation_restore');
  }

  applyPageEndCommit(
    tabId: string,
    resolvedUrl: string,
    presentation: WebPagePresentation,
    commit: BrowserWebEventCommit,
    host: BrowserWebPageCommitHost
  ): void {
    if (commit.shouldRecordNavigationHistory) {
      host.rememberTabNavigation(tabId, resolvedUrl);
    } else {
      host.rememberProvisionalTabNavigation(tabId, resolvedUrl);
    }
    host.applyTabPatch(tabId, commit.tabPatch);
    if (commit.shouldRecordNavigationHistory && !host.shouldSkipTabStatePersistence(tabId, commit.navigationUrl)) {
      host.recordHistoryVisit(tabId, commit.navigationUrl, commit.navigationTitle);
      host.recordTabNavigationMetadata(tabId, commit.navigationUrl, commit.navigationTitle);
    }
    if (commit.shouldApplyActivePresentation) {
      host.syncNavigationState();
      host.syncNavigationStateSoon();
    }
    if (!commit.shouldApplyActivePresentation) {
      return;
    }
    if (commit.shouldReleaseEventContext) {
      host.releaseEventContext(tabId);
    }
    host.applyPagePresentation(
      tabId,
      commit.activeSurfacePlan,
      presentation,
      'navigation_restore'
    );
  }

  applyMainFrameLoadFailure(
    tabId: string,
    sideEffect: BrowserWebLoadFailureSideEffect,
    host: BrowserWebLoadFailureHost
  ): void {
    if (sideEffect.shouldFallbackToHome) {
      host.markTabCrashed(
        tabId,
        sideEffect.degradedReason,
        sideEffect.fault.crashReason ?? 'main_frame_error'
      );
    }
    host.applyTabPatch(tabId, sideEffect.tabPatch);
    host.applyLoadFailurePresentation(
      tabId,
      sideEffect.activeSurfacePlan,
      sideEffect.fault.userMessage,
      sideEffect.degradedReason
    );
    if (sideEffect.shouldFallbackToHome) {
      host.degradeBrokenActiveTabToHome();
    }
  }

  applyLoadFinishedCommit(tabId: string, commit: BrowserWebFollowupCommit, host: BrowserWebFollowupEventHost): void {
    if (!commit.shouldSyncNavigationState) {
      return;
    }
    host.syncNavigationState();
    host.syncNavigationStateSoon();
  }

  applyProgressCommit(commit: BrowserWebFollowupCommit, host: BrowserWebFollowupEventHost): void {
    if (!commit.shouldUpdateProgress) {
      return;
    }
    host.setPageProgress(commit.pageProgress);
  }

  applyNavigationEntryCommittedCommit(
    tabId: string,
    committedUrl: string,
    isMainFrame: boolean,
    shouldHandleActiveTab: boolean,
    commit: BrowserWebFollowupCommit,
    host: BrowserWebFollowupEventHost
  ): void {
    if (isMainFrame && committedUrl.length > 0 && !host.shouldSkipTabStatePersistence(tabId, committedUrl)) {
      host.rememberProvisionalTabNavigation(tabId, committedUrl);
      host.applyNavigationCommittedPatch(tabId, committedUrl);
      if (shouldHandleActiveTab) {
        host.updateActiveCommittedUrl(committedUrl);
      }
    }
    if (!commit.shouldSyncNavigationState) {
      return;
    }
    host.syncNavigationState();
    host.syncNavigationStateSoon();
  }

  applyTitleReceive(
    tabId: string,
    title: string,
    shouldUpdateTabTitle: boolean,
    shouldUpdateActiveTitle: boolean,
    host: BrowserWebFollowupEventHost
  ): void {
    if (!shouldUpdateTabTitle) {
      return;
    }
    host.applyTabTitle(tabId, title);
    if (shouldUpdateActiveTitle) {
      host.updateActiveTitle(title);
    }
  }

  buildHistoryVisitCommit(
    tabId: string,
    url: string,
    title: string,
    now: number = Date.now(),
    dataScope: BrowserDataScope = 'profile_persistent',
    privacyMode: BrowserSessionPrivacyMode = 'regular'
  ): BrowserWebHistoryVisitCommit {
    const boundary = buildBrowserDataBoundary({
      privacyMode: privacyMode,
      dataScope: dataScope,
      sessionId: tabId
    });
    if (!this.privacyEffectPolicy.shouldWritePersistentDataForBoundary('history_visit', boundary)) {
      return {
        shouldRecord: false,
        historyKey: '',
        skipReason: 'privacy_boundary'
      };
    }
    if (!this.shouldRecordHistoryUrl(url)) {
      return {
        shouldRecord: false,
        historyKey: '',
        skipReason: 'internal_url'
      };
    }
    const historyKey = `${url}|${Math.floor(now / 5000)}`;
    const sessionId = boundary.sessionId;
    if (this.lastRecordedHistoryKeyBySessionId[sessionId] === historyKey) {
      return {
        shouldRecord: false,
        historyKey: historyKey,
        skipReason: 'duplicate_window'
      };
    }
    this.lastRecordedHistoryKeyBySessionId[sessionId] = historyKey;
    return {
      shouldRecord: true,
      historyKey: historyKey,
      command: {
        title: title,
        url: url,
        visitedAt: now,
        sessionId: boundary.sessionId,
        profileId: boundary.profileId,
        dataScope: boundary.dataScope
      }
    };
  }

  commitNavigationHistory(input: BrowserWebNavigationHistoryCommitInput): BrowserWebNavigationHistoryCommit {
    const targetTab = input.tabs.find((tab: BrowserTabState) => tab.id === input.tabId);
    if (targetTab === undefined) {
      return {
        handled: false,
        tabs: input.tabs,
        shouldSyncActiveNavigation: false
      };
    }
    const nextTabs = input.tabManager.recordNavigationForTab(input.tabs, input.tabId, input.url, input.title);
    return {
      handled: true,
      tabs: nextTabs,
      shouldSyncActiveNavigation: input.tabId === input.activeTabId
    };
  }

  recordNavigationMetadata(
    tabManager: BrowserTabManagerPort,
    tabId: string,
    url: string,
    title: string,
    host: BrowserWebNavigationHistoryMetadataHost
  ): void {
    if (host.shouldSkipDownloadTabStatePersistence(tabId, url, 'record_web_navigation')) {
      return;
    }
    const commit = this.commitNavigationHistory({
      tabManager: tabManager,
      tabs: host.resolveTabs(),
      activeTabId: host.resolveActiveTabId(),
      tabId: tabId,
      url: url,
      title: title
    });
    if (!commit.handled) {
      return;
    }
    host.applyTabs(commit.tabs);
    host.refreshRuntimeTab(tabId);
    if (commit.shouldSyncActiveNavigation) {
      host.syncNavigationState();
    }
    host.persistTabs();
  }

  buildLoadFinishedCommit(shouldHandleActiveTab: boolean): BrowserWebFollowupCommit {
    return {
      shouldHandleActiveTab: shouldHandleActiveTab,
      shouldSyncNavigationState: shouldHandleActiveTab,
      shouldUpdateProgress: shouldHandleActiveTab,
      pageProgress: 100
    };
  }

  buildProgressCommit(shouldHandleActiveTab: boolean, nextProgress: number): BrowserWebFollowupCommit {
    return {
      shouldHandleActiveTab: shouldHandleActiveTab,
      shouldSyncNavigationState: false,
      shouldUpdateProgress: shouldHandleActiveTab,
      pageProgress: this.clampProgress(nextProgress)
    };
  }

  buildNavigationEntryCommittedCommit(shouldHandleActiveTab: boolean, isMainFrame: boolean): BrowserWebFollowupCommit {
    const shouldSyncNavigationState = shouldHandleActiveTab && isMainFrame;
    return {
      shouldHandleActiveTab: shouldHandleActiveTab,
      shouldSyncNavigationState: shouldSyncNavigationState,
      shouldUpdateProgress: false,
      pageProgress: 0
    };
  }

  buildSnapshotPersistCommit(reason: string, snapshot: WebStateSnapshotRecord): BrowserWebSnapshotPersistCommit {
    return {
      tabPatch: {
        webStatePath: snapshot.path,
        webStateUpdatedAt: snapshot.updatedAt,
        runtimeState: 'active',
        lastError: '',
        lastCrashReason: ''
      },
      runtimeEvent: {
        type: 'snapshot_saved_active',
        message: `${reason} 已保存快照 ${snapshot.path}`
      },
      restoreTraceBreadcrumb: `snapshot_saved ${reason}`
    };
  }

  buildSnapshotRestoreSuccessCommit(snapshotPath: string): BrowserWebSnapshotRestoreSuccessCommit {
    return {
      runtimeEvent: {
        type: 'snapshot_restore_success',
        message: `已从快照恢复 ${snapshotPath}`
      },
      restoreTraceBreadcrumb: `snapshot_restore_success ${snapshotPath}`,
      activeSurfacePlan: {
        shouldApplyVisualState: true,
        shouldRefreshPermissions: false,
        certificateAction: 'refresh',
        shouldRefreshTracking: true,
        shouldSyncNavigationState: true,
        shouldPersistActiveSnapshot: false,
        snapshotReason: ''
      }
    };
  }

  commitMainFrameLoadFailure(input: BrowserWebLoadFailureSideEffectInput): BrowserWebLoadFailureSideEffect {
    const isRestoreFailure = input.recoveryManager.shouldTreatLoadFailureAsRestoreFailure(
      input.tab
    );
    if (isRestoreFailure) {
      input.recoveryManager.recordLoadFailure(input.tabId, input.errorMessage);
    }
    const shouldFallbackToHome = isRestoreFailure && input.recoveryManager.shouldFallbackTabToHome(input.tabId);
    const fault = input.faultClassifier.classifyMainFrameError(input.errorMessage, shouldFallbackToHome);
    return {
      fault: fault,
      shouldFallbackToHome: shouldFallbackToHome,
      degradedReason: input.recoveryManager.getDegradedReason(input.tabId),
      tabPatch: {
        runtimeState: shouldFallbackToHome ? 'crashed' : 'error',
        lastError: fault.userMessage,
        lastCrashReason: shouldFallbackToHome ? (fault.crashReason ?? 'main_frame_error') : '',
        webStatePath: '',
        webStateUpdatedAt: 0
      },
      activeSurfacePlan: {
        shouldApplyVisualState: input.shouldHandleActiveTab,
        shouldRefreshPermissions: false,
        certificateAction: 'none',
        shouldRefreshTracking: false,
        shouldSyncNavigationState: input.shouldHandleActiveTab,
        shouldPersistActiveSnapshot: false,
        snapshotReason: ''
      }
    };
  }

  private shouldRecordHistoryUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    if (normalized.length === 0) {
      return false;
    }
    if (normalized.startsWith('about:') ||
      normalized.startsWith('data:') ||
      normalized.startsWith('file:') ||
      normalized.startsWith('aira://')) {
      return false;
    }
    return true;
  }

  private clampProgress(progress: number): number {
    if (progress < 0) {
      return 0;
    }
    if (progress > 100) {
      return 100;
    }
    return Math.floor(progress);
  }
}
