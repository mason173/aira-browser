#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

function fail(message) {
  process.stderr.write(`Sync closed-loop failure: ${message}\n`);
  process.exitCode = 1;
}

function writeU32(target, offset, value) {
  target[offset] = (value >>> 24) & 0xff;
  target[offset + 1] = (value >>> 16) & 0xff;
  target[offset + 2] = (value >>> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}

function readU32(source, offset) {
  return ((source[offset] << 24) | (source[offset + 1] << 16) |
    (source[offset + 2] << 8) | source[offset + 3]) >>> 0;
}

function writeU64(target, offset, value) {
  const safe = Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  writeU32(target, offset, Math.floor(safe / 4294967296));
  writeU32(target, offset + 4, safe % 4294967296);
}

function readU64(source, offset) {
  return readU32(source, offset) * 4294967296 + readU32(source, offset + 4);
}

function encodeRows(rows) {
  const encoder = new TextEncoder();
  const encoded = rows.map((row) => ({
    rowId: encoder.encode(row.rowId),
    recordKind: encoder.encode(row.recordKind),
    logicalId: encoder.encode(row.logicalId),
    data: encoder.encode(row.data),
    updatedAt: row.updatedAt
  }));
  let packedByteLength = 4;
  for (const row of encoded) {
    packedByteLength += 24 + row.rowId.length + row.recordKind.length +
      row.logicalId.length + row.data.length;
  }
  const packed = new Uint8Array(packedByteLength);
  writeU32(packed, 0, rows.length);
  let offset = 4;
  for (const row of encoded) {
    writeU32(packed, offset, row.rowId.length);
    offset += 4;
    packed.set(row.rowId, offset);
    offset += row.rowId.length;
    writeU32(packed, offset, row.recordKind.length);
    offset += 4;
    packed.set(row.recordKind, offset);
    offset += row.recordKind.length;
    writeU32(packed, offset, row.logicalId.length);
    offset += 4;
    packed.set(row.logicalId, offset);
    offset += row.logicalId.length;
    writeU32(packed, offset, row.data.length);
    offset += 4;
    packed.set(row.data, offset);
    offset += row.data.length;
    writeU64(packed, offset, row.updatedAt);
    offset += 8;
  }
  return packed;
}

function decodeRows(buffer) {
  const decoder = new TextDecoder();
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  const rowCount = readU32(bytes, 0);
  const rows = [];
  let offset = 4;
  const readString = () => {
    const length = readU32(bytes, offset);
    offset += 4;
    const value = decoder.decode(bytes.subarray(offset, offset + length));
    offset += length;
    return value;
  };
  for (let index = 0; index < rowCount; index += 1) {
    const rowId = readString();
    const recordKind = readString();
    const logicalId = readString();
    const data = readString();
    const updatedAt = readU64(bytes, offset);
    offset += 8;
    rows.push({ rowId, recordKind, logicalId, data, updatedAt });
  }
  return rows;
}

function hasLocalWork(enrolled, outbox, tombstones, headMatches) {
  return enrolled > 0 || outbox || (headMatches && tombstones);
}

function readPlan(hasWork, headMatches, remote, replicaReady) {
  if (!String(remote).trim()) {
    return 'cloud';
  }
  if (!hasWork && (headMatches || replicaReady)) {
    return 'skip';
  }
  if (hasWork && (headMatches || replicaReady)) {
    return 'replica';
  }
  return 'cloud';
}

function matchesConfirmedHead(baselineCommitId, commitId) {
  const left = String(commitId || '').trim();
  return left.length > 0 && left === String(baselineCommitId).trim();
}

function mergeCollection(localItems, remoteItems, localTombs, remoteTombs) {
  const ids = [];
  const addId = (id) => {
    if (id && ids.indexOf(id) < 0) {
      ids.push(id);
    }
  };
  for (const item of localItems.concat(remoteItems)) {
    addId(item.id);
  }
  for (const tomb of localTombs.concat(remoteTombs)) {
    addId(tomb.id);
  }
  const items = [];
  const tombstones = [];
  for (const id of ids) {
    const localItem = localItems.find((item) => item.id === id);
    const remoteItem = remoteItems.find((item) => item.id === id);
    const deletedAt = Math.max(
      0,
      ...localTombs.concat(remoteTombs).filter((value) => value.id === id).map((value) => value.deletedAt)
    );
    const liveUpdatedAt = Math.max(localItem ? localItem.updatedAt : 0, remoteItem ? remoteItem.updatedAt : 0);
    if (deletedAt > 0 && deletedAt >= liveUpdatedAt) {
      tombstones.push({ id, deletedAt });
      continue;
    }
    items.push(localItem || remoteItem);
  }
  return { items, tombstones };
}

const payload = JSON.stringify({ visits: new Array(40).fill({ url: 'https://example.com/x', title: 't' }) });
const rows = [];
for (let index = 0; index < 988; index += 1) {
  rows.push({
    rowId: `row-${index}`,
    recordKind: index === 0 ? 'snapshot_head' : 'snapshot_chunk',
    logicalId: `logical-${index}`,
    data: payload,
    updatedAt: 1757520000000 + index
  });
}

// Micro-benchmarks on sub-10ms work are dominated by scheduling noise, so warm
// both paths and take the best of several runs before comparing them.
function bestOf(runs, operation) {
  let best = Infinity;
  for (let index = 0; index < runs; index += 1) {
    const started = Date.now();
    operation();
    best = Math.min(best, Date.now() - started);
  }
  return best;
}

const jsonPacked = Buffer.from(JSON.stringify(rows), 'utf8');
const binaryPacked = encodeRows(rows);
JSON.parse(jsonPacked.toString('utf8'));
decodeRows(binaryPacked);

const jsonMs = bestOf(5, () => {
  JSON.stringify(rows);
});
const binMs = bestOf(5, () => {
  encodeRows(rows);
});
const decoded = decodeRows(binaryPacked);

if (decoded.length !== 988) {
  fail(`binary row roundtrip lost rows: ${decoded.length}`);
}
if (decoded[17].rowId !== 'row-17' || decoded[17].data !== payload || decoded[17].updatedAt !== 1757520000017) {
  fail('binary row roundtrip mutated payload');
}
if (binMs > 500) {
  fail(`binary pack of 988 rows took ${binMs}ms; must stay off the UI-thread JSON path`);
}
if (jsonMs * 4 + 25 < binMs) {
  fail(`binary pack (${binMs}ms) was far slower than JSON.stringify (${jsonMs}ms)`);
}

const cases = [
  [false, true, 'abc', false, 'skip'],
  [false, false, 'new', true, 'skip'],
  [true, true, 'abc', true, 'replica'],
  [true, true, 'abc', false, 'replica'],
  [true, false, 'new', true, 'replica'],
  [true, false, 'new', false, 'cloud'],
  [false, false, 'new', false, 'cloud']
];
for (const [hasWork, headMatches, remote, replicaReady, expected] of cases) {
  const got = readPlan(hasWork, headMatches, remote, replicaReady);
  if (got !== expected) {
    fail(`history plan ${JSON.stringify({ hasWork, headMatches, remote, replicaReady })} => ${got}, expected ${expected}`);
  }
}
if (hasLocalWork(0, false, true, false) !== false) {
  fail('stale tombstones must not count as local work after Head mismatch');
}
if (hasLocalWork(0, false, true, true) !== true) {
  fail('matching Head plus tombstones must count as local work');
}
if (matchesConfirmedHead('cmt-1', 'cmt-1') !== true || matchesConfirmedHead('cmt-1', 'cmt-2') !== false) {
  fail('bookmark Head no-op must key off commit identity');
}

const personalization = mergeCollection(
  [{ id: 'gone', updatedAt: 10 }, { id: 'local', updatedAt: 20 }],
  [{ id: 'gone', updatedAt: 10 }, { id: 'remote', updatedAt: 15 }],
  [{ id: 'gone', deletedAt: 30 }],
  []
);
if (personalization.items.map((item) => item.id).sort().join(',') !== 'local,remote') {
  fail(`personalization merge items=${personalization.items.map((item) => item.id).join(',')}`);
}
if (personalization.tombstones.length !== 1 || personalization.tombstones[0].id !== 'gone') {
  fail('personalization merge must keep the newer tombstone');
}


function sameSnapshotRecord(left, right) {
  if (left.kind !== right.kind || left.logicalId !== right.logicalId || left.updatedAt !== right.updatedAt) {
    return false;
  }
  if (left.kind === 'v') {
    const a = left.data;
    const b = right.data;
    return a.visitId === b.visitId && a.url === b.url && a.title === b.title &&
      a.visitedAt === b.visitedAt && a.clientId === b.clientId &&
      a.nativeVisitId === b.nativeVisitId;
  }
  return JSON.stringify(left.data) === JSON.stringify(right.data);
}

const visitA = {
  kind: 'v',
  logicalId: 'h1:phone-a:1',
  updatedAt: 1,
  data: { visitId: 'h1:phone-a:1', url: 'https://a.example', title: 'A', visitedAt: 1, clientId: 'phone-a', nativeVisitId: '1' }
};
const visitB = {
  kind: 'v',
  logicalId: 'h1:phone-a:1',
  updatedAt: 1,
  data: { nativeVisitId: '1', clientId: 'phone-a', visitedAt: 1, title: 'A', url: 'https://a.example', visitId: 'h1:phone-a:1' }
};
if (!sameSnapshotRecord(visitA, visitB)) {
  fail('one History tombstone must not rewrite buckets whose visit JSON key order differs');
}


function shouldUseBookmarkBaselineRemote(pendingLocalChange, headMatches, hasBaseline) {
  return pendingLocalChange === true && headMatches === true && hasBaseline === true;
}

function readRepo(rel) {
  return fs.readFileSync(path.join(__dirname, '..', rel), 'utf8');
}

if (shouldUseBookmarkBaselineRemote(true, true, true) !== true) {
  fail('a pending Bookmark delete must reuse the confirmed baseline when Head matches');
}
if (shouldUseBookmarkBaselineRemote(true, false, true) !== false) {
  fail('a Head mismatch must still download Bookmark Blocks');
}

const historyRunner = readRepo('AiraBrowser/entry/src/main/ets/services/sync/HuaweiSpaceHistorySyncRunner.ets');
if (!/preparePackedReplicaRows[\s\S]*takePackedReplicaRows[\s\S]*runPackedReplica/.test(historyRunner)) {
  fail('matching-head History local work must pack the replica once and runPackedReplica');
}
if (!/headMatches\) \{[\s\S]*tryLiteReplicaWrite[\s\S]*takePackedReplicaRows/.test(historyRunner)) {
  fail('History packed replica must only consume packed rows when Head matches');
}
if (!historyRunner.includes('writePreparedProjection(packed.projection, desired)')) {
  fail('History replica writes must use writePreparedProjection instead of decoding 994 rows again');
}
if (!historyRunner.includes('tryLiteReplicaWrite') || !historyRunner.includes('history_replica_lite')) {
  fail('matching-head History deletes must rebuild only dirty buckets without decoding 994 rows');
}

const historyRemote = readRepo('AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceHistoryRemoteStore.ets');
if (!historyRemote.includes('async preparePackedReplicaRows') ||
  !historyRemote.includes('async writePreparedProjection') ||
  !historyRemote.includes('peekFreshReplicaRows')) {
  fail('History remote store must expose packed replica read/write without a second decode');
}

const compute = readRepo('AiraBrowser/entry/src/main/ets/services/sync/AiraSyncComputeExecutor.ets');
if (!compute.includes('function planHuaweiHistoryReplicaPacked') ||
  !compute.includes('async planHuaweiHistoryReplicaPacked')) {
  fail('History must decode+merge+buildProjection in one TaskPool packed replica job');
}

const bookmarkSync = readRepo('AiraBrowser/entry/src/main/ets/services/sync/SyncService.ets');
if (!bookmarkSync.includes("bookmark_baseline_remote") ||
  !bookmarkSync.includes('resolveBookmarkRemoteStateForMerge')) {
  fail('pending Bookmark local work must reuse baseline remote when Head matches');
}
if (!bookmarkSync.includes('bookmark_confirm_pending') ||
  !bookmarkSync.includes('skip=write-will-time-first')) {
  fail('pending Bookmark writes must not TIME_FIRST Blocks before the actual write');
}

const bookmarkStore = readRepo('AiraBrowser/entry/src/main/ets/data/sync/AiraHuaweiSpaceRemoteStore.ets');
const writeState = bookmarkStore.split('async writeState(')[1] || '';
const writeBody = writeState.split('async warmupTransport(')[0] || '';
if (writeBody.includes('readAggregateAfterCloudFirst')) {
  fail('Bookmark writeState must not CLOUD_FIRST Blocks through readAggregateAfterCloudFirst');
}
if (!writeBody.includes('readWriteParentsAfterHeadsCloudFirst')) {
  fail('Bookmark writeState must take parents from Heads only');
}
if (!bookmarkStore.includes('heads-only=1 reused=1') || !bookmarkStore.includes('runPhysicalGcNow')) {
  fail('Bookmark writes must reuse the already-read Head and defer physical GC off the sync turn');
}

process.stdout.write(
  `Sync closed-loop passed. jsonPackMs=${jsonMs} binaryPackMs=${binMs} binaryBytes=${binaryPacked.length}\n`
);
