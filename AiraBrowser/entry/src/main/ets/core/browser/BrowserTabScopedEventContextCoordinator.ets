import {
  BrowserDataBoundary,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  BrowserCreateTabOptions,
  BrowserTabState
} from '../tabs/TabManager';
import { resolveCurrentSiteUrl } from './AddressDisplayFormatter';
import { BrowserPrivateProfileLifecycleCoordinator } from './BrowserPrivateProfileLifecycleCoordinator';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';

export interface BrowserTabScopedEventContextFacts {
  tabs: BrowserTabState[];
  activeTabId: string;
  showHomePage: boolean;
  homeProfileId: BrowserProfileId;
  homePrivacyMode: BrowserSessionPrivacyMode;
  homeDataScope: BrowserDataScope;
  currentUrl: string;
  addressInput: string;
}

export interface BrowserTabScopedEventContext {
  tab?: BrowserTabState;
  tabId: string;
  activeTabId: string;
  isActiveTab: boolean;
  currentUrl: string;
  addressInput: string;
  pageUrl: string;
  pageTitle: string;
  openerTabId: string;
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
  privacyMode: BrowserSessionPrivacyMode;
  siteOrigin: string;
  boundaryPrivate: boolean;
  tabPrivate: boolean;
}

export interface BrowserTabScopedBoundaryCreateOptions extends BrowserCreateTabOptions {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface BrowserTabScopedEventContextHost {
  readFacts: () => BrowserTabScopedEventContextFacts;
  resolveOrigin: (url: string) => string;
}

export class BrowserTabScopedEventContextCoordinator {
  private readonly host: BrowserTabScopedEventContextHost;
  private readonly privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator;
  private readonly profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  constructor(
    host: BrowserTabScopedEventContextHost,
    privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator
  ) {
    this.host = host;
    this.privateProfileLifecycleCoordinator = privateProfileLifecycleCoordinator;
  }

  resolveCurrentContext(): BrowserTabScopedEventContext {
    const facts = this.host.readFacts();
    const activeTab = this.findTab(facts.tabs, facts.activeTabId);
    const boundary = this.resolveCurrentBoundaryFromFacts(facts, activeTab);
    const currentPageUrl = resolveCurrentSiteUrl(facts.currentUrl, facts.addressInput);
    const pageUrl = activeTab === undefined
      ? currentPageUrl
      : resolveCurrentSiteUrl(activeTab.url, activeTab.pendingUrl);
    return this.buildContext(
      facts,
      activeTab,
      facts.activeTabId,
      true,
      facts.currentUrl,
      facts.addressInput,
      pageUrl,
      currentPageUrl,
      boundary
    );
  }

  resolveContext(tabId: string): BrowserTabScopedEventContext {
    const facts = this.host.readFacts();
    const activeTab = this.findTab(facts.tabs, facts.activeTabId);
    const currentBoundary = this.resolveCurrentBoundaryFromFacts(facts, activeTab);
    const tab = this.findTab(facts.tabs, tabId);
    const isActiveTab = tabId === facts.activeTabId;
    const currentPageUrl = resolveCurrentSiteUrl(facts.currentUrl, facts.addressInput);
    const pageUrl = tab === undefined
      ? currentPageUrl
      : resolveCurrentSiteUrl(tab.url, tab.pendingUrl);
    const boundary = tab === undefined ? currentBoundary : this.buildBoundary(tab, currentBoundary);
    return this.buildContext(
      facts,
      tab,
      tabId,
      isActiveTab,
      isActiveTab ? facts.currentUrl : (tab === undefined ? '' : pageUrl),
      isActiveTab ? facts.addressInput : '',
      pageUrl,
      isActiveTab || tab === undefined ? currentPageUrl : pageUrl,
      boundary
    );
  }

  resolveCurrentBoundary(): BrowserTabScopedBoundaryCreateOptions {
    const facts = this.host.readFacts();
    const boundary = this.resolveCurrentBoundaryFromFacts(
      facts,
      this.findTab(facts.tabs, facts.activeTabId)
    );
    return {
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope
    };
  }

  isCurrentBoundaryPrivate(): boolean {
    const boundary = this.resolveCurrentBoundary();
    return this.isBoundaryPrivate(boundary.privacyMode, boundary.dataScope);
  }

  isWebSurfaceVisible(): boolean {
    return !this.host.readFacts().showHomePage;
  }

  resolveProfileId(tabId: string): BrowserProfileId {
    return this.resolveContext(tabId).profileId;
  }

  resolveDataScope(tabId: string): BrowserDataScope {
    return this.resolveContext(tabId).dataScope;
  }

  resolvePrivacyMode(tabId: string): BrowserSessionPrivacyMode {
    return this.resolveContext(tabId).privacyMode;
  }

  resolveSiteOrigin(tabId: string): string {
    return this.resolveContext(tabId).siteOrigin;
  }

  resolvePageUrl(tabId: string): string {
    return this.resolveContext(tabId).pageUrl;
  }

  isTabPrivate(tabId: string): boolean {
    return this.resolveContext(tabId).tabPrivate;
  }

  isBoundaryPrivate(
    privacyMode: BrowserSessionPrivacyMode | string,
    dataScope: BrowserDataScope | string,
    sessionId: string = ''
  ): boolean {
    return this.privateProfileLifecycleCoordinator.isSessionEphemeralTab({
      privacyMode: privacyMode,
      dataScope: dataScope,
      sessionId: sessionId
    });
  }

  buildCreateOptions(tabId: string): BrowserCreateTabOptions {
    const context = this.resolveContext(tabId);
    return {
      profileId: context.profileId,
      privacyMode: context.privacyMode,
      dataScope: context.dataScope
    };
  }

  private resolveCurrentBoundaryFromFacts(
    facts: BrowserTabScopedEventContextFacts,
    activeTab: BrowserTabState | undefined
  ): BrowserDataBoundary {
    if (!facts.showHomePage && activeTab !== undefined) {
      return this.profileBoundaryService.buildBoundary({
        profileId: activeTab.profileId,
        privacyMode: activeTab.privacyMode,
        dataScope: activeTab.dataScope,
        sessionId: activeTab.id
      });
    }
    return this.profileBoundaryService.buildBoundary({
      profileId: facts.homeProfileId,
      privacyMode: facts.homePrivacyMode,
      dataScope: facts.homeDataScope,
      sessionId: facts.activeTabId
    });
  }

  private buildBoundary(
    tab: BrowserTabState,
    fallback: BrowserDataBoundary
  ): BrowserDataBoundary {
    return this.profileBoundaryService.buildBoundary({
      profileId: tab.profileId ?? fallback.profileId,
      privacyMode: tab.privacyMode ?? fallback.privacyMode,
      dataScope: tab.dataScope ?? fallback.dataScope,
      sessionId: tab.id.length > 0 ? tab.id : fallback.sessionId
    });
  }

  private buildContext(
    facts: BrowserTabScopedEventContextFacts,
    tab: BrowserTabState | undefined,
    tabId: string,
    isActiveTab: boolean,
    currentUrl: string,
    addressInput: string,
    pageUrl: string,
    originUrl: string,
    boundary: BrowserDataBoundary
  ): BrowserTabScopedEventContext {
    return {
      tab: tab,
      tabId: tabId,
      activeTabId: facts.activeTabId,
      isActiveTab: isActiveTab,
      currentUrl: currentUrl,
      addressInput: addressInput,
      pageUrl: pageUrl,
      pageTitle: tab?.title ?? '',
      openerTabId: tab?.openerTabId ?? '',
      profileId: boundary.profileId,
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode,
      siteOrigin: this.host.resolveOrigin(originUrl),
      boundaryPrivate: this.privateProfileLifecycleCoordinator.isSessionEphemeralTab({
        privacyMode: boundary.privacyMode,
        dataScope: boundary.dataScope
      }),
      tabPrivate: this.privateProfileLifecycleCoordinator.isSessionEphemeralTabState(tab)
    };
  }

  private findTab(tabs: BrowserTabState[], tabId: string): BrowserTabState | undefined {
    return tabs.find((tab: BrowserTabState): boolean => tab.id === tabId);
  }
}
