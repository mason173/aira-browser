import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  ManualElementHideRule,
  ManualElementHideSettings,
  ManualElementHideSiteRules
} from '../../common/models/BrowserModels';

const PREFERENCES_NAME: string = 'aira_manual_element_hide';
const SETTINGS_KEY: string = 'manual_element_hide_settings_v1';
const MAX_RULES_PER_SITE: number = 80;
const MAX_SITES: number = 300;

export class ManualElementHideRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: ManualElementHideSettings = this.buildDefaultSettings();
  private initializationPromise?: Promise<ManualElementHideSettings>;
  private initialized: boolean = false;

  async initialize(): Promise<ManualElementHideSettings> {
    if (this.initialized) {
      return this.getSettings();
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.loadSettingsFromStore()
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw error;
        });
    }
    return this.initializationPromise;
  }

  async ensureInitialized(): Promise<ManualElementHideSettings> {
    return await this.initialize();
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  private async loadSettingsFromStore(): Promise<ManualElementHideSettings> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(SETTINGS_KEY, ''));
    this.settings = this.normalizeSettings(this.parseSettings(rawSettings));
    if (rawSettings.trim().length === 0) {
      await this.persistSettings(this.settings);
      this.initialized = true;
      return this.getSettings();
    }
    this.initialized = true;
    return this.getSettings();
  }

  getSettings(): ManualElementHideSettings {
    return this.cloneSettings(this.settings);
  }

  getEnabledSelectorsForHost(host: string): string[] {
    const site = this.findSite(this.normalizeHost(host));
    if (site === undefined || !site.enabled) {
      return [];
    }
    return site.rules.map((rule: ManualElementHideRule) => rule.selector);
  }

  getRuleCountForHost(host: string): number {
    const site = this.findSite(this.normalizeHost(host));
    return site === undefined ? 0 : site.rules.length;
  }

  async addSelectorsForHost(host: string, selectors: string[], pageUrl: string): Promise<ManualElementHideSiteRules | undefined> {
    const normalizedHost = this.normalizeHost(host);
    const normalizedSelectors = this.normalizeSelectors(selectors);
    if (normalizedHost.length === 0 || normalizedSelectors.length === 0) {
      return undefined;
    }
    await this.ensureInitialized();
    const now = Date.now();
    const existingSite = this.findSite(normalizedHost);
    const existingRules = existingSite?.rules ?? [];
    let nextRules = existingRules.map((rule: ManualElementHideRule) => this.cloneRule(rule));
    normalizedSelectors.forEach((selector: string) => {
      const existingIndex = nextRules.findIndex((rule: ManualElementHideRule) => rule.selector === selector);
      if (existingIndex >= 0) {
        const existing = nextRules[existingIndex];
        nextRules[existingIndex] = {
          id: existing.id,
          host: normalizedHost,
          selector: selector,
          pageUrl: pageUrl,
          createdAt: existing.createdAt,
          updatedAt: now
        };
        return;
      }
      nextRules = nextRules.concat([{
        id: this.buildRuleId(normalizedHost, selector, now),
        host: normalizedHost,
        selector: selector,
        pageUrl: pageUrl,
        createdAt: now,
        updatedAt: now
      }]);
    });
    nextRules = nextRules.slice(Math.max(0, nextRules.length - MAX_RULES_PER_SITE));
    const nextSite: ManualElementHideSiteRules = {
      host: normalizedHost,
      enabled: existingSite?.enabled ?? true,
      rules: nextRules,
      createdAt: existingSite?.createdAt ?? now,
      updatedAt: now
    };
    const otherSites = this.settings.sites.filter((site: ManualElementHideSiteRules) => site.host !== normalizedHost);
    const nextSettings: ManualElementHideSettings = {
      sites: otherSites.concat([nextSite]).slice(Math.max(0, otherSites.length + 1 - MAX_SITES)),
      updatedAt: now
    };
    await this.persistSettings(this.normalizeSettings(nextSettings));
    return this.cloneSite(nextSite);
  }

  async setSiteEnabled(host: string, enabled: boolean): Promise<ManualElementHideSiteRules | undefined> {
    await this.ensureInitialized();
    const normalizedHost = this.normalizeHost(host);
    const site = this.findSite(normalizedHost);
    if (site === undefined) {
      return undefined;
    }
    const now = Date.now();
    const nextSite: ManualElementHideSiteRules = {
      host: normalizedHost,
      enabled: enabled,
      rules: site.rules.map((rule: ManualElementHideRule) => this.cloneRule(rule)),
      createdAt: site.createdAt,
      updatedAt: now
    };
    await this.persistSettings({
      sites: this.settings.sites.map((item: ManualElementHideSiteRules) => {
        return item.host === normalizedHost ? nextSite : this.cloneSite(item);
      }),
      updatedAt: now
    });
    return this.cloneSite(nextSite);
  }

  async clearSite(host: string): Promise<boolean> {
    await this.ensureInitialized();
    const normalizedHost = this.normalizeHost(host);
    const nextSites = this.settings.sites.filter((site: ManualElementHideSiteRules) => site.host !== normalizedHost);
    if (nextSites.length === this.settings.sites.length) {
      return false;
    }
    await this.persistSettings({
      sites: nextSites.map((site: ManualElementHideSiteRules) => this.cloneSite(site)),
      updatedAt: Date.now()
    });
    return true;
  }

  async removeRule(host: string, ruleId: string): Promise<boolean> {
    await this.ensureInitialized();
    const normalizedHost = this.normalizeHost(host);
    const normalizedRuleId = (ruleId ?? '').trim();
    const site = this.findSite(normalizedHost);
    if (site === undefined || normalizedRuleId.length === 0) {
      return false;
    }
    const nextRules = site.rules.filter((rule: ManualElementHideRule) => rule.id !== normalizedRuleId);
    if (nextRules.length === site.rules.length) {
      return false;
    }
    const now = Date.now();
    const nextSites: ManualElementHideSiteRules[] = nextRules.length === 0
      ? this.settings.sites.filter((item: ManualElementHideSiteRules) => item.host !== normalizedHost)
      : this.settings.sites.map((item: ManualElementHideSiteRules) => {
        if (item.host !== normalizedHost) {
          return this.cloneSite(item);
        }
        return {
          host: normalizedHost,
          enabled: site.enabled,
          rules: nextRules.map((rule: ManualElementHideRule) => this.cloneRule(rule)),
          createdAt: site.createdAt,
          updatedAt: now
        };
      });
    await this.persistSettings({
      sites: nextSites,
      updatedAt: now
    });
    return true;
  }

  private findSite(host: string): ManualElementHideSiteRules | undefined {
    if (host.length === 0) {
      return undefined;
    }
    return this.settings.sites.find((site: ManualElementHideSiteRules) => site.host === host);
  }

  private normalizeSettings(value: ManualElementHideSettings | undefined): ManualElementHideSettings {
    const sites: ManualElementHideSiteRules[] = [];
    (value?.sites ?? []).forEach((site: ManualElementHideSiteRules) => {
      const normalizedSite = this.normalizeSite(site);
      if (normalizedSite.host.length > 0 && normalizedSite.rules.length > 0) {
        sites.push(normalizedSite);
      }
    });
    return {
      sites: sites.slice(Math.max(0, sites.length - MAX_SITES)),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizeSite(value: ManualElementHideSiteRules): ManualElementHideSiteRules {
    const host = this.normalizeHost(value.host);
    const rules: ManualElementHideRule[] = [];
    (value.rules ?? []).forEach((rule: ManualElementHideRule) => {
      const normalizedRule = this.normalizeRule(rule, host);
      if (normalizedRule.host.length > 0 && normalizedRule.selector.length > 0) {
        rules.push(normalizedRule);
      }
    });
    return {
      host: host,
      enabled: typeof value.enabled === 'boolean' ? value.enabled : true,
      rules: rules.slice(Math.max(0, rules.length - MAX_RULES_PER_SITE)),
      createdAt: this.normalizeTimestamp(value.createdAt),
      updatedAt: this.normalizeTimestamp(value.updatedAt)
    };
  }

  private normalizeRule(value: ManualElementHideRule, fallbackHost: string): ManualElementHideRule {
    const selector = this.normalizeSelector(value.selector);
    const host = this.normalizeHost(value.host.length > 0 ? value.host : fallbackHost);
    const now = Date.now();
    return {
      id: (value.id ?? '').trim().length > 0 ? value.id.trim() : this.buildRuleId(host, selector, now),
      host: host,
      selector: selector,
      pageUrl: (value.pageUrl ?? '').trim(),
      createdAt: this.normalizeTimestamp(value.createdAt) || now,
      updatedAt: this.normalizeTimestamp(value.updatedAt) || now
    };
  }

  private normalizeSelectors(values: string[]): string[] {
    const selectors: string[] = [];
    values.forEach((value: string) => {
      const selector = this.normalizeSelector(value);
      if (selector.length > 0 && !selectors.includes(selector)) {
        selectors.push(selector);
      }
    });
    return selectors;
  }

  private normalizeSelector(value: string): string {
    const selector = (value ?? '').trim();
    if (selector.length <= 0 || selector.length > 500) {
      return '';
    }
    return selector;
  }

  private normalizeHost(value: string): string {
    let host = (value ?? '').trim().toLowerCase();
    if (host.startsWith('http://')) {
      host = host.substring(7);
    } else if (host.startsWith('https://')) {
      host = host.substring(8);
    }
    const pathStart = host.indexOf('/');
    if (pathStart >= 0) {
      host = host.substring(0, pathStart);
    }
    const portStart = host.indexOf(':');
    if (portStart >= 0) {
      host = host.substring(0, portStart);
    }
    return host;
  }

  private parseSettings(value: string): ManualElementHideSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as ManualElementHideSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private buildDefaultSettings(): ManualElementHideSettings {
    return {
      sites: [],
      updatedAt: 0
    };
  }

  private async persistSettings(settings: ManualElementHideSettings): Promise<ManualElementHideSettings> {
    this.settings = this.cloneSettings(this.normalizeSettings(settings));
    const store = await this.getStore();
    store.putSync(SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    this.initialized = true;
    return this.getSettings();
  }

  private cloneSettings(settings: ManualElementHideSettings): ManualElementHideSettings {
    return {
      sites: settings.sites.map((site: ManualElementHideSiteRules) => this.cloneSite(site)),
      updatedAt: settings.updatedAt
    };
  }

  private cloneSite(value: ManualElementHideSiteRules): ManualElementHideSiteRules {
    return {
      host: value.host,
      enabled: value.enabled,
      rules: value.rules.map((rule: ManualElementHideRule) => this.cloneRule(rule)),
      createdAt: value.createdAt,
      updatedAt: value.updatedAt
    };
  }

  private cloneRule(value: ManualElementHideRule): ManualElementHideRule {
    return {
      id: value.id,
      host: value.host,
      selector: value.selector,
      pageUrl: value.pageUrl,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt
    };
  }

  private buildRuleId(host: string, selector: string, timestamp: number): string {
    let hash = 0;
    const value = `${host}|${selector}`;
    for (let index = 0; index < value.length; index++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(index);
      hash = hash & hash;
    }
    return `manual_hide_${timestamp}_${Math.abs(hash)}`;
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && value > 0 ? value : 0;
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
