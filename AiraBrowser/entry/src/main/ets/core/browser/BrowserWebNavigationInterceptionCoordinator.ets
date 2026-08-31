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
          this.webLoadRuntimeCoordinator.loadUrlForTab(fallbackTabId, fallbackUrl, true)
      );
    }
    return this.webLoadRuntimeCoordinator.loadUrlForTab(
      tabId,
      url,
      true
    );
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
