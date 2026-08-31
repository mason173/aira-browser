import {
  BookmarkNode,
  BookmarkStorageScope
} from '../../common/models/BrowserModels';
import {
  AiraLocalBookmarkOverviewCacheRepository,
  AiraLocalBookmarkRootOverviewCacheEntry,
  AiraLocalBookmarkRootOverviewCacheSnapshot
} from '../../data/sync/AiraLocalBookmarkOverviewCacheRepository';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';
import { BookmarksFeature } from '../../features/bookmarks/BookmarksFeature';
import { BookmarkStatsVersionSignal } from '../bookmarks/BookmarkStatsVersionSignal';
import {
  BookmarkFolderOptionView,
  BookmarkFolderSelectionViewModel
} from './BookmarkFolderSelectionViewModel';

export class BookmarkFolderSelectionPreparationCoordinator {
  private repository: BookmarkRepository;
  private localOverviewRepository: AiraLocalBookmarkOverviewCacheRepository;
  private regularFeature: BookmarksFeature;
  private privateFeature: BookmarksFeature;
  private viewModel: BookmarkFolderSelectionViewModel = new BookmarkFolderSelectionViewModel();
  private regularOptions: BookmarkFolderOptionView[] = [];
  private privateOptions: BookmarkFolderOptionView[] = [];
  private regularOptionsStatsVersion: number = 0;
  private privateOptionsStatsVersion: number = 0;
  private regularPreparePromise?: Promise<BookmarkFolderOptionView[]>;
  private privatePreparePromise?: Promise<BookmarkFolderOptionView[]>;

  constructor(
    repository: BookmarkRepository,
    localOverviewRepository: AiraLocalBookmarkOverviewCacheRepository
  ) {
    this.repository = repository;
    this.localOverviewRepository = localOverviewRepository;
    this.regularFeature = new BookmarksFeature(repository, 'regular');
    this.privateFeature = new BookmarksFeature(repository, 'private');
  }

  getCachedOptions(scope: BookmarkStorageScope): BookmarkFolderOptionView[] {
    return this.resolveCachedOptions(scope).slice();
  }

  getResponsiveOptions(scope: BookmarkStorageScope): BookmarkFolderOptionView[] {
    const cachedOptions = this.resolveCachedOptions(scope);
    if (cachedOptions.length > 0) {
      return cachedOptions.slice();
    }
    return this.buildFastChildOptions(scope, '');
  }

  async prepare(scope: BookmarkStorageScope, forceRefresh: boolean = false): Promise<BookmarkFolderOptionView[]> {
    if (scope === 'private') {
      return this.preparePrivateOptions(forceRefresh);
    }
    return this.prepareRegularOptions(forceRefresh);
  }

  async prepareFolderPreview(
    scope: BookmarkStorageScope,
    parentId: string,
    currentOptions: BookmarkFolderOptionView[]
  ): Promise<BookmarkFolderOptionView[]> {
    const cachedOptions = this.resolveCachedOptions(scope);
    if (cachedOptions.length > 0) {
      return cachedOptions.slice();
    }
    const normalizedParentId = parentId.trim();
    const previewOptions = await this.buildPreviewChildOptions(scope, normalizedParentId);
    if (previewOptions.length <= 0) {
      return currentOptions.slice();
    }
    return this.mergePreviewOptions(currentOptions, previewOptions, normalizedParentId);
  }

  async prepareAll(forceRefresh: boolean = false): Promise<void> {
    await this.prepareRegularOptions(forceRefresh);
    await this.preparePrivateOptions(forceRefresh);
  }

  invalidate(scope?: BookmarkStorageScope): void {
    if (scope === undefined || scope === 'regular') {
      this.regularOptions = [];
      this.regularOptionsStatsVersion = 0;
      this.regularPreparePromise = undefined;
    }
    if (scope === undefined || scope === 'private') {
      this.privateOptions = [];
      this.privateOptionsStatsVersion = 0;
      this.privatePreparePromise = undefined;
    }
  }

  private async prepareRegularOptions(forceRefresh: boolean): Promise<BookmarkFolderOptionView[]> {
    const currentStatsVersion = BookmarkStatsVersionSignal.readVersion();
    if (!forceRefresh && this.regularOptions.length > 0 &&
      this.isPreparedOptionsFresh(this.regularOptionsStatsVersion, currentStatsVersion)) {
      return this.regularOptions.slice();
    }
    if (this.regularPreparePromise !== undefined) {
      return this.regularPreparePromise;
    }
    this.regularPreparePromise = this.buildPreparedOptions(this.regularFeature)
      .then((options: BookmarkFolderOptionView[]) => {
        this.regularOptions = options;
        this.regularOptionsStatsVersion = currentStatsVersion;
        this.refreshLocalOverviewCacheSafely(options, currentStatsVersion);
        return options.slice();
      })
      .finally(() => {
        this.regularPreparePromise = undefined;
      });
    return this.regularPreparePromise;
  }

  private async preparePrivateOptions(forceRefresh: boolean): Promise<BookmarkFolderOptionView[]> {
    const currentStatsVersion = BookmarkStatsVersionSignal.readVersion();
    if (!forceRefresh && this.privateOptions.length > 0 &&
      this.isPreparedOptionsFresh(this.privateOptionsStatsVersion, currentStatsVersion)) {
      return this.privateOptions.slice();
    }
    if (this.privatePreparePromise !== undefined) {
      return this.privatePreparePromise;
    }
    this.privatePreparePromise = this.buildPreparedOptions(this.privateFeature)
      .then((options: BookmarkFolderOptionView[]) => {
        this.privateOptions = options;
        this.privateOptionsStatsVersion = currentStatsVersion;
        return options.slice();
      })
      .finally(() => {
        this.privatePreparePromise = undefined;
      });
    return this.privatePreparePromise;
  }

  private async buildPreparedOptions(feature: BookmarksFeature): Promise<BookmarkFolderOptionView[]> {
    await this.repository.initialize();
    return this.viewModel.buildOptionsAsync(feature);
  }

  private buildFastChildOptions(scope: BookmarkStorageScope, parentId: string): BookmarkFolderOptionView[] {
    return this.buildOptionsFromNodes(
      this.repository.listChildren(parentId.length > 0 ? parentId : undefined, scope)
        .filter((node: BookmarkNode) => node.type === 'folder'),
      scope,
      parentId
    );
  }

  private async buildPreviewChildOptions(
    scope: BookmarkStorageScope,
    parentId: string
  ): Promise<BookmarkFolderOptionView[]> {
    if (this.repository.listPreviewChildren === undefined) {
      return this.buildFastChildOptions(scope, parentId);
    }
    const nodes = await this.repository.listPreviewChildren(parentId.length > 0 ? parentId : undefined, 80, scope);
    return this.buildOptionsFromNodes(
      nodes.filter((node: BookmarkNode) => node.type === 'folder'),
      scope,
      parentId
    );
  }

  private buildOptionsFromNodes(
    folders: BookmarkNode[],
    scope: BookmarkStorageScope,
    parentId: string
  ): BookmarkFolderOptionView[] {
    const cachedRootOverview = parentId.length <= 0 ? this.buildCachedRootOverviewById(scope) :
      new Map<string, AiraLocalBookmarkRootOverviewCacheEntry>();
    return folders.map((folder: BookmarkNode) => {
      const directChildren = this.repository.listChildren(folder.id, scope);
      const cachedOverview = cachedRootOverview.get(folder.id);
      const childFolderCount = cachedOverview !== undefined ? cachedOverview.bookmarkFolderCount :
        directChildren.filter((node: BookmarkNode) => node.type === 'folder').length;
      const bookmarkCount = cachedOverview !== undefined ? cachedOverview.bookmarkItemCount :
        directChildren.filter((node: BookmarkNode) => node.type === 'bookmark').length;
      const option: BookmarkFolderOptionView = {
        id: folder.id,
        title: folder.title,
        subtitle: '',
        parentId: parentId,
        childFolderCount: childFolderCount,
        bookmarkCount: bookmarkCount,
        bookmarkCountText: `${bookmarkCount} 个书签`,
        depth: this.resolveOptionDepth(parentId)
      };
      return option;
    });
  }

  private buildCachedRootOverviewById(scope: BookmarkStorageScope): Map<string, AiraLocalBookmarkRootOverviewCacheEntry> {
    const cached = new Map<string, AiraLocalBookmarkRootOverviewCacheEntry>();
    if (scope !== 'regular') {
      return cached;
    }
    const snapshot = this.localOverviewRepository.getCachedRootSnapshot();
    if (snapshot === undefined || !this.isPreparedOptionsFresh(snapshot.statsVersion, BookmarkStatsVersionSignal.readVersion())) {
      return cached;
    }
    snapshot.entries.forEach((entry: AiraLocalBookmarkRootOverviewCacheEntry) => {
      cached.set(entry.id, entry);
    });
    return cached;
  }

  private mergePreviewOptions(
    currentOptions: BookmarkFolderOptionView[],
    previewOptions: BookmarkFolderOptionView[],
    parentId: string
  ): BookmarkFolderOptionView[] {
    const mergedById = new Map<string, BookmarkFolderOptionView>();
    currentOptions.forEach((option: BookmarkFolderOptionView) => {
      mergedById.set(option.id, option);
    });
    previewOptions.forEach((option: BookmarkFolderOptionView) => {
      mergedById.set(option.id, option);
    });
    if (parentId.length > 0) {
      const parent = mergedById.get(parentId);
      if (parent !== undefined) {
        mergedById.set(parentId, {
          id: parent.id,
          title: parent.title,
          subtitle: parent.subtitle,
          parentId: parent.parentId,
          childFolderCount: Math.max(parent.childFolderCount, previewOptions.length),
          bookmarkCount: parent.bookmarkCount,
          bookmarkCountText: parent.bookmarkCountText,
          depth: parent.depth
        });
      }
    }
    return Array.from(mergedById.values());
  }

  private resolveOptionDepth(parentId: string): number {
    if (parentId.length <= 0) {
      return 0;
    }
    const cachedOptions = this.regularOptions.length > 0 ? this.regularOptions : this.privateOptions;
    const parent = cachedOptions.find((option: BookmarkFolderOptionView) => option.id === parentId);
    return parent !== undefined ? parent.depth + 1 : 1;
  }

  private refreshLocalOverviewCacheSafely(options: BookmarkFolderOptionView[], statsVersion: number): void {
    const bookmarkItemCount = this.resolveRootBookmarkCount(options);
    const bookmarkFolderCount = options.length;
    const rootEntries = this.buildRootOverviewCacheEntries(options);
    setTimeout(() => {
      this.localOverviewRepository.saveSnapshot({
        bookmarkFolderCount: bookmarkFolderCount,
        bookmarkItemCount: bookmarkItemCount,
        updatedAt: Date.now(),
        statsVersion: statsVersion
      }).catch((_error: Error) => {
      });
      const rootSnapshot: AiraLocalBookmarkRootOverviewCacheSnapshot = {
        entries: rootEntries,
        updatedAt: Date.now(),
        statsVersion: statsVersion
      };
      this.localOverviewRepository.saveRootSnapshot(rootSnapshot).catch((_error: Error) => {
      });
    }, 0);
  }

  private resolveRootBookmarkCount(options: BookmarkFolderOptionView[]): number {
    let count = 0;
    options.forEach((option: BookmarkFolderOptionView) => {
      if (option.parentId.length <= 0) {
        count += option.bookmarkCount;
      }
    });
    return count;
  }

  private buildRootOverviewCacheEntries(options: BookmarkFolderOptionView[]): AiraLocalBookmarkRootOverviewCacheEntry[] {
    const rootEntries: AiraLocalBookmarkRootOverviewCacheEntry[] = [];
    options.forEach((option: BookmarkFolderOptionView) => {
      if (option.parentId.length > 0) {
        return;
      }
      rootEntries.push({
        id: option.id,
        title: option.title,
        bookmarkFolderCount: option.childFolderCount,
        bookmarkItemCount: option.bookmarkCount
      });
    });
    return rootEntries;
  }

  private resolveCachedOptions(scope: BookmarkStorageScope): BookmarkFolderOptionView[] {
    const currentStatsVersion = BookmarkStatsVersionSignal.readVersion();
    if (scope === 'private') {
      return this.isPreparedOptionsFresh(this.privateOptionsStatsVersion, currentStatsVersion) ? this.privateOptions : [];
    }
    return this.isPreparedOptionsFresh(this.regularOptionsStatsVersion, currentStatsVersion) ? this.regularOptions : [];
  }

  private isPreparedOptionsFresh(preparedStatsVersion: number, currentStatsVersion: number): boolean {
    const normalizedCurrent = Math.max(0, Math.floor(Number(currentStatsVersion)));
    if (normalizedCurrent <= 0) {
      return true;
    }
    const normalizedPrepared = Math.max(0, Math.floor(Number(preparedStatsVersion)));
    return normalizedPrepared >= normalizedCurrent;
  }
}
