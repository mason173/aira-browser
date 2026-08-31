import {
  TranslationProviderConfig,
  TranslationRule,
  TranslationSettings,
  TranslationSettingsPreferences
} from '../../common/models/BrowserModels';

export type WebpageTranslationManualPolicyBlockReason =
  'none' |
  'app_service_mode' |
  'private_tab' |
  'never_translate_site';

export type WebpageTranslationSourcePolicyBlockReason =
  'none' |
  'never_translate_site' |
  'never_translate_language';

export interface WebpageTranslationManualPolicyInput {
  settings: TranslationSettings;
  appServiceModeFull: boolean;
  privateMode: boolean;
  currentUrl?: string;
}

export interface WebpageTranslationManualPolicyDecision {
  allowed: boolean;
  requiresCloudDisclosure: boolean;
  provider: TranslationProviderConfig | undefined;
  message: string;
  blockReason: WebpageTranslationManualPolicyBlockReason;
}

export interface WebpageTranslationSourceLanguagePolicyInput {
  settings: TranslationSettings;
  sourceLanguage: string;
  currentUrl?: string;
}

export interface WebpageTranslationSourceLanguagePolicyDecision {
  allowed: boolean;
  targetLanguage: string;
  shouldAutoTranslate: boolean;
  message: string;
  blockReason: WebpageTranslationSourcePolicyBlockReason;
  matchedRule: TranslationRule | undefined;
}

export class WebpageTranslationPolicyService {
  resolveManualTranslationDecision(
    input: WebpageTranslationManualPolicyInput
  ): WebpageTranslationManualPolicyDecision {
    const provider = this.resolveActiveProvider(input.settings);
    if (!input.appServiceModeFull) {
      return this.buildManualDecision(
        false,
        false,
        provider,
        '网页翻译需切换到全量模式后使用。',
        'app_service_mode'
      );
    }
    if (input.privateMode && !input.settings.preferences.allowInPrivateTabs) {
      return this.buildManualDecision(
        false,
        false,
        provider,
        '隐私标签页未允许网页翻译，请先在网页翻译设置中开启。',
        'private_tab'
      );
    }
    if (this.findNeverTranslateSiteRule(input.settings, input.currentUrl) !== undefined) {
      return this.buildManualDecision(
        false,
        false,
        provider,
        '当前网站已设为不翻译。',
        'never_translate_site'
      );
    }
    return this.buildManualDecision(
      true,
      this.shouldConfirmCloudDisclosure(input.settings, provider),
      provider,
      '',
      'none'
    );
  }

  resolveSourceLanguageDecision(
    input: WebpageTranslationSourceLanguagePolicyInput
  ): WebpageTranslationSourceLanguagePolicyDecision {
    const siteRule = this.findNeverTranslateSiteRule(input.settings, input.currentUrl);
    if (siteRule !== undefined) {
      return this.buildSourceLanguageDecision(
        false,
        input.settings.preferences.preferredTargetLanguage,
        false,
        '当前网站已设为不翻译。',
        'never_translate_site',
        siteRule
      );
    }
    const normalizedLanguage = this.normalizeLanguageCode(input.sourceLanguage);
    const neverLanguageRule = this.findLanguageRule(input.settings, 'never_translate_language', normalizedLanguage);
    if (neverLanguageRule !== undefined) {
      return this.buildSourceLanguageDecision(
        false,
        input.settings.preferences.preferredTargetLanguage,
        false,
        '当前语言已设为不翻译。',
        'never_translate_language',
        neverLanguageRule
      );
    }
    const alwaysLanguageRule = this.findLanguageRule(input.settings, 'always_translate_language', normalizedLanguage);
    return this.buildSourceLanguageDecision(
      true,
      this.resolveRuleTargetLanguage(input.settings, alwaysLanguageRule),
      alwaysLanguageRule !== undefined,
      '',
      'none',
      alwaysLanguageRule
    );
  }

  resolveActiveProvider(settings: TranslationSettings): TranslationProviderConfig | undefined {
    const activeProviderId = settings.activeProviderId.trim();
    if (activeProviderId.length === 0) {
      return undefined;
    }
    return settings.providers.find((provider: TranslationProviderConfig): boolean => {
      return provider.id === activeProviderId;
    });
  }

  shouldConfirmCloudDisclosure(
    settings: TranslationSettings,
    provider?: TranslationProviderConfig
  ): boolean {
    const resolvedProvider = provider === undefined ? this.resolveActiveProvider(settings) : provider;
    return resolvedProvider !== undefined &&
      resolvedProvider.status === 'configured' &&
      settings.preferences.firstCloudDisclosureAcceptedAt <= 0;
  }

  buildCloudDisclosureProviderName(provider: TranslationProviderConfig | undefined): string {
    return provider?.displayName ?? '所选翻译服务';
  }

  buildCloudDisclosureAcceptedPreferences(
    current: TranslationSettingsPreferences,
    acceptedAt: number
  ): TranslationSettingsPreferences {
    return {
      enabled: current.enabled,
      offerToTranslate: current.offerToTranslate,
      allowInPrivateTabs: current.allowInPrivateTabs,
      preferredTargetLanguage: current.preferredTargetLanguage,
      firstCloudDisclosureAcceptedAt: acceptedAt
    };
  }

  private buildManualDecision(
    allowed: boolean,
    requiresCloudDisclosure: boolean,
    provider: TranslationProviderConfig | undefined,
    message: string,
    blockReason: WebpageTranslationManualPolicyBlockReason
  ): WebpageTranslationManualPolicyDecision {
    return {
      allowed: allowed,
      requiresCloudDisclosure: requiresCloudDisclosure,
      provider: provider,
      message: message,
      blockReason: blockReason
    };
  }

  private buildSourceLanguageDecision(
    allowed: boolean,
    targetLanguage: string,
    shouldAutoTranslate: boolean,
    message: string,
    blockReason: WebpageTranslationSourcePolicyBlockReason,
    matchedRule: TranslationRule | undefined
  ): WebpageTranslationSourceLanguagePolicyDecision {
    return {
      allowed: allowed,
      targetLanguage: targetLanguage,
      shouldAutoTranslate: shouldAutoTranslate,
      message: message,
      blockReason: blockReason,
      matchedRule: matchedRule
    };
  }

  private findNeverTranslateSiteRule(
    settings: TranslationSettings,
    currentUrl?: string
  ): TranslationRule | undefined {
    const currentHost = this.normalizeHost(currentUrl);
    if (currentHost.length === 0) {
      return undefined;
    }
    return settings.rules.find((rule: TranslationRule): boolean => {
      return rule.type === 'never_translate_site' && this.hostMatchesRule(currentHost, rule.host);
    });
  }

  private findLanguageRule(
    settings: TranslationSettings,
    type: 'always_translate_language' | 'never_translate_language',
    languageCode: string
  ): TranslationRule | undefined {
    const normalizedLanguage = this.normalizeLanguageCode(languageCode);
    if (normalizedLanguage.length === 0) {
      return undefined;
    }
    return settings.rules.find((rule: TranslationRule): boolean => {
      return rule.type === type && this.normalizeLanguageCode(rule.languageCode) === normalizedLanguage;
    });
  }

  private resolveRuleTargetLanguage(
    settings: TranslationSettings,
    rule: TranslationRule | undefined
  ): string {
    const ruleTargetLanguage = this.normalizeLanguageCode(rule?.targetLanguageCode);
    if (ruleTargetLanguage.length > 0) {
      return ruleTargetLanguage;
    }
    return settings.preferences.preferredTargetLanguage;
  }

  private hostMatchesRule(currentHost: string, ruleHost: string): boolean {
    const normalizedRuleHost = this.normalizeHost(ruleHost);
    return normalizedRuleHost.length > 0 &&
      (currentHost === normalizedRuleHost || currentHost.endsWith(`.${normalizedRuleHost}`));
  }

  private normalizeHost(value?: string): string {
    let candidate = (value ?? '').trim().toLowerCase();
    if (candidate.length === 0) {
      return '';
    }
    const schemeIndex = candidate.indexOf('://');
    if (schemeIndex >= 0) {
      candidate = candidate.substring(schemeIndex + 3);
    }
    const pathStart = candidate.indexOf('/');
    if (pathStart >= 0) {
      candidate = candidate.substring(0, pathStart);
    }
    const queryStart = candidate.indexOf('?');
    if (queryStart >= 0) {
      candidate = candidate.substring(0, queryStart);
    }
    const hashStart = candidate.indexOf('#');
    if (hashStart >= 0) {
      candidate = candidate.substring(0, hashStart);
    }
    const atIndex = candidate.lastIndexOf('@');
    if (atIndex >= 0) {
      candidate = candidate.substring(atIndex + 1);
    }
    const portStart = candidate.indexOf(':');
    if (portStart >= 0) {
      candidate = candidate.substring(0, portStart);
    }
    return candidate;
  }

  private normalizeLanguageCode(value?: string): string {
    return (value ?? '').trim().toLowerCase();
  }
}
