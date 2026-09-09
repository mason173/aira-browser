import { describe, expect, it } from '@ohos/hypium';
import {
  AiraSyncRemoteHead,
  AiraSyncRemoteKind
} from '../main/ets/common/models/AiraSyncModels';
import { AiraBookmarkSyncIntent } from '../main/ets/services/sync/AiraBookmarkSyncDecisionService';
import {
  AiraBookmarkIdentityNoOpProbe,
  AiraBookmarkIdentityNoOpService
} from '../main/ets/services/sync/AiraBookmarkIdentityNoOpService';

function createProbe(
  remoteKind: AiraSyncRemoteKind = 'huawei_space',
  intent: AiraBookmarkSyncIntent = 'merge',
  conservativeMerge: boolean = false,
  pendingBookmarkSyncAt: number = 0,
  baselineCommitId: string = 'cmt_device_a',
  baselineFolderCount: number = 3,
  baselineItemCount: number = 12,
  hasBaselineSnapshot: boolean = true
): AiraBookmarkIdentityNoOpProbe {
  return {
    remoteKind: remoteKind,
    intent: intent,
    conservativeMerge: conservativeMerge,
    pendingBookmarkSyncAt: pendingBookmarkSyncAt,
    baselineCommitId: baselineCommitId,
    baselineFolderCount: baselineFolderCount,
    baselineItemCount: baselineItemCount,
    hasBaselineSnapshot: hasBaselineSnapshot
  };
}

function createHead(
  commitId: string | null = 'cmt_device_a',
  bookmarkFolders: number = 3,
  bookmarkItems: number = 12,
  hasBookmarkSummary: boolean = true
): AiraSyncRemoteHead {
  return {
    commitId: commitId,
    updatedAt: 1,
    bookmarkFolders: bookmarkFolders,
    bookmarkItems: bookmarkItems,
    hasBookmarkSummary: hasBookmarkSummary
  };
}

export default function airaBookmarkIdentityNoOpServiceTest(): void {
  describe('AiraBookmarkIdentityNoOpService', () => {
    const service = new AiraBookmarkIdentityNoOpService();

    it('accepts an ordinary Huawei no-op with a confirmed matching Head', 0, () => {
      const probe = createProbe();
      expect(service.isEligible(probe)).assertTrue();
      expect(service.matchesConfirmedHead(probe, createHead())).assertTrue();
    });

    it('accepts a multi-head identity match without a single-head summary', 0, () => {
      const probe = createProbe(
        'huawei_space',
        'merge',
        false,
        0,
        'heads:cmt_a,cmt_b',
        3,
        12,
        true
      );
      expect(service.matchesConfirmedHead(
        probe,
        createHead('heads:cmt_a,cmt_b', 0, 0, false)
      )).assertTrue();
    });

    it('rejects pending local writes, provider switches, and other providers', 0, () => {
      expect(service.isEligible(createProbe('huawei_space', 'merge', false, 12))).assertFalse();
      expect(service.isEligible(createProbe('huawei_space', 'merge', true))).assertFalse();
      expect(service.isEligible(createProbe('huawei_space', 'local-over-cloud'))).assertFalse();
      expect(service.isEligible(createProbe('webdav'))).assertFalse();
      expect(service.isEligible(createProbe(
        'huawei_space',
        'merge',
        false,
        0,
        'cmt_device_a',
        3,
        12,
        false
      ))).assertFalse();
      expect(service.isEligible(createProbe(
        'huawei_space',
        'merge',
        false,
        0,
        '',
        3,
        12,
        true
      ))).assertFalse();
    });

    it('falls through when the confirmed Head identity or counts differ', 0, () => {
      const probe = createProbe();
      expect(service.matchesConfirmedHead(probe, createHead('cmt_other'))).assertFalse();
      expect(service.matchesConfirmedHead(probe, createHead(null))).assertFalse();
      expect(service.matchesConfirmedHead(probe, createHead('cmt_device_a', 3, 11))).assertFalse();
      expect(service.matchesConfirmedHead(probe, createHead('cmt_device_a', 2, 12))).assertFalse();
    });
  });
}
