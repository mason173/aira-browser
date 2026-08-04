import { afterEach, describe, expect, test, vi } from 'vitest';
import { LeafTabSyncAiraCloudStore } from './airaCloudStore';

const ORIGIN_HISTORY = {
  version: 1 as const,
  epochId: 'bookmark-history-v1-origin',
  retainedFrom: '1970-01-01T00:00:00.000Z',
};

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
  test('reads the shared v3 bookmark state together with its history descriptor', async () => {
    let requestedUrl = '';
    vi.stubGlobal('fetch', async (input: string | URL | Request) => {
      requestedUrl = String(input);
      return new Response(JSON.stringify({
        ok: true,
        commitId: 'commit-v3',
        history: ORIGIN_HISTORY,
        snapshot: EMPTY_WIRE_SNAPSHOT,
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    });
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token');

    const state = await store.readState();

    expect({
      requestedUrl,
      commitId: state.commitId,
      history: state.history,
      snapshotDeviceId: state.snapshot?.meta.deviceId,
    }).toEqual({
      requestedUrl: 'https://api.aira.cool/sync/v3/bookmarks/read',
      commitId: 'commit-v3',
      history: ORIGIN_HISTORY,
      snapshotDeviceId: 'desktop-a',
    });
  });

  test('writes the canonical snapshot and history to the shared v3 endpoint', async () => {
    let request: { url: string; body: Record<string, unknown> } | null = null;
    vi.stubGlobal('fetch', async (input: string | URL | Request, init?: RequestInit) => {
      request = {
        url: String(input),
        body: JSON.parse(String(init?.body || '{}')) as Record<string, unknown>,
      };
      return new Response(JSON.stringify({
        ok: true,
        commitId: 'commit-written',
        writtenAt: '2026-08-04T00:00:00.000Z',
      }), { status: 200 });
    });
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token');

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
      url: 'https://api.aira.cool/sync/v3/bookmarks/write',
      body: {
        uid: 'uid-a',
        source: 'airatab',
        deviceId: 'desktop-a',
        parentCommitId: null,
        history: ORIGIN_HISTORY,
      },
    });
  });

  test('rejects an incomplete v3 state that omits history', async () => {
    vi.stubGlobal('fetch', async () => new Response(JSON.stringify({
      ok: true,
      commitId: 'commit-incomplete',
      snapshot: EMPTY_WIRE_SNAPSHOT,
    }), { status: 200 }));
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token');

    await expect(store.readState()).rejects.toThrow('同步状态不完整');
  });

  test('rejects a non-canonical outgoing snapshot before making a network request', async () => {
    let requested = false;
    vi.stubGlobal('fetch', async () => {
      requested = true;
      return new Response(JSON.stringify({ ok: true, commitId: 'should-not-write' }), { status: 200 });
    });
    const store = new LeafTabSyncAiraCloudStore('uid-a', 'desktop-token');

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
