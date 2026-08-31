import {
  ManualElementHideRule,
  ManualElementHideSettings,
  ManualElementHideSiteRules
} from '../../common/models/BrowserModels';

export interface ManualElementHideSiteRowViewState {
  id: string;
  host: string;
  title: string;
  ruleCount: number;
}

export interface ManualElementHideSettingsViewState {
  summaryText: string;
  rows: ManualElementHideSiteRowViewState[];
  hasRows: boolean;
}

export interface ManualElementHideRuleRowViewState {
  id: string;
  selector: string;
}

export interface ManualElementHideSiteRulesViewState {
  host: string;
  enabled: boolean;
  rules: ManualElementHideRuleRowViewState[];
  ruleCountText: string;
  hasRules: boolean;
}

export class ManualElementHideSettingsViewModel {
  buildState(settings: ManualElementHideSettings): ManualElementHideSettingsViewState {
    const sites = settings.sites
      .filter((site: ManualElementHideSiteRules) => site.rules.length > 0)
      .sort((left: ManualElementHideSiteRules, right: ManualElementHideSiteRules) => {
        if (right.updatedAt !== left.updatedAt) {
          return right.updatedAt - left.updatedAt;
        }
        return left.host.localeCompare(right.host);
      });
    const rows = sites.map((site: ManualElementHideSiteRules): ManualElementHideSiteRowViewState => {
      return {
        id: site.host,
        host: site.host,
        title: site.host,
        ruleCount: site.rules.length
      };
    });
    const totalRuleCount = sites.reduce((sum: number, site: ManualElementHideSiteRules) => {
      return sum + site.rules.length;
    }, 0);
    return {
      summaryText: sites.length > 0 ? `${sites.length} 个网站 · ${totalRuleCount} 条规则` : '还没有清理过页面元素',
      rows: rows,
      hasRows: rows.length > 0
    };
  }

  buildSiteState(settings: ManualElementHideSettings, host: string): ManualElementHideSiteRulesViewState {
    const normalizedHost = (host ?? '').trim().toLowerCase();
    const site = settings.sites.find((item: ManualElementHideSiteRules) => item.host === normalizedHost);
    if (site === undefined) {
      return this.emptySiteState(normalizedHost);
    }
    const rules = site.rules
      .slice(0)
      .sort((left: ManualElementHideRule, right: ManualElementHideRule) => {
        if (right.updatedAt !== left.updatedAt) {
          return right.updatedAt - left.updatedAt;
        }
        return left.selector.localeCompare(right.selector);
      })
      .map((rule: ManualElementHideRule): ManualElementHideRuleRowViewState => {
        return {
          id: rule.id,
          selector: rule.selector
        };
      });
    return {
      host: site.host,
      enabled: site.enabled,
      rules: rules,
      ruleCountText: `${rules.length} 条清理规则`,
      hasRules: rules.length > 0
    };
  }

  private emptySiteState(host: string): ManualElementHideSiteRulesViewState {
    return {
      host: host,
      enabled: false,
      rules: [],
      ruleCountText: '没有清理规则',
      hasRules: false
    };
  }
}
