import { describe, expect, test } from 'vitest';
import { mergeLeafTabSyncSnapshot, mergeLeafTabSyncSnapshotWithoutBaseline } from './merge';
import {
  parseCanonicalLeafTabSyncWireSnapshot,
  toLeafTabSyncWireSnapshot,
  type LeafTabSyncSnapshot,
} from './schema';

const T0 = '2026-08-04T00:00:00.000Z';
const ROOT_ID = 'browser_root_toolbar';
const COLLIDING_ID = 'cross-type-id';

const createSnapshot = (
  deviceId: string,
  options: {
    includeLiveItem?: boolean;
    includeFolderTombstone?: boolean;
    includeItemTombstone?: boolean;
  } = {},
): LeafTabSyncSnapshot => ({
  meta: { version: 2, deviceId, generatedAt: T0 },
  bookmarkFolders: {
    [ROOT_ID]: {
      id: ROOT_ID,
      type: 'bookmark-folder',
      parentId: null,
      title: 'Root',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1,
    },
  },
  bookmarkItems: options.includeLiveItem ? {
    [COLLIDING_ID]: {
      id: COLLIDING_ID,
      type: 'bookmark-item',
      parentId: ROOT_ID,
      title: 'Live item',
      url: 'https://example.com/live',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1,
    },
  } : {},
  bookmarkOrders: {
    __root__: {
      type: 'bookmark-order',
      parentId: null,
      ids: [ROOT_ID],
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1,
    },
    [ROOT_ID]: {
      type: 'bookmark-order',
      parentId: ROOT_ID,
      ids: options.includeLiveItem ? [COLLIDING_ID] : [],
      updatedAt: T0,
      updatedBy: deviceId,
      revision: options.includeLiveItem ? 2 : 1,
    },
  },
  tombstones: options.includeFolderTombstone || options.includeItemTombstone ? {
    [`${options.includeItemTombstone ? 'bookmark-item' : 'bookmark-folder'}|${COLLIDING_ID}`]: {
      id: COLLIDING_ID,
      type: options.includeItemTombstone ? 'bookmark-item' : 'bookmark-folder',
      deletedAt: T0,
      deletedBy: deviceId,
      lastKnownRevision: 1,
    },
  } : {},
});

describe('mergeLeafTabSyncSnapshot', () => {
  test('keeps a canonical result when a live entity meets an opposite-type tombstone with the same ID', () => {
    const base = createSnapshot('baseline');
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    const remote = createSnapshot('phone-a', { includeFolderTombstone: true });

    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(local))).not.toBeNull();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(remote))).not.toBeNull();

    const merged = mergeLeafTabSyncSnapshot(base, local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(merged.bookmarkItems[COLLIDING_ID]).toBeDefined();
    expect(merged.tombstones[`bookmark-folder|${COLLIDING_ID}`]).toBeUndefined();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(merged))).not.toBeNull();
  });

  test('applies the same opposite-type rule when no provider baseline exists', () => {
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    const remote = createSnapshot('phone-a', { includeFolderTombstone: true });

    const merged = mergeLeafTabSyncSnapshotWithoutBaseline(local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(merged.bookmarkItems[COLLIDING_ID]).toBeDefined();
    expect(merged.tombstones[`bookmark-folder|${COLLIDING_ID}`]).toBeUndefined();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(merged))).not.toBeNull();
  });

  test('still propagates an ordinary same-type deletion', () => {
    const baseline = createSnapshot('baseline', { includeLiveItem: true });
    const local = createSnapshot('desktop-a', { includeLiveItem: true });
    const remote = createSnapshot('phone-a', { includeItemTombstone: true });

    const merged = mergeLeafTabSyncSnapshot(baseline, local, remote, {
      deviceId: 'desktop-a',
      generatedAt: T0,
    }).snapshot;

    expect(merged.bookmarkItems[COLLIDING_ID]).toBeUndefined();
    expect(merged.tombstones[`bookmark-item|${COLLIDING_ID}`]).toBeDefined();
    expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(merged))).not.toBeNull();
  });
});
