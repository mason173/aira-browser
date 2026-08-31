import {
  AdBlockPreferences,
  AdBlockSettings,
  AdBlockSiteException,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';

export interface AdBlockPagePolicyResult {
  available: boolean;
  enabledForPage: boolean;
  allowlisted: boolean;
  summary: string;
}

export interface AdBlockSiteProtectionState {
  canToggle: boolean;
  host: string;
  siteEnabled: boolean;
}

export interface AdBlockRuntimePolicySettings {
  preferences: AdBlockPreferences;
  siteExceptions: AdBlockSiteException[];
  enabledRuleSourceCount: number;
}

export class AdBlockPolicyService {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  buildControllerDisabledSummary(): string {
    return '网页内容过滤未开启';
  }

  buildCapabilityUnavailableSummary(): string {
    return '当前设备暂不支持网页内容过滤';
  }

  resolvePagePolicy(
    settings: AdBlockSettings,
    url: string,
    capabilitySupported: boolean,
    controllerAttached: boolean,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope: BrowserDataScope = 'profile_persistent'
  ): AdBlockPagePolicyResult {
    return this.resolvePagePolicyForRuntime({
      preferences: settings.preferences,
      siteExceptions: settings.siteExceptions,
      enabledRuleSourceCount: this.countEnabledRuleSources(settings)
    }, url, capabilitySupported, controllerAttached, profileId, privacyMode, dataScope);
  }

  resolvePagePolicyForRuntime(
    settings: AdBlockRuntimePolicySettings,
    url: string,
    capabilitySupported: boolean,
    controllerAttached: boolean,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope: BrowserDataScope = 'profile_persistent'
  ): AdBlockPagePolicyResult {
    const host = this.extractHost(url);
    const allowlisted = host.length > 0 ? this.isHostAllowlisted(settings, host, profileId) : false;
    if (!controllerAttached) {
      return {
        available: false,
        enabledForPage: false,
        allowlisted: allowlisted,
        summary: '网页还未加载完成'
      };
    }
    if (!capabilitySupported) {
      return {
        available: false,
        enabledForPage: false,
        allowlisted: allowlisted,
        summary: this.buildCapabilityUnavailableSummary()
      };
    }
    if (!settings.preferences.enabled) {
      return {
        available: true,
        enabledForPage: false,
        allowlisted: allowlisted,
        summary: this.buildControllerDisabledSummary()
      };
    }
    if (settings.enabledRuleSourceCount <= 0) {
      return {
        available: true,
        enabledForPage: false,
        allowlisted: allowlisted,
        summary: '没有启用的拦截规则'
      };
    }
    if (host.length === 0) {
      return {
        available: true,
        enabledForPage: false,
        allowlisted: false,
        summary: '当前页面暂不适用网页内容过滤'
      };
    }
    if (allowlisted) {
      return {
        available: true,
        enabledForPage: false,
        allowlisted: true,
        summary: '此站点已加入例外'
      };
    }
    const boundarySuffix = this.profileBoundaryService.isSessionEphemeral({
      profileId: profileId,
      privacyMode: privacyMode,
      dataScope: dataScope
    }) ? ' · 私密模式不记录站点统计' : '';
    return {
      available: true,
      enabledForPage: true,
      allowlisted: false,
      summary: `已开启，使用规则订阅过滤网页内容${boundarySuffix}`
    };
  }

  isHostAllowlisted(
    settings: AdBlockRuntimePolicySettings | AdBlockSettings,
    host: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): boolean {
    const normalizedHost = this.normalizeComparableHost(host);
    if (normalizedHost.length === 0) {
      return false;
    }
    return settings.siteExceptions.some((item) => {
      if (item.profileId !== profileId) {
        return false;
      }
      if (normalizedHost === item.host) {
        return true;
      }
      return item.includeSubdomains && normalizedHost.endsWith(`.${item.host}`);
    });
  }

  resolveSiteProtectionState(
    settings: AdBlockSettings,
    url: string,
    capabilitySupported: boolean,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): AdBlockSiteProtectionState {
    const host = this.extractHost(url);
    const allowlisted = host.length > 0 ? this.isHostAllowlisted(settings, host, profileId) : false;
    return {
      canToggle: host.length > 0 && capabilitySupported && settings.preferences.enabled,
      host: host,
      siteEnabled: !allowlisted
    };
  }

  extractHost(url: string): string {
    let value = url.trim().toLowerCase();
    if (value.length === 0 || value === 'aira://home') {
      return '';
    }
    if (value.startsWith('http://')) {
      value = value.substring(7);
    } else if (value.startsWith('https://')) {
      value = value.substring(8);
    } else {
      return '';
    }
    const pathStart = value.indexOf('/');
    if (pathStart >= 0) {
      value = value.substring(0, pathStart);
    }
    const portStart = value.indexOf(':');
    if (portStart >= 0) {
      value = value.substring(0, portStart);
    }
    return value;
  }

  private normalizeComparableHost(value: string): string {
    const extractedHost = this.extractHost(value);
    if (extractedHost.length > 0) {
      return extractedHost;
    }
    let normalized = value.trim().toLowerCase();
    if (normalized.length === 0 || normalized.indexOf('://') >= 0) {
      return '';
    }
    const pathStart = normalized.indexOf('/');
    if (pathStart >= 0) {
      normalized = normalized.substring(0, pathStart);
    }
    const portStart = normalized.indexOf(':');
    if (portStart >= 0) {
      normalized = normalized.substring(0, portStart);
    }
    return normalized;
  }

  private countEnabledRuleSources(settings: AdBlockSettings): number {
    let count = 0;
    settings.customRuleSources.forEach((item) => {
      if (item.enabled && item.ruleCount > 0) {
        count += 1;
      }
    });
    return count;
  }
}
