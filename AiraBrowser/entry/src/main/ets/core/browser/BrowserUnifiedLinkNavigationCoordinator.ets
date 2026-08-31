import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  BrowserUnifiedLinkLogic,
  BrowserUnifiedLinkResult,
  BrowserUnifiedLinkSource
} from '../../services/web/BrowserUnifiedLinkLogic';
import { ExternalNavigationPolicyService } from '../../services/web/ExternalNavigationPolicyService';
import { BrowserRecentActionManager } from '../web/BrowserRecentActionManager';
import { WebRuntimeBridge } from '../web/WebRuntimeBridge';
import { BrowserExternalNavigationRuntimeStateCoordinator } from './BrowserExternalNavigationRuntimeStateCoordinator';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import { BrowserUnifiedLinkApplicationCoordinator } from './BrowserUnifiedLinkApplicationCoordinator';

export interface BrowserUnifiedLinkNavigationRequest {
  tabId: string;
  url: string;
  source: BrowserUnifiedLinkSource;
  isMainFrame: boolean;
  isRequestGesture: boolean;
}

export interface BrowserUnifiedLinkNavigationFacts {
  tabVisible: boolean;
  windowVisible: boolean;
}

export interface BrowserUnifiedLinkNavigationHost {
  readNavigationFacts: (tabId: string) => BrowserUnifiedLinkNavigationFacts;
}

interface BrowserUnifiedLinkNavigationCoordinatorOptions {
  externalNavigationPolicyService: ExternalNavigationPolicyService;
  externalNavigationRuntimeStateCoordinator: BrowserExternalNavigationRuntimeStateCoordinator;
  recentActionManager: BrowserRecentActionManager;
  webRuntimeBridge: WebRuntimeBridge;
  preferencesRepository: PreferencesRepository;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  applicationCoordinator: BrowserUnifiedLinkApplicationCoordinator;
  logic?: BrowserUnifiedLinkLogic;
}

const DEFAULT_EXTERNAL_NAVIGATION_DEDUPE_INTERVAL_MS: number = 1200;

export class BrowserUnifiedLinkNavigationCoordinator {
  private readonly logic: BrowserUnifiedLinkLogic;
  private readonly externalNavigationPolicyService: ExternalNavigationPolicyService;
  private readonly externalNavigationRuntimeStateCoordinator: BrowserExternalNavigationRuntimeStateCoordinator;
  private readonly recentActionManager: BrowserRecentActionManager;
  private readonly webRuntimeBridge: WebRuntimeBridge;
  private readonly preferencesRepository: PreferencesRepository;
  private readonly tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  private readonly applicationCoordinator: BrowserUnifiedLinkApplicationCoordinator;

  constructor(options: BrowserUnifiedLinkNavigationCoordinatorOptions) {
    this.logic = options.logic ?? new BrowserUnifiedLinkLogic();
    this.externalNavigationPolicyService = options.externalNavigationPolicyService;
    this.externalNavigationRuntimeStateCoordinator = options.externalNavigationRuntimeStateCoordinator;
    this.recentActionManager = options.recentActionManager;
    this.webRuntimeBridge = options.webRuntimeBridge;
    this.preferencesRepository = options.preferencesRepository;
    this.tabScopedEventContextCoordinator = options.tabScopedEventContextCoordinator;
    this.applicationCoordinator = options.applicationCoordinator;
  }

  evaluate(
    request: BrowserUnifiedLinkNavigationRequest,
    host: BrowserUnifiedLinkNavigationHost,
    now: number = Date.now()
  ): BrowserUnifiedLinkResult {
    const facts = host.readNavigationFacts(request.tabId);
    const context = this.tabScopedEventContextCoordinator.resolveContext(request.tabId);
    const suppressionRecords = this.externalNavigationRuntimeStateCoordinator.refreshSuppressionRecords(
      this.externalNavigationPolicyService,
      now
    );
    return this.logic.evaluate({
      tabId: request.tabId,
      url: request.url,
      originUrl: context.pageUrl,
      refererUrl: context.pageUrl,
      isMainFrame: request.isMainFrame,
      isRequestGesture: request.isRequestGesture,
      isTabVisible: facts.tabVisible,
      isWindowVisible: facts.windowVisible,
      source: request.source,
      fallbackUrl: '',
      openerTabId: context.openerTabId,
      canLoadInWebView: this.webRuntimeBridge.canLoadInWebView(request.url),
      hasRecentAction: this.recentActionManager.isRecentAction(now),
      duplicateUrl: this.externalNavigationRuntimeStateCoordinator.resolveDuplicateUrl(),
      duplicateAt: this.externalNavigationRuntimeStateCoordinator.resolveDuplicateAt(),
      now: now,
      dedupeIntervalMs: DEFAULT_EXTERNAL_NAVIGATION_DEDUPE_INTERVAL_MS,
      settings: this.preferencesRepository.getPreferences().externalNavigation,
      currentOrigin: context.siteOrigin,
      suppressionRecords: suppressionRecords,
      profileId: context.profileId
    });
  }

  handleManualLoad(
    tabId: string,
    url: string,
    isMainFrame: boolean,
    isRequestGesture: boolean,
    navigationHost: BrowserUnifiedLinkNavigationHost,
    now: number = Date.now()
  ): BrowserUnifiedLinkResult {
    const result = this.evaluate({
      tabId,
      url,
      isMainFrame,
      isRequestGesture,
      source: 'manual_load'
    }, navigationHost, now);
    this.applyEvaluatedResult(result, now);
    return result;
  }

  applyEvaluatedResult(
    result: BrowserUnifiedLinkResult,
    now: number = Date.now()
  ): void {
    if (!result.handled || result.action === 'allow_web') {
      return;
    }
    this.applicationCoordinator.applyResult(result, now);
  }
}
