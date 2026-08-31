import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  TranslationProviderConfig,
  TranslationSettings
} from '../../common/models/BrowserModels';
import {
  WebpageTranslationApplyItem,
  WebpageTranslationExtractionResult,
  WebpageTranslationTextItem
} from '../../services/web/WebpageTranslationRuntimeModels';
import {
  WebpageTranslationCacheContext,
  WebpageTranslationPersistentCacheService
} from '../../services/translation/WebpageTranslationPersistentCacheService';

const WEBPAGE_TRANSLATION_CACHE_LOG_DOMAIN: number = 0x0000;
const WEBPAGE_TRANSLATION_CACHE_LOG_TAG: string = 'QFWebTranslateCache';

export interface WebpageTranslationCachePipelineStats {
  sourceCount: number;
  sourceChars: number;
  cacheHitCount: number;
  cacheHitChars: number;
  missedCount: number;
  missedChars: number;
}

export interface WebpageTranslationCachePipeline {
  sourceItems: WebpageTranslationTextItem[];
  cachedApplyItems: WebpageTranslationApplyItem[];
  missedSourceItems: WebpageTranslationTextItem[];
  stats: WebpageTranslationCachePipelineStats;
}

export class WebpageTranslationCacheCoordinator {
  private persistentCacheService: WebpageTranslationPersistentCacheService = new WebpageTranslationPersistentCacheService();

  buildRuntimeCacheNamespace(
    provider: TranslationProviderConfig | undefined,
    settings: TranslationSettings,
    sourceLanguage: string = ''
  ): string {
    return [
      this.buildProviderNamespacePart(provider),
      this.normalizeLanguagePart(sourceLanguage),
      this.normalizeLanguagePart(settings.preferences.preferredTargetLanguage),
      'v2'
    ].join(':');
  }

  buildPersistentCacheContext(
    provider: TranslationProviderConfig | undefined,
    sourceLanguage: string,
    settings: TranslationSettings
  ): WebpageTranslationCacheContext {
    return {
      providerNamespace: `${this.buildProviderNamespacePart(provider)}:v1`,
      sourceLanguage: sourceLanguage,
      targetLanguage: settings.preferences.preferredTargetLanguage
    };
  }

  async hydrateExtraction(
    extraction: WebpageTranslationExtractionResult,
    context: WebpageTranslationCacheContext
  ): Promise<WebpageTranslationExtractionResult> {
    const hydratedItems = await this.hydrateItems(extraction.items, context);
    const cacheHitCount = this.countCachedItems(hydratedItems);
    hilog.info(
      WEBPAGE_TRANSLATION_CACHE_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_CACHE_LOG_TAG,
      'hydrate extraction done mode=%{public}s items=%{public}d cacheHit=%{public}d uncached=%{public}d provider=%{public}s source=%{public}s target=%{public}s',
      extraction.diagnostics?.mode ?? '',
      hydratedItems.length,
      cacheHitCount,
      hydratedItems.length - cacheHitCount,
      context.providerNamespace,
      context.sourceLanguage,
      context.targetLanguage
    );
    return {
      url: extraction.url,
      lang: extraction.lang,
      title: extraction.title,
      items: hydratedItems,
      diagnostics: extraction.diagnostics
    };
  }

  async hydrateItems(
    items: WebpageTranslationTextItem[],
    context: WebpageTranslationCacheContext
  ): Promise<WebpageTranslationTextItem[]> {
    try {
      return await this.persistentCacheService.hydrateItems(items, context);
    } catch (error) {
      hilog.warn(
        WEBPAGE_TRANSLATION_CACHE_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_CACHE_LOG_TAG,
        'persistent translation cache hydrate failed error=%{public}s',
        this.stringifyError(error)
      );
      return items;
    }
  }

  async storeTranslations(
    sourceItems: WebpageTranslationTextItem[],
    translations: WebpageTranslationApplyItem[],
    context: WebpageTranslationCacheContext
  ): Promise<void> {
    try {
      await this.persistentCacheService.storeTranslations(sourceItems, translations, context);
      hilog.info(
        WEBPAGE_TRANSLATION_CACHE_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_CACHE_LOG_TAG,
        'store translations done sourceItems=%{public}d translations=%{public}d provider=%{public}s source=%{public}s target=%{public}s',
        sourceItems.length,
        translations.length,
        context.providerNamespace,
        context.sourceLanguage,
        context.targetLanguage
      );
    } catch (error) {
      hilog.warn(
        WEBPAGE_TRANSLATION_CACHE_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_CACHE_LOG_TAG,
        'persistent translation cache store failed error=%{public}s',
        this.stringifyError(error)
      );
    }
  }

  buildCachePipeline(items: WebpageTranslationTextItem[]): WebpageTranslationCachePipeline {
    const cachedApplyItems: WebpageTranslationApplyItem[] = [];
    const missedSourceItems: WebpageTranslationTextItem[] = [];
    let cacheHitChars = 0;
    let missedChars = 0;
    items.forEach((item: WebpageTranslationTextItem) => {
      const cachedText = item.cachedTranslatedText?.trim() ?? '';
      if (cachedText.length > 0) {
        cachedApplyItems.push({
          id: item.id,
          translatedText: cachedText
        });
        cacheHitChars += this.countItemChars([item]);
      } else {
        missedSourceItems.push(item);
        missedChars += this.countItemChars([item]);
      }
    });
    return {
      sourceItems: items,
      cachedApplyItems: cachedApplyItems,
      missedSourceItems: missedSourceItems,
      stats: {
        sourceCount: items.length,
        sourceChars: cacheHitChars + missedChars,
        cacheHitCount: cachedApplyItems.length,
        cacheHitChars: cacheHitChars,
        missedCount: missedSourceItems.length,
        missedChars: missedChars
      }
    };
  }

  countCachedItems(items: WebpageTranslationTextItem[]): number {
    let total = 0;
    items.forEach((item: WebpageTranslationTextItem) => {
      if ((item.cachedTranslatedText?.trim() ?? '').length > 0) {
        total += 1;
      }
    });
    return total;
  }

  private buildProviderNamespacePart(provider: TranslationProviderConfig | undefined): string {
    if (provider === undefined) {
      return 'none';
    }
    return `${provider.templateId}:${provider.id}:${provider.model}`;
  }

  private normalizeLanguagePart(value: string): string {
    const normalized = value.trim().toLowerCase();
    return normalized.length > 0 ? normalized : 'unknown';
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
}
