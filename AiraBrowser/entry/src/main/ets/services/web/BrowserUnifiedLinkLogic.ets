import {
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID,
  ExternalNavigationSettings
} from '../../common/models/BrowserModels';
import {
  ExternalNavigationDecision,
  ExternalNavigationPolicyService,
  ExternalNavigationSuppressionRecord
} from './ExternalNavigationPolicyService';

export type BrowserUnifiedLinkSource =
  'override_url_loading' |
  'load_intercept' |
  'window_new' |
  'manual_load';

export type BrowserUnifiedLinkAction =
  'allow_web' |
  'consume_internal' |
  'consume_extension_action' |
  'consume_security_block' |
  'rewrite_same_web_navigation' |
  'deny' |
  'open_external' |
  'show_info_bar' |
  'show_dialog' |
  'load_fallback_in_web';

export interface BrowserUnifiedLinkContext {
  tabId: string;
  url: string;
  originUrl: string;
  refererUrl: string;
  isMainFrame: boolean;
  isRequestGesture: boolean;
  isTabVisible: boolean;
  isWindowVisible: boolean;
  source: BrowserUnifiedLinkSource;
  fallbackUrl: string;
  openerTabId: string;
  canLoadInWebView: boolean;
  hasRecentAction: boolean;
  appLinkingExempt?: boolean;
  deeplinkExempt?: boolean;
  duplicateUrl: string;
  duplicateAt: number;
  now: number;
  dedupeIntervalMs: number;
  settings: ExternalNavigationSettings;
  currentOrigin: string;
  suppressionRecords: ExternalNavigationSuppressionRecord[];
  profileId?: BrowserProfileId;
}

export interface BrowserUnifiedLinkResult {
  handled: boolean;
  shouldConsumeWebLoad: boolean;
  action: BrowserUnifiedLinkAction;
  tabId: string;
  url: string;
  fallbackUrl: string;
  appName: string;
  message: string;
  isUserTriggered: boolean;
  key: string;
  reason: string;
  externalDecision?: ExternalNavigationDecision;
}

export class BrowserUnifiedLinkLogic {
  private readonly externalNavigationPolicyService: ExternalNavigationPolicyService;

  constructor(externalNavigationPolicyService: ExternalNavigationPolicyService = new ExternalNavigationPolicyService()) {
    this.externalNavigationPolicyService = externalNavigationPolicyService;
  }

  evaluate(context: BrowserUnifiedLinkContext): BrowserUnifiedLinkResult {
    const normalizedUrl = context.url.trim();
    if (normalizedUrl.length <= 0) {
      return this.buildAllowWebResult(context, 'empty_url');
    }

    if (context.canLoadInWebView) {
      return this.buildAllowWebResult(context, this.isHttpOrHttpsUrl(normalizedUrl)
        ? 'ordinary_web_url'
        : 'webview_supported_scheme');
    }

    const isUserTriggered = context.isRequestGesture || context.hasRecentAction || context.deeplinkExempt === true;
    if (!context.isMainFrame && !isUserTriggered) {
      return this.buildConsumedResult(context, 'consume_security_block', 'subframe_deeplink_blocked',
        '已阻止子框架自动打开外部应用。');
    }

    if (!this.canHandleExternalSchemeFromSurface(context)) {
      return this.buildConsumedResult(context, 'deny', 'external_policy_not_visible',
        '已阻止后台页面打开外部应用。');
    }

    const decision = this.externalNavigationPolicyService.shouldInterceptExternalNavigationRequest({
      url: normalizedUrl,
      isMainFrame: context.isMainFrame,
      isRequestGesture: context.isRequestGesture,
      recentWebActivation: context.hasRecentAction || context.deeplinkExempt === true,
      duplicateUrl: context.duplicateUrl,
      duplicateAt: context.duplicateAt,
      now: context.now,
      dedupeIntervalMs: context.dedupeIntervalMs,
      settings: context.settings,
      currentOrigin: context.currentOrigin,
      suppressionRecords: context.suppressionRecords,
      profileId: context.profileId ?? DEFAULT_BROWSER_PROFILE_ID
    });

    if (!decision.shouldIntercept) {
      return this.buildAllowWebResult(context, 'external_policy_pass_through');
    }
    if (decision.shouldBlock) {
      return this.buildExternalResult(context, decision, 'consume_security_block', 'external_policy_block');
    }
    if (decision.shouldOpenDirectly) {
      return this.buildExternalResult(context, decision, 'open_external', 'external_policy_allow');
    }
    if (decision.shouldSuppressPrompt) {
      return this.buildExternalResult(context, decision, 'deny', 'external_policy_suppressed');
    }
    if (!decision.isUserTriggered) {
      return this.buildExternalResult(context, decision, 'deny', 'external_policy_not_user_triggered');
    }
    if (decision.shouldPrompt) {
      return this.buildExternalResult(context, decision, 'show_info_bar', 'external_policy_prompt');
    }
    return this.buildExternalResult(context, decision, 'deny', 'external_policy_default_deny');
  }

  private buildAllowWebResult(context: BrowserUnifiedLinkContext, reason: string): BrowserUnifiedLinkResult {
    return {
      handled: false,
      shouldConsumeWebLoad: false,
      action: 'allow_web',
      tabId: context.tabId,
      url: context.url.trim(),
      fallbackUrl: context.fallbackUrl,
      appName: '',
      message: '',
      isUserTriggered: context.isRequestGesture || context.hasRecentAction,
      key: '',
      reason: reason
    };
  }

  private buildConsumedResult(
    context: BrowserUnifiedLinkContext,
    action: BrowserUnifiedLinkAction,
    reason: string,
    message: string
  ): BrowserUnifiedLinkResult {
    return {
      handled: true,
      shouldConsumeWebLoad: true,
      action: action,
      tabId: context.tabId,
      url: context.url.trim(),
      fallbackUrl: context.fallbackUrl,
      appName: this.externalNavigationPolicyService.getAppName(context.url),
      message: message,
      isUserTriggered: context.isRequestGesture || context.hasRecentAction,
      key: '',
      reason: reason
    };
  }

  private buildExternalResult(
    context: BrowserUnifiedLinkContext,
    decision: ExternalNavigationDecision,
    action: BrowserUnifiedLinkAction,
    reason: string
  ): BrowserUnifiedLinkResult {
    return {
      handled: true,
      shouldConsumeWebLoad: true,
      action: action,
      tabId: context.tabId,
      url: context.url.trim(),
      fallbackUrl: context.fallbackUrl,
      appName: decision.appName,
      message: decision.message,
      isUserTriggered: decision.isUserTriggered,
      key: decision.key,
      reason: reason,
      externalDecision: decision
    };
  }

  private isHttpOrHttpsUrl(url: string): boolean {
    const scheme = this.getUrlScheme(url);
    return scheme === 'http' || scheme === 'https';
  }

  private canHandleExternalSchemeFromSurface(context: BrowserUnifiedLinkContext): boolean {
    return context.deeplinkExempt === true || (context.isTabVisible && context.isWindowVisible);
  }

  private getUrlScheme(url: string): string {
    const match = url.trim().match(/^([a-z][a-z0-9+.-]*):/i);
    return match === null ? '' : match[1].toLowerCase();
  }
}
