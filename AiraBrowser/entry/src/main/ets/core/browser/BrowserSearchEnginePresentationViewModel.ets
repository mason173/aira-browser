import {
  SearchEngineId,
  SearchEngineRecord
} from '../../common/models/BrowserModels';

export class BrowserSearchEngineChromePresentation {
  selectedSearchEngine: SearchEngineId;
  searchEngines: SearchEngineRecord[];
  placeholder: ResourceStr;

  constructor(
    selectedSearchEngine: SearchEngineId,
    searchEngines: SearchEngineRecord[],
    placeholder: ResourceStr
  ) {
    this.selectedSearchEngine = selectedSearchEngine;
    this.searchEngines = searchEngines.slice();
    this.placeholder = placeholder;
  }
}

export class BrowserSearchEnginePresentationViewModel {
  buildChromePresentation(
    selectedSearchEngine: SearchEngineId,
    availableSearchEngines: SearchEngineRecord[]
  ): BrowserSearchEngineChromePresentation {
    return new BrowserSearchEngineChromePresentation(
      selectedSearchEngine,
      availableSearchEngines,
      this.buildPlaceholder(selectedSearchEngine, availableSearchEngines)
    );
  }

  buildPlaceholder(_selectedSearchEngine: SearchEngineId, _availableSearchEngines: SearchEngineRecord[]): ResourceStr {
    return $r('app.string.aira_search_card_placeholder');
  }

  resolveName(searchEngine: SearchEngineId, availableSearchEngines: SearchEngineRecord[]): string {
    return this.resolveRecord(searchEngine, availableSearchEngines)?.name ?? 'Bing';
  }

  resolveRecord(
    searchEngine: SearchEngineId,
    availableSearchEngines: SearchEngineRecord[]
  ): SearchEngineRecord | undefined {
    return availableSearchEngines.find((item: SearchEngineRecord) => item.id === searchEngine);
  }
}
