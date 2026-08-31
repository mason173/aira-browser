import {
  DEFAULT_SEARCH_ENGINE_ID,
  SEARCH_ENGINE_OPTIONS,
  SearchEngineId,
  SearchEngineOption,
  SearchEngineRecord
} from '../../common/models/BrowserModels';
import { looksLikeUrl, normalizeUrl } from '../../common/utils/UrlUtils';

export interface SearchEngineTemplateValidationResult {
  valid: boolean;
  normalizedTemplate: string;
  homepageUrl: string;
  suggestedName: string;
  errorMessage: string;
}

const SEARCH_TERMS_PLACEHOLDER: string = '{searchTerms}';
const LEGACY_SEARCH_PLACEHOLDER: string = '%s';
const CUSTOM_SEARCH_ENGINE_ID_PREFIX: string = 'custom_';

export class SearchEngineTemplateService {
  normalizeTemplate(template: string): string {
    return template.trim().replaceAll(LEGACY_SEARCH_PLACEHOLDER, SEARCH_TERMS_PLACEHOLDER);
  }

  validateTemplate(template: string): SearchEngineTemplateValidationResult {
    const normalizedTemplate = this.normalizeTemplate(template);
    if (normalizedTemplate.length === 0) {
      return this.buildInvalidResult(normalizedTemplate, '请输入搜索 URL。');
    }
    if (!normalizedTemplate.includes(SEARCH_TERMS_PLACEHOLDER)) {
      return this.buildInvalidResult(normalizedTemplate, '搜索 URL 需要包含 {searchTerms}。');
    }
    if (this.countPlaceholder(normalizedTemplate) !== 1) {
      return this.buildInvalidResult(normalizedTemplate, '搜索 URL 只能包含一个 {searchTerms}。');
    }
    const probeUrl = normalizedTemplate.replace(SEARCH_TERMS_PLACEHOLDER, 'aira');
    if (!this.isHttpUrl(probeUrl)) {
      return this.buildInvalidResult(normalizedTemplate, '请输入 http 或 https 开头的完整 URL。');
    }
    return {
      valid: true,
      normalizedTemplate: normalizedTemplate,
      homepageUrl: this.resolveHomepageUrl(probeUrl),
      suggestedName: this.resolveSuggestedName(probeUrl),
      errorMessage: ''
    };
  }

  buildSearchUrl(query: string, engine: SearchEngineRecord | SearchEngineOption | undefined): string {
    const trimmedQuery = query.trim();
    if (trimmedQuery.length === 0) {
      return '';
    }
    const template = this.resolveTemplate(engine);
    return template.replace(SEARCH_TERMS_PLACEHOLDER, encodeURIComponent(trimmedQuery));
  }

  normalizeEngineId(value: SearchEngineId | string | undefined, availableEngines: SearchEngineRecord[]): SearchEngineId {
    const candidate = (value ?? '').trim();
    if (availableEngines.some((engine: SearchEngineRecord) => engine.id === candidate)) {
      return candidate;
    }
    return DEFAULT_SEARCH_ENGINE_ID;
  }

  buildCustomEngineId(name: string, now: number = Date.now()): string {
    const compactName = name.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    const suffix = compactName.length > 0 ? compactName : 'engine';
    return `${CUSTOM_SEARCH_ENGINE_ID_PREFIX}${suffix}_${now}`;
  }

  isBuiltInEngineId(engineId: string): boolean {
    return SEARCH_ENGINE_OPTIONS.some((option: SearchEngineOption) => option.id === engineId);
  }

  private resolveTemplate(engine: SearchEngineRecord | SearchEngineOption | undefined): string {
    const template = engine?.searchUrlTemplate?.trim() ?? '';
    if (template.length > 0) {
      return this.normalizeTemplate(template);
    }
    return SEARCH_ENGINE_OPTIONS.find((option: SearchEngineOption) => option.id === DEFAULT_SEARCH_ENGINE_ID)?.searchUrlTemplate ??
      'https://www.bing.com/search?q={searchTerms}';
  }

  private countPlaceholder(template: string): number {
    return template.split(SEARCH_TERMS_PLACEHOLDER).length - 1;
  }

  private isHttpUrl(value: string): boolean {
    if (!looksLikeUrl(value)) {
      return false;
    }
    const normalized = normalizeUrl(value);
    const lower = normalized.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  private resolveHomepageUrl(value: string): string {
    const normalized = normalizeUrl(value);
    const schemeEnd = normalized.indexOf('://');
    if (schemeEnd <= 0) {
      return '';
    }
    const pathStart = normalized.indexOf('/', schemeEnd + 3);
    if (pathStart < 0) {
      return normalized;
    }
    return normalized.substring(0, pathStart);
  }

  resolveSuggestedName(template: string): string {
    const normalizedTemplate = this.normalizeTemplate(template);
    const probeUrl = normalizedTemplate.includes(SEARCH_TERMS_PLACEHOLDER)
      ? normalizedTemplate.replace(SEARCH_TERMS_PLACEHOLDER, 'aira')
      : normalizedTemplate;
    const homepageUrl = this.resolveHomepageUrl(probeUrl);
    const schemeEnd = homepageUrl.indexOf('://');
    if (schemeEnd <= 0) {
      return '';
    }
    const host = homepageUrl.substring(schemeEnd + 3).trim().toLowerCase();
    if (host.startsWith('www.') && host.length > 4) {
      return host.substring(4);
    }
    return host;
  }

  private buildInvalidResult(normalizedTemplate: string, errorMessage: string): SearchEngineTemplateValidationResult {
    return {
      valid: false,
      normalizedTemplate: normalizedTemplate,
      homepageUrl: '',
      suggestedName: '',
      errorMessage: errorMessage
    };
  }
}
