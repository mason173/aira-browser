import {
  SearchEngineId,
  SearchEngineRecord
} from '../../common/models/BrowserModels';

export class BrowserSearchEngineChromePresentation {
  selectedSearchEngine: SearchEngineId;
  searchEngines: SearchEngineRecord[];
  placeholder: string;

  constructor(
    selectedSearchEngine: SearchEngineId,
    searchEngines: SearchEngineRecord[],
    placeholder: string
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

  buildPlaceholder(_selectedSearchEngine: SearchEngineId, _availableSearchEngines: SearchEngineRecord[]): string {
    return '搜索或输入网址';
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

  resolveIcon(searchEngine: SearchEngineId): Resource {
    switch (searchEngine) {
      case 'google':
        return $r('app.media.search_engine_google');
      case 'duckduckgo':
        return $r('app.media.search_engine_duckduckgo');
      case 'baidu':
        return $r('app.media.search_engine_baidu');
      case 'bing':
      default:
        return $r('app.media.search_engine_bing');
    }
  }
}
