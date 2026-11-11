import {
  SEARCH_ENGINE_OPTIONS,
  SearchEngineId,
  SearchEngineOption,
  SearchEngineRecord,
  TabRecord
} from '../../common/models/BrowserModels';
import { resolveAddressInput } from '../../common/utils/UrlUtils';
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
    const address = resolveAddressInput(input);
    if (address.intent === 'empty') {
      return '';
    }

    if (address.intent === 'navigate') {
      return address.navigationUrl;
    }

    const searchEngineRecord = typeof searchEngine === 'string'
      ? availableSearchEngines.find((engine: SearchEngineRecord) => engine.id === searchEngine) ??
        SEARCH_ENGINE_OPTIONS.find((option: SearchEngineOption): boolean => option.id === searchEngine)
      : searchEngine;
    return this.searchEngineTemplateService.buildSearchUrl(address.submittedText, searchEngineRecord);
  }
}
