import {
  HistorySyncDeleteRange,
  HistorySyncExactTombstone,
  HistorySyncRetentionFrontier,
  HistorySyncVisit,
  HuaweiSpaceHistorySyncState
} from '../../common/models/HistorySyncModels';
import {
  HuaweiSpaceHistoryProjection,
  HuaweiSpaceHistoryRow
} from '../../data/sync/HuaweiSpaceHistorySnapshotCodec';
import { util } from '@kit.ArkTS';

interface AiraHistoryStateMetadata {
  clearBefore: number;
  retentionFrontier: HistorySyncRetentionFrontier;
}

export interface AiraHistoryRemoteWriteProjection {
  rowsToUpsert: HuaweiSpaceHistoryRow[];
  rowIdsToDeleteBeforePublish: string[];
  legacyRowIdsToDeleteAfterConfirmation: string[];
  targetHeadRowId: string;
  targetDeviceId: string;
  targetGeneration: number;
  targetStateChecksum: string;
}

export class AiraHistoryTaskpoolTransferCodec {
  static decodeRows(rowBuffer: ArrayBuffer): HuaweiSpaceHistoryRow[] {
    const rowLengthBytes = 4;
    const decoder = util.TextDecoder.create('utf-8');
    const bytes = new Uint8Array(rowBuffer);
    const rows: HuaweiSpaceHistoryRow[] = [];
    let offset = 0;
    while (offset < bytes.byteLength) {
      if (offset + rowLengthBytes > bytes.byteLength) {
        throw new Error('Huawei History TaskPool row frame is truncated.');
      }
      const rowLength = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
      offset += rowLengthBytes;
      if (rowLength <= 0 || offset + rowLength > bytes.byteLength) {
        throw new Error('Huawei History TaskPool row frame length is invalid.');
      }
      rows.push(JSON.parse(
        decoder.decodeToString(bytes.subarray(offset, offset + rowLength))
      ) as HuaweiSpaceHistoryRow);
      offset += rowLength;
    }
    return rows;
  }

  static decodeState(stateBuffer: ArrayBuffer): HuaweiSpaceHistorySyncState {
    const frameHeaderBytes = 5;
    const metadataFrame = 0;
    const visitFrame = 1;
    const tombstoneFrame = 2;
    const deleteRangeFrame = 3;
    const decoder = util.TextDecoder.create('utf-8');
    const bytes = new Uint8Array(stateBuffer);
    const visits: HistorySyncVisit[] = [];
    const tombstones: HistorySyncExactTombstone[] = [];
    const deleteRanges: HistorySyncDeleteRange[] = [];
    let metadata: AiraHistoryStateMetadata | undefined = undefined;
    let offset = 0;
    while (offset < bytes.byteLength) {
      if (offset + frameHeaderBytes > bytes.byteLength) {
        throw new Error('Huawei History TaskPool state frame is truncated.');
      }
      const kind = bytes[offset];
      const frameLength = (bytes[offset + 1] << 24) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 8) |
        bytes[offset + 4];
      offset += frameHeaderBytes;
      if (frameLength <= 0 || offset + frameLength > bytes.byteLength) {
        throw new Error('Huawei History TaskPool state frame length is invalid.');
      }
      const encoded = decoder.decodeToString(bytes.subarray(offset, offset + frameLength));
      offset += frameLength;
      if (kind === metadataFrame) {
        if (metadata !== undefined) {
          throw new Error('Huawei History TaskPool state metadata is duplicated.');
        }
        metadata = JSON.parse(encoded) as AiraHistoryStateMetadata;
      } else if (kind === visitFrame) {
        visits.push(JSON.parse(encoded) as HistorySyncVisit);
      } else if (kind === tombstoneFrame) {
        tombstones.push(JSON.parse(encoded) as HistorySyncExactTombstone);
      } else if (kind === deleteRangeFrame) {
        deleteRanges.push(JSON.parse(encoded) as HistorySyncDeleteRange);
      } else {
        throw new Error('Huawei History TaskPool state frame kind is invalid.');
      }
    }
    if (metadata === undefined) {
      throw new Error('Huawei History TaskPool state metadata is missing.');
    }
    return {
      visits,
      tombstones,
      deleteRanges,
      clearBefore: metadata.clearBefore,
      retentionFrontier: metadata.retentionFrontier
    };
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
