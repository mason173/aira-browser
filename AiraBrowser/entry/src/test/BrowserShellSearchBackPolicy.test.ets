import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserShellBackCoordinator,
  BrowserShellBackState
} from '../main/ets/core/browser/BrowserShellBackCoordinator';

function createSearchBackState(
  searchActive: boolean,
  searchInputFocused: boolean
): BrowserShellBackState {
  return {
    manualElementHideSelectionActive: false,
    largeScreenOmniboxEditing: false,
    readerModeVisible: false,
    readerModeImagePreviewVisible: false,
    readerModePanelVisible: false,
    novelReaderVisible: false,
    novelReaderPanelVisible: false,
    customHomepageTransientBackActive: false,
    tabsSheetVisible: false,
    downloadPromptGuid: '',
    externalNavigationPromptVisible: false,
    splitToolbarSearchActive: searchActive,
    splitToolbarSearchInputFocused: searchInputFocused
  };
}

export default function browserShellSearchBackPolicyTest(): void {
  describe('BrowserShellSearchBackPolicy', () => {
    it('closes the keyboard first and exits the search page on the next Back', 0, () => {
      const coordinator = new BrowserShellBackCoordinator();
      // Search page open with the field holding the keyboard: Back only closes the keyboard.
      expect(coordinator.resolveBackAction(createSearchBackState(true, true)))
        .assertEqual('release_search_input_focus');
      // Keyboard gone, page still open: the next Back leaves the search page.
      expect(coordinator.resolveBackAction(createSearchBackState(true, false)))
        .assertEqual('dismiss_search_invocation');
    });

    it('exits immediately when the search page is open without the keyboard', 0, () => {
      const coordinator = new BrowserShellBackCoordinator();
      // No keyboard to close (external keyboard, or the field never focused): one Back exits.
      expect(coordinator.resolveBackAction(createSearchBackState(true, false)))
        .assertEqual('dismiss_search_invocation');
    });

    it('leaves ordinary Back untouched when no search page is open', 0, () => {
      const coordinator = new BrowserShellBackCoordinator();
      expect(coordinator.resolveBackAction(createSearchBackState(false, false)))
        .assertEqual('pass_through');
      // A stale focus report cannot fabricate a search session.
      expect(coordinator.resolveBackAction(createSearchBackState(false, true)))
        .assertEqual('pass_through');
    });
  });
}
