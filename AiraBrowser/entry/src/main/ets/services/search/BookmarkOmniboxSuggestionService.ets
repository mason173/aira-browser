import { BookmarkSearchIndexStore } from '../../common/models/BookmarkSearchIndexModels';
import { BookmarkNode, BookmarkStorageScope, SearchSuggestion } from '../../common/models/BrowserModels';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';
import { matchBookmarkSuggestions } from './LocalOmniboxSuggestionMatcher';
import { DEFAULT_SEARCH_SUGGESTION_POLICY } from '../../features/search/SearchSuggestionPolicy';
import { BookmarkOmniboxIndex } from './BookmarkOmniboxIndex';

interface BookmarkOmniboxScopeState {
  generation: number;
  persistedRevision?: string;
  index?: BookmarkOmniboxIndex;
  pending?: Promise<boolean>;
  candidates?: BookmarkNode[];
  queryKey?: string;
  suggestions?: SearchSuggestion[];
}

/** Currency is decided by database revision checks, so yielding restores run to completion. */
function neverCancelBookmarkIndexLoad(): boolean {
  return false;
}

export class BookmarkOmniboxSuggestionService {
  private readonly repository: BookmarkRepository;
  private readonly indexStore?: BookmarkSearchIndexStore;
  private regularState?: BookmarkOmniboxScopeState;
  private privateState?: BookmarkOmniboxScopeState;
  private initializationPromise?: Promise<void>;

  constructor(repository: BookmarkRepository, indexStore?: BookmarkSearchIndexStore) {
    this.repository = repository;
    this.indexStore = indexStore;
  }

  buildSuggestions(
    query: string,
    scope: BookmarkStorageScope,
    limit: number = DEFAULT_SEARCH_SUGGESTION_POLICY.candidates.local
  ): SearchSuggestion[] {
    if (query.trim().length === 0 || limit <= 0) {
      return [];
    }
    const state = this.resolveState(scope);
    const queryKey = JSON.stringify([query, limit]);
    if (state.queryKey === queryKey && state.suggestions !== undefined) {
      return state.suggestions.slice();
    }
    let suggestions: SearchSuggestion[];
    if (state.index !== undefined) {
      suggestions = state.index.match(query, limit);
    } else if (!this.repository.isInitialized()) {
      // A cold seed cache is not an authoritative empty bookmark collection.
      return [];
    } else {
      const candidates = state.candidates ?? this.repository.listSuggestionCandidates(undefined, scope);
      if (this.indexStore === undefined) {
        this.startIndexBuild(state, candidates);
      }
      // Never wait for warmup to show a result: while the persisted index restores,
      // the initialized repository cache still answers and the loaded index
      // replaces these results on the next refresh after ensureLoaded.
      suggestions = matchBookmarkSuggestions(candidates, query, limit);
    }
    state.queryKey = queryKey;
    state.suggestions = suggestions;
    return suggestions.slice();
  }

  async ensureLoaded(scope: BookmarkStorageScope): Promise<boolean> {
    if (this.indexStore !== undefined) {
      return this.ensurePersistentLoaded(scope, this.indexStore);
    }
    const repositoryWasCold = !this.repository.isInitialized();
    if (repositoryWasCold) {
      await this.initializeRepository();
    }
    if (!this.repository.isInitialized()) {
      return false;
    }
    // A concurrent mutation may replace the snapshot while a yielding build is in progress.
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const state = this.resolveState(scope);
      if (state.index !== undefined) {
        return repositoryWasCold;
      }
      const loaded = await this.startIndexBuild(
        state, state.candidates ?? this.repository.listSuggestionCandidates(undefined, scope)
      );
      if (loaded || this.repository.getChangeGeneration() === state.generation) {
        return loaded;
      }
    }
    return false;
  }

  /** Restores the persisted snapshot once per launch; never initializes the repository from prewarm. */
  prewarm(scope: BookmarkStorageScope): Promise<boolean> {
    if (this.indexStore !== undefined) {
      // The persisted snapshot restores from the home prewarm, so the first explicit
      // search answers from the index instead of paying a cold rebuild.
      return this.ensureLoaded(scope).catch((_error: Error) => false);
    }
    return this.repository.isInitialized() ? this.ensureLoaded(scope) : Promise.resolve(false);
  }

  private async ensurePersistentLoaded(scope: BookmarkStorageScope, store: BookmarkSearchIndexStore): Promise<boolean> {
    const state = this.resolveState(scope);
    if (state.pending === undefined) {
      state.pending = this.loadPersistentState(scope, state, store)
        .finally(() => { state.pending = undefined; });
    }
    return state.pending;
  }

  private async loadPersistentState(
    scope: BookmarkStorageScope, state: BookmarkOmniboxScopeState, store: BookmarkSearchIndexStore
  ): Promise<boolean> {
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const revision = await store.readRevision();
      if (state.index !== undefined && state.persistedRevision === revision) {
        return false;
      }
      state.index = undefined;
      state.queryKey = undefined;
      state.suggestions = undefined;
      const next = new BookmarkOmniboxIndex();
      // A corrupt cache must never prevent a search against the authoritative records.
      // Repository cache churn (startup load, sync patches) does not move the database
      // revision, so only the revision checks below decide whether a result is current.
      const snapshot = await store.load(scope).catch((_error: Error) => undefined);
      if (snapshot !== undefined && await next.restoreChunksYielding(snapshot.chunks, neverCancelBookmarkIndexLoad) &&
        await store.readRevision() === snapshot.revision) {
        state.index = next;
        state.persistedRevision = snapshot.revision;
        return true;
      }
      const source = await store.readSource(scope);
      if (source === undefined) {
        continue;
      }
      if (await next.replaceRecordsYielding(source.records, neverCancelBookmarkIndexLoad) &&
        await store.readRevision() === source.revision) {
        state.index = next;
        state.persistedRevision = source.revision;
        // Publish first; durable serialization/write does not delay the current query.
        next.exportChunksYielding().then((chunks: string[]) => {
          return store.save(scope, source.revision, chunks);
        }).catch((_error: Error) => {});
        return true;
      }
    }
    return false;
  }

  private initializeRepository(): Promise<void> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.repository.initialize()
        .then(() => {
          this.initializationPromise = undefined;
        })
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw error;
        });
    }
    return this.initializationPromise;
  }

  private resolveState(scope: BookmarkStorageScope): BookmarkOmniboxScopeState {
    const generation = this.repository.getChangeGeneration();
    const current = scope === 'private' ? this.privateState : this.regularState;
    if (current !== undefined) {
      if (current.generation === generation) {
        return current;
      }
      if (current.persistedRevision !== undefined) {
        // A persisted index is anchored to the database revision, not the in-memory
        // cache generation: startup refreshes and sync patches must not discard it.
        // ensureLoaded revalidates the revision and reloads only when data moved.
        current.generation = generation;
        return current;
      }
    }
    const next: BookmarkOmniboxScopeState = { generation: generation };
    if (scope === 'private') {
      this.privateState = next;
    } else {
      this.regularState = next;
    }
    return next;
  }

  private startIndexBuild(state: BookmarkOmniboxScopeState, candidates: BookmarkNode[]): Promise<boolean> {
    if (state.pending !== undefined) {
      return state.pending;
    }
    state.candidates = candidates;
    const next = new BookmarkOmniboxIndex();
    state.pending = next.replaceYielding(
      candidates,
      (): boolean => this.repository.getChangeGeneration() !== state.generation
    ).then((loaded: boolean) => {
      state.pending = undefined;
      state.candidates = undefined;
      if (!loaded || this.repository.getChangeGeneration() !== state.generation) {
        return false;
      }
      state.index = next;
      return true;
    }).catch((_error: Error) => {
      state.pending = undefined;
      state.candidates = undefined;
      return false;
    });
    return state.pending;
  }
}
