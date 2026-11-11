import {
  DEFAULT_SEARCH_ENGINE_ID,
  SEARCH_ENGINE_OPTIONS,
  SearchEngineId,
  SearchEngineOption,
  SearchEngineRecord,
  SearchEngineResultPageShape
} from '../../common/models/BrowserModels';
import { normalizeUrl } from '../../common/utils/UrlUtils';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';

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
      return this.buildInvalidResult(normalizedTemplate, resolveAppResourceText($r('app.string.settings_search_engine_url_required')));
    }
    if (!normalizedTemplate.includes(SEARCH_TERMS_PLACEHOLDER)) {
      return this.buildInvalidResult(normalizedTemplate, resolveAppResourceText($r('app.string.settings_search_engine_url_needs_placeholder')));
    }
    if (this.countPlaceholder(normalizedTemplate) !== 1) {
      return this.buildInvalidResult(normalizedTemplate, resolveAppResourceText($r('app.string.settings_search_engine_url_one_placeholder')));
    }
    const probeUrl = normalizedTemplate.replace(SEARCH_TERMS_PLACEHOLDER, 'aira');
    if (!this.isHttpUrl(probeUrl)) {
      return this.buildInvalidResult(normalizedTemplate, resolveAppResourceText($r('app.string.settings_search_engine_url_scheme')));
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

  /**
   * The declared result-page shape of a built-in engine, or undefined when Aira has not verified one.
   *
   * The lookup is always keyed by an engine identity Aira already holds, never by URL inference, and custom engines
   * never declare a shape because Aira cannot verify how their own result page submits a search.
   */
  resolveResultPageShape(engineId: SearchEngineId): SearchEngineResultPageShape | undefined {
    const option = SEARCH_ENGINE_OPTIONS.find((candidate: SearchEngineOption): boolean => candidate.id === engineId);
    const shape = option?.resultPageShape;
    if (shape === undefined || shape.hosts.length === 0 || shape.pathSuffixes.length === 0 ||
      shape.queryKeys.length === 0) {
      return undefined;
    }
    return shape;
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
    if (/\s/.test(value.trim())) {
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
