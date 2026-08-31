import { BrowserMediaDiscoveryCoordinator } from './media/BrowserMediaDiscoveryCoordinator';
import { BrowserMediaDiscoveryHost } from './media/BrowserMediaDiscoveryModels';
import { BrowserAdBlockCoordinator } from './BrowserAdBlockCoordinator';
import { BrowserBackgroundTabPreviewRuntimeCoordinator } from './BrowserBackgroundTabPreviewRuntimeCoordinator';
import { BrowserSiteControlsRuntimeCoordinator } from './BrowserSiteControlsRuntimeCoordinator';
import { BrowserPageChromeThemeSamplingCoordinator } from './BrowserPageChromeThemeSamplingCoordinator';
import {
  BrowserPrivateProfileCookieLifecycleHost,
  BrowserPrivateProfileLifecycleCoordinator
} from './BrowserPrivateProfileLifecycleCoordinator';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import {
  BrowserFaviconCoordinator,
  sharedBrowserFaviconCoordinator
} from './BrowserFaviconCoordinator';
import { BrowserTabManagerPort } from '../tabs/TabManager';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { ManualElementHideRuntimeCoordinator } from '../adblock/ManualElementHideRuntimeCoordinator';
import { UserScriptRuntimeCoordinator } from '../userscripts/UserScriptRuntimeCoordinator';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import { BrowserWebPageLifecycleApplicationHost } from './BrowserWebPageLifecycleModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN: number = 0x0000;
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG: string = 'HomeSearchDiag';
const FAVICON_DEEP_DISCOVERY_INITIAL_DELAY_MS: number = 700;

interface PendingFaviconDeepDiscovery {
  documentUrl: string;
  navigationIndex: number;
  navigationKey: string;
  timerId: number;
}

export interface BrowserWebPageFeatureEffectsDependencies {
  tabManager: BrowserTabManagerPort;
  adBlockCoordinator: BrowserAdBlockCoordinator;
  siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator;
  mediaDiscoveryCoordinator: BrowserMediaDiscoveryCoordinator;
  mediaDiscoveryHost: BrowserMediaDiscoveryHost;
  pageChromeThemeSamplingCoordinator: BrowserPageChromeThemeSamplingCoordinator;
  privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator;
  privateProfileCookieLifecycleHost: BrowserPrivateProfileCookieLifecycleHost;
  backgroundTabPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  preferencesRepository: PreferencesRepository;
  manualElementHideRuntimeCoordinator: ManualElementHideRuntimeCoordinator;
  userScriptRuntimeCoordinator: UserScriptRuntimeCoordinator;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  faviconCoordinator?: BrowserFaviconCoordinator;
}

export class BrowserWebPageFeatureEffectsCoordinator {
  private readonly dependencies: BrowserWebPageFeatureEffectsDependencies;
  private readonly faviconCoordinator: BrowserFaviconCoordinator;
  private pendingFaviconDeepDiscoveryByTabId: Record<string, PendingFaviconDeepDiscovery | undefined> = {};
  private completedFaviconDeepDiscoveryKeyByTabId: Record<string, string | undefined> = {};

  constructor(dependencies: BrowserWebPageFeatureEffectsDependencies) {
    this.dependencies = dependencies;
    this.faviconCoordinator = dependencies.faviconCoordinator ?? sharedBrowserFaviconCoordinator;
  }

  prepareForPageBegin(tabId: string, host: BrowserWebPageLifecycleApplicationHost): void {
    this.clearFaviconDeepDiscovery(tabId);
    if (this.dependencies.tabScopedEventContextCoordinator.resolvePrivacyMode(tabId) === 'private') {
      this.dependencies.userScriptRuntimeCoordinator.clearAutomaticInjectionDocumentForPage(tabId);
    }
    this.dependencies.adBlockCoordinator.resetPageStats(tabId);
    this.dependencies.siteControlsRuntimeCoordinator.resetPageProtectionFeedback(tabId);
    this.dependencies.mediaDiscoveryCoordinator.clearTabForNavigation(tabId);
    const facts = host.resolveShellFacts();
    if (tabId === facts.activeTabId && facts.webPageVisible) {
      this.dependencies.mediaDiscoveryCoordinator.refreshActiveMediaDiscoverySurface(
        this.dependencies.mediaDiscoveryHost
      );
    }
  }

  applyActivePageBeginChromeEffects(host: BrowserWebPageLifecycleApplicationHost): void {
    const facts = host.resolveShellFacts();
    if (!facts.renderedPageErrorSurfaceVisible) {
      host.applyErrorSurfaceState({
        visible: facts.pageErrorSurfaceVisible,
        reloadHold: false,
        retryTabId: facts.activeErrorDocumentRetryTabId
      });
    }
    this.dependencies.siteControlsRuntimeCoordinator.refreshActiveProtectionPresentation();
  }

  applyActivePageEndChromeEffects(tabId: string, host: BrowserWebPageLifecycleApplicationHost): void {
    const facts = host.resolveShellFacts();
    host.applyErrorSurfaceState({
      visible: facts.pageErrorSurfaceVisible,
      reloadHold: false,
      retryTabId: ''
    });
    this.scheduleTabPageChromeThemeProbe(tabId);
    this.scheduleTabPageChromeVisualSample(tabId);
  }

  applyActiveLoadFinishedChromeEffects(tabId: string, host: BrowserWebPageLifecycleApplicationHost): void {
    this.scheduleTabPageChromeThemeProbe(tabId);
    this.scheduleTabPageChromeVisualSample(tabId);
  }

  applyLoadFinishedEffects(
    tabId: string,
    url: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    this.scheduleCurrentPageIconCandidates(tabId, url, host);
  }

  applyPageEndEffects(
    tabId: string,
    url: string,
    title: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    this.injectAdBlockCosmeticRulesForPage(tabId, url, host);
    this.applyManualElementHideRulesForPage(tabId, url);
    this.scheduleCurrentPageIconCandidates(tabId, url, host);
    this.dependencies.mediaDiscoveryCoordinator.runPageEndProbesForTab(
      tabId,
      url,
      title,
      this.dependencies.mediaDiscoveryHost
    );
    this.dependencies.privateProfileLifecycleCoordinator.savePreservedCookiesForTabIfNeeded(
      tabId,
      this.dependencies.privateProfileCookieLifecycleHost
    );
    this.dependencies.backgroundTabPreviewRuntimeCoordinator.schedulePageReadyCapture(tabId, 'page_end');
  }

  blockClosedTabUserScriptDocument(tabId: string): void {
    this.dependencies.userScriptRuntimeCoordinator.blockAutomaticInjectionDocumentForPage(tabId);
  }

  applyHistoryUrlRuntimeEffects(
    tabId: string,
    url: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    if (host.resolveShellFacts().activeTabId === tabId) {
      this.dependencies.siteControlsRuntimeCoordinator.refreshTrackingProtectionStatus();
    }
    this.injectAdBlockCosmeticRulesForPage(tabId, url, host);
    this.applyManualElementHideRulesForPage(tabId, url);
  }

  applyManualElementHideRulesForPage(tabId: string, url: string): void {
    this.dependencies.manualElementHideRuntimeCoordinator.applyForPage({
      tabId: tabId,
      pageUrl: url,
      appServiceModeEnabled: this.isFullAppServiceMode()
    });
  }

  private injectAdBlockCosmeticRulesForPage(
    tabId: string,
    url: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    if (!this.isFullAppServiceMode()) {
      return;
    }
    void this.dependencies.siteControlsRuntimeCoordinator.injectAdBlockCosmeticRulesForPage(tabId, url)
      .then((summary) => {
        if (summary.totalActionCount <= 0) {
          return;
        }
        this.dependencies.adBlockCoordinator.recordCosmeticSelectors(
          tabId,
          summary.selectors,
          summary.hiddenElementCount,
          summary.placeholderCollapsedCount
        );
        if (host.resolveShellFacts().activeTabId === tabId) {
          this.dependencies.siteControlsRuntimeCoordinator.refreshActiveProtectionPresentation();
        }
      }).catch((_error: Error) => {});
  }

  private isFullAppServiceMode(): boolean {
    return this.dependencies.preferencesRepository.getPreferences().appServiceMode !== 'basic';
  }

  private collectCurrentPageIconCandidates(
    tabId: string,
    url: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    const tab = this.dependencies.tabManager.getTab(host.resolveShellFacts().tabs, tabId);
    this.faviconCoordinator.handleCurrentPageReady({
      tabId: tabId,
      documentUrl: url,
      privateMode: this.dependencies.tabScopedEventContextCoordinator.resolvePrivacyMode(tabId) === 'private',
      controller: this.dependencies.runtimeLifecyclePort.resolveController(tabId),
      launchContext: tab?.launchContext,
      navigationIndex: tab?.navigationIndex ?? -1
    });
  }

  private scheduleCurrentPageIconCandidates(
    tabId: string,
    url: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    const tab = this.dependencies.tabManager.getTab(host.resolveShellFacts().tabs, tabId);
    if (tab === undefined) {
      return;
    }
    const navigationKey = this.resolveFaviconDeepDiscoveryNavigationKey(tabId, tab.navigationIndex, url);
    const pending = this.pendingFaviconDeepDiscoveryByTabId[tabId];
    if (pending?.navigationKey === navigationKey ||
      this.completedFaviconDeepDiscoveryKeyByTabId[tabId] === navigationKey) {
      return;
    }
    if (pending !== undefined && pending.timerId >= 0) {
      clearTimeout(pending.timerId);
    }
    const nextPending: PendingFaviconDeepDiscovery = {
      documentUrl: url,
      navigationIndex: tab.navigationIndex,
      navigationKey: navigationKey,
      timerId: -1
    };
    this.pendingFaviconDeepDiscoveryByTabId[tabId] = nextPending;
    this.scheduleFaviconDeepDiscoveryTimer(
      tabId,
      nextPending,
      host,
      FAVICON_DEEP_DISCOVERY_INITIAL_DELAY_MS
    );
  }

  private scheduleFaviconDeepDiscoveryTimer(
    tabId: string,
    pending: PendingFaviconDeepDiscovery,
    host: BrowserWebPageLifecycleApplicationHost,
    delayMs: number
  ): void {
    pending.timerId = setTimeout((): void => {
      pending.timerId = -1;
      const currentPending = this.pendingFaviconDeepDiscoveryByTabId[tabId];
      if (currentPending?.navigationKey !== pending.navigationKey) {
        return;
      }
      if (!this.isFaviconDeepDiscoveryNavigationCurrent(tabId, pending, host)) {
        this.pendingFaviconDeepDiscoveryByTabId[tabId] = undefined;
        return;
      }
      if (host.shouldDeferFaviconVisualUpdate(tabId)) {
        this.scheduleFaviconDeepDiscoveryTimer(
          tabId,
          pending,
          host,
          host.resolveDeferredPresentationDelayMs(0)
        );
        return;
      }
      this.pendingFaviconDeepDiscoveryByTabId[tabId] = undefined;
      this.completedFaviconDeepDiscoveryKeyByTabId[tabId] = pending.navigationKey;
      this.collectCurrentPageIconCandidates(tabId, pending.documentUrl, host);
    }, Math.max(0, Math.floor(delayMs)));
  }

  private isFaviconDeepDiscoveryNavigationCurrent(
    tabId: string,
    pending: PendingFaviconDeepDiscovery,
    host: BrowserWebPageLifecycleApplicationHost
  ): boolean {
    const tab = this.dependencies.tabManager.getTab(host.resolveShellFacts().tabs, tabId);
    if (tab === undefined || tab.navigationIndex !== pending.navigationIndex) {
      return false;
    }
    return this.resolveFaviconDeepDiscoveryNavigationKey(tabId, tab.navigationIndex, tab.url) ===
      pending.navigationKey;
  }

  private resolveFaviconDeepDiscoveryNavigationKey(
    tabId: string,
    navigationIndex: number,
    documentUrl: string
  ): string {
    const normalizedUrl = documentUrl.trim();
    const fragmentIndex = normalizedUrl.indexOf('#');
    const navigationUrl = fragmentIndex >= 0 ? normalizedUrl.substring(0, fragmentIndex) : normalizedUrl;
    return `${tabId}|${navigationIndex}|${navigationUrl}`;
  }

  private clearFaviconDeepDiscovery(tabId: string): void {
    const pending = this.pendingFaviconDeepDiscoveryByTabId[tabId];
    if (pending !== undefined && pending.timerId >= 0) {
      clearTimeout(pending.timerId);
    }
    this.pendingFaviconDeepDiscoveryByTabId[tabId] = undefined;
    this.completedFaviconDeepDiscoveryKeyByTabId[tabId] = undefined;
  }

  private scheduleTabPageChromeThemeProbe(tabId: string): void {
    this.dependencies.pageChromeThemeSamplingCoordinator.scheduleScriptProbe(tabId);
  }

  private scheduleTabPageChromeVisualSample(tabId: string): void {
    this.dependencies.pageChromeThemeSamplingCoordinator.scheduleVisualSample(tabId);
  }
}
