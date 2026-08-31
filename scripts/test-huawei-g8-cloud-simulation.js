#!/usr/bin/env node

'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const HEAD_TABLE = 'AiraG8BookmarkHeads';
const BLOCK_TABLE = 'AiraG8BookmarkBlocks';
const BUCKET_COUNT = 64;
const INDEX_SHARD_COUNT = 64;
const MAX_ROW_BYTES = 12 * 1024;
const MAX_PAGE_BYTES = 10 * 1024;
const STORAGE_EPOCH_MS = 90 * 24 * 60 * 60 * 1000;
const STORAGE_EPOCH_QUARANTINE_MS = 7 * 24 * 60 * 60 * 1000;
const LANES = ['live', 'order', 'tombstone'];

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function byteCount(value) {
  return Buffer.byteLength(value, 'utf8');
}

function stableRecordKey(record) {
  return `${record.p}|${record.k}|${record.i}|${record.s}`;
}

function recordLane(record) {
  if (record.k === 'tombstone') {
    return 'tombstone';
  }
  if (record.k === 'orderPart') {
    return 'order';
  }
  return 'live';
}

function bucketIndex(record) {
  return Number.parseInt(sha256(stableRecordKey(record)).slice(0, 8), 16) % BUCKET_COUNT;
}

function blockRowId(storageEpoch, recordKind, logicalId) {
  return `${storageEpoch}|${recordKind}|${logicalId}`;
}

function headRowId(accountUid, deviceId) {
  const slotId = sha256(deviceId);
  return [accountUid, 'g8', 'head', slotId]
    .map((value) => `${value.length}:${value}`)
    .join('|');
}

function cloneSnapshot(snapshot) {
  return new Map(Array.from(snapshot, ([key, value]) => [key, { ...value }]));
}

function snapshotFingerprint(snapshot) {
  return sha256(JSON.stringify(Array.from(snapshot)
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, record]) => [key, record.d])));
}

function recordVersion(record) {
  const data = JSON.parse(record.d);
  return Number(data.revision ?? data.lastKnownRevision ?? 0);
}

function mergeSnapshots(...snapshots) {
  const merged = new Map();
  for (const snapshot of snapshots) {
    for (const [key, record] of snapshot) {
      const existing = merged.get(key);
      if (existing === undefined || recordVersion(record) > recordVersion(existing) ||
        (recordVersion(record) === recordVersion(existing) && record.d > existing.d)) {
        merged.set(key, { ...record });
      }
    }
  }
  return merged;
}

function createBookmarkSnapshot(itemCount, updatedBy = 'seed-device') {
  const snapshot = new Map();
  const createdAt = '2026-01-01T00:00:00.000Z';
  const folder = {
    p: 'shared',
    k: 'folder',
    i: 'folder-main',
    s: 0,
    d: JSON.stringify({
      id: 'folder-main',
      type: 'bookmark-folder',
      parentId: null,
      title: 'Bookmarks',
      createdAt,
      updatedAt: createdAt,
      updatedBy,
      revision: 1
    })
  };
  snapshot.set(stableRecordKey(folder), folder);

  const itemIds = [];
  for (let index = 0; index < itemCount; index += 1) {
    const id = `item-${String(index).padStart(4, '0')}`;
    itemIds.push(id);
    const item = {
      p: 'shared',
      k: 'item',
      i: id,
      s: 0,
      d: JSON.stringify({
        id,
        type: 'bookmark-item',
        parentId: 'folder-main',
        title: `Bookmark ${String(index).padStart(4, '0')}`,
        url: `https://example.com/bookmarks/${String(index).padStart(4, '0')}`,
        createdAt,
        updatedAt: createdAt,
        updatedBy,
        revision: 1
      })
    };
    snapshot.set(stableRecordKey(item), item);
  }

  const rootOrderPart = {
    p: 'shared',
    k: 'orderPart',
    i: '__root__',
    s: 0,
    d: JSON.stringify({
      type: 'bookmark-order-part',
      parentId: null,
      ids: ['folder-main'],
      updatedAt: createdAt,
      updatedBy,
      revision: 1,
      partIndex: 0,
      partCount: 1
    })
  };
  snapshot.set(stableRecordKey(rootOrderPart), rootOrderPart);

  const partCount = Math.max(1, Math.ceil(itemIds.length / 64));
  for (let partIndex = 0; partIndex < partCount; partIndex += 1) {
    const orderPart = {
      p: 'shared',
      k: 'orderPart',
      i: 'folder-main',
      s: partIndex,
      d: JSON.stringify({
        type: 'bookmark-order-part',
        parentId: 'folder-main',
        ids: itemIds.slice(partIndex * 64, (partIndex + 1) * 64),
        updatedAt: createdAt,
        updatedBy,
        revision: 1,
        partIndex,
        partCount
      })
    };
    snapshot.set(stableRecordKey(orderPart), orderPart);
  }

  for (let index = 0; index < 3; index += 1) {
    const tombstone = {
      p: 'shared',
      k: 'tombstone',
      i: `bookmark-item|retired-${index}`,
      s: 0,
      d: JSON.stringify({
        id: `retired-${index}`,
        type: 'bookmark-item',
        deletedAt: '2026-01-02T00:00:00.000Z',
        deletedBy: updatedBy,
        lastKnownRevision: 1
      })
    };
    snapshot.set(stableRecordKey(tombstone), tombstone);
  }
  return snapshot;
}

function editItem(snapshot, itemId, title, updatedBy) {
  const next = cloneSnapshot(snapshot);
  const key = `shared|item|${itemId}|0`;
  const existing = next.get(key);
  assert.ok(existing, `missing item ${itemId}`);
  const data = JSON.parse(existing.d);
  data.title = title;
  data.updatedAt = '2026-02-01T00:00:00.000Z';
  data.updatedBy = updatedBy;
  data.revision += 1;
  next.set(key, { ...existing, d: JSON.stringify(data) });
  return next;
}

function addItem(snapshot, itemId, updatedBy) {
  const next = cloneSnapshot(snapshot);
  const record = {
    p: 'shared',
    k: 'item',
    i: itemId,
    s: 0,
    d: JSON.stringify({
      id: itemId,
      type: 'bookmark-item',
      parentId: 'folder-main',
      title: `Unique ${itemId}`,
      url: `https://example.com/${itemId}`,
      createdAt: '2026-03-01T00:00:00.000Z',
      updatedAt: '2026-03-01T00:00:00.000Z',
      updatedBy,
      revision: 1
    })
  };
  next.set(stableRecordKey(record), record);
  const orderIds = readOrderIds(next, 'folder-main');
  if (!orderIds.includes(itemId)) {
    orderIds.push(itemId);
  }
  return writeOrderIds(next, 'folder-main', orderIds, updatedBy);
}

function orderLogicalKey(parentId) {
  return parentId ?? '__root__';
}

function readOrderIds(snapshot, parentId) {
  const logicalKey = orderLogicalKey(parentId);
  return Array.from(snapshot.values())
    .filter((record) => record.p === 'shared' && record.k === 'orderPart' && record.i === logicalKey)
    .sort((left, right) => left.s - right.s)
    .flatMap((record) => JSON.parse(record.d).ids);
}

function writeOrderIds(snapshot, parentId, ids, updatedBy) {
  const next = cloneSnapshot(snapshot);
  const logicalKey = orderLogicalKey(parentId);
  const existingParts = Array.from(next.values())
    .filter((record) => record.p === 'shared' && record.k === 'orderPart' && record.i === logicalKey);
  const revision = existingParts.reduce((maximum, record) => {
    return Math.max(maximum, Number(JSON.parse(record.d).revision ?? 0));
  }, 0) + 1;
  existingParts.forEach((record) => next.delete(stableRecordKey(record)));
  const partCount = Math.max(1, Math.ceil(ids.length / 64));
  for (let partIndex = 0; partIndex < partCount; partIndex += 1) {
    const orderPart = {
      p: 'shared',
      k: 'orderPart',
      i: logicalKey,
      s: partIndex,
      d: JSON.stringify({
        type: 'bookmark-order-part',
        parentId,
        ids: ids.slice(partIndex * 64, (partIndex + 1) * 64),
        updatedAt: '2026-03-01T00:00:00.000Z',
        updatedBy,
        revision,
        partIndex,
        partCount
      })
    };
    next.set(stableRecordKey(orderPart), orderPart);
  }
  return next;
}

function addFolder(snapshot, folderId, updatedBy) {
  const next = cloneSnapshot(snapshot);
  const folder = {
    p: 'shared',
    k: 'folder',
    i: folderId,
    s: 0,
    d: JSON.stringify({
      id: folderId,
      type: 'bookmark-folder',
      parentId: null,
      title: `Folder ${folderId}`,
      createdAt: '2026-03-01T00:00:00.000Z',
      updatedAt: '2026-03-01T00:00:00.000Z',
      updatedBy,
      revision: 1
    })
  };
  next.set(stableRecordKey(folder), folder);
  const rootIds = readOrderIds(next, null);
  if (!rootIds.includes(folderId)) {
    rootIds.push(folderId);
  }
  return writeOrderIds(next, null, rootIds, updatedBy);
}

function moveItem(snapshot, itemId, targetFolderId, updatedBy) {
  let next = cloneSnapshot(snapshot);
  const key = `shared|item|${itemId}|0`;
  const existing = next.get(key);
  assert.ok(existing, `missing item ${itemId}`);
  const data = JSON.parse(existing.d);
  const sourceFolderId = data.parentId;
  data.parentId = targetFolderId;
  data.updatedAt = '2026-03-02T00:00:00.000Z';
  data.updatedBy = updatedBy;
  data.revision += 1;
  next.set(key, { ...existing, d: JSON.stringify(data) });
  next = writeOrderIds(
    next,
    sourceFolderId,
    readOrderIds(next, sourceFolderId).filter((id) => id !== itemId),
    updatedBy
  );
  const targetIds = readOrderIds(next, targetFolderId);
  if (!targetIds.includes(itemId)) {
    targetIds.push(itemId);
  }
  return writeOrderIds(next, targetFolderId, targetIds, updatedBy);
}

function deleteItem(snapshot, itemId, updatedBy) {
  let next = cloneSnapshot(snapshot);
  const key = `shared|item|${itemId}|0`;
  const existing = next.get(key);
  assert.ok(existing, `missing item ${itemId}`);
  const data = JSON.parse(existing.d);
  next.delete(key);
  next = writeOrderIds(
    next,
    data.parentId,
    readOrderIds(next, data.parentId).filter((id) => id !== itemId),
    updatedBy
  );
  const tombstone = {
    p: 'shared',
    k: 'tombstone',
    i: `bookmark-item|${itemId}`,
    s: 0,
    d: JSON.stringify({
      id: itemId,
      type: 'bookmark-item',
      deletedAt: '2026-03-03T00:00:00.000Z',
      deletedBy: updatedBy,
      lastKnownRevision: data.revision
    })
  };
  next.set(stableRecordKey(tombstone), tombstone);
  return next;
}

function snapshotHasItem(snapshot, itemId) {
  return snapshot.has(`shared|item|${itemId}|0`);
}

function snapshotHasTombstone(snapshot, itemId) {
  return snapshot.has(`shared|tombstone|bookmark-item|${itemId}|0`);
}

function assertCanonicalMutationSnapshot(snapshot) {
  const folders = Array.from(snapshot.values())
    .filter((record) => record.p === 'shared' && record.k === 'folder')
    .map((record) => JSON.parse(record.d));
  const items = Array.from(snapshot.values())
    .filter((record) => record.p === 'shared' && record.k === 'item')
    .map((record) => JSON.parse(record.d));
  const liveIds = new Set(folders.concat(items).map((entity) => entity.id));
  const tombstoneIds = Array.from(snapshot.values())
    .filter((record) => record.p === 'shared' && record.k === 'tombstone')
    .map((record) => JSON.parse(record.d).id);
  assert.ok(tombstoneIds.every((id) => !liveIds.has(id)), 'live/tombstone IDs must stay disjoint');
  const folderIds = new Set(folders.map((folder) => folder.id));
  const membership = new Map();
  for (const parentId of [null, ...folderIds]) {
    for (const id of readOrderIds(snapshot, parentId)) {
      assert.equal(membership.has(id), false, `duplicate order membership for ${id}`);
      membership.set(id, parentId);
    }
  }
  folders.concat(items).forEach((entity) => {
    assert.equal(membership.has(entity.id), true, `missing order membership for ${entity.id}`);
    assert.equal(membership.get(entity.id), entity.parentId, `wrong order parent for ${entity.id}`);
    assert.ok(entity.parentId === null || folderIds.has(entity.parentId), `unknown parent for ${entity.id}`);
  });
}

function buildProjection({
  accountUid,
  deviceId,
  commitId,
  parentCommitIds,
  snapshot,
  storageEpoch,
  updatedAt
}) {
  const recordsByBucket = Array.from({ length: BUCKET_COUNT }, () => []);
  const records = Array.from(snapshot.values())
    .sort((left, right) => stableRecordKey(left).localeCompare(stableRecordKey(right)));
  for (const record of records) {
    recordsByBucket[bucketIndex(record)].push(record);
  }

  const blocks = new Map();
  const references = [];
  for (let bucket = 0; bucket < recordsByBucket.length; bucket += 1) {
    const bucketRecords = recordsByBucket[bucket];
    for (const lane of LANES) {
      const laneRecords = bucketRecords.filter((record) => recordLane(record) === lane);
      let segmentIndex = 0;
      let page = [];
      const appendPage = () => {
        if (page.length === 0) {
          return;
        }
        const encoded = JSON.stringify({
          formatVersion: 1,
          bucketIndex: bucket,
          lane,
          segmentIndex,
          records: page
        });
        assert.ok(byteCount(encoded) <= MAX_PAGE_BYTES, 'chunk page exceeds 10 KiB');
        const chunkId = sha256(encoded);
        const rowId = blockRowId(storageEpoch, 'chunk', chunkId);
        blocks.set(rowId, {
          rowId,
          accountUid,
          recordKind: 'chunk',
          logicalId: chunkId,
          storageEpoch,
          data: encoded,
          updatedAt
        });
        references.push({ b: bucket, l: lane, s: segmentIndex, h: chunkId, n: page.length });
        segmentIndex += 1;
        page = [];
      };
      for (const record of laneRecords) {
        const candidate = page.concat(record);
        const candidateJson = JSON.stringify({
          formatVersion: 1,
          bucketIndex: bucket,
          lane,
          segmentIndex,
          records: candidate
        });
        if (byteCount(candidateJson) > MAX_PAGE_BYTES) {
          assert.ok(page.length > 0, 'single canonical record exceeds 10 KiB');
          appendPage();
        }
        page.push(record);
      }
      appendPage();
    }
  }

  const indexReferences = [];
  for (let shardIndex = 0; shardIndex < INDEX_SHARD_COUNT; shardIndex += 1) {
    const chunks = references.filter((reference) => reference.b === shardIndex);
    const encoded = JSON.stringify({ formatVersion: 1, shardIndex, chunks });
    assert.ok(byteCount(encoded) <= MAX_ROW_BYTES, 'index exceeds 12 KiB');
    const indexId = sha256(encoded);
    const rowId = blockRowId(storageEpoch, 'index', indexId);
    blocks.set(rowId, {
      rowId,
      accountUid,
      recordKind: 'index',
      logicalId: indexId,
      storageEpoch,
      data: encoded,
      updatedAt
    });
    indexReferences.push({ s: shardIndex, h: indexId, n: chunks.length });
  }

  const aggregateChecksum = sha256(JSON.stringify({
    bucketCount: BUCKET_COUNT,
    hasPrivateData: false,
    indexes: indexReferences
  }));
  const manifest = {
    formatVersion: 1,
    schemaVersion: 1,
    bucketCount: BUCKET_COUNT,
    storageEpoch,
    commitId,
    parentCommitIds: parentCommitIds.slice().sort(),
    deviceId,
    generatedAt: new Date(updatedAt).toISOString(),
    history: {
      version: 1,
      epochId: 'simulation-history-v1',
      retainedFrom: '2026-01-01T00:00:00.000Z'
    },
    updatedAt,
    hasPrivateData: false,
    indexes: indexReferences,
    physicalRecordCount: records.length,
    counts: {
      folderCount: records.filter((record) => record.k === 'folder').length,
      itemCount: records.filter((record) => record.k === 'item').length,
      orderCount: new Set(records.filter((record) => record.k === 'orderPart').map((record) => record.i)).size,
      tombstoneCount: records.filter((record) => record.k === 'tombstone').length,
      privateFolderCount: 0,
      privateItemCount: 0,
      privateOrderCount: 0,
      privateTombstoneCount: 0
    },
    aggregateChecksum
  };
  const encodedManifest = JSON.stringify(manifest);
  assert.ok(byteCount(encodedManifest) <= MAX_ROW_BYTES, 'Head exceeds 12 KiB');
  const rowId = headRowId(accountUid, deviceId);
  const head = {
    rowId,
    accountUid,
    recordKind: 'head',
    logicalId: commitId,
    storageEpoch,
    data: encodedManifest,
    updatedAt
  };
  return { manifest, head, blocks };
}

function sameRow(left, right) {
  return left !== undefined && right !== undefined &&
    left.rowId === right.rowId && left.logicalId === right.logicalId &&
    left.storageEpoch === right.storageEpoch && left.data === right.data &&
    left.updatedAt === right.updatedAt;
}

class InMemoryHuaweiCloud {
  constructor() {
    this.heads = new Map();
    this.blocks = new Map();
    this.events = [];
    this.failures = [];
    this.metrics = {
      syncCalls: new Map(),
      uploadedRows: 0,
      downloadedRows: 0,
      deletedRows: 0
    };
  }

  failNext(table, mode, message) {
    this.failures.push({ table, mode, message });
  }

  sync(device, table, mode) {
    const metricKey = `${mode}:${table}`;
    this.metrics.syncCalls.set(metricKey, (this.metrics.syncCalls.get(metricKey) ?? 0) + 1);
    this.events.push(`${mode}:${table}:begin`);
    const failureIndex = this.failures.findIndex((failure) => failure.table === table && failure.mode === mode);
    if (failureIndex >= 0) {
      const [failure] = this.failures.splice(failureIndex, 1);
      this.events.push(`${mode}:${table}:failed`);
      throw new Error(failure.message);
    }

    const cloudRows = table === HEAD_TABLE ? this.heads : this.blocks;
    const localRows = table === HEAD_TABLE ? device.heads : device.blocks;
    const dirtyUpserts = table === HEAD_TABLE ? device.dirtyHeadUpserts : device.dirtyBlockUpserts;
    const dirtyDeletes = table === HEAD_TABLE ? device.dirtyHeadDeletes : device.dirtyBlockDeletes;
    let changed = 0;

    if (mode === 'TIME_FIRST') {
      for (const rowId of dirtyDeletes) {
        if (cloudRows.delete(rowId)) {
          this.metrics.deletedRows += 1;
          changed += 1;
        }
      }
      dirtyDeletes.clear();
      for (const rowId of dirtyUpserts) {
        const row = localRows.get(rowId);
        assert.ok(row, `dirty ${table} row missing locally`);
        if (!sameRow(cloudRows.get(rowId), row)) {
          cloudRows.set(rowId, { ...row });
          this.metrics.uploadedRows += 1;
          changed += 1;
        }
      }
      dirtyUpserts.clear();
    } else {
      for (const [rowId, row] of cloudRows) {
        if (!sameRow(localRows.get(rowId), row)) {
          localRows.set(rowId, { ...row });
          this.metrics.downloadedRows += 1;
          changed += 1;
        }
      }
      for (const rowId of Array.from(localRows.keys())) {
        if (!cloudRows.has(rowId) && !dirtyUpserts.has(rowId)) {
          localRows.delete(rowId);
          changed += 1;
        }
      }
    }
    this.events.push(`${mode}:${table}:end:${changed}`);
  }

  rowCount() {
    return this.heads.size + this.blocks.size;
  }

  snapshotMetrics() {
    return {
      syncCalls: new Map(this.metrics.syncCalls),
      uploadedRows: this.metrics.uploadedRows,
      downloadedRows: this.metrics.downloadedRows,
      deletedRows: this.metrics.deletedRows
    };
  }
}

function metricDelta(after, before, key) {
  if (key.startsWith('sync:')) {
    const metricKey = key.slice('sync:'.length);
    return (after.syncCalls.get(metricKey) ?? 0) - (before.syncCalls.get(metricKey) ?? 0);
  }
  return after[key] - before[key];
}

class SimulatedHuaweiDevice {
  constructor(cloud, deviceId, snapshot = new Map(), accountUid = 'simulation-account') {
    this.cloud = cloud;
    this.deviceId = deviceId;
    this.accountUid = accountUid;
    this.localSnapshot = cloneSnapshot(snapshot);
    this.heads = new Map();
    this.blocks = new Map();
    this.dirtyHeadUpserts = new Set();
    this.dirtyBlockUpserts = new Set();
    this.dirtyHeadDeletes = new Set();
    this.dirtyBlockDeletes = new Set();
    this.commitSequence = 0;
  }

  cloudSync(table, mode) {
    this.cloud.sync(this, table, mode);
  }

  commitBarrier(table) {
    this.cloudSync(table, 'TIME_FIRST');
    this.cloudSync(table, 'CLOUD_FIRST');
  }

  stageRow(table, row) {
    const localRows = table === HEAD_TABLE ? this.heads : this.blocks;
    const upserts = table === HEAD_TABLE ? this.dirtyHeadUpserts : this.dirtyBlockUpserts;
    const deletes = table === HEAD_TABLE ? this.dirtyHeadDeletes : this.dirtyBlockDeletes;
    const existing = localRows.get(row.rowId);
    if (!sameRow(existing, row)) {
      localRows.set(row.rowId, { ...row });
      upserts.add(row.rowId);
      deletes.delete(row.rowId);
    }
  }

  stageDelete(table, rowId) {
    const localRows = table === HEAD_TABLE ? this.heads : this.blocks;
    const upserts = table === HEAD_TABLE ? this.dirtyHeadUpserts : this.dirtyBlockUpserts;
    const deletes = table === HEAD_TABLE ? this.dirtyHeadDeletes : this.dirtyBlockDeletes;
    if (localRows.delete(rowId)) {
      upserts.delete(rowId);
      deletes.add(rowId);
    }
  }

  parseLocalManifests() {
    const manifests = [];
    for (const row of this.heads.values()) {
      const manifest = JSON.parse(row.data);
      assert.equal(manifest.commitId, row.logicalId);
      assert.equal(manifest.storageEpoch, row.storageEpoch);
      assert.equal(row.rowId, headRowId(this.accountUid, manifest.deviceId));
      manifests.push({ manifest, rowId: row.rowId });
    }
    return manifests;
  }

  materialize(manifest) {
    const snapshot = new Map();
    let physicalRecordCount = 0;
    assert.equal(manifest.indexes.length, INDEX_SHARD_COUNT);
    for (const indexReference of manifest.indexes) {
      const indexRow = this.blocks.get(blockRowId(manifest.storageEpoch, 'index', indexReference.h));
      if (indexRow === undefined || sha256(indexRow.data) !== indexReference.h) {
        return null;
      }
      const index = JSON.parse(indexRow.data);
      if (index.shardIndex !== indexReference.s || index.chunks.length !== indexReference.n) {
        return null;
      }
      for (const chunkReference of index.chunks) {
        const chunkRow = this.blocks.get(blockRowId(manifest.storageEpoch, 'chunk', chunkReference.h));
        if (chunkRow === undefined || sha256(chunkRow.data) !== chunkReference.h) {
          return null;
        }
        const chunk = JSON.parse(chunkRow.data);
        if (chunk.bucketIndex !== chunkReference.b || chunk.lane !== chunkReference.l ||
          chunk.segmentIndex !== chunkReference.s || chunk.records.length !== chunkReference.n) {
          return null;
        }
        for (const record of chunk.records) {
          const key = stableRecordKey(record);
          if (bucketIndex(record) !== chunk.bucketIndex || recordLane(record) !== chunk.lane ||
            snapshot.has(key)) {
            return null;
          }
          snapshot.set(key, record);
          physicalRecordCount += 1;
        }
      }
    }
    const checksum = sha256(JSON.stringify({
      bucketCount: BUCKET_COUNT,
      hasPrivateData: manifest.hasPrivateData,
      indexes: manifest.indexes
    }));
    if (checksum !== manifest.aggregateChecksum || physicalRecordCount !== manifest.physicalRecordCount) {
      return null;
    }
    return snapshot;
  }

  localViableHeads() {
    const all = this.parseLocalManifests();
    const complete = new Map();
    for (const candidate of all) {
      const snapshot = this.materialize(candidate.manifest);
      if (snapshot !== null) {
        complete.set(candidate.manifest.commitId, { ...candidate, snapshot });
      }
    }
    const referenced = new Set();
    for (const candidate of complete.values()) {
      for (const parentId of candidate.manifest.parentCommitIds) {
        if (complete.has(parentId)) {
          referenced.add(parentId);
        }
      }
    }
    return Array.from(complete.values())
      .filter((candidate) => !referenced.has(candidate.manifest.commitId))
      .sort((left, right) => left.manifest.commitId.localeCompare(right.manifest.commitId));
  }

  readRemoteHeads() {
    this.cloudSync(HEAD_TABLE, 'CLOUD_FIRST');
    const manifests = this.parseLocalManifests();
    const completeBeforeBlockSync = manifests.filter((candidate) => this.materialize(candidate.manifest) !== null);
    if (completeBeforeBlockSync.length < manifests.length) {
      this.cloudSync(BLOCK_TABLE, 'CLOUD_FIRST');
    }
    const heads = this.localViableHeads();
    if (heads.length === 0 && manifests.length > 0) {
      throw new Error('Head rows exist but no complete snapshot can be materialized');
    }
    return heads;
  }

  resolveStorageEpoch(now) {
    let storageEpoch = Math.floor(Math.max(0, now) / STORAGE_EPOCH_MS) + 1;
    for (const { manifest } of this.parseLocalManifests()) {
      storageEpoch = Math.max(storageEpoch, manifest.storageEpoch);
    }
    return storageEpoch;
  }

  publishCurrent(parentCommitIds, now, options = {}) {
    const storageEpoch = this.resolveStorageEpoch(now);
    const commitId = `${this.deviceId}:${++this.commitSequence}:${snapshotFingerprint(this.localSnapshot).slice(0, 12)}`;
    const projection = buildProjection({
      accountUid: this.accountUid,
      deviceId: this.deviceId,
      commitId,
      parentCommitIds,
      snapshot: this.localSnapshot,
      storageEpoch,
      updatedAt: now
    });
    for (const row of projection.blocks.values()) {
      this.stageRow(BLOCK_TABLE, row);
    }
    this.commitBarrier(BLOCK_TABLE);
    assert.ok(this.materialize(projection.manifest), 'Blocks were not complete after confirmation');
    if (options.failAfterBlockConfirmation) {
      throw new Error('injected interruption after Blocks confirmation');
    }
    this.stageRow(HEAD_TABLE, projection.head);
    this.commitBarrier(HEAD_TABLE);
    assert.ok(sameRow(this.heads.get(projection.head.rowId), projection.head), 'Head was not confirmed');
    return { commitId, projection };
  }

  sync(now, options = {}) {
    const heads = this.readRemoteHeads();
    const remoteSnapshot = heads.length > 0
      ? mergeSnapshots(...heads.map((head) => head.snapshot))
      : new Map();
    const merged = mergeSnapshots(remoteSnapshot, this.localSnapshot);
    const remoteFingerprint = snapshotFingerprint(remoteSnapshot);
    const mergedFingerprint = snapshotFingerprint(merged);
    this.localSnapshot = merged;
    const shouldCommit = heads.length === 0
      ? merged.size > 0
      : heads.length > 1 || remoteFingerprint !== mergedFingerprint;
    if (!shouldCommit) {
      return { committed: false, heads };
    }
    const publication = this.publishCurrent(
      heads.map((head) => head.manifest.commitId),
      now,
      options
    );
    if (options.runGc) {
      publication.gcResult = this.runPhysicalGcSafely(now);
    }
    return { committed: true, heads, ...publication };
  }

  buildGcPlan(now) {
    const manifests = this.parseLocalManifests();
    if (manifests.length === 0) {
      return null;
    }
    const storageEpoch = Math.max(...manifests.map((candidate) => candidate.manifest.storageEpoch));
    const epochStartedAt = (storageEpoch - 1) * STORAGE_EPOCH_MS;
    if (storageEpoch <= 1 || now < epochStartedAt + STORAGE_EPOCH_QUARANTINE_MS) {
      return null;
    }
    const heads = this.localViableHeads();
    if (heads.length === 0 || heads.some((head) => head.manifest.storageEpoch !== storageEpoch)) {
      return null;
    }
    return {
      storageEpoch,
      supersededHeadRowIds: manifests
        .filter((candidate) => candidate.manifest.storageEpoch < storageEpoch)
        .map((candidate) => candidate.rowId)
        .sort()
    };
  }

  runPhysicalGc(now) {
    this.cloudSync(HEAD_TABLE, 'CLOUD_FIRST');
    const plan = this.buildGcPlan(now);
    if (plan === null) {
      return { status: 'skipped', deletedHeads: 0, deletedBlocks: 0 };
    }
    for (const rowId of plan.supersededHeadRowIds) {
      this.stageDelete(HEAD_TABLE, rowId);
    }
    if (plan.supersededHeadRowIds.length > 0) {
      this.commitBarrier(HEAD_TABLE);
    }
    assert.ok(plan.supersededHeadRowIds.every((rowId) => !this.cloud.heads.has(rowId)),
      'old Head deletion was not confirmed');
    const confirmedPlan = this.buildGcPlan(now);
    if (confirmedPlan === null || confirmedPlan.storageEpoch !== plan.storageEpoch ||
      confirmedPlan.supersededHeadRowIds.length > 0) {
      return { status: 'deferred', deletedHeads: plan.supersededHeadRowIds.length, deletedBlocks: 0 };
    }
    const oldBlockRowIds = Array.from(this.blocks.values())
      .filter((row) => row.storageEpoch < confirmedPlan.storageEpoch)
      .map((row) => row.rowId);
    for (const rowId of oldBlockRowIds) {
      this.stageDelete(BLOCK_TABLE, rowId);
    }
    if (oldBlockRowIds.length > 0) {
      this.commitBarrier(BLOCK_TABLE);
    }
    assert.ok(Array.from(this.cloud.blocks.values())
      .every((row) => row.storageEpoch >= confirmedPlan.storageEpoch), 'old Block deletion was not confirmed');
    return {
      status: 'completed',
      deletedHeads: plan.supersededHeadRowIds.length,
      deletedBlocks: oldBlockRowIds.length
    };
  }

  runPhysicalGcSafely(now) {
    try {
      return this.runPhysicalGc(now);
    } catch (error) {
      return { status: 'deferred', deletedHeads: 0, deletedBlocks: 0, error: error.message };
    }
  }
}

function assertProductionSourceContract() {
  const root = path.resolve(__dirname, '..');
  const owner = fs.readFileSync(path.join(
    root,
    'AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceRdbStoreOwner.ets'
  ), 'utf8');
  const repository = fs.readFileSync(path.join(
    root,
    'AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceBookmarkChunkRepository.ets'
  ), 'utf8');
  const remoteStore = fs.readFileSync(path.join(
    root,
    'AiraBrowser/entry/src/main/ets/data/sync/AiraHuaweiSpaceRemoteStore.ets'
  ), 'utf8');

  assert.match(owner, /HUAWEI_SPACE_BOOKMARK_HEAD_TABLE: string = 'AiraG8BookmarkHeads'/);
  assert.match(owner, /HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE: string = 'AiraG8BookmarkBlocks'/);
  assert.match(owner,
    /executeSql\(HUAWEI_SPACE_BOOKMARK_HEAD_SCHEMA\)[\s\S]*ensureColumn\([\s\S]*HUAWEI_SPACE_BOOKMARK_HEAD_TABLE,[\s\S]*'storageEpoch',[\s\S]*'INTEGER'[\s\S]*executeSql\(HUAWEI_SPACE_BOOKMARK_HEAD_ACCOUNT_KIND_INDEX\)/);
  assert.match(owner,
    /executeSql\(HUAWEI_SPACE_BOOKMARK_BLOCK_SCHEMA\)[\s\S]*ensureColumn\([\s\S]*HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE,[\s\S]*'storageEpoch',[\s\S]*'INTEGER'[\s\S]*executeSql\(HUAWEI_SPACE_BOOKMARK_BLOCK_ACCOUNT_KIND_INDEX\)/);
  assert.match(repository, /HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT: number = 64/);
  assert.match(repository, /HUAWEI_SPACE_BOOKMARK_INDEX_SHARD_COUNT: number = 64/);
  assert.match(repository, /HUAWEI_SPACE_BOOKMARK_MAX_ROW_JSON_BYTES: number = 12 \* 1024/);
  assert.match(repository, /HUAWEI_SPACE_BOOKMARK_MAX_PAGE_JSON_BYTES: number = 10 \* 1024/);
  assert.match(repository, /HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_MS: number = 90 \* 24 \* 60 \* 60 \* 1000/);
  assert.match(repository, /HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_QUARANTINE_MS: number = 7 \* 24 \* 60 \* 60 \* 1000/);
  assert.match(repository, /\['live', 'order', 'tombstone'\]/);

  const writeOffset = remoteStore.indexOf('writeSnapshotBlocks(store');
  const blockBarrierOffset = remoteStore.indexOf(
    'runIncrementalCommitBarrier(store, this.chunkRepository.getBlockCloudTableNames())',
    writeOffset
  );
  const confirmBlocksOffset = remoteStore.indexOf('confirmPublicationBlocks(store', blockBarrierOffset);
  const publishHeadOffset = remoteStore.indexOf('publishHead(store', confirmBlocksOffset);
  const headBarrierOffset = remoteStore.indexOf(
    'runIncrementalCommitBarrier(store, this.chunkRepository.getHeadCloudTableNames())',
    publishHeadOffset
  );
  assert.ok(writeOffset >= 0 && writeOffset < blockBarrierOffset && blockBarrierOffset < confirmBlocksOffset &&
    confirmBlocksOffset < publishHeadOffset && publishHeadOffset < headBarrierOffset,
  'production publication order drifted from Blocks-confirmed-before-Head');
  assert.match(remoteStore,
    /getHeadCloudTableNames\(\)[\s\S]*readMaterializedHeads\(store\)[\s\S]*needsBlockSync[\s\S]*getBlockCloudTableNames\(\)/);
}

function assertG7UpgradeSourceContract() {
  const root = path.resolve(__dirname, '..');
  const upgradeStore = fs.readFileSync(path.join(
    root,
    'AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceBookmarkUpgradeStore.ets'
  ), 'utf8');
  const coordinator = fs.readFileSync(path.join(
    root,
    'AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceCoordinator.ets'
  ), 'utf8');
  const configStore = fs.readFileSync(path.join(
    root,
    'AiraBrowser/entry/src/main/ets/services/sync/AiraSyncConfigStore.ets'
  ), 'utf8');

  assert.match(upgradeStore, /HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION: number = 8/);
  assert.match(coordinator,
    /runHuaweiSpaceBookmarkUpgradePreparation[\s\S]*affectedLegacySelection[\s\S]*prepareCurrentVersion\([\s\S]*prepareHuaweiSpaceBookmarkReenable\(\)/);
  assert.match(configStore,
    /prepareHuaweiSpaceBookmarkReenable[\s\S]*bookmarkSyncEnabled: activeHuaweiBookmark \? false : settings\.bookmarkSyncEnabled[\s\S]*huaweiSpace: \{/);
  assert.match(coordinator,
    /completeHuaweiSpaceBookmarkUpgradeIfNeeded[\s\S]*pendingBookmarkSyncAt[\s\S]*lastSuccessAt <= 0[\s\S]*bookmarkRuntime\.blocked[\s\S]*markCompleted\(\)/);
}

function assertFailurePolicySourceContract() {
  const root = path.resolve(__dirname, '..');
  const remoteStore = fs.readFileSync(path.join(
    root,
    'AiraBrowser/entry/src/main/ets/data/sync/AiraHuaweiSpaceRemoteStore.ets'
  ), 'utf8');
  const syncService = fs.readFileSync(path.join(
    root,
    'AiraBrowser/entry/src/main/ets/services/sync/SyncService.ets'
  ), 'utf8');

  for (const progressCode of ['UNKNOWN_ERROR', 'NETWORK_ERROR', 'LOCKED_BY_OTHERS']) {
    assert.match(remoteStore, new RegExp(`ProgressCode\\.${progressCode}[\\s\\S]{0,360}true`));
  }
  for (const progressCode of [
    'CLOUD_DISABLED',
    'RECORD_LIMIT_EXCEEDED',
    'NO_SPACE_FOR_ASSET',
    'BLOCKED_BY_NETWORK_STRATEGY'
  ]) {
    assert.match(remoteStore, new RegExp(`ProgressCode\\.${progressCode}[\\s\\S]{0,420}false`));
  }
  assert.match(syncService,
    /const blocked = activeProvider === 'huawei_space' &&[\s\S]*!isRetryableHuaweiSpaceBookmarkSyncError\(syncError\)[\s\S]*saveProviderRuntimeState\([\s\S]*blocked/);
}

function runScenario(name, scenario) {
  const result = scenario();
  process.stdout.write(`PASS ${name}\n`);
  return result;
}

function scenarioInitialPublication() {
  const cloud = new InMemoryHuaweiCloud();
  const writer = new SimulatedHuaweiDevice(cloud, 'device-a', createBookmarkSnapshot(620));
  const result = writer.sync(24 * 60 * 60 * 1000);
  assert.equal(result.committed, true);
  assert.equal(cloud.heads.size, 1);
  assert.ok(cloud.blocks.size < 180, `dense projection unexpectedly used ${cloud.blocks.size} Blocks`);
  const blockTime = cloud.events.indexOf(`TIME_FIRST:${BLOCK_TABLE}:begin`);
  const blockCloud = cloud.events.indexOf(`CLOUD_FIRST:${BLOCK_TABLE}:begin`, blockTime);
  const headTime = cloud.events.indexOf(`TIME_FIRST:${HEAD_TABLE}:begin`, blockCloud);
  const headCloud = cloud.events.indexOf(`CLOUD_FIRST:${HEAD_TABLE}:begin`, headTime);
  assert.ok(blockTime >= 0 && blockTime < blockCloud && blockCloud < headTime && headTime < headCloud);
  const observer = new SimulatedHuaweiDevice(cloud, 'observer');
  const heads = observer.readRemoteHeads();
  assert.equal(heads.length, 1);
  assert.equal(heads[0].snapshot.size, writer.localSnapshot.size);
  assert.equal(snapshotFingerprint(heads[0].snapshot), snapshotFingerprint(writer.localSnapshot));
  return { cloud, writer, initialBlockCount: cloud.blocks.size };
}

function scenarioNoOpStability() {
  const { cloud } = scenarioInitialPublication();
  const reader = new SimulatedHuaweiDevice(cloud, 'reader');
  const warmup = reader.sync(2 * 24 * 60 * 60 * 1000);
  assert.equal(warmup.committed, false);
  const rowsBefore = cloud.rowCount();
  const metricsBefore = cloud.snapshotMetrics();
  for (let index = 0; index < 500; index += 1) {
    const result = reader.sync((3 * 24 * 60 * 60 * 1000) + index);
    assert.equal(result.committed, false);
  }
  const metricsAfter = cloud.snapshotMetrics();
  const metrics = {
    rowDelta: cloud.rowCount() - rowsBefore,
    headCloudFirst: metricDelta(metricsAfter, metricsBefore, `sync:CLOUD_FIRST:${HEAD_TABLE}`),
    blockCloudFirst: metricDelta(metricsAfter, metricsBefore, `sync:CLOUD_FIRST:${BLOCK_TABLE}`),
    uploads: metricDelta(metricsAfter, metricsBefore, 'uploadedRows'),
    downloads: metricDelta(metricsAfter, metricsBefore, 'downloadedRows'),
    cloudHeads: cloud.heads.size,
    cloudBlocks: cloud.blocks.size
  };
  assert.deepEqual(metrics, {
    rowDelta: 0,
    headCloudFirst: 500,
    blockCloudFirst: 0,
    uploads: 0,
    downloads: 0,
    cloudHeads: 1,
    cloudBlocks: cloud.blocks.size
  });
  return metrics;
}

function scenarioLocalizedEdit() {
  const { cloud, writer } = scenarioInitialPublication();
  const headCountBefore = cloud.heads.size;
  const blockRowsBefore = new Map(cloud.blocks);
  writer.localSnapshot = editItem(writer.localSnapshot, 'item-0100', 'Changed! 0100', writer.deviceId);
  const result = writer.sync(4 * 24 * 60 * 60 * 1000);
  assert.equal(result.committed, true);
  const newRows = Array.from(cloud.blocks.values()).filter((row) => !blockRowsBefore.has(row.rowId));
  assert.equal(cloud.heads.size, headCountBefore);
  assert.equal(newRows.length, 2);
  assert.deepEqual(newRows.map((row) => row.recordKind).sort(), ['chunk', 'index']);
}

function readSingleRemoteSnapshot(cloud, observerId) {
  const observer = new SimulatedHuaweiDevice(cloud, observerId);
  const heads = observer.readRemoteHeads();
  assert.equal(heads.length, 1);
  return heads[0].snapshot;
}

function scenarioCanonicalMutationRoundTrips() {
  const cloud = new InMemoryHuaweiCloud();
  const writer = new SimulatedHuaweiDevice(cloud, 'mutation-writer', createBookmarkSnapshot(12));
  let publication = writer.sync(24 * 60 * 60 * 1000);
  assert.equal(publication.committed, true);
  let parentCommitId = publication.commitId;

  writer.localSnapshot = addItem(writer.localSnapshot, 'matrix-added', writer.deviceId);
  assertCanonicalMutationSnapshot(writer.localSnapshot);
  publication = writer.publishCurrent([parentCommitId], 2 * 24 * 60 * 60 * 1000);
  parentCommitId = publication.commitId;
  let observed = readSingleRemoteSnapshot(cloud, 'mutation-add-observer');
  assert.equal(snapshotHasItem(observed, 'matrix-added'), true);
  assert.equal(readOrderIds(observed, 'folder-main').includes('matrix-added'), true);

  writer.localSnapshot = editItem(writer.localSnapshot, 'item-0001', 'Matrix edited', writer.deviceId);
  assertCanonicalMutationSnapshot(writer.localSnapshot);
  publication = writer.publishCurrent([parentCommitId], 3 * 24 * 60 * 60 * 1000);
  parentCommitId = publication.commitId;
  observed = readSingleRemoteSnapshot(cloud, 'mutation-edit-observer');
  assert.equal(JSON.parse(observed.get('shared|item|item-0001|0').d).title, 'Matrix edited');

  writer.localSnapshot = addFolder(writer.localSnapshot, 'folder-moved-to', writer.deviceId);
  writer.localSnapshot = moveItem(writer.localSnapshot, 'item-0002', 'folder-moved-to', writer.deviceId);
  assertCanonicalMutationSnapshot(writer.localSnapshot);
  publication = writer.publishCurrent([parentCommitId], 4 * 24 * 60 * 60 * 1000);
  parentCommitId = publication.commitId;
  observed = readSingleRemoteSnapshot(cloud, 'mutation-move-observer');
  assert.equal(JSON.parse(observed.get('shared|item|item-0002|0').d).parentId, 'folder-moved-to');
  assert.equal(readOrderIds(observed, 'folder-main').includes('item-0002'), false);
  assert.equal(readOrderIds(observed, 'folder-moved-to').includes('item-0002'), true);

  writer.localSnapshot = deleteItem(writer.localSnapshot, 'matrix-added', writer.deviceId);
  assertCanonicalMutationSnapshot(writer.localSnapshot);
  writer.publishCurrent([parentCommitId], 5 * 24 * 60 * 60 * 1000);
  observed = readSingleRemoteSnapshot(cloud, 'mutation-delete-observer');
  assert.equal(snapshotHasItem(observed, 'matrix-added'), false);
  assert.equal(snapshotHasTombstone(observed, 'matrix-added'), true);
  assert.equal(readOrderIds(observed, 'folder-main').includes('matrix-added'), false);
}

function scenarioRetryableTransportFailureRecovery() {
  const { cloud, writer } = scenarioInitialPublication();
  const oldHead = { ...Array.from(cloud.heads.values())[0] };
  writer.localSnapshot = editItem(writer.localSnapshot, 'item-0003', 'Retry recovered', writer.deviceId);
  cloud.failNext(BLOCK_TABLE, 'TIME_FIRST', 'injected retryable network failure');
  assert.throws(
    () => writer.sync(4 * 24 * 60 * 60 * 1000),
    /injected retryable network failure/
  );
  assert.ok(sameRow(Array.from(cloud.heads.values())[0], oldHead));
  const retry = writer.sync(4 * 24 * 60 * 60 * 1000 + 1);
  assert.equal(retry.committed, true);
  const observed = readSingleRemoteSnapshot(cloud, 'retry-observer');
  assert.equal(JSON.parse(observed.get('shared|item|item-0003|0').d).title, 'Retry recovered');
}

function scenarioInterruptedPublication() {
  const { cloud, writer } = scenarioInitialPublication();
  const oldHead = { ...Array.from(cloud.heads.values())[0] };
  writer.localSnapshot = editItem(writer.localSnapshot, 'item-0200', 'Interrupted 0200', writer.deviceId);
  assert.throws(
    () => writer.sync(5 * 24 * 60 * 60 * 1000, { failAfterBlockConfirmation: true }),
    /injected interruption/
  );
  assert.equal(cloud.heads.size, 1);
  assert.ok(sameRow(Array.from(cloud.heads.values())[0], oldHead));
  const observer = new SimulatedHuaweiDevice(cloud, 'observer-after-interruption');
  const heads = observer.readRemoteHeads();
  assert.equal(heads.length, 1);
  assert.equal(heads[0].manifest.commitId, oldHead.logicalId);
  assert.equal(JSON.parse(heads[0].snapshot.get('shared|item|item-0200|0').d).title, 'Bookmark 0200');
}

function scenarioIncompleteHeadFallback() {
  const { cloud, writer } = scenarioInitialPublication();
  const originalHead = Array.from(cloud.heads.values())[0];
  const deviceB = new SimulatedHuaweiDevice(cloud, 'device-b');
  deviceB.sync(6 * 24 * 60 * 60 * 1000);
  deviceB.localSnapshot = addItem(deviceB.localSnapshot, 'device-b-only', deviceB.deviceId);
  const publication = deviceB.sync(7 * 24 * 60 * 60 * 1000);
  assert.equal(publication.committed, true);
  const childManifest = publication.projection.manifest;
  const parentManifest = JSON.parse(originalHead.data);
  const parentIndexes = new Set(parentManifest.indexes.map((reference) => reference.h));
  const uniqueIndex = childManifest.indexes.find((reference) => !parentIndexes.has(reference.h));
  assert.ok(uniqueIndex, 'child Head should reference an edited index');
  cloud.blocks.delete(blockRowId(childManifest.storageEpoch, 'index', uniqueIndex.h));

  const observer = new SimulatedHuaweiDevice(cloud, 'observer-incomplete');
  const heads = observer.readRemoteHeads();
  assert.equal(heads.length, 1);
  assert.equal(heads[0].manifest.commitId, originalHead.logicalId);
  assert.equal(snapshotHasItem(heads[0].snapshot, 'device-b-only'), false);
  assert.ok(heads[0].snapshot.size > 600, 'fallback must not become an empty remote');
}

function createConcurrentWorld() {
  const cloud = new InMemoryHuaweiCloud();
  const deviceA = new SimulatedHuaweiDevice(cloud, 'device-a', createBookmarkSnapshot(300));
  const initial = deviceA.sync(24 * 60 * 60 * 1000);
  const initialCommitId = initial.commitId;
  const deviceB = new SimulatedHuaweiDevice(cloud, 'device-b');
  deviceB.sync(2 * 24 * 60 * 60 * 1000);
  deviceA.localSnapshot = addItem(deviceA.localSnapshot, 'device-a-only', deviceA.deviceId);
  deviceB.localSnapshot = addItem(deviceB.localSnapshot, 'device-b-only', deviceB.deviceId);
  const headA = deviceA.publishCurrent([initialCommitId], 3 * 24 * 60 * 60 * 1000);
  const headB = deviceB.publishCurrent([initialCommitId], 3 * 24 * 60 * 60 * 1000 + 1);
  return { cloud, deviceA, deviceB, headA, headB };
}

function scenarioConcurrentConvergence() {
  const world = createConcurrentWorld();
  const observer = new SimulatedHuaweiDevice(world.cloud, 'concurrent-observer');
  const concurrentHeads = observer.readRemoteHeads();
  assert.equal(concurrentHeads.length, 2);
  const merged = mergeSnapshots(...concurrentHeads.map((head) => head.snapshot));
  assert.equal(snapshotHasItem(merged, 'device-a-only'), true);
  assert.equal(snapshotHasItem(merged, 'device-b-only'), true);

  world.deviceA.localSnapshot = merged;
  const converged = world.deviceA.publishCurrent(
    concurrentHeads.map((head) => head.manifest.commitId),
    4 * 24 * 60 * 60 * 1000
  );
  const finalObserver = new SimulatedHuaweiDevice(world.cloud, 'converged-observer');
  const finalHeads = finalObserver.readRemoteHeads();
  assert.equal(finalHeads.length, 1);
  assert.equal(finalHeads[0].manifest.commitId, converged.commitId);
  assert.equal(snapshotHasItem(finalHeads[0].snapshot, 'device-a-only'), true);
  assert.equal(snapshotHasItem(finalHeads[0].snapshot, 'device-b-only'), true);
}

function createGcWorld() {
  const concurrent = createConcurrentWorld();
  const observer = new SimulatedHuaweiDevice(concurrent.cloud, 'gc-observer');
  const oldHeads = observer.readRemoteHeads();
  const checkpointSnapshot = mergeSnapshots(...oldHeads.map((head) => head.snapshot));
  const checkpoint = new SimulatedHuaweiDevice(concurrent.cloud, 'checkpoint-device', checkpointSnapshot);
  const checkpointTime = STORAGE_EPOCH_MS + (24 * 60 * 60 * 1000);
  const publication = checkpoint.publishCurrent(
    oldHeads.map((head) => head.manifest.commitId),
    checkpointTime
  );
  return {
    ...concurrent,
    checkpoint,
    checkpointTime,
    publication,
    oldHeadRowIds: oldHeads.map((head) => head.rowId),
    oldBlockRowIds: Array.from(concurrent.cloud.blocks.values())
      .filter((row) => row.storageEpoch === 1)
      .map((row) => row.rowId)
  };
}

function scenarioGcOrdering() {
  const world = createGcWorld();
  const beforeQuarantineHeads = world.cloud.heads.size;
  const beforeQuarantineBlocks = world.cloud.blocks.size;
  const early = world.checkpoint.runPhysicalGc(STORAGE_EPOCH_MS + (6 * 24 * 60 * 60 * 1000));
  assert.equal(early.status, 'skipped');
  assert.equal(world.cloud.heads.size, beforeQuarantineHeads);
  assert.equal(world.cloud.blocks.size, beforeQuarantineBlocks);

  const eventOffset = world.cloud.events.length;
  const result = world.checkpoint.runPhysicalGc(STORAGE_EPOCH_MS + (8 * 24 * 60 * 60 * 1000));
  assert.equal(result.status, 'completed');
  assert.ok(result.deletedHeads > 0);
  assert.ok(result.deletedBlocks > 0);
  assert.ok(world.oldHeadRowIds.every((rowId) => !world.cloud.heads.has(rowId)));
  assert.ok(world.oldBlockRowIds.every((rowId) => !world.cloud.blocks.has(rowId)));
  const events = world.cloud.events.slice(eventOffset);
  const headDelete = events.findIndex((event) => event.startsWith(`TIME_FIRST:${HEAD_TABLE}:`));
  const blockDelete = events.findIndex((event) => event.startsWith(`TIME_FIRST:${BLOCK_TABLE}:`));
  assert.ok(headDelete >= 0 && blockDelete > headDelete, 'Blocks must be deleted only after Head deletion confirmation');
  return world;
}

function scenarioGcFailureIsNonFatal() {
  const world = createGcWorld();
  const blocksBefore = new Map(world.cloud.blocks);
  const confirmedCommitId = world.publication.commitId;
  world.cloud.failNext(HEAD_TABLE, 'TIME_FIRST', 'injected Head GC failure');
  const result = world.checkpoint.runPhysicalGcSafely(
    STORAGE_EPOCH_MS + (8 * 24 * 60 * 60 * 1000)
  );
  assert.equal(result.status, 'deferred');
  assert.match(result.error, /injected Head GC failure/);
  assert.equal(world.cloud.heads.get(headRowId(world.checkpoint.accountUid, world.checkpoint.deviceId)).logicalId,
    confirmedCommitId);
  assert.deepEqual(world.cloud.blocks, blocksBefore);
}

function scenarioStaleDeviceReturn() {
  const world = createGcWorld();
  world.deviceB.localSnapshot = addItem(world.deviceB.localSnapshot, 'stale-device-only', world.deviceB.deviceId);
  const gc = world.checkpoint.runPhysicalGc(STORAGE_EPOCH_MS + (8 * 24 * 60 * 60 * 1000));
  assert.equal(gc.status, 'completed');
  const result = world.deviceB.sync(STORAGE_EPOCH_MS + (9 * 24 * 60 * 60 * 1000));
  assert.equal(result.committed, true);
  assert.equal(result.projection.manifest.storageEpoch, 2);
  const observer = new SimulatedHuaweiDevice(world.cloud, 'stale-return-observer');
  const heads = observer.readRemoteHeads();
  assert.equal(heads.length, 1);
  assert.equal(snapshotHasItem(heads[0].snapshot, 'stale-device-only'), true);
  assert.equal(snapshotHasItem(heads[0].snapshot, 'device-a-only'), true);
  assert.equal(snapshotHasItem(heads[0].snapshot, 'device-b-only'), true);
}

function main() {
  runScenario('production G8 constants and ordering match the simulation', assertProductionSourceContract);
  runScenario('G7 selections require the version-8 re-enable gate until real success', assertG7UpgradeSourceContract);
  runScenario('retryable and blocked Huawei progress codes keep distinct runtime policy',
    assertFailurePolicySourceContract);
  const initial = runScenario('initial Blocks are confirmed before one replaceable Head', scenarioInitialPublication);
  const noOp = runScenario('500 no-op syncs stay Head-only with zero row growth', scenarioNoOpStability);
  runScenario('one equal-size edit adds only one chunk and one index', scenarioLocalizedEdit);
  runScenario('canonical add, edit, move, and delete snapshots round-trip through G8',
    scenarioCanonicalMutationRoundTrips);
  runScenario('a retryable transport failure keeps the old Head and succeeds on retry',
    scenarioRetryableTransportFailureRecovery);
  runScenario('interruption before Head publication keeps the old remote truth', scenarioInterruptedPublication);
  runScenario('an incomplete child Head falls back to its complete parent', scenarioIncompleteHeadFallback);
  runScenario('concurrent device Heads converge without losing either unique bookmark', scenarioConcurrentConvergence);
  runScenario('GC waits for quarantine and confirms Head deletion before Blocks', scenarioGcOrdering);
  runScenario('Head GC failure does not fail the confirmed commit or delete Blocks', scenarioGcFailureIsNonFatal);
  runScenario('a stale device returns after GC and republishes preserved local data', scenarioStaleDeviceReturn);

  process.stdout.write('\nHuawei G8 in-memory simulation metrics\n');
  process.stdout.write(`  initial snapshot: 620 bookmarks -> ${initial.initialBlockCount} Block rows + 1 Head row\n`);
  process.stdout.write(`  500 unchanged syncs: ${noOp.headCloudFirst} Head fetches, ` +
    `${noOp.blockCloudFirst} Block fetches, ${noOp.uploads} uploads, row delta ${noOp.rowDelta}\n`);
  process.stdout.write(`  final no-op cloud size: ${noOp.cloudHeads} Head row + ${noOp.cloudBlocks} Block rows\n`);
  process.stdout.write('\nProtocol-model simulation passed. Real Huawei Cloud behavior still requires deployed Record Types and device testing.\n');
}

main();
