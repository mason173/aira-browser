/// <reference types="chrome" />

import { getBookmarksApi } from '@/platform/runtime';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';

type BookmarkApi = typeof chrome.bookmarks;
type BookmarkTreeNode = chrome.bookmarks.BookmarkTreeNode;
type BookmarkCreateDetails = chrome.bookmarks.CreateDetails;

export type BrowserBookmarkHtmlNode =
  | {
      type: 'folder';
      title: string;
      children: BrowserBookmarkHtmlNode[];
    }
  | {
      type: 'bookmark';
      title: string;
      url: string;
    };

export type BrowserBookmarkHtmlImportResult = {
  folderId: string;
  folderTitle: string;
  folderCount: number;
  bookmarkCount: number;
};

const ROOT_FOLDER_ID_MAP: Record<string, 'toolbar' | 'other' | 'mobile' | 'unknown'> = {
  '1': 'toolbar',
  '2': 'other',
  '3': 'mobile',
  toolbar_____: 'toolbar',
  menu________: 'other',
  mobile______: 'mobile',
  unfiled_____: 'unknown',
};

const ROOT_FOLDER_TITLE_PATTERNS: Array<{ pattern: RegExp; role: 'toolbar' | 'other' | 'mobile' | 'unknown' }> = [
  { pattern: /toolbar|bookmarks bar|bookmarks toolbar|favorites bar|书签栏|收藏夹栏/i, role: 'toolbar' },
  { pattern: /bookmarks menu|menu|other|其他书签|其他收藏夹|favorites/i, role: 'other' },
  { pattern: /mobile|移动书签|移动收藏夹/i, role: 'mobile' },
];

const ensureBookmarkPermission = async () => {
  const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true });
  if (!granted) {
    throw new Error('未授予书签权限');
  }
};

const hasBookmarkRuntimeError = () => Boolean(globalThis.chrome?.runtime?.lastError);

const callBookmarksApi = <T>(
  executor: (api: BookmarkApi, resolve: (value: T) => void, reject: (error: Error) => void) => void,
): Promise<T> => {
  const api = getBookmarksApi();
  if (!api) {
    return Promise.reject(new Error('当前环境不支持浏览器书签 API'));
  }

  return new Promise<T>((resolve, reject) => {
    executor(
      api,
      (value) => {
        if (hasBookmarkRuntimeError()) {
          reject(new Error(globalThis.chrome?.runtime?.lastError?.message || '书签 API 调用失败'));
          return;
        }
        resolve(value);
      },
      reject,
    );
  });
};

const getBookmarkTree = () => (
  callBookmarksApi<BookmarkTreeNode[]>((api, resolve) => {
    api.getTree((nodes) => resolve(nodes || []));
  })
);

const createBookmarkNode = (details: BookmarkCreateDetails) => (
  callBookmarksApi<BookmarkTreeNode>((api, resolve) => {
    api.create(details, (node) => resolve(node));
  })
);

const htmlEscape = (value: string) => (
  value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
);

const htmlUnescape = (value: string) => {
  if (typeof document === 'undefined') {
    return value
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }
  const textarea = document.createElement('textarea');
  textarea.innerHTML = value;
  return textarea.value;
};

const stripTags = (value: string) => value.replace(/<[^>]*>/g, '');

const toBookmarkTimestamp = (value: number | undefined) => {
  if (!Number.isFinite(value)) return Math.floor(Date.now() / 1000);
  return Math.max(0, Math.floor((value || 0) / 1000));
};

const detectRootFolderRole = (node: BookmarkTreeNode): 'toolbar' | 'other' | 'mobile' | 'unknown' => {
  if (node.id && ROOT_FOLDER_ID_MAP[node.id]) {
    return ROOT_FOLDER_ID_MAP[node.id];
  }
  const title = node.title || '';
  for (const entry of ROOT_FOLDER_TITLE_PATTERNS) {
    if (entry.pattern.test(title)) return entry.role;
  }
  return 'unknown';
};

const getImportParentId = async () => {
  const tree = await getBookmarkTree();
  const roots = tree[0]?.children || [];
  return (
    roots.find((node) => detectRootFolderRole(node) === 'toolbar')?.id ||
    roots.find((node) => detectRootFolderRole(node) === 'other')?.id ||
    roots[0]?.id
  );
};

const serializeBookmarkNode = (node: BookmarkTreeNode, depth: number): string[] => {
  const indent = '    '.repeat(depth);
  const title = htmlEscape(node.title || '');
  if (node.url) {
    return [
      `${indent}<DT><A HREF="${htmlEscape(node.url)}" ADD_DATE="${toBookmarkTimestamp(node.dateAdded)}">${title}</A>`,
    ];
  }

  const lines = [
    `${indent}<DT><H3 ADD_DATE="${toBookmarkTimestamp(node.dateAdded)}" LAST_MODIFIED="${toBookmarkTimestamp(node.dateGroupModified)}">${title}</H3>`,
    `${indent}<DL><p>`,
  ];
  for (const child of node.children || []) {
    lines.push(...serializeBookmarkNode(child, depth + 1));
  }
  lines.push(`${indent}</DL><p>`);
  return lines;
};

export const exportBrowserBookmarksAsHtml = async () => {
  await ensureBookmarkPermission();
  const tree = await getBookmarkTree();
  const rootChildren = tree[0]?.children || [];
  const lines = [
    '<!DOCTYPE NETSCAPE-Bookmark-file-1>',
    '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
    '<TITLE>Bookmarks</TITLE>',
    '<H1>Bookmarks</H1>',
    '<DL><p>',
  ];
  for (const child of rootChildren) {
    lines.push(...serializeBookmarkNode(child, 1));
  }
  lines.push('</DL><p>');
  return `${lines.join('\n')}\n`;
};

const readAttribute = (line: string, name: string) => {
  const match = line.match(new RegExp(`${name}\\s*=\\s*(['"])(.*?)\\1`, 'i'));
  return match ? htmlUnescape(match[2] || '') : '';
};

const readTagText = (line: string, tag: 'A' | 'H3') => {
  const match = line.match(new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i'));
  return htmlUnescape(stripTags(match?.[1] || '').trim());
};

export const parseBrowserBookmarksHtml = (html: string): BrowserBookmarkHtmlNode[] => {
  const root: BrowserBookmarkHtmlNode[] = [];
  const stack: BrowserBookmarkHtmlNode[][] = [root];
  let pendingFolder: Extract<BrowserBookmarkHtmlNode, { type: 'folder' }> | null = null;

  for (const rawLine of html.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;

    if (/<DT>\s*<H3\b/i.test(line) || /^<H3\b/i.test(line)) {
      const folder: BrowserBookmarkHtmlNode = {
        type: 'folder',
        title: readTagText(line, 'H3') || 'Folder',
        children: [],
      };
      stack[stack.length - 1]?.push(folder);
      pendingFolder = folder;
      continue;
    }

    if (/<DL\b/i.test(line)) {
      if (pendingFolder) {
        stack.push(pendingFolder.children);
        pendingFolder = null;
      }
      continue;
    }

    if (/<\/DL>/i.test(line)) {
      pendingFolder = null;
      if (stack.length > 1) {
        stack.pop();
      }
      continue;
    }

    if (/<DT>\s*<A\b/i.test(line) || /^<A\b/i.test(line)) {
      const url = readAttribute(line, 'HREF').trim();
      if (!url) continue;
      stack[stack.length - 1]?.push({
        type: 'bookmark',
        title: readTagText(line, 'A') || url,
        url,
      });
    }
  }

  return root;
};

const countBookmarkHtmlNodes = (nodes: readonly BrowserBookmarkHtmlNode[]) => {
  let folderCount = 0;
  let bookmarkCount = 0;
  const visit = (items: readonly BrowserBookmarkHtmlNode[]) => {
    for (const item of items) {
      if (item.type === 'bookmark') {
        bookmarkCount += 1;
        continue;
      }
      folderCount += 1;
      visit(item.children);
    }
  };
  visit(nodes);
  return { folderCount, bookmarkCount };
};

const createBookmarkHtmlNodes = async (parentId: string, nodes: readonly BrowserBookmarkHtmlNode[]) => {
  for (const node of nodes) {
    if (node.type === 'bookmark') {
      await createBookmarkNode({
        parentId,
        title: node.title,
        url: node.url,
      });
      continue;
    }
    const folder = await createBookmarkNode({
      parentId,
      title: node.title || 'Folder',
    });
    await createBookmarkHtmlNodes(folder.id, node.children);
  }
};

export const importBrowserBookmarksFromHtml = async (html: string): Promise<BrowserBookmarkHtmlImportResult> => {
  await ensureBookmarkPermission();
  const parsedNodes = parseBrowserBookmarksHtml(html);
  const { folderCount, bookmarkCount } = countBookmarkHtmlNodes(parsedNodes);
  if (bookmarkCount <= 0 && folderCount <= 0) {
    throw new Error('未识别到可导入的浏览器书签');
  }

  const parentId = await getImportParentId();
  if (!parentId) {
    throw new Error('没有找到可写入的浏览器书签目录');
  }

  const folderTitle = `Aira Imported Bookmarks ${new Date().toLocaleString('zh-CN', {
    hour12: false,
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })}`;
  const importRoot = await createBookmarkNode({
    parentId,
    title: folderTitle,
  });
  await createBookmarkHtmlNodes(importRoot.id, parsedNodes);
  return {
    folderId: importRoot.id,
    folderTitle,
    folderCount,
    bookmarkCount,
  };
};
