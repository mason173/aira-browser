import { webview } from '@kit.ArkWeb';
import { BrowserFingerprintPrivacyPolicyService } from '../privacy/BrowserFingerprintPrivacyPolicyService';
import { BrowserPrivacyRuntimeAdapter } from '../privacy/BrowserPrivacyRuntimeAdapter';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  BrowserCookiePolicySettings,
  DEFAULT_BROWSER_PROFILE_ID,
  SitePermissionRule,
  SitePermissionSettings,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode,
  resolveBrowserDataScopeForPrivacyMode
} from '../../common/models/BrowserModels';
import {
  PrivateModeCookieSnapshotRecord,
  PrivateModeCookieSnapshotRepository
} from '../../data/browser/PrivateModeCookieSnapshotRepository';
import { RegularSessionCookieSnapshotRepository } from '../../data/browser/RegularSessionCookieSnapshotRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { sharedBrowserSslDecisionCacheRuntime } from './BrowserSslDecisionCacheRuntime';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';

export interface CurrentSiteDataSummary {
  cookieCount: number;
  storageUsageBytes: number;
  storageOrigin: string;
}

export interface SiteDataPolicySnapshot {
  acceptCookies: boolean;
  acceptThirdPartyCookies: boolean;
  savedPermissionCount: number;
}

export interface SiteDataBoundarySnapshot extends SiteDataPolicySnapshot {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  sessionPermissionCount: number;
  fullDataClearRequiresBrowserRuntime: boolean;
}

export interface SiteDataPolicySummary {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  summaryLine: string;
  permissionSummaryLine: string;
  canExposeProfilePermissionRules: boolean;
}

export interface SitePermissionBoundarySummary {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  allowCount: number;
  blockCount: number;
  summaryLine: string;
}

export interface SiteDataClearResult {
  hasError: boolean;
  message: string;
  failureMessages?: string[];
}

export class ArkWebIncognitoRuntimeClearOptions {
  preserveCookieSnapshot: boolean;

  constructor(preserveCookieSnapshot: boolean = false) {
    this.preserveCookieSnapshot = preserveCookieSnapshot;
  }
}

export interface SiteDataClearDialogState {
  title: ResourceStr;
  message: ResourceStr;
  confirmLabel: ResourceStr;
}

export interface SiteDataClearCurrentPlan {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  storageOrigin: string;
  clearOriginStorage: boolean;
  summaryLine: string;
}

export interface SiteDataClearOnClosePlan {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  storageOrigin: string;
  clearOriginStorage: boolean;
  clearCookiesSupported: boolean;
  summaryLine: string;
}

export interface SiteDataClearAllPlan {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  clearWebStorage: boolean;
  clearCookies: boolean;
  clearCache: boolean;
  clearProfilePermissions: boolean;
  clearSessionPermissions: boolean;
  summaryLine: string;
}

export interface SiteDataClearSelection {
  clearWebStorage: boolean;
  clearCookies: boolean;
  clearCache: boolean;
  clearProfilePermissions: boolean;
}

interface SiteDataErasureContext {
  dataScope: BrowserDataScope;
  isSessionEphemeral: boolean;
}

export interface BrowserCookiePolicyApplyResult {
  acceptCookies: boolean;
  acceptThirdPartyCookies: boolean;
}

export interface PrivateModeCookiePreservationResult {
  hasError: boolean;
  savedCookieCount: number;
  restoredCookieCount: number;
  failedCookieCount: number;
  message: string;
}

class PrivateModeCookiePreservationResultRecord implements PrivateModeCookiePreservationResult {
  hasError: boolean;
  savedCookieCount: number;
  restoredCookieCount: number;
  failedCookieCount: number;
  message: string;

  constructor(
    hasError: boolean,
    savedCookieCount: number,
    restoredCookieCount: number,
    failedCookieCount: number,
    message: string
  ) {
    this.hasError = hasError;
    this.savedCookieCount = savedCookieCount;
    this.restoredCookieCount = restoredCookieCount;
    this.failedCookieCount = failedCookieCount;
    this.message = message;
  }
}

export class SiteDataControlService {
  private privacyRuntimeAdapter: BrowserPrivacyRuntimeAdapter = new BrowserPrivacyRuntimeAdapter();
  private preferencesRepository: PreferencesRepository;
  private privateCookieSnapshotRepository?: PrivateModeCookieSnapshotRepository;
  private regularSessionCookieSnapshotRepository?: RegularSessionCookieSnapshotRepository;

  constructor(
    preferencesRepository: PreferencesRepository,
    privateCookieSnapshotRepository?: PrivateModeCookieSnapshotRepository,
    regularSessionCookieSnapshotRepository?: RegularSessionCookieSnapshotRepository
  ) {
    this.preferencesRepository = preferencesRepository;
    this.privateCookieSnapshotRepository = privateCookieSnapshotRepository;
    this.regularSessionCookieSnapshotRepository = regularSessionCookieSnapshotRepository;
  }

  async loadCurrentSiteData(
    url: string,
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): Promise<CurrentSiteDataSummary> {
    const normalizedUrl = url.trim();
    const normalizedOrigin = this.normalizeOrigin(origin);
    const normalizedDataScope = normalizeBrowserDataScope(dataScope, normalizeBrowserSessionPrivacyMode(privacyMode));
    if (normalizedUrl.length === 0 || normalizedOrigin.length === 0 || normalizedDataScope === 'session_ephemeral') {
      return this.buildEmptyCurrentSiteDataSummary();
    }

    const origins = await webview.WebStorage.getOrigins();
    const matchedOrigin = origins.find((item: webview.WebStorageOrigin) => {
      return this.normalizeOrigin(item.origin) === normalizedOrigin;
    });
    return {
      cookieCount: this.readCookieCount(normalizedUrl),
      storageUsageBytes: matchedOrigin?.usage ?? 0,
      storageOrigin: matchedOrigin?.origin ?? ''
    };
  }

  buildEmptyCurrentSiteDataSummary(): CurrentSiteDataSummary {
    return {
      cookieCount: 0,
      storageUsageBytes: 0,
      storageOrigin: ''
    };
  }

  getBoundarySnapshot(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope,
    sessionPermissionCount: number = 0
  ): SiteDataBoundarySnapshot {
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(privacyMode);
    const normalizedDataScope = normalizeBrowserDataScope(dataScope, normalizedPrivacyMode);
    return {
      acceptCookies: this.readCookieAcceptance(),
      acceptThirdPartyCookies: this.readThirdPartyCookieAcceptance(),
      savedPermissionCount: normalizedDataScope === 'session_ephemeral'
        ? 0
        : this.preferencesRepository.listSitePermissionSettings(normalizedProfileId).length,
      profileId: normalizedProfileId,
      privacyMode: normalizedPrivacyMode,
      dataScope: normalizedDataScope,
      sessionPermissionCount: normalizedDataScope === 'session_ephemeral' ? Math.max(0, sessionPermissionCount) : 0,
      fullDataClearRequiresBrowserRuntime: true
    };
  }

  buildPolicySummary(snapshot: SiteDataBoundarySnapshot): SiteDataPolicySummary {
    const cookieLabel = snapshot.acceptCookies
      ? resolveAppResourceText($r('app.string.site_data_cookies_allowed'))
      : resolveAppResourceText($r('app.string.site_data_cookies_blocked'));
    const thirdPartyLabel = snapshot.acceptThirdPartyCookies
      ? resolveAppResourceText($r('app.string.site_data_third_party_allowed'))
      : resolveAppResourceText($r('app.string.site_data_third_party_blocked'));
    const profileLabel = snapshot.profileId === DEFAULT_BROWSER_PROFILE_ID
      ? resolveAppResourceText($r('app.string.site_data_profile_regular'))
      : resolveAppResourceText($r('app.string.site_data_profile_named', snapshot.profileId));
    const privacyLabel = snapshot.privacyMode === 'private'
      ? resolveAppResourceText($r('app.string.site_data_session_private'))
      : resolveAppResourceText($r('app.string.site_data_session_regular'));
    if (snapshot.dataScope === 'session_ephemeral') {
      return {
        profileId: snapshot.profileId,
        privacyMode: snapshot.privacyMode,
        dataScope: snapshot.dataScope,
        summaryLine: resolveAppResourceText($r(
          'app.string.site_data_summary_private',
          profileLabel,
          cookieLabel,
          thirdPartyLabel,
          privacyLabel
        )),
        permissionSummaryLine: resolveAppResourceText($r(
          'app.string.site_data_permissions_private',
          snapshot.sessionPermissionCount
        )),
        canExposeProfilePermissionRules: false
      };
    }
    return {
      profileId: snapshot.profileId,
      privacyMode: snapshot.privacyMode,
      dataScope: snapshot.dataScope,
      summaryLine: resolveAppResourceText($r(
        'app.string.site_data_summary_regular',
        profileLabel,
        cookieLabel,
        thirdPartyLabel,
        privacyLabel
      )),
      permissionSummaryLine: resolveAppResourceText($r(
        'app.string.site_data_permissions_saved',
        snapshot.savedPermissionCount
      )),
      canExposeProfilePermissionRules: true
    };
  }

  buildPolicySummaryForBoundary(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope,
    sessionPermissionCount: number = 0
  ): SiteDataPolicySummary {
    return this.buildPolicySummary(
      this.getBoundarySnapshot(profileId, privacyMode, dataScope, sessionPermissionCount)
    );
  }

  buildPermissionSummaryForBoundary(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope,
    permissionRules: SitePermissionSettings[] = [],
    sessionPermissionCount: number = 0
  ): SitePermissionBoundarySummary {
    const summary = this.buildPolicySummaryForBoundary(profileId, privacyMode, dataScope, sessionPermissionCount);
    if (summary.dataScope === 'session_ephemeral') {
      return {
        profileId: summary.profileId,
        privacyMode: summary.privacyMode,
        dataScope: summary.dataScope,
        allowCount: 0,
        blockCount: 0,
        summaryLine: summary.permissionSummaryLine
      };
    }
    let allowCount = 0;
    let blockCount = 0;
    permissionRules.forEach((settings: SitePermissionSettings) => {
      [settings.camera, settings.microphone, settings.location, settings.sensor, settings.clipboard]
        .forEach((rule: SitePermissionRule) => {
        if (rule === 'allow') {
          allowCount += 1;
        } else if (rule === 'block') {
          blockCount += 1;
        }
      });
    });
    return {
      profileId: summary.profileId,
      privacyMode: summary.privacyMode,
      dataScope: summary.dataScope,
      allowCount: allowCount,
      blockCount: blockCount,
      summaryLine: resolveAppResourceText($r(
        'app.string.site_data_permission_counts',
        summary.permissionSummaryLine,
        allowCount,
        blockCount
      ))
    };
  }

  async setCookiePolicyEnabledState(
    acceptCookies: boolean,
    acceptThirdPartyCookies: boolean
  ): Promise<void> {
    webview.WebCookieManager.putAcceptCookieEnabled(acceptCookies);
    webview.WebCookieManager.saveCookieSync();
    await this.preferencesRepository.updateCookiePolicySettings({
      acceptCookies: acceptCookies,
      acceptThirdPartyCookies: acceptThirdPartyCookies
    });
    this.applyBrowserCompatibleCookiePolicy();
  }

  applyBrowserCompatibleCookiePolicy(settings?: BrowserCookiePolicySettings): BrowserCookiePolicyApplyResult {
    const policy = settings ?? this.preferencesRepository.getPreferences().cookiePolicy;
    const runtimeApplied = this.privacyRuntimeAdapter.applyCookiePolicy(
      policy.acceptCookies,
      BrowserFingerprintPrivacyPolicyService.resolveEffectiveThirdPartyCookiesAllowed(
        policy.acceptThirdPartyCookies
      )
    );
    BrowserFingerprintPrivacyPolicyService.reportCookiePolicyRuntimeApplied(runtimeApplied);
    return {
      acceptCookies: this.readCookieAcceptance(),
      acceptThirdPartyCookies: this.readThirdPartyCookieAcceptance()
    };
  }

  /**
   * ArkWeb keeps newly accepted cookies in memory and writes them about every 30 seconds.
   * Force-stopping after background does not run onDestroy, so callers on the way to process
   * death must flush here. Session cookies on PC, 2-in-1, and tablet are still not persisted
   * by the engine; those are copied separately before the process can die.
   */
  persistMemoryCookies(): boolean {
    try {
      webview.WebCookieManager.saveCookieSync();
      return true;
    } catch (_error) {
      return false;
    }
  }

  /**
   * Copy regular-profile session cookies before the process can die. The engine
   * drops them on the next start, which signs sites such as GitHub out overnight.
   */
  async preserveRegularSessionCookies(): Promise<number> {
    const repository = this.regularSessionCookieSnapshotRepository;
    if (repository === undefined) {
      return 0;
    }
    const now = Date.now();
    const cookies = await webview.WebCookieManager.fetchAllCookies(false);
    const sessionCookies: PrivateModeCookieSnapshotRecord[] = [];
    cookies.forEach((cookie: webview.WebHttpCookie) => {
      const record = this.toPrivateCookieSnapshotRecord(cookie, now);
      if (record !== undefined && record.isSessionCookie) {
        sessionCookies.push(record);
      }
    });
    await repository.saveSnapshot(sessionCookies);
    return sessionCookies.length;
  }

  /**
   * Put the saved session cookies back before the first page loads. A cookie the
   * engine already kept is left alone, so a second launch cannot duplicate it.
   */
  async restoreRegularSessionCookies(): Promise<number> {
    const repository = this.regularSessionCookieSnapshotRepository;
    if (repository === undefined) {
      return 0;
    }
    const snapshot = await repository.readSnapshot();
    if (snapshot.cookies.length <= 0) {
      return 0;
    }
    const liveCookies = await webview.WebCookieManager.fetchAllCookies(false);
    let restoredCookieCount = 0;
    snapshot.cookies.forEach((cookie: PrivateModeCookieSnapshotRecord) => {
      if (this.regularSessionCookieAlreadyPresent(liveCookies, cookie)) {
        return;
      }
      const url = this.buildCookieUrl(cookie);
      const value = this.buildSetCookieValue(cookie);
      webview.WebCookieManager.configCookieSync(url, value, false, cookie.isHttpOnly);
      restoredCookieCount += 1;
    });
    if (restoredCookieCount > 0) {
      webview.WebCookieManager.saveCookieSync();
    }
    return restoredCookieCount;
  }

  private regularSessionCookieAlreadyPresent(
    liveCookies: webview.WebHttpCookie[],
    cookie: PrivateModeCookieSnapshotRecord
  ): boolean {
    return liveCookies.some((live: webview.WebHttpCookie): boolean => {
      return live.name === cookie.name &&
        live.domain === cookie.domain &&
        (live.path.trim().length > 0 ? live.path.trim() : '/') === cookie.path;
    });
  }

  buildClearCurrentSiteDataDialogState(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): SiteDataClearDialogState {
    const plan = this.buildClearCurrentSiteDataPlan('', profileId, privacyMode, dataScope);
    if (plan.dataScope === 'session_ephemeral') {
      return {
        title: $r('app.string.settings_site_info_clear_dialog_private_title'),
        message: $r('app.string.settings_site_info_clear_dialog_private_message'),
        confirmLabel: $r('app.string.settings_site_info_clear_dialog_private_confirm')
      };
    }
    return {
      title: $r('app.string.settings_site_info_clear_dialog_title'),
      message: $r('app.string.settings_site_info_clear_dialog_message'),
      confirmLabel: $r('app.string.settings_site_info_clear_dialog_confirm')
    };
  }

  async restorePreservedPrivateModeCookies(): Promise<PrivateModeCookiePreservationResult> {
    const repository = this.privateCookieSnapshotRepository;
    if (repository === undefined) {
      return new PrivateModeCookiePreservationResultRecord(false, 0, 0, 0, resolveAppResourceText($r('app.string.site_data_cookie_snapshot_off')));
    }
    try {
      const snapshot = await repository.readSnapshot();
      if (snapshot.cookies.length <= 0) {
        return new PrivateModeCookiePreservationResultRecord(false, 0, 0, 0, resolveAppResourceText($r('app.string.site_data_cookie_nothing_to_restore')));
      }
      let restoredCookieCount = 0;
      let failedCookieCount = 0;
      snapshot.cookies.forEach((cookie: PrivateModeCookieSnapshotRecord) => {
        try {
          const url = this.buildCookieUrl(cookie);
          const value = this.buildSetCookieValue(cookie);
          webview.WebCookieManager.configCookieSync(url, value, true, cookie.isHttpOnly);
          restoredCookieCount += 1;
        } catch (_error) {
          failedCookieCount += 1;
        }
      });
      webview.WebCookieManager.saveCookieSync();
      return new PrivateModeCookiePreservationResultRecord(
        failedCookieCount > 0,
        snapshot.cookies.length,
        restoredCookieCount,
        failedCookieCount,
        resolveAppResourceText($r('app.string.site_data_cookie_restored', restoredCookieCount, failedCookieCount))
      );
    } catch (error) {
      return new PrivateModeCookiePreservationResultRecord(
        true,
        0,
        0,
        0,
        resolveAppResourceText($r('app.string.site_data_cookie_restore_failed', JSON.stringify(error)))
      );
    }
  }

  async savePreservedPrivateModeCookies(): Promise<PrivateModeCookiePreservationResult> {
    try {
      const savedCookieCount = await this.savePrivateCookieSnapshot();
      return new PrivateModeCookiePreservationResultRecord(
        false,
        savedCookieCount,
        0,
        0,
        resolveAppResourceText($r('app.string.site_data_cookie_saved', savedCookieCount))
      );
    } catch (error) {
      return new PrivateModeCookiePreservationResultRecord(
        true,
        0,
        0,
        0,
        resolveAppResourceText($r('app.string.site_data_cookie_save_failed', JSON.stringify(error)))
      );
    }
  }

  async clearPrivateSessionData(preserveCookiesOnClose: boolean = false): Promise<SiteDataClearResult> {
    const options: ArkWebIncognitoRuntimeClearOptions =
      new ArkWebIncognitoRuntimeClearOptions(preserveCookiesOnClose);
    return this.clearArkWebIncognitoRuntimeData(options);
  }

  async clearArkWebIncognitoRuntimeData(options: ArkWebIncognitoRuntimeClearOptions): Promise<SiteDataClearResult> {
    try {
      let savedCookieCount = 0;
      if (options.preserveCookieSnapshot) {
        savedCookieCount = await this.savePrivateCookieSnapshot();
      } else {
        await this.privateCookieSnapshotRepository?.clearSnapshot();
      }
      webview.WebCookieManager.clearAllCookiesSync(true);
      webview.WebStorage.deleteAllData(true);
      webview.GeolocationPermissions.deleteAllGeolocation(true);
      webview.WebCookieManager.saveCookieSync();
      return {
        hasError: false,
        message: options.preserveCookieSnapshot
          ? resolveAppResourceText($r('app.string.site_data_private_cleared_kept', savedCookieCount))
          : resolveAppResourceText($r('app.string.site_data_private_cleared'))
      };
    } catch (error) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.site_data_private_clear_failed', JSON.stringify(error)))
      };
    }
  }

  clearCurrentSiteData(
    storageOrigin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): SiteDataClearResult {
    const context = this.resolveErasureContext(privacyMode, dataScope);
    if (context === undefined) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.settings_site_info_erasure_scope_mismatch'))
      };
    }
    const plan = this.buildClearCurrentSiteDataPlan(
      storageOrigin,
      profileId,
      privacyMode,
      dataScope
    );
    if (!plan.clearOriginStorage || context.isSessionEphemeral) {
      return {
        hasError: true,
        message: plan.dataScope === 'session_ephemeral'
          ? resolveAppResourceText($r('app.string.settings_site_info_private_clear_unsupported'))
          : resolveAppResourceText($r('app.string.settings_site_info_no_clearable_storage'))
      };
    }
    try {
      webview.WebStorage.deleteOrigin(plan.storageOrigin);
    } catch (error) {
      return {
        hasError: true,
        message: resolveAppResourceText(
          $r('app.string.settings_site_info_clear_failed_detail'),
          JSON.stringify(error)
        )
      };
    }
    return {
      hasError: false,
      message: resolveAppResourceText($r('app.string.settings_site_info_cleared'))
    };
  }

  clearSiteDataOnClose(
    origin: string,
    _url: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): SiteDataClearResult {
    const context = this.resolveErasureContext(privacyMode, dataScope);
    if (context === undefined) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.settings_site_info_erasure_scope_mismatch'))
      };
    }
    const normalizedOrigin = this.normalizeOrigin(origin);
    if (normalizedOrigin.length === 0) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.site_data_origin_unavailable'))
      };
    }
    const plan = this.buildSiteDataClearOnClosePlan(
      normalizedOrigin,
      profileId,
      privacyMode,
      dataScope
    );
    if (!plan.clearOriginStorage || context.isSessionEphemeral) {
      return {
        hasError: false,
        message: plan.dataScope === 'session_ephemeral'
          ? resolveAppResourceText($r('app.string.site_data_private_not_per_site'))
          : resolveAppResourceText($r('app.string.settings_site_info_no_clearable_storage'))
      };
    }
    try {
      webview.WebStorage.deleteOrigin(plan.storageOrigin);
    } catch (error) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.site_data_storage_clear_failed', JSON.stringify(error)))
      };
    }
    return {
      hasError: false,
      message: resolveAppResourceText($r('app.string.site_data_storage_cleared_kept'))
    };
  }

  async clearAllSiteData(
    controllerAttached: boolean,
    controller?: webview.WebviewController,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): Promise<SiteDataClearResult> {
    const context = this.resolveErasureContext(privacyMode, dataScope);
    if (context === undefined) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.settings_site_info_erasure_scope_mismatch'))
      };
    }
    const plan = this.buildClearAllSiteDataPlan(profileId, privacyMode, dataScope);
    const isSessionEphemeral = context.isSessionEphemeral;
    const failureMessages: string[] = [];

    if (plan.clearWebStorage) {
      try {
        webview.WebStorage.deleteAllData(isSessionEphemeral);
      } catch (error) {
        failureMessages.push(resolveAppResourceText($r('app.string.site_data_failure_storage', JSON.stringify(error))));
      }
    }

    if (plan.clearCookies) {
      try {
        this.clearAllCookiesForContext(isSessionEphemeral);
      } catch (error) {
        failureMessages.push(resolveAppResourceText($r('app.string.site_data_failure_cookies', JSON.stringify(error))));
      }
    }

    if (plan.clearCache) {
      try {
        this.clearCache(controllerAttached, controller);
      } catch (error) {
        failureMessages.push(resolveAppResourceText($r('app.string.site_data_failure_cache', JSON.stringify(error))));
      }
    }

    if (plan.clearProfilePermissions) {
      try {
        await this.preferencesRepository.clearAllSitePermissionSettings(plan.profileId);
        webview.GeolocationPermissions.deleteAllGeolocation(false);
        sharedBrowserSslDecisionCacheRuntime.requestClear();
      } catch (error) {
        failureMessages.push(resolveAppResourceText($r('app.string.site_data_failure_permissions', JSON.stringify(error))));
      }
    }

    if (failureMessages.length > 0) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.site_data_partial_clear_failed', failureMessages.join(resolveAppResourceText($r('app.string.site_data_detail_separator'))))),
        failureMessages: failureMessages.slice()
      };
    }
    return {
      hasError: false,
      message: isSessionEphemeral
        ? resolveAppResourceText($r('app.string.site_data_private_all_cleared'))
        : resolveAppResourceText($r('app.string.site_data_all_cleared'))
    };
  }

  async clearSelectedSiteData(
    selection: SiteDataClearSelection,
    controllerAttached: boolean,
    controller?: webview.WebviewController,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): Promise<SiteDataClearResult> {
    const context = this.resolveErasureContext(privacyMode, dataScope);
    if (context === undefined) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.settings_site_info_erasure_scope_mismatch'))
      };
    }
    const failureMessages: string[] = [];
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    const normalizedDataScope = context.dataScope;
    const isSessionEphemeral = context.isSessionEphemeral;

    if (selection.clearWebStorage) {
      try {
        webview.WebStorage.deleteAllData(isSessionEphemeral);
      } catch (error) {
        failureMessages.push(resolveAppResourceText($r('app.string.site_data_failure_storage', JSON.stringify(error))));
      }
    }

    if (selection.clearCookies) {
      try {
        this.clearAllCookiesForContext(isSessionEphemeral);
      } catch (error) {
        failureMessages.push(resolveAppResourceText($r('app.string.site_data_failure_cookies', JSON.stringify(error))));
      }
    }

    if (!isSessionEphemeral && selection.clearCache) {
      try {
        this.clearCache(controllerAttached, controller);
      } catch (error) {
        failureMessages.push(resolveAppResourceText($r('app.string.site_data_failure_cache', JSON.stringify(error))));
      }
    }

    if (!isSessionEphemeral && selection.clearProfilePermissions) {
      try {
        await this.preferencesRepository.clearAllSitePermissionSettings(normalizedProfileId);
        webview.GeolocationPermissions.deleteAllGeolocation(false);
        sharedBrowserSslDecisionCacheRuntime.requestClear();
      } catch (error) {
        failureMessages.push(resolveAppResourceText($r('app.string.site_data_failure_permissions', JSON.stringify(error))));
      }
    }

    if (failureMessages.length > 0) {
      return {
        hasError: true,
        message: resolveAppResourceText($r('app.string.site_data_partial_clear_failed', failureMessages.join(resolveAppResourceText($r('app.string.site_data_detail_separator'))))),
        failureMessages: failureMessages.slice()
      };
    }
    return {
      hasError: false,
      message: resolveAppResourceText($r('app.string.site_data_selected_cleared'))
    };
  }

  buildClearAllSiteDataPlan(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): SiteDataClearAllPlan {
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(privacyMode);
    const normalizedDataScope = normalizeBrowserDataScope(dataScope, normalizedPrivacyMode);
    const context = this.resolveErasureContext(privacyMode, dataScope);
    if (context === undefined) {
      return {
        profileId: normalizedProfileId,
        privacyMode: normalizedPrivacyMode,
        dataScope: normalizedDataScope,
        clearWebStorage: false,
        clearCookies: false,
        clearCache: false,
        clearProfilePermissions: false,
        clearSessionPermissions: false,
        summaryLine: `siteDataClearAllPlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} capability=invalid-context`
      };
    }
    if (normalizedDataScope === 'session_ephemeral') {
      return {
        profileId: normalizedProfileId,
        privacyMode: normalizedPrivacyMode,
        dataScope: normalizedDataScope,
        clearWebStorage: true,
        clearCookies: true,
        clearCache: false,
        clearProfilePermissions: false,
        clearSessionPermissions: true,
      summaryLine: `siteDataClearAllPlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} webStorage=true cookies=true cookieContext=incognito cache=false profilePermissions=false sessionPermissions=true`
      };
    }
    return {
      profileId: normalizedProfileId,
      privacyMode: normalizedPrivacyMode,
      dataScope: normalizedDataScope,
      clearWebStorage: true,
      clearCookies: true,
      clearCache: true,
      clearProfilePermissions: true,
      clearSessionPermissions: false,
      summaryLine: `siteDataClearAllPlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} webStorage=true cookies=true cookieContext=regular cache=true profilePermissions=true sessionPermissions=false`
    };
  }

  buildClearCurrentSiteDataPlan(
    storageOrigin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): SiteDataClearCurrentPlan {
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(privacyMode);
    const normalizedDataScope = normalizeBrowserDataScope(dataScope, normalizedPrivacyMode);
    const normalizedStorageOrigin = storageOrigin.trim();
    const context = this.resolveErasureContext(privacyMode, dataScope);
    if (context === undefined) {
      return {
        profileId: normalizedProfileId,
        privacyMode: normalizedPrivacyMode,
        dataScope: normalizedDataScope,
        storageOrigin: normalizedStorageOrigin,
        clearOriginStorage: false,
        summaryLine: `siteDataClearCurrentPlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} storageOrigin=${normalizedStorageOrigin} capability=invalid-context`
      };
    }
    if (normalizedDataScope === 'session_ephemeral') {
      return {
        profileId: normalizedProfileId,
        privacyMode: normalizedPrivacyMode,
        dataScope: normalizedDataScope,
        storageOrigin: normalizedStorageOrigin,
        clearOriginStorage: false,
        summaryLine: `siteDataClearCurrentPlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} storageOrigin=${normalizedStorageOrigin} originStorage=false cookies=false cache=false capability=private-origin-unavailable`
      };
    }
    return {
      profileId: normalizedProfileId,
      privacyMode: normalizedPrivacyMode,
      dataScope: normalizedDataScope,
      storageOrigin: normalizedStorageOrigin,
      clearOriginStorage: normalizedStorageOrigin.length > 0,
      summaryLine: `siteDataClearCurrentPlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} storageOrigin=${normalizedStorageOrigin} originStorage=${normalizedStorageOrigin.length > 0} cookies=false cache=false capability=origin-storage-only`
    };
  }

  buildSiteDataClearOnClosePlan(
    storageOrigin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): SiteDataClearOnClosePlan {
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(privacyMode);
    const normalizedDataScope = normalizeBrowserDataScope(dataScope, normalizedPrivacyMode);
    const normalizedStorageOrigin = storageOrigin.trim();
    const context = this.resolveErasureContext(privacyMode, dataScope);
    if (context === undefined) {
      return {
        profileId: normalizedProfileId,
        privacyMode: normalizedPrivacyMode,
        dataScope: normalizedDataScope,
        storageOrigin: normalizedStorageOrigin,
        clearOriginStorage: false,
        clearCookiesSupported: false,
        summaryLine: `siteDataClearOnClosePlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} storageOrigin=${normalizedStorageOrigin} capability=invalid-context`
      };
    }
    if (normalizedDataScope === 'session_ephemeral') {
      return {
        profileId: normalizedProfileId,
        privacyMode: normalizedPrivacyMode,
        dataScope: normalizedDataScope,
        storageOrigin: normalizedStorageOrigin,
        clearOriginStorage: false,
        clearCookiesSupported: false,
        summaryLine: `siteDataClearOnClosePlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} storageOrigin=${normalizedStorageOrigin} originStorage=false cookies=false cache=false capability=private-origin-unavailable`
      };
    }
    return {
      profileId: normalizedProfileId,
      privacyMode: normalizedPrivacyMode,
      dataScope: normalizedDataScope,
      storageOrigin: normalizedStorageOrigin,
      clearOriginStorage: normalizedStorageOrigin.length > 0,
      clearCookiesSupported: false,
      summaryLine: `siteDataClearOnClosePlan profile=${normalizedProfileId} privacy=${normalizedPrivacyMode} dataScope=${normalizedDataScope} storageOrigin=${normalizedStorageOrigin} originStorage=${normalizedStorageOrigin.length > 0} cookies=false cache=false capability=origin-storage-only`
    };
  }

  private clearCache(controllerAttached: boolean, controller?: webview.WebviewController): void {
    if (controllerAttached && controller !== undefined) {
      controller.removeCache(true);
      return;
    }
    webview.WebviewController.removeAllCache(true);
  }

  private clearAllCookiesForContext(isSessionEphemeral: boolean): void {
    if (isSessionEphemeral) {
      webview.WebCookieManager.clearAllCookiesSync(true);
    } else {
      webview.WebCookieManager.clearAllCookiesSync(false);
      void this.regularSessionCookieSnapshotRepository?.clearSnapshot();
    }
    webview.WebCookieManager.saveCookieSync();
  }

  private resolveErasureContext(
    privacyMode: BrowserSessionPrivacyMode,
    dataScope?: BrowserDataScope
  ): SiteDataErasureContext | undefined {
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(privacyMode);
    const normalizedDataScope = normalizeBrowserDataScope(dataScope, normalizedPrivacyMode);
    const expectedDataScope = resolveBrowserDataScopeForPrivacyMode(normalizedPrivacyMode);
    if (normalizedDataScope !== expectedDataScope) {
      return undefined;
    }
    return {
      dataScope: normalizedDataScope,
      isSessionEphemeral: normalizedDataScope === 'session_ephemeral'
    };
  }

  private readCookieAcceptance(): boolean {
    try {
      return webview.WebCookieManager.isCookieAllowed();
    } catch (_error) {
      return true;
    }
  }

  private readThirdPartyCookieAcceptance(): boolean {
    try {
      return webview.WebCookieManager.isThirdPartyCookieAllowed();
    } catch (_error) {
      return true;
    }
  }

  private readCookieCount(url: string): number {
    try {
      return this.countCookiePairs(webview.WebCookieManager.fetchCookieSync(url, false));
    } catch (_error) {
      return 0;
    }
  }

  private countCookiePairs(cookieHeader: string): number {
    const trimmed = cookieHeader.trim();
    if (trimmed.length === 0) {
      return 0;
    }
    return trimmed.split(';')
      .map((item: string) => item.trim())
      .filter((item: string) => item.length > 0 && item.indexOf('=') > 0)
      .length;
  }

  private normalizeOrigin(origin: string): string {
    return origin.trim().toLowerCase();
  }

  private async savePrivateCookieSnapshot(): Promise<number> {
    const repository = this.privateCookieSnapshotRepository;
    if (repository === undefined) {
      return 0;
    }
    const now = Date.now();
    const cookies = await webview.WebCookieManager.fetchAllCookies(true);
    const snapshotCookies = cookies
      .map((cookie: webview.WebHttpCookie): PrivateModeCookieSnapshotRecord | undefined => {
        return this.toPrivateCookieSnapshotRecord(cookie, now);
      })
      .filter((cookie: PrivateModeCookieSnapshotRecord | undefined) => cookie !== undefined) as PrivateModeCookieSnapshotRecord[];
    await repository.saveSnapshot(snapshotCookies);
    return snapshotCookies.length;
  }

  private toPrivateCookieSnapshotRecord(
    cookie: webview.WebHttpCookie,
    updatedAt: number
  ): PrivateModeCookieSnapshotRecord | undefined {
    const name = cookie.name.trim();
    const domain = cookie.domain.trim();
    if (name.length <= 0 || domain.length <= 0) {
      return undefined;
    }
    return {
      name: name,
      value: cookie.value,
      domain: domain,
      path: cookie.path.trim().length > 0 ? cookie.path.trim() : '/',
      expiresDate: cookie.expiresDate,
      isSessionCookie: cookie.isSessionCookie,
      isHttpOnly: cookie.isHttpOnly,
      isSecure: cookie.isSecure,
      samesitePolicy: cookie.samesitePolicy,
      updatedAt: updatedAt
    };
  }

  private buildCookieUrl(cookie: PrivateModeCookieSnapshotRecord): string {
    const host = cookie.domain.trim().replace(/^\./, '');
    const scheme = cookie.isSecure ? 'https://' : 'http://';
    return `${scheme}${host}${cookie.path.startsWith('/') ? cookie.path : `/${cookie.path}`}`;
  }

  private buildSetCookieValue(cookie: PrivateModeCookieSnapshotRecord): string {
    const parts: string[] = [`${cookie.name}=${cookie.value}`];
    const domain = cookie.domain.trim();
    if (domain.length > 0) {
      parts.push(`Domain=${domain}`);
    }
    parts.push(`Path=${cookie.path.trim().length > 0 ? cookie.path.trim() : '/'}`);
    if (!cookie.isSessionCookie && cookie.expiresDate.trim().length > 0) {
      parts.push(`Expires=${cookie.expiresDate.trim()}`);
    }
    if (cookie.isSecure) {
      parts.push('Secure');
    }
    if (cookie.isHttpOnly) {
      parts.push('HttpOnly');
    }
    const sameSite = this.resolveSameSiteLabel(cookie.samesitePolicy);
    if (sameSite.length > 0) {
      parts.push(`SameSite=${sameSite}`);
    }
    return parts.join('; ');
  }

  private resolveSameSiteLabel(policy: number): string {
    if (policy === webview.WebHttpCookieSameSitePolicy.NONE) {
      return 'None';
    }
    if (policy === webview.WebHttpCookieSameSitePolicy.LAX) {
      return 'Lax';
    }
    if (policy === webview.WebHttpCookieSameSitePolicy.STRICT) {
      return 'Strict';
    }
    return '';
  }
}
