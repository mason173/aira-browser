import { describe, expect, it } from '@ohos/hypium';
import { HistorySyncMergeService } from '../main/ets/services/sync/HistorySyncMergeService';
import {
  hasHuaweiHistoryLocalWork,
  resolveHuaweiHistoryRemoteReadPlan,
  shouldLoadUnchangedHuaweiHistoryReplica,
  shouldSkipUnchangedHuaweiHistoryRemote,
  shouldUseCachedHuaweiHistoryRemote
} from '../main/ets/services/sync/HuaweiSpaceHistorySyncRunner';
import {
  HISTORY_STARTUP_QUIET_MS,
  resolveHistoryStartupQuietDelayMs
} from '../main/ets/core/sync/SyncExperienceAutomaticRuntime';
import { AIRA_SYNC_UI_YIELD_MS } from '../main/ets/services/sync/AiraSyncWorkThrottleService';
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

    it('skips unchanged Huawei History when local enrollment is empty and heads match', 0, () => {
      expect(shouldSkipUnchangedHuaweiHistoryRemote(0, false, 'abc', 'abc')).assertTrue();
      expect(shouldSkipUnchangedHuaweiHistoryRemote(1, false, 'abc', 'abc')).assertFalse();
      expect(shouldSkipUnchangedHuaweiHistoryRemote(0, true, 'abc', 'abc')).assertFalse();
      expect(shouldSkipUnchangedHuaweiHistoryRemote(0, false, '', 'abc')).assertFalse();
      expect(shouldSkipUnchangedHuaweiHistoryRemote(0, false, 'abc', 'def')).assertFalse();
    });

    it('reuses the local replica when heads match and only local mutations remain', 0, () => {
      expect(shouldLoadUnchangedHuaweiHistoryReplica(0, true, 'abc', 'abc')).assertTrue();
      expect(shouldLoadUnchangedHuaweiHistoryReplica(1, false, 'abc', 'abc')).assertTrue();
      expect(shouldLoadUnchangedHuaweiHistoryReplica(0, false, 'abc', 'abc')).assertFalse();
      expect(shouldLoadUnchangedHuaweiHistoryReplica(0, true, 'abc', 'def')).assertFalse();
      expect(shouldLoadUnchangedHuaweiHistoryReplica(0, true, '', 'abc')).assertFalse();
    });

    it('does not treat stale tombstones as local work after a Head mismatch', 0, () => {
      expect(hasHuaweiHistoryLocalWork(0, false, true, false)).assertFalse();
      expect(hasHuaweiHistoryLocalWork(0, false, true, true)).assertTrue();
      expect(hasHuaweiHistoryLocalWork(0, true, false, false)).assertTrue();
      expect(hasHuaweiHistoryLocalWork(1, false, false, false)).assertTrue();
    });

    it('skips History when the local replica already matches a newer Head', 0, () => {
      expect(resolveHuaweiHistoryRemoteReadPlan(false, false, 'new-head', true)).assertEqual('skip');
      expect(resolveHuaweiHistoryRemoteReadPlan(false, true, 'abc', false)).assertEqual('skip');
    });

    it('reads the local replica for local mutations even when persisted Head is stale', 0, () => {
      expect(resolveHuaweiHistoryRemoteReadPlan(true, false, 'new-head', true)).assertEqual('replica');
      expect(resolveHuaweiHistoryRemoteReadPlan(true, true, 'abc', true)).assertEqual('replica');
      expect(resolveHuaweiHistoryRemoteReadPlan(true, true, 'abc', false)).assertEqual('replica');
    });

    it('falls back to cloud Blocks only when the local replica cannot satisfy the Head', 0, () => {
      expect(resolveHuaweiHistoryRemoteReadPlan(true, false, 'new-head', false)).assertEqual('cloud');
      expect(resolveHuaweiHistoryRemoteReadPlan(false, false, 'new-head', false)).assertEqual('cloud');
      expect(resolveHuaweiHistoryRemoteReadPlan(false, false, '', false)).assertEqual('cloud');
    });

    it('defers account and foreground History until the startup quiet window elapses', 0, () => {
      expect(HISTORY_STARTUP_QUIET_MS).assertEqual(30000);
      expect(resolveHistoryStartupQuietDelayMs('account', 5000, 40000, 10000)).assertEqual(30000);
      expect(resolveHistoryStartupQuietDelayMs('foreground', 5000, 12000, 10000)).assertEqual(5000);
      expect(resolveHistoryStartupQuietDelayMs('local_change', 5000, 40000, 10000)).assertEqual(5000);
    });

    it('yields a frame during cooperative sync work', 0, () => {
      expect(AIRA_SYNC_UI_YIELD_MS).assertEqual(16);
    });

    it('routes snapshot heads and blocks onto isolated H2 tables', 0, () => {
      expect(huaweiHistoryPhysicalTable('snapshot_head')).assertEqual('head');
      expect(huaweiHistoryPhysicalTable('snapshot_bucket')).assertEqual('block');
      expect(huaweiHistoryPhysicalTable('snapshot_chunk')).assertEqual('block');
      expect(huaweiHistoryPhysicalTable('visit')).assertEqual('legacy');
    });
  });
}
