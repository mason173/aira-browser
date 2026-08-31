import {
  BrowserHttpsFirstDeclinedRetryRecord,
  BrowserHttpsFirstHttpSessionGrantRecord,
  BrowserWebSecuritySettingsRepository,
  sharedBrowserWebSecuritySettingsRepository
} from '../../data/preferences/BrowserWebSecuritySettingsRepository';
import {
  BrowserDataBoundary,
  BrowserDataBoundaryInput,
  BrowserProfileId,
  buildBrowserDataBoundary,
  normalizeBrowserProfileId
} from '../../common/models/BrowserModels';
import { BrowserPrivacyEffectPolicyService } from '../privacy/BrowserPrivacyEffectPolicyService';
import { SiteIdentityService } from './SiteIdentityService';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface BrowserHttpsFirstUpgradeDecision {
  targetUrl: string;
  reason: string;
}

export type BrowserHttpsFirstFallbackExecutor = (tabId: string, fallbackUrl: string) => boolean;

export type BrowserHttpsFirstFailureAction =
  'normal_failure' |
  'automatic_http_fallback' |
  'require_http_confirmation';

export type BrowserHttpsFirstFailureDelivery = 'apply' | 'suppress_duplicate';

export interface BrowserHttpsFirstFailureDecision {
  action: BrowserHttpsFirstFailureAction;
  delivery: BrowserHttpsFirstFailureDelivery;
  attemptId: number;
  failedUrl: string;
  fallbackUrl: string;
  reason: string;
}

export interface BrowserHttpsFirstResourceFailureInput {
  requestUrl: string;
  isMainFrame: boolean;
  errorCode: number;
  navigationId: number;
}

export interface BrowserHttpsFirstSslFailureInput {
  requestUrl: string;
  isMainFrame: boolean;
  isFatalError: boolean;
  navigationId: number;
}

export interface BrowserHttpsFirstPreparedFallback {
  attemptId: number;
  tabId: string;
  fallbackUrl: string;
  fallbackExecutor: BrowserHttpsFirstFallbackExecutor;
}

type BrowserHttpsFirstUpgradeSource = 'browser_generated' | 'intercepted_http';

type BrowserHttpsFirstUpgradeAttemptPhase =
  'upgrading' |
  'awaiting_secondary_failure_signal' |
  'awaiting_http_confirmation' |
  'automatic_http_fallback_pending' |
  'fallback_prepared';

interface BrowserHttpsFirstUpgradeAttempt {
  attemptId: number;
  originalUrl: string;
  upgradedUrl: string;
  strictMode: boolean;
  boundary: BrowserDataBoundary;
  source: BrowserHttpsFirstUpgradeSource;
  phase: BrowserHttpsFirstUpgradeAttemptPhase;
  failedUrl: string;
  navigationId: number;
  fallbackExecutor?: BrowserHttpsFirstFallbackExecutor;
}

interface BrowserHttpsFirstDeclinedRetry {
  originalUrl: string;
  upgradedUrl: string;
  boundary: BrowserDataBoundary;
  source: BrowserHttpsFirstUpgradeSource;
  fallbackExecutor?: BrowserHttpsFirstFallbackExecutor;
}

interface BrowserHttpsFirstHttpSessionGrant {
  anchorHost: string;
  effectivePort: number;
  boundary: BrowserDataBoundary;
  expiresAt: number;
}

const HTTP_FALLBACK_EXCEPTION_LIFETIME_MS: number = 15 * 24 * 60 * 60 * 1000;
const HTTPS_FIRST_DECLINED_RETRY_LIFETIME_MS: number = 24 * 60 * 60 * 1000;
const HTTPS_FIRST_LOG_DOMAIN: number = 0x0000;
const HTTPS_FIRST_LOG_TAG: string = 'HttpsFirstNav';
const HTTP_PRESENTATION_HOST_ALIASES: string[] = ['m', 'mobile', 'wap', 'www'];

const HTTPS_FIRST_FALLBACK_ERROR_CODES: number[] = [
  -100,
  -101,
  -102,
  -103,
  -104,
  -107,
  -112,
  -113,
  -118
];

export class BrowserHttpsFirstNavigationService {
  private readonly settingsRepository: BrowserWebSecuritySettingsRepository;
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private readonly siteIdentityService: SiteIdentityService = new SiteIdentityService();
  private attemptsByTabId: Record<string, BrowserHttpsFirstUpgradeAttempt | undefined> = {};
  private declinedRetryByTabId: Record<string, BrowserHttpsFirstDeclinedRetry | undefined> = {};
  private httpSessionGrantByTabId: Record<string, BrowserHttpsFirstHttpSessionGrant | undefined> = {};
  private privateHttpFallbackExceptionsByKey: Record<string, boolean | undefined> = {};
  private nextAttemptId: number = 1;

  constructor(
    settingsRepository: BrowserWebSecuritySettingsRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService()
  ) {
    this.settingsRepository = settingsRepository;
    this.privacyEffectPolicy = privacyEffectPolicy;
  }

  registerBrowserGeneratedUpgrade(
    tabId: string,
    upgradedUrl: string,
    fallbackUrl: string,
    boundary: BrowserDataBoundaryInput,
    fallbackExecutor: BrowserHttpsFirstFallbackExecutor
  ): boolean {
    const normalizedTabId = tabId.trim();
    const normalizedUpgradedUrl = upgradedUrl.trim();
    const normalizedFallbackUrl = fallbackUrl.trim();
    if (normalizedTabId.length === 0 ||
      !this.urlsMatch(this.buildUpgradeUrl(normalizedFallbackUrl), normalizedUpgradedUrl)) {
      return false;
    }
    this.clearDeclinedRetry(normalizedTabId);
    this.clearHttpSessionGrant(normalizedTabId);
    this.attemptsByTabId[normalizedTabId] = {
      attemptId: this.allocateAttemptId(),
      originalUrl: normalizedFallbackUrl,
      upgradedUrl: normalizedUpgradedUrl,
      strictMode: this.settingsRepository.getSettings().httpsFirstEnabled,
      boundary: buildBrowserDataBoundary(boundary),
      source: 'browser_generated',
      phase: 'upgrading',
      failedUrl: '',
      navigationId: 0,
      fallbackExecutor: fallbackExecutor
    };
    this.logAttempt('registered', this.attemptsByTabId[normalizedTabId] as BrowserHttpsFirstUpgradeAttempt,
      normalizedTabId);
    return true;
  }

  attachFallbackExecutor(tabId: string, fallbackExecutor: BrowserHttpsFirstFallbackExecutor): void {
    const attempt = this.attemptsByTabId[tabId];
    if (attempt !== undefined) {
      attempt.fallbackExecutor = fallbackExecutor;
    }
  }

  prepareProgrammaticNavigation(
    tabId: string,
    targetUrl: string,
    browserGeneratedHttpFallbackUrl: string,
    boundary: BrowserDataBoundaryInput,
    fallbackExecutor: BrowserHttpsFirstFallbackExecutor
  ): boolean {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return false;
    }
    const normalizedFallbackUrl = browserGeneratedHttpFallbackUrl.trim();
    if (normalizedFallbackUrl.length > 0) {
      return this.registerBrowserGeneratedUpgrade(
        normalizedTabId,
        targetUrl,
        normalizedFallbackUrl,
        boundary,
        fallbackExecutor
      );
    }
    this.cancelAttempt(normalizedTabId);
    return this.beginMainFrameNavigation(normalizedTabId, targetUrl, boundary);
  }

  beginMainFrameNavigation(
    tabId: string,
    targetUrl: string,
    boundary: BrowserDataBoundaryInput
  ): boolean {
    const normalizedUrl = targetUrl.trim();
    if (!this.isHttpOrHttpsUrl(normalizedUrl)) {
      return false;
    }
    const normalizedBoundary = buildBrowserDataBoundary(boundary);
    const httpAllowed = this.isHttpFallbackSiteAllowed(normalizedUrl, boundary);
    const sessionGrant = this.resolveHttpSessionGrant(tabId, normalizedBoundary, normalizedUrl);
    const sessionAllowed = sessionGrant !== undefined &&
      this.isHttpSessionGrantAllowed(sessionGrant, normalizedUrl, normalizedBoundary);
    const declinedRetry = this.declinedRetryByTabId[tabId];
    if (declinedRetry !== undefined && !this.urlsMatch(normalizedUrl, declinedRetry.upgradedUrl)) {
      this.clearDeclinedRetry(tabId);
    }
    if (sessionAllowed) {
      this.attemptsByTabId[tabId] = undefined;
      return true;
    }
    if (sessionGrant !== undefined) {
      this.clearHttpSessionGrant(tabId);
    }
    if (httpAllowed) {
      this.replaceHttpSessionGrant(
        tabId,
        this.buildHttpSessionGrant(
          normalizedUrl,
          normalizedBoundary,
          this.resolveHttpFallbackSiteExpiration(normalizedUrl, normalizedBoundary)
        )
      );
      this.attemptsByTabId[tabId] = undefined;
      return true;
    }
    const attempt = this.attemptsByTabId[tabId];
    if (attempt !== undefined &&
      this.isServerDowngradeForCurrentAttempt(attempt, normalizedUrl, normalizedBoundary)) {
      this.replaceHttpSessionGrant(
        tabId,
        this.buildHttpSessionGrant(normalizedUrl, normalizedBoundary)
      );
      this.attemptsByTabId[tabId] = undefined;
      this.logAttempt('server_downgrade_fallback', attempt, tabId);
      return true;
    }
    if (attempt !== undefined && !this.urlsMatch(normalizedUrl, attempt.originalUrl) &&
      !this.urlsMatch(normalizedUrl, attempt.upgradedUrl)) {
      this.attemptsByTabId[tabId] = undefined;
    }
    return false;
  }

  resolveRememberedHttpFallbackUrl(
    fallbackUrl: string,
    boundary: BrowserDataBoundaryInput
  ): string {
    const normalizedFallbackUrl = fallbackUrl.trim();
    return this.isHttpFallbackSiteAllowed(normalizedFallbackUrl, boundary) ? normalizedFallbackUrl : '';
  }

  resolveNavigationDecision(
    tabId: string,
    targetUrl: string,
    request: WebResourceRequest | undefined,
    boundary: BrowserDataBoundaryInput
  ): BrowserHttpsFirstUpgradeDecision | undefined {
    const normalizedUrl = targetUrl.trim();
    const enabled = this.settingsRepository.getSettings().httpsFirstEnabled;
    const isGet = request !== undefined && this.isGetRequest(request);
    if (!enabled || request === undefined || !isGet) {
      return undefined;
    }
    const upgradedUrl = this.buildUpgradeUrl(normalizedUrl);
    if (upgradedUrl.length === 0) {
      return undefined;
    }
    this.clearDeclinedRetry(tabId);
    this.attemptsByTabId[tabId] = {
      attemptId: this.allocateAttemptId(),
      originalUrl: normalizedUrl,
      upgradedUrl: upgradedUrl,
      strictMode: true,
      boundary: buildBrowserDataBoundary(boundary),
      source: 'intercepted_http',
      phase: 'upgrading',
      failedUrl: '',
      navigationId: 0
    };
    this.logAttempt('registered', this.attemptsByTabId[tabId] as BrowserHttpsFirstUpgradeAttempt, tabId);
    return {
      targetUrl: upgradedUrl,
      reason: 'https_first_upgrade'
    };
  }

  resolveResourceFailureDecision(
    tabId: string,
    input: BrowserHttpsFirstResourceFailureInput
  ): BrowserHttpsFirstFailureDecision {
    const eligible = HTTPS_FIRST_FALLBACK_ERROR_CODES.indexOf(input.errorCode) >= 0;
    return this.resolveFailureDecision(
      tabId,
      input.requestUrl,
      input.isMainFrame,
      eligible,
      input.navigationId,
      `resource_error_${input.errorCode}`
    );
  }

  resolveSslFailureDecision(
    tabId: string,
    input: BrowserHttpsFirstSslFailureInput
  ): BrowserHttpsFirstFailureDecision {
    return this.resolveFailureDecision(
      tabId,
      input.requestUrl,
      input.isMainFrame,
      true,
      input.navigationId,
      input.isFatalError ? 'ssl_error_fatal' : 'ssl_error'
    );
  }

  bindNavigationAttempt(tabId: string, targetUrl: string, navigationId: number): void {
    const attempt = this.attemptsByTabId[tabId];
    if (attempt === undefined || navigationId <= 0 || !this.urlsMatch(targetUrl, attempt.upgradedUrl)) {
      return;
    }
    attempt.navigationId = navigationId;
  }

  isAttemptCurrent(tabId: string, attemptId: number): boolean {
    return attemptId > 0 && this.attemptsByTabId[tabId]?.attemptId === attemptId;
  }

  declineFallback(tabId: string, attemptId: number): boolean {
    const attempt = this.attemptsByTabId[tabId];
    if (attempt === undefined) {
      return false;
    }
    if (attempt.attemptId !== attemptId) {
      return false;
    }
    if (attempt.phase !== 'awaiting_http_confirmation') {
      return false;
    }
    if (attempt.fallbackExecutor === undefined) {
      return false;
    }
    this.declinedRetryByTabId[tabId] = {
      originalUrl: attempt.originalUrl,
      upgradedUrl: attempt.upgradedUrl,
      boundary: attempt.boundary,
      source: attempt.source,
      fallbackExecutor: attempt.fallbackExecutor
    };
    const retryDataPolicy = this.privacyEffectPolicy.resolveDataPolicyForBoundary(
      'https_first_retry_provenance',
      attempt.boundary
    );
    if (retryDataPolicy.persistentWriteAllowed) {
      this.settingsRepository.rememberHttpsFirstDeclinedRetry(
        tabId,
        attempt.boundary.profileId,
        attempt.originalUrl,
        attempt.upgradedUrl,
        attempt.source,
        Date.now() + HTTPS_FIRST_DECLINED_RETRY_LIFETIME_MS
      );
    } else {
      this.settingsRepository.clearHttpsFirstDeclinedRetry(tabId);
    }
    this.attemptsByTabId[tabId] = undefined;
    this.logAttempt('declined', attempt, tabId);
    return true;
  }

  rearmDeclinedRetry(tabId: string, targetHttpsUrl: string): boolean {
    const normalizedTabId = tabId.trim();
    const normalizedTargetUrl = targetHttpsUrl.trim();
    const retry = this.resolveDeclinedRetry(normalizedTabId);
    if (retry === undefined) {
      return false;
    }
    const targetMatches = this.urlsMatch(normalizedTargetUrl, retry.upgradedUrl);
    const recipeValid = this.urlsMatch(this.buildUpgradeUrl(retry.originalUrl), retry.upgradedUrl);
    if (!targetMatches || !recipeValid) {
      this.clearDeclinedRetry(normalizedTabId);
      return false;
    }
    const attempt: BrowserHttpsFirstUpgradeAttempt = {
      attemptId: this.allocateAttemptId(),
      originalUrl: retry.originalUrl,
      upgradedUrl: retry.upgradedUrl,
      strictMode: this.settingsRepository.getSettings().httpsFirstEnabled,
      boundary: retry.boundary,
      source: retry.source,
      phase: 'upgrading',
      failedUrl: '',
      navigationId: 0,
      fallbackExecutor: retry.fallbackExecutor
    };
    this.clearDeclinedRetry(normalizedTabId);
    this.clearHttpSessionGrant(normalizedTabId);
    this.attemptsByTabId[normalizedTabId] = attempt;
    this.logAttempt('rearmed_retry', attempt, normalizedTabId);
    return true;
  }

  prepareFallback(
    tabId: string,
    attemptId: number,
    rememberSiteException: boolean = false
  ): BrowserHttpsFirstPreparedFallback | undefined {
    const attempt = this.attemptsByTabId[tabId];
    if (attempt === undefined || attempt.attemptId !== attemptId || attempt.fallbackExecutor === undefined ||
      (attempt.phase !== 'awaiting_http_confirmation' &&
        attempt.phase !== 'automatic_http_fallback_pending')) {
      return undefined;
    }
    const grantExpiresAt = rememberSiteException ? Date.now() + HTTP_FALLBACK_EXCEPTION_LIFETIME_MS : 0;
    if (rememberSiteException) {
      this.rememberHttpFallbackSite(attempt, grantExpiresAt);
    }
    attempt.phase = 'fallback_prepared';
    this.replaceHttpSessionGrant(
      tabId,
      this.buildHttpSessionGrant(attempt.originalUrl, attempt.boundary, grantExpiresAt)
    );
    return {
      attemptId: attempt.attemptId,
      tabId: tabId,
      fallbackUrl: attempt.originalUrl,
      fallbackExecutor: attempt.fallbackExecutor
    };
  }

  executePreparedFallback(prepared: BrowserHttpsFirstPreparedFallback): boolean {
    const attempt = this.attemptsByTabId[prepared.tabId];
    if (attempt === undefined || attempt.attemptId !== prepared.attemptId || attempt.phase !== 'fallback_prepared') {
      return false;
    }
    let issued = false;
    try {
      issued = prepared.fallbackExecutor(prepared.tabId, prepared.fallbackUrl);
    } catch (_error) {
      issued = false;
    }
    const currentAttempt = this.attemptsByTabId[prepared.tabId];
    if (currentAttempt?.attemptId === prepared.attemptId) {
      this.attemptsByTabId[prepared.tabId] = undefined;
    }
    if (!issued) {
      this.clearHttpSessionGrant(prepared.tabId);
    }
    hilog.info(
      HTTPS_FIRST_LOG_DOMAIN,
      HTTPS_FIRST_LOG_TAG,
      'fallback execute tab=%{public}s attempt=%{public}d issued=%{public}s',
      prepared.tabId,
      prepared.attemptId,
      issued ? '1' : '0'
    );
    return issued;
  }

  cancelAttempt(tabId: string, attemptId: number = 0): void {
    if (attemptId <= 0) {
      this.clearDeclinedRetry(tabId);
    }
    const attempt = this.attemptsByTabId[tabId];
    if (attempt !== undefined && (attemptId <= 0 || attempt.attemptId === attemptId)) {
      this.attemptsByTabId[tabId] = undefined;
      this.logAttempt('cancelled', attempt, tabId);
    }
  }

  cancelFallback(tabId: string, url: string): void {
    const grant = this.httpSessionGrantByTabId[tabId];
    if (grant !== undefined && this.isHttpSessionGrantAllowed(grant, url, grant.boundary)) {
      this.clearHttpSessionGrant(tabId);
    }
  }

  finishNavigation(tabId: string, url: string): void {
    const normalizedUrl = url.trim();
    const attempt = this.attemptsByTabId[tabId];
    if (attempt === undefined) {
      return;
    }
    if (!this.isHttpOrHttpsUrl(normalizedUrl)) {
      return;
    }
    if (attempt.phase !== 'upgrading' &&
      this.urlsMatch(normalizedUrl, attempt.failedUrl)) {
      return;
    }
    if (this.urlsMatch(normalizedUrl, attempt.upgradedUrl) || !this.urlsMatch(normalizedUrl, attempt.originalUrl)) {
      this.attemptsByTabId[tabId] = undefined;
    }
  }

  clearTab(tabId: string): void {
    this.attemptsByTabId[tabId] = undefined;
    this.clearDeclinedRetry(tabId);
    this.clearHttpSessionGrant(tabId);
  }

  clearPrivateSessionExceptions(profileId: BrowserProfileId): void {
    const prefix = `${normalizeBrowserProfileId(profileId)}|`;
    Object.keys(this.privateHttpFallbackExceptionsByKey).forEach((storageKey: string): void => {
      if (storageKey.startsWith(prefix)) {
        this.privateHttpFallbackExceptionsByKey[storageKey] = undefined;
      }
    });
    this.clearInMemorySiteDecisions(normalizeBrowserProfileId(profileId), 'session_ephemeral');
  }

  async clearSiteDecisions(boundaryInput: BrowserDataBoundaryInput): Promise<void> {
    const boundary = buildBrowserDataBoundary(boundaryInput);
    this.clearInMemorySiteDecisions(boundary.profileId, boundary.dataScope);
    if (boundary.dataScope === 'profile_persistent') {
      await this.settingsRepository.clearHttpsFirstSiteDecisions(boundary.profileId);
      return;
    }
    this.clearPrivateSessionExceptions(boundary.profileId);
  }

  private buildUpgradeUrl(url: string): string {
    const target = this.siteIdentityService.resolveSiteSettingTarget(url);
    if (target === undefined || target.scheme !== 'http' || this.isLoopbackHost(target.host)) {
      return '';
    }
    let remainder = url.substring('http://'.length);
    const authorityEnd = remainder.search(/[/?#]/);
    let authority = authorityEnd >= 0 ? remainder.substring(0, authorityEnd) : remainder;
    const suffix = authorityEnd >= 0 ? remainder.substring(authorityEnd) : '';
    if (authority.endsWith(':80')) {
      authority = authority.substring(0, authority.length - 3);
    }
    if (authority.length === 0) {
      return '';
    }
    return `https://${authority}${suffix}`;
  }

  private rememberHttpFallbackSite(attempt: BrowserHttpsFirstUpgradeAttempt, expiresAt: number): void {
    const siteKey = this.resolveHttpFallbackSiteKey(attempt.originalUrl);
    if (siteKey.length === 0) {
      return;
    }
    const dataPolicy = this.privacyEffectPolicy.resolveDataPolicyForBoundary(
      'http_fallback_exception',
      attempt.boundary
    );
    if (!dataPolicy.persistentWriteAllowed) {
      this.privateHttpFallbackExceptionsByKey[
        this.buildHttpFallbackExceptionStorageKey(attempt.boundary.profileId, siteKey)
      ] = true;
      return;
    }
    this.settingsRepository.rememberHttpFallbackSite(
      attempt.boundary.profileId,
      siteKey,
      expiresAt
    );
  }

  private isHttpFallbackSiteAllowed(url: string, boundaryInput: BrowserDataBoundaryInput): boolean {
    const siteKey = this.resolveHttpFallbackSiteKey(url);
    if (siteKey.length === 0) {
      return false;
    }
    const boundary = buildBrowserDataBoundary(boundaryInput);
    return this.isHttpFallbackSiteKeyAllowed(siteKey, boundary);
  }

  private isHttpFallbackSiteKeyAllowed(siteKey: string, boundary: BrowserDataBoundary): boolean {
    const storageKey = this.buildHttpFallbackExceptionStorageKey(boundary.profileId, siteKey);
    const dataPolicy = this.privacyEffectPolicy.resolveDataPolicyForBoundary('http_fallback_exception', boundary);
    if (!dataPolicy.persistentReadAllowed) {
      return this.privateHttpFallbackExceptionsByKey[storageKey] === true;
    }
    return this.settingsRepository.isHttpFallbackSiteAllowed(boundary.profileId, siteKey);
  }

  private buildHttpSessionGrant(
    url: string,
    boundary: BrowserDataBoundary,
    expiresAt: number = 0
  ): BrowserHttpsFirstHttpSessionGrant | undefined {
    const target = this.siteIdentityService.resolveSiteSettingTarget(url);
    if (target === undefined || target.scheme !== 'http') {
      return undefined;
    }
    return {
      anchorHost: this.resolveApprovedHttpSessionAnchorHost(target.host, target.effectivePort, boundary),
      effectivePort: target.effectivePort,
      boundary: boundary,
      expiresAt: expiresAt
    };
  }

  private resolveApprovedHttpSessionAnchorHost(
    host: string,
    effectivePort: number,
    boundary: BrowserDataBoundary
  ): string {
    const labels = host.split('.').filter((label: string): boolean => label.length > 0);
    let anchorHost = host;
    for (let index = 1; index <= labels.length - 2; index += 1) {
      const candidateHost = labels.slice(index).join('.');
      if (this.isHttpFallbackSiteKeyAllowed(`${candidateHost}|${effectivePort}`, boundary)) {
        anchorHost = candidateHost;
      }
    }
    return anchorHost;
  }

  private isHttpSessionGrantAllowed(
    grant: BrowserHttpsFirstHttpSessionGrant,
    url: string,
    boundary: BrowserDataBoundary
  ): boolean {
    const target = this.siteIdentityService.resolveSiteSettingTarget(url);
    return target !== undefined && target.scheme === 'http' && target.effectivePort === grant.effectivePort &&
      (grant.expiresAt <= 0 || grant.expiresAt > Date.now()) &&
      boundary.profileId === grant.boundary.profileId && boundary.privacyMode === grant.boundary.privacyMode &&
      boundary.dataScope === grant.boundary.dataScope &&
      (this.siteIdentityService.hostMatches(target.host, grant.anchorHost, true) ||
        this.isKnownHttpPresentationHostAlias(target.host, grant.anchorHost));
  }

  private isKnownHttpPresentationHostAlias(firstHost: string, secondHost: string): boolean {
    const firstAliasBase = this.resolveHttpPresentationHostAliasBase(firstHost);
    const secondAliasBase = this.resolveHttpPresentationHostAliasBase(secondHost);
    if (firstAliasBase.length === 0 && secondAliasBase.length === 0) {
      return false;
    }
    const normalizedFirstBase = firstAliasBase.length > 0 ? firstAliasBase : firstHost.trim().toLowerCase();
    const normalizedSecondBase = secondAliasBase.length > 0 ? secondAliasBase : secondHost.trim().toLowerCase();
    return normalizedFirstBase.length > 0 && normalizedFirstBase === normalizedSecondBase;
  }

  private resolveHttpPresentationHostAliasBase(host: string): string {
    const normalizedHost = host.trim().toLowerCase();
    const separatorIndex = normalizedHost.indexOf('.');
    if (separatorIndex <= 0 || separatorIndex >= normalizedHost.length - 1) {
      return '';
    }
    const alias = normalizedHost.substring(0, separatorIndex);
    if (HTTP_PRESENTATION_HOST_ALIASES.indexOf(alias) < 0) {
      return '';
    }
    return normalizedHost.substring(separatorIndex + 1);
  }

  private isServerDowngradeForCurrentAttempt(
    attempt: BrowserHttpsFirstUpgradeAttempt,
    targetUrl: string,
    boundary: BrowserDataBoundary
  ): boolean {
    const canAcceptDowngrade = attempt.phase === 'upgrading' ||
      attempt.phase === 'awaiting_secondary_failure_signal';
    return canAcceptDowngrade && attempt.fallbackExecutor !== undefined &&
      attempt.boundary.profileId === boundary.profileId &&
      attempt.boundary.privacyMode === boundary.privacyMode &&
      attempt.boundary.dataScope === boundary.dataScope &&
      this.urlsMatch(targetUrl, attempt.originalUrl) &&
      this.urlsMatch(this.buildUpgradeUrl(targetUrl), attempt.upgradedUrl);
  }

  private resolveHttpSessionGrant(
    tabId: string,
    boundary: BrowserDataBoundary,
    targetUrl: string
  ): BrowserHttpsFirstHttpSessionGrant | undefined {
    const inMemoryGrant = this.httpSessionGrantByTabId[tabId];
    if (inMemoryGrant !== undefined) {
      return inMemoryGrant;
    }
    if (boundary.privacyMode !== 'regular' || boundary.dataScope !== 'profile_persistent') {
      this.settingsRepository.clearHttpsFirstHttpSessionGrant(tabId);
      return undefined;
    }
    const persisted: BrowserHttpsFirstHttpSessionGrantRecord | undefined =
      this.settingsRepository.readHttpsFirstHttpSessionGrant(tabId);
    if (persisted === undefined || persisted.profileId !== boundary.profileId) {
      if (persisted !== undefined) {
        this.settingsRepository.clearHttpsFirstHttpSessionGrant(tabId);
      }
      return undefined;
    }
    const exceptionExpiresAt = this.settingsRepository.readHttpFallbackSiteExpiration(
      persisted.profileId,
      `${persisted.anchorHost}|${persisted.effectivePort}`
    );
    if (exceptionExpiresAt <= 0) {
      this.settingsRepository.clearHttpsFirstHttpSessionGrant(tabId);
      return undefined;
    }
    const grant: BrowserHttpsFirstHttpSessionGrant = {
      anchorHost: persisted.anchorHost,
      effectivePort: persisted.effectivePort,
      boundary: boundary,
      expiresAt: Math.min(persisted.expiresAt, exceptionExpiresAt)
    };
    if (!this.isHttpSessionGrantAllowed(grant, targetUrl, boundary)) {
      this.settingsRepository.clearHttpsFirstHttpSessionGrant(tabId);
      return undefined;
    }
    this.httpSessionGrantByTabId[tabId] = grant;
    return grant;
  }

  private replaceHttpSessionGrant(
    tabId: string,
    grant: BrowserHttpsFirstHttpSessionGrant | undefined
  ): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return;
    }
    if (grant === undefined) {
      this.clearHttpSessionGrant(normalizedTabId);
      return;
    }
    this.httpSessionGrantByTabId[normalizedTabId] = grant;
    const dataPolicy = this.privacyEffectPolicy.resolveDataPolicyForBoundary(
      'http_fallback_exception',
      grant.boundary
    );
    if (!dataPolicy.persistentWriteAllowed || grant.expiresAt <= Date.now()) {
      this.settingsRepository.clearHttpsFirstHttpSessionGrant(normalizedTabId);
      return;
    }
    this.settingsRepository.rememberHttpsFirstHttpSessionGrant(
      normalizedTabId,
      grant.boundary.profileId,
      grant.anchorHost,
      grant.effectivePort,
      grant.expiresAt
    );
  }

  private clearHttpSessionGrant(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return;
    }
    this.httpSessionGrantByTabId[normalizedTabId] = undefined;
    this.settingsRepository.clearHttpsFirstHttpSessionGrant(normalizedTabId);
  }

  private resolveHttpFallbackSiteExpiration(url: string, boundary: BrowserDataBoundary): number {
    const dataPolicy = this.privacyEffectPolicy.resolveDataPolicyForBoundary('http_fallback_exception', boundary);
    if (!dataPolicy.persistentReadAllowed) {
      return 0;
    }
    const target = this.siteIdentityService.resolveSiteSettingTarget(url);
    if (target === undefined || target.scheme !== 'http') {
      return 0;
    }
    const anchorHost = this.resolveApprovedHttpSessionAnchorHost(target.host, target.effectivePort, boundary);
    return this.settingsRepository.readHttpFallbackSiteExpiration(
      boundary.profileId,
      `${anchorHost}|${target.effectivePort}`
    );
  }

  private clearInMemorySiteDecisions(profileId: BrowserProfileId, dataScope: string): void {
    Object.keys(this.attemptsByTabId).forEach((tabId: string): void => {
      const attempt = this.attemptsByTabId[tabId];
      if (attempt !== undefined && attempt.boundary.profileId === profileId && attempt.boundary.dataScope === dataScope) {
        this.attemptsByTabId[tabId] = undefined;
      }
    });
    Object.keys(this.declinedRetryByTabId).forEach((tabId: string): void => {
      const retry = this.declinedRetryByTabId[tabId];
      if (retry !== undefined && retry.boundary.profileId === profileId && retry.boundary.dataScope === dataScope) {
        this.declinedRetryByTabId[tabId] = undefined;
      }
    });
    Object.keys(this.httpSessionGrantByTabId).forEach((tabId: string): void => {
      const grant = this.httpSessionGrantByTabId[tabId];
      if (grant !== undefined && grant.boundary.profileId === profileId && grant.boundary.dataScope === dataScope) {
        this.clearHttpSessionGrant(tabId);
      }
    });
  }

  private resolveHttpFallbackSiteKey(url: string): string {
    const target = this.siteIdentityService.resolveSiteSettingTarget(url);
    if (target === undefined || target.scheme !== 'http') {
      return '';
    }
    return `${target.host}|${target.effectivePort}`;
  }

  private buildHttpFallbackExceptionStorageKey(profileId: BrowserProfileId, siteKey: string): string {
    return `${normalizeBrowserProfileId(profileId)}|${siteKey}`;
  }

  private isLoopbackHost(host: string): boolean {
    const normalized = host.trim().toLowerCase();
    return normalized === 'localhost' || normalized === '127.0.0.1' || normalized === '::1' ||
      normalized.endsWith('.localhost');
  }

  private isHttpOrHttpsUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private resolveDeclinedRetry(tabId: string): BrowserHttpsFirstDeclinedRetry | undefined {
    const inMemoryRetry = this.declinedRetryByTabId[tabId];
    if (inMemoryRetry !== undefined) {
      return inMemoryRetry;
    }
    const persisted = this.settingsRepository.readHttpsFirstDeclinedRetry(tabId);
    if (persisted === undefined) {
      return undefined;
    }
    const source = this.resolveUpgradeSource(persisted);
    if (source === undefined || !this.urlsMatch(this.buildUpgradeUrl(persisted.originalUrl), persisted.upgradedUrl)) {
      this.settingsRepository.clearHttpsFirstDeclinedRetry(tabId);
      return undefined;
    }
    const retry: BrowserHttpsFirstDeclinedRetry = {
      originalUrl: persisted.originalUrl,
      upgradedUrl: persisted.upgradedUrl,
      boundary: buildBrowserDataBoundary({
        profileId: persisted.profileId,
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      }),
      source: source
    };
    this.declinedRetryByTabId[tabId] = retry;
    return retry;
  }

  private resolveUpgradeSource(
    persisted: BrowserHttpsFirstDeclinedRetryRecord
  ): BrowserHttpsFirstUpgradeSource | undefined {
    if (persisted.source === 'browser_generated' || persisted.source === 'intercepted_http') {
      return persisted.source;
    }
    return undefined;
  }

  private clearDeclinedRetry(tabId: string): void {
    this.declinedRetryByTabId[tabId] = undefined;
    this.settingsRepository.clearHttpsFirstDeclinedRetry(tabId);
  }

  private isGetRequest(request: WebResourceRequest): boolean {
    try {
      return request.getRequestMethod().trim().toUpperCase() === 'GET';
    } catch (_error) {
      return false;
    }
  }

  private resolveFailureDecision(
    tabId: string,
    requestUrl: string,
    isMainFrame: boolean,
    eligible: boolean,
    navigationId: number,
    reason: string
  ): BrowserHttpsFirstFailureDecision {
    const attempt = this.attemptsByTabId[tabId];
    if (attempt === undefined || !isMainFrame || !this.urlsMatch(requestUrl, attempt.upgradedUrl) ||
      attempt.fallbackExecutor === undefined || navigationId <= 0 || attempt.navigationId !== navigationId) {
      return this.buildNormalFailureDecision(requestUrl, reason);
    }
    if (!eligible) {
      if (attempt.phase === 'upgrading') {
        attempt.phase = 'awaiting_secondary_failure_signal';
        attempt.failedUrl = requestUrl.trim();
      }
      return this.buildNormalFailureDecision(requestUrl, reason);
    }
    const action: BrowserHttpsFirstFailureAction = attempt.strictMode
      ? 'require_http_confirmation'
      : 'automatic_http_fallback';
    const delivery: BrowserHttpsFirstFailureDelivery =
      attempt.phase === 'upgrading' || attempt.phase === 'awaiting_secondary_failure_signal'
      ? 'apply'
      : 'suppress_duplicate';
    if (delivery === 'apply') {
      attempt.phase = action === 'require_http_confirmation'
        ? 'awaiting_http_confirmation'
        : 'automatic_http_fallback_pending';
      attempt.failedUrl = requestUrl.trim();
    }
    hilog.info(
      HTTPS_FIRST_LOG_DOMAIN,
      HTTPS_FIRST_LOG_TAG,
      'failure decision tab=%{public}s attempt=%{public}d action=%{public}s delivery=%{public}s reason=%{public}s',
      tabId,
      attempt.attemptId,
      action,
      delivery,
      reason
    );
    return {
      action: action,
      delivery: delivery,
      attemptId: attempt.attemptId,
      failedUrl: attempt.failedUrl.length > 0 ? attempt.failedUrl : requestUrl.trim(),
      fallbackUrl: attempt.originalUrl,
      reason: reason
    };
  }

  private buildNormalFailureDecision(requestUrl: string, reason: string): BrowserHttpsFirstFailureDecision {
    return {
      action: 'normal_failure',
      delivery: 'apply',
      attemptId: 0,
      failedUrl: requestUrl.trim(),
      fallbackUrl: '',
      reason: reason
    };
  }

  private urlsMatch(left: string, right: string): boolean {
    const normalizedLeft = this.normalizeUrlIdentity(left);
    const normalizedRight = this.normalizeUrlIdentity(right);
    return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
  }

  private normalizeUrlIdentity(url: string): string {
    const trimmed = url.trim();
    const target = this.siteIdentityService.resolveSiteSettingTarget(trimmed);
    if (target === undefined) {
      return trimmed;
    }
    const schemeEnd = trimmed.indexOf('://');
    if (schemeEnd < 0) {
      return trimmed;
    }
    const remainder = trimmed.substring(schemeEnd + 3);
    const suffixStart = remainder.search(/[/?#]/);
    let suffix = suffixStart >= 0 ? remainder.substring(suffixStart) : '/';
    const fragmentStart = suffix.indexOf('#');
    if (fragmentStart >= 0) {
      suffix = suffix.substring(0, fragmentStart);
    }
    if (suffix.length === 0 || suffix.startsWith('?')) {
      suffix = `/${suffix}`;
    }
    return `${target.canonicalOrigin}${suffix}`;
  }

  private allocateAttemptId(): number {
    const attemptId = this.nextAttemptId;
    this.nextAttemptId += 1;
    return attemptId;
  }

  private logAttempt(action: string, attempt: BrowserHttpsFirstUpgradeAttempt, tabId: string): void {
    hilog.info(
      HTTPS_FIRST_LOG_DOMAIN,
      HTTPS_FIRST_LOG_TAG,
      'attempt %{public}s tab=%{public}s attempt=%{public}d strict=%{public}s source=%{public}s',
      action,
      tabId,
      attempt.attemptId,
      attempt.strictMode ? '1' : '0',
      attempt.source
    );
  }

}

export const sharedBrowserHttpsFirstNavigationService: BrowserHttpsFirstNavigationService =
  new BrowserHttpsFirstNavigationService(sharedBrowserWebSecuritySettingsRepository);
