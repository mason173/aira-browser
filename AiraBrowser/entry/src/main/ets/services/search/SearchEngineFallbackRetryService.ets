import {
  SearchEngineId,
  SearchEngineRecord,
  SearchEngineSettings
} from '../../common/models/BrowserModels';
import { SearchEngineTemplateService } from './SearchEngineTemplateService';

const SEARCH_TERMS_PLACEHOLDER: string = '{searchTerms}';
const LEGACY_SEARCH_PLACEHOLDER: string = '%s';
interface ParsedHttpUrl {
  host: string;
  path: string;
  query: string;
}

export interface SearchEngineFallbackRetryInput {
  failedUrl: string;
  settings: SearchEngineSettings;
  availableSearchEngines: SearchEngineRecord[];
}

export interface SearchEngineFallbackRetryAction {
  query: string;
  fallbackSearchUrl: string;
  primaryEngineId: SearchEngineId;
  primaryEngineName: string;
  fallbackEngineId: SearchEngineId;
  fallbackEngineName: string;
}

export class SearchEngineFallbackRetryService {
  private templateService: SearchEngineTemplateService = new SearchEngineTemplateService();

  buildRetryAction(input: SearchEngineFallbackRetryInput): SearchEngineFallbackRetryAction | undefined {
    const failedUrl = input.failedUrl.trim();
    if (failedUrl.length <= 0 || !input.settings.fallbackSearch.enabled) {
      return undefined;
    }
    const primaryEngine = this.findEngine(input.settings.defaultSearchEngineId, input.availableSearchEngines);
    const fallbackEngine = this.findEngine(input.settings.fallbackSearch.fallbackSearchEngineId,
      input.availableSearchEngines);
    if (primaryEngine === undefined || fallbackEngine === undefined || primaryEngine.id === fallbackEngine.id) {
      return undefined;
    }
    const query = this.extractSearchQuery(failedUrl, primaryEngine);
    if (query.length <= 0) {
      return undefined;
    }
    const fallbackSearchUrl = this.templateService.buildSearchUrl(query, fallbackEngine);
    if (fallbackSearchUrl.length <= 0) {
      return undefined;
    }
    return {
      query: query,
      fallbackSearchUrl: fallbackSearchUrl,
      primaryEngineId: primaryEngine.id,
      primaryEngineName: primaryEngine.name,
      fallbackEngineId: fallbackEngine.id,
      fallbackEngineName: fallbackEngine.name
    };
  }

  private extractSearchQuery(failedUrl: string, engine: SearchEngineRecord): string {
    const template = this.normalizeTemplate(engine.searchUrlTemplate);
    const templateParts = this.parseHttpUrl(template);
    const failedParts = this.parseHttpUrl(failedUrl);
    if (templateParts === undefined || failedParts === undefined) {
      return '';
    }
    if (!this.isSameHost(templateParts.host, failedParts.host) || !this.isSamePath(templateParts.path, failedParts.path)) {
      return '';
    }
    const searchParamName = this.resolveSearchParamName(templateParts.query);
    if (searchParamName.length > 0) {
      return this.readQueryParam(failedParts.query, searchParamName);
    }
    return this.extractByTemplateBoundaries(failedUrl, template);
  }

  private resolveSearchParamName(templateQuery: string): string {
    const pairs = templateQuery.split('&');
    for (let i = 0; i < pairs.length; i += 1) {
      const pair = pairs[i];
      const separatorIndex = pair.indexOf('=');
      if (separatorIndex < 0) {
        continue;
      }
      const value = pair.substring(separatorIndex + 1);
      if (value.indexOf(SEARCH_TERMS_PLACEHOLDER) >= 0) {
        return this.decodeQueryComponent(pair.substring(0, separatorIndex));
      }
    }
    return '';
  }

  private readQueryParam(query: string, name: string): string {
    const pairs = query.split('&');
    for (let i = 0; i < pairs.length; i += 1) {
      const pair = pairs[i];
      const separatorIndex = pair.indexOf('=');
      const rawName = separatorIndex >= 0 ? pair.substring(0, separatorIndex) : pair;
      if (this.decodeQueryComponent(rawName) !== name) {
        continue;
      }
      const rawValue = separatorIndex >= 0 ? pair.substring(separatorIndex + 1) : '';
      return this.decodeQueryComponent(rawValue).trim();
    }
    return '';
  }

  private extractByTemplateBoundaries(failedUrl: string, template: string): string {
    const marker = '__AIRA_SEARCH_TERMS__';
    const markerTemplate = template.replace(SEARCH_TERMS_PLACEHOLDER, marker);
    const markerIndex = markerTemplate.indexOf(marker);
    if (markerIndex < 0) {
      return '';
    }
    const prefix = markerTemplate.substring(0, markerIndex);
    const suffix = markerTemplate.substring(markerIndex + marker.length);
    if (!failedUrl.startsWith(prefix)) {
      return '';
    }
    const valueStart = prefix.length;
    const valueEnd = suffix.length > 0 ? failedUrl.indexOf(suffix, valueStart) : failedUrl.length;
    if (valueEnd < valueStart) {
      return '';
    }
    return this.decodeQueryComponent(failedUrl.substring(valueStart, valueEnd)).trim();
  }

  private parseHttpUrl(value: string): ParsedHttpUrl | undefined {
    const trimmed = value.trim();
    const schemeEnd = trimmed.indexOf('://');
    if (schemeEnd <= 0) {
      return undefined;
    }
    const scheme = trimmed.substring(0, schemeEnd).toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') {
      return undefined;
    }
    const rest = trimmed.substring(schemeEnd + 3);
    const hostEnd = this.findFirstIndex(rest, ['/', '?', '#']);
    const host = hostEnd >= 0 ? rest.substring(0, hostEnd) : rest;
    const afterHost = hostEnd >= 0 ? rest.substring(hostEnd) : '';
    const path = afterHost.startsWith('/') ? this.extractPath(afterHost) : '/';
    const query = this.extractQuery(afterHost);
    return {
      host: this.normalizeHost(host),
      path: this.normalizePath(path),
      query: query
    };
  }

  private extractPath(value: string): string {
    const queryIndex = value.indexOf('?');
    const hashIndex = value.indexOf('#');
    const end = this.resolvePositiveMin(queryIndex, hashIndex, value.length);
    return value.substring(0, end);
  }

  private extractQuery(value: string): string {
    const queryIndex = value.indexOf('?');
    if (queryIndex < 0) {
      return '';
    }
    const hashIndex = value.indexOf('#', queryIndex + 1);
    const end = hashIndex >= 0 ? hashIndex : value.length;
    return value.substring(queryIndex + 1, end);
  }

  private findFirstIndex(value: string, needles: string[]): number {
    let result = -1;
    for (let i = 0; i < needles.length; i += 1) {
      const index = value.indexOf(needles[i]);
      if (index >= 0 && (result < 0 || index < result)) {
        result = index;
      }
    }
    return result;
  }

  private resolvePositiveMin(left: number, right: number, fallback: number): number {
    if (left >= 0 && right >= 0) {
      return Math.min(left, right);
    }
    if (left >= 0) {
      return left;
    }
    if (right >= 0) {
      return right;
    }
    return fallback;
  }

  private normalizeTemplate(value: string): string {
    return value.trim().replaceAll(LEGACY_SEARCH_PLACEHOLDER, SEARCH_TERMS_PLACEHOLDER);
  }

  private normalizeHost(value: string): string {
    const withoutCredentials = value.trim().toLowerCase();
    const atIndex = withoutCredentials.lastIndexOf('@');
    const hostWithPort = atIndex >= 0 ? withoutCredentials.substring(atIndex + 1) : withoutCredentials;
    const colonIndex = hostWithPort.indexOf(':');
    const host = colonIndex >= 0 ? hostWithPort.substring(0, colonIndex) : hostWithPort;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  private normalizePath(value: string): string {
    const normalized = value.trim();
    if (normalized.length === 0) {
      return '/';
    }
    return normalized.endsWith('/') && normalized.length > 1 ? normalized.substring(0, normalized.length - 1) : normalized;
  }

  private isSameHost(left: string, right: string): boolean {
    return left.length > 0 && left === right;
  }

  private isSamePath(left: string, right: string): boolean {
    return this.normalizePath(left) === this.normalizePath(right);
  }

  private decodeQueryComponent(value: string): string {
    try {
      return decodeURIComponent(value.replace(/\+/g, '%20'));
    } catch (_error) {
      return value.replace(/\+/g, ' ');
    }
  }

  private findEngine(
    engineId: SearchEngineId,
    availableSearchEngines: SearchEngineRecord[]
  ): SearchEngineRecord | undefined {
    return availableSearchEngines.find((engine: SearchEngineRecord): boolean => engine.id === engineId);
  }
}
