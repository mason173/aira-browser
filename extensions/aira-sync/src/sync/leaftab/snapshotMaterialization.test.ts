import { describe, expect, test } from 'vitest';
import type { LeafTabBookmarkTreeDraft } from './bookmarks';
import type { LeafTabSyncSnapshot } from './schema';
import { assertLeafTabBookmarkTreeMatchesSnapshot } from './snapshot';

const EXPECTED_SNAPSHOT: LeafTabSyncSnapshot = {
  meta: {
    version: 2,
    deviceId: 'phone-a',
    generatedAt: '2026-08-04T00:00:00.000Z',
  },
  bookmarkFolders: {
    browser_root_toolbar: {
      id: 'browser_root_toolbar',
      type: 'bookmark-folder',
      parentId: null,
      title: '书签栏',
      createdAt: '2026-08-04T00:00:00.000Z',
      updatedAt: '2026-08-04T00:00:00.000Z',
      updatedBy: 'phone-a',
      revision: 1,
    },
  },
  bookmarkItems: {
    item_a: {
      id: 'item_a',
      type: 'bookmark-item',
      parentId: 'browser_root_toolbar',
      title: 'Aira',
      url: 'https://aira.cool/',
      createdAt: '2026-08-04T00:00:00.000Z',
      updatedAt: '2026-08-04T00:00:00.000Z',
      updatedBy: 'phone-a',
      revision: 1,
    },
  },
  bookmarkOrders: {
    __root__: {
      type: 'bookmark-order',
      parentId: null,
      ids: ['browser_root_toolbar'],
      updatedAt: '2026-08-04T00:00:00.000Z',
      updatedBy: 'phone-a',
      revision: 1,
    },
    browser_root_toolbar: {
      type: 'bookmark-order',
      parentId: 'browser_root_toolbar',
      ids: ['item_a'],
      updatedAt: '2026-08-04T00:00:00.000Z',
      updatedBy: 'phone-a',
      revision: 1,
    },
  },
  tombstones: {},
};

describe('assertLeafTabBookmarkTreeMatchesSnapshot', () => {
  test('rejects an apply that silently omits a remote bookmark', () => {
    const incompleteTree: LeafTabBookmarkTreeDraft = {
      folders: [{
        entityId: 'browser_root_toolbar',
        localNodeId: '1',
        parentId: null,
        title: '书签栏',
      }],
      items: [],
      orderIdsByParent: {
        __root__: ['browser_root_toolbar'],
        browser_root_toolbar: [],
      },
      nodeIdToEntityId: { '1': 'browser_root_toolbar' },
    };

    expect(() => assertLeafTabBookmarkTreeMatchesSnapshot(incompleteTree, EXPECTED_SNAPSHOT))
      .toThrow('本地书签落地校验未通过');
  });
});

  test('accepts Chrome-normalized URLs and keeps javascript bookmarklets', () => {
    const snapshot: LeafTabSyncSnapshot = {
      ...EXPECTED_SNAPSHOT,
      bookmarkItems: {
        item_a: {
          ...EXPECTED_SNAPSHOT.bookmarkItems.item_a,
          url: 'https://aira.cool/foo bar',
        },
        bookmarklet: {
          id: 'bookmarklet',
          type: 'bookmark-item',
          parentId: 'browser_root_toolbar',
          title: 'Bookmarklet',
          url: 'javascript:alert(1)',
          createdAt: '2026-08-04T00:00:00.000Z',
          updatedAt: '2026-08-04T00:00:00.000Z',
          updatedBy: 'phone-a',
          revision: 1,
        },
      },
      bookmarkOrders: {
        ...EXPECTED_SNAPSHOT.bookmarkOrders,
        browser_root_toolbar: {
          ...EXPECTED_SNAPSHOT.bookmarkOrders.browser_root_toolbar,
          ids: ['item_a', 'bookmarklet'],
        },
      },
    };
    const tree: LeafTabBookmarkTreeDraft = {
      folders: [{
        entityId: 'browser_root_toolbar',
        localNodeId: '1',
        parentId: null,
        title: '书签栏',
      }],
      items: [{
        entityId: 'item_a',
        localNodeId: '10',
        parentId: 'browser_root_toolbar',
        title: 'Aira',
        url: 'https://aira.cool/foo%20bar',
      }, {
        entityId: 'bookmarklet',
        localNodeId: '11',
        parentId: 'browser_root_toolbar',
        title: 'Bookmarklet',
        url: 'javascript:alert(1)',
      }],
      orderIdsByParent: {
        __root__: ['browser_root_toolbar'],
        browser_root_toolbar: ['item_a', 'bookmarklet'],
      },
      nodeIdToEntityId: {
        '1': 'browser_root_toolbar',
        '10': 'item_a',
        '11': 'bookmarklet',
      },
    };

    expect(() => assertLeafTabBookmarkTreeMatchesSnapshot(tree, snapshot)).not.toThrow();
  });

