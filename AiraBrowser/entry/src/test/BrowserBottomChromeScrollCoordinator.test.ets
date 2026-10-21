import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserBottomChromeScrollCoordinator,
  BrowserBottomChromeScrollPresentation,
  BrowserBottomChromePresentationScrollInput,
  BrowserBottomChromeWebScrollInput
} from '../main/ets/core/browser/BrowserBottomChromeScrollCoordinator';
import { BrowserBottomToolbarScrollBehavior } from '../main/ets/common/models/BrowserModels';
import { HomeSearchPanelDetent } from '../main/ets/core/browser/HomeSearchPanelDetentViewModel';

function buildWebInput(
  scrollOffsetY: number,
  currentDetent: HomeSearchPanelDetent = 'peek',
  currentPresentation: BrowserBottomChromeScrollPresentation = 'resting',
  scrollBehavior: BrowserBottomToolbarScrollBehavior = 'compact'
): BrowserBottomChromeWebScrollInput {
  return {
    tabId: 'tab-1',
    scrollOffsetY: scrollOffsetY,
    webPageVisible: true,
    addressFocused: false,
    currentDetent: currentDetent,
    currentPresentation: currentPresentation,
    presentationChangeAllowed: true,
    showTabsSheet: false,
    scrollBehavior: scrollBehavior,
    webAppImmersiveMode: false,
    fullScreenModeEnabled: false
  };
}

function buildHomeInput(
  scrollOffsetY: number,
  currentDetent: HomeSearchPanelDetent = 'peek'
): BrowserBottomChromePresentationScrollInput {
  return {
    surfaceId: 'home-content',
    scrollOffsetY: scrollOffsetY,
    surfaceVisible: true,
    addressFocused: false,
    currentDetent: currentDetent,
    currentPresentation: 'resting',
    presentationChangeAllowed: true,
    showTabsSheet: false,
    scrollBehavior: 'compact'
  };
}

export default function browserBottomChromeScrollCoordinatorTest(): void {
  describe('BrowserBottomChromeScrollCoordinator', () => {
    it('keeps the manually hidden web panel hidden when the page is read on', 0, () => {
      const coordinator = new BrowserBottomChromeScrollCoordinator();
      // First sample for the tab only seeds the baseline.
      let decision = coordinator.handleWebScrollMove(buildWebInput(100), 1000);
      expect(decision.changed).assertFalse();
      decision = coordinator.handleWebScrollMove(buildWebInput(800), 1100);
      expect(decision.changed).assertFalse();
      decision = coordinator.handleWebScrollSettle(buildWebInput(800), 1200);
      expect(decision.changed).assertFalse();
      expect(decision.detent).assertEqual('peek');
      expect(decision.reason).assertEqual('none');
    });

    it('still restores the manually hidden web panel after a later upward gesture', 0, () => {
      const coordinator = new BrowserBottomChromeScrollCoordinator();
      coordinator.handleWebScrollMove(buildWebInput(100), 1000);
      coordinator.handleWebScrollMove(buildWebInput(800), 1100);
      coordinator.handleWebScrollSettle(buildWebInput(800), 1200);
      coordinator.handleWebScrollMove(buildWebInput(760), 2000);
      const decision = coordinator.handleWebScrollSettle(buildWebInput(760), 2100);
      expect(decision.detent).assertEqual('low');
      expect(decision.presentation).assertEqual('resting');
      expect(decision.reason).assertEqual('manual_peek_scroll_settle_restore');
    });

    it('restores the manually hidden web panel only when the settle gesture ran toward the top', 0, () => {
      const coordinator = new BrowserBottomChromeScrollCoordinator();
      coordinator.handleWebScrollMove(buildWebInput(1000), 1000);
      // A direction reversal inside one gesture resolves to the last direction: up wins.
      coordinator.handleWebScrollMove(buildWebInput(1300), 1100);
      coordinator.handleWebScrollMove(buildWebInput(1240), 1200);
      let decision = coordinator.handleWebScrollSettle(buildWebInput(1240), 1300);
      expect(decision.detent).assertEqual('low');
      expect(decision.reason).assertEqual('manual_peek_scroll_settle_restore');

      // An upward jitter below the reveal delta must not summon the panel.
      const quietCoordinator = new BrowserBottomChromeScrollCoordinator();
      quietCoordinator.handleWebScrollMove(buildWebInput(1000), 1000);
      quietCoordinator.handleWebScrollMove(buildWebInput(995), 1100);
      decision = quietCoordinator.handleWebScrollSettle(buildWebInput(995), 1200);
      expect(decision.changed).assertFalse();
      expect(decision.detent).assertEqual('peek');
    });

    it('keeps the manually hidden home panel hidden while the feed is read on', 0, () => {
      const coordinator = new BrowserBottomChromeScrollCoordinator();
      let decision = coordinator.handleHomeScroll(buildHomeInput(0), 1000);
      expect(decision.changed).assertFalse();
      decision = coordinator.handleHomeScroll(buildHomeInput(200), 1100);
      expect(decision.changed).assertFalse();
      expect(decision.detent).assertEqual('peek');
      expect(decision.reason).assertEqual('none');
    });

    it('restores the manually hidden home panel on a scroll back toward the feed top', 0, () => {
      const coordinator = new BrowserBottomChromeScrollCoordinator();
      coordinator.handleHomeScroll(buildHomeInput(600), 1000);
      const decision = coordinator.handleHomeScroll(buildHomeInput(580), 1100);
      expect(decision.detent).assertEqual('low');
      expect(decision.presentation).assertEqual('resting');
      expect(decision.reason).assertEqual('home_manual_peek_scroll_restore');
    });

    it('keeps the ordinary scroll collapse and reveal semantics unchanged', 0, () => {
      const coordinator = new BrowserBottomChromeScrollCoordinator();
      coordinator.handleWebScrollMove(buildWebInput(0, 'low'), 1000);
      let decision = coordinator.handleWebScrollMove(buildWebInput(40, 'low'), 1100);
      expect(decision.presentation).assertEqual('compact');
      expect(decision.reason).assertEqual('scroll_compact');
      decision = coordinator.handleWebScrollMove(buildWebInput(10, 'low', 'compact'), 2000);
      expect(decision.presentation).assertEqual('resting');
      expect(decision.reason).assertEqual('scroll_reveal');

      const hiddenCoordinator = new BrowserBottomChromeScrollCoordinator();
      hiddenCoordinator.handleWebScrollMove(buildWebInput(0, 'low', 'resting', 'hidden'), 1000);
      decision = hiddenCoordinator.handleWebScrollMove(buildWebInput(40, 'low', 'resting', 'hidden'), 1100);
      expect(decision.presentation).assertEqual('hidden');
      expect(decision.reason).assertEqual('scroll_hide');
    });
  });
}
