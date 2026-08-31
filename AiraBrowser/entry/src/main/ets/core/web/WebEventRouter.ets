import { BrowserTabState } from '../tabs/TabManager';
import { isBrowserNewWindowTestUrl } from '../../app/debug/BrowserNewWindowTestPage';

interface WebEventRouteContext {
  tabId: string;
  navigationId: number;
  targetUrl: string;
  strict: boolean;
  acceptedUrl: string;
  committedUrl: string;
  phase: WebNavigationTransactionPhase;
}

interface WebHttpUrlParts {
  scheme: string;
  host: string;
  path: string;
}

type WebNavigationTransactionPhase =
  'idle' |
  'pending' |
  'provisional' |
  'committed' |
  'finished' |
  'failed';

export type WebMainFrameEventKind =
  'page_begin' |
  'page_end' |
  'navigation_entry_committed' |
  'error_receive';

export interface WebMainFrameEventDecision {
  accepted: boolean;
  reason: string;
  navigationId: number;
  expectedUrl: string;
  acceptedUrl: string;
  committedUrl: string;
}

export interface WebMainFrameEventDecisionInput {
  activeSurfaceVisible?: boolean;
  foregroundUrlCandidates?: string[];
}

export interface WebPageEventRouteInput {
  tabId: string;
  activeTabId: string;
  activeSurfaceVisible?: boolean;
  tab?: BrowserTabState;
  eventUrl: string;
  fallbackUrl: string;
}

export interface WebPageEventRoute {
  resolvedUrl: string;
  shouldHandleActiveTab: boolean;
  shouldSyncEventContext: boolean;
  shouldReleaseEventContext: boolean;
  strictNavigation: boolean;
}

export interface WebFollowupEventRoute {
  shouldHandleActiveTab: boolean;
}

export interface WebTitleEventRoute {
  shouldUpdateTabTitle: boolean;
  shouldUpdateActiveTitle: boolean;
}

export class WebEventRouter {
  private contexts: Record<string, WebEventRouteContext | undefined> = {};
  private nextNavigationId: number = 1;

  beginNavigation(
    tabId: string,
    targetUrl: string,
    strict: boolean,
    forceNewNavigationId: boolean = false
  ): number {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return 0;
    }
    const normalizedTargetUrl = targetUrl.trim();
    const existing = this.contexts[normalizedTabId];
    const existingTarget = existing?.targetUrl ?? '';
    const isSameTarget =
      this.normalizeNavigationTarget(existingTarget) === this.normalizeNavigationTarget(normalizedTargetUrl)
    const reuseExisting = isSameTarget && !forceNewNavigationId;
    const nextAcceptedUrl = reuseExisting ? (existing?.acceptedUrl ?? '') : '';
    const nextCommittedUrl = reuseExisting ? (existing?.committedUrl ?? '') : '';
    const navigationId = reuseExisting
      ? (existing?.navigationId ?? this.allocateNavigationId())
      : this.allocateNavigationId();
    this.contexts[normalizedTabId] = {
      tabId: tabId,
      navigationId: navigationId,
      targetUrl: normalizedTargetUrl,
      strict: strict,
      acceptedUrl: nextAcceptedUrl,
      committedUrl: nextCommittedUrl,
      phase: reuseExisting ? (existing?.phase ?? 'pending') : 'pending'
    };
    return navigationId;
  }

  releaseNavigation(tabId: string): void {
    const context = this.resolveContext(tabId);
    if (context === undefined) {
      return;
    }
    const settledUrl = context.committedUrl.trim().length > 0
      ? context.committedUrl
      : (context.acceptedUrl.trim().length > 0 ? context.acceptedUrl : context.targetUrl);
    this.contexts[tabId] = {
      tabId: tabId,
      navigationId: context.navigationId,
      targetUrl: settledUrl,
      strict: false,
      acceptedUrl: settledUrl,
      committedUrl: settledUrl,
      phase: settledUrl.trim().length > 0 ? 'finished' : 'idle'
    };
  }

  isStrictNavigation(): boolean {
    return Object.keys(this.contexts).some((tabId: string): boolean => {
      return this.contexts[tabId]?.strict === true;
    });
  }

  shouldHandleActiveTabFollowup(tabId: string, activeTabId: string, activeSurfaceVisible: boolean = true): boolean {
    const context = this.resolveContext(tabId);
    return activeSurfaceVisible && context?.strict !== true && tabId === activeTabId;
  }

  observeMainFrameRequest(tabId: string, targetUrl: string, strict: boolean = false): void {
    const normalizedUrl = targetUrl.trim();
    if (normalizedUrl.length === 0) {
      return;
    }
    const context = this.resolveContext(tabId);
    if (context !== undefined &&
      this.normalizeNavigationTarget(context.targetUrl) === this.normalizeNavigationTarget(normalizedUrl)) {
      context.strict = strict;
      if (context.phase === 'idle' || context.phase === 'finished' || context.phase === 'failed') {
        context.phase = 'pending';
      }
      this.contexts[tabId] = context;
      return;
    }
    this.beginNavigation(tabId, normalizedUrl, strict);
  }

  resolveMainFrameEventDecision(
    tabId: string,
    eventUrl: string,
    kind: WebMainFrameEventKind,
    input?: WebMainFrameEventDecisionInput
  ): WebMainFrameEventDecision {
    const context = this.resolveContext(tabId);
    if (context === undefined || context.targetUrl.trim().length === 0) {
      return this.buildMainFrameEventDecision(true, 'no_active_navigation', 0, '', '', '');
    }
    const normalizedEventUrl = this.normalizeNavigationTarget(eventUrl);
    if (normalizedEventUrl.length === 0 ||
      normalizedEventUrl.startsWith('about:') ||
      normalizedEventUrl.startsWith('data:')) {
      return this.buildMainFrameEventDecision(
        true,
        'internal_or_empty_url',
        context.navigationId,
        context.targetUrl,
        context.acceptedUrl,
        context.committedUrl
      );
    }
    const normalizedTargetUrl = this.normalizeNavigationTarget(context.targetUrl);
    const normalizedAcceptedUrl = this.normalizeNavigationTarget(context.acceptedUrl);
    const normalizedCommittedUrl = this.normalizeNavigationTarget(context.committedUrl);
    if (normalizedEventUrl === normalizedTargetUrl ||
      normalizedEventUrl === normalizedAcceptedUrl ||
      normalizedEventUrl === normalizedCommittedUrl) {
      this.markAcceptedMainFrameUrl(tabId, eventUrl, kind);
      const updatedContext = this.resolveContext(tabId) ?? context;
      return this.buildMainFrameEventDecision(
        true,
        'matches_current_navigation',
        updatedContext.navigationId,
        updatedContext.targetUrl,
        updatedContext.acceptedUrl,
        updatedContext.committedUrl
      );
    }
    if ((kind === 'page_begin' || kind === 'navigation_entry_committed') &&
      normalizedAcceptedUrl.length === 0 &&
      this.isLikelySameNavigationRedirect(context.targetUrl, eventUrl)) {
      this.markAcceptedMainFrameUrl(tabId, eventUrl, kind);
      const updatedContext = this.resolveContext(tabId) ?? context;
      return this.buildMainFrameEventDecision(
        true,
        'accepted_redirect_candidate',
        updatedContext.navigationId,
        updatedContext.targetUrl,
        updatedContext.acceptedUrl,
        updatedContext.committedUrl
      );
    }
    if ((kind === 'page_begin' || kind === 'navigation_entry_committed') &&
      this.isLikelyEncodedRedirectDestination(context.targetUrl, eventUrl)) {
      this.markAcceptedMainFrameUrl(tabId, eventUrl, kind);
      const updatedContext = this.resolveContext(tabId) ?? context;
      return this.buildMainFrameEventDecision(
        true,
        'accepted_redirect_destination',
        updatedContext.navigationId,
        updatedContext.targetUrl,
        updatedContext.acceptedUrl,
        updatedContext.committedUrl
      );
    }
    if ((kind === 'page_begin' || kind === 'navigation_entry_committed') &&
      input?.activeSurfaceVisible === true &&
      this.matchesForegroundNavigationCandidate(normalizedEventUrl, input.foregroundUrlCandidates ?? [])) {
      this.adoptForegroundMainFrameNavigation(tabId, eventUrl, kind);
      const updatedContext = this.resolveContext(tabId) ?? context;
      return this.buildMainFrameEventDecision(
        true,
        'matches_foreground_navigation',
        updatedContext.navigationId,
        updatedContext.targetUrl,
        updatedContext.acceptedUrl,
        updatedContext.committedUrl
      );
    }
    return this.buildMainFrameEventDecision(
      false,
      'stale_navigation_event',
      context.navigationId,
      context.targetUrl,
      context.acceptedUrl,
      context.committedUrl
    );
  }

  resolvePageBeginRoute(input: WebPageEventRouteInput): WebPageEventRoute {
    return this.buildPageEventRoute(input, false);
  }

  resolvePageEndRoute(input: WebPageEventRouteInput): WebPageEventRoute {
    return this.buildPageEventRoute(input, true);
  }

  resolveFollowupRoute(
    tabId: string,
    activeTabId: string,
    activeSurfaceVisible: boolean = true
  ): WebFollowupEventRoute {
    return {
      shouldHandleActiveTab: this.shouldHandleActiveTabFollowup(tabId, activeTabId, activeSurfaceVisible)
    };
  }

  resolveTitleRoute(tabId: string, activeTabId: string, activeSurfaceVisible: boolean = true): WebTitleEventRoute {
    const context = this.resolveContext(tabId);
    if (context?.strict === true) {
      return {
        shouldUpdateTabTitle: false,
        shouldUpdateActiveTitle: false
      };
    }
    return {
      shouldUpdateTabTitle: true,
      shouldUpdateActiveTitle: activeSurfaceVisible && tabId === activeTabId
    };
  }

  resolveNavigationUrl(tab: BrowserTabState | undefined, eventUrl: string, fallbackUrl: string): string {
    const normalizedEventUrl = this.normalizeNavigationTarget(eventUrl);
    const context = this.resolveContext(tab?.id ?? '');
    const internalDebugPageContext =
      isBrowserNewWindowTestUrl(context?.targetUrl ?? '') ||
      isBrowserNewWindowTestUrl(tab?.url ?? '');
    if (!internalDebugPageContext) {
      return eventUrl;
    }
    if (normalizedEventUrl.length === 0 || normalizedEventUrl.startsWith('about:') || normalizedEventUrl.startsWith('data:')) {
      return fallbackUrl;
    }
    return eventUrl;
  }

  private buildPageEventRoute(input: WebPageEventRouteInput, releaseEventContext: boolean): WebPageEventRoute {
    const shouldHandleActiveTab = input.activeSurfaceVisible !== false && input.tabId === input.activeTabId;
    const context = this.resolveContext(input.tabId);
    return {
      resolvedUrl: this.resolveNavigationUrl(input.tab, input.eventUrl, input.fallbackUrl),
      shouldHandleActiveTab: shouldHandleActiveTab,
      shouldSyncEventContext: shouldHandleActiveTab,
      shouldReleaseEventContext: shouldHandleActiveTab && releaseEventContext,
      strictNavigation: context?.strict === true
    };
  }

  private resolveContext(tabId: string): WebEventRouteContext | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return undefined;
    }
    return this.contexts[normalizedTabId];
  }

  private markAcceptedMainFrameUrl(tabId: string, eventUrl: string, kind: WebMainFrameEventKind): void {
    const context = this.resolveContext(tabId);
    if (context === undefined) {
      return;
    }
    const normalizedEventUrl = eventUrl.trim();
    if (kind === 'error_receive') {
      context.phase = 'failed';
      this.contexts[tabId] = context;
      return;
    }
    context.acceptedUrl = normalizedEventUrl;
    if (kind === 'page_begin') {
      context.targetUrl = normalizedEventUrl;
      context.phase = 'provisional';
      context.strict = false;
    } else if (kind === 'navigation_entry_committed') {
      context.targetUrl = normalizedEventUrl;
      context.committedUrl = normalizedEventUrl;
      context.phase = 'committed';
      context.strict = false;
    } else if (kind === 'page_end') {
      context.phase = 'finished';
    }
    this.contexts[tabId] = context;
  }

  private adoptForegroundMainFrameNavigation(tabId: string, eventUrl: string, kind: WebMainFrameEventKind): void {
    const context = this.resolveContext(tabId);
    if (context === undefined) {
      this.beginNavigation(tabId, eventUrl, false);
      this.markAcceptedMainFrameUrl(tabId, eventUrl, kind);
      return;
    }
    context.navigationId = this.allocateNavigationId();
    context.targetUrl = eventUrl.trim();
    context.acceptedUrl = '';
    context.committedUrl = '';
    context.strict = false;
    context.phase = 'pending';
    this.contexts[tabId] = context;
    this.markAcceptedMainFrameUrl(tabId, eventUrl, kind);
  }

  private buildMainFrameEventDecision(
    accepted: boolean,
    reason: string,
    navigationId: number,
    expectedUrl: string,
    acceptedUrl: string,
    committedUrl: string
  ): WebMainFrameEventDecision {
    return {
      accepted: accepted,
      reason: reason,
      navigationId: navigationId,
      expectedUrl: expectedUrl,
      acceptedUrl: acceptedUrl,
      committedUrl: committedUrl
    };
  }

  private isLikelySameNavigationRedirect(targetUrl: string, eventUrl: string): boolean {
    const targetParts = this.extractHttpUrlParts(targetUrl);
    const eventParts = this.extractHttpUrlParts(eventUrl);
    if (targetParts.host.length === 0 || eventParts.host.length === 0) {
      return false;
    }
    if (targetParts.host !== eventParts.host) {
      return false;
    }
    if (targetParts.path !== eventParts.path) {
      return false;
    }
    return targetParts.scheme === eventParts.scheme ||
      (targetParts.scheme === 'http' && eventParts.scheme === 'https');
  }

  private isLikelyEncodedRedirectDestination(targetUrl: string, eventUrl: string): boolean {
    const eventParts = this.extractHttpUrlParts(eventUrl);
    if (eventParts.host.length === 0) {
      return false;
    }
    const candidates = this.extractQueryUrlCandidates(targetUrl);
    for (let index = 0; index < candidates.length; index += 1) {
      const candidateParts = this.extractHttpUrlParts(candidates[index]);
      if (candidateParts.host.length === 0 || candidateParts.host !== eventParts.host) {
        continue;
      }
      if (candidateParts.scheme !== eventParts.scheme &&
        !(candidateParts.scheme === 'http' && eventParts.scheme === 'https')) {
        continue;
      }
      if (candidateParts.path === '/' ||
        candidateParts.path === eventParts.path ||
        eventParts.path.startsWith(candidateParts.path)) {
        return true;
      }
    }
    return false;
  }

  private extractQueryUrlCandidates(url: string): string[] {
    const queryStart = url.indexOf('?');
    if (queryStart < 0) {
      return [];
    }
    const hashStart = url.indexOf('#', queryStart + 1);
    const query = hashStart >= 0 ? url.substring(queryStart + 1, hashStart) : url.substring(queryStart + 1);
    const rawParts = query.split('&');
    const candidates: string[] = [];
    rawParts.forEach((part: string) => {
      const equalsIndex = part.indexOf('=');
      if (equalsIndex < 0 || equalsIndex >= part.length - 1) {
        return;
      }
      const decoded = this.decodeUrlCandidate(part.substring(equalsIndex + 1));
      const lowerDecoded = decoded.toLowerCase();
      if (lowerDecoded.startsWith('http://') || lowerDecoded.startsWith('https://')) {
        candidates.push(decoded);
      }
    });
    return candidates;
  }

  private decodeUrlCandidate(value: string): string {
    let decoded = value.replace(/\+/g, ' ').trim();
    for (let index = 0; index < 3; index += 1) {
      try {
        const next = decodeURIComponent(decoded);
        if (next === decoded) {
          return next.trim();
        }
        decoded = next.trim();
      } catch (_error) {
        return decoded;
      }
    }
    return decoded;
  }

  private matchesForegroundNavigationCandidate(normalizedEventUrl: string, candidates: string[]): boolean {
    if (normalizedEventUrl.length <= 0) {
      return false;
    }
    for (let index = 0; index < candidates.length; index += 1) {
      if (normalizedEventUrl === this.normalizeNavigationTarget(candidates[index])) {
        return true;
      }
    }
    return false;
  }

  private extractHttpUrlParts(url: string): WebHttpUrlParts {
    const trimmed = url.trim();
    const schemeSeparatorIndex = trimmed.indexOf('://');
    if (schemeSeparatorIndex <= 0) {
      return this.buildEmptyHttpUrlParts();
    }
    const scheme = trimmed.substring(0, schemeSeparatorIndex).toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') {
      return this.buildEmptyHttpUrlParts();
    }
    const afterScheme = trimmed.substring(schemeSeparatorIndex + 3);
    const hostEndIndex = this.findFirstUrlBoundary(afterScheme);
    const hostWithPort = (hostEndIndex >= 0 ? afterScheme.substring(0, hostEndIndex) : afterScheme)
      .substring(afterScheme.lastIndexOf('@') + 1)
      .toLowerCase();
    const host = hostWithPort.startsWith('[')
      ? hostWithPort
      : hostWithPort.split(':')[0];
    const pathWithQuery = hostEndIndex >= 0 ? afterScheme.substring(hostEndIndex) : '/';
    const hashIndex = pathWithQuery.indexOf('#');
    const withoutHash = hashIndex >= 0 ? pathWithQuery.substring(0, hashIndex) : pathWithQuery;
    const path = withoutHash.length > 0 ? withoutHash : '/';
    return { scheme: scheme, host: host, path: path };
  }

  private buildEmptyHttpUrlParts(): WebHttpUrlParts {
    return {
      scheme: '',
      host: '',
      path: ''
    };
  }

  private findFirstUrlBoundary(value: string): number {
    const slashIndex = value.indexOf('/');
    const queryIndex = value.indexOf('?');
    const hashIndex = value.indexOf('#');
    let result = -1;
    [slashIndex, queryIndex, hashIndex].forEach((index: number) => {
      if (index >= 0 && (result < 0 || index < result)) {
        result = index;
      }
    });
    return result;
  }

  private normalizeNavigationTarget(url: string): string {
    const trimmed = url.trim().toLowerCase();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  private allocateNavigationId(): number {
    const id = this.nextNavigationId;
    this.nextNavigationId += 1;
    return id;
  }
}
