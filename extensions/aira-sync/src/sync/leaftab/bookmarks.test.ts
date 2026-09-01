import { afterEach, describe, expect, test, vi } from 'vitest';
import { LEAFTAB_BOOKMARK_MAPPING_KEY } from '@/features/sync/app/leafTabSyncStorageKeys';
import { captureLeafTabBookmarkTreeDraft } from './bookmarks';
import type { LeafTabSyncSnapshot } from './schema';

type FakeBookmarkNode = {
  id: string;
  title: string;
  url?: string;
  children?: FakeBookmarkNode[];
};

type FakeEvent = {
  addListener: (listener: () => void) => void;
  emit: () => void;
};

type BookmarkHarnessOptions = {
  getTreeDelayMs?: number;
  onGetTree?: (phase: 'start' | 'end') => void;
};

const createEvent = (): FakeEvent => {
  const listeners: Array<() => void> = [];
  return {
    addListener(listener) {
      listeners.push(listener);
    },
    emit() {
      listeners.forEach((listener) => listener());
    },
  };
};

const createStorage = () => {
  const values = new Map<string, string>();
  return {
    getItem(key: string) {
      return values.get(key) ?? null;
    },
    setItem(key: string, value: string) {
      values.set(key, value);
    },
    removeItem(key: string) {
      values.delete(key);
    },
  } as unknown as Storage;
};

const createTree = (
  itemParentId: 'folder-1' | 'folder-2',
  duplicateItems = false,
): FakeBookmarkNode => ({
  id: '0',
  title: '',
  children: [{
    id: '1',
    title: 'Bookmarks Bar',
    children: [{
      id: 'folder-1',
      title: 'Folder one',
      children: itemParentId === 'folder-1'
        ? [{
            id: 'bookmark-1',
            title: 'Example',
            url: 'https://example.com/',
          }, ...(duplicateItems ? [{
            id: 'bookmark-2',
            title: 'Example',
            url: 'https://example.com/',
          }] : [])]
        : [],
    }, {
      id: 'folder-2',
      title: 'Folder two',
      children: itemParentId === 'folder-2' ? [{
        id: 'bookmark-1',
        title: 'Example',
        url: 'https://example.com/',
      }] : [],
    }],
  }, {
    id: '2',
    title: 'Other Bookmarks',
    children: [],
  }],
});

const installBookmarksHarness = (
  tree: { current: FakeBookmarkNode },
  options: BookmarkHarnessOptions = {},
) => {
  const moved = createEvent();
  const bookmarks = {
    getTree(callback: (nodes: chrome.bookmarks.BookmarkTreeNode[]) => void) {
      options.onGetTree?.('start');
      const finish = () => {
        callback([tree.current] as unknown as chrome.bookmarks.BookmarkTreeNode[]);
        options.onGetTree?.('end');
      };
      if (options.getTreeDelayMs) {
        setTimeout(finish, options.getTreeDelayMs);
      } else {
        finish();
      }
    },
    onCreated: createEvent(),
    onRemoved: createEvent(),
    onChanged: createEvent(),
    onMoved: moved,
    onChildrenReordered: createEvent(),
    onImportEnded: createEvent(),
  };
  vi.stubGlobal('chrome', {
    bookmarks,
    runtime: {},
  } as unknown as typeof chrome);
  const storage = createStorage();
  vi.stubGlobal('localStorage', storage);
  return { moved, storage };
};

describe('LeafTab bookmark identity capture', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('keeps an entity ID when a bookmark moves between folders', async () => {
    const tree = { current: createTree('folder-1') };
    const { moved } = installBookmarksHarness(tree);

    const before = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-a',
    });
    const beforeItem = before.items.find((item) => item.localNodeId === 'bookmark-1');
    expect(beforeItem).toBeDefined();

    tree.current = createTree('folder-2');
    moved.emit();
    const after = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-a',
    });
    const afterItem = after.items.find((item) => item.localNodeId === 'bookmark-1');

    expect(afterItem?.entityId).toBe(beforeItem?.entityId);
    expect(afterItem?.parentId).not.toBe(beforeItem?.parentId);
  });

  test('uses the browser node ID when the persisted mapping is missing', async () => {
    const tree = { current: createTree('folder-1') };
    const { moved, storage } = installBookmarksHarness(tree);

    const before = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-a',
    });
    const beforeItem = before.items.find((item) => item.localNodeId === 'bookmark-1');
    expect(beforeItem).toBeDefined();

    storage.removeItem(LEAFTAB_BOOKMARK_MAPPING_KEY);
    tree.current = createTree('folder-2');
    moved.emit();
    const after = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-a',
    });
    const afterItem = after.items.find((item) => item.localNodeId === 'bookmark-1');

    expect(afterItem?.entityId).toBe(beforeItem?.entityId);
  });

  test('reuses a unique legacy entity ID from the sync baseline during migration', async () => {
    const tree = { current: createTree('folder-1') };
    const { storage } = installBookmarksHarness(tree);
    const previousSnapshot = {
      bookmarkFolders: {},
      bookmarkItems: {
        legacy_item: {
          id: 'legacy_item',
          type: 'bookmark-item',
          parentId: 'legacy_folder',
          title: 'Example',
          url: 'https://example.com/',
        },
      },
    } as unknown as LeafTabSyncSnapshot;

    storage.removeItem(LEAFTAB_BOOKMARK_MAPPING_KEY);
    const draft = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      previousSnapshot,
      deviceId: 'desktop-a',
    });

    expect(draft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('legacy_item');
  });

  test('reuses the matching legacy ID when the baseline has duplicate title and URL entries', async () => {
    const tree = { current: createTree('folder-1', true) };
    const { moved, storage } = installBookmarksHarness(tree);
    const previousSnapshot = {
      meta: {
        version: 2,
        deviceId: 'desktop-a',
        generatedAt: '2026-08-31T00:00:00.000Z',
      },
      bookmarkFolders: {
        'bkf_folder-one_ro4zn7': {
          id: 'bkf_folder-one_ro4zn7',
          type: 'bookmark-folder',
          parentId: 'browser_root_toolbar',
          title: 'Folder one',
        },
        'bkf_folder-two_1ac2vep': {
          id: 'bkf_folder-two_1ac2vep',
          type: 'bookmark-folder',
          parentId: 'browser_root_toolbar',
          title: 'Folder two',
        },
      },
      bookmarkItems: {
        'bkm_example_1c9wmzh': {
          id: 'bkm_example_1c9wmzh',
          type: 'bookmark-item',
          parentId: 'bkf_folder-one_ro4zn7',
          title: 'Example',
          url: 'https://example.com/',
        },
        'bkm_example_1bfxtwk': {
          id: 'bkm_example_1bfxtwk',
          type: 'bookmark-item',
          parentId: 'bkf_folder-one_ro4zn7',
          title: 'Example',
          url: 'https://example.com/',
        },
      },
      bookmarkOrders: {},
      tombstones: {},
    } as unknown as LeafTabSyncSnapshot;

    storage.removeItem(LEAFTAB_BOOKMARK_MAPPING_KEY);
    const draft = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      previousSnapshot,
      deviceId: 'desktop-a',
    });

    expect(draft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('bkm_example_1c9wmzh');
    expect(draft.items.find((item) => item.localNodeId === 'bookmark-2')?.entityId)
      .toBe('bkm_example_1bfxtwk');
    expect(new Set(draft.items.map((item) => item.entityId)).size).toBe(2);

    moved.emit();
    const nextDraft = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-a',
    });
    expect(nextDraft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('bkm_example_1c9wmzh');
    expect(nextDraft.items.find((item) => item.localNodeId === 'bookmark-2')?.entityId)
      .toBe('bkm_example_1bfxtwk');
  });

  test('rebuilds migration IDs after a no-baseline draft was cached', async () => {
    const tree = { current: createTree('folder-1') };
    const { storage } = installBookmarksHarness(tree);

    const initialDraft = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-a',
    });
    expect(initialDraft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('bkm_local_desktop-a_bookmark-1');

    storage.removeItem(LEAFTAB_BOOKMARK_MAPPING_KEY);
    const previousSnapshot = {
      meta: {
        version: 2,
        deviceId: 'desktop-a',
        generatedAt: '2026-08-31T00:00:00.000Z',
      },
      bookmarkFolders: {
        'bkf_folder-one_ro4zn7': {
          id: 'bkf_folder-one_ro4zn7',
          type: 'bookmark-folder',
          parentId: 'browser_root_toolbar',
          title: 'Folder one',
        },
      },
      bookmarkItems: {
        'bkm_example_1c9wmzh': {
          id: 'bkm_example_1c9wmzh',
          type: 'bookmark-item',
          parentId: 'bkf_folder-one_ro4zn7',
          title: 'Example',
          url: 'https://example.com/',
        },
      },
      bookmarkOrders: {},
      tombstones: {},
    } as unknown as LeafTabSyncSnapshot;

    const migratedDraft = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      previousSnapshot,
      deviceId: 'desktop-a',
    });
    expect(migratedDraft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('bkm_example_1c9wmzh');
  });

  test('serializes captures with different migration contexts', async () => {
    const tree = { current: createTree('folder-1') };
    let activeTreeReads = 0;
    let maxConcurrentTreeReads = 0;
    const { storage } = installBookmarksHarness(tree, {
      getTreeDelayMs: 1,
      onGetTree(phase) {
        activeTreeReads += phase === 'start' ? 1 : -1;
        maxConcurrentTreeReads = Math.max(maxConcurrentTreeReads, activeTreeReads);
      },
    });
    const previousSnapshot = {
      meta: {
        version: 2,
        deviceId: 'desktop-a',
        generatedAt: '2026-08-31T00:00:00.000Z',
      },
      bookmarkFolders: {
        'bkf_folder-one_ro4zn7': {
          id: 'bkf_folder-one_ro4zn7',
          type: 'bookmark-folder',
          parentId: 'browser_root_toolbar',
          title: 'Folder one',
        },
      },
      bookmarkItems: {
        'bkm_example_1c9wmzh': {
          id: 'bkm_example_1c9wmzh',
          type: 'bookmark-item',
          parentId: 'bkf_folder-one_ro4zn7',
          title: 'Example',
          url: 'https://example.com/',
        },
      },
      bookmarkOrders: {},
      tombstones: {},
    } as unknown as LeafTabSyncSnapshot;

    storage.removeItem(LEAFTAB_BOOKMARK_MAPPING_KEY);
    const noBaselineCapture = captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-a',
    });
    const baselineCapture = captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      previousSnapshot,
      deviceId: 'desktop-a',
    });
    const [noBaselineDraft, baselineDraft] = await Promise.all([
      noBaselineCapture,
      baselineCapture,
    ]);

    expect(maxConcurrentTreeReads).toBe(1);
    expect(noBaselineDraft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('bkm_local_desktop-a_bookmark-1');
    expect(baselineDraft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('bkm_example_1c9wmzh');
  });

  test('ignores stale mapping reservations when restoring a legacy ID', async () => {
    const tree = { current: createTree('folder-1') };
    const { storage } = installBookmarksHarness(tree);
    storage.setItem(LEAFTAB_BOOKMARK_MAPPING_KEY, JSON.stringify({
      version: 1,
      nodeIdToEntityId: {
        'removed-bookmark': 'bkm_example_1c9wmzh',
      },
      savedAt: '2026-08-31T00:00:00.000Z',
    }));

    const previousSnapshot = {
      meta: {
        version: 2,
        deviceId: 'desktop-a',
        generatedAt: '2026-08-31T00:00:00.000Z',
      },
      bookmarkFolders: {
        'bkf_folder-one_ro4zn7': {
          id: 'bkf_folder-one_ro4zn7',
          type: 'bookmark-folder',
          parentId: 'browser_root_toolbar',
          title: 'Folder one',
        },
      },
      bookmarkItems: {
        'bkm_example_1c9wmzh': {
          id: 'bkm_example_1c9wmzh',
          type: 'bookmark-item',
          parentId: 'bkf_folder-one_ro4zn7',
          title: 'Example',
          url: 'https://example.com/',
        },
      },
      bookmarkOrders: {},
      tombstones: {},
    } as unknown as LeafTabSyncSnapshot;

    const draft = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      previousSnapshot,
      deviceId: 'desktop-a',
    });

    expect(draft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('bkm_example_1c9wmzh');
  });

  test('fills an unmapped duplicate from the remaining legacy candidate', async () => {
    const tree = { current: createTree('folder-1', true) };
    const { storage } = installBookmarksHarness(tree);
    storage.setItem(LEAFTAB_BOOKMARK_MAPPING_KEY, JSON.stringify({
      version: 1,
      nodeIdToEntityId: {
        'bookmark-1': 'bkm_example_1bfxtwk',
      },
      savedAt: '2026-08-31T00:00:00.000Z',
    }));

    const previousSnapshot = {
      meta: {
        version: 2,
        deviceId: 'desktop-a',
        generatedAt: '2026-08-31T00:00:00.000Z',
      },
      bookmarkFolders: {
        'bkf_folder-one_ro4zn7': {
          id: 'bkf_folder-one_ro4zn7',
          type: 'bookmark-folder',
          parentId: 'browser_root_toolbar',
          title: 'Folder one',
        },
      },
      bookmarkItems: {
        'bkm_example_1c9wmzh': {
          id: 'bkm_example_1c9wmzh',
          type: 'bookmark-item',
          parentId: 'bkf_folder-one_ro4zn7',
          title: 'Example',
          url: 'https://example.com/',
        },
        'bkm_example_1bfxtwk': {
          id: 'bkm_example_1bfxtwk',
          type: 'bookmark-item',
          parentId: 'bkf_folder-one_ro4zn7',
          title: 'Example',
          url: 'https://example.com/',
        },
      },
      bookmarkOrders: {},
      tombstones: {},
    } as unknown as LeafTabSyncSnapshot;

    const draft = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      previousSnapshot,
      deviceId: 'desktop-a',
    });

    expect(draft.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId)
      .toBe('bkm_example_1bfxtwk');
    expect(draft.items.find((item) => item.localNodeId === 'bookmark-2')?.entityId)
      .toBe('bkm_example_1c9wmzh');
    expect(new Set(draft.items.map((item) => item.entityId)).size).toBe(2);
  });

  test('separates fallback IDs from different installations with the same browser node ID', async () => {
    const firstTree = { current: createTree('folder-1') };
    installBookmarksHarness(firstTree);
    const first = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-a',
    });

    const secondTree = { current: createTree('folder-1') };
    installBookmarksHarness(secondTree);
    const second = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
      deviceId: 'desktop-b',
    });

    const firstEntityId = first.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId;
    const secondEntityId = second.items.find((item) => item.localNodeId === 'bookmark-1')?.entityId;
    expect(firstEntityId).toBe('bkm_local_desktop-a_bookmark-1');
    expect(secondEntityId).toBe('bkm_local_desktop-b_bookmark-1');
    expect(secondEntityId).not.toBe(firstEntityId);
  });
});
