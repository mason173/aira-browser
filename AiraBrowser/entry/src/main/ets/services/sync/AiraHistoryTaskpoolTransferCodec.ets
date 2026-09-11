import {
  HuaweiSpaceHistorySyncState
} from '../../common/models/HistorySyncModels';
import {
  HuaweiSpaceHistoryProjection,
  HuaweiSpaceHistoryRecordKind,
  HuaweiSpaceHistoryRow
} from '../../data/sync/HuaweiSpaceHistorySnapshotCodec';
import { util } from '@kit.ArkTS';

export interface AiraHistoryRemoteWriteProjection {
  rowsToUpsert: HuaweiSpaceHistoryRow[];
  rowIdsToDeleteBeforePublish: string[];
  legacyRowIdsToDeleteAfterConfirmation: string[];
  targetHeadRowId: string;
  targetDeviceId: string;
  targetGeneration: number;
  targetStateChecksum: string;
}

function writeU32(target: Uint8Array, offset: number, value: number): void {
  target[offset] = (value >>> 24) & 0xff;
  target[offset + 1] = (value >>> 16) & 0xff;
  target[offset + 2] = (value >>> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}

function readU32(source: Uint8Array, offset: number): number {
  return ((source[offset] << 24) | (source[offset + 1] << 16) |
    (source[offset + 2] << 8) | source[offset + 3]) >>> 0;
}

function writeU64(target: Uint8Array, offset: number, value: number): void {
  const safe = Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  writeU32(target, offset, Math.floor(safe / 4294967296));
  writeU32(target, offset + 4, safe % 4294967296);
}

function readU64(source: Uint8Array, offset: number): number {
  return readU32(source, offset) * 4294967296 + readU32(source, offset + 4);
}

export class AiraHistoryTaskpoolTransferCodec {
  static encodeRows(rows: HuaweiSpaceHistoryRow[]): ArrayBuffer {
    const encoder = util.TextEncoder.create('utf-8');
    const rowIds: Uint8Array[] = [];
    const kinds: Uint8Array[] = [];
    const logicalIds: Uint8Array[] = [];
    const payloads: Uint8Array[] = [];
    let packedByteLength = 4;
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      const rowId = encoder.encodeInto(row.rowId);
      const recordKind = encoder.encodeInto(row.recordKind);
      const logicalId = encoder.encodeInto(row.logicalId);
      const data = encoder.encodeInto(row.data);
      rowIds.push(rowId);
      kinds.push(recordKind);
      logicalIds.push(logicalId);
      payloads.push(data);
      packedByteLength += 24 + rowId.byteLength + recordKind.byteLength +
        logicalId.byteLength + data.byteLength;
    }
    const packed = new ArrayBuffer(packedByteLength);
    const target = new Uint8Array(packed);
    writeU32(target, 0, rows.length);
    let offset = 4;
    for (let index = 0; index < rows.length; index += 1) {
      const rowId = rowIds[index];
      const recordKind = kinds[index];
      const logicalId = logicalIds[index];
      const data = payloads[index];
      writeU32(target, offset, rowId.byteLength);
      offset += 4;
      target.set(rowId, offset);
      offset += rowId.byteLength;
      writeU32(target, offset, recordKind.byteLength);
      offset += 4;
      target.set(recordKind, offset);
      offset += recordKind.byteLength;
      writeU32(target, offset, logicalId.byteLength);
      offset += 4;
      target.set(logicalId, offset);
      offset += logicalId.byteLength;
      writeU32(target, offset, data.byteLength);
      offset += 4;
      target.set(data, offset);
      offset += data.byteLength;
      writeU64(target, offset, rows[index].updatedAt);
      offset += 8;
    }
    return packed;
  }

  static decodeRows(rowBuffer: ArrayBuffer): HuaweiSpaceHistoryRow[] {
    const decoder = util.TextDecoder.create('utf-8');
    const bytes = new Uint8Array(rowBuffer);
    if (bytes.byteLength < 4) {
      throw new Error('Huawei History TaskPool row payload is truncated.');
    }
    const rowCount = readU32(bytes, 0);
    const rows: HuaweiSpaceHistoryRow[] = [];
    let offset = 4;
    const readString = (): string => {
      if (offset + 4 > bytes.byteLength) {
        throw new Error('Huawei History TaskPool row payload is truncated.');
      }
      const length = readU32(bytes, offset);
      offset += 4;
      if (length < 0 || offset + length > bytes.byteLength) {
        throw new Error('Huawei History TaskPool row payload length is invalid.');
      }
      const value = decoder.decodeToString(bytes.subarray(offset, offset + length));
      offset += length;
      return value;
    };
    for (let index = 0; index < rowCount; index += 1) {
      const rowId = readString();
      const recordKind = readString();
      const logicalId = readString();
      const data = readString();
      if (offset + 8 > bytes.byteLength) {
        throw new Error('Huawei History TaskPool row payload is truncated.');
      }
      const updatedAt = readU64(bytes, offset);
      offset += 8;
      rows.push({
        rowId: rowId,
        recordKind: recordKind as HuaweiSpaceHistoryRecordKind,
        logicalId: logicalId,
        data: data,
        updatedAt: updatedAt
      });
    }
    return rows;
  }

  static encodeState(state: HuaweiSpaceHistorySyncState): ArrayBuffer {
    const encoder = util.TextEncoder.create('utf-8');
    const bytes = encoder.encodeInto(JSON.stringify(state));
    const packed = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(packed).set(bytes);
    return packed;
  }

  static decodeState(stateBuffer: ArrayBuffer): HuaweiSpaceHistorySyncState {
    const decoder = util.TextDecoder.create('utf-8');
    const parsed = JSON.parse(
      decoder.decodeToString(new Uint8Array(stateBuffer))
    ) as HuaweiSpaceHistorySyncState;
    if (!Array.isArray(parsed.visits) || !Array.isArray(parsed.tombstones) ||
      !Array.isArray(parsed.deleteRanges)) {
      throw new Error('Huawei History TaskPool state is invalid.');
    }
    return parsed;
  }

  static copyBuffer(buffer: ArrayBuffer): ArrayBuffer {
    const copy = new ArrayBuffer(buffer.byteLength);
    new Uint8Array(copy).set(new Uint8Array(buffer));
    return copy;
  }

  static leanProjection(projection: HuaweiSpaceHistoryProjection): AiraHistoryRemoteWriteProjection {
    return {
      rowsToUpsert: projection.rowsToUpsert,
      rowIdsToDeleteBeforePublish: projection.rowIdsToDeleteBeforePublish,
      legacyRowIdsToDeleteAfterConfirmation: projection.legacyRowIdsToDeleteAfterConfirmation,
      targetHeadRowId: projection.targetHeadRowId,
      targetDeviceId: projection.targetDeviceId,
      targetGeneration: projection.targetGeneration,
      targetStateChecksum: projection.targetStateChecksum
    };
  }
}
