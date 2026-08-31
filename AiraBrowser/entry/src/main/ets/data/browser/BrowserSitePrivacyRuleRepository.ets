import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserProfileId,
  BrowserSitePrivacyRule
} from '../../common/models/BrowserModels';
import {
  BrowserSitePrivacyRuleMode,
  BrowserSitePrivacyRuleService
} from '../../services/web/BrowserSitePrivacyRuleService';

const PREFERENCES_NAME: string = 'aira_browser_site_privacy_rules';
const SITE_PRIVACY_RULES_KEY: string = 'site_privacy_rules';
const MAX_SITE_PRIVACY_RULES: number = 160;

export class BrowserSitePrivacyRuleRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private service: BrowserSitePrivacyRuleService = new BrowserSitePrivacyRuleService();
  private siteRules: BrowserSitePrivacyRule[] = [];

  async initialize(): Promise<void> {
    const store = await this.getStore();
    this.siteRules = this.parseSiteRules(String(store.getSync(SITE_PRIVACY_RULES_KEY, '')));
  }

  listSiteRules(profileId?: BrowserProfileId): BrowserSitePrivacyRule[] {
    const rules = profileId === undefined
      ? this.siteRules
      : this.siteRules.filter((rule: BrowserSitePrivacyRule) => rule.profileId === profileId);
    return rules.map((rule: BrowserSitePrivacyRule) => this.copySiteRule(rule));
  }

  findSiteRule(origin: string, profileId: BrowserProfileId): BrowserSitePrivacyRule | undefined {
    const normalizedOrigin = this.service.extractOrigin(origin);
    if (normalizedOrigin.length <= 0) {
      return undefined;
    }
    const matchedRule = this.siteRules.find((rule: BrowserSitePrivacyRule) => {
      return rule.profileId === profileId && rule.primaryOrigin === normalizedOrigin;
    });
    return matchedRule === undefined ? undefined : this.copySiteRule(matchedRule);
  }

  findMatchingRule(url: string, profileId: BrowserProfileId): BrowserSitePrivacyRule | undefined {
    const matchedRule = this.siteRules.find((rule: BrowserSitePrivacyRule) => {
      return rule.profileId === profileId && this.service.matchesRule(url, rule);
    });
    return matchedRule === undefined ? undefined : this.copySiteRule(matchedRule);
  }

  async upsertSiteRule(
    profileId: BrowserProfileId,
    origin: string,
    mode: BrowserSitePrivacyRuleMode,
    includeSubdomains: boolean = false,
    preserveCookiesOnClose: boolean = false
  ): Promise<BrowserSitePrivacyRule | undefined> {
    const nextRule = this.service.normalizeRule(
      this.service.buildRule(profileId, origin, mode, includeSubdomains, preserveCookiesOnClose)
    );
    if (nextRule === undefined) {
      return undefined;
    }
    const nextRules = this.siteRules
      .filter((rule: BrowserSitePrivacyRule) => {
        return rule.profileId !== profileId || rule.primaryOrigin !== nextRule.primaryOrigin;
      })
      .concat([nextRule])
      .sort((left: BrowserSitePrivacyRule, right: BrowserSitePrivacyRule) => {
        return left.updatedAt - right.updatedAt;
      })
      .slice(-MAX_SITE_PRIVACY_RULES);
    await this.persistSiteRules(nextRules);
    return this.copySiteRule(nextRule);
  }

  async removeSiteRule(origin: string, profileId: BrowserProfileId): Promise<void> {
    const normalizedOrigin = this.service.extractOrigin(origin);
    if (normalizedOrigin.length <= 0) {
      return;
    }
    const nextRules = this.siteRules.filter((rule: BrowserSitePrivacyRule) => {
      return rule.profileId !== profileId || rule.primaryOrigin !== normalizedOrigin;
    });
    if (nextRules.length === this.siteRules.length) {
      return;
    }
    await this.persistSiteRules(nextRules);
  }

  async clearAllSiteRules(): Promise<void> {
    if (this.siteRules.length === 0) {
      return;
    }
    await this.persistSiteRules([]);
  }

  private parseSiteRules(value: string): BrowserSitePrivacyRule[] {
    if (value.trim().length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as BrowserSitePrivacyRule[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const normalizedRules: BrowserSitePrivacyRule[] = [];
      parsed.forEach((rule: BrowserSitePrivacyRule) => {
        const normalizedRule = this.service.normalizeRule(rule);
        if (normalizedRule !== undefined) {
          normalizedRules.push(normalizedRule);
        }
      });
      return normalizedRules.slice(-MAX_SITE_PRIVACY_RULES);
    } catch (_error) {
      return [];
    }
  }

  private async persistSiteRules(siteRules: BrowserSitePrivacyRule[]): Promise<void> {
    this.siteRules = siteRules.map((rule: BrowserSitePrivacyRule) => this.copySiteRule(rule));
    const store = await this.getStore();
    store.putSync(SITE_PRIVACY_RULES_KEY, JSON.stringify(this.siteRules));
    store.flushSync();
  }

  private copySiteRule(rule: BrowserSitePrivacyRule): BrowserSitePrivacyRule {
    return {
      profileId: rule.profileId,
      origin: rule.origin,
      siteKey: rule.siteKey,
      displayHost: rule.displayHost,
      primaryOrigin: rule.primaryOrigin,
      mode: rule.mode,
      includeSubdomains: rule.includeSubdomains,
      preserveCookiesOnClose: rule.preserveCookiesOnClose,
      updatedAt: rule.updatedAt
    };
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}
