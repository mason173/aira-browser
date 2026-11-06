import { BookmarkNode, BookmarkStorageScope } from '../../common/models/BrowserModels';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../../data/repositories/BookmarkRepositoryCore';

export interface BookmarkBrowseLocation {
  folderId: string;
  rootId: string;
  query: string;
  /** Distance from the list's resting top, excluding any contentStartOffset inset. */
  offset: number;
}

interface BookmarkBrowseSession {
  location: BookmarkBrowseLocation;
  ancestors: string[];
}

/** Remembers where a bookmark was opened, in memory only and separately for each bookmark scope. */
export class BookmarkBrowseSessionStore {
  private readonly sessions: Map<BookmarkStorageScope, BookmarkBrowseSession> =
    new Map<BookmarkStorageScope, BookmarkBrowseSession>();

  remember(scope: BookmarkStorageScope, folderId: string, query: string, offset: number,
    findNode: (id: string) => BookmarkNode | undefined): void {
    const ancestors: string[] = [];
    let node = findNode(folderId);
    while (node?.type === 'folder' && !ancestors.includes(node.id)) {
      ancestors.push(node.id);
      node = node.parentId === undefined ? undefined : findNode(node.parentId);
    }
    const toolbarRoot = scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
    const otherRoot = scope === 'private' ? PRIVATE_BOOKMARK_OTHER_ROOT_ID : BOOKMARK_OTHER_ROOT_ID;
    const rootId = ancestors.includes(otherRoot) ? otherRoot : toolbarRoot;
    this.sessions.set(scope, {
      location: {
        folderId: folderId,
        rootId: rootId,
        query: query,
        offset: Number.isFinite(offset) ? Math.max(0, offset) : 0
      },
      ancestors: ancestors
    });
  }

  peek(scope: BookmarkStorageScope): BookmarkBrowseLocation | undefined {
    const location = this.sessions.get(scope)?.location;
    return location === undefined ? undefined : this.copy(location);
  }

  resolve(scope: BookmarkStorageScope,
    findNode: (id: string) => BookmarkNode | undefined): BookmarkBrowseLocation | undefined {
    const session = this.sessions.get(scope);
    if (session === undefined) {
      return undefined;
    }
    const location = this.copy(session.location);
    const candidates = [location.folderId].concat(session.ancestors, [location.rootId]);
    for (const id of candidates) {
      const folder = findNode(id);
      if (folder?.type !== 'folder' || (folder.scope ?? 'regular') !== scope) {
        continue;
      }
      if (folder.id !== location.folderId) {
        location.offset = 0;
      }
      location.folderId = folder.id;
      let ancestor: BookmarkNode | undefined = folder;
      const visited: Set<string> = new Set<string>();
      while (ancestor !== undefined && !visited.has(ancestor.id)) {
        visited.add(ancestor.id);
        if (ancestor.id === BOOKMARK_TOOLBAR_ROOT_ID || ancestor.id === BOOKMARK_OTHER_ROOT_ID ||
          ancestor.id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID || ancestor.id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
          location.rootId = ancestor.id;
          break;
        }
        ancestor = ancestor.parentId === undefined ? undefined : findNode(ancestor.parentId);
      }
      return location;
    }
    return undefined;
  }

  parentLocation(scope: BookmarkStorageScope, folderId: string, rootId: string,
    findNode: (id: string) => BookmarkNode | undefined): BookmarkBrowseLocation {
    const folder = findNode(folderId);
    const parent = folder?.parentId === undefined ? undefined : findNode(folder.parentId);
    return {
      folderId: parent?.type === 'folder' && (parent.scope ?? 'regular') === scope ? parent.id : rootId,
      rootId: rootId,
      query: '',
      offset: 0
    };
  }

  private copy(location: BookmarkBrowseLocation): BookmarkBrowseLocation {
    return {
      folderId: location.folderId,
      rootId: location.rootId,
      query: location.query,
      offset: location.offset
    };
  }
}

export const sharedBookmarkBrowseSessionStore: BookmarkBrowseSessionStore = new BookmarkBrowseSessionStore();
