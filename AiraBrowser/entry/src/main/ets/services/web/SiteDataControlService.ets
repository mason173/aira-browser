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
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { sharedBrowserSslDecisionCacheRuntime } from './BrowserSslDecisionCacheRuntime';

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
  title: string;
  message: string;
  confirmLabel: string;
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

  constructor(
    preferencesRepository: PreferencesRepository,
    privateCookieSnapshotRepository?: PrivateModeCookieSnapshotRepository
  ) {
    this.preferencesRepository = preferencesRepository;
    this.privateCookieSnapshotRepository = privateCookieSnapshotRepository;
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
    const cookieLabel = snapshot.acceptCookies ? '当前允许站点 Cookie' : '当前已禁用站点 Cookie';
    const thirdPartyLabel = snapshot.acceptThirdPartyCookies ? '当前允许第三方 Cookie' : '当前已拦截第三方 Cookie';
    const profileLabel = snapshot.profileId === DEFAULT_BROWSER_PROFILE_ID
      ? '当前资料：常规浏览资料'
      : `当前资料：${snapshot.profileId}`;
    const privacyLabel = snapshot.privacyMode === 'private' ? '当前会话边界：私密会话' : '当前会话边界：常规会话';
    if (snapshot.dataScope === 'session_ephemeral') {
      return {
        profileId: snapshot.profileId,
        privacyMode: snapshot.privacyMode,
        dataScope: snapshot.dataScope,
        summaryLine: `${profileLabel}；${cookieLabel}；${thirdPartyLabel}；${privacyLabel}；数据范围：仅本次私密会话。平台不支持按当前站点清除私密 Cookie 或站点存储，请使用“清除本次私密数据”统一清理。`,
        permissionSummaryLine: `当前仅显示本次私密会话的站点权限；会话权限规则 ${snapshot.sessionPermissionCount} 条；不会读取或列出常规浏览资料中的站点权限规则。`,
        canExposeProfilePermissionRules: false
      };
    }
    return {
      profileId: snapshot.profileId,
      privacyMode: snapshot.privacyMode,
      dataScope: snapshot.dataScope,
      summaryLine: `${profileLabel}；${cookieLabel}；${thirdPartyLabel}；${privacyLabel}；数据范围：常规浏览资料。当前站点清理只处理按来源隔离的站点存储；Cookie、缓存和全部站点存储在“隐私防护”中统一清理。`,
      permissionSummaryLine: `已保存 ${snapshot.savedPermissionCount} 条站点权限。当前站点清理不会删除 Cookie 或共享网页缓存。`,
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
      summaryLine: `${summary.permissionSummaryLine} 其中允许 ${allowCount} 项，阻止 ${blockCount} 项。`
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

  buildClearCurrentSiteDataDialogState(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope
  ): SiteDataClearDialogState {
    const plan = this.buildClearCurrentSiteDataPlan('', profileId, privacyMode, dataScope);
    if (plan.dataScope === 'session_ephemeral') {
      return {
        title: '无法按站点清除私密数据',
        message: '系统当前不支持只清除这个私密站点的存储或 Cookie，请前往“隐私防护”清除本次私密数据。',
        confirmLabel: '知道了'
      };
    }
    return {
      title: '清除当前站点存储',
      message: '只会清除当前网站保存的本地数据，不会清除 Cookie 或网页缓存，登录状态可能保留。确定要继续吗？',
      confirmLabel: '清除'
    };
  }

  async restorePreservedPrivateModeCookies(): Promise<PrivateModeCookiePreservationResult> {
    const repository = this.privateCookieSnapshotRepository;
    if (repository === undefined) {
      return new PrivateModeCookiePreservationResultRecord(false, 0, 0, 0, '未启用隐私 Cookie 快照。');
    }
    try {
      const snapshot = await repository.readSnapshot();
      if (snapshot.cookies.length <= 0) {
        return new PrivateModeCookiePreservationResultRecord(false, 0, 0, 0, '没有可恢复的隐私 Cookie。');
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
        `隐私 Cookie 已恢复 ${restoredCookieCount} 条，失败 ${failedCookieCount} 条。`
      );
    } catch (error) {
      return new PrivateModeCookiePreservationResultRecord(
        true,
        0,
        0,
        0,
        `恢复隐私 Cookie 失败：${JSON.stringify(error)}`
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
        `隐私 Cookie 已保存 ${savedCookieCount} 条。`
      );
    } catch (error) {
      return new PrivateModeCookiePreservationResultRecord(
        true,
        0,
        0,
        0,
        `保存隐私 Cookie 失败：${JSON.stringify(error)}`
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
          ? `私密会话数据已清除，已保留 ${savedCookieCount} 条 Cookie 快照。`
          : '私密会话数据已清除。'
      };
    } catch (error) {
      return {
        hasError: true,
        message: `清除私密会话数据失败：${JSON.stringify(error)}`
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
        message: '浏览数据范围不一致，未执行清理。'
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
          ? '系统当前不支持按站点清除私密存储，请前往“隐私防护”清除本次私密数据。'
          : '当前站点没有可按站点清除的本地存储。'
      };
    }
    try {
      webview.WebStorage.deleteOrigin(plan.storageOrigin);
    } catch (error) {
      return {
        hasError: true,
        message: `清除当前站点存储失败：${JSON.stringify(error)}`
      };
    }
    return {
      hasError: false,
      message: '当前站点存储已清除，Cookie 和网页缓存已保留。'
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
        message: '浏览数据范围不一致，未执行清理。'
      };
    }
    const normalizedOrigin = this.normalizeOrigin(origin);
    if (normalizedOrigin.length === 0) {
      return {
        hasError: true,
        message: '站点地址不可用，未清理数据。'
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
          ? '私密数据未按站点清除；Cookie 和站点存储将在私密会话结束时统一清理。'
          : '当前站点没有可按站点清除的本地存储。'
      };
    }
    try {
      webview.WebStorage.deleteOrigin(plan.storageOrigin);
    } catch (error) {
      return {
        hasError: true,
        message: `清除站点存储失败：${JSON.stringify(error)}`
      };
    }
    return {
      hasError: false,
      message: '站点存储已清除，Cookie 和网页缓存已保留。'
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
        message: '浏览数据范围不一致，未执行清理。'
      };
    }
    const plan = this.buildClearAllSiteDataPlan(profileId, privacyMode, dataScope);
    const isSessionEphemeral = context.isSessionEphemeral;
    const failureMessages: string[] = [];

    if (plan.clearWebStorage) {
      try {
        webview.WebStorage.deleteAllData(isSessionEphemeral);
      } catch (error) {
        failureMessages.push(`站点存储：${JSON.stringify(error)}`);
      }
    }

    if (plan.clearCookies) {
      try {
        this.clearAllCookiesForContext(isSessionEphemeral);
      } catch (error) {
        failureMessages.push(`Cookie：${JSON.stringify(error)}`);
      }
    }

    if (plan.clearCache) {
      try {
        this.clearCache(controllerAttached, controller);
      } catch (error) {
        failureMessages.push(`网页缓存：${JSON.stringify(error)}`);
      }
    }

    if (plan.clearProfilePermissions) {
      try {
        await this.preferencesRepository.clearAllSitePermissionSettings(plan.profileId);
        webview.GeolocationPermissions.deleteAllGeolocation(false);
        sharedBrowserSslDecisionCacheRuntime.requestClear();
      } catch (error) {
        failureMessages.push(`站点权限：${JSON.stringify(error)}`);
      }
    }

    if (failureMessages.length > 0) {
      return {
        hasError: true,
        message: `部分浏览数据清除失败：${failureMessages.join('；')}`,
        failureMessages: failureMessages.slice()
      };
    }
    return {
      hasError: false,
      message: isSessionEphemeral
        ? '本次私密会话的 Cookie 和站点存储已清除，常规浏览资料未受影响。'
        : '浏览数据、Cookie、缓存和当前浏览资料中的站点权限已全部清除。'
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
        message: '浏览数据范围不一致，未执行清理。'
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
        failureMessages.push(`站点存储：${JSON.stringify(error)}`);
      }
    }

    if (selection.clearCookies) {
      try {
        this.clearAllCookiesForContext(isSessionEphemeral);
      } catch (error) {
        failureMessages.push(`Cookie：${JSON.stringify(error)}`);
      }
    }

    if (!isSessionEphemeral && selection.clearCache) {
      try {
        this.clearCache(controllerAttached, controller);
      } catch (error) {
        failureMessages.push(`网页缓存：${JSON.stringify(error)}`);
      }
    }

    if (!isSessionEphemeral && selection.clearProfilePermissions) {
      try {
        await this.preferencesRepository.clearAllSitePermissionSettings(normalizedProfileId);
        webview.GeolocationPermissions.deleteAllGeolocation(false);
        sharedBrowserSslDecisionCacheRuntime.requestClear();
      } catch (error) {
        failureMessages.push(`站点权限：${JSON.stringify(error)}`);
      }
    }

    if (failureMessages.length > 0) {
      return {
        hasError: true,
        message: `部分浏览数据清除失败：${failureMessages.join('；')}`,
        failureMessages: failureMessages.slice()
      };
    }
    return {
      hasError: false,
      message: '所选浏览数据已清除。'
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
