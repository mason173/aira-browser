import { describe, expect, it } from '@ohos/hypium';
import {
  HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION,
  shouldRegisterHuaweiSpaceDistributedTables
} from '../main/ets/data/sync/HuaweiSpaceRdbStoreOwner';
import {
  AUTOMATIC_DRAIN_YIELD_MS,
  HUAWEI_SPACE_TRANSPORT_WARMUP_DELAY_MS,
  isHuaweiSpaceTransportWarmupBeforePeriodicFreshness
} from '../main/ets/core/sync/SyncExperienceAutomaticRuntime';

export default function huaweiSpaceTransportWarmupTest(): void {
  describe('Huawei Space transport warmup', () => {
    it('registers distributed tables only on a version bump or unregistered legacy rows', 0, () => {
      expect(shouldRegisterHuaweiSpaceDistributedTables(
        0,
        HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION,
        false
      )).assertTrue();
      expect(shouldRegisterHuaweiSpaceDistributedTables(
        HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION - 1,
        HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION,
        false
      )).assertTrue();
      expect(shouldRegisterHuaweiSpaceDistributedTables(
        HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION,
        HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION,
        true
      )).assertFalse();
      expect(shouldRegisterHuaweiSpaceDistributedTables(
        0,
        HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION,
        true
      )).assertTrue();
    });

    it('warms the Huawei store after first content and before the 30s automatic freshness timer', 0, () => {
      expect(isHuaweiSpaceTransportWarmupBeforePeriodicFreshness()).assertTrue();
      expect(HUAWEI_SPACE_TRANSPORT_WARMUP_DELAY_MS > 0).assertTrue();
      expect(AUTOMATIC_DRAIN_YIELD_MS > 0).assertTrue();
      expect(HUAWEI_SPACE_TRANSPORT_WARMUP_DELAY_MS < 30000).assertTrue();
    });
  });
}
