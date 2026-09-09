import { describe, expect, it } from '@ohos/hypium';
import { HistorySyncMergeService } from '../main/ets/services/sync/HistorySyncMergeService';
import { shouldUseCachedHuaweiHistoryRemote } from
  '../main/ets/services/sync/HuaweiSpaceHistorySyncRunner';
import { huaweiHistoryPhysicalTable } from
  '../main/ets/data/sync/HuaweiSpaceHistorySnapshotCodec';

export default function huaweiSpaceHistoryCloudReadGateTest(): void {
  describe('Huawei history cached remote gate', () => {
    const mergeService = new HistorySyncMergeService();

    it('reuses the confirmed remote after the first ordinary cloud read', 0, () => {
      expect(shouldUseCachedHuaweiHistoryRemote(
        true,
        'uid-a',
        'uid-a',
        mergeService.emptyState()
      )).assertTrue();
    });

    it('still reads cloud for provider transitions, another account, or a cold cache', 0, () => {
      const cached = mergeService.emptyState();
      expect(shouldUseCachedHuaweiHistoryRemote(false, 'uid-a', 'uid-a', cached)).assertFalse();
      expect(shouldUseCachedHuaweiHistoryRemote(true, 'uid-a', 'uid-b', cached)).assertFalse();
      expect(shouldUseCachedHuaweiHistoryRemote(true, 'uid-a', 'uid-a', undefined)).assertFalse();
    });

    it('routes snapshot heads and blocks onto isolated H2 tables', 0, () => {
      expect(huaweiHistoryPhysicalTable('snapshot_head')).assertEqual('head');
      expect(huaweiHistoryPhysicalTable('snapshot_bucket')).assertEqual('block');
      expect(huaweiHistoryPhysicalTable('snapshot_chunk')).assertEqual('block');
      expect(huaweiHistoryPhysicalTable('visit')).assertEqual('legacy');
    });
  });
}
