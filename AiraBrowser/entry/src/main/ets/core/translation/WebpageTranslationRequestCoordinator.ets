import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  TranslationProviderConfig
} from '../../common/models/BrowserModels';
import { TranslationSecretStore } from '../../data/translation/TranslationSecretStore';
import { TranslationProviderBatchPolicyService } from '../../services/translation/TranslationProviderBatchPolicyService';
import { WebpageTranslationBatchService } from '../../services/translation/WebpageTranslationBatchService';
import {
  WebpageTranslationApplyItem,
  WebpageTranslationTextItem
} from '../../services/web/WebpageTranslationRuntimeModels';

const AIRA_SYSTEM_TRANSLATION_BATCH_DELAY_MS: number = 300;
const WEBPAGE_TRANSLATION_REQUEST_LOG_DOMAIN: number = 0x0000;
const WEBPAGE_TRANSLATION_REQUEST_LOG_TAG: string = 'QFWebTranslateReq';

export interface WebpageTranslationBudgetBatch {
  items: WebpageTranslationTextItem[];
  charCount: number;
}

export class WebpageTranslationRequestCoordinator {
  private batchService: WebpageTranslationBatchService;
  private batchPolicyService: TranslationProviderBatchPolicyService = new TranslationProviderBatchPolicyService();

  constructor(secretStore?: TranslationSecretStore) {
    this.batchService = new WebpageTranslationBatchService(secretStore);
  }

  cancelActiveRequests(): void {
    this.batchService.cancelActiveRequests();
  }

  async translateBatch(
    provider: TranslationProviderConfig | undefined,
    items: WebpageTranslationTextItem[],
    sourceLanguage: string,
    targetLanguage: string
  ): Promise<WebpageTranslationApplyItem[]> {
    const requestedChars = this.countItemChars(items);
    try {
      const translations = await this.batchService.translateBatch(
        provider,
        items,
        sourceLanguage,
        targetLanguage
      );
      hilog.info(
        WEBPAGE_TRANSLATION_REQUEST_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_REQUEST_LOG_TAG,
        'provider request done chars=%{public}d translated=%{public}d provider=%{public}s source=%{public}s target=%{public}s',
        requestedChars,
        translations.length,
        provider?.templateId ?? 'none',
        sourceLanguage,
        targetLanguage
      );
      return translations;
    } catch (error) {
      hilog.warn(
        WEBPAGE_TRANSLATION_REQUEST_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_REQUEST_LOG_TAG,
        'provider request failed chars=%{public}d provider=%{public}s error=%{public}s',
        requestedChars,
        provider?.templateId ?? 'none',
        this.stringifyError(error)
      );
      throw this.normalizeThrowable(error);
    }
  }

  resolveBatchCharBudget(provider: TranslationProviderConfig | undefined): number {
    return this.batchPolicyService.resolvePolicy(provider).batchCharBudget;
  }

  resolveBatchItemGuard(provider: TranslationProviderConfig | undefined): number {
    return this.batchPolicyService.resolvePolicy(provider).batchItemGuard;
  }

  resolveInitialNodeLimit(provider: TranslationProviderConfig | undefined): number {
    return this.batchPolicyService.resolvePolicy(provider).initialNodeLimit;
  }

  resolveInitialCharLimit(provider: TranslationProviderConfig | undefined): number {
    return this.batchPolicyService.resolvePolicy(provider).initialCharLimit;
  }

  buildBudgetBatches(
    items: WebpageTranslationTextItem[],
    charBudget: number,
    itemGuard: number
  ): WebpageTranslationBudgetBatch[] {
    const batches: WebpageTranslationBudgetBatch[] = [];
    let currentItems: WebpageTranslationTextItem[] = [];
    let currentChars = 0;
    items.forEach((item: WebpageTranslationTextItem) => {
      const itemChars = this.countItemChars([item]);
      const shouldFlush = currentItems.length > 0 &&
        (currentItems.length >= itemGuard || currentChars + itemChars > charBudget);
      if (shouldFlush) {
        batches.push({
          items: currentItems,
          charCount: currentChars
        });
        currentItems = [];
        currentChars = 0;
      }
      currentItems.push(item);
      currentChars += itemChars;
    });
    if (currentItems.length > 0) {
      batches.push({
        items: currentItems,
        charCount: currentChars
      });
    }
    return batches;
  }

  async delayBetweenTranslationBatches(provider: TranslationProviderConfig | undefined): Promise<void> {
    if (provider?.templateId !== 'aira_system') {
      return;
    }
    await this.delay(AIRA_SYSTEM_TRANSLATION_BATCH_DELAY_MS);
  }

  private delay(durationMs: number): Promise<void> {
    return new Promise((resolve) => {
      setTimeout(resolve, durationMs);
    });
  }

  private countItemChars(items: WebpageTranslationTextItem[]): number {
    let total = 0;
    items.forEach((item: WebpageTranslationTextItem) => {
      const itemLength = item.charLength !== undefined && item.charLength > 0
        ? item.charLength
        : item.text.length;
      total += itemLength;
    });
    return total;
  }

  private stringifyError(error: Error | Object | string | number | boolean | undefined): string {
    if (error === undefined) {
      return 'unknown error';
    }
    if (error instanceof Error) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_error) {
      return `${error}`;
    }
  }

  private normalizeThrowable(error: Error | Object | string | number | boolean | undefined): Error {
    if (error instanceof Error) {
      return error;
    }
    return new Error(this.stringifyError(error));
  }
}
