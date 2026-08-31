import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserTabletInterfaceModeTransitionOwner
} from '../main/ets/core/settings/BrowserTabletInterfaceModeTransitionOwner';

export default function browserTabletInterfaceModeTransitionOwnerTest(): void {
  describe('BrowserTabletInterfaceModeTransitionOwner', () => {
    it('only consumes a marker for its declared consumer', 0, () => {
      const owner = new BrowserTabletInterfaceModeTransitionOwner();
      owner.begin('touch', 'standalone_settings_route');

      expect(owner.consumeCommitted('touch', 'phone_native_settings_handoff')).assertFalse();
      expect(owner.consumeCommitted('touch', 'standalone_settings_route')).assertTrue();
      expect(owner.consumeCommitted('touch', 'standalone_settings_route')).assertFalse();
    });

    it('replaces an older pending marker with the newest mode and consumer', 0, () => {
      const owner = new BrowserTabletInterfaceModeTransitionOwner();
      owner.begin('desktop', 'phone_native_settings_handoff');
      owner.begin('touch', 'standalone_settings_route');

      expect(owner.consumeCommitted('desktop', 'phone_native_settings_handoff')).assertFalse();
      expect(owner.consumeCommitted('touch', 'standalone_settings_route')).assertTrue();
    });
  });
}
