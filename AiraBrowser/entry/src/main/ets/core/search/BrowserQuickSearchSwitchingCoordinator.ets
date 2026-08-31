import { webview } from '@kit.ArkWeb';
import {
  SearchEngineId,
  SearchEngineRecord
} from '../../common/models/BrowserModels';
import { BrowserCreateTabOptions } from '../tabs/TabManager';
import { SearchEngineRepository } from '../../data/search/SearchEngineRepository';
import {
  QuickSearchSwitchPreferencesRepository
} from '../../data/search/QuickSearchSwitchPreferencesRepository';
import { SearchEngineTemplateService } from '../../services/search/SearchEngineTemplateService';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { normalizeNavigationTarget } from '../browser/AddressDisplayFormatter';
import { BrowserAppUrlOpenCoordinator } from '../browser/BrowserAppUrlOpenCoordinator';
import {
  BrowserWebTopImmersionSessionCoordinator
} from '../browser/BrowserWebTopImmersionSessionCoordinator';
import { BrowserHistoryApiChangeEvent } from '../web/BrowserHistoryApiBridge';

export const BROWSER_QUICK_SEARCH_SWITCH_BAR_HEIGHT: number = 48;
const ARKWEB_BACK_FORWARD_LIST_MAX_SIZE: number = 50;
const ARKWEB_MAIN_FRAME_NEW_ENTRY_NAVIGATION_TYPE: number = 1;

export type BrowserQuickSearchSubmissionIntent = 'empty' | 'navigate' | 'search';

export interface BrowserQuickSearchSubmissionSeed {
  intent: BrowserQuickSearchSubmissionIntent;
  query: string;
  searchEngineId: SearchEngineId;
  resolvedUrl: string;
}

export interface BrowserQuickSearchSubmissionRecorder {
  recordAddressSubmission(seed: BrowserQuickSearchSubmissionSeed): void;
}

export interface BrowserQuickSearchReloadOwner {
  prepareQuickSearchForReload(tabId: string): void;
}

export interface BrowserQuickSearchNavigationCommit {
  navigationType: number;
  isMainFrame: boolean;
  isSameDocument: boolean;
  didReplaceEntry: boolean;
}

export interface BrowserQuickSearchEngineItem {
  engineId: SearchEngineId;
  label: string;
  selected: boolean;
}

export interface BrowserQuickSearchSwitchingPresentation {
  visible: boolean;
  occupiedHeightPx: number;
  query: string;
  selectedEngineId: SearchEngineId;
  engines: BrowserQuickSearchEngineItem[];
}

export interface BrowserQuickSearchSwitchingHost {
  resolveActiveTabId: () => string;
  resolveTabIds: () => string[];
  resolveCurrentBoundary: () => BrowserCreateTabOptions;
  isWebPageVisible: () => boolean;
  isWebAppActive: () => boolean;
  publishPresentation: (presentation: BrowserQuickSearchSwitchingPresentation) => void;
}

interface BrowserQuickSearchContext {
  query: string;
  engineId: SearchEngineId;
  targetUrl: string;
  committedUrl: string;
  generation: number;
}

interface BrowserQuickSearchHistoryAssociation {
  historyIndex: number;
  historySize: number;
  historyUrl: string;
  context: BrowserQuickSearchContext;
}

interface BrowserQuickSearchTabSession {
  tabId: string;
  generation: number;
  associations: BrowserQuickSearchHistoryAssociation[];
  pendingContext?: BrowserQuickSearchContext;
  currentContext?: BrowserQuickSearchContext;
  ownedNavigationStarted: boolean;
  latestOwnedBeginUrl: string;
  supersededNavigationUrls: string[];
  unownedNavigationInFlight: boolean;
  failureRetained: boolean;
  ownedDocumentInitializing: boolean;
}

interface BrowserQuickSearchHistorySnapshot {
  currentIndex: number;
  size: number;
  currentUrl: string;
}

export function createHiddenBrowserQuickSearchSwitchingPresentation(): BrowserQuickSearchSwitchingPresentation {
  return {
    visible: false,
    occupiedHeightPx: 0,
    query: '',
    selectedEngineId: '',
    engines: []
  };
}

export class BrowserQuickSearchSwitchingCoordinator implements BrowserQuickSearchSubmissionRecorder,
  BrowserQuickSearchReloadOwner {
  private readonly searchEngineRepository: SearchEngineRepository;
  private readonly preferencesRepository: QuickSearchSwitchPreferencesRepository;
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  private readonly topImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator;
  private readonly host: BrowserQuickSearchSwitchingHost;
  private readonly templateService: SearchEngineTemplateService;
  private sessionsByTabId: Record<string, BrowserQuickSearchTabSession | undefined> = {};
  private pendingAddressSubmission?: BrowserQuickSearchContext;
  private pendingAddressSubmissionTabId: string = '';
  private generation: number = 0;
  private presentation: BrowserQuickSearchSwitchingPresentation =
    createHiddenBrowserQuickSearchSwitchingPresentation();

  constructor(
    searchEngineRepository: SearchEngineRepository,
    preferencesRepository: QuickSearchSwitchPreferencesRepository,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator,
    topImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator,
    host: BrowserQuickSearchSwitchingHost,
    templateService: SearchEngineTemplateService = new SearchEngineTemplateService()
  ) {
    this.searchEngineRepository = searchEngineRepository;
    this.preferencesRepository = preferencesRepository;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.appUrlOpenCoordinator = appUrlOpenCoordinator;
    this.topImmersionSessionCoordinator = topImmersionSessionCoordinator;
    this.host = host;
    this.templateService = templateService;
  }

  getPresentation(): BrowserQuickSearchSwitchingPresentation {
    return this.clonePresentation(this.presentation);
  }

  recordAddressSubmission(seed: BrowserQuickSearchSubmissionSeed): void {
    if (seed.intent === 'empty') {
      return;
    }
    if (seed.intent === 'navigate') {
      this.clearPendingAddressSubmissionSeed();
      this.suspendActiveSession('address-navigation', true);
      return;
    }
    const context = this.buildContext(seed.query, seed.searchEngineId, seed.resolvedUrl);
    if (context === undefined) {
      this.clearPendingAddressSubmissionSeed();
      this.suspendActiveSession('invalid-address-search');
      return;
    }
    this.pendingAddressSubmission = context;
    const activeTabId = this.host.isWebPageVisible() ? this.host.resolveActiveTabId().trim() : '';
    this.pendingAddressSubmissionTabId = activeTabId;
    if (activeTabId.length > 0) {
      this.beginOwnedNavigation(activeTabId, context);
    } else {
      this.publishHidden('address-search-awaiting-tab');
    }
  }

  prepareQuickSearchForReload(tabId: string): void {
    const normalizedTabId = tabId.trim();
    const session = this.sessionsByTabId[normalizedTabId];
    const context = session?.pendingContext ?? session?.currentContext;
    if (session === undefined || context === undefined) {
      return;
    }
    session.pendingContext = context;
    session.currentContext = context;
    session.ownedNavigationStarted = true;
    session.latestOwnedBeginUrl = context.committedUrl.length > 0 ? context.committedUrl : context.targetUrl;
    session.supersededNavigationUrls = [];
    session.unownedNavigationInFlight = false;
    session.failureRetained = false;
    session.ownedDocumentInitializing = true;
    this.publishActiveTabIfNeeded(normalizedTabId, 'expected-reload');
  }

  selectEngine(engineId: SearchEngineId): void {
    const activeTabId = this.host.resolveActiveTabId().trim();
    const session = this.sessionsByTabId[activeTabId];
    const currentContext = session?.currentContext ?? session?.pendingContext;
    if (activeTabId.length <= 0 || currentContext === undefined || currentContext.engineId === engineId) {
      return;
    }
    const engine = this.searchEngineRepository.listEngines().find((candidate: SearchEngineRecord): boolean => {
      return candidate.id === engineId;
    });
    if (engine === undefined) {
      this.syncActivePresentation('engine-missing');
      return;
    }
    const targetUrl = this.templateService.buildSearchUrl(currentContext.query, engine);
    const context = this.buildContext(currentContext.query, engine.id, targetUrl);
    if (context === undefined) {
      return;
    }
    this.clearPendingAddressSubmissionSeed();
    this.beginOwnedNavigation(activeTabId, context);
    this.appUrlOpenCoordinator.openCurrentAppUi(
      targetUrl,
      `正在使用 ${engine.name} 搜索`,
      this.host.resolveCurrentBoundary(),
      targetUrl
    );
  }

  handlePageBegin(tabId: string, eventUrl: string, historyTargetIntentUrl: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedEventUrl = eventUrl.trim();
    if (normalizedTabId.length <= 0 || normalizedEventUrl.length <= 0) {
      return;
    }
    this.pruneClosedTabSessions();
    let session = this.sessionsByTabId[normalizedTabId];
    const pendingAddressSubmission = this.pendingAddressSubmission;
    const pendingTabMatches = pendingAddressSubmission !== undefined &&
      (this.pendingAddressSubmissionTabId.length <= 0 || this.pendingAddressSubmissionTabId === normalizedTabId);
    const pendingUrlMatches = pendingAddressSubmission !== undefined &&
      this.sameUrl(pendingAddressSubmission.targetUrl, normalizedEventUrl);
    const pendingNewActiveTabNavigation = pendingAddressSubmission !== undefined &&
      this.pendingAddressSubmissionTabId.length <= 0 &&
      normalizedTabId === this.host.resolveActiveTabId().trim() &&
      this.isHttpNavigationUrl(normalizedEventUrl);
    if (session === undefined && pendingAddressSubmission !== undefined && pendingTabMatches &&
      (pendingUrlMatches || pendingNewActiveTabNavigation)) {
      this.beginOwnedNavigation(normalizedTabId, pendingAddressSubmission);
      session = this.sessionsByTabId[normalizedTabId];
      if (session !== undefined) {
        session.ownedNavigationStarted = true;
        session.latestOwnedBeginUrl = normalizedEventUrl;
        session.unownedNavigationInFlight = false;
        session.currentContext = pendingAddressSubmission;
        session.failureRetained = false;
        session.ownedDocumentInitializing = true;
        this.clearPendingAddressSubmission(pendingAddressSubmission);
        this.publishActiveTabIfNeeded(normalizedTabId, 'adopted-page-begin');
        return;
      }
    }
    if (session === undefined) {
      this.publishActiveTabIfNeeded(normalizedTabId, 'page-begin-no-session');
      return;
    }
    const failureContext = session.currentContext;
    if (session.failureRetained && failureContext !== undefined &&
      (this.sameUrl(failureContext.targetUrl, normalizedEventUrl) ||
        this.sameUrl(failureContext.committedUrl, normalizedEventUrl))) {
      session.pendingContext = failureContext;
      session.ownedNavigationStarted = true;
      session.latestOwnedBeginUrl = normalizedEventUrl;
      session.supersededNavigationUrls = [];
      session.unownedNavigationInFlight = false;
      session.failureRetained = false;
      session.ownedDocumentInitializing = true;
      this.publishActiveTabIfNeeded(normalizedTabId, 'failure-retry-page-begin');
      return;
    }
    const pendingContext = session.pendingContext;
    if (pendingContext !== undefined) {
      if (this.sameUrl(pendingContext.targetUrl, normalizedEventUrl)) {
        session.ownedNavigationStarted = true;
        session.latestOwnedBeginUrl = normalizedEventUrl;
        session.unownedNavigationInFlight = false;
        session.currentContext = pendingContext;
        session.failureRetained = false;
        session.ownedDocumentInitializing = true;
        this.clearPendingAddressSubmission(pendingContext);
        this.publishActiveTabIfNeeded(normalizedTabId, 'owned-page-begin');
        return;
      }
      if (session.supersededNavigationUrls.some((url: string): boolean => {
        return this.sameUrl(url, normalizedEventUrl);
      })) {
        this.publishActiveTabIfNeeded(normalizedTabId, 'superseded-page-begin');
        return;
      }
      if (session.ownedNavigationStarted) {
        session.latestOwnedBeginUrl = normalizedEventUrl;
        session.unownedNavigationInFlight = false;
        session.currentContext = pendingContext;
        session.ownedDocumentInitializing = true;
        this.publishActiveTabIfNeeded(normalizedTabId, 'owned-page-redirect');
        return;
      }
      this.clearPendingAddressSubmission(pendingContext);
      session.pendingContext = undefined;
      session.currentContext = undefined;
      session.latestOwnedBeginUrl = '';
      session.supersededNavigationUrls = [];
      session.unownedNavigationInFlight = true;
      session.failureRetained = false;
      session.ownedDocumentInitializing = false;
      this.publishActiveTabIfNeeded(normalizedTabId, 'owned-page-mismatch');
      return;
    }

    const normalizedHistoryIntentUrl = historyTargetIntentUrl.trim();
    const snapshot = this.captureHistorySnapshot(normalizedTabId);
    if (normalizedHistoryIntentUrl.length > 0) {
      if (session.unownedNavigationInFlight) {
        this.publishActiveTabIfNeeded(normalizedTabId, 'history-page-begin-during-unowned-navigation');
        return;
      }
      session.currentContext = this.resolveAssociatedContext(
        session,
        snapshot,
        normalizedEventUrl,
        normalizedHistoryIntentUrl
      );
      session.latestOwnedBeginUrl = '';
      session.supersededNavigationUrls = [];
      session.unownedNavigationInFlight = false;
      session.failureRetained = false;
      session.ownedDocumentInitializing = false;
      this.publishActiveTabIfNeeded(normalizedTabId, 'history-page-begin');
      return;
    }
    if (this.isConfirmedReload(session, snapshot, normalizedEventUrl)) {
      session.unownedNavigationInFlight = false;
      session.failureRetained = false;
      this.publishActiveTabIfNeeded(normalizedTabId, 'reload-page-begin');
      return;
    }
    session.currentContext = undefined;
    session.latestOwnedBeginUrl = '';
    session.supersededNavigationUrls = [];
    session.unownedNavigationInFlight = true;
    session.failureRetained = false;
    session.ownedDocumentInitializing = false;
    this.publishActiveTabIfNeeded(normalizedTabId, 'unowned-page-begin');
  }

  handleNavigationCommitted(
    tabId: string,
    committedUrl: string,
    commit: BrowserQuickSearchNavigationCommit
  ): void {
    if (!commit.isMainFrame) {
      return;
    }
    this.reconcileCommittedNavigation(tabId, committedUrl, 'navigation-committed', commit);
  }

  handlePageEnd(tabId: string, committedUrl: string): void {
    this.reconcileCommittedNavigation(tabId, committedUrl, 'page-end');
  }

  handleMainFrameFailure(tabId: string, failedUrl: string): void {
    const normalizedTabId = tabId.trim();
    const session = this.sessionsByTabId[normalizedTabId];
    const context = session?.pendingContext ?? session?.currentContext;
    if (session === undefined || context === undefined) {
      return;
    }
    const normalizedFailedUrl = failedUrl.trim();
    if (!this.sameUrl(context.targetUrl, normalizedFailedUrl) &&
      !this.sameUrl(context.committedUrl, normalizedFailedUrl) &&
      !this.sameUrl(session.latestOwnedBeginUrl, normalizedFailedUrl)) {
      return;
    }
    session.pendingContext = undefined;
    session.currentContext = {
      query: context.query,
      engineId: context.engineId,
      targetUrl: context.targetUrl,
      committedUrl: normalizedFailedUrl,
      generation: context.generation
    };
    session.ownedNavigationStarted = false;
    session.latestOwnedBeginUrl = '';
    session.supersededNavigationUrls = [];
    session.unownedNavigationInFlight = false;
    session.failureRetained = true;
    session.ownedDocumentInitializing = false;
    this.clearPendingAddressSubmission(context);
    this.publishActiveTabIfNeeded(normalizedTabId, 'main-frame-failure');
  }

  handleNavigationCancelled(tabId: string, restoredUrl: string = ''): void {
    const normalizedTabId = tabId.trim();
    const session = this.sessionsByTabId[normalizedTabId];
    if (session === undefined || !session.unownedNavigationInFlight) {
      return;
    }
    const snapshot = this.captureHistorySnapshot(normalizedTabId);
    const normalizedRestoredUrl = restoredUrl.trim();
    if (snapshot === undefined || (normalizedRestoredUrl.length > 0 &&
      !this.sameUrl(snapshot.currentUrl, normalizedRestoredUrl))) {
      this.publishActiveTabIfNeeded(normalizedTabId, 'navigation-cancelled-history-mismatch');
      return;
    }
    const association = this.findAssociation(session, snapshot);
    if (association === undefined) {
      this.publishActiveTabIfNeeded(normalizedTabId, 'navigation-cancelled-unassociated');
      return;
    }
    session.pendingContext = undefined;
    session.currentContext = association.context;
    session.ownedNavigationStarted = false;
    session.latestOwnedBeginUrl = '';
    session.supersededNavigationUrls = [];
    session.unownedNavigationInFlight = false;
    session.failureRetained = false;
    session.ownedDocumentInitializing = false;
    this.publishActiveTabIfNeeded(normalizedTabId, 'navigation-cancelled-restored');
  }

  handleHistoryApiUrlChange(tabId: string, event: BrowserHistoryApiChangeEvent): void {
    const normalizedTabId = tabId.trim();
    const session = this.sessionsByTabId[normalizedTabId];
    if (session === undefined) {
      return;
    }
    if (session.unownedNavigationInFlight) {
      this.publishActiveTabIfNeeded(normalizedTabId, 'history-api-during-unowned-navigation');
      return;
    }
    const snapshot = this.captureHistorySnapshot(normalizedTabId);
    if (this.reconcileOwnedHistoryReplacement(normalizedTabId, session, snapshot, event)) {
      return;
    }
    if (snapshot !== undefined && event.kind === 'popstate') {
      const association = this.findAssociation(session, snapshot);
      if (association !== undefined) {
        session.pendingContext = undefined;
        session.currentContext = association.context;
        session.ownedNavigationStarted = false;
        session.latestOwnedBeginUrl = '';
        session.supersededNavigationUrls = [];
        session.unownedNavigationInFlight = false;
        session.failureRetained = false;
        session.ownedDocumentInitializing = false;
        this.publishActiveTabIfNeeded(normalizedTabId, 'history-api-associated');
        return;
      }
    }
    if (snapshot !== undefined) {
      if (this.isAtAmbiguousHistoryRolloverBoundary(session, snapshot)) {
        session.associations = [];
      } else {
        this.retainAssociationsBefore(session, snapshot);
      }
    }
    session.pendingContext = undefined;
    session.currentContext = undefined;
    session.ownedNavigationStarted = false;
    session.latestOwnedBeginUrl = '';
    session.supersededNavigationUrls = [];
    session.unownedNavigationInFlight = false;
    session.failureRetained = false;
    session.ownedDocumentInitializing = false;
    this.publishActiveTabIfNeeded(normalizedTabId, 'history-api-change');
  }

  handleLoadFinished(tabId: string): void {
    const session = this.sessionsByTabId[tabId.trim()];
    if (session !== undefined) {
      session.ownedDocumentInitializing = false;
    }
  }

  refreshEligibility(source: string): void {
    this.syncActivePresentation(source);
  }

  syncActivePresentation(source: string): void {
    this.pruneClosedTabSessions();
    const activeTabId = this.host.resolveActiveTabId().trim();
    const session = this.sessionsByTabId[activeTabId];
    if (session !== undefined && session.pendingContext === undefined && !session.failureRetained &&
      !session.unownedNavigationInFlight) {
      const snapshot = this.captureHistorySnapshot(activeTabId);
      const association = this.findAssociation(session, snapshot);
      session.currentContext = association?.context;
    }
    this.publishPresentationForSession(session, source);
  }

  private reconcileCommittedNavigation(
    tabId: string,
    committedUrl: string,
    source: string,
    commit?: BrowserQuickSearchNavigationCommit
  ): void {
    const normalizedTabId = tabId.trim();
    const normalizedCommittedUrl = committedUrl.trim();
    const session = this.sessionsByTabId[normalizedTabId];
    if (session === undefined || normalizedCommittedUrl.length <= 0) {
      return;
    }
    const snapshot = this.captureHistorySnapshot(normalizedTabId);
    if (snapshot === undefined || !this.sameUrl(snapshot.currentUrl, normalizedCommittedUrl)) {
      this.publishActiveTabIfNeeded(normalizedTabId, `${source}-history-unavailable`);
      return;
    }
    const pendingContext = session.pendingContext;
    if ((pendingContext !== undefined || session.unownedNavigationInFlight) &&
      this.isAtAmbiguousHistoryRolloverBoundary(session, snapshot)) {
      session.associations = [];
    }
    if (pendingContext !== undefined &&
      (this.sameUrl(pendingContext.targetUrl, normalizedCommittedUrl) ||
        (session.ownedNavigationStarted && this.sameUrl(session.latestOwnedBeginUrl, normalizedCommittedUrl)) ||
        this.isPendingOwnedMainFrameNewEntryCommit(
          session,
          snapshot,
          normalizedCommittedUrl,
          commit
        ))) {
      const committedContext: BrowserQuickSearchContext = {
        query: pendingContext.query,
        engineId: pendingContext.engineId,
        targetUrl: pendingContext.targetUrl,
        committedUrl: normalizedCommittedUrl,
        generation: pendingContext.generation
      };
      this.retainAssociationsBefore(session, snapshot);
      session.associations.push({
        historyIndex: snapshot.currentIndex,
        historySize: snapshot.size,
        historyUrl: snapshot.currentUrl,
        context: committedContext
      });
      this.clearPendingAddressSubmission(pendingContext);
      session.pendingContext = undefined;
      session.currentContext = committedContext;
      session.ownedNavigationStarted = false;
      session.latestOwnedBeginUrl = '';
      session.supersededNavigationUrls = [];
      session.unownedNavigationInFlight = false;
      session.failureRetained = false;
      this.publishActiveTabIfNeeded(normalizedTabId, source);
      return;
    }
    if (pendingContext !== undefined) {
      this.publishActiveTabIfNeeded(normalizedTabId, `${source}-superseded`);
      return;
    }
    if (this.reconcileOwnedCommittedEntryReplacement(
      session,
      snapshot,
      normalizedCommittedUrl,
      commit
    )) {
      this.publishActiveTabIfNeeded(normalizedTabId, `${source}-owned-entry-replacement`);
      return;
    }
    const association = session.unownedNavigationInFlight ? undefined : this.findAssociation(session, snapshot);
    if (association !== undefined) {
      session.currentContext = association.context;
      session.latestOwnedBeginUrl = '';
      session.supersededNavigationUrls = [];
      session.unownedNavigationInFlight = false;
      session.failureRetained = false;
      this.publishActiveTabIfNeeded(normalizedTabId, `${source}-associated`);
      return;
    }
    this.retainAssociationsBefore(session, snapshot);
    session.currentContext = undefined;
    session.latestOwnedBeginUrl = '';
    session.supersededNavigationUrls = [];
    session.unownedNavigationInFlight = false;
    session.failureRetained = false;
    session.ownedDocumentInitializing = false;
    this.publishActiveTabIfNeeded(normalizedTabId, `${source}-unowned`);
  }

  private isPendingOwnedMainFrameNewEntryCommit(
    session: BrowserQuickSearchTabSession,
    snapshot: BrowserQuickSearchHistorySnapshot,
    committedUrl: string,
    commit: BrowserQuickSearchNavigationCommit | undefined
  ): boolean {
    if (commit === undefined || !commit.isMainFrame || commit.isSameDocument || commit.didReplaceEntry ||
      commit.navigationType !== ARKWEB_MAIN_FRAME_NEW_ENTRY_NAVIGATION_TYPE ||
      !this.sameUrl(snapshot.currentUrl, committedUrl)) {
      return false;
    }
    return !session.supersededNavigationUrls.some((url: string): boolean => {
      return this.sameUrl(url, committedUrl);
    });
  }

  private reconcileOwnedCommittedEntryReplacement(
    session: BrowserQuickSearchTabSession,
    snapshot: BrowserQuickSearchHistorySnapshot,
    committedUrl: string,
    commit: BrowserQuickSearchNavigationCommit | undefined
  ): boolean {
    const currentContext = session.currentContext;
    if (!session.ownedDocumentInitializing || currentContext === undefined || commit === undefined ||
      !commit.isMainFrame || commit.isSameDocument || !commit.didReplaceEntry ||
      commit.navigationType !== ARKWEB_MAIN_FRAME_NEW_ENTRY_NAVIGATION_TYPE ||
      !this.sameUrl(snapshot.currentUrl, committedUrl)) {
      return false;
    }
    const association = session.associations.find((candidate: BrowserQuickSearchHistoryAssociation): boolean => {
      return candidate.historyIndex === snapshot.currentIndex && candidate.historySize === snapshot.size &&
        candidate.context.generation === currentContext.generation;
    });
    if (association === undefined) {
      return false;
    }
    const rewrittenContext: BrowserQuickSearchContext = {
      query: association.context.query,
      engineId: association.context.engineId,
      targetUrl: association.context.targetUrl,
      committedUrl: snapshot.currentUrl,
      generation: association.context.generation
    };
    association.historyUrl = snapshot.currentUrl;
    association.context = rewrittenContext;
    session.currentContext = rewrittenContext;
    session.latestOwnedBeginUrl = snapshot.currentUrl;
    session.unownedNavigationInFlight = false;
    session.failureRetained = false;
    return true;
  }

  private beginOwnedNavigation(tabId: string, context: BrowserQuickSearchContext): void {
    const session = this.resolveOrCreateSession(tabId);
    const supersededNavigationUrls = session.supersededNavigationUrls.slice();
    if (session.pendingContext !== undefined) {
      this.appendUniqueUrl(supersededNavigationUrls, session.pendingContext.targetUrl);
      this.appendUniqueUrl(supersededNavigationUrls, session.pendingContext.committedUrl);
      this.appendUniqueUrl(supersededNavigationUrls, session.latestOwnedBeginUrl);
    }
    session.generation = context.generation;
    session.pendingContext = context;
    session.currentContext = context;
    session.ownedNavigationStarted = false;
    session.latestOwnedBeginUrl = '';
    session.supersededNavigationUrls = supersededNavigationUrls.filter((url: string): boolean => {
      return !this.sameUrl(url, context.targetUrl);
    });
    session.unownedNavigationInFlight = false;
    session.failureRetained = false;
    session.ownedDocumentInitializing = true;
    this.publishActiveTabIfNeeded(tabId, 'begin-owned-navigation');
  }

  private suspendActiveSession(source: string, unownedNavigationInFlight: boolean = false): void {
    const activeTabId = this.host.resolveActiveTabId().trim();
    const session = this.sessionsByTabId[activeTabId];
    if (session !== undefined) {
      session.pendingContext = undefined;
      session.currentContext = undefined;
      session.ownedNavigationStarted = false;
      session.latestOwnedBeginUrl = '';
      session.supersededNavigationUrls = [];
      session.unownedNavigationInFlight = unownedNavigationInFlight;
      session.failureRetained = false;
      session.ownedDocumentInitializing = false;
    }
    this.publishHidden(source);
  }

  private resolveAssociatedContext(
    session: BrowserQuickSearchTabSession,
    snapshot: BrowserQuickSearchHistorySnapshot | undefined,
    eventUrl: string,
    historyTargetIntentUrl: string
  ): BrowserQuickSearchContext | undefined {
    if (snapshot === undefined || !this.sameUrl(eventUrl, historyTargetIntentUrl) ||
      !this.sameUrl(snapshot.currentUrl, eventUrl)) {
      return undefined;
    }
    return this.findAssociation(session, snapshot)?.context;
  }

  private isConfirmedReload(
    session: BrowserQuickSearchTabSession,
    snapshot: BrowserQuickSearchHistorySnapshot | undefined,
    eventUrl: string
  ): boolean {
    if (session.currentContext === undefined || snapshot === undefined || !this.sameUrl(snapshot.currentUrl, eventUrl)) {
      return false;
    }
    return this.findAssociation(session, snapshot)?.context.generation === session.currentContext.generation;
  }

  private reconcileOwnedHistoryReplacement(
    tabId: string,
    session: BrowserQuickSearchTabSession,
    snapshot: BrowserQuickSearchHistorySnapshot | undefined,
    event: BrowserHistoryApiChangeEvent
  ): boolean {
    if (!session.ownedDocumentInitializing || event.kind !== 'replaceState' || snapshot === undefined ||
      !this.sameUrl(snapshot.currentUrl, event.newUrl)) {
      return false;
    }
    const pendingContext = session.pendingContext;
    if (pendingContext !== undefined && session.ownedNavigationStarted &&
      (this.sameUrl(pendingContext.targetUrl, event.oldUrl) ||
        this.sameUrl(pendingContext.committedUrl, event.oldUrl) ||
        this.sameUrl(session.latestOwnedBeginUrl, event.oldUrl))) {
      session.currentContext = pendingContext;
      session.latestOwnedBeginUrl = snapshot.currentUrl;
      session.unownedNavigationInFlight = false;
      session.failureRetained = false;
      this.publishActiveTabIfNeeded(tabId, 'owned-history-replace-pending');
      return true;
    }
    const currentContext = session.currentContext;
    if (currentContext === undefined) {
      return false;
    }
    const association = session.associations.find((candidate: BrowserQuickSearchHistoryAssociation): boolean => {
      return candidate.historyIndex === snapshot.currentIndex && snapshot.size >= candidate.historySize &&
        candidate.context.generation === currentContext.generation &&
        this.sameUrl(candidate.historyUrl, event.oldUrl);
    });
    if (association === undefined) {
      return false;
    }
    const rewrittenContext: BrowserQuickSearchContext = {
      query: association.context.query,
      engineId: association.context.engineId,
      targetUrl: association.context.targetUrl,
      committedUrl: snapshot.currentUrl,
      generation: association.context.generation
    };
    association.historySize = snapshot.size;
    association.historyUrl = snapshot.currentUrl;
    association.context = rewrittenContext;
    session.currentContext = rewrittenContext;
    session.latestOwnedBeginUrl = snapshot.currentUrl;
    session.unownedNavigationInFlight = false;
    session.failureRetained = false;
    this.publishActiveTabIfNeeded(tabId, 'owned-history-replace-committed');
    return true;
  }

  private findAssociation(
    session: BrowserQuickSearchTabSession,
    snapshot: BrowserQuickSearchHistorySnapshot | undefined
  ): BrowserQuickSearchHistoryAssociation | undefined {
    if (snapshot === undefined) {
      return undefined;
    }
    return session.associations.find((association: BrowserQuickSearchHistoryAssociation): boolean => {
      return association.historyIndex === snapshot.currentIndex &&
        snapshot.size >= association.historySize &&
        this.sameUrl(association.historyUrl, snapshot.currentUrl);
    });
  }

  private captureHistorySnapshot(tabId: string): BrowserQuickSearchHistorySnapshot | undefined {
    const controller = this.runtimeLifecyclePort.resolveController(tabId);
    if (controller === undefined) {
      return undefined;
    }
    try {
      const entries = controller.getBackForwardEntries();
      const currentIndex = entries.currentIndex;
      if (entries.size <= 0 || currentIndex < 0 || currentIndex >= entries.size) {
        return undefined;
      }
      return {
        currentIndex: currentIndex,
        size: entries.size,
        currentUrl: this.resolveHistoryItemUrl(entries.getItemAtIndex(currentIndex))
      };
    } catch (_error) {
      return undefined;
    }
  }

  private resolveHistoryItemUrl(item: webview.HistoryItem | undefined): string {
    if (item === undefined) {
      return '';
    }
    const historyUrl = item.historyUrl.trim();
    return historyUrl.length > 0 ? historyUrl : item.historyRawUrl.trim();
  }

  private buildContext(
    query: string,
    engineId: SearchEngineId,
    targetUrl: string
  ): BrowserQuickSearchContext | undefined {
    const normalizedQuery = query.trim();
    const normalizedTargetUrl = targetUrl.trim();
    if (normalizedQuery.length <= 0 || normalizedTargetUrl.length <= 0 || engineId.trim().length <= 0) {
      return undefined;
    }
    this.generation += 1;
    return {
      query: normalizedQuery,
      engineId: engineId,
      targetUrl: normalizedTargetUrl,
      committedUrl: '',
      generation: this.generation
    };
  }

  private clearPendingAddressSubmission(context: BrowserQuickSearchContext): void {
    if (this.pendingAddressSubmission?.generation === context.generation) {
      this.clearPendingAddressSubmissionSeed();
    }
  }

  private clearPendingAddressSubmissionSeed(): void {
    this.pendingAddressSubmission = undefined;
    this.pendingAddressSubmissionTabId = '';
  }

  private resolveOrCreateSession(tabId: string): BrowserQuickSearchTabSession {
    const normalizedTabId = tabId.trim();
    const existing = this.sessionsByTabId[normalizedTabId];
    if (existing !== undefined) {
      return existing;
    }
    const created: BrowserQuickSearchTabSession = {
      tabId: normalizedTabId,
      generation: 0,
      associations: [],
      ownedNavigationStarted: false,
      latestOwnedBeginUrl: '',
      supersededNavigationUrls: [],
      unownedNavigationInFlight: false,
      failureRetained: false,
      ownedDocumentInitializing: false
    };
    this.sessionsByTabId[normalizedTabId] = created;
    return created;
  }

  private pruneClosedTabSessions(): void {
    const tabIds = this.host.resolveTabIds();
    const retained: Record<string, BrowserQuickSearchTabSession | undefined> = {};
    tabIds.forEach((tabId: string) => {
      const session = this.sessionsByTabId[tabId];
      if (session !== undefined) {
        retained[tabId] = session;
      }
    });
    this.sessionsByTabId = retained;
  }

  private publishActiveTabIfNeeded(tabId: string, source: string): void {
    if (tabId.trim() !== this.host.resolveActiveTabId().trim()) {
      return;
    }
    this.publishPresentationForSession(this.sessionsByTabId[tabId], source);
  }

  private publishPresentationForSession(
    session: BrowserQuickSearchTabSession | undefined,
    source: string
  ): void {
    const context = session?.currentContext ?? session?.pendingContext;
    const engines = this.searchEngineRepository.listEngines();
    if (!this.preferencesRepository.isEnabled() || !this.host.isWebPageVisible() || this.host.isWebAppActive() ||
      context === undefined || engines.length < 2) {
      this.publishHidden(source);
      return;
    }
    this.publish({
      visible: true,
      occupiedHeightPx: BROWSER_QUICK_SEARCH_SWITCH_BAR_HEIGHT,
      query: context.query,
      selectedEngineId: context.engineId,
      engines: engines.map((engine: SearchEngineRecord): BrowserQuickSearchEngineItem => ({
        engineId: engine.id,
        label: engine.name,
        selected: engine.id === context.engineId
      }))
    }, source);
  }

  private publishHidden(source: string): void {
    this.publish(createHiddenBrowserQuickSearchSwitchingPresentation(), source);
  }

  private publish(next: BrowserQuickSearchSwitchingPresentation, source: string): void {
    if (this.presentationSignature(this.presentation) === this.presentationSignature(next)) {
      return;
    }
    const previousOccupiedHeight = this.presentation.occupiedHeightPx;
    this.presentation = this.clonePresentation(next);
    this.host.publishPresentation(this.getPresentation());
    if (previousOccupiedHeight !== next.occupiedHeightPx) {
      this.topImmersionSessionCoordinator.refreshVisibleInset(`quick-search-${source}`);
    }
  }

  private presentationSignature(presentation: BrowserQuickSearchSwitchingPresentation): string {
    const engineSignature = presentation.engines.map((item: BrowserQuickSearchEngineItem): string => {
      return `${item.engineId}:${item.label}:${item.selected ? '1' : '0'}`;
    }).join('|');
    return `${presentation.visible ? '1' : '0'}:${presentation.occupiedHeightPx}:${presentation.query}:` +
      `${presentation.selectedEngineId}:${engineSignature}`;
  }

  private clonePresentation(
    presentation: BrowserQuickSearchSwitchingPresentation
  ): BrowserQuickSearchSwitchingPresentation {
    return {
      visible: presentation.visible,
      occupiedHeightPx: presentation.occupiedHeightPx,
      query: presentation.query,
      selectedEngineId: presentation.selectedEngineId,
      engines: presentation.engines.map((item: BrowserQuickSearchEngineItem): BrowserQuickSearchEngineItem => ({
        engineId: item.engineId,
        label: item.label,
        selected: item.selected
      }))
    };
  }

  private sameUrl(left: string, right: string): boolean {
    const normalizedLeft = normalizeNavigationTarget(left);
    const normalizedRight = normalizeNavigationTarget(right);
    return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
  }

  private isHttpNavigationUrl(url: string): boolean {
    const normalizedUrl = url.trim().toLowerCase();
    return normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://');
  }

  private appendUniqueUrl(urls: string[], url: string): void {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length > 0 && !urls.some((candidate: string): boolean => {
      return this.sameUrl(candidate, normalizedUrl);
    })) {
      urls.push(normalizedUrl);
    }
  }

  private retainAssociationsBefore(
    session: BrowserQuickSearchTabSession,
    snapshot: BrowserQuickSearchHistorySnapshot
  ): void {
    session.associations = session.associations
      .filter((association: BrowserQuickSearchHistoryAssociation): boolean => {
        return association.historyIndex < snapshot.currentIndex;
      })
      .map((association: BrowserQuickSearchHistoryAssociation): BrowserQuickSearchHistoryAssociation => ({
        historyIndex: association.historyIndex,
        historySize: snapshot.size,
        historyUrl: association.historyUrl,
        context: association.context
      }));
  }

  private isAtAmbiguousHistoryRolloverBoundary(
    session: BrowserQuickSearchTabSession,
    snapshot: BrowserQuickSearchHistorySnapshot
  ): boolean {
    return snapshot.size >= ARKWEB_BACK_FORWARD_LIST_MAX_SIZE &&
      snapshot.currentIndex === snapshot.size - 1 &&
      session.associations.some((association: BrowserQuickSearchHistoryAssociation): boolean => {
        return association.historySize >= ARKWEB_BACK_FORWARD_LIST_MAX_SIZE;
      });
  }
}
