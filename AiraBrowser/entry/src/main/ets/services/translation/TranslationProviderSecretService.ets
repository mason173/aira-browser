import {
  TranslationProviderConfig,
  TranslationProviderTemplateId,
  TranslationSettings
} from '../../common/models/BrowserModels';
import { TranslationSettingsRepository } from '../../data/translation/TranslationSettingsRepository';
import { TranslationSecretStore } from '../../data/translation/TranslationSecretStore';

interface TranslationProviderSecretRefs {
  apiKey?: string;
  secretKey?: string;
}

export class TranslationProviderSecretService {
  private secretStore: TranslationSecretStore;

  constructor(secretStore: TranslationSecretStore) {
    this.secretStore = secretStore;
  }

  buildUserProviderId(
    settings: TranslationSettings,
    templateId: TranslationProviderTemplateId,
    providerId: string = ''
  ): string {
    const normalizedProviderId = providerId.trim();
    if (normalizedProviderId.length > 0) {
      return normalizedProviderId;
    }
    const existingProvider = settings.providers.find((item: TranslationProviderConfig) => {
      return item.templateId === templateId;
    });
    if (existingProvider !== undefined) {
      return existingProvider.id;
    }
    return `${templateId}_${Date.now()}`;
  }

  async secureProviderForSave(
    provider: TranslationProviderConfig,
    repository: TranslationSettingsRepository
  ): Promise<TranslationProviderConfig> {
    const providerId = this.buildUserProviderId(repository.getSettings(), provider.templateId, provider.id);
    const providerWithId = this.cloneProviderWithSecrets(provider, providerId, provider.apiKey, provider.secretKey);
    await this.saveProviderSecrets(providerWithId);
    return this.sanitizeProvider(providerWithId);
  }

  async resolveProviderSecrets(provider: TranslationProviderConfig): Promise<TranslationProviderConfig> {
    const refs = this.parseSecretRefs(provider.secretRefsJson);
    const apiKey = provider.apiKey.trim().length > 0
      ? provider.apiKey
      : await this.readSecret(refs.apiKey ?? '');
    const secretKey = provider.secretKey.trim().length > 0
      ? provider.secretKey
      : await this.readSecret(refs.secretKey ?? '');
    return this.cloneProviderWithSecrets(provider, provider.id, apiKey, secretKey);
  }

  async buildEditableProvider(provider: TranslationProviderConfig): Promise<TranslationProviderConfig> {
    return this.resolveProviderSecrets(provider);
  }

  async migratePlaintextSecrets(repository: TranslationSettingsRepository): Promise<void> {
    const settings = repository.getSettings();
    let changed = false;
    const providers: TranslationProviderConfig[] = [];
    for (let index = 0; index < settings.providers.length; index += 1) {
      const provider = settings.providers[index];
      if (!this.hasPlaintextSecret(provider)) {
        providers.push(provider);
        continue;
      }
      await this.saveProviderSecrets(provider);
      providers.push(this.sanitizeProvider(provider));
      changed = true;
    }
    if (changed) {
      await repository.replaceProviders(providers);
    }
  }

  private async saveProviderSecrets(provider: TranslationProviderConfig): Promise<void> {
    if (provider.apiKey.trim().length > 0) {
      await this.secretStore.saveSecret(this.buildAlias(provider.id, 'apiKey'), provider.apiKey);
    }
    if (provider.secretKey.trim().length > 0) {
      await this.secretStore.saveSecret(this.buildAlias(provider.id, 'secretKey'), provider.secretKey);
    }
  }

  private sanitizeProvider(provider: TranslationProviderConfig): TranslationProviderConfig {
    return {
      id: provider.id,
      templateId: provider.templateId,
      displayName: provider.displayName,
      endpoint: provider.endpoint,
      apiKey: '',
      appId: provider.appId,
      secretKey: '',
      region: provider.region,
      model: provider.model,
      optionsJson: provider.optionsJson,
      secretRefsJson: this.encodeSecretRefs(provider),
      status: provider.status,
      failureReason: provider.failureReason,
      updatedAt: provider.updatedAt
    };
  }

  private encodeSecretRefs(provider: TranslationProviderConfig): string {
    const refs: TranslationProviderSecretRefs = this.parseSecretRefs(provider.secretRefsJson);
    if (provider.apiKey.trim().length > 0) {
      refs.apiKey = this.buildAlias(provider.id, 'apiKey');
    }
    if (provider.secretKey.trim().length > 0) {
      refs.secretKey = this.buildAlias(provider.id, 'secretKey');
    }
    return JSON.stringify(refs);
  }

  private parseSecretRefs(value: string): TranslationProviderSecretRefs {
    try {
      const parsed = JSON.parse(value.length > 0 ? value : '{}') as TranslationProviderSecretRefs;
      return {
        apiKey: this.readString(parsed.apiKey),
        secretKey: this.readString(parsed.secretKey)
      };
    } catch (_error) {
      return {};
    }
  }

  private async readSecret(alias: string): Promise<string> {
    return alias.trim().length > 0 ? await this.secretStore.getSecret(alias) : '';
  }

  private hasPlaintextSecret(provider: TranslationProviderConfig): boolean {
    return provider.apiKey.trim().length > 0 || provider.secretKey.trim().length > 0;
  }

  private buildAlias(providerId: string, field: 'apiKey' | 'secretKey'): string {
    return `aira.translation.${providerId.trim()}.${field}`;
  }

  private cloneProviderWithSecrets(
    provider: TranslationProviderConfig,
    providerId: string,
    apiKey: string,
    secretKey: string
  ): TranslationProviderConfig {
    return {
      id: providerId,
      templateId: provider.templateId,
      displayName: provider.displayName,
      endpoint: provider.endpoint,
      apiKey: apiKey,
      appId: provider.appId,
      secretKey: secretKey,
      region: provider.region,
      model: provider.model,
      optionsJson: provider.optionsJson,
      secretRefsJson: provider.secretRefsJson,
      status: provider.status,
      failureReason: provider.failureReason,
      updatedAt: provider.updatedAt
    };
  }

  private readString(value: string | undefined): string {
    return (value ?? '').trim();
  }
}
