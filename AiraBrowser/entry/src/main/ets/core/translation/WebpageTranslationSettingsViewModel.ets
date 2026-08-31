import {
  TranslationProviderConfig,
  TranslationProviderTemplateId,
  TranslationSettings,
  TranslationSettingsPreferences
} from '../../common/models/BrowserModels';
import { TranslationProviderTemplateService } from '../../services/translation/TranslationProviderTemplateService';

export interface TranslationProviderRowView {
  id: string;
  templateId: TranslationProviderTemplateId;
  title: string;
  subtitle: string;
  statusText: string;
  isActive: boolean;
  isConfigured: boolean;
  requiresPro: boolean;
  isEditable: boolean;
}

export interface TranslationLanguageOptionView {
  code: string;
  label: string;
  helperText: string;
}

export interface WebpageTranslationSettingsViewState {
  enabled: boolean;
  allowInPrivateTabs: boolean;
  preferredTargetLanguage: string;
  preferredTargetLanguageLabel: string;
  targetLanguageDescription: string;
  targetLanguageSheetHelperText: string;
  targetLanguageOptions: TranslationLanguageOptionView[];
  providerStatusText: string;
  hasActiveProvider: boolean;
  providers: TranslationProviderRowView[];
}

export class WebpageTranslationSettingsViewModel {
  private templateService: TranslationProviderTemplateService = new TranslationProviderTemplateService();

  buildState(settings: TranslationSettings): WebpageTranslationSettingsViewState {
    const activeProvider = this.resolveActiveProvider(settings);
    const preferredTargetLanguage = this.normalizePreferredTargetLanguageForProvider(
      activeProvider,
      settings.preferences.preferredTargetLanguage
    );
    return {
      enabled: settings.preferences.enabled,
      allowInPrivateTabs: settings.preferences.allowInPrivateTabs,
      preferredTargetLanguage: preferredTargetLanguage,
      preferredTargetLanguageLabel: this.buildLanguageLabel(preferredTargetLanguage),
      targetLanguageDescription: this.buildTargetLanguageDescription(),
      targetLanguageSheetHelperText: this.buildTargetLanguageSheetHelperText(),
      targetLanguageOptions: this.buildTargetLanguageOptions(),
      providerStatusText: this.buildProviderStatusText(activeProvider),
      hasActiveProvider: activeProvider !== undefined && activeProvider.status === 'configured',
      providers: this.buildProviderRows(settings)
    };
  }

  private buildProviderRows(settings: TranslationSettings): TranslationProviderRowView[] {
    const rows: TranslationProviderRowView[] = settings.providers.map((provider: TranslationProviderConfig): TranslationProviderRowView => {
      return {
        id: provider.id,
        templateId: provider.templateId,
        title: provider.displayName,
        subtitle: this.buildProviderSubtitle(provider),
        statusText: this.buildProviderStatusText(provider),
        isActive: provider.id === settings.activeProviderId,
        isConfigured: provider.status === 'configured',
        requiresPro: this.templateService.findTemplate(provider.templateId).requiresPro,
        isEditable: !this.templateService.findTemplate(provider.templateId).builtIn
      };
    });
    const configuredTemplateIds: string[] = rows.map((row: TranslationProviderRowView) => row.templateId);
    this.templateService.listConfigurableTemplates().forEach((template) => {
      if (configuredTemplateIds.indexOf(template.id) >= 0) {
        return;
      }
      rows.push({
        id: `template_${template.id}`,
        templateId: template.id,
        title: template.displayName,
        subtitle: template.id === 'custom_http' ? '需要填写 HTTPS Endpoint' : '需要填写 API 凭据',
        statusText: '未配置',
        isActive: false,
        isConfigured: false,
        requiresPro: template.requiresPro,
        isEditable: !template.builtIn
      });
    });
    return this.sortProviderRows(rows);
  }

  private sortProviderRows(rows: TranslationProviderRowView[]): TranslationProviderRowView[] {
    return rows.slice().sort((left: TranslationProviderRowView, right: TranslationProviderRowView): number => {
      return this.resolveProviderRowOrder(left) - this.resolveProviderRowOrder(right);
    });
  }

  private resolveProviderRowOrder(row: TranslationProviderRowView): number {
    if (row.templateId === 'aira_system') {
      return 0;
    }
    if (row.templateId === 'custom_http') {
      return 200;
    }
    return 100;
  }

  buildPreferencesPatch(
    current: TranslationSettingsPreferences,
    key: 'enabled' | 'allowInPrivateTabs' | 'preferredTargetLanguage',
    value: boolean | string | number
  ): TranslationSettingsPreferences {
    return {
      enabled: key === 'enabled' && typeof value === 'boolean' ? value : current.enabled,
      offerToTranslate: current.offerToTranslate,
      allowInPrivateTabs: key === 'allowInPrivateTabs' && typeof value === 'boolean'
        ? value
        : current.allowInPrivateTabs,
      preferredTargetLanguage: key === 'preferredTargetLanguage' && typeof value === 'string'
        ? value
        : current.preferredTargetLanguage,
      firstCloudDisclosureAcceptedAt: current.firstCloudDisclosureAcceptedAt
    };
  }

  private resolveActiveProvider(settings: TranslationSettings): TranslationProviderConfig | undefined {
    return settings.providers.find((provider: TranslationProviderConfig) => provider.id === settings.activeProviderId);
  }

  private buildProviderStatusText(provider: TranslationProviderConfig | undefined): string {
    if (provider === undefined) {
      return '未配置';
    }
    if (provider.status === 'configured') {
      return '已配置';
    }
    if (provider.status === 'failed') {
      return provider.failureReason.length > 0 ? `失败：${provider.failureReason}` : '配置失败';
    }
    if (provider.status === 'unavailable') {
      return provider.failureReason.length > 0 ? `不可用：${provider.failureReason}` : '不可用';
    }
    return '未完成配置';
  }

  private buildProviderSubtitle(provider: TranslationProviderConfig): string {
    if (provider.templateId === 'aira_system') {
      return '由 Aira 系统翻译服务提供';
    }
    if (provider.status === 'configured') {
      return '已填写 API 凭据';
    }
    return this.templateService.buildTemplateLabel(provider.templateId);
  }

  buildLanguageLabel(languageCode: string): string {
    switch (languageCode) {
      case 'zh-CN':
        return '简体中文';
      case 'zh-TW':
        return '繁体中文';
      case 'en':
        return 'English';
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      default:
        return languageCode.trim().length > 0 ? languageCode : '简体中文';
    }
  }

  isTargetLanguageSupportedByProvider(
    _provider: TranslationProviderConfig | undefined,
    _languageCode: string
  ): boolean {
    return true;
  }

  normalizePreferredTargetLanguageForProvider(
    _provider: TranslationProviderConfig | undefined,
    languageCode: string
  ): string {
    return languageCode.trim().length > 0 ? languageCode : 'zh-CN';
  }

  private buildTargetLanguageDescription(): string {
    return '手动翻译网页时默认使用此语言';
  }

  buildTargetLanguageSheetHelperText(): string {
    return '多语言能力由当前服务商提供，实际可用语种以服务商为准。';
  }

  buildTargetLanguageOptions(): TranslationLanguageOptionView[] {
    return [
      { code: 'zh-CN', label: '简体中文', helperText: 'Chinese Simplified' },
      { code: 'zh-TW', label: '繁体中文', helperText: 'Chinese Traditional' },
      { code: 'en', label: 'English', helperText: '英语' },
      { code: 'ja', label: '日本語', helperText: '日语' },
      { code: 'ko', label: '한국어', helperText: '韩语' },
      { code: 'fr', label: 'Français', helperText: '法语' },
      { code: 'de', label: 'Deutsch', helperText: '德语' },
      { code: 'es', label: 'Español', helperText: '西班牙语' },
      { code: 'pt', label: 'Português', helperText: '葡萄牙语' },
      { code: 'ru', label: 'Русский', helperText: '俄语' }
    ];
  }
}
