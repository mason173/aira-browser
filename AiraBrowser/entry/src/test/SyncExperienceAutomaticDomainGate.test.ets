import { describe, expect, it } from '@ohos/hypium';
import {
  SyncExperienceAutomaticDomainSelection,
  resolveSyncExperienceAutomaticDomainSelection
} from '../main/ets/core/sync/SyncExperienceAutomaticRuntime';

export default function syncExperienceAutomaticDomainGateTest(): void {
  describe('SyncExperience automatic domain gate', () => {
    it('blocks only automatic bookmarks while V4 bootstrap is required', 0, () => {
      const selection: SyncExperienceAutomaticDomainSelection = resolveSyncExperienceAutomaticDomainSelection({
        runBookmarks: true,
        runPersonalization: true,
        runHistory: true
      }, false);

      expect(selection.runBookmarks).assertFalse();
      expect(selection.runPersonalization).assertTrue();
      expect(selection.runHistory).assertTrue();
    });

    it('keeps all requested domains when bootstrap allows bookmarks', 0, () => {
      const selection: SyncExperienceAutomaticDomainSelection = resolveSyncExperienceAutomaticDomainSelection({
        runBookmarks: true,
        runPersonalization: true,
        runHistory: true
      }, true);

      expect(selection.runBookmarks).assertTrue();
      expect(selection.runPersonalization).assertTrue();
      expect(selection.runHistory).assertTrue();
    });
  });
}
