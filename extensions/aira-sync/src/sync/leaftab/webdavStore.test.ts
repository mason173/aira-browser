import { afterEach, describe, expect, test, vi } from 'vitest';

vi.mock('@/utils/extensionPermissions', () => ({
  ensureOriginPermission: async () => true,
}));

import { LeafTabSyncWebdavStore } from './webdavStore';
import type { LeafTabSyncHistoryDescriptor, LeafTabSyncSnapshot } from './schema';

const ORIGIN_HISTORY = {
  version: 1 as const,
  epochId: 'bookmark-history-v1-origin',
  retainedFrom: '1970-01-01T00:00:00.000Z',
};

afterEach(() => {
  vi.unstubAllGlobals();
});

const createMemoryWebdavFetch = () => {
  const files = new Map<string, { body: string; etag: string }>();
  let revision = 0;
  let rejectNextSnapshotPut = false;
  const snapshotWrites: Array<{ url: string; body: string; headers: Headers }> = [];
  const fetcher = async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const method = String(init?.method || 'GET').toUpperCase();
    const headers = new Headers(init?.headers);
    const current = files.get(url);
    if (method === 'MKCOL') return new Response(null, { status: 201 });
    if (method === 'GET') {
      if (!current) return new Response(null, { status: 404 });
      return new Response(current.body, { status: 200, headers: { ETag: current.etag } });
    }
    if (method === 'DELETE') {
      files.delete(url);
      return new Response(null, { status: 204 });
    }
    if (method === 'PUT') {
      if (rejectNextSnapshotPut && url.endsWith('/snapshot.json')) {
        rejectNextSnapshotPut = false;
        return new Response(null, { status: 412 });
      }
      if (headers.get('If-None-Match') === '*' && current) {
        return new Response(null, { status: 412 });
      }
      const ifMatch = headers.get('If-Match');
      if (ifMatch && (!current || current.etag !== ifMatch)) {
        return new Response(null, { status: 412 });
      }
      revision += 1;
      const body = String(init?.body || '');
      const next = { body, etag: `"revision-${revision}"` };
      files.set(url, next);
      if (url.endsWith('/snapshot.json')) {
        snapshotWrites.push({ url, body, headers });
      }
      return new Response(null, { status: current ? 204 : 201, headers: { ETag: next.etag } });
    }
    return new Response(null, { status: 405 });
  };
  return {
    fetcher,
    files,
    snapshotWrites,
    rejectNextSnapshotWrite: () => { rejectNextSnapshotPut = true; },
  };
};

const EMPTY_SNAPSHOT: LeafTabSyncSnapshot = {
  meta: {
    version: 2,
    deviceId: 'desktop-a',
    generatedAt: '2026-08-04T00:00:00.000Z',
  },
  bookmarkFolders: {},
  bookmarkItems: {},
  bookmarkOrders: {},
  tombstones: {},
};

describe('LeafTabSyncWebdavStore', () => {
  test('reads only the g3 version-2 bookmark envelope with its history descriptor', async () => {
    let requestedUrl = '';
    vi.stubGlobal('fetch', async (input: string | URL | Request) => {
      requestedUrl = String(input);
      return new Response(JSON.stringify({
        version: 2,
        history: ORIGIN_HISTORY,
        commitId: 'commit-webdav-v2',
        parentCommitId: null,
        deviceId: 'desktop-a',
        createdAt: '2026-08-04T00:00:00.000Z',
        snapshot: {
          meta: {
            version: 2,
            deviceId: 'desktop-a',
            generatedAt: '2026-08-04T00:00:00.000Z',
          },
          bookmarkFolders: [],
          bookmarkItems: [],
          bookmarkOrders: [],
          tombstones: [],
        },
      }), {
        status: 200,
        headers: { ETag: '"revision-1"' },
      });
    });
    const store = new LeafTabSyncWebdavStore({
      url: 'https://dav.example',
      requestPermission: false,
    });

    const state = await store.readState();

    expect({
      requestedUrl,
      commitId: state.commitId,
      history: state.history,
    }).toEqual({
      requestedUrl: 'https://dav.example/aira/g3/bookmarks/snapshot.json',
      commitId: 'commit-webdav-v2',
      history: ORIGIN_HISTORY,
    });
  });

  test('first publication writes a g3 version-2 history envelope with create-only CAS', async () => {
    const memory = createMemoryWebdavFetch();
    vi.stubGlobal('fetch', memory.fetcher);
    const store = new LeafTabSyncWebdavStore({
      url: 'https://dav-write.example',
      requestPermission: false,
    });

    const result = await store.writeState({
      snapshot: EMPTY_SNAPSHOT,
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: null,
      createdAt: '2026-08-04T00:00:00.000Z',
    });
    const publication = memory.snapshotWrites[0];
    const envelope = JSON.parse(publication.body) as Record<string, unknown>;

    expect({
      url: publication.url,
      ifNoneMatch: publication.headers.get('If-None-Match'),
      version: envelope.version,
      history: envelope.history,
      commitId: envelope.commitId,
    }).toEqual({
      url: 'https://dav-write.example/aira/g3/bookmarks/snapshot.json',
      ifNoneMatch: '*',
      version: 2,
      history: ORIGIN_HISTORY,
      commitId: result.commitId,
    });
  });

  test('rejects a history frontier rollback before replacing the existing WebDAV snapshot', async () => {
    const memory = createMemoryWebdavFetch();
    vi.stubGlobal('fetch', memory.fetcher);
    const store = new LeafTabSyncWebdavStore({
      url: 'https://dav-history.example',
      requestPermission: false,
    });
    const newerHistory: LeafTabSyncHistoryDescriptor = {
      version: 1,
      epochId: 'bookmark-history-v1-newer',
      retainedFrom: '2026-05-01T00:00:00.000Z',
    };
    const first = await store.writeState({
      snapshot: EMPTY_SNAPSHOT,
      history: newerHistory,
      deviceId: 'desktop-a',
      parentCommitId: null,
      createdAt: '2026-08-04T00:00:00.000Z',
    });

    await expect(store.writeState({
      snapshot: EMPTY_SNAPSHOT,
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: first.commitId,
      createdAt: '2026-08-04T00:01:00.000Z',
    })).rejects.toThrow('历史边界不能回退');
    expect(memory.snapshotWrites).toHaveLength(1);
  });

  test('rejects the retired WebDAV version-1 envelope instead of compatibility-reading it', async () => {
    vi.stubGlobal('fetch', async () => new Response(JSON.stringify({
      version: 1,
      commitId: 'commit-v1',
      parentCommitId: null,
      deviceId: 'desktop-a',
      createdAt: '2026-08-04T00:00:00.000Z',
      snapshot: {
        meta: EMPTY_SNAPSHOT.meta,
        bookmarkFolders: [],
        bookmarkItems: [],
        bookmarkOrders: [],
        tombstones: [],
      },
    }), { status: 200, headers: { ETag: '"revision-v1"' } }));
    const store = new LeafTabSyncWebdavStore({
      url: 'https://dav-v1.example',
      requestPermission: false,
    });

    await expect(store.readState()).rejects.toThrow('快照格式无效');
  });

  test('does not overwrite a snapshot whose commit changed on another device', async () => {
    const memory = createMemoryWebdavFetch();
    vi.stubGlobal('fetch', memory.fetcher);
    const store = new LeafTabSyncWebdavStore({
      url: 'https://dav-parent-race.example',
      requestPermission: false,
    });
    const first = await store.writeState({
      snapshot: EMPTY_SNAPSHOT,
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: null,
      createdAt: '2026-08-04T00:00:00.000Z',
    });
    const snapshotUrl = 'https://dav-parent-race.example/aira/g3/bookmarks/snapshot.json';
    const externalEnvelope = JSON.parse(memory.files.get(snapshotUrl)!.body) as Record<string, unknown>;
    externalEnvelope.commitId = 'commit-from-other-device';
    memory.files.set(snapshotUrl, {
      body: JSON.stringify(externalEnvelope),
      etag: '"external-revision"',
    });

    await expect(store.writeState({
      snapshot: EMPTY_SNAPSHOT,
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: first.commitId,
      createdAt: '2026-08-04T00:01:00.000Z',
    })).rejects.toThrow('远端已更新');
    expect(JSON.parse(memory.files.get(snapshotUrl)!.body)).toMatchObject({
      commitId: 'commit-from-other-device',
    });
  });

  test('does not overwrite a snapshot when its ETag becomes stale during the update', async () => {
    const memory = createMemoryWebdavFetch();
    vi.stubGlobal('fetch', memory.fetcher);
    const store = new LeafTabSyncWebdavStore({
      url: 'https://dav-etag-race.example',
      requestPermission: false,
    });
    const first = await store.writeState({
      snapshot: EMPTY_SNAPSHOT,
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: null,
      createdAt: '2026-08-04T00:00:00.000Z',
    });
    memory.rejectNextSnapshotWrite();

    await expect(store.writeState({
      snapshot: {
        ...EMPTY_SNAPSHOT,
        meta: { ...EMPTY_SNAPSHOT.meta, generatedAt: '2026-08-04T00:01:00.000Z' },
      },
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: first.commitId,
      createdAt: '2026-08-04T00:01:00.000Z',
    })).rejects.toThrow('远端已被其他设备更新');
    expect(memory.snapshotWrites).toHaveLength(1);
  });

  test('rejects a non-canonical outgoing snapshot before probing WebDAV', async () => {
    let requested = false;
    vi.stubGlobal('fetch', async () => {
      requested = true;
      return new Response(null, { status: 500 });
    });
    const store = new LeafTabSyncWebdavStore({
      url: 'https://dav-invalid.example',
      requestPermission: false,
    });

    await expect(store.writeState({
      snapshot: {
        ...EMPTY_SNAPSHOT,
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
      },
      history: ORIGIN_HISTORY,
      deviceId: 'desktop-a',
      parentCommitId: null,
    })).rejects.toThrow('快照格式无效');
    expect(requested).toBe(false);
  });
});
