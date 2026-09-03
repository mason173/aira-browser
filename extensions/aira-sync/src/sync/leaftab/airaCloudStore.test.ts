import { afterEach, describe, expect, test, vi } from 'vitest';
import { LeafTabSyncAiraCloudStore } from './airaCloudStore';

const ORIGIN_HISTORY = {
  version: 1 as const,
  epochId: 'bookmark-history-v1-origin',
  retainedFrom: '1970-01-01T00:00:00.000Z',
};
const TEST_BOOKMARK_ENDPOINT = 'https://sync.example.test/sync/v4/bookmarks';

const EMPTY_WIRE_SNAPSHOT = {
  meta: {
    version: 2 as const,
    deviceId: 'desktop-a',
    generatedAt: '2026-08-04T00:00:00.000Z',
  },
  bookmarkFolders: [],
  bookmarkItems: [],
  bookmarkOrders: [],
  tombstones: [],
};

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('LeafTabSyncAiraCloudStore', () => {
  test('reads the shared v4 bookmark state together with its history descriptor', async () => {
    let requestedUrl = '';
    vi.stubGlobal('fetch', async (input: string | URL | Request) => {
      requestedUrl = String(input);
      return new Response(JSON.stringify({
        ok: true,
        protocol: 'aira-cloud-bookmarks-v4',
        commitId: 'commit-v4',
        history: ORIGIN_HISTORY,
        snapshot: EMPTY_WIRE_SNAPSHOT,
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    });
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token', TEST_BOOKMARK_ENDPOINT);

    const state = await store.readState();

    expect({
      requestedUrl,
      commitId: state.commitId,
      history: state.history,
      snapshotDeviceId: state.snapshot?.meta.deviceId,
    }).toEqual({
      requestedUrl: `${TEST_BOOKMARK_ENDPOINT}/read`,
      commitId: 'commit-v4',
      history: ORIGIN_HISTORY,
      snapshotDeviceId: 'desktop-a',
    });
  });

  test('writes the canonical snapshot and history to the shared v4 endpoint', async () => {
    let request: { url: string; body: Record<string, unknown> } | null = null;
    vi.stubGlobal('fetch', async (input: string | URL | Request, init?: RequestInit) => {
      request = {
        url: String(input),
        body: JSON.parse(String(init?.body || '{}')) as Record<string, unknown>,
      };
      return new Response(JSON.stringify({
        ok: true,
        protocol: 'aira-cloud-bookmarks-v4',
        commitId: 'commit-written',
        writtenAt: '2026-08-04T00:00:00.000Z',
      }), { status: 200 });
    });
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token', TEST_BOOKMARK_ENDPOINT);

    await store.writeState({
      snapshot: {
        meta: EMPTY_WIRE_SNAPSHOT.meta,
        bookmarkFolders: {},
        bookmarkItems: {},
        bookmarkOrders: {},
        tombstones: {},
      },
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: null,
      createdAt: '2026-08-04T00:00:00.000Z',
    });

    expect(request).toMatchObject({
      url: `${TEST_BOOKMARK_ENDPOINT}/write`,
      body: {
        uid: 'uid-a',
        source: 'airatab',
        protocol: 'aira-cloud-bookmarks-v4',
        deviceId: 'desktop-a',
        parentCommitId: null,
        history: ORIGIN_HISTORY,
      },
    });
  });

  test('rejects an incomplete v4 state that omits history', async () => {
    vi.stubGlobal('fetch', async () => new Response(JSON.stringify({
      ok: true,
      protocol: 'aira-cloud-bookmarks-v4',
      commitId: 'commit-incomplete',
      snapshot: EMPTY_WIRE_SNAPSHOT,
    }), { status: 200 }));
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token', TEST_BOOKMARK_ENDPOINT);

    await expect(store.readState()).rejects.toThrow('同步状态不完整');
  });

  test('stops when the server does not identify the v4 protocol', async () => {
    vi.stubGlobal('fetch', async () => new Response(JSON.stringify({
      ok: true,
      commitId: 'legacy-commit',
      history: ORIGIN_HISTORY,
      snapshot: EMPTY_WIRE_SNAPSHOT,
    }), { status: 200 }));
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token', TEST_BOOKMARK_ENDPOINT);

    await expect(store.readState()).rejects.toMatchObject({ code: 'client_update_required' });
  });

  test('rejects a non-canonical outgoing snapshot before making a network request', async () => {
    let requested = false;
    vi.stubGlobal('fetch', async () => {
      requested = true;
      return new Response(JSON.stringify({ ok: true, commitId: 'should-not-write' }), { status: 200 });
    });
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token', TEST_BOOKMARK_ENDPOINT);

    await expect(store.writeState({
      snapshot: {
        meta: EMPTY_WIRE_SNAPSHOT.meta,
        bookmarkFolders: {},
        bookmarkItems: {
          orphan: {
            id: 'orphan',
            type: 'bookmark-item',
            parentId: null,
            title: 'Orphan',
            url: 'https://example.com/',
            createdAt: '2026-08-04T00:00:00.000Z',
            updatedAt: '2026-08-04T00:00:00.000Z',
            updatedBy: 'desktop-a',
            revision: 1,
          },
        },
        bookmarkOrders: {},
        tombstones: {},
      },
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: null,
    })).rejects.toThrow('快照格式无效');
    expect(requested).toBe(false);
  });
});
