import {
  AdBlockCustomRuleSource,
  AdBlockPreferences,
  AdBlockSettings,
  AdBlockSiteException
} from '../../common/models/BrowserModels';
import {
  APP_PROMOTION_BANNER_RULE_SOURCE_ID,
  BUILT_IN_AD_BLOCK_RULE_SOURCE_ID,
  SMOOTH_MODE_AD_BLOCK_RULE_SOURCE_ID
} from '../../features/adblock/AdBlockBuiltInRuleSource';
import {
  AdBlockThirdPartyRuleSourceDefinition,
  getAdBlockThirdPartyRuleSources,
  isAdBlockThirdPartyRuleSourceId
} from '../../features/adblock/AdBlockThirdPartyRuleSourceCatalog';

export interface AdBlockExceptionRowView {
  host: string;
  subtitle: string;
}

export interface AdBlockCustomRuleSourceRowView {
  id: string;
  title: string;
  url: string;
  sourceType: 'system' | 'remote' | 'local';
  enabled: boolean;
  statusText: string;
  detailText: string;
  hasError: boolean;
  isSystem: boolean;
  isThirdPartyPreset: boolean;
  canRefresh: boolean;
  canRemove: boolean;
}

export interface AdBlockSettingsViewState {
  enabled: boolean;
  updateOnForeground: boolean;
  hasProtectionStats: boolean;
  customRuleSources: AdBlockCustomRuleSourceRowView[];
  hasCustomRuleSources: boolean;
  exceptions: AdBlockExceptionRowView[];
  hasExceptions: boolean;
}

export class AdBlockSettingsViewModel {
  buildState(settings: AdBlockSettings): AdBlockSettingsViewState {
    const visibleRuleSources = this.buildVisibleRuleSources(settings.customRuleSources);
    return {
      enabled: settings.preferences.enabled,
      updateOnForeground: settings.preferences.updateOnForeground,
      hasProtectionStats: settings.stats.totalProtectionActionCount > 0,
      customRuleSources: visibleRuleSources,
      hasCustomRuleSources: visibleRuleSources.length > 0,
      exceptions: settings.siteExceptions.map((item: AdBlockSiteException): AdBlockExceptionRowView => {
        return {
          host: item.host,
          subtitle: item.includeSubdomains ? '包含子域名' : '仅当前域名'
        };
      }),
      hasExceptions: settings.siteExceptions.length > 0
    };
  }

  buildPreferencesPatch(
    current: AdBlockPreferences,
    key: 'enabled' | 'updateOnForeground',
    value: boolean
  ): AdBlockPreferences {
    return {
      enabled: key === 'enabled' ? value : current.enabled,
      updateOnForeground: key === 'updateOnForeground' ? value : current.updateOnForeground
    };
  }

  private buildVisibleRuleSources(sources: AdBlockCustomRuleSource[]): AdBlockCustomRuleSourceRowView[] {
    const presetRows = getAdBlockThirdPartyRuleSources()
      .map((definition: AdBlockThirdPartyRuleSourceDefinition): AdBlockCustomRuleSourceRowView => {
        const downloadedSource = sources.find((item: AdBlockCustomRuleSource) => {
          return item.id === definition.id && item.url === definition.url;
        });
        if (downloadedSource === undefined) {
          return this.buildPendingThirdPartyPresetRow(definition);
        }
        return this.buildRuleSourceRow(downloadedSource, true);
      });
    const customRows = sources
      .filter((item: AdBlockCustomRuleSource) => {
        return !this.isRemovedBuiltInRuleSourceId(item.id) && !isAdBlockThirdPartyRuleSourceId(item.id);
      })
      .map((item: AdBlockCustomRuleSource): AdBlockCustomRuleSourceRowView => {
        return this.buildRuleSourceRow(item, false);
      });
    return presetRows.concat(customRows);
  }

  private buildPendingThirdPartyPresetRow(
    definition: AdBlockThirdPartyRuleSourceDefinition
  ): AdBlockCustomRuleSourceRowView {
    return {
      id: definition.id,
      title: definition.title,
      url: definition.url,
      sourceType: 'remote',
      enabled: false,
      statusText: '尚未下载',
      detailText: definition.sourceHost,
      hasError: false,
      isSystem: false,
      isThirdPartyPreset: true,
      canRefresh: false,
      canRemove: false
    };
  }

  private buildRuleSourceRow(
    item: AdBlockCustomRuleSource,
    isThirdPartyPreset: boolean
  ): AdBlockCustomRuleSourceRowView {
    return {
      id: item.id,
      title: item.title,
      url: item.url,
      sourceType: item.sourceType,
      enabled: item.enabled,
      statusText: this.buildCustomRuleStatusText(item),
      detailText: this.buildCustomRuleDetailText(item),
      hasError: item.lastError.trim().length > 0,
      isSystem: this.isProtectedSystemSource(item),
      isThirdPartyPreset: isThirdPartyPreset,
      canRefresh: item.sourceType !== 'system' && item.ruleCount > 0,
      canRemove: item.sourceType !== 'system' && !isThirdPartyPreset
    };
  }

  private buildCustomRuleStatusText(source: AdBlockCustomRuleSource): string {
    if (source.lastError.trim().length > 0) {
      return source.lastError;
    }
    const networkRuleCount = source.nativeNetworkRuleCount ?? 0;
    const cosmeticRuleCount = source.nativeCosmeticRuleCount ?? 0;
    const ruleText = `${networkRuleCount} 条网络规则，${cosmeticRuleCount} 条外观与脚本规则`;
    if (source.lastUpdatedAt <= 0) {
      return ruleText;
    }
    return `${ruleText} · ${new Date(source.lastUpdatedAt).toLocaleDateString()}`;
  }

  private buildCustomRuleDetailText(source: AdBlockCustomRuleSource): string {
    if (this.isProtectedSystemSource(source)) {
      return '系统预置';
    }
    return source.url;
  }

  private isProtectedSystemSource(source: AdBlockCustomRuleSource): boolean {
    return source.sourceType === 'system';
  }

  private isRemovedBuiltInRuleSourceId(sourceId: string): boolean {
    return sourceId === BUILT_IN_AD_BLOCK_RULE_SOURCE_ID ||
      sourceId === SMOOTH_MODE_AD_BLOCK_RULE_SOURCE_ID ||
      sourceId === APP_PROMOTION_BANNER_RULE_SOURCE_ID;
  }
}
