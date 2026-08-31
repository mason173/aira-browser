import {
  BrowserLargeScreenInputProfile,
  BrowserLargeScreenWindowProfile
} from './BrowserLargeScreenTabStripViewModel';

export type BrowserLargeScreenTopChromeActionSlot =
  'navigation' |
  'address' |
  'page_actions' |
  'window_actions';

export type BrowserLargeScreenTopChromeActionId =
  'back' |
  'forward' |
  'reload' |
  'address' |
  'bookmark' |
  'download' |
  'share' |
  'tab_menu' |
  'new_tab' |
  'new_window';

export interface BrowserLargeScreenTopChromeHostCapabilities {
  tabMenuAvailable: boolean;
  newWindowAvailable: boolean;
}

export interface BrowserLargeScreenTopChromeActionFacts {
  windowProfile: BrowserLargeScreenWindowProfile;
  inputProfile: BrowserLargeScreenInputProfile;
  keyboardHintsAvailable: boolean;
  hasActiveTab: boolean;
  canGoBack: boolean;
  canGoForward: boolean;
  isLoading: boolean;
  hostCapabilities: BrowserLargeScreenTopChromeHostCapabilities;
}

export interface BrowserLargeScreenTopChromeActionPresentation {
  id: BrowserLargeScreenTopChromeActionId;
  slot: BrowserLargeScreenTopChromeActionSlot;
  visible: boolean;
  enabled: boolean;
  hoverVisible: boolean;
  keyboardHintVisible: boolean;
}

export interface BrowserLargeScreenTopChromeActionSnapshot {
  actions: BrowserLargeScreenTopChromeActionPresentation[];
  hoverActionsVisible: boolean;
  keyboardHintsVisible: boolean;
}

/**
 * Resolves action slots and affordance visibility for the Large-Screen Top
 * Chrome. It emits intent metadata only; existing browser action owners still
 * execute navigation, tab, download, bookmark, and window commands.
 */
export class BrowserLargeScreenTopChromeActionViewModel {
  resolve(facts: BrowserLargeScreenTopChromeActionFacts): BrowserLargeScreenTopChromeActionSnapshot {
    const hoverActionsVisible = facts.inputProfile !== 'touch';
    const keyboardHintsVisible = facts.keyboardHintsAvailable && facts.inputProfile === 'keyboard_pointer';
    const actions: BrowserLargeScreenTopChromeActionPresentation[] = [
      this.action('back', 'navigation', true, facts.canGoBack, hoverActionsVisible, keyboardHintsVisible),
      this.action('forward', 'navigation', true, facts.canGoForward, hoverActionsVisible, keyboardHintsVisible),
      this.action('reload', 'navigation', true, facts.hasActiveTab, hoverActionsVisible, keyboardHintsVisible),
      this.action('address', 'address', true, facts.hasActiveTab, hoverActionsVisible, keyboardHintsVisible),
      this.action('bookmark', 'page_actions', facts.hasActiveTab, facts.hasActiveTab, hoverActionsVisible, keyboardHintsVisible),
      this.action('download', 'page_actions', facts.hasActiveTab, facts.hasActiveTab, hoverActionsVisible, keyboardHintsVisible),
      this.action('share', 'page_actions', facts.hasActiveTab, facts.hasActiveTab, hoverActionsVisible, keyboardHintsVisible),
      this.action('tab_menu', 'window_actions', facts.hostCapabilities.tabMenuAvailable, true, hoverActionsVisible, keyboardHintsVisible),
      this.action('new_tab', 'window_actions', true, true, hoverActionsVisible, keyboardHintsVisible),
      this.action('new_window', 'window_actions', facts.hostCapabilities.newWindowAvailable, true, hoverActionsVisible, keyboardHintsVisible)
    ];
    return {
      actions: actions,
      hoverActionsVisible: hoverActionsVisible,
      keyboardHintsVisible: keyboardHintsVisible
    };
  }

  private action(
    id: BrowserLargeScreenTopChromeActionId,
    slot: BrowserLargeScreenTopChromeActionSlot,
    visible: boolean,
    enabled: boolean,
    hoverVisible: boolean,
    keyboardHintVisible: boolean
  ): BrowserLargeScreenTopChromeActionPresentation {
    return {
      id: id,
      slot: slot,
      visible: visible,
      enabled: enabled,
      hoverVisible: hoverVisible,
      keyboardHintVisible: keyboardHintVisible
    };
  }
}
