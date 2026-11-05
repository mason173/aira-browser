import router from '@ohos.router';
import { BookmarkNode, BookmarkStorageScope } from '../../common/models/BrowserModels';
import { BookmarkManagementFeature } from '../../features/bookmarks/BookmarkManagementFeature';
import { BOOKMARK_TOOLBAR_ROOT_ID, PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID, isBookmarkRootNodeId } from '../../data/repositories/BookmarkRepositoryCore';
import { BOOKMARK_MANAGER_ROUTE, BROWSER_SHELL_ROUTE } from '../../app/router/AppRoutes';
import { BrowserAppUrlOpenIntent } from '../browser/BrowserAppUrlOpenCoordinator';
import { requestOpenBrowserUrlWithRouteParams } from '../navigation/BrowserNativeNavigationRequestCenter';
import { BookmarkBrowseLocation, sharedBookmarkBrowseSessionStore } from './BookmarkBrowseSessionStore';

export interface BookmarkManagerRouteParams {
  folderId?: string;
  folderTitle?: string;
  query?: string;
  dataScope?: string;
  privacyMode?: string;
  boundarySource?: string;
  bookmarkScope?: string;
}

export interface BookmarkManagerBrowseHost {
  feature: BookmarkManagementFeature;
  scope: () => BookmarkStorageScope;
  folderId: () => string;
  rootId: () => string;
  query: () => string;
  scroller: () => Scroller;
  applyLocation: (location: BookmarkBrowseLocation) => void;
  exitSearch: () => void;
  reload: () => void;
  setElevated: (elevated: boolean) => void;
}

/** Coordinates a phone bookmark manager's return location without retaining its page or private data on disk. */
export class BookmarkManagerBrowseSessionCoordinator {
  private readonly host: BookmarkManagerBrowseHost;
  private resumed: boolean = false;
  private pending?: BookmarkBrowseLocation;
  private validated: boolean = false;
  private restoreTimer: number = -1;
  private disposed: boolean = false;

  constructor(host: BookmarkManagerBrowseHost) {
    this.host = host;
  }

  initialize(params: BookmarkManagerRouteParams | undefined): BookmarkBrowseLocation {
    this.dispose();
    this.disposed = false;
    this.validated = false;
    this.pending = undefined;
    this.resumed = false;
    const scope = this.host.scope();
    if ((params?.folderId?.trim() ?? '').length === 0 && (params?.query?.trim() ?? '').length === 0) {
      this.pending = sharedBookmarkBrowseSessionStore.peek(scope);
      this.resumed = this.pending !== undefined;
      if (this.pending !== undefined) {
        return this.pending;
      }
    }
    const rootId = scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
    return { folderId: params?.folderId ?? rootId, rootId: rootId, query: params?.query ?? '', offset: 0 };
  }

  validateLocation(): void {
    if (this.disposed || this.validated) {
      return;
    }
    this.cancelOutdatedRestore();
    if (this.pending !== undefined) {
      this.pending = sharedBookmarkBrowseSessionStore.resolve(this.host.scope(),
        (id: string): BookmarkNode | undefined => this.host.feature.findNodeById(id));
      this.host.applyLocation(this.pending ?? this.defaultLocation());
    }
    this.validated = true;
  }

  remember(): void {
    sharedBookmarkBrowseSessionStore.remember(this.host.scope(), this.host.folderId(), this.host.query(),
      this.host.scroller().offset()?.yOffset ?? this.pending?.offset ?? 0,
      (id: string): BookmarkNode | undefined => this.host.feature.findNodeById(id));
  }

  scheduleScrollRestore(): void {
    this.cancelOutdatedRestore();
    if (this.disposed || this.pending === undefined || !this.validated || this.restoreTimer >= 0) {
      return;
    }
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      this.cancelOutdatedRestore();
      const location = this.pending;
      const scroller = this.host.scroller();
      if (location === undefined || scroller.offset() === undefined) {
        return;
      }
      this.pending = undefined;
      scroller.scrollTo({ xOffset: 0, yOffset: location.offset, animation: false });
      this.host.setElevated(location.offset > 8);
    }, 0);
  }

  navigateParent(): boolean {
    if (!this.resumed || isBookmarkRootNodeId(this.host.folderId())) {
      return false;
    }
    const location = sharedBookmarkBrowseSessionStore.parentLocation(this.host.scope(), this.host.folderId(),
      this.host.rootId(), (id: string): BookmarkNode | undefined => this.host.feature.findNodeById(id));
    this.host.exitSearch();
    this.pending = undefined;
    // Reset the still-bound folder list before applying the parent presentation.
    const scroller = this.host.scroller();
    if (scroller.offset() !== undefined) {
      scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
    this.host.applyLocation(location);
    this.host.setElevated(false);
    this.host.reload();
    return true;
  }

  openFolder(folder: BookmarkNode, params: BookmarkManagerRouteParams): Promise<void> {
    return router.pushUrl({
      url: BOOKMARK_MANAGER_ROUTE,
      params: {
        folderId: folder.id,
        folderTitle: folder.title,
        dataScope: params.dataScope,
        privacyMode: params.privacyMode,
        boundarySource: params.boundarySource,
        bookmarkScope: this.host.scope()
      }
    });
  }

  openBookmark(node: BookmarkNode, intent: BrowserAppUrlOpenIntent, privacyMode: string, dataScope: string): void {
    if (node.url === undefined || node.url.length === 0) {
      return;
    }
    this.host.feature.authorizeNavigation();
    this.remember();
    router.back({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(node.url, intent, node.title, 'bookmark',
        { privacyMode: privacyMode, dataScope: dataScope })
    });
  }

  dispose(): void {
    this.disposed = true;
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
  }

  private cancelOutdatedRestore(): void {
    if (this.pending !== undefined && (this.pending.folderId !== this.host.folderId() ||
      this.pending.query.trim() !== this.host.query().trim())) {
      this.pending = undefined;
    }
  }

  private defaultLocation(): BookmarkBrowseLocation {
    const rootId = this.host.scope() === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
    return { folderId: rootId, rootId: rootId, query: '', offset: 0 };
  }
}
