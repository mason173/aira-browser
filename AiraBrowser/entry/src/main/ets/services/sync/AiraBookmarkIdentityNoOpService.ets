import {
  AiraSyncRemoteHead,
  AiraSyncRemoteKind
} from '../../common/models/AiraSyncModels';
import { AiraBookmarkSyncIntent } from './AiraBookmarkSyncDecisionService';

export interface AiraBookmarkIdentityNoOpProbe {
  remoteKind: AiraSyncRemoteKind;
  intent: AiraBookmarkSyncIntent;
  conservativeMerge: boolean;
  pendingBookmarkSyncAt: number;
  baselineCommitId: string;
  baselineFolderCount: number;
  baselineItemCount: number;
  hasBaselineSnapshot: boolean;
  baselineHasExpiredTombstone: boolean;
}

export class AiraBookmarkIdentityNoOpService {
  // A confirmed Head whose commit equals the baseline commit proves the remote still holds
  // exactly the content this device last synced. Combined with no recorded local mutation,
  // local == baseline == remote, so the full snapshot read and merge can be skipped.
  // Aira Cloud and Huawei Space both return a content-addressed commit from `/head`, so the
  // same proof holds for either; that read is a tiny summary, not the full snapshot.
  //
  // The proof covers live content only, so a baseline that still carries a tombstone older than
  // the retention window must not short-circuit: retiring that tombstone is a maintenance write
  // the full path performs, and skipping it would pin the frontier (and the accumulated history)
  // forever. When the Head equals the baseline commit, the baseline tombstones are exactly the
  // remote ones, so inspecting the baseline is sufficient.
  isEligible(probe: AiraBookmarkIdentityNoOpProbe): boolean {
    return (probe.remoteKind === 'huawei_space' || probe.remoteKind === 'aira_cloud') &&
      probe.intent === 'merge' &&
      !probe.conservativeMerge &&
      probe.pendingBookmarkSyncAt <= 0 &&
      probe.hasBaselineSnapshot &&
      !probe.baselineHasExpiredTombstone &&
      probe.baselineCommitId.trim().length > 0;
  }

  matchesConfirmedHead(probe: AiraBookmarkIdentityNoOpProbe, head: AiraSyncRemoteHead): boolean {
    const commitId = head.commitId?.trim() ?? '';
    return commitId.length > 0 && commitId === probe.baselineCommitId.trim();
  }
}
