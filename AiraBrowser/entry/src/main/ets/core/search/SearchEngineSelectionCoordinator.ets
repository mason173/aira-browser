import {
  BrowserDataScope,
  SearchEngineId,
  SearchEngineRecord,
  SearchEngineSelectionScope
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { SearchEngineRepository } from '../../data/search/SearchEngineRepository';

export const SEARCH_ENGINE_NOT_AVAILABLE_ERROR: string = 'ENGINE_NOT_AVAILABLE';

export interface SearchEngineSelectionSnapshot {
  selectedSearchEngineId: SearchEngineId;
  selectionScope: SearchEngineSelectionScope;
  availableSearchEngines: SearchEngineRecord[];
}

export class SearchEngineSelectionCoordinator {
  private searchEngineRepository: SearchEngineRepository;
  private preferencesRepository: PreferencesRepository;
  private sessionSelectedSearchEngineId: SearchEngineId = '';

  constructor(
    searchEngineRepository: SearchEngineRepository,
    preferencesRepository: PreferencesRepository
  ) {
    this.searchEngineRepository = searchEngineRepository;
    this.preferencesRepository = preferencesRepository;
  }

  getSnapshot(dataScope: BrowserDataScope): SearchEngineSelectionSnapshot {
    const availableSearchEngines = this.searchEngineRepository.listEngines();
    const defaultSearchEngineId = this.searchEngineRepository.getDefaultEngine().id;
    const sessionEngineAvailable = this.sessionSelectedSearchEngineId.length > 0 &&
      availableSearchEngines.some((engine: SearchEngineRecord): boolean => {
        return engine.id === this.sessionSelectedSearchEngineId;
      });
    const sessionSelectionActive = dataScope === 'session_ephemeral' && sessionEngineAvailable;
    return {
      selectedSearchEngineId: sessionSelectionActive ? this.sessionSelectedSearchEngineId : defaultSearchEngineId,
      selectionScope: dataScope === 'session_ephemeral' ? 'session' : 'persistent',
      availableSearchEngines: availableSearchEngines
    };
  }

  handleBoundaryChange(
    previousDataScope: BrowserDataScope,
    nextDataScope: BrowserDataScope
  ): SearchEngineSelectionSnapshot {
    if (previousDataScope !== 'session_ephemeral' && nextDataScope === 'session_ephemeral') {
      this.sessionSelectedSearchEngineId = '';
    }
    return this.getSnapshot(nextDataScope);
  }

  async select(
    searchEngineId: SearchEngineId,
    dataScope: BrowserDataScope
  ): Promise<SearchEngineSelectionSnapshot> {
    const normalizedId = searchEngineId.trim();
    const target = this.searchEngineRepository.listEngines().find((engine: SearchEngineRecord): boolean => {
      return engine.id === normalizedId;
    });
    if (target === undefined) {
      throw new Error(SEARCH_ENGINE_NOT_AVAILABLE_ERROR);
    }
    if (dataScope === 'session_ephemeral') {
      this.sessionSelectedSearchEngineId = target.id;
      return this.getSnapshot(dataScope);
    }
    const settings = await this.searchEngineRepository.setDefaultEngine(target.id);
    await this.preferencesRepository.updateSearchEngine(settings.defaultSearchEngineId);
    return this.getSnapshot(dataScope);
  }
}
