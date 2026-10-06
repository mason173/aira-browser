import { describe, expect, it } from '@ohos/hypium';
import { BrowserToolbarLayoutSettings } from '../main/ets/common/models/BrowserModels';
import {
  BrowserSplitToolbarSlotDefinition,
  hasSplitToolbarCustomizations,
  replaceSplitToolbarInteraction,
  resetAllSplitToolbarSlots,
  resetSplitToolbarSlot,
  resolveSplitToolbarLongPressActionId,
  resolveSplitToolbarTapActionId,
  splitToolbarSlotsForScene
} from '../main/ets/core/browser/BrowserSplitToolbarCustomizationPolicy';

const KNOWN_ACTION_IDS: string[] = [
  'webBack',
  'webForward',
  'bottomChromeMenu',
  'webReload',
  'openTabs',
  'newTab',
  'openBookmarks',
  'history',
  'home',
  'downloads',
  'settings'
];

function isKnownAction(actionId: string): boolean {
  return KNOWN_ACTION_IDS.includes(actionId);
}

function sampleSettings(): BrowserToolbarLayoutSettings {
  return {
    primaryActionIds: ['downloads', 'settings', 'home', 'openBookmarks', 'history'],
    secondaryActionIds: [],
    leadingSlotActionId: 'webReload',
    menuSlotLongPressActionId: 'history',
    updatedAt: 5
  };
}

export default function browserSplitToolbarCustomizationPolicyTest(): void {
  describe('BrowserSplitToolbarCustomizationPolicy', () => {
    it('keeps the home and web bars on their own default buttons', 0, () => {
      const settings = sampleSettings();
      const home = splitToolbarSlotsForScene('home').map((slot: BrowserSplitToolbarSlotDefinition): string => {
        return resolveSplitToolbarTapActionId(settings, slot.id, isKnownAction);
      });
      const web = splitToolbarSlotsForScene('web').map((slot: BrowserSplitToolbarSlotDefinition): string => {
        return resolveSplitToolbarTapActionId(settings, slot.id, isKnownAction);
      });
      expect(home.join(',')).assertEqual('openBookmarks,history,openTabs,bottomChromeMenu');
      expect(web.join(',')).assertEqual('webBack,webForward,home,openTabs,bottomChromeMenu');
      expect(hasSplitToolbarCustomizations(settings)).assertFalse();
    });

    it('replaces a free tap and refuses a duplicate or a locked tap', 0, () => {
      const settings = sampleSettings();
      const replaced = replaceSplitToolbarInteraction(
        settings, 'homeLeading', 'tap', 'downloads', isKnownAction
      );
      expect(resolveSplitToolbarTapActionId(replaced, 'homeLeading', isKnownAction)).assertEqual('downloads');
      expect(replaced.leadingSlotActionId).assertEqual('webReload');

      const duplicate = replaceSplitToolbarInteraction(
        replaced, 'homeSecondary', 'tap', 'downloads', isKnownAction
      );
      expect(resolveSplitToolbarTapActionId(duplicate, 'homeSecondary', isKnownAction)).assertEqual('history');

      // Back, forward and menu taps are now replaceable, like home. Only the tabs tap stays fixed,
      // because the count badge lives on that button.
      const replacedBack = replaceSplitToolbarInteraction(
        settings, 'webBack', 'tap', 'downloads', isKnownAction
      );
      expect(resolveSplitToolbarTapActionId(replacedBack, 'webBack', isKnownAction)).assertEqual('downloads');
      const replacedMenu = replaceSplitToolbarInteraction(
        settings, 'webMenu', 'tap', 'webReload', isKnownAction
      );
      expect(resolveSplitToolbarTapActionId(replacedMenu, 'webMenu', isKnownAction)).assertEqual('webReload');

      const lockedTabs = replaceSplitToolbarInteraction(
        settings, 'webTabs', 'tap', 'downloads', isKnownAction
      );
      expect(resolveSplitToolbarTapActionId(lockedTabs, 'webTabs', isKnownAction)).assertEqual('openTabs');
      const lockedHomeTabs = replaceSplitToolbarInteraction(
        settings, 'homeTabs', 'tap', 'downloads', isKnownAction
      );
      expect(resolveSplitToolbarTapActionId(lockedHomeTabs, 'homeTabs', isKnownAction)).assertEqual('openTabs');

      // A tap another slot already shows is refused, locked or not.
      expect(resolveSplitToolbarTapActionId(
        replaceSplitToolbarInteraction(settings, 'webHome', 'tap', 'webBack', isKnownAction),
        'webHome',
        isKnownAction
      )).assertEqual('home');
    });

    it('keeps long press off the tap lock and resets only the split bar', 0, () => {
      const settings = sampleSettings();
      const pressed = replaceSplitToolbarInteraction(
        settings, 'webBack', 'longPress', 'history', isKnownAction
      );
      expect(resolveSplitToolbarLongPressActionId(pressed, 'webBack', isKnownAction)).assertEqual('history');
      expect(hasSplitToolbarCustomizations(pressed)).assertTrue();

      const slotReset = resetSplitToolbarSlot(pressed, 'webBack', isKnownAction);
      expect(resolveSplitToolbarLongPressActionId(slotReset, 'webBack', isKnownAction)).assertEqual('none');

      const customized = replaceSplitToolbarInteraction(
        pressed, 'homeLeading', 'tap', 'settings', isKnownAction
      );
      const reset = resetAllSplitToolbarSlots(customized);
      expect(hasSplitToolbarCustomizations(reset)).assertFalse();
      expect(reset.leadingSlotActionId).assertEqual('webReload');
      expect(reset.menuSlotLongPressActionId).assertEqual('history');
      expect(reset.updatedAt).assertEqual(5);
    });
  });
}
