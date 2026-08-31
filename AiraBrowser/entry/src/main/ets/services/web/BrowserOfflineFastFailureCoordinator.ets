import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../common/models/BrowserModels';
import {
  BrowserTabState,
  BrowserTabManagerPort
} from '../../core/tabs/TabManager';
import { BrowserWebLoadFailureSurfaceCoordinator } from '../../core/browser/BrowserWebLoadFailureSurfaceCoordinator';
import {
  WebNetworkAvailabilityService,
  WebNetworkAvailabilitySnapshot
} from './WebNetworkAvailabilityService';

export interface BrowserOfflineFastFailureCoordinatorHost {
  readFacts: () => BrowserOfflineFastFailureFacts;
}

export interface BrowserOfflineFastFailureFacts {
  tabs: BrowserTabState[];
  activeTabId: string;
  pendingWebUrl: string;
  homeSurfaceVisible: boolean;
  loading: boolean;
}

export interface BrowserOfflineFastFailureApplication {
  applyOfflineFastFailure: (
    tabId: string,
    targetUrl: string,
    errorMessage: string,
    fallbackTab: BrowserTabState
  ) => void;
}

export interface BrowserOfflineFastFailureCoordinatorDependencies {
  tabManager: BrowserTabManagerPort;
  loadFailureSurfaceCoordinator: BrowserWebLoadFailureSurfaceCoordinator;
  resolveApplication: () => BrowserOfflineFastFailureApplication;
}

export class BrowserOfflineFastFailureCoordinator {
  private readonly host: BrowserOfflineFastFailureCoordinatorHost;
  private readonly dependencies: BrowserOfflineFastFailureCoordinatorDependencies;
  private readonly service: WebNetworkAvailabilityService;
  private readonly delayMs: number;
  private timer: number = -1;
  private scheduledTabId: string = '';

  constructor(
    dependencies: BrowserOfflineFastFailureCoordinatorDependencies,
    host: BrowserOfflineFastFailureCoordinatorHost,
    delayMs: number,
    service: WebNetworkAvailabilityService = new WebNetworkAvailabilityService()
  ) {
    this.dependencies = dependencies;
    this.host = host;
    this.delayMs = delayMs;
    this.service = service;
  }

  startMonitoring(): void {
    this.service.start((snapshot: WebNetworkAvailabilitySnapshot): void => {
      this.handleNetworkAvailabilityChanged(snapshot);
    });
  }

  stopMonitoring(): void {
    this.service.stop();
    this.cancelTimer();
  }

  shouldFastFailNavigation(targetUrl: string): boolean {
    return this.service.shouldFastFailNavigation(targetUrl);
  }

  buildOfflineMessage(): string {
    return this.service.buildOfflineMessage();
  }

  isNetworkNavigationUrl(targetUrl: string): boolean {
    return this.service.isNetworkNavigationUrl(targetUrl);
  }

  applyIfNeeded(tabId: string, targetUrl: string): boolean {
    if (!this.service.shouldFastFailNavigation(targetUrl)) {
      return false;
    }
    this.apply(tabId, targetUrl, 'offline_before_navigation');
    return true;
  }

  scheduleForLoadingTab(tabId: string, targetUrl: string): void {
    if (!this.service.isNetworkNavigationUrl(targetUrl)) {
      return;
    }
    const snapshot = this.service.refresh();
    if (!snapshot.reliable || snapshot.available) {
      return;
    }
    this.cancelTimer();
    this.scheduledTabId = tabId;
    this.timer = setTimeout(() => {
      this.timer = -1;
      const scheduledTabId = this.scheduledTabId;
      this.scheduledTabId = '';
      const tab = this.dependencies.tabManager.getTab(this.host.readFacts().tabs, scheduledTabId);
      if (tab === undefined || tab.runtimeState !== 'loading') {
        return;
      }
      const currentTargetUrl = tab.pendingUrl.length > 0 ? tab.pendingUrl : targetUrl;
      if (this.service.shouldFastFailNavigation(currentTargetUrl)) {
        this.apply(scheduledTabId, currentTargetUrl, 'offline_during_navigation');
      }
    }, this.delayMs);
  }

  cancelForTab(tabId: string): void {
    if (this.scheduledTabId !== tabId) {
      return;
    }
    this.cancelTimer();
  }

  private handleNetworkAvailabilityChanged(snapshot: WebNetworkAvailabilitySnapshot): void {
    if (!snapshot.reliable || snapshot.available) {
      return;
    }
    const facts = this.host.readFacts();
    const activeTab = this.dependencies.tabManager.getActiveTab(facts.tabs, facts.activeTabId);
    if (activeTab === undefined || activeTab.isHome || facts.homeSurfaceVisible || !facts.loading ||
      this.dependencies.loadFailureSurfaceCoordinator.shouldShow(activeTab.id)) {
      return;
    }
    const pendingUrl = facts.pendingWebUrl;
    const targetUrl = pendingUrl.length > 0
      ? pendingUrl
      : activeTab.pendingUrl.length > 0 ? activeTab.pendingUrl : activeTab.url;
    this.scheduleForLoadingTab(activeTab.id, targetUrl);
  }

  private cancelTimer(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    this.scheduledTabId = '';
  }

  private apply(tabId: string, targetUrl: string, source: string): void {
    const normalizedTargetUrl = targetUrl.trim();
    if (normalizedTargetUrl.length <= 0 || !this.service.isNetworkNavigationUrl(normalizedTargetUrl)) {
      return;
    }
    const errorMessage = this.service.buildOfflineMessage();
    this.cancelForTab(tabId);
    this.dependencies.resolveApplication().applyOfflineFastFailure(
      tabId,
      normalizedTargetUrl,
      errorMessage,
      this.buildFailureFallbackTab(tabId, normalizedTargetUrl, errorMessage)
    );
  }

  private buildFailureFallbackTab(tabId: string, targetUrl: string, errorMessage: string): BrowserTabState {
    return {
      id: tabId,
      profileId: DEFAULT_BROWSER_PROFILE_ID as BrowserProfileId,
      title: targetUrl,
      url: targetUrl,
      isHome: false,
      lastActiveAt: Date.now(),
      pendingUrl: targetUrl,
      navigationHistory: [],
      navigationIndex: -1,
      runtimeState: 'error',
      lastError: errorMessage,
      lastRestoreReason: '',
      lastDiscardReason: '',
      lastCrashReason: '',
      lastLoadedAt: 0,
      webStatePath: '',
      webStateUpdatedAt: 0,
      scrollOffsetY: 0,
      lastGoodUrl: '',
      lastGoodTitle: '',
      lastRestorableUrl: '',
      lastRestorableTitle: '',
      lastRestoreType: 'none',
      privacyMode: 'regular' as BrowserSessionPrivacyMode,
      dataScope: 'profile_persistent' as BrowserDataScope,
      launchContext: {
        sourceType: '',
        sourceId: '',
        sourceUrl: '',
        key: ''
      },
      openerTabId: '',
      openSource: '',
      openedByNewWindow: false,
      pinned: false,
      muted: false,
      audible: false
    };
  }
}
