import {
  BrowserCreateTabOptions,
  BrowserTabState,
  BrowserTabManagerPort
} from '../../core/tabs/TabManager';
import { BrowserAddressSubmissionCoordinator } from '../../core/navigation/BrowserAddressSubmissionCoordinator';
import { BrowserAddressDisplayCoordinator } from '../../core/browser/BrowserAddressDisplayCoordinator';
import { BrowserRecentActionManager } from '../../core/web/BrowserRecentActionManager';
import { BrowserWebLoadFailureSurfaceCoordinator } from '../../core/browser/BrowserWebLoadFailureSurfaceCoordinator';
import { BrowserTabSwitchCoordinator } from '../../core/browser/BrowserTabSwitchCoordinator';
import { BrowserWebTopImmersionSessionCoordinator } from
  '../../core/browser/BrowserWebTopImmersionSessionCoordinator';
import { BrowserWebPageLifecycleApplicationHost } from '../../core/browser/BrowserWebPageLifecycleModels';
import { SearchEngineRepository } from '../../data/search/SearchEngineRepository';
import { BrowserActiveTabRuntimeRestoreCoordinator } from './BrowserActiveTabRuntimeRestoreCoordinator';
import { BrowserHostedRuntimeSurfacePort } from './BrowserHostedRuntimeSurfacePort';
import { BrowserRuntimeLifecyclePort } from './BrowserRuntimeLifecyclePort';
import { BrowserWebLoadRuntimeCoordinator } from './BrowserWebLoadRuntimeCoordinator';
import { BrowserWebNavigationStateSyncCoordinator } from './BrowserWebNavigationStateSyncCoordinator';
import { TelegramWebCompatibilityService } from './TelegramWebCompatibilityService';
import {
  SearchEngineFallbackRetryService
} from '../search/SearchEngineFallbackRetryService';
import {
  WEB_LOAD_ERROR_DOCUMENT_BASE_URL,
  WEB_LOAD_ERROR_DOCUMENT_RETRY_URL,
  WEB_LOAD_ERROR_DOCUMENT_SETTINGS_URL,
  WebLoadErrorDocumentLayoutOptions,
  WebLoadErrorDocumentService
} from './WebLoadErrorDocumentService';
import {
  WebLoadErrorPresentation,
  WebLoadErrorPresentationService
} from './WebLoadErrorPresentationService';

export interface BrowserErrorDocumentRuntimeFacts {
  tab?: BrowserTabState;
  activeTabId: string;
  activeWebTab: boolean;
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  currentTitle: string;
  fallbackErrorMessage: string;
  runtimeDegradedMessage: string;
  bottomChromeInsetVp: number;
  accentColor: string;
  onAccentColor: string;
  createOptions: BrowserCreateTabOptions;
}

export interface BrowserErrorDocumentLoadShell {
  resolvePresentationFacts: (tabId: string) => BrowserErrorDocumentPresentationFacts;
  scheduleActiveErrorDocumentPreview: () => void;
  lockActiveTabsOverviewSnapshot: () => void;
}

export interface BrowserErrorDocumentPresentationFacts {
  fallbackErrorMessage: string;
  runtimeDegradedMessage: string;
  bottomChromeInsetVp: number;
  accentColor: string;
  onAccentColor: string;
  createOptions: BrowserCreateTabOptions;
}

export interface BrowserErrorDocumentLoadDependencies {
  loadFailureSurfaceCoordinator: BrowserWebLoadFailureSurfaceCoordinator;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator;
  addressSubmissionCoordinator: BrowserAddressSubmissionCoordinator;
  recentActionManager: BrowserRecentActionManager;
  searchEngineRepository: SearchEngineRepository;
  addressDisplayCoordinator: BrowserAddressDisplayCoordinator;
  visibleUrlService: TelegramWebCompatibilityService;
  tabManager: BrowserTabManagerPort;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  navigationStateSyncCoordinator: BrowserWebNavigationStateSyncCoordinator;
  topImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator;
  lifecycleHost: BrowserWebPageLifecycleApplicationHost;
  completeActivePageLoadingProgress: () => void;
}

export interface BrowserErrorDocumentLoadRequest {
  tabId: string;
  targetUrl: string;
  errorMessage: string;
}

export interface BrowserErrorDocumentCommittedUrlResolution {
  ignored: boolean;
  targetUrl: string;
}

export class BrowserErrorDocumentLoadCoordinator {
  private readonly dependencies: BrowserErrorDocumentLoadDependencies;
  private readonly shell: BrowserErrorDocumentLoadShell;
  private readonly presentationService: WebLoadErrorPresentationService;
  private readonly documentService: WebLoadErrorDocumentService;
  private readonly fallbackRetryService: SearchEngineFallbackRetryService;

  constructor(
    dependencies: BrowserErrorDocumentLoadDependencies,
    shell: BrowserErrorDocumentLoadShell,
    presentationService: WebLoadErrorPresentationService = new WebLoadErrorPresentationService(),
    documentService: WebLoadErrorDocumentService = new WebLoadErrorDocumentService(),
    fallbackRetryService: SearchEngineFallbackRetryService = new SearchEngineFallbackRetryService()
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
    this.presentationService = presentationService;
    this.documentService = documentService;
    this.fallbackRetryService = fallbackRetryService;
  }

  load(request: BrowserErrorDocumentLoadRequest): boolean {
    const normalizedTargetUrl = request.targetUrl.trim();
    const facts = this.resolveFacts(request.tabId);
    const presentation = this.buildPresentation(request.tabId, normalizedTargetUrl, request.errorMessage);
    const layoutOptions = this.buildLayoutOptions(request.tabId);
    const payload = this.documentService.buildPayload(presentation, normalizedTargetUrl, layoutOptions);
    if (facts.activeWebTab && facts.tab !== undefined) {
      this.applyActivePageErrorSurfaceVisible(false);
      this.dependencies.hostedRuntimeSurfacePort.ensureActiveWebSurfaceForNavigation(facts.tab);
    }
    this.dependencies.loadFailureSurfaceCoordinator.markWebDocumentLoading(request.tabId);
    const loaded = this.dependencies.webLoadRuntimeCoordinator.runDataLoad(
      request.tabId,
      normalizedTargetUrl,
      payload,
      false
    );
    if (!loaded) {
      this.dependencies.loadFailureSurfaceCoordinator.markWebDocumentFailed(request.tabId);
      if (facts.activeWebTab) {
        this.applyActivePageErrorSurfaceVisible(true);
        this.dependencies.hostedRuntimeSurfacePort.detachActive();
      }
    } else if (facts.activeWebTab) {
      this.applyActivePageErrorSurfaceVisible(false);
    }
    if (loaded) {
      this.commitAsCurrentPage(request.tabId, normalizedTargetUrl, presentation);
      this.markCommitted(request.tabId, normalizedTargetUrl, 'load_issued');
    }
    return loaded;
  }

  resolveLoadFailureTargetUrl(tabId: string): string {
    const facts = this.resolveFacts(tabId);
    const candidates: string[] = facts.activeWebTab
      ? [
        facts.pendingWebUrl,
        facts.currentUrl,
        facts.addressInput,
        facts.tab?.pendingUrl ?? '',
        facts.tab?.url ?? ''
      ]
      : [
        facts.tab?.pendingUrl ?? '',
        facts.tab?.url ?? ''
      ];
    for (let index = 0; index < candidates.length; index += 1) {
      const value = candidates[index].trim();
      if (value.length > 0) {
        return value;
      }
    }
    return 'about:blank';
  }

  markCommitted(tabId: string, targetUrl: string, source: string): void {
    this.dependencies.loadFailureSurfaceCoordinator.markWebDocumentCommitted(tabId);
    if (this.resolveFacts(tabId).activeWebTab) {
      this.clearActiveErrorDocumentCommittedUi();
      this.dependencies.completeActivePageLoadingProgress();
      this.shell.scheduleActiveErrorDocumentPreview();
    }
  }

  resolveCommittedUrl(
    tabId: string,
    candidateUrl: string,
    source: string
  ): BrowserErrorDocumentCommittedUrlResolution {
    if (!this.dependencies.loadFailureSurfaceCoordinator.shouldShow(tabId)) {
      return {
        ignored: false,
        targetUrl: ''
      };
    }
    const normalizedCandidateUrl = candidateUrl.trim();
    const targetUrl = this.dependencies.loadFailureSurfaceCoordinator.resolveTargetUrl(tabId);
    if (!this.isInternalErrorDocumentUrl(normalizedCandidateUrl, targetUrl)) {
      return {
        ignored: false,
        targetUrl: ''
      };
    }
    return {
      ignored: true,
      targetUrl: targetUrl
    };
  }

  shouldIgnoreCommittedUrl(tabId: string, candidateUrl: string, source: string): boolean {
    const resolution = this.resolveCommittedUrl(tabId, candidateUrl, source);
    if (!resolution.ignored || resolution.targetUrl.length <= 0) {
      return false;
    }
    if (this.resolveFacts(tabId).activeWebTab) {
      this.applyActiveCommittedUrlCorrection(resolution.targetUrl);
    }
    return true;
  }

  handleActionUrl(tabId: string, targetUrl: string): boolean {
    const normalizedTargetUrl = targetUrl.trim();
    if (!this.dependencies.loadFailureSurfaceCoordinator.shouldShow(tabId)) {
      return false;
    }
    if (normalizedTargetUrl === WEB_LOAD_ERROR_DOCUMENT_RETRY_URL) {
      if (this.resolveFacts(tabId).activeWebTab) {
        this.retryActivePageAfterLoadError();
      }
      return true;
    }
    if (normalizedTargetUrl === WEB_LOAD_ERROR_DOCUMENT_SETTINGS_URL) {
      this.dependencies.lifecycleHost.openSystemNetworkSettings();
      return true;
    }
    return false;
  }

  retryActivePageAfterLoadError(): void {
    const facts = this.resolveFacts('');
    this.shell.lockActiveTabsOverviewSnapshot();
    const retryTabId = this.dependencies.loadFailureSurfaceCoordinator.isWebDocumentCommitted(facts.activeTabId)
      ? facts.activeTabId
      : '';
    this.applyActiveErrorDocumentRetryUi(retryTabId, '正在重新加载页面');
    this.dependencies.activeTabRuntimeRestoreCoordinator.reloadActive('user_manual_reload', false);
  }

  tryAutomaticSearchFallback(tabId: string, failedUrl: string): boolean {
    const facts = this.resolveFacts(tabId);
    if (!facts.activeWebTab) {
      return false;
    }
    const action = this.fallbackRetryService.buildRetryAction({
      failedUrl: failedUrl,
      settings: this.dependencies.searchEngineRepository.getSettings(),
      availableSearchEngines: this.dependencies.searchEngineRepository.listEngines()
    });
    if (action === undefined ||
      !this.dependencies.addressSubmissionCoordinator.consumeAutomaticSearchFallback(action)) {
      return false;
    }
    this.dependencies.loadFailureSurfaceCoordinator.clear(tabId);
    this.applyActivePageErrorSurfaceVisible(false);
    this.dependencies.recentActionManager.recordOperate(Date.now());
    this.dependencies.addressSubmissionCoordinator.openAutomaticSearchFallback(action);
    return true;
  }

  buildActivePresentation(): WebLoadErrorPresentation {
    const facts = this.resolveFacts('');
    const errorMessage = this.dependencies.loadFailureSurfaceCoordinator.resolveErrorMessage(
      facts.activeTabId,
      facts.fallbackErrorMessage
    );
    return this.buildPresentation(
      facts.activeTabId,
      facts.pendingWebUrl.length > 0 ? facts.pendingWebUrl : facts.currentUrl,
      errorMessage
    );
  }

  buildPresentation(tabId: string, targetUrl: string, errorMessage: string): WebLoadErrorPresentation {
    const facts = this.resolveFacts(tabId);
    return this.presentationService.build({
      url: targetUrl.length > 0 ? targetUrl : (facts.tab?.url ?? facts.currentUrl),
      pendingUrl: targetUrl.length > 0 ? targetUrl : (facts.tab?.pendingUrl ?? facts.pendingWebUrl),
      title: facts.activeWebTab ? facts.currentTitle : (facts.tab?.title ?? ''),
      errorMessage: errorMessage,
      runtimeDegradedMessage: facts.activeWebTab ? facts.runtimeDegradedMessage : '',
      crashed: facts.tab?.runtimeState === 'crashed'
    });
  }

  private commitAsCurrentPage(
    tabId: string,
    targetUrl: string,
    presentation: WebLoadErrorPresentation
  ): void {
    const normalizedTargetUrl = targetUrl.trim();
    if (normalizedTargetUrl.length <= 0) {
      return;
    }
    const updatedTabs = this.dependencies.tabManager.recordNavigationForTab(
      this.dependencies.lifecycleHost.resolveShellFacts().tabs,
      tabId,
      normalizedTargetUrl,
      presentation.title
    );
    this.dependencies.tabSwitchCoordinator.commitTabs(updatedTabs, {
      refreshRuntimeTabIds: [tabId]
    });
    this.dependencies.runtimeLifecyclePort.rememberCommittedNavigation(tabId, normalizedTargetUrl);
    if (!this.resolveFacts(tabId).activeWebTab) {
      return;
    }
    this.applyActiveCommittedErrorDocument(normalizedTargetUrl, presentation.title);
  }

  private buildLayoutOptions(tabId: string): WebLoadErrorDocumentLayoutOptions {
    const facts = this.resolveFacts(tabId);
    return {
      bottomChromeInsetVp: facts.bottomChromeInsetVp,
      accentColor: facts.accentColor,
      onAccentColor: facts.onAccentColor,
      darkAccentColor: facts.accentColor,
      darkOnAccentColor: facts.onAccentColor
    };
  }

  private isInternalErrorDocumentUrl(candidateUrl: string, targetUrl: string): boolean {
    const normalizedCandidateUrl = candidateUrl.trim();
    if (normalizedCandidateUrl.length <= 0) {
      return false;
    }
    const lowerCandidateUrl = normalizedCandidateUrl.toLowerCase();
    return lowerCandidateUrl.startsWith('data:') ||
      lowerCandidateUrl.startsWith(WEB_LOAD_ERROR_DOCUMENT_BASE_URL) ||
      (targetUrl.length > 0 && normalizedCandidateUrl === targetUrl);
  }

  private resolveFacts(tabId: string): BrowserErrorDocumentRuntimeFacts {
    const shellFacts = this.dependencies.lifecycleHost.resolveShellFacts();
    const resolvedTabId = tabId.trim().length > 0 ? tabId : shellFacts.activeTabId;
    const presentationFacts = this.shell.resolvePresentationFacts(resolvedTabId);
    return {
      tab: this.dependencies.tabManager.getTab(shellFacts.tabs, resolvedTabId),
      activeTabId: shellFacts.activeTabId,
      activeWebTab: resolvedTabId === shellFacts.activeTabId && shellFacts.webPageVisible,
      currentUrl: shellFacts.currentUrl,
      pendingWebUrl: shellFacts.pendingWebUrl,
      addressInput: shellFacts.addressInput,
      currentTitle: shellFacts.currentTitle,
      fallbackErrorMessage: presentationFacts.fallbackErrorMessage,
      runtimeDegradedMessage: presentationFacts.runtimeDegradedMessage,
      bottomChromeInsetVp: presentationFacts.bottomChromeInsetVp,
      accentColor: presentationFacts.accentColor,
      onAccentColor: presentationFacts.onAccentColor,
      createOptions: presentationFacts.createOptions
    };
  }

  private applyActivePageErrorSurfaceVisible(visible: boolean): void {
    const facts = this.dependencies.lifecycleHost.resolveShellFacts();
    this.dependencies.lifecycleHost.applyErrorSurfaceState({
      visible: visible,
      reloadHold: facts.pageErrorSurfaceReloadHold,
      retryTabId: facts.activeErrorDocumentRetryTabId
    });
  }

  private clearActiveErrorDocumentCommittedUi(): void {
    this.dependencies.lifecycleHost.applyErrorSurfaceState({
      visible: false,
      reloadHold: false,
      retryTabId: ''
    });
  }

  private applyActiveCommittedErrorDocument(targetUrl: string, title: string): void {
    const activeTabId = this.dependencies.lifecycleHost.resolveShellFacts().activeTabId;
    this.dependencies.lifecycleHost.applyActiveDocumentState({
      currentUrl: targetUrl,
      pendingWebUrl: targetUrl,
      addressInput: this.dependencies.addressDisplayCoordinator.resolveCommittedDisplay(
        activeTabId,
        this.dependencies.visibleUrlService.resolveVisibleUrl(targetUrl)
      ),
      currentTitle: title
    });
    this.dependencies.topImmersionSessionCoordinator.requestVisible('error-document-commit');
    this.dependencies.navigationStateSyncCoordinator.syncSoon();
  }

  private applyActiveCommittedUrlCorrection(targetUrl: string): void {
    const facts = this.dependencies.lifecycleHost.resolveShellFacts();
    this.dependencies.lifecycleHost.applyActiveDocumentState({
      currentUrl: targetUrl,
      pendingWebUrl: targetUrl,
      addressInput: this.dependencies.addressDisplayCoordinator.resolveCommittedDisplay(
        facts.activeTabId,
        this.dependencies.visibleUrlService.resolveVisibleUrl(targetUrl)
      ),
      currentTitle: facts.currentTitle
    });
  }

  private applyActiveErrorDocumentRetryUi(retryTabId: string, helperMessage: string): void {
    this.dependencies.lifecycleHost.applyErrorSurfaceState({
      visible: this.dependencies.lifecycleHost.resolveShellFacts().pageErrorSurfaceVisible,
      reloadHold: false,
      retryTabId: retryTabId
    });
    this.dependencies.lifecycleHost.applyRuntimeState({ errorMessage: '' });
    this.dependencies.lifecycleHost.applyRuntimeState({ helperMessage: helperMessage });
  }
}
