import { BookmarkNode, BookmarkStorageScope } from '../../common/models/BrowserModels';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../../data/repositories/BookmarkRepositoryCore';
import { BookmarkListDataSource } from './BookmarkListDataSource';

export interface BookmarkRootPageRefreshResult {
  toolbarChanged: boolean;
  otherChanged: boolean;
}

/** Keeps the two bookmark-manager root lists mounted so a horizontal swipe can show either page. */
export class BookmarkRootPageStore {
  readonly toolbarDataSource: BookmarkListDataSource = new BookmarkListDataSource();
  readonly otherDataSource: BookmarkListDataSource = new BookmarkListDataSource();
  readonly toolbarScroller: Scroller = new Scroller();
  readonly otherScroller: Scroller = new Scroller();
  private toolbarCount: number = 0;
  private otherCount: number = 0;

  toolbarRootId(scope: BookmarkStorageScope): string {
    return scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
  }

  otherRootId(scope: BookmarkStorageScope): string {
    return scope === 'private' ? PRIVATE_BOOKMARK_OTHER_ROOT_ID : BOOKMARK_OTHER_ROOT_ID;
  }

  toolbarNodeCount(): number {
    return this.toolbarCount;
  }

  otherNodeCount(): number {
    return this.otherCount;
  }

  dataSourceFor(rootId: string, scope: BookmarkStorageScope): BookmarkListDataSource {
    return rootId === this.otherRootId(scope) ? this.otherDataSource : this.toolbarDataSource;
  }

  scrollerFor(rootId: string, scope: BookmarkStorageScope): Scroller {
    return rootId === this.otherRootId(scope) ? this.otherScroller : this.toolbarScroller;
  }

  headerScrollers(showRootTabs: boolean, selectedRootId: string, scope: BookmarkStorageScope,
    folderScroller: Scroller): Scroller[] {
    if (!showRootTabs) {
      return [folderScroller];
    }
    return [this.scrollerFor(selectedRootId, scope)];
  }

  titleElevated(rootId: string, scope: BookmarkStorageScope): boolean {
    const count = rootId === this.otherRootId(scope) ? this.otherCount : this.toolbarCount;
    if (count <= 0) {
      return false;
    }
    // A populated root can be selected before its list is bound to the scroller.
    const position = this.scrollerFor(rootId, scope).offset();
    if (position === undefined) {
      return false;
    }
    const offset = position.yOffset;
    return Number.isFinite(offset) && offset > 8;
  }

  replace(rootId: string, scope: BookmarkStorageScope, nodes: BookmarkNode[]): boolean {
    if (rootId === this.toolbarRootId(scope)) {
      return this.replaceDataSource(this.toolbarDataSource, nodes, true);
    }
    if (rootId === this.otherRootId(scope)) {
      return this.replaceDataSource(this.otherDataSource, nodes, false);
    }
    return false;
  }

  refresh(scope: BookmarkStorageScope, currentFolderId: string,
    listChildren: (rootId: string) => BookmarkNode[]): BookmarkRootPageRefreshResult {
    if (currentFolderId.length > 0) {
      return { toolbarChanged: false, otherChanged: false };
    }
    const toolbarRootId = this.toolbarRootId(scope);
    const otherRootId = this.otherRootId(scope);
    return {
      toolbarChanged: this.replace(toolbarRootId, scope, listChildren(toolbarRootId)),
      otherChanged: this.replace(otherRootId, scope, listChildren(otherRootId))
    };
  }

  private replaceDataSource(dataSource: BookmarkListDataSource, nodes: BookmarkNode[], toolbarPage: boolean): boolean {
    const changed = !this.nodesMatch(dataSource, nodes);
    if (changed) {
      dataSource.replaceNodes(nodes);
    }
    const count = dataSource.totalCount();
    if (toolbarPage) {
      this.toolbarCount = count;
    } else {
      this.otherCount = count;
    }
    return changed;
  }

  private nodesMatch(dataSource: BookmarkListDataSource, nodes: BookmarkNode[]): boolean {
    if (dataSource.totalCount() !== nodes.length) {
      return false;
    }
    for (let index = 0; index < nodes.length; index++) {
      const current = dataSource.getData(index);
      const next = nodes[index];
      if (current.id !== next.id || current.position !== next.position || current.title !== next.title ||
        current.url !== next.url || current.updatedAt !== next.updatedAt) {
        return false;
      }
    }
    return true;
  }
}
