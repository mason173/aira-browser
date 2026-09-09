import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import {
  HistorySyncDeleteRange,
  HistorySyncExactTombstone,
  HistorySyncRetentionFrontier,
  HistorySyncVisit,
  HuaweiSpaceHistorySyncState
} from '../../common/models/HistorySyncModels';
import { AiraSyncCooperativeThrottle } from '../../services/sync/AiraSyncWorkThrottleService';
import { HistorySyncMergeService } from '../../services/sync/HistorySyncMergeService';

const HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION: number = 2;
const HUAWEI_SPACE_HISTORY_BUCKET_COUNT: number = 64;
const HUAWEI_SPACE_HISTORY_ROW_MAX_BYTES: number = 12 * 1024;
const HUAWEI_SPACE_HISTORY_CHUNK_TARGET_BYTES: number = 11 * 1024;
const HUAWEI_SPACE_HISTORY_SLOT_COUNT: number = 2;
const HUAWEI_SPACE_HISTORY_MAX_CHUNKS_PER_BUCKET: number = 128;

export type HuaweiSpaceHistoryRecordKind =
  'visit' |
  'tombstone' |
  'delete_range' |
  'clear_before' |
  'retention_frontier' |
  'snapshot_head' |
  'snapshot_bucket' |
  'snapshot_chunk';

export type HuaweiSpaceHistoryPhysicalTable = 'head' | 'block' | 'legacy';

export function huaweiHistoryPhysicalTable(
  recordKind: HuaweiSpaceHistoryRecordKind
): HuaweiSpaceHistoryPhysicalTable {
  if (recordKind === 'snapshot_head') {
    return 'head';
  }
  if (recordKind === 'snapshot_bucket' || recordKind === 'snapshot_chunk') {
    return 'block';
  }
  return 'legacy';
}

type HuaweiSpaceHistoryLegacyRecordKind =
  'visit' |
  'tombstone' |
  'delete_range' |
  'clear_before' |
  'retention_frontier';

type HuaweiSpaceHistorySnapshotRecordKind = 'v' | 't' | 'd' | 'c' | 'r';

export interface HuaweiSpaceHistoryRow {
  rowId: string;
  recordKind: HuaweiSpaceHistoryRecordKind;
  logicalId: string;
  data: string;
  updatedAt: number;
}

interface HuaweiSpaceHistoryClearBeforePayload {
  clearBefore: number;
}

interface HuaweiSpaceHistorySnapshotRecord {
  kind: HuaweiSpaceHistorySnapshotRecordKind;
  logicalId: string;
  updatedAt: number;
  data: Object;
}

interface HuaweiSpaceHistoryChunkData {
  formatVersion: number;
  deviceId: string;
  bucketIndex: number;
  bucketSlot: number;
  segmentIndex: number;
  generatedAt: number;
  records: HuaweiSpaceHistorySnapshotRecord[];
}

interface HuaweiSpaceHistoryChunkReference {
  segmentIndex: number;
  hash: string;
  recordCount: number;
}

interface HuaweiSpaceHistoryBucketData {
  formatVersion: number;
  deviceId: string;
  bucketIndex: number;
  bucketSlot: number;
  generatedAt: number;
  chunks: HuaweiSpaceHistoryChunkReference[];
}

interface HuaweiSpaceHistoryBucketReference {
  bucketIndex: number;
  bucketSlot: number;
  hash: string;
  recordCount: number;
}

interface HuaweiSpaceHistorySnapshotCounts {
  visits: number;
  tombstones: number;
  deleteRanges: number;
  clearBefore: number;
  retentionFrontier: number;
}

interface HuaweiSpaceHistoryHeadData {
  formatVersion: number;
  deviceId: string;
  headSlot: number;
  generation: number;
  generatedAt: number;
  buckets: HuaweiSpaceHistoryBucketReference[];
  counts: HuaweiSpaceHistorySnapshotCounts;
  stateChecksum: string;
}

interface HuaweiSpaceHistoryChunk {
  row: HuaweiSpaceHistoryRow;
  value: HuaweiSpaceHistoryChunkData;
  hash: string;
}

interface HuaweiSpaceHistoryBucket {
  row: HuaweiSpaceHistoryRow;
  value: HuaweiSpaceHistoryBucketData;
  hash: string;
}

interface HuaweiSpaceHistoryHead {
  row: HuaweiSpaceHistoryRow;
  value: HuaweiSpaceHistoryHeadData;
  bucketRecords: Map<number, HuaweiSpaceHistorySnapshotRecord[]>;
  state: HuaweiSpaceHistorySyncState;
}

interface HuaweiSpaceHistoryBuiltBucket {
  rows: HuaweiSpaceHistoryRow[];
  reference: HuaweiSpaceHistoryBucketReference;
}

interface HuaweiSpaceHistoryBuiltChunk {
  row: HuaweiSpaceHistoryRow;
  reference: HuaweiSpaceHistoryChunkReference;
}

export interface HuaweiSpaceHistoryPhysicalMirror {
  state: HuaweiSpaceHistorySyncState;
  rows: HuaweiSpaceHistoryRow[];
  legacyRowIds: string[];
  selectedHeads: HuaweiSpaceHistoryHead[];
}

export interface HuaweiSpaceHistoryProjection {
  state: HuaweiSpaceHistorySyncState;
  rowsToUpsert: HuaweiSpaceHistoryRow[];
  rowIdsToDeleteBeforePublish: string[];
  legacyRowIdsToDeleteAfterConfirmation: string[];
  targetHeadRowId: string;
  targetDeviceId: string;
  targetGeneration: number;
  targetStateChecksum: string;
}

export class HuaweiSpaceHistorySnapshotCodec {
  private readonly uid: string;
  private readonly deviceId: string;
  private readonly mergeService: HistorySyncMergeService = new HistorySyncMergeService();
  private readonly encoder: util.TextEncoder = new util.TextEncoder();

  constructor(uid: string, deviceId: string) {
    this.uid = uid.trim();
    this.deviceId = deviceId.trim();
    if (this.uid.length <= 0 || this.deviceId.length <= 0) {
      throw new Error('Huawei History snapshot identity is incomplete.');
    }
  }

  decodeRows(
    rows: HuaweiSpaceHistoryRow[],
    now: number = Date.now()
  ): HuaweiSpaceHistoryPhysicalMirror {
    const legacyState = this.mergeService.emptyState();
    const legacyRowIds: string[] = [];
    const chunksByRowId = new Map<string, HuaweiSpaceHistoryChunk>();
    const bucketsByRowId = new Map<string, HuaweiSpaceHistoryBucket>();
    const heads: HuaweiSpaceHistoryHeadData[] = [];
    let compactRowCount = 0;

    rows.forEach((row: HuaweiSpaceHistoryRow): void => {
      this.validateOuterRow(row);
      this.assertRowSize(row.data);
      this.requireTimestamp(row.updatedAt, 'updatedAt', true);
      if (this.isLegacyRecordKind(row.recordKind)) {
        this.appendLegacyRow(legacyState, row);
        legacyRowIds.push(row.rowId);
        return;
      }
      compactRowCount += 1;
      if (row.recordKind === 'snapshot_chunk') {
        const chunk = this.parseChunk(row);
        chunksByRowId.set(row.rowId, chunk);
        return;
      }
      if (row.recordKind === 'snapshot_bucket') {
        const bucket = this.parseBucket(row);
        bucketsByRowId.set(row.rowId, bucket);
        return;
      }
      if (row.recordKind === 'snapshot_head') {
        heads.push(this.parseHead(row));
        return;
      }
      throw new Error('Huawei History contains an unsupported physical record kind.');
    });

    const completeHeads = this.materializeHeads(heads, bucketsByRowId, chunksByRowId);
    const selectedHeads = this.selectNewestHeadPerDevice(completeHeads);
    if (compactRowCount > 0 && selectedHeads.length <= 0 && legacyRowIds.length <= 0) {
      throw new Error('Huawei History compact snapshot is incomplete.');
    }
    let compactState = this.mergeService.emptyState();
    selectedHeads.forEach((head: HuaweiSpaceHistoryHead): void => {
      compactState = this.mergeService.merge(compactState, head.state, now);
    });
    const state = this.mergeService.merge(compactState, legacyState, now);
    return {
      state,
      rows: rows.slice(),
      legacyRowIds: legacyRowIds.sort(),
      selectedHeads
    };
  }

  async decodeRowsCooperatively(
    rows: HuaweiSpaceHistoryRow[],
    throttle: AiraSyncCooperativeThrottle,
    now: number = Date.now()
  ): Promise<HuaweiSpaceHistoryPhysicalMirror> {
    const legacyState = this.mergeService.emptyState();
    const legacyRowIds: string[] = [];
    const chunksByRowId = new Map<string, HuaweiSpaceHistoryChunk>();
    const bucketsByRowId = new Map<string, HuaweiSpaceHistoryBucket>();
    const heads: HuaweiSpaceHistoryHeadData[] = [];
    let compactRowCount = 0;
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      this.validateOuterRow(row);
      this.assertRowSize(row.data);
      this.requireTimestamp(row.updatedAt, 'updatedAt', true);
      if (this.isLegacyRecordKind(row.recordKind)) {
        this.appendLegacyRow(legacyState, row);
        legacyRowIds.push(row.rowId);
      } else {
        compactRowCount += 1;
        if (row.recordKind === 'snapshot_chunk') {
          chunksByRowId.set(row.rowId, this.parseChunk(row));
        } else if (row.recordKind === 'snapshot_bucket') {
          bucketsByRowId.set(row.rowId, this.parseBucket(row));
        } else if (row.recordKind === 'snapshot_head') {
          heads.push(this.parseHead(row));
        } else {
          throw new Error('Huawei History contains an unsupported physical record kind.');
        }
      }
      await throttle.afterBatchItem(index + 1);
    }
    const completeHeads = await this.materializeHeadsCooperatively(
      heads,
      bucketsByRowId,
      chunksByRowId,
      throttle
    );
    const selectedHeads = await this.selectNewestHeadPerDeviceCooperatively(completeHeads, throttle);
    if (compactRowCount > 0 && selectedHeads.length <= 0 && legacyRowIds.length <= 0) {
      throw new Error('Huawei History compact snapshot is incomplete.');
    }
    let compactState = this.mergeService.emptyState();
    for (let index = 0; index < selectedHeads.length; index += 1) {
      compactState = await this.mergeService.mergeCooperatively(
        compactState,
        selectedHeads[index].state,
        throttle,
        now
      );
      await throttle.afterStage();
    }
    const state = await this.mergeService.mergeCooperatively(compactState, legacyState, throttle, now);
    const sortedLegacyRowIds = await this.sortStringsCooperatively(legacyRowIds, throttle);
    return {
      state,
      rows: rows.slice(),
      legacyRowIds: sortedLegacyRowIds,
      selectedHeads
    };
  }

  buildProjection(
    state: HuaweiSpaceHistorySyncState,
    mirror: HuaweiSpaceHistoryPhysicalMirror,
    generatedAt: number = Date.now()
  ): HuaweiSpaceHistoryProjection {
    const normalized = this.mergeService.normalize(state);
    const ownHead = mirror.selectedHeads.find((head: HuaweiSpaceHistoryHead): boolean => {
      return head.value.deviceId === this.deviceId;
    });
    if (ownHead !== undefined && this.mergeService.sameState(ownHead.state, normalized)) {
      return {
        state: normalized,
        rowsToUpsert: [],
        rowIdsToDeleteBeforePublish: [],
        legacyRowIdsToDeleteAfterConfirmation: mirror.legacyRowIds.slice(),
        targetHeadRowId: ownHead.row.rowId,
        targetDeviceId: this.deviceId,
        targetGeneration: ownHead.value.generation,
        targetStateChecksum: ownHead.value.stateChecksum
      };
    }

    const timestamp = this.requireTimestamp(generatedAt, 'generatedAt');
    const maxKnownGeneration = this.resolveMaxKnownGeneration(mirror.rows);
    const generation = maxKnownGeneration + 1;
    if (!Number.isSafeInteger(generation) || generation <= 0) {
      throw new Error('Huawei History snapshot generation is exhausted.');
    }
    const headSlot = ownHead === undefined ? 0 : 1 - ownHead.value.headSlot;
    const desiredBuckets = this.buildBucketRecords(normalized);
    const bucketReferences: HuaweiSpaceHistoryBucketReference[] = [];
    const rowsToUpsert: HuaweiSpaceHistoryRow[] = [];
    const rowIdsToDeleteBeforePublish: string[] = [];

    for (let bucketIndex = 0; bucketIndex < HUAWEI_SPACE_HISTORY_BUCKET_COUNT; bucketIndex += 1) {
      const desiredRecords = desiredBuckets.get(bucketIndex) ?? [];
      const currentReference = ownHead?.value.buckets[bucketIndex];
      const currentRecords = ownHead?.bucketRecords.get(bucketIndex) ?? [];
      if (currentReference !== undefined && this.sameRecords(currentRecords, desiredRecords)) {
        bucketReferences.push(currentReference);
        continue;
      }
      const bucketSlot = currentReference === undefined ? 0 : 1 - currentReference.bucketSlot;
      const built = this.buildBucket(
        bucketIndex,
        bucketSlot,
        generation,
        timestamp,
        desiredRecords
      );
      rowsToUpsert.push(...built.rows);
      bucketReferences.push(built.reference);
      mirror.rows.forEach((row: HuaweiSpaceHistoryRow): void => {
        if (row.recordKind !== 'snapshot_chunk') {
          return;
        }
        const expectedPrefix = this.buildChunkLogicalPrefix(this.deviceId, bucketIndex, bucketSlot);
        if (row.logicalId.startsWith(expectedPrefix) &&
          built.rows.find((candidate: HuaweiSpaceHistoryRow): boolean => candidate.rowId === row.rowId) === undefined) {
          rowIdsToDeleteBeforePublish.push(row.rowId);
        }
      });
    }

    const stateChecksum = this.sha256Hex(JSON.stringify(normalized));
    const head = this.buildHead(
      headSlot,
      generation,
      timestamp,
      bucketReferences,
      normalized,
      stateChecksum
    );
    rowsToUpsert.push(head);
    return {
      state: normalized,
      rowsToUpsert,
      rowIdsToDeleteBeforePublish: Array.from(new Set<string>(rowIdsToDeleteBeforePublish)).sort(),
      legacyRowIdsToDeleteAfterConfirmation: mirror.legacyRowIds.slice(),
      targetHeadRowId: head.rowId,
      targetDeviceId: this.deviceId,
      targetGeneration: generation,
      targetStateChecksum: stateChecksum
    };
  }

  async buildProjectionCooperatively(
    state: HuaweiSpaceHistorySyncState,
    mirror: HuaweiSpaceHistoryPhysicalMirror,
    throttle: AiraSyncCooperativeThrottle,
    generatedAt: number = Date.now()
  ): Promise<HuaweiSpaceHistoryProjection> {
    const normalized = await this.mergeService.normalizeCooperatively(state, throttle);
    const ownHead = mirror.selectedHeads.find((head: HuaweiSpaceHistoryHead): boolean => {
      return head.value.deviceId === this.deviceId;
    });
    if (ownHead !== undefined && await this.mergeService.sameStateCooperatively(
      ownHead.state,
      normalized,
      throttle
    )) {
      return {
        state: normalized,
        rowsToUpsert: [],
        rowIdsToDeleteBeforePublish: [],
        legacyRowIdsToDeleteAfterConfirmation: mirror.legacyRowIds.slice(),
        targetHeadRowId: ownHead.row.rowId,
        targetDeviceId: this.deviceId,
        targetGeneration: ownHead.value.generation,
        targetStateChecksum: ownHead.value.stateChecksum
      };
    }
    const timestamp = this.requireTimestamp(generatedAt, 'generatedAt');
    const maxKnownGeneration = await this.resolveMaxKnownGenerationCooperatively(mirror.rows, throttle);
    const generation = maxKnownGeneration + 1;
    if (!Number.isSafeInteger(generation) || generation <= 0) {
      throw new Error('Huawei History snapshot generation is exhausted.');
    }
    const headSlot = ownHead === undefined ? 0 : 1 - ownHead.value.headSlot;
    const desiredBuckets = await this.buildBucketRecordsCooperatively(normalized, throttle);
    const bucketReferences: HuaweiSpaceHistoryBucketReference[] = [];
    const rowsToUpsert: HuaweiSpaceHistoryRow[] = [];
    const rowIdsToDeleteBeforePublish: string[] = [];
    for (let bucketIndex = 0; bucketIndex < HUAWEI_SPACE_HISTORY_BUCKET_COUNT; bucketIndex += 1) {
      const desiredRecords = desiredBuckets.get(bucketIndex) ?? [];
      const currentReference = ownHead?.value.buckets[bucketIndex];
      const currentRecords = ownHead?.bucketRecords.get(bucketIndex) ?? [];
      if (currentReference !== undefined && await this.sameRecordsCooperatively(
        currentRecords,
        desiredRecords,
        throttle
      )) {
        bucketReferences.push(currentReference);
        continue;
      }
      const bucketSlot = currentReference === undefined ? 0 : 1 - currentReference.bucketSlot;
      const built = await this.buildBucketCooperatively(
        bucketIndex,
        bucketSlot,
        generation,
        timestamp,
        desiredRecords,
        throttle
      );
      rowsToUpsert.push(...built.rows);
      bucketReferences.push(built.reference);
      const builtRowIds = new Set<string>();
      built.rows.forEach((row: HuaweiSpaceHistoryRow): void => {
        builtRowIds.add(row.rowId);
      });
      const expectedPrefix = this.buildChunkLogicalPrefix(this.deviceId, bucketIndex, bucketSlot);
      for (let rowIndex = 0; rowIndex < mirror.rows.length; rowIndex += 1) {
        const row = mirror.rows[rowIndex];
        if (row.recordKind === 'snapshot_chunk' && row.logicalId.startsWith(expectedPrefix) &&
          !builtRowIds.has(row.rowId)) {
          rowIdsToDeleteBeforePublish.push(row.rowId);
        }
        await throttle.afterBatchItem(rowIndex + 1);
      }
      await throttle.afterStage();
    }
    const stateChecksum = await this.sha256HistoryStateCooperatively(normalized, throttle);
    const head = this.buildHead(headSlot, generation, timestamp, bucketReferences, normalized, stateChecksum);
    rowsToUpsert.push(head);
    const sortedRowIdsToDelete = await this.sortStringsCooperatively(
      Array.from(new Set<string>(rowIdsToDeleteBeforePublish)),
      throttle
    );
    return {
      state: normalized,
      rowsToUpsert,
      rowIdsToDeleteBeforePublish: sortedRowIdsToDelete,
      legacyRowIdsToDeleteAfterConfirmation: mirror.legacyRowIds.slice(),
      targetHeadRowId: head.rowId,
      targetDeviceId: this.deviceId,
      targetGeneration: generation,
      targetStateChecksum: stateChecksum
    };
  }

  isProjectionTargetConfirmed(
    mirror: HuaweiSpaceHistoryPhysicalMirror,
    targetHeadRowId: string,
    targetDeviceId: string,
    targetGeneration: number,
    targetStateChecksum: string
  ): boolean {
    const head = mirror.selectedHeads.find((value: HuaweiSpaceHistoryHead): boolean => {
      return value.row.rowId === targetHeadRowId &&
        value.value.deviceId === targetDeviceId &&
        value.value.generation === targetGeneration;
    });
    return head !== undefined && head.value.stateChecksum === targetStateChecksum;
  }

  isProjectionConfirmed(
    mirror: HuaweiSpaceHistoryPhysicalMirror,
    projection: HuaweiSpaceHistoryProjection
  ): boolean {
    const head = mirror.selectedHeads.find((value: HuaweiSpaceHistoryHead): boolean => {
      return value.row.rowId === projection.targetHeadRowId &&
        value.value.deviceId === projection.targetDeviceId &&
        value.value.generation === projection.targetGeneration;
    });
    return head !== undefined && this.mergeService.sameState(head.state, projection.state);
  }

  async isProjectionConfirmedCooperatively(
    mirror: HuaweiSpaceHistoryPhysicalMirror,
    projection: HuaweiSpaceHistoryProjection,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<boolean> {
    const head = mirror.selectedHeads.find((value: HuaweiSpaceHistoryHead): boolean => {
      return value.row.rowId === projection.targetHeadRowId &&
        value.value.deviceId === projection.targetDeviceId &&
        value.value.generation === projection.targetGeneration;
    });
    return head !== undefined && await this.mergeService.sameStateCooperatively(
      head.state,
      projection.state,
      throttle
    );
  }

  requireRecordKind(value: string): HuaweiSpaceHistoryRecordKind {
    if (value === 'visit' || value === 'tombstone' || value === 'delete_range' ||
      value === 'clear_before' || value === 'retention_frontier' ||
      value === 'snapshot_head' || value === 'snapshot_bucket' || value === 'snapshot_chunk') {
      return value;
    }
    throw new Error('Huawei History record kind is invalid.');
  }

  validateOuterRow(row: HuaweiSpaceHistoryRow): void {
    if (row.rowId.trim().length <= 0 || row.logicalId.trim().length <= 0) {
      throw new Error('Huawei History row identity is empty.');
    }
    if (this.isLegacyRecordKind(row.recordKind)) {
      if (row.rowId !== this.buildLegacyRowId(row.recordKind, row.logicalId, row.data)) {
        throw new Error('Huawei History legacy row identity is invalid.');
      }
      return;
    }
    if (row.rowId !== this.buildCompactRowId(row.recordKind, row.logicalId)) {
      throw new Error('Huawei History compact row identity is invalid.');
    }
  }

  private appendLegacyRow(state: HuaweiSpaceHistorySyncState, row: HuaweiSpaceHistoryRow): void {
    this.validateOuterRow(row);
    if (row.recordKind === 'visit') {
      state.visits.push(this.parseVisit(row.logicalId, row.updatedAt, row.data));
      return;
    }
    if (row.recordKind === 'tombstone') {
      state.tombstones.push(this.parseTombstone(row.logicalId, row.updatedAt, row.data));
      return;
    }
    if (row.recordKind === 'delete_range') {
      state.deleteRanges.push(this.parseDeleteRange(row.logicalId, row.updatedAt, row.data));
      return;
    }
    if (row.recordKind === 'clear_before') {
      state.clearBefore = Math.max(state.clearBefore, this.parseClearBefore(row.logicalId, row.updatedAt, row.data));
      return;
    }
    const incoming = this.mergeService.emptyState();
    incoming.retentionFrontier = this.parseRetentionFrontier(row.logicalId, row.updatedAt, row.data);
    state.retentionFrontier = this.mergeService.merge(state, incoming, 0).retentionFrontier;
  }

  private buildBucketRecords(
    state: HuaweiSpaceHistorySyncState
  ): Map<number, HuaweiSpaceHistorySnapshotRecord[]> {
    const buckets = new Map<number, HuaweiSpaceHistorySnapshotRecord[]>();
    for (let index = 0; index < HUAWEI_SPACE_HISTORY_BUCKET_COUNT; index += 1) {
      buckets.set(index, []);
    }
    state.visits.forEach((value: HistorySyncVisit): void => {
      this.appendSnapshotRecord(buckets, this.buildVisitRecord(value));
    });
    state.tombstones.forEach((value: HistorySyncExactTombstone): void => {
      this.appendSnapshotRecord(buckets, this.buildTombstoneRecord(value));
    });
    state.deleteRanges.forEach((value: HistorySyncDeleteRange): void => {
      this.appendSnapshotRecord(buckets, this.buildDeleteRangeRecord(value));
    });
    if (state.clearBefore > 0) {
      const payload: HuaweiSpaceHistoryClearBeforePayload = { clearBefore: state.clearBefore };
      this.appendSnapshotRecord(buckets, {
        kind: 'c',
        logicalId: String(state.clearBefore),
        updatedAt: state.clearBefore,
        data: payload
      });
    }
    const frontier = state.retentionFrontier;
    if (frontier.cutoffAt > 0 || frontier.boundaryVisitedAt > 0) {
      this.appendSnapshotRecord(buckets, {
        kind: 'r',
        logicalId: this.buildRetentionFrontierLogicalId(frontier),
        updatedAt: frontier.updatedAt,
        data: frontier
      });
    }
    buckets.forEach((records: HuaweiSpaceHistorySnapshotRecord[]): void => {
      records.sort((left: HuaweiSpaceHistorySnapshotRecord, right: HuaweiSpaceHistorySnapshotRecord): number => {
        return this.buildSnapshotRecordKey(left).localeCompare(this.buildSnapshotRecordKey(right));
      });
    });
    return buckets;
  }

  private async buildBucketRecordsCooperatively(
    state: HuaweiSpaceHistorySyncState,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<Map<number, HuaweiSpaceHistorySnapshotRecord[]>> {
    const buckets = new Map<number, HuaweiSpaceHistorySnapshotRecord[]>();
    for (let index = 0; index < HUAWEI_SPACE_HISTORY_BUCKET_COUNT; index += 1) {
      buckets.set(index, []);
    }
    let processed = 0;
    for (let index = 0; index < state.visits.length; index += 1) {
      this.appendSnapshotRecord(buckets, this.buildVisitRecord(state.visits[index]));
      processed += 1;
      await throttle.afterBatchItem(processed);
    }
    for (let index = 0; index < state.tombstones.length; index += 1) {
      this.appendSnapshotRecord(buckets, this.buildTombstoneRecord(state.tombstones[index]));
      processed += 1;
      await throttle.afterBatchItem(processed);
    }
    for (let index = 0; index < state.deleteRanges.length; index += 1) {
      this.appendSnapshotRecord(buckets, this.buildDeleteRangeRecord(state.deleteRanges[index]));
      processed += 1;
      await throttle.afterBatchItem(processed);
    }
    if (state.clearBefore > 0) {
      const payload: HuaweiSpaceHistoryClearBeforePayload = { clearBefore: state.clearBefore };
      this.appendSnapshotRecord(buckets, {
        kind: 'c',
        logicalId: String(state.clearBefore),
        updatedAt: state.clearBefore,
        data: payload
      });
    }
    const frontier = state.retentionFrontier;
    if (frontier.cutoffAt > 0 || frontier.boundaryVisitedAt > 0) {
      this.appendSnapshotRecord(buckets, {
        kind: 'r',
        logicalId: this.buildRetentionFrontierLogicalId(frontier),
        updatedAt: frontier.updatedAt,
        data: frontier
      });
    }
    for (let bucketIndex = 0; bucketIndex < HUAWEI_SPACE_HISTORY_BUCKET_COUNT; bucketIndex += 1) {
      const records = buckets.get(bucketIndex) ?? [];
      const sortedRecords = await this.sortSnapshotRecordsCooperatively(records, throttle);
      buckets.set(bucketIndex, sortedRecords);
      await throttle.afterStage();
    }
    return buckets;
  }

  private appendSnapshotRecord(
    buckets: Map<number, HuaweiSpaceHistorySnapshotRecord[]>,
    record: HuaweiSpaceHistorySnapshotRecord
  ): void {
    const bucketIndex = this.resolveBucketIndex(this.buildSnapshotRecordKey(record));
    const records = buckets.get(bucketIndex) ?? [];
    records.push(record);
    buckets.set(bucketIndex, records);
  }

  private buildBucket(
    bucketIndex: number,
    bucketSlot: number,
    generation: number,
    generatedAt: number,
    records: HuaweiSpaceHistorySnapshotRecord[]
  ): HuaweiSpaceHistoryBuiltBucket {
    const rows: HuaweiSpaceHistoryRow[] = [];
    const chunkReferences: HuaweiSpaceHistoryChunkReference[] = [];
    let pending: HuaweiSpaceHistorySnapshotRecord[] = [];
    const flush = (): void => {
      const segmentIndex = chunkReferences.length;
      const chunk = this.buildChunk(
        bucketIndex,
        bucketSlot,
        segmentIndex,
        generation,
        generatedAt,
        pending
      );
      rows.push(chunk.row);
      chunkReferences.push(chunk.reference);
      pending = [];
    };
    records.forEach((record: HuaweiSpaceHistorySnapshotRecord): void => {
      const candidate = pending.concat([record]);
      const candidateData = this.buildChunkData(
        bucketIndex,
        bucketSlot,
        chunkReferences.length,
        generation,
        generatedAt,
        candidate
      );
      const candidateJson = JSON.stringify(candidateData);
      if (this.byteLength(candidateJson) <= HUAWEI_SPACE_HISTORY_CHUNK_TARGET_BYTES) {
        pending = candidate;
        return;
      }
      if (pending.length <= 0) {
        throw new Error('One Huawei History record exceeds the compact chunk row limit.');
      }
      flush();
      const singleData = this.buildChunkData(
        bucketIndex,
        bucketSlot,
        chunkReferences.length,
        generation,
        generatedAt,
        [record]
      );
      if (this.byteLength(JSON.stringify(singleData)) > HUAWEI_SPACE_HISTORY_CHUNK_TARGET_BYTES) {
        throw new Error('One Huawei History record exceeds the compact chunk row limit.');
      }
      pending = [record];
    });
    if (pending.length > 0) {
      flush();
    }
    if (chunkReferences.length > HUAWEI_SPACE_HISTORY_MAX_CHUNKS_PER_BUCKET) {
      throw new Error('Huawei History bucket exceeds the compact snapshot safety limit.');
    }
    const bucketData: HuaweiSpaceHistoryBucketData = {
      formatVersion: HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION,
      deviceId: this.deviceId,
      bucketIndex,
      bucketSlot,
      generatedAt,
      chunks: chunkReferences
    };
    const encoded = JSON.stringify(bucketData);
    this.assertRowSize(encoded);
    const logicalId = this.buildBucketLogicalId(this.deviceId, bucketIndex, bucketSlot);
    const bucketRow: HuaweiSpaceHistoryRow = {
      rowId: this.buildCompactRowId('snapshot_bucket', logicalId),
      recordKind: 'snapshot_bucket',
      logicalId,
      data: encoded,
      updatedAt: generatedAt
    };
    rows.push(bucketRow);
    const reference: HuaweiSpaceHistoryBucketReference = {
      bucketIndex,
      bucketSlot,
      hash: this.sha256Hex(encoded),
      recordCount: records.length
    };
    const built: HuaweiSpaceHistoryBuiltBucket = {
      rows,
      reference
    };
    return built;
  }

  private async buildBucketCooperatively(
    bucketIndex: number,
    bucketSlot: number,
    generation: number,
    generatedAt: number,
    records: HuaweiSpaceHistorySnapshotRecord[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistoryBuiltBucket> {
    const rows: HuaweiSpaceHistoryRow[] = [];
    const chunkReferences: HuaweiSpaceHistoryChunkReference[] = [];
    let pending: HuaweiSpaceHistorySnapshotRecord[] = [];
    for (let index = 0; index < records.length; index += 1) {
      const record = records[index];
      const candidate = pending.concat([record]);
      const candidateData = this.buildChunkData(
        bucketIndex,
        bucketSlot,
        chunkReferences.length,
        generation,
        generatedAt,
        candidate
      );
      if (this.byteLength(JSON.stringify(candidateData)) <= HUAWEI_SPACE_HISTORY_CHUNK_TARGET_BYTES) {
        pending = candidate;
      } else {
        if (pending.length <= 0) {
          throw new Error('One Huawei History record exceeds the compact chunk row limit.');
        }
        const chunk = this.buildChunk(
          bucketIndex,
          bucketSlot,
          chunkReferences.length,
          generation,
          generatedAt,
          pending
        );
        rows.push(chunk.row);
        chunkReferences.push(chunk.reference);
        const singleData = this.buildChunkData(
          bucketIndex,
          bucketSlot,
          chunkReferences.length,
          generation,
          generatedAt,
          [record]
        );
        if (this.byteLength(JSON.stringify(singleData)) > HUAWEI_SPACE_HISTORY_CHUNK_TARGET_BYTES) {
          throw new Error('One Huawei History record exceeds the compact chunk row limit.');
        }
        pending = [record];
      }
      await throttle.afterBatchItem(index + 1);
    }
    if (pending.length > 0) {
      const chunk = this.buildChunk(
        bucketIndex,
        bucketSlot,
        chunkReferences.length,
        generation,
        generatedAt,
        pending
      );
      rows.push(chunk.row);
      chunkReferences.push(chunk.reference);
    }
    if (chunkReferences.length > HUAWEI_SPACE_HISTORY_MAX_CHUNKS_PER_BUCKET) {
      throw new Error('Huawei History bucket exceeds the compact snapshot safety limit.');
    }
    const bucketData: HuaweiSpaceHistoryBucketData = {
      formatVersion: HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION,
      deviceId: this.deviceId,
      bucketIndex,
      bucketSlot,
      generatedAt,
      chunks: chunkReferences
    };
    const encoded = JSON.stringify(bucketData);
    this.assertRowSize(encoded);
    const logicalId = this.buildBucketLogicalId(this.deviceId, bucketIndex, bucketSlot);
    const bucketRow: HuaweiSpaceHistoryRow = {
      rowId: this.buildCompactRowId('snapshot_bucket', logicalId),
      recordKind: 'snapshot_bucket',
      logicalId,
      data: encoded,
      updatedAt: generatedAt
    };
    rows.push(bucketRow);
    return {
      rows,
      reference: {
        bucketIndex,
        bucketSlot,
        hash: this.sha256Hex(encoded),
        recordCount: records.length
      }
    };
  }

  private buildChunk(
    bucketIndex: number,
    bucketSlot: number,
    segmentIndex: number,
    generation: number,
    generatedAt: number,
    records: HuaweiSpaceHistorySnapshotRecord[]
  ): HuaweiSpaceHistoryBuiltChunk {
    const value = this.buildChunkData(
      bucketIndex,
      bucketSlot,
      segmentIndex,
      generation,
      generatedAt,
      records
    );
    const encoded = JSON.stringify(value);
    this.assertRowSize(encoded);
    const logicalId = this.buildChunkLogicalId(this.deviceId, bucketIndex, bucketSlot, segmentIndex);
    const row: HuaweiSpaceHistoryRow = {
      rowId: this.buildCompactRowId('snapshot_chunk', logicalId),
      recordKind: 'snapshot_chunk',
      logicalId,
      data: encoded,
      updatedAt: generatedAt
    };
    const reference: HuaweiSpaceHistoryChunkReference = {
      segmentIndex,
      hash: this.sha256Hex(encoded),
      recordCount: records.length
    };
    const built: HuaweiSpaceHistoryBuiltChunk = { row, reference };
    return built;
  }

  private buildChunkData(
    bucketIndex: number,
    bucketSlot: number,
    segmentIndex: number,
    _generation: number,
    generatedAt: number,
    records: HuaweiSpaceHistorySnapshotRecord[]
  ): HuaweiSpaceHistoryChunkData {
    return {
      formatVersion: HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION,
      deviceId: this.deviceId,
      bucketIndex,
      bucketSlot,
      segmentIndex,
      generatedAt,
      records
    };
  }

  private buildHead(
    headSlot: number,
    generation: number,
    generatedAt: number,
    buckets: HuaweiSpaceHistoryBucketReference[],
    state: HuaweiSpaceHistorySyncState,
    stateChecksum?: string
  ): HuaweiSpaceHistoryRow {
    const value: HuaweiSpaceHistoryHeadData = {
      formatVersion: HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION,
      deviceId: this.deviceId,
      headSlot,
      generation,
      generatedAt,
      buckets,
      counts: this.countState(state),
      stateChecksum: stateChecksum ?? this.sha256Hex(JSON.stringify(state))
    };
    const encoded = JSON.stringify(value);
    this.assertRowSize(encoded);
    const logicalId = this.buildHeadLogicalId(this.deviceId, headSlot);
    return {
      rowId: this.buildCompactRowId('snapshot_head', logicalId),
      recordKind: 'snapshot_head',
      logicalId,
      data: encoded,
      updatedAt: generatedAt
    };
  }

  private parseChunk(row: HuaweiSpaceHistoryRow): HuaweiSpaceHistoryChunk {
    this.validateOuterRow(row);
    const value = JSON.parse(row.data) as HuaweiSpaceHistoryChunkData;
    this.requireCompactHeader(value.formatVersion, value.deviceId, value.bucketIndex, value.bucketSlot);
    this.requireInteger(value.segmentIndex, 0, HUAWEI_SPACE_HISTORY_MAX_CHUNKS_PER_BUCKET - 1, 'segmentIndex');
    this.requireTimestamp(value.generatedAt, 'generatedAt');
    if (!Array.isArray(value.records) || value.records.length <= 0 || row.updatedAt !== value.generatedAt) {
      throw new Error('Huawei History snapshot chunk metadata is invalid.');
    }
    const records = value.records.map((record: HuaweiSpaceHistorySnapshotRecord): HuaweiSpaceHistorySnapshotRecord => {
      return this.parseSnapshotRecord(record);
    });
    const canonical: HuaweiSpaceHistoryChunkData = {
      formatVersion: HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION,
      deviceId: value.deviceId,
      bucketIndex: value.bucketIndex,
      bucketSlot: value.bucketSlot,
      segmentIndex: value.segmentIndex,
      generatedAt: value.generatedAt,
      records
    };
    const expectedLogicalId = this.buildChunkLogicalId(
      canonical.deviceId,
      canonical.bucketIndex,
      canonical.bucketSlot,
      canonical.segmentIndex
    );
    if (row.logicalId !== expectedLogicalId || JSON.stringify(canonical) !== row.data) {
      throw new Error('Huawei History snapshot chunk is not canonical.');
    }
    return { row, value: canonical, hash: this.sha256Hex(row.data) };
  }

  private parseBucket(row: HuaweiSpaceHistoryRow): HuaweiSpaceHistoryBucket {
    this.validateOuterRow(row);
    const value = JSON.parse(row.data) as HuaweiSpaceHistoryBucketData;
    this.requireCompactHeader(value.formatVersion, value.deviceId, value.bucketIndex, value.bucketSlot);
    this.requireTimestamp(value.generatedAt, 'generatedAt');
    if (!Array.isArray(value.chunks) || value.chunks.length > HUAWEI_SPACE_HISTORY_MAX_CHUNKS_PER_BUCKET ||
      row.updatedAt !== value.generatedAt) {
      throw new Error('Huawei History snapshot bucket metadata is invalid.');
    }
    const chunks: HuaweiSpaceHistoryChunkReference[] = value.chunks.map(
      (reference: HuaweiSpaceHistoryChunkReference, index: number): HuaweiSpaceHistoryChunkReference => {
        this.requireInteger(reference.segmentIndex, 0, HUAWEI_SPACE_HISTORY_MAX_CHUNKS_PER_BUCKET - 1, 'segmentIndex');
        this.requireHash(reference.hash, 'chunk hash');
        this.requireInteger(reference.recordCount, 1, 100000, 'recordCount');
        if (reference.segmentIndex !== index) {
          throw new Error('Huawei History snapshot chunk references are not contiguous.');
        }
        return {
          segmentIndex: reference.segmentIndex,
          hash: reference.hash,
          recordCount: reference.recordCount
        };
      }
    );
    const canonical: HuaweiSpaceHistoryBucketData = {
      formatVersion: HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION,
      deviceId: value.deviceId,
      bucketIndex: value.bucketIndex,
      bucketSlot: value.bucketSlot,
      generatedAt: value.generatedAt,
      chunks
    };
    const expectedLogicalId = this.buildBucketLogicalId(
      canonical.deviceId,
      canonical.bucketIndex,
      canonical.bucketSlot
    );
    if (row.logicalId !== expectedLogicalId || JSON.stringify(canonical) !== row.data) {
      throw new Error('Huawei History snapshot bucket is not canonical.');
    }
    return { row, value: canonical, hash: this.sha256Hex(row.data) };
  }

  private parseHead(row: HuaweiSpaceHistoryRow): HuaweiSpaceHistoryHeadData {
    this.validateOuterRow(row);
    const value = JSON.parse(row.data) as HuaweiSpaceHistoryHeadData;
    if (value.formatVersion !== HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION ||
      typeof value.deviceId !== 'string' || value.deviceId.trim().length <= 0) {
      throw new Error('Huawei History snapshot head identity is invalid.');
    }
    this.requireInteger(value.headSlot, 0, HUAWEI_SPACE_HISTORY_SLOT_COUNT - 1, 'headSlot');
    this.requireInteger(value.generation, 1, Number.MAX_SAFE_INTEGER, 'generation');
    this.requireTimestamp(value.generatedAt, 'generatedAt');
    this.requireHash(value.stateChecksum, 'stateChecksum');
    const buckets = this.parseBucketReferences(value.buckets);
    const counts = this.parseCounts(value.counts);
    const canonical: HuaweiSpaceHistoryHeadData = {
      formatVersion: HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION,
      deviceId: value.deviceId.trim(),
      headSlot: value.headSlot,
      generation: value.generation,
      generatedAt: value.generatedAt,
      buckets,
      counts,
      stateChecksum: value.stateChecksum
    };
    const expectedLogicalId = this.buildHeadLogicalId(canonical.deviceId, canonical.headSlot);
    if (row.logicalId !== expectedLogicalId || row.updatedAt !== canonical.generatedAt ||
      JSON.stringify(canonical) !== row.data) {
      throw new Error('Huawei History snapshot head is not canonical.');
    }
    return canonical;
  }

  private materializeHeads(
    heads: HuaweiSpaceHistoryHeadData[],
    bucketsByRowId: Map<string, HuaweiSpaceHistoryBucket>,
    chunksByRowId: Map<string, HuaweiSpaceHistoryChunk>
  ): HuaweiSpaceHistoryHead[] {
    const complete: HuaweiSpaceHistoryHead[] = [];
    heads.forEach((head: HuaweiSpaceHistoryHeadData): void => {
      const materialized = this.materializeHead(head, bucketsByRowId, chunksByRowId);
      if (materialized !== undefined) {
        complete.push(materialized);
      }
    });
    return complete;
  }

  private async materializeHeadsCooperatively(
    heads: HuaweiSpaceHistoryHeadData[],
    bucketsByRowId: Map<string, HuaweiSpaceHistoryBucket>,
    chunksByRowId: Map<string, HuaweiSpaceHistoryChunk>,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistoryHead[]> {
    const complete: HuaweiSpaceHistoryHead[] = [];
    for (let index = 0; index < heads.length; index += 1) {
      const materialized = await this.materializeHeadCooperatively(
        heads[index],
        bucketsByRowId,
        chunksByRowId,
        throttle
      );
      if (materialized !== undefined) {
        complete.push(materialized);
      }
      await throttle.afterStage();
    }
    return complete;
  }

  private materializeHead(
    head: HuaweiSpaceHistoryHeadData,
    bucketsByRowId: Map<string, HuaweiSpaceHistoryBucket>,
    chunksByRowId: Map<string, HuaweiSpaceHistoryChunk>
  ): HuaweiSpaceHistoryHead | undefined {
    const records: HuaweiSpaceHistorySnapshotRecord[] = [];
    const bucketRecords = new Map<number, HuaweiSpaceHistorySnapshotRecord[]>();
    for (let index = 0; index < head.buckets.length; index += 1) {
      const reference = head.buckets[index];
      const logicalId = this.buildBucketLogicalId(head.deviceId, reference.bucketIndex, reference.bucketSlot);
      const rowId = this.buildCompactRowId('snapshot_bucket', logicalId);
      const bucket = bucketsByRowId.get(rowId);
      if (bucket === undefined || bucket.hash !== reference.hash) {
        return undefined;
      }
      const materializedBucket: HuaweiSpaceHistorySnapshotRecord[] = [];
      for (let chunkIndex = 0; chunkIndex < bucket.value.chunks.length; chunkIndex += 1) {
        const chunkReference = bucket.value.chunks[chunkIndex];
        const chunkLogicalId = this.buildChunkLogicalId(
          head.deviceId,
          reference.bucketIndex,
          reference.bucketSlot,
          chunkReference.segmentIndex
        );
        const chunkRowId = this.buildCompactRowId('snapshot_chunk', chunkLogicalId);
        const chunk = chunksByRowId.get(chunkRowId);
        if (chunk === undefined || chunk.hash !== chunkReference.hash ||
          chunk.value.records.length !== chunkReference.recordCount) {
          return undefined;
        }
        materializedBucket.push(...chunk.value.records);
      }
      if (materializedBucket.length !== reference.recordCount ||
        !this.isCanonicalBucket(reference.bucketIndex, materializedBucket)) {
        return undefined;
      }
      bucketRecords.set(reference.bucketIndex, materializedBucket);
      records.push(...materializedBucket);
    }
    const state = this.stateFromRecords(records);
    if (!this.sameCounts(this.countState(state), head.counts) ||
      this.sha256Hex(JSON.stringify(state)) !== head.stateChecksum) {
      return undefined;
    }
    const logicalId = this.buildHeadLogicalId(head.deviceId, head.headSlot);
    const rowId = this.buildCompactRowId('snapshot_head', logicalId);
    return {
      row: {
        rowId,
        recordKind: 'snapshot_head',
        logicalId,
        data: JSON.stringify(head),
        updatedAt: head.generatedAt
      },
      value: head,
      bucketRecords,
      state
    };
  }

  private async materializeHeadCooperatively(
    head: HuaweiSpaceHistoryHeadData,
    bucketsByRowId: Map<string, HuaweiSpaceHistoryBucket>,
    chunksByRowId: Map<string, HuaweiSpaceHistoryChunk>,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistoryHead | undefined> {
    const records: HuaweiSpaceHistorySnapshotRecord[] = [];
    const bucketRecords = new Map<number, HuaweiSpaceHistorySnapshotRecord[]>();
    for (let index = 0; index < head.buckets.length; index += 1) {
      const reference = head.buckets[index];
      const logicalId = this.buildBucketLogicalId(head.deviceId, reference.bucketIndex, reference.bucketSlot);
      const rowId = this.buildCompactRowId('snapshot_bucket', logicalId);
      const bucket = bucketsByRowId.get(rowId);
      if (bucket === undefined || bucket.hash !== reference.hash) {
        return undefined;
      }
      const materializedBucket: HuaweiSpaceHistorySnapshotRecord[] = [];
      for (let chunkIndex = 0; chunkIndex < bucket.value.chunks.length; chunkIndex += 1) {
        const chunkReference = bucket.value.chunks[chunkIndex];
        const chunkLogicalId = this.buildChunkLogicalId(
          head.deviceId,
          reference.bucketIndex,
          reference.bucketSlot,
          chunkReference.segmentIndex
        );
        const chunkRowId = this.buildCompactRowId('snapshot_chunk', chunkLogicalId);
        const chunk = chunksByRowId.get(chunkRowId);
        if (chunk === undefined || chunk.hash !== chunkReference.hash ||
          chunk.value.records.length !== chunkReference.recordCount) {
          return undefined;
        }
        materializedBucket.push(...chunk.value.records);
        await throttle.afterBatchItem(chunkIndex + 1);
      }
      if (materializedBucket.length !== reference.recordCount ||
        !await this.isCanonicalBucketCooperatively(reference.bucketIndex, materializedBucket, throttle)) {
        return undefined;
      }
      bucketRecords.set(reference.bucketIndex, materializedBucket);
      records.push(...materializedBucket);
      await throttle.afterStage();
    }
    const state = await this.stateFromRecordsCooperatively(records, throttle);
    const stateChecksum = await this.sha256HistoryStateCooperatively(state, throttle);
    if (!this.sameCounts(this.countState(state), head.counts) || stateChecksum !== head.stateChecksum) {
      return undefined;
    }
    const logicalId = this.buildHeadLogicalId(head.deviceId, head.headSlot);
    const rowId = this.buildCompactRowId('snapshot_head', logicalId);
    return {
      row: {
        rowId,
        recordKind: 'snapshot_head',
        logicalId,
        data: JSON.stringify(head),
        updatedAt: head.generatedAt
      },
      value: head,
      bucketRecords,
      state
    };
  }

  private selectNewestHeadPerDevice(heads: HuaweiSpaceHistoryHead[]): HuaweiSpaceHistoryHead[] {
    const selected = new Map<string, HuaweiSpaceHistoryHead>();
    heads.forEach((head: HuaweiSpaceHistoryHead): void => {
      const existing = selected.get(head.value.deviceId);
      if (existing === undefined || head.value.generation > existing.value.generation ||
        (head.value.generation === existing.value.generation && head.value.headSlot > existing.value.headSlot)) {
        selected.set(head.value.deviceId, head);
      }
    });
    return Array.from(selected.values()).sort((left: HuaweiSpaceHistoryHead, right: HuaweiSpaceHistoryHead): number => {
      return left.value.deviceId.localeCompare(right.value.deviceId);
    });
  }

  private async selectNewestHeadPerDeviceCooperatively(
    heads: HuaweiSpaceHistoryHead[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistoryHead[]> {
    const selected = new Map<string, HuaweiSpaceHistoryHead>();
    for (let index = 0; index < heads.length; index += 1) {
      const head = heads[index];
      const existing = selected.get(head.value.deviceId);
      if (existing === undefined || head.value.generation > existing.value.generation ||
        (head.value.generation === existing.value.generation && head.value.headSlot > existing.value.headSlot)) {
        selected.set(head.value.deviceId, head);
      }
      await throttle.afterBatchItem(index + 1);
    }
    return this.sortHeadsCooperatively(Array.from(selected.values()), throttle);
  }

  private async sortHeadsCooperatively(
    values: HuaweiSpaceHistoryHead[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistoryHead[]> {
    if (values.length <= 1) {
      return values.slice();
    }
    let source = values.slice();
    let target = values.slice();
    let width = 1;
    let processed = 0;
    while (width < source.length) {
      for (let start = 0; start < source.length; start += width * 2) {
        let left = start;
        const leftEnd = Math.min(start + width, source.length);
        let right = leftEnd;
        const rightEnd = Math.min(start + width * 2, source.length);
        let output = start;
        while (left < leftEnd || right < rightEnd) {
          if (right >= rightEnd || (left < leftEnd &&
            source[left].value.deviceId.localeCompare(source[right].value.deviceId) <= 0)) {
            target[output] = source[left];
            left += 1;
          } else {
            target[output] = source[right];
            right += 1;
          }
          output += 1;
          processed += 1;
          await throttle.afterBatchItem(processed);
        }
      }
      const swap = source;
      source = target;
      target = swap;
      width *= 2;
      await throttle.afterStage();
    }
    return source;
  }

  private async sortStringsCooperatively(
    values: string[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<string[]> {
    if (values.length <= 1) {
      return values.slice();
    }
    let source = values.slice();
    let target = values.slice();
    let width = 1;
    let processed = 0;
    while (width < source.length) {
      for (let start = 0; start < source.length; start += width * 2) {
        let left = start;
        const leftEnd = Math.min(start + width, source.length);
        let right = leftEnd;
        const rightEnd = Math.min(start + width * 2, source.length);
        let output = start;
        while (left < leftEnd || right < rightEnd) {
          if (right >= rightEnd ||
            (left < leftEnd && source[left].localeCompare(source[right]) <= 0)) {
            target[output] = source[left];
            left += 1;
          } else {
            target[output] = source[right];
            right += 1;
          }
          output += 1;
          processed += 1;
          await throttle.afterBatchItem(processed);
        }
      }
      const swap = source;
      source = target;
      target = swap;
      width *= 2;
      await throttle.afterStage();
    }
    return source;
  }

  private async sortSnapshotRecordsCooperatively(
    values: HuaweiSpaceHistorySnapshotRecord[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistorySnapshotRecord[]> {
    if (values.length <= 1) {
      return values.slice();
    }
    let source = values.slice();
    let target = values.slice();
    let width = 1;
    let processed = 0;
    while (width < source.length) {
      for (let start = 0; start < source.length; start += width * 2) {
        let left = start;
        const leftEnd = Math.min(start + width, source.length);
        let right = leftEnd;
        const rightEnd = Math.min(start + width * 2, source.length);
        let output = start;
        while (left < leftEnd || right < rightEnd) {
          const takeLeft = right >= rightEnd || (left < leftEnd &&
            this.buildSnapshotRecordKey(source[left]).localeCompare(
              this.buildSnapshotRecordKey(source[right])
            ) <= 0);
          if (takeLeft) {
            target[output] = source[left];
            left += 1;
          } else {
            target[output] = source[right];
            right += 1;
          }
          output += 1;
          processed += 1;
          await throttle.afterBatchItem(processed);
        }
      }
      const swap = source;
      source = target;
      target = swap;
      width *= 2;
      await throttle.afterStage();
    }
    return source;
  }

  private stateFromRecords(records: HuaweiSpaceHistorySnapshotRecord[]): HuaweiSpaceHistorySyncState {
    const state = this.mergeService.emptyState();
    records.forEach((record: HuaweiSpaceHistorySnapshotRecord): void => {
      if (record.kind === 'v') {
        state.visits.push(record.data as HistorySyncVisit);
      } else if (record.kind === 't') {
        state.tombstones.push(record.data as HistorySyncExactTombstone);
      } else if (record.kind === 'd') {
        state.deleteRanges.push(record.data as HistorySyncDeleteRange);
      } else if (record.kind === 'c') {
        const value = record.data as HuaweiSpaceHistoryClearBeforePayload;
        state.clearBefore = Math.max(state.clearBefore, value.clearBefore);
      } else {
        const incoming = this.mergeService.emptyState();
        incoming.retentionFrontier = record.data as HistorySyncRetentionFrontier;
        state.retentionFrontier = this.mergeService.merge(state, incoming, 0).retentionFrontier;
      }
    });
    return this.mergeService.normalize(state);
  }

  private async stateFromRecordsCooperatively(
    records: HuaweiSpaceHistorySnapshotRecord[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistorySyncState> {
    const state = this.mergeService.emptyState();
    for (let index = 0; index < records.length; index += 1) {
      const record = records[index];
      if (record.kind === 'v') {
        state.visits.push(record.data as HistorySyncVisit);
      } else if (record.kind === 't') {
        state.tombstones.push(record.data as HistorySyncExactTombstone);
      } else if (record.kind === 'd') {
        state.deleteRanges.push(record.data as HistorySyncDeleteRange);
      } else if (record.kind === 'c') {
        const value = record.data as HuaweiSpaceHistoryClearBeforePayload;
        state.clearBefore = Math.max(state.clearBefore, value.clearBefore);
      } else {
        const incoming = this.mergeService.emptyState();
        incoming.retentionFrontier = record.data as HistorySyncRetentionFrontier;
        state.retentionFrontier = this.mergeService.merge(state, incoming, 0).retentionFrontier;
      }
      await throttle.afterBatchItem(index + 1);
    }
    return this.mergeService.normalizeCooperatively(state, throttle);
  }

  private parseSnapshotRecord(value: HuaweiSpaceHistorySnapshotRecord): HuaweiSpaceHistorySnapshotRecord {
    if (value === null || typeof value !== 'object' || typeof value.logicalId !== 'string' ||
      typeof value.updatedAt !== 'number' || value.data === null || typeof value.data !== 'object') {
      throw new Error('Huawei History snapshot record is invalid.');
    }
    let canonical: HuaweiSpaceHistorySnapshotRecord;
    const encoded = JSON.stringify(value.data);
    if (value.kind === 'v') {
      const visit = this.parseVisit(value.logicalId, value.updatedAt, encoded);
      canonical = this.buildVisitRecord(visit);
    } else if (value.kind === 't') {
      const tombstone = this.parseTombstone(value.logicalId, value.updatedAt, encoded);
      canonical = this.buildTombstoneRecord(tombstone);
    } else if (value.kind === 'd') {
      const range = this.parseDeleteRange(value.logicalId, value.updatedAt, encoded);
      canonical = this.buildDeleteRangeRecord(range);
    } else if (value.kind === 'c') {
      const clearBefore = this.parseClearBefore(value.logicalId, value.updatedAt, encoded);
      canonical = {
        kind: 'c',
        logicalId: String(clearBefore),
        updatedAt: clearBefore,
        data: { clearBefore } as HuaweiSpaceHistoryClearBeforePayload
      };
    } else if (value.kind === 'r') {
      const frontier = this.parseRetentionFrontier(value.logicalId, value.updatedAt, encoded);
      canonical = {
        kind: 'r',
        logicalId: this.buildRetentionFrontierLogicalId(frontier),
        updatedAt: frontier.updatedAt,
        data: frontier
      };
    } else {
      throw new Error('Huawei History snapshot record kind is invalid.');
    }
    if (JSON.stringify(canonical) !== JSON.stringify(value)) {
      throw new Error('Huawei History snapshot record is not canonical.');
    }
    return canonical;
  }

  private buildVisitRecord(value: HistorySyncVisit): HuaweiSpaceHistorySnapshotRecord {
    const encoded = JSON.stringify(value);
    const canonical = this.parseVisit(value.visitId, value.visitedAt, encoded);
    return { kind: 'v', logicalId: canonical.visitId, updatedAt: canonical.visitedAt, data: canonical };
  }

  private buildTombstoneRecord(value: HistorySyncExactTombstone): HuaweiSpaceHistorySnapshotRecord {
    const encoded = JSON.stringify(value);
    const canonical = this.parseTombstone(value.visitId, value.deletedAt, encoded);
    return { kind: 't', logicalId: canonical.visitId, updatedAt: canonical.deletedAt, data: canonical };
  }

  private buildDeleteRangeRecord(value: HistorySyncDeleteRange): HuaweiSpaceHistorySnapshotRecord {
    const encoded = JSON.stringify(value);
    const canonical = this.parseDeleteRange(value.rangeId, value.endedAt, encoded);
    return { kind: 'd', logicalId: canonical.rangeId, updatedAt: canonical.endedAt, data: canonical };
  }

  private parseVisit(logicalId: string, updatedAt: number, encoded: string): HistorySyncVisit {
    const value = JSON.parse(encoded) as HistorySyncVisit;
    if (value === null || typeof value !== 'object' || typeof value.visitId !== 'string' ||
      typeof value.clientId !== 'string' || typeof value.nativeVisitId !== 'string' ||
      typeof value.url !== 'string' || typeof value.title !== 'string' ||
      typeof value.transition !== 'string' || typeof value.referrer !== 'string' ||
      typeof value.deviceName !== 'string' || typeof value.source !== 'string' ||
      !this.isHistoryTransition(value.transition)) {
      throw new Error('Huawei History visit payload is invalid.');
    }
    this.requireTimestamp(value.visitedAt, 'visitedAt');
    const state = this.mergeService.emptyState();
    state.visits = [value];
    const normalized = this.mergeService.normalize(state);
    if (normalized.visits.length !== 1) {
      throw new Error('Huawei History visit payload is not canonical.');
    }
    const canonical = normalized.visits[0];
    if (canonical.visitId !== logicalId || canonical.visitedAt !== updatedAt ||
      JSON.stringify(canonical) !== encoded) {
      throw new Error('Huawei History visit payload identity is invalid.');
    }
    return canonical;
  }

  private parseTombstone(logicalId: string, updatedAt: number, encoded: string): HistorySyncExactTombstone {
    const value = JSON.parse(encoded) as HistorySyncExactTombstone;
    this.requireTimestamp(value.deletedAt, 'deletedAt');
    const state = this.mergeService.emptyState();
    state.tombstones = [value];
    const normalized = this.mergeService.normalize(state);
    if (normalized.tombstones.length !== 1) {
      throw new Error('Huawei History tombstone payload is invalid.');
    }
    const canonical = normalized.tombstones[0];
    if (canonical.visitId !== logicalId || canonical.deletedAt !== updatedAt ||
      JSON.stringify(canonical) !== encoded) {
      throw new Error('Huawei History tombstone payload identity is invalid.');
    }
    return canonical;
  }

  private parseDeleteRange(logicalId: string, updatedAt: number, encoded: string): HistorySyncDeleteRange {
    const value = JSON.parse(encoded) as HistorySyncDeleteRange;
    const state = this.mergeService.emptyState();
    state.deleteRanges = [value];
    const normalized = this.mergeService.normalize(state);
    if (normalized.deleteRanges.length !== 1) {
      throw new Error('Huawei History delete range payload is invalid.');
    }
    const canonical = normalized.deleteRanges[0];
    if (canonical.rangeId !== logicalId || canonical.endedAt !== updatedAt ||
      JSON.stringify(canonical) !== encoded) {
      throw new Error('Huawei History delete range payload identity is invalid.');
    }
    return canonical;
  }

  private parseClearBefore(logicalId: string, updatedAt: number, encoded: string): number {
    const value = JSON.parse(encoded) as HuaweiSpaceHistoryClearBeforePayload;
    const clearBefore = this.requireTimestamp(value.clearBefore, 'clearBefore');
    const canonical: HuaweiSpaceHistoryClearBeforePayload = { clearBefore };
    if (logicalId !== String(clearBefore) || updatedAt !== clearBefore || JSON.stringify(canonical) !== encoded) {
      throw new Error('Huawei History clear frontier payload is invalid.');
    }
    return clearBefore;
  }

  private parseRetentionFrontier(
    logicalId: string,
    updatedAt: number,
    encoded: string
  ): HistorySyncRetentionFrontier {
    const value = JSON.parse(encoded) as HistorySyncRetentionFrontier;
    const state = this.mergeService.emptyState();
    state.retentionFrontier = value;
    const canonical = this.mergeService.normalize(state).retentionFrontier;
    if ((canonical.cutoffAt <= 0 && canonical.boundaryVisitedAt <= 0) ||
      logicalId !== this.buildRetentionFrontierLogicalId(canonical) || canonical.updatedAt !== updatedAt ||
      JSON.stringify(canonical) !== encoded) {
      throw new Error('Huawei History retention frontier payload is invalid.');
    }
    return canonical;
  }

  private parseBucketReferences(value: HuaweiSpaceHistoryBucketReference[]): HuaweiSpaceHistoryBucketReference[] {
    if (!Array.isArray(value) || value.length !== HUAWEI_SPACE_HISTORY_BUCKET_COUNT) {
      throw new Error('Huawei History snapshot head bucket count is invalid.');
    }
    return value.map(
      (reference: HuaweiSpaceHistoryBucketReference, index: number): HuaweiSpaceHistoryBucketReference => {
        this.requireInteger(reference.bucketIndex, 0, HUAWEI_SPACE_HISTORY_BUCKET_COUNT - 1, 'bucketIndex');
        this.requireInteger(reference.bucketSlot, 0, HUAWEI_SPACE_HISTORY_SLOT_COUNT - 1, 'bucketSlot');
        this.requireInteger(reference.recordCount, 0, 100000, 'recordCount');
        this.requireHash(reference.hash, 'bucket hash');
        if (reference.bucketIndex !== index) {
          throw new Error('Huawei History snapshot buckets are not canonical.');
        }
        return {
          bucketIndex: reference.bucketIndex,
          bucketSlot: reference.bucketSlot,
          hash: reference.hash,
          recordCount: reference.recordCount
        };
      }
    );
  }

  private parseCounts(value: HuaweiSpaceHistorySnapshotCounts): HuaweiSpaceHistorySnapshotCounts {
    const canonical: HuaweiSpaceHistorySnapshotCounts = {
      visits: this.requireInteger(value.visits, 0, 10000, 'visits'),
      tombstones: this.requireInteger(value.tombstones, 0, 100000, 'tombstones'),
      deleteRanges: this.requireInteger(value.deleteRanges, 0, 100000, 'deleteRanges'),
      clearBefore: this.requireInteger(value.clearBefore, 0, 1, 'clearBefore'),
      retentionFrontier: this.requireInteger(value.retentionFrontier, 0, 1, 'retentionFrontier')
    };
    return canonical;
  }

  private countState(state: HuaweiSpaceHistorySyncState): HuaweiSpaceHistorySnapshotCounts {
    return {
      visits: state.visits.length,
      tombstones: state.tombstones.length,
      deleteRanges: state.deleteRanges.length,
      clearBefore: state.clearBefore > 0 ? 1 : 0,
      retentionFrontier: state.retentionFrontier.cutoffAt > 0 || state.retentionFrontier.boundaryVisitedAt > 0 ? 1 : 0
    };
  }

  private sameCounts(
    left: HuaweiSpaceHistorySnapshotCounts,
    right: HuaweiSpaceHistorySnapshotCounts
  ): boolean {
    return left.visits === right.visits && left.tombstones === right.tombstones &&
      left.deleteRanges === right.deleteRanges && left.clearBefore === right.clearBefore &&
      left.retentionFrontier === right.retentionFrontier;
  }

  private sameRecords(
    left: HuaweiSpaceHistorySnapshotRecord[],
    right: HuaweiSpaceHistorySnapshotRecord[]
  ): boolean {
    return JSON.stringify(left) === JSON.stringify(right);
  }

  private async sameRecordsCooperatively(
    left: HuaweiSpaceHistorySnapshotRecord[],
    right: HuaweiSpaceHistorySnapshotRecord[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<boolean> {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index += 1) {
      if (JSON.stringify(left[index]) !== JSON.stringify(right[index])) {
        return false;
      }
      await throttle.afterBatchItem(index + 1);
    }
    return true;
  }

  private isCanonicalBucket(bucketIndex: number, records: HuaweiSpaceHistorySnapshotRecord[]): boolean {
    let previous = '';
    for (let index = 0; index < records.length; index += 1) {
      const key = this.buildSnapshotRecordKey(records[index]);
      if (this.resolveBucketIndex(key) !== bucketIndex || (index > 0 && key.localeCompare(previous) <= 0)) {
        return false;
      }
      previous = key;
    }
    return true;
  }

  private async isCanonicalBucketCooperatively(
    bucketIndex: number,
    records: HuaweiSpaceHistorySnapshotRecord[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<boolean> {
    let previous = '';
    for (let index = 0; index < records.length; index += 1) {
      const key = this.buildSnapshotRecordKey(records[index]);
      if (this.resolveBucketIndex(key) !== bucketIndex || (index > 0 && key.localeCompare(previous) <= 0)) {
        return false;
      }
      previous = key;
      await throttle.afterBatchItem(index + 1);
    }
    return true;
  }

  private resolveMaxKnownGeneration(rows: HuaweiSpaceHistoryRow[]): number {
    let maxGeneration = 0;
    rows.forEach((row: HuaweiSpaceHistoryRow): void => {
      if (row.recordKind !== 'snapshot_head') {
        return;
      }
      const value = this.parseHead(row);
      if (value.deviceId === this.deviceId) {
        maxGeneration = Math.max(maxGeneration, value.generation);
      }
    });
    return maxGeneration;
  }

  private async resolveMaxKnownGenerationCooperatively(
    rows: HuaweiSpaceHistoryRow[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<number> {
    let maxGeneration = 0;
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      if (row.recordKind === 'snapshot_head') {
        const value = this.parseHead(row);
        if (value.deviceId === this.deviceId) {
          maxGeneration = Math.max(maxGeneration, value.generation);
        }
      }
      await throttle.afterBatchItem(index + 1);
    }
    return maxGeneration;
  }

  private requireCompactHeader(
    formatVersion: number,
    deviceId: string,
    bucketIndex: number,
    bucketSlot: number
  ): void {
    if (formatVersion !== HUAWEI_SPACE_HISTORY_SNAPSHOT_FORMAT_VERSION ||
      typeof deviceId !== 'string' || deviceId.trim().length <= 0) {
      throw new Error('Huawei History compact row identity is invalid.');
    }
    this.requireInteger(bucketIndex, 0, HUAWEI_SPACE_HISTORY_BUCKET_COUNT - 1, 'bucketIndex');
    this.requireInteger(bucketSlot, 0, HUAWEI_SPACE_HISTORY_SLOT_COUNT - 1, 'bucketSlot');
  }

  private buildSnapshotRecordKey(record: HuaweiSpaceHistorySnapshotRecord): string {
    return `${record.kind}:${record.logicalId}`;
  }

  private resolveBucketIndex(key: string): number {
    return Number.parseInt(this.sha256Hex(key).slice(0, 8), 16) % HUAWEI_SPACE_HISTORY_BUCKET_COUNT;
  }

  private buildHeadLogicalId(deviceId: string, headSlot: number): string {
    return `${deviceId}:head:${headSlot}`;
  }

  private buildBucketLogicalId(deviceId: string, bucketIndex: number, bucketSlot: number): string {
    return `${deviceId}:bucket:${bucketIndex}:${bucketSlot}`;
  }

  private buildChunkLogicalPrefix(deviceId: string, bucketIndex: number, bucketSlot: number): string {
    return `${deviceId}:chunk:${bucketIndex}:${bucketSlot}:`;
  }

  private buildChunkLogicalId(
    deviceId: string,
    bucketIndex: number,
    bucketSlot: number,
    segmentIndex: number
  ): string {
    return `${this.buildChunkLogicalPrefix(deviceId, bucketIndex, bucketSlot)}${segmentIndex}`;
  }

  private buildRetentionFrontierLogicalId(value: HistorySyncRetentionFrontier): string {
    return `${value.cutoffAt}:${value.boundaryVisitedAt}:${value.boundaryVisitId}`;
  }

  private buildLegacyRowId(
    recordKind: HuaweiSpaceHistoryRecordKind,
    logicalId: string,
    data: string
  ): string {
    return `h1:${this.sha256Hex(`${this.uid}\n${recordKind}\n${logicalId}\n${data}`)}`;
  }

  private buildCompactRowId(recordKind: HuaweiSpaceHistoryRecordKind, logicalId: string): string {
    return `h2:${this.sha256Hex(`${this.uid}\n${recordKind}\n${logicalId}`)}`;
  }

  private isLegacyRecordKind(value: HuaweiSpaceHistoryRecordKind): boolean {
    return value === 'visit' || value === 'tombstone' || value === 'delete_range' ||
      value === 'clear_before' || value === 'retention_frontier';
  }

  private isHistoryTransition(value: string): boolean {
    return value === 'link' || value === 'typed' || value === 'auto_bookmark' || value === 'auto_subframe' ||
      value === 'manual_subframe' || value === 'generated' || value === 'auto_toplevel' ||
      value === 'form_submit' || value === 'reload' || value === 'keyword' || value === 'keyword_generated' ||
      value === 'unknown';
  }

  private requireHash(value: string, field: string): string {
    const normalized = typeof value === 'string' ? value.trim().toLowerCase() : '';
    if (!/^[0-9a-f]{64}$/.test(normalized)) {
      throw new Error(`Huawei History ${field} is invalid.`);
    }
    return normalized;
  }

  private requireInteger(value: number, min: number, max: number, field: string): number {
    if (!Number.isSafeInteger(value) || value < min || value > max) {
      throw new Error(`Huawei History ${field} is invalid.`);
    }
    return value;
  }

  private requireTimestamp(value: number, field: string, allowZero: boolean = false): number {
    const normalized = Number(value);
    if (!Number.isSafeInteger(normalized) || normalized < 0 || (!allowZero && normalized <= 0)) {
      throw new Error(`Huawei History ${field} is invalid.`);
    }
    return normalized;
  }

  private assertRowSize(value: string): void {
    if (this.byteLength(value) > HUAWEI_SPACE_HISTORY_ROW_MAX_BYTES) {
      throw new Error('Huawei History row exceeds the 12 KiB safety limit.');
    }
  }

  private byteLength(value: string): number {
    return this.encoder.encodeInto(value).byteLength;
  }

  private async sha256HistoryStateCooperatively(
    state: HuaweiSpaceHistorySyncState,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: this.encoder.encodeInto('{"visits":[') });
    for (let index = 0; index < state.visits.length; index += 1) {
      const prefix = index > 0 ? ',' : '';
      digest.updateSync({ data: this.encoder.encodeInto(`${prefix}${JSON.stringify(state.visits[index])}`) });
      await throttle.afterBatchItem(index + 1);
    }
    digest.updateSync({ data: this.encoder.encodeInto('],"tombstones":[') });
    for (let index = 0; index < state.tombstones.length; index += 1) {
      const prefix = index > 0 ? ',' : '';
      digest.updateSync({ data: this.encoder.encodeInto(`${prefix}${JSON.stringify(state.tombstones[index])}`) });
      await throttle.afterBatchItem(index + 1);
    }
    digest.updateSync({ data: this.encoder.encodeInto('],"deleteRanges":[') });
    for (let index = 0; index < state.deleteRanges.length; index += 1) {
      const prefix = index > 0 ? ',' : '';
      digest.updateSync({ data: this.encoder.encodeInto(`${prefix}${JSON.stringify(state.deleteRanges[index])}`) });
      await throttle.afterBatchItem(index + 1);
    }
    digest.updateSync({
      data: this.encoder.encodeInto(
        `],"clearBefore":${JSON.stringify(state.clearBefore)},` +
        `"retentionFrontier":${JSON.stringify(state.retentionFrontier)}}`
      )
    });
    const result = digest.digestSync().data;
    let output = '';
    for (let index = 0; index < result.length; index += 1) {
      output += result[index].toString(16).padStart(2, '0');
    }
    return output;
  }

  private sha256Hex(value: string): string {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: this.encoder.encodeInto(value) });
    const result = digest.digestSync().data;
    let output = '';
    for (let index = 0; index < result.length; index += 1) {
      output += result[index].toString(16).padStart(2, '0');
    }
    return output;
  }
}
