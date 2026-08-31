import { WebpageTranslationTextItem } from '../web/WebpageTranslationRuntimeModels';

interface WebpageTranslationLanguageDetection {
  language: string;
  signalCount: number;
  dominance: number;
  confidence: number;
  reliable: boolean;
  latinWordCount: number;
}

export interface WebpageTranslationLanguageInference {
  language: string;
  pageLanguage: string;
  textLanguage: string;
  confidence: number;
  signalCount: number;
  dominance: number;
  reliableTextDetection: boolean;
}

export class WebpageTranslationLanguageService {
  normalizeLanguageCode(value: string): string {
    const candidate = value.trim().toLowerCase().replace('_', '-');
    if (candidate.length === 0) {
      return '';
    }
    const hyphenIndex = candidate.indexOf('-');
    return hyphenIndex > 0 ? candidate.substring(0, hyphenIndex) : candidate;
  }

  inferLanguage(pageLanguage: string, items: WebpageTranslationTextItem[]): string {
    return this.inferLanguageWithConfidence(pageLanguage, items).language;
  }

  inferLanguageWithConfidence(pageLanguage: string, items: WebpageTranslationTextItem[]): WebpageTranslationLanguageInference {
    const normalizedPageLanguage = this.normalizeLanguageCode(pageLanguage);
    const textDetection = this.detectFromSample(items);
    if (normalizedPageLanguage.length === 0) {
      return this.buildInference(textDetection.language, normalizedPageLanguage, textDetection);
    }
    if (textDetection.language.length === 0) {
      return this.buildInference(normalizedPageLanguage, normalizedPageLanguage, textDetection, 0.35);
    }
    if (textDetection.language === normalizedPageLanguage) {
      return this.buildInference(normalizedPageLanguage, normalizedPageLanguage, textDetection, textDetection.confidence);
    }
    if (this.shouldPreferTextDetection(textDetection)) {
      return this.buildInference(textDetection.language, normalizedPageLanguage, textDetection);
    }
    return this.buildInference(normalizedPageLanguage, normalizedPageLanguage, textDetection, 0.4);
  }

  private detectFromSample(items: WebpageTranslationTextItem[]): WebpageTranslationLanguageDetection {
    let sample = '';
    const qualityItems = this.filterQualitySampleItems(items);
    for (let i = 0; i < qualityItems.length && sample.length < 1800; i++) {
      sample += ` ${qualityItems[i].text}`;
    }
    if (sample.trim().length === 0 && qualityItems.length !== items.length) {
      for (let i = 0; i < items.length && sample.length < 1200; i++) {
        sample += ` ${items[i].text}`;
      }
    }
    const normalizedSample = sample.trim();
    if (normalizedSample.length === 0) {
      return this.buildDetection('', 0, 0, 0);
    }

    const cjkCount = this.countMatches(normalizedSample, /[\u4e00-\u9fff]/g);
    const kanaCount = this.countMatches(normalizedSample, /[\u3040-\u30ff]/g);
    const hangulCount = this.countMatches(normalizedSample, /[\uac00-\ud7af]/g);
    const latinCount = this.countMatches(normalizedSample, /[A-Za-z\u00C0-\u024F]/g);
    const latinWordCount = this.countMatches(normalizedSample, /[A-Za-z\u00C0-\u024F]{2,}/g);
    const signalTotal = cjkCount + kanaCount + hangulCount + latinCount;

    if (signalTotal <= 0) {
      return this.buildDetection('', 0, 0, latinWordCount);
    }
    if (hangulCount >= 8 && this.isReliableNonLatinDetection(hangulCount, signalTotal)) {
      return this.buildDetection('ko', hangulCount, signalTotal, latinWordCount);
    }
    if (kanaCount >= 6 && this.isReliableNonLatinDetection(kanaCount + cjkCount, signalTotal)) {
      return this.buildDetection('ja', kanaCount + cjkCount, signalTotal, latinWordCount);
    }
    if (cjkCount >= 12 && this.isReliableNonLatinDetection(cjkCount, signalTotal)) {
      return this.buildDetection('zh', cjkCount, signalTotal, latinWordCount);
    }
    if (latinCount >= 80 && latinWordCount >= 8) {
      return this.buildDetection('en', latinCount, signalTotal, latinWordCount);
    }
    if (latinCount >= 36 && latinWordCount >= 5 && latinCount / signalTotal >= 0.72) {
      return this.buildDetection('en', latinCount, signalTotal, latinWordCount);
    }
    return this.buildDetection('', 0, signalTotal, latinWordCount);
  }

  private shouldPreferTextDetection(detection: WebpageTranslationLanguageDetection): boolean {
    return detection.reliable;
  }

  private filterQualitySampleItems(items: WebpageTranslationTextItem[]): WebpageTranslationTextItem[] {
    const filtered = items.filter((item: WebpageTranslationTextItem): boolean => {
      const text = item.text.trim();
      const score = item.score ?? 0;
      return text.length >= 24 || score >= 30;
    });
    return filtered.length > 0 ? filtered : items;
  }

  private isReliableNonLatinDetection(signalCount: number, signalTotal: number): boolean {
    return signalCount >= 24 || signalCount / signalTotal >= 0.5;
  }

  private buildDetection(
    language: string,
    signalCount: number,
    signalTotal: number,
    latinWordCount: number
  ): WebpageTranslationLanguageDetection {
    const dominance = signalTotal <= 0 ? 0 : signalCount / signalTotal;
    const reliable = language.length > 0 &&
      signalCount >= 24 &&
      dominance >= (language === 'en' ? 0.72 : 0.45);
    return {
      language: language,
      signalCount: signalCount,
      dominance: dominance,
      confidence: reliable ? Math.min(0.98, Math.max(0.72, dominance)) : 0,
      reliable: reliable,
      latinWordCount: latinWordCount
    };
  }

  private buildInference(
    language: string,
    pageLanguage: string,
    detection: WebpageTranslationLanguageDetection,
    confidenceOverride?: number
  ): WebpageTranslationLanguageInference {
    return {
      language: language,
      pageLanguage: pageLanguage,
      textLanguage: detection.language,
      confidence: confidenceOverride ?? detection.confidence,
      signalCount: detection.signalCount,
      dominance: detection.dominance,
      reliableTextDetection: detection.reliable
    };
  }

  private countMatches(value: string, pattern: RegExp): number {
    const matches = value.match(pattern);
    return matches === null ? 0 : matches.length;
  }
}
