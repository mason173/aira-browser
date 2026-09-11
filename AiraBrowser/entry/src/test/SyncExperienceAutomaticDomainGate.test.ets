import { describe, expect, it } from '@ohos/hypium';
import {
  SyncExperienceAutomaticDomainSelection,
  hasAutomaticDomainRemainder,
  resolveSyncExperienceAutomaticDomainSelection,
  splitAutomaticDomainTurn
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

    it('runs one automatic domain per turn and defers the rest', 0, () => {
      const turn = splitAutomaticDomainTurn({
        runBookmarks: true,
        runPersonalization: true,
        runHistory: true
      });
      expect(turn.current.runBookmarks).assertTrue();
      expect(turn.current.runPersonalization).assertFalse();
      expect(turn.current.runHistory).assertFalse();
      expect(turn.remainder.runBookmarks).assertFalse();
      expect(turn.remainder.runPersonalization).assertTrue();
      expect(turn.remainder.runHistory).assertTrue();
      expect(hasAutomaticDomainRemainder(turn.remainder)).assertTrue();
    });

    it('defers history after personalization when bookmarks are not requested', 0, () => {
      const turn = splitAutomaticDomainTurn({
        runBookmarks: false,
        runPersonalization: true,
        runHistory: true
      });
      expect(turn.current.runPersonalization).assertTrue();
      expect(turn.current.runHistory).assertFalse();
      expect(turn.remainder.runPersonalization).assertFalse();
      expect(turn.remainder.runHistory).assertTrue();
    });

    it('keeps a single-domain turn intact', 0, () => {
      const turn = splitAutomaticDomainTurn({
        runBookmarks: false,
        runPersonalization: false,
        runHistory: true
      });
      expect(turn.current.runHistory).assertTrue();
      expect(hasAutomaticDomainRemainder(turn.remainder)).assertFalse();
    });
  });
}
