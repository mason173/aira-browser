import { BookmarkNode, BookmarkStorageScope, HistoryVisit } from '../../common/models/BrowserModels';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../../data/repositories/BookmarkRepositoryCore';

export const BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_LIMIT: number = 10;
export const BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_WIDTH_VP: number = 320;
export const BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_GAP_VP: number = 6;
export const BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_EMPTY_MESSAGE: string = '还没有历史记录';
export const BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_PRIVATE_MESSAGE: string = '无痕模式不显示历史记录';
export const BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_LOADING_MESSAGE: string = '正在读取历史记录';
export const BROWSER_LARGE_SCREEN_OVERFLOW_BOOKMARK_EMPTY_MESSAGE: string = '这个文件夹是空的';
export const BROWSER_LARGE_SCREEN_OVERFLOW_OTHER_BOOKMARKS_TITLE: string = '其他书签';

export interface BrowserLargeScreenOverflowHistoryItem {
  id: string;
  title: string;
  url: string;
}

export interface BrowserLargeScreenOverflowBookmarkItem {
  id: string;
  title: string;
  url: string;
  folder: boolean;
}

export function resolveOverflowBookmarkScope(privateMode: boolean): BookmarkStorageScope {
  return privateMode ? 'private' : 'regular';
}

export function resolveOverflowBookmarkToolbarRootId(scope: BookmarkStorageScope): string {
  return scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
}

export function resolveOverflowBookmarkOtherRootId(scope: BookmarkStorageScope): string {
  return scope === 'private' ? PRIVATE_BOOKMARK_OTHER_ROOT_ID : BOOKMARK_OTHER_ROOT_ID;
}

export function resolveOverflowHistoryEmptyMessage(privateMode: boolean, ready: boolean): string {
  if (!ready) {
    return BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_LOADING_MESSAGE;
  }
  if (privateMode) {
    return BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_PRIVATE_MESSAGE;
  }
  return BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_EMPTY_MESSAGE;
}

export function projectOverflowHistoryItems(
  visits: HistoryVisit[],
  privateMode: boolean,
  limit: number = BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_LIMIT
): BrowserLargeScreenOverflowHistoryItem[] {
  if (privateMode) {
    return [];
  }
  const normalizedLimit = Math.max(1, Math.floor(limit));
  const items: BrowserLargeScreenOverflowHistoryItem[] = [];
  for (let index = 0; index < visits.length && items.length < normalizedLimit; index += 1) {
    const visit = visits[index];
    const url = visit.url.trim();
    if (url.length === 0 || visit.dataScope === 'session_ephemeral') {
      continue;
    }
    items.push({
      id: visit.id,
      title: resolveHistoryTitle(visit, url),
      url: url
    });
  }
  return items;
}

export function projectOverflowBookmarkItems(nodes: BookmarkNode[]): BrowserLargeScreenOverflowBookmarkItem[] {
  const folders: BrowserLargeScreenOverflowBookmarkItem[] = [];
  const bookmarks: BrowserLargeScreenOverflowBookmarkItem[] = [];
  nodes.forEach((node: BookmarkNode): void => {
    if (node.sync.deletedAt !== undefined) {
      return;
    }
    if (node.type === 'folder') {
      folders.push(toBookmarkItem(node, true));
      return;
    }
    const url = (node.url ?? '').trim();
    if (node.type === 'bookmark' && url.length > 0) {
      bookmarks.push(toBookmarkItem(node, false));
    }
  });
  return folders.concat(bookmarks);
}

export function appendOtherBookmarksFolder(
  items: BrowserLargeScreenOverflowBookmarkItem[],
  otherRootId: string,
  otherChildCount: number
): BrowserLargeScreenOverflowBookmarkItem[] {
  if (otherChildCount <= 0 || items.some((item: BrowserLargeScreenOverflowBookmarkItem): boolean =>
    item.id === otherRootId)) {
    return items;
  }
  const next = items.slice();
  next.push({
    id: otherRootId,
    title: BROWSER_LARGE_SCREEN_OVERFLOW_OTHER_BOOKMARKS_TITLE,
    url: '',
    folder: true
  });
  return next;
}

function resolveHistoryTitle(visit: HistoryVisit, url: string): string {
  const title = visit.title.trim();
  if (title.length > 0) {
    return title;
  }
  const host = (visit.host ?? '').trim();
  if (host.length > 0) {
    return host;
  }
  return url;
}

function toBookmarkItem(node: BookmarkNode, folder: boolean): BrowserLargeScreenOverflowBookmarkItem {
  const title = node.title.trim();
  const url = (node.url ?? '').trim();
  return {
    id: node.id,
    title: title.length > 0 ? title : (url.length > 0 ? url : '未命名'),
    url: url,
    folder: folder
  };
}
