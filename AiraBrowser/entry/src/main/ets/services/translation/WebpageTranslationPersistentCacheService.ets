import {
  WebpageTranslationCacheRecord,
  WebpageTranslationPersistentCacheRepository
} from '../../data/translation/WebpageTranslationPersistentCacheRepository';
import {
  WebpageTranslationApplyItem,
  WebpageTranslationTextItem
} from '../web/WebpageTranslationRuntimeModels';

export interface WebpageTranslationCacheContext {
  providerNamespace: string;
  sourceLanguage: string;
  targetLanguage: string;
}

export class WebpageTranslationPersistentCacheService {
  private repository: WebpageTranslationPersistentCacheRepository;

  constructor(repository: WebpageTranslationPersistentCacheRepository = new WebpageTranslationPersistentCacheRepository()) {
    this.repository = repository;
  }

  async hydrateItems(
    items: WebpageTranslationTextItem[],
    context: WebpageTranslationCacheContext
  ): Promise<WebpageTranslationTextItem[]> {
    const results: WebpageTranslationTextItem[] = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      const existingCachedText = item.cachedTranslatedText?.trim() ?? '';
      if (existingCachedText.length > 0) {
        results.push(item);
        continue;
      }
      const key = this.buildKey(context, item.text);
      const record = await this.repository.find(key);
      if (record !== undefined && this.isUsableRecord(record, item.text, context)) {
        results.push({
          id: item.id,
          text: item.text,
          cachedTranslatedText: record.translatedText,
          charLength: item.charLength,
          order: item.order,
          score: item.score,
          nearViewport: item.nearViewport,
          top: item.top
        });
      } else {
        results.push(item);
      }
    }
    return results;
  }

  async storeTranslations(
    sourceItems: WebpageTranslationTextItem[],
    translations: WebpageTranslationApplyItem[],
    context: WebpageTranslationCacheContext
  ): Promise<void> {
    if (translations.length === 0 || sourceItems.length === 0) {
      return;
    }
    const sourceById: Record<string, WebpageTranslationTextItem> = {};
    sourceItems.forEach((item: WebpageTranslationTextItem) => {
      sourceById[item.id] = item;
    });

    const now = Date.now();
    const records: WebpageTranslationCacheRecord[] = [];
    translations.forEach((translation: WebpageTranslationApplyItem) => {
      const item = sourceById[translation.id];
      const translatedText = translation.translatedText.trim();
      if (item === undefined || item.text.trim().length === 0 || translatedText.length === 0) {
        return;
      }
      records.push({
        key: this.buildKey(context, item.text),
        providerNamespace: this.normalizeNamespace(context.providerNamespace),
        sourceLanguage: this.normalizeLanguage(context.sourceLanguage),
        targetLanguage: this.normalizeLanguage(context.targetLanguage),
        sourceText: item.text,
        translatedText: translatedText,
        sourceHash: this.repository.buildSourceHash(item.text),
        updatedAt: now,
        lastUsedAt: now,
        useCount: 1,
        textChars: item.text.length + translatedText.length
      });
    });
    if (records.length > 0) {
      await this.repository.upsertMany(records);
    }
  }

  buildKey(context: WebpageTranslationCacheContext, sourceText: string): string {
    return this.repository.buildKey(
      context.providerNamespace,
      context.sourceLanguage,
      context.targetLanguage,
      sourceText
    );
  }

  private isUsableRecord(
    record: WebpageTranslationCacheRecord,
    sourceText: string,
    context: WebpageTranslationCacheContext
  ): boolean {
    return record.providerNamespace === this.normalizeNamespace(context.providerNamespace) &&
      record.sourceLanguage === this.normalizeLanguage(context.sourceLanguage) &&
      record.targetLanguage === this.normalizeLanguage(context.targetLanguage) &&
      record.sourceHash === this.repository.buildSourceHash(sourceText) &&
      record.translatedText.trim().length > 0;
  }

  private normalizeNamespace(value: string): string {
    return value.trim().toLowerCase();
  }

  private normalizeLanguage(value: string): string {
    return value.trim().toLowerCase();
  }
}
