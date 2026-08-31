import { KeyCode } from '@kit.InputKit';
import {
  BrowserTabsOverviewKeyboardMove,
  BrowserTabsOverviewKeyboardViewModel
} from '../BrowserTabsOverviewKeyboardViewModel';
import { BrowserTabState } from '../../tabs/TabManager';

export { BrowserTabsOverviewKeyboardMove } from '../BrowserTabsOverviewKeyboardViewModel';

interface BrowserTabsOverviewKeyboardMoveSelectionInput {
  tabIds: string[];
  currentTabId: string;
  activeTabId: string;
  columnCount: number;
  move: BrowserTabsOverviewKeyboardMove;
}

interface BrowserTabsOverviewKeyboardMoveSelectionResult {
  tabId: string;
  shouldApply: boolean;
  shouldScroll: boolean;
}

interface BrowserTabsOverviewKeyboardResolvedSelectionInput {
  tabIds: string[];
  effectiveSelectedTabId: string;
  externalSelectedTabId: string;
}

interface BrowserTabsOverviewKeyboardBadgeInput {
  tabIds: string[];
  tabId: string;
}

interface BrowserTabsOverviewKeyboardSelectionScrollRunInput {
  tabId: string;
  isStillSelected: (tabId: string) => boolean;
  scrollSelection: (tabId: string) => void;
}

export interface BrowserTabsOverviewKeyboardApplicationHost {
  getTabs: () => BrowserTabState[];
  isPrivacySectionActive: () => boolean;
  getActiveTabId: () => string;
  getSelectedTabId: () => string;
  applySelection: (tabId: string, showNumberBadges: boolean, resetOpeningSelection: boolean) => void;
  setNumberBadgesVisible: (visible: boolean) => void;
  showShortcutMessage: (message: string) => void;
  finishTabSelection: (tabId: string) => Promise<void>;
}

export interface BrowserTabsOverviewKeyboardShellKeyEventInput {
  isTabsOverviewVisible: boolean;
  isKeyDown: boolean;
  isKeyUp: boolean;
  keyCode: number;
}

export class BrowserTabsOverviewKeyboardCoordinator {
  private viewModel: BrowserTabsOverviewKeyboardViewModel = new BrowserTabsOverviewKeyboardViewModel();

  resolveNumberedTabId(tabs: BrowserTabState[], digit: number): string {
    return this.viewModel.resolveNumberedBrowserTabId(tabs, digit);
  }

  handleNumberShortcut(digit: number, host: BrowserTabsOverviewKeyboardApplicationHost): void {
    const targetTabId = this.viewModel.resolveNumberedBrowserTabId(this.resolveSectionTabs(host), digit);
    if (targetTabId.length <= 0) {
      host.showShortcutMessage('没有对应的标签页。');
      return;
    }
    host.applySelection(targetTabId, false, false);
    void host.finishTabSelection(targetTabId);
  }

  resetSelectionForOpening(host: BrowserTabsOverviewKeyboardApplicationHost): void {
    host.applySelection(this.resolveFallbackSelection(host), false, true);
  }

  async openSelectedTab(host: BrowserTabsOverviewKeyboardApplicationHost): Promise<void> {
    const selectedTabId = host.getSelectedTabId();
    const tabId = selectedTabId.length > 0 ? selectedTabId : this.resolveFallbackSelection(host);
    if (tabId.length <= 0) {
      return;
    }
    await host.finishTabSelection(tabId);
  }

  setNumberBadgesVisible(visible: boolean, host: BrowserTabsOverviewKeyboardApplicationHost): void {
    host.setNumberBadgesVisible(visible);
  }

  handleShellKeyEvent(
    input: BrowserTabsOverviewKeyboardShellKeyEventInput,
    host: BrowserTabsOverviewKeyboardApplicationHost
  ): boolean {
    if (!input.isTabsOverviewVisible) {
      return false;
    }
    if (input.isKeyDown) {
      this.handleShellKeyDown(input.keyCode, host);
      return this.isShellHandledKey(input.keyCode);
    }
    if (input.isKeyUp && this.isCtrlKeyCode(input.keyCode)) {
      host.setNumberBadgesVisible(false);
      return true;
    }
    return false;
  }

  moveSelection(input: BrowserTabsOverviewKeyboardMoveSelectionInput): BrowserTabsOverviewKeyboardMoveSelectionResult {
    const nextTabId = this.viewModel.moveSelection({
      tabIds: input.tabIds,
      currentTabId: input.currentTabId,
      activeTabId: input.activeTabId,
      columnCount: input.columnCount,
      move: input.move
    });
    return {
      tabId: nextTabId,
      shouldApply: nextTabId.length > 0 && nextTabId !== input.currentTabId,
      shouldScroll: true
    };
  }

  resolveSelectedTabId(input: BrowserTabsOverviewKeyboardResolvedSelectionInput): string {
    return this.viewModel.resolveSelectedTabId(
      input.tabIds,
      input.effectiveSelectedTabId,
      input.externalSelectedTabId
    );
  }

  resolveBadgeText(input: BrowserTabsOverviewKeyboardBadgeInput): string {
    return this.viewModel.resolveBadgeText(input.tabIds, input.tabId);
  }

  scheduleSelectionScroll(input: BrowserTabsOverviewKeyboardSelectionScrollRunInput): void {
    this.viewModel.scheduleSelectionScroll({
      tabId: input.tabId,
      isStillSelected: input.isStillSelected,
      scrollSelection: input.scrollSelection
    });
  }

  private resolveFallbackSelection(host: BrowserTabsOverviewKeyboardApplicationHost): string {
    return this.viewModel.resolveInitialBrowserTabSelection(this.resolveSectionTabs(host), host.getActiveTabId());
  }

  private resolveSectionTabs(host: BrowserTabsOverviewKeyboardApplicationHost): BrowserTabState[] {
    return this.viewModel.resolveSectionTabs(host.getTabs(), host.isPrivacySectionActive());
  }

  private handleShellKeyDown(keyCode: number, host: BrowserTabsOverviewKeyboardApplicationHost): void {
    if (this.isCtrlKeyCode(keyCode)) {
      host.setNumberBadgesVisible(true);
      return;
    }
    if (this.isEnterKeyCode(keyCode)) {
      void this.openSelectedTab(host);
    }
  }

  private isShellHandledKey(keyCode: number): boolean {
    return this.isCtrlKeyCode(keyCode) || this.isEnterKeyCode(keyCode);
  }

  private isCtrlKeyCode(keyCode: number): boolean {
    return keyCode === KeyCode.KEYCODE_CTRL_LEFT || keyCode === KeyCode.KEYCODE_CTRL_RIGHT;
  }

  private isEnterKeyCode(keyCode: number): boolean {
    return keyCode === KeyCode.KEYCODE_ENTER || keyCode === KeyCode.KEYCODE_NUMPAD_ENTER ||
      keyCode === KeyCode.KEYCODE_DPAD_CENTER;
  }
}
