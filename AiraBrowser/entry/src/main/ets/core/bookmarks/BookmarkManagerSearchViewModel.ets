import { BookmarkNode } from '../../common/models/BrowserModels';
import { BookmarkManagementFeature } from '../../features/bookmarks/BookmarkManagementFeature';

const BOOKMARK_MANAGER_SEARCH_RESULT_LIMIT: number = 2147483647;

export interface BookmarkManagerSearchState {
  query: string;
  isSearchMode: boolean;
  isActive: boolean;
  resultCount: number;
  emptyTitle: ResourceStr;
  emptyMessage: ResourceStr;
}

export interface BookmarkManagerSearchResult {
  state: BookmarkManagerSearchState;
  nodes: BookmarkNode[];
}

export class BookmarkManagerSearchViewModel {
  private bookmarkManagementFeature: BookmarkManagementFeature;
  private currentFolderNodes: BookmarkNode[] = [];
  private query: string = '';
  private isSearchMode: boolean = false;
  private routeQueryInitialized: boolean = false;
  private excludedNodeIds: string[] = [];

  constructor(bookmarkManagementFeature: BookmarkManagementFeature) {
    this.bookmarkManagementFeature = bookmarkManagementFeature;
  }

  createInitialState(): BookmarkManagerSearchState {
    return this.buildState(false, false, 0);
  }

  initializeRouteQuery(query?: string): BookmarkManagerSearchResult {
    if (!this.routeQueryInitialized) {
      this.routeQueryInitialized = true;
      const initialQuery = query?.trim() ?? '';
      if (initialQuery.length > 0) {
        this.query = initialQuery;
        this.isSearchMode = true;
      }
    }
    return this.buildResult();
  }

  setCurrentFolderNodes(nodes: BookmarkNode[]): BookmarkManagerSearchResult {
    this.currentFolderNodes = nodes.slice();
    this.excludedNodeIds = [];
    return this.buildResult();
  }

  setQuery(query: string): BookmarkManagerSearchResult {
    this.query = query;
    return this.buildResult();
  }

  enterSearchMode(): BookmarkManagerSearchResult {
    this.isSearchMode = true;
    this.query = '';
    return this.buildResult();
  }

  exitSearchMode(): BookmarkManagerSearchResult {
    this.isSearchMode = false;
    this.query = '';
    return this.buildResult();
  }

  removeNodesByIds(nodeIds: string[]): BookmarkManagerSearchResult {
    if (nodeIds.length === 0) {
      return this.buildResult();
    }
    const deletingIds = new Set<string>(nodeIds);
    this.currentFolderNodes = this.currentFolderNodes.filter((node: BookmarkNode) => !deletingIds.has(node.id));
    nodeIds.forEach((nodeId: string) => {
      if (this.excludedNodeIds.indexOf(nodeId) < 0) {
        this.excludedNodeIds.push(nodeId);
      }
    });
    return this.buildResult();
  }

  replaceNode(node: BookmarkNode): BookmarkManagerSearchResult {
    this.currentFolderNodes = this.currentFolderNodes.map((item: BookmarkNode) => {
      return item.id === node.id ? node : item;
    });
    return this.buildResult();
  }

  getCurrentFolderNodes(): BookmarkNode[] {
    return this.currentFolderNodes.slice();
  }

  reset(): BookmarkManagerSearchResult {
    this.currentFolderNodes = [];
    this.query = '';
    this.isSearchMode = false;
    this.excludedNodeIds = [];
    return this.buildResult();
  }

  private buildResult(): BookmarkManagerSearchResult {
    const normalizedQuery = this.query.trim();
    const isActive = this.isSearchMode && normalizedQuery.length > 0;
    let nodes: BookmarkNode[] = [];
    if (isActive) {
      nodes = this.bookmarkManagementFeature.searchBookmarks(normalizedQuery, BOOKMARK_MANAGER_SEARCH_RESULT_LIMIT);
    } else if (!this.isSearchMode) {
      nodes = this.currentFolderNodes.slice();
    }
    if (this.excludedNodeIds.length > 0) {
      const excludedIds = new Set<string>(this.excludedNodeIds);
      nodes = nodes.filter((node: BookmarkNode) => !excludedIds.has(node.id));
    }
    return {
      state: this.buildState(this.isSearchMode, isActive, nodes.length),
      nodes: nodes
    };
  }

  private buildState(isSearchMode: boolean, isActive: boolean, resultCount: number): BookmarkManagerSearchState {
    return {
      query: this.query,
      isSearchMode: isSearchMode,
      isActive: isActive,
      resultCount: resultCount,
      emptyTitle: isActive ? $r('app.string.bookmark_no_match') : (isSearchMode ? $r('app.string.bookmark_search') : $r('app.string.bookmark_empty')),
      emptyMessage: isActive
        ? $r('app.string.history_try_another')
        : (isSearchMode ? $r('app.string.history_search_hint') : $r('app.string.bookmark_empty_hint'))
    };
  }
}
