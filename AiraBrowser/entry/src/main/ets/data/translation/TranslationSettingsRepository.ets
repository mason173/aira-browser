import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  TranslationProviderConfig,
  TranslationProviderStatus,
  TranslationProviderTemplateId,
  TranslationRule,
  TranslationRuleType,
  TranslationSettings,
  TranslationSettingsPreferences
} from '../../common/models/BrowserModels';

const PREFERENCES_NAME: string = 'aira_browser_translation';
const TRANSLATION_SETTINGS_KEY: string = 'translation_settings';
export const AIRA_SYSTEM_TRANSLATION_PROVIDER_ID: string = 'aira_system_translation';
const AIRA_SYSTEM_TRANSLATION_ENDPOINT: string = '';

export const DEFAULT_TRANSLATION_PREFERENCES: TranslationSettingsPreferences = {
  enabled: true,
  offerToTranslate: false,
  allowInPrivateTabs: false,
  preferredTargetLanguage: 'zh-CN',
  firstCloudDisclosureAcceptedAt: 0
};

export class TranslationSettingsRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: TranslationSettings = this.buildDefaultSettings();
  private initialized: boolean = false;
  private initializePromise?: Promise<TranslationSettings>;

  async initialize(): Promise<TranslationSettings> {
    if (this.initialized) {
      return this.getSettings();
    }
    if (this.initializePromise !== undefined) {
      return this.initializePromise;
    }
    this.initializePromise = this.loadSettingsFromStore();
    try {
      return await this.initializePromise;
    } finally {
      this.initializePromise = undefined;
    }
  }

  async ensureInitialized(): Promise<TranslationSettings> {
    return await this.initialize();
  }

  private async loadSettingsFromStore(): Promise<TranslationSettings> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(TRANSLATION_SETTINGS_KEY, ''));
    this.settings = this.normalizeSettings(this.parseSettings(rawSettings));
    if (rawSettings.trim().length === 0) {
      await this.persistSettings(this.settings);
    }
    this.initialized = true;
    return this.getSettings();
  }

  getSettings(): TranslationSettings {
    return this.cloneSettings(this.settings);
  }

  async preferAiraSystemProvider(): Promise<TranslationSettings> {
    await this.ensureInitialized();
    const normalizedSettings = this.normalizeSettings(this.settings);
    if (normalizedSettings.activeProviderId.length > 0) {
      this.settings = this.cloneSettings(normalizedSettings);
      return this.getSettings();
    }
    return this.persistSettings({
      preferences: this.clonePreferences(normalizedSettings.preferences),
      activeProviderId: AIRA_SYSTEM_TRANSLATION_PROVIDER_ID,
      providers: normalizedSettings.providers.map((item: TranslationProviderConfig) => this.cloneProvider(item)),
      rules: normalizedSettings.rules.map((item: TranslationRule) => this.cloneRule(item)),
      updatedAt: Date.now()
    });
  }

  async updatePreferences(preferences: TranslationSettingsPreferences): Promise<TranslationSettings> {
    await this.ensureInitialized();
    const nextSettings: TranslationSettings = {
      preferences: this.normalizePreferences(preferences),
      activeProviderId: this.settings.activeProviderId,
      providers: this.settings.providers.map((item: TranslationProviderConfig) => this.cloneProvider(item)),
      rules: this.settings.rules.map((item: TranslationRule) => this.cloneRule(item)),
      updatedAt: Date.now()
    };
    return this.persistSettings(nextSettings);
  }

  async saveProvider(provider: TranslationProviderConfig): Promise<TranslationSettings> {
    await this.ensureInitialized();
    const normalizedProvider = this.normalizeProvider(provider);
    if (normalizedProvider.id.length === 0) {
      throw new Error('翻译服务配置无效。');
    }
    const nextProviders = this.settings.providers
      .filter((item: TranslationProviderConfig) => item.id !== normalizedProvider.id)
      .concat(normalizedProvider);
    const nextSettings: TranslationSettings = {
      preferences: this.clonePreferences(this.settings.preferences),
      activeProviderId: normalizedProvider.id,
      providers: nextProviders,
      rules: this.settings.rules.map((item: TranslationRule) => this.cloneRule(item)),
      updatedAt: Date.now()
    };
    return this.persistSettings(this.normalizeSettings(nextSettings));
  }

  async setActiveProvider(providerId: string): Promise<TranslationSettings> {
    await this.ensureInitialized();
    const normalizedProviderId = providerId.trim();
    const hasProvider = this.settings.providers.some((item: TranslationProviderConfig) => item.id === normalizedProviderId);
    const nextSettings: TranslationSettings = {
      preferences: this.clonePreferences(this.settings.preferences),
      activeProviderId: hasProvider ? normalizedProviderId : '',
      providers: this.settings.providers.map((item: TranslationProviderConfig) => this.cloneProvider(item)),
      rules: this.settings.rules.map((item: TranslationRule) => this.cloneRule(item)),
      updatedAt: Date.now()
    };
    return this.persistSettings(nextSettings);
  }

  async replaceProviders(providers: TranslationProviderConfig[]): Promise<TranslationSettings> {
    await this.ensureInitialized();
    const normalizedProviders = this.normalizeProviders(providers);
    const hasActiveProvider = normalizedProviders.some((item: TranslationProviderConfig) => {
      return item.id === this.settings.activeProviderId;
    });
    const nextSettings: TranslationSettings = {
      preferences: this.clonePreferences(this.settings.preferences),
      activeProviderId: hasActiveProvider ? this.settings.activeProviderId : '',
      providers: normalizedProviders,
      rules: this.settings.rules.map((item: TranslationRule) => this.cloneRule(item)),
      updatedAt: Date.now()
    };
    return this.persistSettings(this.normalizeSettings(nextSettings));
  }

  async saveUserProvider(provider: TranslationProviderConfig): Promise<TranslationSettings> {
    await this.ensureInitialized();
    return this.saveProvider({
      id: provider.id.trim().length > 0 ? provider.id : this.buildUserProviderId(provider.templateId),
      templateId: provider.templateId,
      displayName: provider.displayName,
      endpoint: provider.endpoint,
      apiKey: provider.apiKey,
      appId: provider.appId,
      secretKey: provider.secretKey,
      region: provider.region,
      model: provider.model,
      optionsJson: provider.optionsJson,
      secretRefsJson: provider.secretRefsJson,
      status: provider.status,
      failureReason: provider.failureReason,
      updatedAt: Date.now()
    });
  }

  private normalizeSettings(value: TranslationSettings | undefined): TranslationSettings {
    const providers = this.ensureBuiltInProviders(this.normalizeProviders(value?.providers ?? []));
    const activeProviderId = (value?.activeProviderId ?? '').trim();
    const hasActiveProvider = providers.some((provider: TranslationProviderConfig) => provider.id === activeProviderId);
    const defaultProviderId = providers.some((provider: TranslationProviderConfig) => {
      return provider.id === AIRA_SYSTEM_TRANSLATION_PROVIDER_ID;
    }) ? AIRA_SYSTEM_TRANSLATION_PROVIDER_ID : '';
    return {
      preferences: this.normalizePreferences(value?.preferences),
      activeProviderId: hasActiveProvider ? activeProviderId : defaultProviderId,
      providers: providers,
      rules: this.normalizeRules(value?.rules ?? []),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizePreferences(value: TranslationSettingsPreferences | undefined): TranslationSettingsPreferences {
    return {
      enabled: typeof value?.enabled === 'boolean' ? value.enabled : DEFAULT_TRANSLATION_PREFERENCES.enabled,
      offerToTranslate: typeof value?.offerToTranslate === 'boolean'
        ? value.offerToTranslate
        : DEFAULT_TRANSLATION_PREFERENCES.offerToTranslate,
      allowInPrivateTabs: typeof value?.allowInPrivateTabs === 'boolean'
        ? value.allowInPrivateTabs
        : DEFAULT_TRANSLATION_PREFERENCES.allowInPrivateTabs,
      preferredTargetLanguage: this.normalizeLanguageCode(value?.preferredTargetLanguage) ||
        DEFAULT_TRANSLATION_PREFERENCES.preferredTargetLanguage,
      firstCloudDisclosureAcceptedAt: this.normalizeTimestamp(value?.firstCloudDisclosureAcceptedAt)
    };
  }

  private normalizeProviders(values: TranslationProviderConfig[]): TranslationProviderConfig[] {
    const results: TranslationProviderConfig[] = [];
    values.forEach((value: TranslationProviderConfig) => {
      if (!this.isKnownTemplateId(`${value.templateId ?? ''}`.trim())) {
        return;
      }
      const provider = this.normalizeProvider(value);
      if (provider.id.length > 0) {
        results.push(provider);
      }
    });
    return results;
  }

  private normalizeProvider(value: TranslationProviderConfig): TranslationProviderConfig {
    const templateId = this.normalizeTemplateId(value.templateId);
    return {
      id: (value.id ?? '').trim(),
      templateId: templateId,
      displayName: (value.displayName ?? this.buildTemplateLabel(templateId)).trim(),
      endpoint: (value.endpoint ?? '').trim(),
      apiKey: (value.apiKey ?? '').trim(),
      appId: (value.appId ?? '').trim(),
      secretKey: (value.secretKey ?? '').trim(),
      region: (value.region ?? '').trim(),
      model: (value.model ?? '').trim(),
      optionsJson: this.normalizeJsonString(value.optionsJson),
      secretRefsJson: this.normalizeJsonString(value.secretRefsJson),
      status: this.normalizeStatus(value.status),
      failureReason: (value.failureReason ?? '').trim(),
      updatedAt: this.normalizeTimestamp(value.updatedAt)
    };
  }

  private normalizeRules(values: TranslationRule[]): TranslationRule[] {
    const results: TranslationRule[] = [];
    values.forEach((value: TranslationRule) => {
      const rule = this.normalizeRule(value);
      if (rule.type === 'never_translate_site') {
        if (rule.host.length > 0) {
          results.push(rule);
        }
        return;
      }
      if (rule.languageCode.length > 0) {
        results.push(rule);
      }
    });
    return results;
  }

  private normalizeRule(value: TranslationRule): TranslationRule {
    return {
      type: this.normalizeRuleType(value.type),
      languageCode: this.normalizeLanguageCode(value.languageCode),
      host: this.normalizeHost(value.host),
      targetLanguageCode: this.normalizeLanguageCode(value.targetLanguageCode),
      createdAt: this.normalizeTimestamp(value.createdAt) || Date.now()
    };
  }

  private normalizeTemplateId(value: TranslationProviderTemplateId | undefined): TranslationProviderTemplateId {
    const candidate = `${value ?? ''}`.trim();
    if (this.isKnownTemplateId(candidate)) {
      return candidate as TranslationProviderTemplateId;
    }
    return 'custom_http';
  }

  private isKnownTemplateId(value: string): boolean {
    return value === 'aira_system' ||
      value === 'custom_http' ||
      value === 'deepl' ||
      value === 'google_cloud' ||
      value === 'tencent_cloud' ||
      value === 'baidu' ||
      value === 'microsoft' ||
      value === 'alibaba_cloud' ||
      value === 'volcano' ||
      value === 'youdao';
  }

  private normalizeStatus(value: TranslationProviderStatus | undefined): TranslationProviderStatus {
    const candidate = `${value ?? ''}`.trim();
    if (candidate === 'configured' || candidate === 'failed' || candidate === 'unavailable') {
      return candidate as TranslationProviderStatus;
    }
    return 'not_configured';
  }

  private normalizeRuleType(value: TranslationRuleType | undefined): TranslationRuleType {
    const candidate = `${value ?? ''}`.trim();
    if (candidate === 'always_translate_language' || candidate === 'never_translate_site') {
      return candidate as TranslationRuleType;
    }
    return 'never_translate_language';
  }

  private normalizeLanguageCode(value: string | undefined): string {
    return (value ?? '').trim();
  }

  private normalizeHost(value: string | undefined): string {
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

  private buildUserProviderId(templateId: TranslationProviderTemplateId): string {
    const existingProvider = this.settings.providers.find((item: TranslationProviderConfig) => {
      return item.templateId === templateId;
    });
    if (existingProvider !== undefined) {
      return existingProvider.id;
    }
    return `${templateId}_${Date.now()}`;
  }


  private normalizeJsonString(value: string | undefined): string {
    const candidate = (value ?? '').trim();
    if (candidate.length === 0) {
      return '{}';
    }
    try {
      JSON.parse(candidate);
      return candidate;
    } catch (_error) {
      return '{}';
    }
  }

  private buildTemplateLabel(templateId: TranslationProviderTemplateId): string {
    switch (templateId) {
      case 'aira_system':
        return 'Aira 系统翻译';
      case 'deepl':
        return 'DeepL';
      case 'google_cloud':
        return 'Google Cloud Translation';
      case 'tencent_cloud':
        return '腾讯云机器翻译';
      case 'baidu':
        return '百度翻译';
      case 'microsoft':
        return 'Microsoft Translator';
      case 'alibaba_cloud':
        return '阿里云机器翻译';
      case 'volcano':
        return '火山翻译';
      case 'youdao':
        return '有道智云';
      default:
        return '自定义接口';
    }
  }

  private parseSettings(value: string): TranslationSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as TranslationSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private buildDefaultSettings(): TranslationSettings {
    return {
      preferences: this.clonePreferences(DEFAULT_TRANSLATION_PREFERENCES),
      activeProviderId: AIRA_SYSTEM_TRANSLATION_PROVIDER_ID,
      providers: [this.buildAiraSystemProvider()],
      rules: [],
      updatedAt: 0
    };
  }

  private ensureBuiltInProviders(providers: TranslationProviderConfig[]): TranslationProviderConfig[] {
    const hasAiraSystemProvider = providers.some((provider: TranslationProviderConfig) => {
      return provider.id === AIRA_SYSTEM_TRANSLATION_PROVIDER_ID || provider.templateId === 'aira_system';
    });
    if (hasAiraSystemProvider) {
      return providers.map((provider: TranslationProviderConfig) => {
        if (provider.id === AIRA_SYSTEM_TRANSLATION_PROVIDER_ID || provider.templateId === 'aira_system') {
          return this.normalizeProvider({
            id: AIRA_SYSTEM_TRANSLATION_PROVIDER_ID,
            templateId: 'aira_system',
            displayName: 'Aira 系统翻译',
            endpoint: provider.endpoint.trim().length > 0 ? provider.endpoint : AIRA_SYSTEM_TRANSLATION_ENDPOINT,
            apiKey: '',
            appId: '',
            secretKey: '',
            region: 'ap-guangzhou',
            model: 'tencent_cloud',
            optionsJson: '{}',
            secretRefsJson: '{}',
            status: 'configured',
            failureReason: '',
            updatedAt: provider.updatedAt
          });
        }
        return provider;
      });
    }
    return [this.buildAiraSystemProvider()].concat(providers);
  }

  private buildAiraSystemProvider(): TranslationProviderConfig {
    return {
      id: AIRA_SYSTEM_TRANSLATION_PROVIDER_ID,
      templateId: 'aira_system',
      displayName: 'Aira 系统翻译',
      endpoint: AIRA_SYSTEM_TRANSLATION_ENDPOINT,
      apiKey: '',
      appId: '',
      secretKey: '',
      region: 'ap-guangzhou',
      model: 'tencent_cloud',
      optionsJson: '{}',
      secretRefsJson: '{}',
      status: 'configured',
      failureReason: '',
      updatedAt: 0
    };
  }

  private async persistSettings(settings: TranslationSettings): Promise<TranslationSettings> {
    this.settings = this.cloneSettings(settings);
    const store = await this.getStore();
    store.putSync(TRANSLATION_SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    this.initialized = true;
    return this.getSettings();
  }

  private cloneSettings(settings: TranslationSettings): TranslationSettings {
    return {
      preferences: this.clonePreferences(settings.preferences),
      activeProviderId: settings.activeProviderId,
      providers: settings.providers.map((item: TranslationProviderConfig) => this.cloneProvider(item)),
      rules: settings.rules.map((item: TranslationRule) => this.cloneRule(item)),
      updatedAt: settings.updatedAt
    };
  }

  private clonePreferences(value: TranslationSettingsPreferences): TranslationSettingsPreferences {
    return {
      enabled: value.enabled,
      offerToTranslate: value.offerToTranslate,
      allowInPrivateTabs: value.allowInPrivateTabs,
      preferredTargetLanguage: value.preferredTargetLanguage,
      firstCloudDisclosureAcceptedAt: value.firstCloudDisclosureAcceptedAt
    };
  }

  private cloneProvider(value: TranslationProviderConfig): TranslationProviderConfig {
    return {
      id: value.id,
      templateId: value.templateId,
      displayName: value.displayName,
      endpoint: value.endpoint,
      apiKey: value.apiKey,
      appId: value.appId,
      secretKey: value.secretKey,
      region: value.region,
      model: value.model,
      optionsJson: value.optionsJson,
      secretRefsJson: value.secretRefsJson,
      status: value.status,
      failureReason: value.failureReason,
      updatedAt: value.updatedAt
    };
  }

  private cloneRule(value: TranslationRule): TranslationRule {
    return {
      type: value.type,
      languageCode: value.languageCode,
      host: value.host,
      targetLanguageCode: value.targetLanguageCode,
      createdAt: value.createdAt
    };
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
