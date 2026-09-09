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
}

export class AiraBookmarkIdentityNoOpService {
  isEligible(probe: AiraBookmarkIdentityNoOpProbe): boolean {
    return probe.remoteKind === 'huawei_space' &&
      probe.intent === 'merge' &&
      !probe.conservativeMerge &&
      probe.pendingBookmarkSyncAt <= 0 &&
      probe.hasBaselineSnapshot &&
      probe.baselineCommitId.trim().length > 0;
  }

  matchesConfirmedHead(probe: AiraBookmarkIdentityNoOpProbe, head: AiraSyncRemoteHead): boolean {
    const commitId = head.commitId?.trim() ?? '';
    if (commitId.length <= 0 || commitId !== probe.baselineCommitId.trim()) {
      return false;
    }
    if (!head.hasBookmarkSummary) {
      return true;
    }
    return head.bookmarkFolders === probe.baselineFolderCount &&
      head.bookmarkItems === probe.baselineItemCount;
  }
}
