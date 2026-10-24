import { common } from '@kit.AbilityKit';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import {
  BrowserDataScope,
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID,
  ExternalNavigationSettings
} from '../../common/models/BrowserModels';
import { SiteIdentityService } from './SiteIdentityService';
import { QqWebLoginContext, sharedQqWebLoginCallbackService } from './QqWebLoginCallbackService';
import {
  ExternalNavigationLaunchResult,
  ExternalNavigationLaunchService,
  ExternalNavigationTargetLaunchInfo
} from './ExternalNavigationLaunchService';

export type ExternalNavigationPromptPreflightAction =
  'show_prompt' |
  'show_unavailable_message';

export interface ExternalNavigationDecision {
  shouldIntercept: boolean;
  shouldPrompt: boolean;
  shouldSuppressPrompt: boolean;
  shouldOpenDirectly: boolean;
  shouldBlock: boolean;
  isUserTriggered: boolean;
  appName: string;
  key: string;
  message: string;
}

export interface ExternalNavigationRequestContext {
  url: string;
  isMainFrame: boolean;
  isRequestGesture: boolean;
  recentWebActivation?: boolean;
  duplicateUrl: string;
  duplicateAt: number;
  now: number;
  dedupeIntervalMs: number;
  settings: ExternalNavigationSettings;
  currentOrigin: string;
  suppressionRecords: ExternalNavigationSuppressionRecord[];
  profileId?: BrowserProfileId;
}

export interface ExternalNavigationDialogModel {
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel: string;
  appName: string;
  displayOrigin: string;
  redactedOrigin: boolean;
  summaryLine: string;
}

export interface ExternalNavigationOpenResult extends ExternalNavigationLaunchResult {}

export interface ExternalNavigationSuppressionRecord {
  key: string;
  suppressedUntil: number;
}

export interface ExternalNavigationPromptPreflightResult {
  action: ExternalNavigationPromptPreflightAction;
  appName: string;
  fallbackUrl: string;
  message: string;
  faultCode: string;
  targetInfo: ExternalNavigationTargetLaunchInfo;
}

export class ExternalNavigationPolicyService {
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();
  private externalNavigationLaunchService: ExternalNavigationLaunchService = new ExternalNavigationLaunchService();

  buildRequestTriggeredByUser(isRequestGesture: boolean, recentWebActivation: boolean): boolean {
    return isRequestGesture || recentWebActivation;
  }

  shouldInterceptExternalNavigation(
    url: string,
    isMainFrame: boolean,
    isUserTriggered: boolean,
    duplicateUrl: string,
    duplicateAt: number,
    now: number,
    dedupeIntervalMs: number,
    settings: ExternalNavigationSettings,
    currentOrigin: string,
    suppressionRecords: ExternalNavigationSuppressionRecord[],
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): ExternalNavigationDecision {
    if (!isMainFrame && !isUserTriggered) {
      return this.buildPassThroughDecision();
    }

    const normalizedUrl = url.trim();
    if (normalizedUrl.length === 0) {
      return this.buildPassThroughDecision();
    }

    const appName = this.getAppName(normalizedUrl);
    const key = this.buildSuppressionKey(currentOrigin, normalizedUrl);
    const effectivePolicy = this.resolveEffectiveAppOpenPolicy(settings, currentOrigin, profileId);
    if (effectivePolicy === 'block') {
      return {
        shouldIntercept: true,
        shouldPrompt: false,
        shouldSuppressPrompt: false,
        shouldOpenDirectly: false,
        shouldBlock: true,
        isUserTriggered: isUserTriggered,
        appName: appName,
        key: key,
        message: resolveAppResourceText($r('app.string.external_nav_blocked', appName))
      };
    }
    if (effectivePolicy === 'allow') {
      if (!isUserTriggered) {
        return {
          shouldIntercept: true,
          shouldPrompt: false,
          shouldSuppressPrompt: true,
          shouldOpenDirectly: false,
          shouldBlock: false,
          isUserTriggered: isUserTriggered,
          appName: appName,
          key: key,
          message: resolveAppResourceText($r('app.string.external_nav_blocked_auto', appName))
        };
      }
      return {
        shouldIntercept: true,
        shouldPrompt: false,
        shouldSuppressPrompt: false,
        shouldOpenDirectly: true,
        shouldBlock: false,
        isUserTriggered: isUserTriggered,
        appName: appName,
        key: key,
        message: resolveAppResourceText($r('app.string.external_nav_allowed', appName))
      };
    }
    const shouldSuppressPrompt = normalizedUrl === duplicateUrl && now - duplicateAt < dedupeIntervalMs;
    const userSuppressed = this.isSuppressedByUserCancel(key, now, suppressionRecords);
    return {
      shouldIntercept: true,
      shouldPrompt: !shouldSuppressPrompt && !userSuppressed,
      shouldSuppressPrompt: shouldSuppressPrompt || userSuppressed,
      shouldOpenDirectly: false,
      shouldBlock: false,
      isUserTriggered: isUserTriggered,
      appName: appName,
      key: key,
      message: userSuppressed
        ? resolveAppResourceText($r('app.string.external_nav_suppressed', appName))
        : (isUserTriggered
          ? resolveAppResourceText($r('app.string.external_nav_request', appName))
          : resolveAppResourceText($r('app.string.external_nav_blocked_auto', appName)))
    };
  }

  shouldInterceptExternalNavigationRequest(
    context: ExternalNavigationRequestContext
  ): ExternalNavigationDecision {
    return this.shouldInterceptExternalNavigation(
      context.url,
      context.isMainFrame,
      this.buildRequestTriggeredByUser(context.isRequestGesture, context.recentWebActivation ?? false),
      context.duplicateUrl,
      context.duplicateAt,
      context.now,
      context.dedupeIntervalMs,
      context.settings,
      context.currentOrigin,
      context.suppressionRecords,
      context.profileId ?? DEFAULT_BROWSER_PROFILE_ID
    );
  }

  async rememberSiteRule(
    settings: ExternalNavigationSettings,
    currentOrigin: string,
    policy: 'allow' | 'block',
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    persist: (settings: ExternalNavigationSettings) => Promise<void>
  ): Promise<void> {
    const identity = this.siteIdentityService.resolve(currentOrigin);
    if (identity.primaryOrigin.length <= 0) {
      return;
    }
    const nextSettings: ExternalNavigationSettings = {
      appOpenPolicy: settings.appOpenPolicy,
      suppressAfterCancelMs: settings.suppressAfterCancelMs,
      siteRules: settings.siteRules
        .filter((rule) => rule.primaryOrigin !== identity.primaryOrigin || rule.profileId !== profileId)
        .concat([{
          profileId: profileId,
          origin: identity.primaryOrigin,
          siteKey: identity.siteKey,
          displayHost: identity.displayHost,
          primaryOrigin: identity.primaryOrigin,
          policy: policy,
          updatedAt: Date.now()
        }])
        .slice(-120)
    };
    await persist(nextSettings);
  }

  buildDialogModel(
    url: string,
    currentOrigin: string,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): ExternalNavigationDialogModel {
    const appName = this.getAppName(url);
    const displayOrigin = this.getDisplayOriginForScope(currentOrigin, dataScope);
    const redactedOrigin = dataScope === 'session_ephemeral';
    const scheme = this.getUrlScheme(url) || 'unknown';
    return {
      title: resolveAppResourceText($r('app.string.external_nav_open_title')),
      message: resolveAppResourceText($r('app.string.external_nav_open_message', displayOrigin, appName)),
      confirmLabel: resolveAppResourceText($r('app.string.settings_site_capability_rule_allow')),
      cancelLabel: resolveAppResourceText($r('app.string.settings_custom_home_cancel')),
      appName: appName,
      displayOrigin: displayOrigin,
      redactedOrigin: redactedOrigin,
      summaryLine:
        `externalNavigationDialog scope=${dataScope} originRedacted=${redactedOrigin ? 1 : 0} ` +
        `app=${appName.replace(/\s+/g, '_')} scheme=${scheme}`
    };
  }

  async openExternalLink(
    context: common.UIAbilityContext,
    url: string,
    loginContext?: QqWebLoginContext
  ): Promise<ExternalNavigationOpenResult> {
    const login = sharedQqWebLoginCallbackService.prepareLaunch(url, loginContext);
    let success = false;
    try {
      const result = await this.externalNavigationLaunchService.openExternalLink(context, {
        url: login?.launchUrl ?? url,
        source: 'external_navigation_prompt',
        userTriggered: true,
        redactDiagnostics: login !== undefined
      });
      success = result.success;
      return result;
    } finally {
      if (!success && login !== undefined) {
        sharedQqWebLoginCallbackService.cancel(login.requestId);
      }
    }
  }

  getAppName(url: string): string {
    const scheme = this.externalNavigationLaunchService.resolveExternalAppScheme(url);
    if (scheme === 'baiduboxapp') {
      return resolveAppResourceText($r('app.string.external_nav_baidu'));
    }
    if (scheme === 'bilibili') {
      return resolveAppResourceText($r('app.string.external_nav_bilibili'));
    }
    if (scheme === 'qklink') {
      return resolveAppResourceText($r('app.string.external_nav_quark'));
    }
    if (scheme.length > 0) {
      return resolveAppResourceText($r('app.string.external_nav_scheme_app', scheme));
    }
    return resolveAppResourceText($r('app.string.browser_external_navigation_prompt_view_model_001'));
  }

  private getStableAppKeyName(url: string): string {
    const scheme = this.externalNavigationLaunchService.resolveExternalAppScheme(url);
    if (scheme === 'baiduboxapp') {
      return '百度 App';
    }
    if (scheme === 'bilibili') {
      return '哔哩哔哩 App';
    }
    if (scheme === 'qklink') {
      return '夸克 App';
    }
    if (scheme.length > 0) {
      return `${scheme} 应用`;
    }
    return '其他应用';
  }

  async resolveTargetAppName(url: string): Promise<string> {
    try {
      const targetInfo = await this.externalNavigationLaunchService.resolveTargetLaunchInfo(url);
      return this.resolvePromptAppName(url, targetInfo);
    } catch (_error) {
    }
    return this.getAppName(url);
  }

  async resolvePromptPreflight(url: string): Promise<ExternalNavigationPromptPreflightResult> {
    const targetInfo = await this.externalNavigationLaunchService.resolveTargetLaunchInfo(url);
    const fallbackUrl = targetInfo.fallbackUrl.trim();
    const appName = this.resolvePromptAppName(url, targetInfo);
    if (targetInfo.launchUrl.trim().length <= 0 || targetInfo.classification === 'unsupported') {
      return {
        action: 'show_unavailable_message',
        appName: appName,
        fallbackUrl: fallbackUrl,
        message: resolveAppResourceText($r('app.string.external_nav_invalid_link')),
        faultCode: 'external_navigation_invalid_url',
        targetInfo: targetInfo
      };
    }
    if (this.isConfirmedNoMatchingAbility(targetInfo)) {
      return {
        action: 'show_unavailable_message',
        appName: appName,
        fallbackUrl: fallbackUrl,
        message: resolveAppResourceText($r('app.string.external_nav_no_app')),
        faultCode: 'external_navigation_no_ability',
        targetInfo: targetInfo
      };
    }
    return {
      action: 'show_prompt',
      appName: appName,
      fallbackUrl: fallbackUrl,
      message: targetInfo.multipleCandidates
        ? resolveAppResourceText($r('app.string.external_nav_multiple'))
        : resolveAppResourceText($r('app.string.external_nav_can_open')),
      faultCode: '',
      targetInfo: targetInfo
    };
  }

  buildSuppressionRecord(
    currentOrigin: string,
    url: string,
    now: number,
    suppressAfterCancelMs: number
  ): ExternalNavigationSuppressionRecord {
    return {
      key: this.buildSuppressionKey(currentOrigin, url),
      suppressedUntil: now + Math.max(0, suppressAfterCancelMs)
    };
  }

  pruneSuppressionRecords(
    records: ExternalNavigationSuppressionRecord[],
    now: number
  ): ExternalNavigationSuppressionRecord[] {
    return records.filter((record: ExternalNavigationSuppressionRecord) => {
      return record.key.trim().length > 0 && record.suppressedUntil > now;
    });
  }

  upsertSuppressionRecord(
    records: ExternalNavigationSuppressionRecord[],
    nextRecord: ExternalNavigationSuppressionRecord
  ): ExternalNavigationSuppressionRecord[] {
    return records
      .filter((record: ExternalNavigationSuppressionRecord) => record.key !== nextRecord.key)
      .concat([nextRecord])
      .slice(-80);
  }

  private buildPassThroughDecision(): ExternalNavigationDecision {
    return {
      shouldIntercept: false,
      shouldPrompt: false,
      shouldSuppressPrompt: false,
      shouldOpenDirectly: false,
      shouldBlock: false,
      isUserTriggered: false,
      appName: '',
      key: '',
      message: ''
    };
  }

  private isSuppressedByUserCancel(
    key: string,
    now: number,
    records: ExternalNavigationSuppressionRecord[]
  ): boolean {
    return records.some((record: ExternalNavigationSuppressionRecord) => {
      return record.key === key && record.suppressedUntil > now;
    });
  }

  private resolveEffectiveAppOpenPolicy(
    settings: ExternalNavigationSettings,
    currentOrigin: string,
    profileId: BrowserProfileId
  ): 'block' | 'ask' | 'allow' {
    const identity = this.siteIdentityService.resolve(currentOrigin);
    const rule = settings.siteRules.find((item) => {
      return item.primaryOrigin === identity.primaryOrigin && item.profileId === profileId;
    });
    return rule?.policy ?? settings.appOpenPolicy;
  }

  private buildSuppressionKey(origin: string, url: string): string {
    const originKey = origin.trim().toLowerCase();
    const scheme = this.getUrlScheme(url);
    return `${originKey}|${scheme}|${this.getStableAppKeyName(url).toLowerCase()}`;
  }

  private resolvePromptAppName(url: string, targetInfo: ExternalNavigationTargetLaunchInfo): string {
    if (targetInfo.multipleCandidates) {
      return resolveAppResourceText($r('app.string.external_nav_available_apps'));
    }
    const appName = targetInfo.appName.trim();
    if (appName.length > 0) {
      return appName;
    }
    return this.getAppName(url);
  }

  private isConfirmedNoMatchingAbility(targetInfo: ExternalNavigationTargetLaunchInfo): boolean {
    if (targetInfo.queryStatus !== 'unsupported' || targetInfo.abilityCount > 0) {
      return false;
    }
    if (targetInfo.queryErrorCode === '17700003' || targetInfo.queryErrorCode === '16000019') {
      return true;
    }
    const queryErrorMessage = targetInfo.queryErrorMessage.toLowerCase();
    return queryErrorMessage.indexOf('no matching ability') >= 0 ||
      queryErrorMessage.indexOf('no_matching_ability') >= 0 ||
      queryErrorMessage.indexOf('ability is not found') >= 0;
  }

  private getDisplayOrigin(origin: string): string {
    const host = this.getHostFromUrl(origin);
    return host.length > 0 ? host : origin;
  }

  private getDisplayOriginForScope(origin: string, dataScope: BrowserDataScope): string {
    if (dataScope === 'session_ephemeral') {
      return resolveAppResourceText($r('app.string.external_nav_private_page'));
    }
    return this.getDisplayOrigin(origin);
  }

  private getHostFromUrl(url: string): string {
    const withoutScheme = url.trim().replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
    const withoutUserInfo = withoutScheme.substring(withoutScheme.lastIndexOf('@') + 1);
    if (withoutUserInfo.startsWith('[')) {
      const endBracketIndex = withoutUserInfo.indexOf(']');
      return endBracketIndex >= 0 ? withoutUserInfo.substring(1, endBracketIndex) : withoutUserInfo;
    }
    const boundaryIndex = this.findFirstUrlBoundary(withoutUserInfo);
    const hostWithPort = boundaryIndex >= 0 ? withoutUserInfo.substring(0, boundaryIndex) : withoutUserInfo;
    const colonIndex = hostWithPort.indexOf(':');
    return colonIndex >= 0 ? hostWithPort.substring(0, colonIndex) : hostWithPort;
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

  private getUrlScheme(url: string): string {
    const match = url.trim().match(/^([a-z][a-z0-9+.-]*):/i);
    return match === null ? '' : match[1].toLowerCase();
  }
}
