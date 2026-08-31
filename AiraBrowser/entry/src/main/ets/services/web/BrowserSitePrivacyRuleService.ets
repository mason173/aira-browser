import {
  BrowserProfileId,
  BrowserSitePrivacyRule
} from '../../common/models/BrowserModels';
import { SiteIdentityService } from './SiteIdentityService';

export type BrowserSitePrivacyRuleMode = 'default' | 'clear_on_close';

export class BrowserSitePrivacyRuleService {
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();

  buildRule(
    profileId: BrowserProfileId,
    origin: string,
    mode: BrowserSitePrivacyRuleMode,
    includeSubdomains: boolean = false,
    preserveCookiesOnClose: boolean = false
  ): BrowserSitePrivacyRule | undefined {
    if (mode !== 'clear_on_close') {
      return undefined;
    }
    const identity = this.siteIdentityService.resolve(origin);
    if (identity.primaryOrigin.length <= 0) {
      return undefined;
    }
    return {
      profileId: profileId,
      origin: identity.primaryOrigin,
      siteKey: identity.siteKey,
      displayHost: identity.displayHost,
      primaryOrigin: identity.primaryOrigin,
      mode: 'clear_on_close',
      includeSubdomains: includeSubdomains,
      preserveCookiesOnClose: preserveCookiesOnClose,
      updatedAt: Date.now()
    };
  }

  normalizeRule(rule: BrowserSitePrivacyRule | undefined): BrowserSitePrivacyRule | undefined {
    if (rule === undefined || rule.mode !== 'clear_on_close') {
      return undefined;
    }
    if (typeof rule.siteKey !== 'string' || typeof rule.displayHost !== 'string' ||
      typeof rule.primaryOrigin !== 'string') {
      return undefined;
    }
    if (rule.siteKey.length <= 0 || rule.displayHost.length <= 0 || rule.primaryOrigin.length <= 0) {
      return undefined;
    }
    const identity = this.siteIdentityService.resolve(rule.primaryOrigin);
    if (identity.primaryOrigin.length <= 0) {
      return undefined;
    }
    return {
      profileId: rule.profileId,
      origin: identity.primaryOrigin,
      siteKey: identity.siteKey,
      displayHost: identity.displayHost,
      primaryOrigin: identity.primaryOrigin,
      mode: 'clear_on_close',
      includeSubdomains: rule.includeSubdomains === true,
      preserveCookiesOnClose: rule.preserveCookiesOnClose === true,
      updatedAt: rule.updatedAt > 0 ? rule.updatedAt : Date.now()
    };
  }

  extractOrigin(value: string): string {
    return this.siteIdentityService.resolve(value).primaryOrigin;
  }

  extractHost(value: string): string {
    return this.siteIdentityService.resolve(value).displayHost;
  }

  matchesRule(url: string, rule: BrowserSitePrivacyRule): boolean {
    const normalizedRule = this.normalizeRule(rule);
    if (normalizedRule === undefined) {
      return false;
    }
    const targetOrigin = this.extractOrigin(url);
    if (targetOrigin.length <= 0) {
      return false;
    }
    return targetOrigin === normalizedRule.origin;
  }

  resolveRuleSummary(rule: BrowserSitePrivacyRule | undefined): string {
    if (rule === undefined) {
      return '关闭';
    }
    return rule.preserveCookiesOnClose ? '保留 Cookie' : '开启';
  }
}
