import { Want, bundleManager, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type ExternalNavigationLaunchClassification =
  'http_app_link' |
  'deeplink' |
  'unsupported';

export type ExternalNavigationLaunchMode =
  'app_linking_only' |
  'deeplink_view_data';

export type ExternalNavigationLaunchStatus =
  'success' |
  'no_matching_ability' |
  'invalid_url' |
  'platform_blocked' |
  'failed_unknown';

export type ExternalNavigationAbilityQueryStatus =
  'supported' |
  'unsupported' |
  'skipped';

export type ExternalNavigationLaunchResolution =
  'direct' |
  'android_intent_scheme';

export interface ExternalNavigationLaunchRequest {
  url: string;
  originUrl?: string;
  source?: string;
  tabId?: string;
  userTriggered?: boolean;
  hideFailureTipDialog?: boolean;
  redactDiagnostics?: boolean;
  targetElement?: ExternalNavigationTargetElement;
  action?: string;
}

export interface ExternalNavigationTargetElement {
  bundleName: string;
  moduleName: string;
  abilityName: string;
}

export interface ExternalNavigationLaunchResult {
  success: boolean;
  status: ExternalNavigationLaunchStatus;
  classification: ExternalNavigationLaunchClassification;
  mode: ExternalNavigationLaunchMode;
  originalUrl: string;
  attemptedUrl: string;
  fallbackUrl: string;
  errorCode: string;
  errorMessage: string;
  message: string;
  userMessage: string;
  diagnosticSummary: string;
}

export interface ExternalNavigationTargetLaunchInfo {
  originalUrl: string;
  launchUrl: string;
  fallbackUrl: string;
  classification: ExternalNavigationLaunchClassification;
  resolution: ExternalNavigationLaunchResolution;
  appName: string;
  bundleName: string;
  abilityName: string;
  queryStatus: ExternalNavigationAbilityQueryStatus;
  queryErrorCode: string;
  queryErrorMessage: string;
  abilityCount: number;
  multipleCandidates: boolean;
}

const WANT_ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';
const WANT_PARAM_REQUEST_THAWING: string = 'requestThawing';
// GET_ABILITY_INFO ACL is currently PC/2in1-only; keep target app detail lookup hidden for phone/tablet builds.
const ENABLE_EXTERNAL_TARGET_APP_DETAIL_QUERY: boolean = false;
const FALLBACK_PARAM_NAMES: string[] = [
  's.browser_fallback_url',
  'browser_fallback_url'
];
const HARMONY_CLIENT_REWRITE_LAUNCH_API: string = 'startAbility_harmony_client_scheme_rewrite';
const OPEN_LINK_ALL_SCHEMES_LAUNCH_API: string = 'openLink_all_schemes';
// China Mobile activity pages build `com.greenpoint://android.mc10086.activity?<query>` from an
// Android token and the cross-platform `cn.10086.app://<query>` from a HarmonyOS/ArkWeb token. A
// page that misread the platform therefore leaves an Android-only scheme that the HarmonyOS client
// never registered, so the same query is retried through the cross-platform client entry.
const DEEPLINK_SCHEME_REWRITES: DeeplinkSchemeRewrite[] = [
  {
    androidPrefix: 'com.greenpoint://android.mc10086.activity?',
    harmonyPrefix: 'cn.10086.app://'
  }
];

interface ExternalNavigationLaunchResultInput {
  success: boolean;
  status: ExternalNavigationLaunchStatus;
  classification: ExternalNavigationLaunchClassification;
  mode: ExternalNavigationLaunchMode;
  originalUrl: string;
  attemptedUrl: string;
  fallbackUrl: string;
  errorCode: string;
  errorMessage: string;
  message: string;
  userMessage: string;
  request: ExternalNavigationLaunchRequest;
  launchApi: string;
  resolution: ExternalNavigationLaunchResolution;
  queryStatus: string;
  queryErrorCode: string;
  queryErrorMessage: string;
}

interface ExternalNavigationLaunchTarget {
  launchUrl: string;
  fallbackUrl: string;
  resolution: ExternalNavigationLaunchResolution;
}

interface ParsedIntentUrl {
  targetUrl: string;
  fallbackUrl: string;
}

interface DeeplinkAbilityQueryResult {
  status: ExternalNavigationAbilityQueryStatus;
  errorCode: string;
  errorMessage: string;
  abilityInfos: bundleManager.AbilityInfo[];
}

interface DeeplinkSchemeRewrite {
  androidPrefix: string;
  harmonyPrefix: string;
}

interface LaunchedAttempt {
  attemptedUrl: string;
  launchApi: string;
}

export class ExternalNavigationLaunchService {
  async openExternalLink(
    context: common.UIAbilityContext,
    request: ExternalNavigationLaunchRequest
  ): Promise<ExternalNavigationLaunchResult> {
    const normalizedUrl = request.url.trim();
    const launchTarget = this.resolveLaunchTarget(normalizedUrl);
    const launchUrl = launchTarget.launchUrl;
    const classification = this.classifyUrl(launchUrl);
    const fallbackUrl = launchTarget.fallbackUrl.length > 0
      ? launchTarget.fallbackUrl
      : this.extractFallbackUrl(launchUrl);
    const targetElement = this.normalizeTargetElement(request.targetElement);

    if (launchUrl.length <= 0 || classification === 'unsupported') {
      return this.buildResult({
        success: false,
        status: 'invalid_url',
        classification: classification,
        mode: 'deeplink_view_data',
        originalUrl: normalizedUrl,
        attemptedUrl: launchUrl,
        fallbackUrl: fallbackUrl,
        errorCode: '',
        errorMessage: '',
        message: '外部应用链接无效。',
        userMessage: '链接无效，无法打开外部应用。',
        request: request,
        launchApi: '',
        resolution: launchTarget.resolution,
        queryStatus: '',
        queryErrorCode: '',
        queryErrorMessage: ''
      });
    }

    if (request.targetElement !== undefined && targetElement === undefined) {
      return this.buildResult({
        success: false,
        status: 'invalid_url',
        classification: classification,
        mode: 'deeplink_view_data',
        originalUrl: normalizedUrl,
        attemptedUrl: launchUrl,
        fallbackUrl: fallbackUrl,
        errorCode: '',
        errorMessage: '',
        message: '外部应用目标无效。',
        userMessage: '目标应用信息无效，无法打开。',
        request: request,
        launchApi: '',
        resolution: launchTarget.resolution,
        queryStatus: '',
        queryErrorCode: '',
        queryErrorMessage: ''
      });
    }

    if (targetElement !== undefined) {
      return await this.tryOpenLink(
        context,
        request,
        launchUrl,
        classification,
        'deeplink_view_data',
        fallbackUrl,
        launchTarget.resolution,
        targetElement
      );
    }

    if (classification === 'http_app_link') {
      return await this.tryOpenLink(
        context,
        request,
        launchUrl,
        classification,
        'app_linking_only',
        fallbackUrl,
        launchTarget.resolution
      );
    }

    return await this.tryOpenLink(
      context,
      request,
      launchUrl,
      classification,
      'deeplink_view_data',
      fallbackUrl,
      launchTarget.resolution
    );
  }

  classifyUrl(url: string): ExternalNavigationLaunchClassification {
    const scheme = this.getUrlScheme(url);
    if (scheme === 'http' || scheme === 'https') {
      return 'http_app_link';
    }
    if (scheme.length > 0) {
      return 'deeplink';
    }
    return 'unsupported';
  }

  resolveExternalAppScheme(url: string): string {
    return this.getUrlScheme(this.resolveLaunchTarget(url.trim()).launchUrl);
  }

  async resolveTargetLaunchInfo(url: string): Promise<ExternalNavigationTargetLaunchInfo> {
    const launchTarget = this.resolveLaunchTarget(url.trim());
    const launchUrl = launchTarget.launchUrl;
    const classification = this.classifyUrl(launchUrl);
    if (launchUrl.length <= 0 || classification === 'unsupported') {
      return this.buildEmptyTargetLaunchInfo(
        url.trim(),
        launchUrl,
        launchTarget.fallbackUrl,
        classification,
        launchTarget.resolution,
        'unsupported',
        '',
        ''
      );
    }
    const queryResult = await this.queryLaunchAbility(launchUrl, classification);
    const abilityInfo = this.resolvePrimaryAbilityInfo(queryResult.abilityInfos);
    if (abilityInfo === undefined) {
      return this.buildEmptyTargetLaunchInfo(
        url.trim(),
        launchUrl,
        launchTarget.fallbackUrl,
        classification,
        launchTarget.resolution,
        queryResult.status,
        queryResult.errorCode,
        queryResult.errorMessage
      );
    }
    return {
      originalUrl: url.trim(),
      launchUrl: launchUrl,
      fallbackUrl: launchTarget.fallbackUrl,
      classification: classification,
      resolution: launchTarget.resolution,
      appName: this.resolveAbilityDisplayName(abilityInfo),
      bundleName: abilityInfo.bundleName,
      abilityName: abilityInfo.name,
      queryStatus: queryResult.status,
      queryErrorCode: queryResult.errorCode,
      queryErrorMessage: queryResult.errorMessage,
      abilityCount: queryResult.abilityInfos.length,
      multipleCandidates: queryResult.abilityInfos.length > 1
    };
  }

  private resolveLaunchTarget(url: string): ExternalNavigationLaunchTarget {
    const normalizedUrl = url.trim();
    const parsedIntent = this.parseIntentUrl(normalizedUrl);
    if (parsedIntent !== undefined && parsedIntent.targetUrl.length > 0) {
      return {
        launchUrl: parsedIntent.targetUrl,
        fallbackUrl: parsedIntent.fallbackUrl.length > 0
          ? parsedIntent.fallbackUrl
          : this.extractFallbackUrl(parsedIntent.targetUrl),
        resolution: 'android_intent_scheme'
      };
    }
    return {
      launchUrl: normalizedUrl,
      fallbackUrl: this.extractFallbackUrl(normalizedUrl),
      resolution: 'direct'
    };
  }

  private parseIntentUrl(url: string): ParsedIntentUrl | undefined {
    const trimmed = url.trim();
    if (this.getUrlScheme(trimmed) !== 'intent') {
      return undefined;
    }
    const lower = trimmed.toLowerCase();
    const marker = '#intent;';
    const markerIndex = lower.indexOf(marker);
    if (markerIndex <= 'intent:'.length) {
      return undefined;
    }

    const body = trimmed.substring('intent'.length, markerIndex);
    const params = trimmed.substring(markerIndex + marker.length);
    const targetScheme = this.extractIntentParam(params, 'scheme').trim().toLowerCase();
    if (!this.isValidScheme(targetScheme)) {
      return undefined;
    }

    return {
      targetUrl: `${targetScheme}${body}`,
      fallbackUrl: this.extractIntentFallbackUrl(params)
    };
  }

  private extractIntentParam(params: string, key: string): string {
    const expected = key.toLowerCase();
    const parts = params.split(';');
    for (let i = 0; i < parts.length; i += 1) {
      const part = parts[i];
      const eq = part.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const rawKey = part.substring(0, eq).trim().toLowerCase();
      if (rawKey === expected) {
        return part.substring(eq + 1).trim();
      }
    }
    return '';
  }

  private extractIntentFallbackUrl(params: string): string {
    const parts = params.split(';');
    for (let i = 0; i < parts.length; i += 1) {
      const part = parts[i];
      const eq = part.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key = part.substring(0, eq).trim().toLowerCase();
      if (FALLBACK_PARAM_NAMES.indexOf(key) < 0) {
        continue;
      }
      const fallbackUrl = this.normalizeFallbackCandidate(part.substring(eq + 1));
      if (this.isHttpUrl(fallbackUrl)) {
        return fallbackUrl;
      }
    }
    return '';
  }

  private async tryOpenLink(
    context: common.UIAbilityContext,
    request: ExternalNavigationLaunchRequest,
    targetUrl: string,
    classification: ExternalNavigationLaunchClassification,
    mode: ExternalNavigationLaunchMode,
    fallbackUrl: string,
    resolution: ExternalNavigationLaunchResolution,
    targetElement?: ExternalNavigationTargetElement
  ): Promise<ExternalNavigationLaunchResult> {
    const launchApi = this.resolveLaunchApi(mode, targetElement);
    const queryResult = mode === 'deeplink_view_data' && targetElement === undefined
      ? await this.queryDeeplinkAbility(targetUrl)
      : this.buildSkippedQueryResult();

    try {
      if (targetElement !== undefined) {
        await this.startTargetedAbility(context, targetUrl, targetElement, request.action);
      } else if (mode === 'app_linking_only') {
        await context.openLink(targetUrl, {
          appLinkingOnly: true,
          hideFailureTipDialog: request.hideFailureTipDialog === true
        });
      } else {
        await this.startDeeplinkAbility(context, targetUrl);
      }
      return this.buildResult({
        success: true,
        status: 'success',
        classification: classification,
        mode: mode,
        originalUrl: request.url.trim(),
        attemptedUrl: targetUrl,
        fallbackUrl: fallbackUrl,
        errorCode: '',
        errorMessage: '',
        message: this.buildSuccessMessage(mode),
        userMessage: this.buildSuccessUserMessage(),
        request: request,
        launchApi: launchApi,
        resolution: resolution,
        queryStatus: queryResult.status,
        queryErrorCode: queryResult.errorCode,
        queryErrorMessage: queryResult.errorMessage
      });
    } catch (error) {
      const businessError = error as BusinessError;
      const errorMessage = this.stringifyError(businessError);
      const errorCode = this.extractErrorCode(businessError, errorMessage);
      const status = this.resolveFailureStatus(errorCode, errorMessage);
      if (status === 'no_matching_ability' && mode === 'deeplink_view_data' && targetElement === undefined) {
        const recovered = await this.recoverDeeplinkLaunch(context, request, targetUrl);
        if (recovered !== undefined) {
          return this.buildResult({
            success: true,
            status: 'success',
            classification: classification,
            mode: mode,
            originalUrl: request.url.trim(),
            attemptedUrl: recovered.attemptedUrl,
            fallbackUrl: fallbackUrl,
            errorCode: '',
            errorMessage: '',
            message: this.buildSuccessMessage(mode),
            userMessage: this.buildSuccessUserMessage(),
            request: request,
            launchApi: recovered.launchApi,
            resolution: resolution,
            queryStatus: queryResult.status,
            queryErrorCode: queryResult.errorCode,
            queryErrorMessage: queryResult.errorMessage
          });
        }
      }
      const reportedErrorMessage = request.redactDiagnostics === true ? '' : errorMessage;
      return this.buildResult({
        success: false,
        status: status,
        classification: classification,
        mode: mode,
        originalUrl: request.url.trim(),
        attemptedUrl: targetUrl,
        fallbackUrl: fallbackUrl,
        errorCode: errorCode,
        errorMessage: reportedErrorMessage,
        message: this.buildFailureMessage(mode, status, errorCode, reportedErrorMessage),
        userMessage: this.buildFailureUserMessage(mode, status),
        request: request,
        launchApi: launchApi,
        resolution: resolution,
        queryStatus: queryResult.status,
        queryErrorCode: queryResult.errorCode,
        queryErrorMessage: queryResult.errorMessage
      });
    }
  }

  /**
   * Recovers from a page that built an Android-only app scheme because it misread the platform
   * token. The retry stays bounded and ordered: first the cross-platform client entry for the same
   * query, then the system's own URI router without a forced action. Each step only runs when the
   * previous one reported that no installed ability claimed the URI.
   */
  private async recoverDeeplinkLaunch(
    context: common.UIAbilityContext,
    request: ExternalNavigationLaunchRequest,
    targetUrl: string
  ): Promise<LaunchedAttempt | undefined> {
    const rewrittenUrl = this.resolveCrossPlatformSchemeRewrite(targetUrl);
    if (rewrittenUrl.length > 0) {
      try {
        await this.startDeeplinkAbility(context, rewrittenUrl);
        return {
          attemptedUrl: rewrittenUrl,
          launchApi: HARMONY_CLIENT_REWRITE_LAUNCH_API
        };
      } catch (_rewriteError) {
      }
    }
    // startAbility above forces `ohos.want.action.viewData`. A target app may declare the scheme
    // under a different action, so the last attempt lets the system match on the URI alone. It
    // prefers the cross-platform entry when the original URI was the Android-only scheme.
    const routerUrl = rewrittenUrl.length > 0 ? rewrittenUrl : targetUrl;
    try {
      await context.openLink(routerUrl, {
        appLinkingOnly: false,
        hideFailureTipDialog: request.hideFailureTipDialog === true
      });
      return {
        attemptedUrl: routerUrl,
        launchApi: OPEN_LINK_ALL_SCHEMES_LAUNCH_API
      };
    } catch (_openLinkError) {
    }
    return undefined;
  }

  resolveCrossPlatformSchemeRewrite(url: string): string {
    const normalizedUrl = url.trim();
    for (let index = 0; index < DEEPLINK_SCHEME_REWRITES.length; index += 1) {
      const rewrite = DEEPLINK_SCHEME_REWRITES[index];
      if (normalizedUrl.startsWith(rewrite.androidPrefix)) {
        return `${rewrite.harmonyPrefix}${normalizedUrl.substring(rewrite.androidPrefix.length)}`;
      }
    }
    return '';
  }

  private async startDeeplinkAbility(
    context: common.UIAbilityContext,
    targetUrl: string
  ): Promise<void> {
    const parameters: Record<string, Object> = {};
    parameters[WANT_PARAM_REQUEST_THAWING] = 1;
    const want: Want = {
      action: WANT_ACTION_VIEW_DATA,
      uri: targetUrl,
      parameters: parameters
    };
    await context.startAbility(want);
  }

  private async startTargetedAbility(
    context: common.UIAbilityContext,
    targetUrl: string,
    targetElement: ExternalNavigationTargetElement,
    action: string | undefined
  ): Promise<void> {
    const want: Want = {
      bundleName: targetElement.bundleName,
      moduleName: targetElement.moduleName,
      abilityName: targetElement.abilityName,
      uri: targetUrl
    };
    const normalizedAction = action?.trim() ?? '';
    if (normalizedAction.length > 0) {
      want.action = normalizedAction;
    }
    await context.startAbility(want);
  }

  private normalizeTargetElement(
    targetElement: ExternalNavigationTargetElement | undefined
  ): ExternalNavigationTargetElement | undefined {
    if (targetElement === undefined) {
      return undefined;
    }
    const bundleName = targetElement.bundleName.trim();
    const moduleName = targetElement.moduleName.trim();
    const abilityName = targetElement.abilityName.trim();
    if (bundleName.length <= 0 || moduleName.length <= 0 || abilityName.length <= 0) {
      return undefined;
    }
    return {
      bundleName: bundleName,
      moduleName: moduleName,
      abilityName: abilityName
    };
  }

  private async queryDeeplinkAbility(targetUrl: string): Promise<DeeplinkAbilityQueryResult> {
    return await this.queryLaunchAbility(targetUrl, 'deeplink');
  }

  private async queryLaunchAbility(
    targetUrl: string,
    classification: ExternalNavigationLaunchClassification
  ): Promise<DeeplinkAbilityQueryResult> {
    if (!ENABLE_EXTERNAL_TARGET_APP_DETAIL_QUERY) {
      return this.buildSkippedQueryResult();
    }
    try {
      const abilityInfos = await bundleManager.getAbilityInfo(
        targetUrl,
        this.resolveAbilityQueryFlags(classification)
      );
      return {
        status: abilityInfos.length > 0 ? 'supported' : 'unsupported',
        errorCode: '',
        errorMessage: '',
        abilityInfos: abilityInfos
      };
    } catch (error) {
      const businessError = error as BusinessError;
      const errorMessage = this.stringifyError(businessError);
      const errorCode = this.extractErrorCode(businessError, errorMessage);
      if (errorCode === '17700003') {
        return {
          status: 'unsupported',
          errorCode: errorCode,
          errorMessage: errorMessage,
          abilityInfos: []
        };
      }
      return {
        status: 'skipped',
        errorCode: errorCode,
        errorMessage: errorMessage,
        abilityInfos: []
      };
    }
  }

  private buildSkippedQueryResult(): DeeplinkAbilityQueryResult {
    return {
      status: 'skipped',
      errorCode: '',
      errorMessage: '',
      abilityInfos: []
    };
  }

  private resolveAbilityQueryFlags(classification: ExternalNavigationLaunchClassification): number {
    let flags = bundleManager.AbilityFlag.GET_ABILITY_INFO_WITH_APPLICATION;
    if (classification === 'http_app_link') {
      flags = flags | bundleManager.AbilityFlag.GET_ABILITY_INFO_WITH_APP_LINKING;
    }
    return flags;
  }

  private resolvePrimaryAbilityInfo(
    abilityInfos: bundleManager.AbilityInfo[]
  ): bundleManager.AbilityInfo | undefined {
    if (abilityInfos.length <= 0) {
      return undefined;
    }
    return abilityInfos[0];
  }

  private resolveAbilityDisplayName(abilityInfo: bundleManager.AbilityInfo): string {
    const applicationLabel = abilityInfo.applicationInfo?.label ?? '';
    const displayName = this.resolveDisplayLabel([
      applicationLabel,
      abilityInfo.label
    ]);
    return displayName;
  }

  private resolveDisplayLabel(candidates: string[]): string {
    for (let i = 0; i < candidates.length; i += 1) {
      const label = candidates[i].trim();
      if (label.length > 0 && !label.startsWith('$')) {
        return label;
      }
    }
    return '';
  }

  private buildEmptyTargetLaunchInfo(
    originalUrl: string,
    launchUrl: string,
    fallbackUrl: string,
    classification: ExternalNavigationLaunchClassification,
    resolution: ExternalNavigationLaunchResolution,
    queryStatus: ExternalNavigationAbilityQueryStatus,
    queryErrorCode: string,
    queryErrorMessage: string
  ): ExternalNavigationTargetLaunchInfo {
    return {
      originalUrl: originalUrl,
      launchUrl: launchUrl,
      fallbackUrl: fallbackUrl,
      classification: classification,
      resolution: resolution,
      appName: '',
      bundleName: '',
      abilityName: '',
      queryStatus: queryStatus,
      queryErrorCode: queryErrorCode,
      queryErrorMessage: queryErrorMessage,
      abilityCount: 0,
      multipleCandidates: false
    };
  }

  private resolveLaunchApi(
    mode: ExternalNavigationLaunchMode,
    targetElement?: ExternalNavigationTargetElement
  ): string {
    if (targetElement !== undefined) {
      return 'startAbility_targeted_viewData';
    }
    if (mode === 'deeplink_view_data') {
      return 'startAbility_viewData';
    }
    return 'openLink_appLinkingOnly';
  }

  private buildSuccessMessage(mode: ExternalNavigationLaunchMode): string {
    if (mode === 'deeplink_view_data') {
      return '已通过系统外部应用能力打开。';
    }
    return '已交给系统打开。';
  }

  private buildSuccessUserMessage(): string {
    return '已交给系统打开。';
  }

  private buildResult(input: ExternalNavigationLaunchResultInput): ExternalNavigationLaunchResult {
    return {
      success: input.success,
      status: input.status,
      classification: input.classification,
      mode: input.mode,
      originalUrl: input.originalUrl,
      attemptedUrl: input.attemptedUrl,
      fallbackUrl: input.fallbackUrl,
      errorCode: input.errorCode,
      errorMessage: input.errorMessage,
      message: input.message,
      userMessage: input.userMessage,
      diagnosticSummary: this.buildDiagnosticSummary(input)
    };
  }

  private buildDiagnosticSummary(input: ExternalNavigationLaunchResultInput): string {
    const urlsRedacted = input.request.redactDiagnostics === true;
    return [
      `success=${input.success ? 1 : 0}`,
      `status=${input.status}`,
      `classification=${input.classification}`,
      `mode=${input.mode}`,
      `launchApi=${this.sanitizeDiagnosticValue(input.launchApi)}`,
      `resolution=${input.resolution}`,
      `source=${this.sanitizeDiagnosticValue(input.request.source ?? '')}`,
      `userTriggered=${input.request.userTriggered === true ? 1 : 0}`,
      `origin=${this.sanitizeDiagnosticValue(urlsRedacted ? '<redacted>' : (input.request.originUrl ?? ''))}`,
      `original=${this.sanitizeDiagnosticValue(urlsRedacted ? '<redacted>' : input.originalUrl)}`,
      `attempted=${this.sanitizeDiagnosticValue(urlsRedacted ? '<redacted>' : input.attemptedUrl)}`,
      `fallback=${this.sanitizeDiagnosticValue(urlsRedacted ? '<redacted>' : input.fallbackUrl)}`,
      `query=${this.sanitizeDiagnosticValue(input.queryStatus)}`,
      `queryErrorCode=${this.sanitizeDiagnosticValue(input.queryErrorCode)}`,
      `queryError=${this.sanitizeDiagnosticValue(urlsRedacted && input.queryErrorMessage.length > 0 ?
        '<redacted>' : input.queryErrorMessage)}`,
      `errorCode=${this.sanitizeDiagnosticValue(input.errorCode)}`,
      `error=${this.sanitizeDiagnosticValue(urlsRedacted && input.errorMessage.length > 0 ?
        '<redacted>' : input.errorMessage)}`
    ].join(' ');
  }

  private buildFailureMessage(
    mode: ExternalNavigationLaunchMode,
    status: ExternalNavigationLaunchStatus,
    errorCode: string,
    errorMessage: string
  ): string {
    if (status === 'no_matching_ability') {
      if (mode === 'app_linking_only') {
        return `没有已安装应用声明可打开此 AppLinking 链接。${this.buildErrorSuffix(errorCode, errorMessage)}`;
      }
      return `没有已安装应用声明可打开此外部链接。${this.buildErrorSuffix(errorCode, errorMessage)}`;
    }
    if (status === 'platform_blocked') {
      return `系统暂时阻止打开外部应用。${this.buildErrorSuffix(errorCode, errorMessage)}`;
    }
    if (status === 'invalid_url') {
      return `外部应用链接无效。${this.buildErrorSuffix(errorCode, errorMessage)}`;
    }
    return `打开外部应用失败。${this.buildErrorSuffix(errorCode, errorMessage)}`;
  }

  private buildFailureUserMessage(
    mode: ExternalNavigationLaunchMode,
    status: ExternalNavigationLaunchStatus
  ): string {
    if (status === 'no_matching_ability') {
      if (mode === 'app_linking_only') {
        return '当前链接无法由已安装应用处理。';
      }
      return '没有找到可打开此链接的应用。';
    }
    if (status === 'platform_blocked') {
      return '系统暂时阻止打开外部应用，请回到前台后重试。';
    }
    if (status === 'invalid_url') {
      return '链接无效，无法打开外部应用。';
    }
    return '打开外部应用失败。';
  }

  private buildErrorSuffix(errorCode: string, errorMessage: string): string {
    if (errorCode.length <= 0 && errorMessage.length <= 0) {
      return '';
    }
    return ` code=${errorCode} error=${errorMessage}`;
  }

  private resolveFailureStatus(errorCode: string, errorMessage: string): ExternalNavigationLaunchStatus {
    if (errorCode === '16000019' ||
      errorCode === '17700003' ||
      errorMessage.indexOf('No matching ability') >= 0 ||
      errorMessage.indexOf('No_matching_ability') >= 0 ||
      errorMessage.indexOf('ability is not found') >= 0) {
      return 'no_matching_ability';
    }
    if (errorCode === '401') {
      return 'invalid_url';
    }
    if (errorCode === '16000053' || errorCode === '16000136') {
      return 'platform_blocked';
    }
    return 'failed_unknown';
  }

  private extractFallbackUrl(url: string): string {
    const queryStart = url.indexOf('?');
    if (queryStart < 0 || queryStart >= url.length - 1) {
      return '';
    }
    const fragmentStart = url.indexOf('#', queryStart + 1);
    const query = fragmentStart < 0
      ? url.substring(queryStart + 1)
      : url.substring(queryStart + 1, fragmentStart);
    const pairs = query.split('&');
    for (let i = 0; i < pairs.length; i += 1) {
      const pair = pairs[i];
      const eq = pair.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const name = this.decodeQueryComponent(pair.substring(0, eq)).toLowerCase();
      if (FALLBACK_PARAM_NAMES.indexOf(name) < 0) {
        continue;
      }
      const candidate = this.normalizeFallbackCandidate(pair.substring(eq + 1));
      if (this.isHttpUrl(candidate)) {
        return candidate;
      }
    }
    return '';
  }

  private normalizeFallbackCandidate(value: string): string {
    let candidate = value.trim();
    for (let i = 0; i < 3; i += 1) {
      if (this.isHttpUrl(candidate)) {
        return candidate;
      }
      const decoded = this.decodeQueryComponent(candidate).trim();
      if (decoded === candidate) {
        return decoded;
      }
      candidate = decoded;
    }
    return candidate;
  }

  private decodeQueryComponent(value: string): string {
    try {
      return decodeURIComponent(value.replace(/\+/g, '%20'));
    } catch (_error) {
      return value.replace(/\+/g, ' ');
    }
  }

  private isHttpUrl(url: string): boolean {
    const scheme = this.getUrlScheme(url);
    return scheme === 'http' || scheme === 'https';
  }

  private getUrlScheme(url: string): string {
    const trimmed = url.trim();
    const colonIndex = trimmed.indexOf(':');
    if (colonIndex <= 0) {
      return '';
    }
    return trimmed.substring(0, colonIndex).toLowerCase();
  }

  private isValidScheme(scheme: string): boolean {
    const normalizedScheme = scheme.trim().toLowerCase();
    if (normalizedScheme.length <= 0) {
      return false;
    }
    const firstCode = normalizedScheme.charCodeAt(0);
    if (firstCode < 97 || firstCode > 122) {
      return false;
    }
    for (let i = 1; i < normalizedScheme.length; i += 1) {
      const code = normalizedScheme.charCodeAt(i);
      const isLowerAlpha = code >= 97 && code <= 122;
      const isNumber = code >= 48 && code <= 57;
      const isAllowedSymbol = normalizedScheme[i] === '+' ||
        normalizedScheme[i] === '-' ||
        normalizedScheme[i] === '.';
      if (!isLowerAlpha && !isNumber && !isAllowedSymbol) {
        return false;
      }
    }
    return true;
  }

  private stringifyError(error: BusinessError): string {
    if (error === undefined || error === null) {
      return '';
    }
    const message = error.message ?? '';
    if (message.length > 0) {
      return message;
    }
    try {
      return JSON.stringify(error);
    } catch (_stringifyError) {
      return `${error}`;
    }
  }

  private extractErrorCode(error: BusinessError, errorMessage: string): string {
    if (error !== undefined && error !== null && error.code !== undefined && error.code !== 0) {
      return `${error.code}`;
    }
    const codeMatch = errorMessage.match(/\b\d{3,8}\b/);
    return codeMatch === null ? '' : codeMatch[0];
  }

  private sanitizeDiagnosticValue(value: string): string {
    return value.replace(/\s+/g, '_').substring(0, 320);
  }
}
