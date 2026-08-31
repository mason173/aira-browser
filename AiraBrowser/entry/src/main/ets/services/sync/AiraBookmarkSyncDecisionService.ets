import { AiraSyncSnapshot } from '../../common/models/AiraSyncModels';
import {
  AiraBookmarkMergeResult,
  AiraBookmarkMergeService
} from './AiraBookmarkMergeService';
import { AiraSyncWorkThrottleService } from './AiraSyncWorkThrottleService';

export type AiraBookmarkSyncIntent = 'cloud-over-local' | 'local-over-cloud' | 'merge';

interface AiraBookmarkSyncDecisionInput {
  intent: AiraBookmarkSyncIntent;
  baseline: AiraSyncSnapshot | null;
  local: AiraSyncSnapshot;
  remote: AiraSyncSnapshot | null;
}

export class AiraBookmarkSyncDecisionService {
  private mergeService: AiraBookmarkMergeService = new AiraBookmarkMergeService();

  private decide(input: AiraBookmarkSyncDecisionInput): AiraBookmarkMergeResult {
    if (input.intent === 'cloud-over-local') {
      if (input.remote === null) {
        throw new Error('云端没有可用于覆盖本机的书签快照。');
      }
      return {
        snapshot: input.remote,
        hasConflicts: false,
        conflictCount: 0,
        localChangeCount: 0,
        remoteChangeCount: 0,
        localApplyRequired: !this.mergeService.sameLocalMaterializationContent(input.local, input.remote),
        remoteWriteRequired: false,
        conflictDetails: [],
        summary: '已选择使用云端完整书签快照覆盖本机。'
      };
    }
    if (input.intent === 'local-over-cloud') {
      return {
        snapshot: input.local,
        hasConflicts: false,
        conflictCount: 0,
        localChangeCount: 0,
        remoteChangeCount: 0,
        localApplyRequired: false,
        remoteWriteRequired: input.remote === null ||
          !this.mergeService.sameSnapshotContent(input.remote, input.local),
        conflictDetails: [],
        summary: '已选择使用本机完整书签快照覆盖云端。'
      };
    }
    if (input.intent === 'merge') {
      return this.mergeService.merge(
        input.baseline,
        input.local,
        input.remote,
        input.local.meta.deviceId
      );
    }
    throw new Error(`尚未实现的书签同步意图：${input.intent}`);
  }

  async decideCooperatively(
    input: AiraBookmarkSyncDecisionInput,
    throttle: AiraSyncWorkThrottleService
  ): Promise<AiraBookmarkMergeResult> {
    if (input.intent !== 'merge') {
      await throttle.afterStage();
      return this.decide(input);
    }
    return this.mergeService.mergeCooperatively(
      input.baseline,
      input.local,
      input.remote,
      throttle,
      input.local.meta.deviceId
    );
  }
}
