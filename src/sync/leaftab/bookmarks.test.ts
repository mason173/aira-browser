import { beforeEach, describe, expect, it } from 'vitest';
import { replaceLeafTabBookmarkTree } from './bookmarks';

type TestBookmarkNode = chrome.bookmarks.BookmarkTreeNode & {
  children?: TestBookmarkNode[];
};

let bookmarkTree: TestBookmarkNode;
let nextNodeId = 10;

const cloneTree = <T,>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

const findNode = (
  id: string,
  node: TestBookmarkNode = bookmarkTree,
  parent: TestBookmarkNode | null = null,
): { node: TestBookmarkNode; parent: TestBookmarkNode | null } | null => {
  if (node.id === id) return { node, parent };
  for (const child of node.children || []) {
    const found = findNode(id, child, node);
    if (found) return found;
  }
  return null;
};

const removeNodeFromParent = (id: string) => {
  const found = findNode(id);
  if (!found?.parent?.children) return null;
  const index = found.parent.children.findIndex((child) => child.id === id);
  if (index < 0) return null;
  return found.parent.children.splice(index, 1)[0] || null;
};

const insertNode = (parentId: string, node: TestBookmarkNode, index?: number) => {
  const parent = findNode(parentId)?.node;
  if (!parent) throw new Error(`Missing bookmark parent ${parentId}`);
  parent.children ||= [];
  const nextIndex = typeof index === 'number'
    ? Math.max(0, Math.min(index, parent.children.length))
    : parent.children.length;
  parent.children.splice(nextIndex, 0, node);
};

const installBookmarkApiMock = () => {
  globalThis.chrome = {
    runtime: {},
    bookmarks: {
      getTree: (callback: (results: chrome.bookmarks.BookmarkTreeNode[]) => void) => callback([cloneTree(bookmarkTree)]),
      create: (
        details: chrome.bookmarks.CreateDetails,
        callback?: (result: chrome.bookmarks.BookmarkTreeNode) => void,
      ) => {
        const node: TestBookmarkNode = {
          id: String(nextNodeId++),
          parentId: details.parentId,
          title: details.title || '',
          syncing: false,
          ...(details.url ? { url: details.url } : { children: [] }),
        };
        insertNode(details.parentId || '0', node, details.index);
        callback?.(cloneTree(node));
      },
      update: (
        id: string,
        changes: chrome.bookmarks.UpdateChanges,
        callback?: (result: chrome.bookmarks.BookmarkTreeNode) => void,
      ) => {
        const node = findNode(id)?.node;
        if (!node) throw new Error(`Missing bookmark ${id}`);
        if (typeof changes.title === 'string') node.title = changes.title;
        if (typeof changes.url === 'string') node.url = changes.url;
        callback?.(cloneTree(node));
      },
      move: (
        id: string,
        destination: chrome.bookmarks.MoveDestination,
        callback?: (result: chrome.bookmarks.BookmarkTreeNode) => void,
      ) => {
        const node = removeNodeFromParent(id);
        if (!node) throw new Error(`Missing bookmark ${id}`);
        node.parentId = destination.parentId || node.parentId;
        insertNode(node.parentId || '0', node, destination.index);
        callback?.(cloneTree(node));
      },
      remove: (id: string, callback?: () => void) => {
        removeNodeFromParent(id);
        callback?.();
      },
      removeTree: (id: string, callback?: () => void) => {
        removeNodeFromParent(id);
        callback?.();
      },
      onCreated: { addListener: () => {} },
      onRemoved: { addListener: () => {} },
      onChanged: { addListener: () => {} },
      onMoved: { addListener: () => {} },
      onChildrenReordered: { addListener: () => {} },
      onImportEnded: { addListener: () => {} },
    } as unknown as typeof chrome.bookmarks,
  } as typeof chrome;
};

const resetBookmarkTree = () => {
  bookmarkTree = {
    id: '0',
    title: '',
    syncing: false,
    children: [
      {
        id: '1',
        parentId: '0',
        title: 'Bookmarks Bar',
        syncing: false,
        children: [
          {
            id: '4',
            parentId: '1',
            title: 'Keep local',
            url: 'https://keep.example.com',
            syncing: false,
          },
          {
            id: '5',
            parentId: '1',
            title: 'Delete local',
            url: 'https://delete.example.com',
            syncing: false,
          },
        ],
      },
      {
        id: '2',
        parentId: '0',
        title: 'Other Bookmarks',
        syncing: false,
        children: [],
      },
    ],
  };
};

describe('replaceLeafTabBookmarkTree', () => {
  beforeEach(() => {
    localStorage.clear();
    nextNodeId = 10;
    resetBookmarkTree();
    installBookmarkApiMock();
  });

  it('keeps local bookmarks that are absent from the live snapshot unless a tombstone exists', async () => {
    await replaceLeafTabBookmarkTree({
      folderLookup: {
        browser_root_toolbar: {
          parentId: null,
          title: '书签栏',
        },
        browser_root_other: {
          parentId: null,
          title: '其他书签',
        },
      },
      itemLookup: {},
      orderIdsByParent: {
        __root__: ['browser_root_toolbar', 'browser_root_other'],
        browser_root_toolbar: [],
        browser_root_other: [],
      },
      tombstoneIds: [],
      requestPermission: false,
    });

    expect(findNode('4')?.node.url).toBe('https://keep.example.com');
    expect(findNode('5')?.node.url).toBe('https://delete.example.com');
  });

  it('deletes only nodes whose entity id is tombstoned', async () => {
    localStorage.setItem(
      'leaftab_sync_bookmark_mapping_v1:roots:toolbar+other',
      JSON.stringify({
        version: 1,
        nodeIdToEntityId: {
          1: 'browser_root_toolbar',
          2: 'browser_root_other',
          4: 'bkm_keep',
          5: 'bkm_delete',
        },
        savedAt: '2026-06-05T00:00:00.000Z',
      }),
    );

    await replaceLeafTabBookmarkTree({
      folderLookup: {
        browser_root_toolbar: {
          parentId: null,
          title: '书签栏',
        },
        browser_root_other: {
          parentId: null,
          title: '其他书签',
        },
      },
      itemLookup: {},
      orderIdsByParent: {
        __root__: ['browser_root_toolbar', 'browser_root_other'],
        browser_root_toolbar: [],
        browser_root_other: [],
      },
      tombstoneIds: ['bkm_delete'],
      requestPermission: false,
    });

    expect(findNode('4')?.node.url).toBe('https://keep.example.com');
    expect(findNode('5')).toBeNull();
  });
});
