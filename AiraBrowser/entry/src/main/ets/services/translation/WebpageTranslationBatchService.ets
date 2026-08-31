import {
  WebpageTranslationApplyItem,
  WebpageTranslationTextItem
} from '../web/WebpageTranslationRuntimeModels';
import { TranslationProviderConfig } from '../../common/models/BrowserModels';
import { TranslationProviderRequestService } from './TranslationProviderRequestService';
import {
  TranslationProviderError,
  TranslationProviderFailureClassifierService
} from './TranslationProviderFailureClassifierService';
import { TranslationSecretStore } from '../../data/translation/TranslationSecretStore';
import { TranslationProviderSecretService } from './TranslationProviderSecretService';

export class WebpageTranslationBatchService {
  private providerRequestService: TranslationProviderRequestService = new TranslationProviderRequestService();
  private failureClassifier: TranslationProviderFailureClassifierService =
    new TranslationProviderFailureClassifierService();
  private secretService?: TranslationProviderSecretService;

  constructor(secretStore?: TranslationSecretStore) {
    if (secretStore !== undefined) {
      this.secretService = new TranslationProviderSecretService(secretStore);
    }
  }

  cancelActiveRequests(): void {
    this.providerRequestService.cancelActiveRequests();
  }

  async translateBatch(
    provider: TranslationProviderConfig | undefined,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): Promise<WebpageTranslationApplyItem[]> {
    if (provider === undefined || provider.status !== 'configured') {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'missing_provider',
        '当前没有可用的翻译服务。'
      ));
    }
    if (!this.providerRequestService.supportsProvider(provider.templateId)) {
      throw new TranslationProviderError(this.failureClassifier.buildFailure(
        'missing_provider',
        '当前服务商接口尚未接入。'
      ));
    }
    const resolvedProvider = this.secretService === undefined
      ? provider
      : await this.secretService.resolveProviderSecrets(provider);
    return this.providerRequestService.translateBatch(
      resolvedProvider,
      items,
      sourceLanguage,
      targetLanguage
    );
  }
}
