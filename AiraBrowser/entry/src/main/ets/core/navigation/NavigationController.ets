import {
  DEFAULT_SEARCH_ENGINE_ID,
  SEARCH_ENGINE_OPTIONS,
  SearchEngineId,
  SearchEngineOption,
  SearchEngineRecord,
  TabRecord
} from '../../common/models/BrowserModels';
import { looksLikeUrl, normalizeAddressInputText, normalizeUrl } from '../../common/utils/UrlUtils';
import { SearchEngineTemplateService } from '../../services/search/SearchEngineTemplateService';

export class NavigationController {
  private searchEngineTemplateService: SearchEngineTemplateService = new SearchEngineTemplateService();

  getAddressBarValue(tab: TabRecord): string {
    return tab.url;
  }

  resolveAddressInput(
    input: string,
    searchEngine: SearchEngineId | SearchEngineRecord = 'bing',
    availableSearchEngines: SearchEngineRecord[] = []
  ): string {
    const trimmed: string = normalizeAddressInputText(input);
    if (trimmed.length === 0) {
      return '';
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('file://') ||
      looksLikeUrl(trimmed)) {
      return normalizeUrl(trimmed);
    }

    const searchEngineRecord = typeof searchEngine === 'string'
      ? availableSearchEngines.find((engine: SearchEngineRecord) => engine.id === searchEngine)
      : searchEngine;
    if (searchEngineRecord !== undefined) {
      return this.searchEngineTemplateService.buildSearchUrl(trimmed, searchEngineRecord);
    }

    const template: string = this.getSearchTemplate(String(searchEngine));
    return template.replace('{searchTerms}', encodeURIComponent(trimmed));
  }

  private getSearchTemplate(searchEngine: SearchEngineId): string {
    const matched = SEARCH_ENGINE_OPTIONS.find((option: SearchEngineOption): boolean => option.id === searchEngine);
    return matched?.searchUrlTemplate ??
      SEARCH_ENGINE_OPTIONS.find((option: SearchEngineOption): boolean => option.id === DEFAULT_SEARCH_ENGINE_ID)
        ?.searchUrlTemplate ??
      'https://www.bing.com/search?q={searchTerms}';
  }
}
