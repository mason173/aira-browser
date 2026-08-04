import { describe, expect, test } from 'vitest';
import { parseCanonicalLeafTabSyncWireSnapshot, type LeafTabSyncWireSnapshot } from './schema';

const T0 = '2026-08-04T00:00:00.000Z';

const createValidWireSnapshot = (): LeafTabSyncWireSnapshot => ({
  meta: { version: 2, deviceId: 'desktop-a', generatedAt: T0 },
  bookmarkFolders: [{
    id: 'root-a',
    type: 'bookmark-folder',
    parentId: null,
    title: 'Root',
    createdAt: T0,
    updatedAt: T0,
    updatedBy: 'desktop-a',
    revision: 1,
  }],
  bookmarkItems: [{
    id: 'item-a',
    type: 'bookmark-item',
    parentId: 'root-a',
    title: 'A',
    url: 'https://example.com/a',
    createdAt: T0,
    updatedAt: T0,
    updatedBy: 'desktop-a',
    revision: 1,
  }],
  bookmarkOrders: [{
    type: 'bookmark-order',
    parentId: null,
    ids: ['root-a'],
    updatedAt: T0,
    updatedBy: 'desktop-a',
    revision: 1,
  }, {
    type: 'bookmark-order',
    parentId: 'root-a',
    ids: ['item-a'],
    updatedAt: T0,
    updatedBy: 'desktop-a',
    revision: 1,
  }],
  tombstones: [],
});

const malformedSnapshots: Array<[string, () => LeafTabSyncWireSnapshot]> = [
  ['an invalid tombstone timestamp', () => ({
    ...createValidWireSnapshot(),
    tombstones: [{
      id: 'deleted-a',
      type: 'bookmark-item',
      deletedAt: 'not-a-date',
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    }],
  })],
  ['a live entity and tombstone with the same identity', () => ({
    ...createValidWireSnapshot(),
    tombstones: [{
      id: 'item-a',
      type: 'bookmark-item',
      deletedAt: T0,
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    }],
  })],
  ['a live entity missing from its parent order', () => ({
    ...createValidWireSnapshot(),
    bookmarkOrders: createValidWireSnapshot().bookmarkOrders.map((order) => (
      order.parentId === 'root-a' ? { ...order, ids: [] } : order
    )),
  })],
  ['the same identity in shared and App-private partitions', () => ({
    ...createValidWireSnapshot(),
    appPrivateBookmarks: {
      bookmarkFolders: [],
      bookmarkItems: [],
      bookmarkOrders: [],
      tombstones: [{
        id: 'item-a',
        type: 'bookmark-item',
        deletedAt: T0,
        deletedBy: 'phone-a',
        lastKnownRevision: 1,
      }],
    },
  })],
];

describe('parseCanonicalLeafTabSyncWireSnapshot', () => {
  test.each(malformedSnapshots)('rejects %s', (_label, createSnapshot) => {
    expect(parseCanonicalLeafTabSyncWireSnapshot(createSnapshot())).toBeNull();
  });
});
