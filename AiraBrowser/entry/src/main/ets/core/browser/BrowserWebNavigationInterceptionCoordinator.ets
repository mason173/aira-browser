import {
  BrowserAdBlockCoordinator,
  BrowserAdBlockRequestContext
} from './BrowserAdBlockCoordinator';
import {
  BrowserWebComponentNavigationEventSource,
  BrowserWebComponentWebUrlDecision
} from '../web/BrowserWebComponentController';
import { TelegramWebCompatibilityService } from '../../services/web/TelegramWebCompatibilityService';
import { BrowserWebLoadRuntimeCoordinator } from '../../services/web/BrowserWebLoadRuntimeCoordinator';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import {
  sharedBrowserHttpsFirstNavigationService
} from '../../services/web/BrowserHttpsFirstNavigationService';
import { documentViewerHtmlFileTransport } from '../../services/viewer/DocumentViewerHtmlFileTransport';

/**
 * How long a rewritten main-frame navigation waits before it is issued.
 *
 * `onLoadIntercept` runs while ArkWeb is deciding that navigation, and the decision is only finished once the
 * callback returns. Issuing the replacement load from inside the callback put both the replacement `loadUrl()`
 * and the Browsing Identity setter it triggers on ArkWeb's pending-entry guard: the custom-UA setter walks the
 * frame tree and reloads, and the reentrancy guard aborts the process with SIGTRAP. Deferring by one task lets
 * the original decision finish first, so the rewrite is an ordinary pre-navigation load again.
 */
const SAME_WEB_NAVIGATION_REWRITE_DEFERRAL_MS: number = 0;

export interface BrowserWebNavigationInterceptionCoordinatorDependencies {
  adBlockCoordinator: BrowserAdBlockCoordinator;
  telegramWebCompatibilityService: TelegramWebCompatibilityService;
  webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
}

export interface BrowserWebNavigationMainFrameInput {
  tabId: string;
  targetUrl: string;
  request?: WebResourceRequest;
  source: BrowserWebComponentNavigationEventSource;
}

export interface BrowserWebNavigationInterceptionHost {
  isAdBlockCapabilitySupported: () => boolean;
  isControllerAttached: () => boolean;
  shouldStrengthenAdBlockingForSmoothScroll: () => boolean;
  refreshSiteProtectionAfterNavigationClean: () => void;
}

export class BrowserWebNavigationInterceptionCoordinator {
  private readonly adBlockCoordinator: BrowserAdBlockCoordinator;
  private readonly telegramWebCompatibilityService: TelegramWebCompatibilityService;
  private readonly webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  private readonly tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  /** One deferred rewrite per tab: a second decision must not race the replacement the first one scheduled. */
  private pendingRewriteTimerByTabId: Record<string, number | undefined> = {};

  constructor(dependencies: BrowserWebNavigationInterceptionCoordinatorDependencies) {
    this.adBlockCoordinator = dependencies.adBlockCoordinator;
    this.telegramWebCompatibilityService = dependencies.telegramWebCompatibilityService;
    this.webLoadRuntimeCoordinator = dependencies.webLoadRuntimeCoordinator;
    this.tabScopedEventContextCoordinator = dependencies.tabScopedEventContextCoordinator;
  }

  resolveMainFrameWebUrlDecision(
    input: BrowserWebNavigationMainFrameInput,
    host: BrowserWebNavigationInterceptionHost
  ): BrowserWebComponentWebUrlDecision {
    if (documentViewerHtmlFileTransport.isTransportUrl(input.targetUrl)) {
      const visibleUrl = documentViewerHtmlFileTransport.resolveVisibleUrl(input.targetUrl);
      return {
        action: 'allow_web',
        targetUrl: visibleUrl.length > 0 ? visibleUrl : input.targetUrl,
        reason: 'document_viewer_html_file'
      };
    }
    const context = this.tabScopedEventContextCoordinator.resolveContext(input.tabId);
    const isHttpFallbackBypass = sharedBrowserHttpsFirstNavigationService.beginMainFrameNavigation(
      input.tabId,
      input.targetUrl,
      {
        profileId: context.profileId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope
      }
    );
    if (input.source === 'override_url_loading' && input.request !== undefined) {
      const cleanedUrl = this.adBlockCoordinator.cleanNavigationUrl(this.buildAdBlockRequestContext(input, host));
      if (cleanedUrl.changed) {
        host.refreshSiteProtectionAfterNavigationClean();
        return {
          action: 'rewrite_same_web_navigation',
          targetUrl: cleanedUrl.url,
          reason: 'adblock_cleaned_url'
        };
      }
    }
    if (input.request !== undefined &&
      this.adBlockCoordinator.shouldBlockMainFrameNavigation(this.buildAdBlockRequestContext(input, host))) {
      return {
        action: 'deny',
        targetUrl: input.targetUrl,
        reason: 'adblock_blocked_navigation'
      };
    }
    if (this.telegramWebCompatibilityService.shouldRewriteMainFrameNavigation(input.targetUrl)) {
      const visibleUrl = this.telegramWebCompatibilityService.resolveVisibleUrl(input.targetUrl);
      return {
        action: 'rewrite_same_web_navigation',
        targetUrl: visibleUrl,
        reason: 'telegram_main_frame_rewrite'
      };
    }
    if (!isHttpFallbackBypass && input.source === 'load_intercept') {
      const httpsFirstDecision = sharedBrowserHttpsFirstNavigationService.resolveNavigationDecision(
        input.tabId,
        input.targetUrl,
        input.request,
        {
          profileId: context.profileId,
          privacyMode: context.privacyMode,
          dataScope: context.dataScope
        }
      );
      if (httpsFirstDecision !== undefined) {
        return {
          action: 'rewrite_same_web_navigation',
          targetUrl: httpsFirstDecision.targetUrl,
          reason: httpsFirstDecision.reason
        };
      }
    }
    return {
      action: 'allow_web',
      targetUrl: this.telegramWebCompatibilityService.resolveVisibleUrl(input.targetUrl),
      reason: 'allow_web'
    };
  }

  executeSameWebNavigationRewrite(tabId: string, url: string, reason: string): boolean {
    if (reason === 'https_first_upgrade') {
      sharedBrowserHttpsFirstNavigationService.attachFallbackExecutor(
        tabId,
        (fallbackTabId: string, fallbackUrl: string): boolean =>
          this.webLoadRuntimeCoordinator.loadUrlForTab(fallbackTabId, fallbackUrl, true, false, true,
            'InterceptionHttpsFallback')
      );
    }
    // The callback has to return before the replacement navigation is issued: ArkWeb is still deciding the
    // navigation this rewrite replaces, and anything that reaches the Controller from here — the load itself,
    // and the identity preparation the load performs — reenters that decision. The caller consumes the original
    // navigation, so returning true is what stops it.
    this.scheduleSameWebNavigationRewrite(tabId, url);
    return true;
  }

  /**
   * Returns immediately: the CALLER must consume the original navigation (`true`) and let this callback return,
   * because ArkWeb is still deciding that navigation until it does.
   */
  scheduleSameWebNavigationRewrite(tabId: string, url: string): void {
    this.cancelSameWebNavigationRewrite(tabId);
    this.pendingRewriteTimerByTabId[tabId] = setTimeout((): void => {
      this.pendingRewriteTimerByTabId[tabId] = undefined;
      this.webLoadRuntimeCoordinator.loadUrlForTab(tabId, url, true);
    }, SAME_WEB_NAVIGATION_REWRITE_DEFERRAL_MS);
  }

  cancelSameWebNavigationRewrite(tabId: string): void {
    const timerId = this.pendingRewriteTimerByTabId[tabId];
    if (timerId === undefined) {
      return;
    }
    this.pendingRewriteTimerByTabId[tabId] = undefined;
    clearTimeout(timerId);
  }

  private buildAdBlockRequestContext(
    input: BrowserWebNavigationMainFrameInput,
    host: BrowserWebNavigationInterceptionHost
  ): BrowserAdBlockRequestContext {
    const context = this.tabScopedEventContextCoordinator.resolveContext(input.tabId);
    return {
      tabId: input.tabId,
      request: input.request as WebResourceRequest,
      pageUrl: context.pageUrl,
      capabilitySupported: host.isAdBlockCapabilitySupported(),
      controllerAttached: host.isControllerAttached(),
      profileId: context.profileId,
      privacyMode: context.privacyMode,
      dataScope: context.dataScope,
      strengthenForSmoothScroll: host.shouldStrengthenAdBlockingForSmoothScroll()
    };
  }

}
