export interface BrowserRootAddressInputSessionSnapshot {
  isHomeMode: boolean;
  homeSearchFocused: boolean;
  homeSearchOverlayVisible: boolean;
  homeAddressInput: string;
  searchSuggestionsVisible: boolean;
  webBottomAddressFocused: boolean;
  webBottomAddressDraft: string;
  keyboardOverlayInsetVp: number;
  keyboardHiddenConfirmed: boolean;
  keyboardHideProtectionUntilMs: number;
  nowMs: number;
}

export interface BrowserRootAddressInputSessionEndPlan {
  shouldResetSearchOverlay: boolean;
  shouldClearHomeSearchFocus: boolean;
  shouldClearHomeAddressInput: boolean;
  shouldClearWebAddressFocus: boolean;
  shouldClearWebAddressDraft: boolean;
  shouldCollapsePanel: boolean;
  shouldReleaseKeyboardAvoidMode: boolean;
  shouldHideTextInput: boolean;
  webStatusBarRestoreReason: string;
}

export interface BrowserRootAddressInputSubmitPlan extends BrowserRootAddressInputSessionEndPlan {
  rawInput: string;
  shouldRestoreScrollPresentation: boolean;
}

const ROOT_ADDRESS_KEYBOARD_HIDE_PROTECTION_MS: number = 1100;

export class BrowserRootAddressInputSessionCoordinator {
  isKeyboardInsetSyncActive(snapshot: BrowserRootAddressInputSessionSnapshot): boolean {
    return this.hasInputSessionResidue(snapshot);
  }

  buildKeyboardHideProtectionUntil(nowMs: number): number {
    return Math.max(0, Math.ceil(nowMs)) + ROOT_ADDRESS_KEYBOARD_HIDE_PROTECTION_MS;
  }

  shouldConfirmKeyboardHidden(snapshot: BrowserRootAddressInputSessionSnapshot): boolean {
    if (!snapshot.keyboardHiddenConfirmed) {
      return false;
    }
    if (!this.hasActiveInputIntent(snapshot)) {
      return true;
    }
    return Math.max(0, snapshot.nowMs) >= Math.max(0, snapshot.keyboardHideProtectionUntilMs);
  }

  buildEndPlan(snapshot: BrowserRootAddressInputSessionSnapshot): BrowserRootAddressInputSessionEndPlan {
    const hasHomeInput = snapshot.isHomeMode && snapshot.homeAddressInput.trim().length > 0;
    const hasWebInput = snapshot.webBottomAddressDraft.trim().length > 0;
    const hasSearchOverlayResidue = snapshot.homeSearchOverlayVisible || snapshot.searchSuggestionsVisible;
    const hasInputSessionResidue = this.hasInputSessionResidue(snapshot);
    return {
      shouldResetSearchOverlay: snapshot.keyboardHiddenConfirmed || hasSearchOverlayResidue || snapshot.homeSearchFocused ||
        snapshot.webBottomAddressFocused || hasHomeInput || hasWebInput,
      shouldClearHomeSearchFocus: snapshot.homeSearchFocused,
      shouldClearHomeAddressInput: hasHomeInput,
      shouldClearWebAddressFocus: snapshot.webBottomAddressFocused,
      shouldClearWebAddressDraft: hasWebInput,
      shouldCollapsePanel: snapshot.keyboardHiddenConfirmed || hasInputSessionResidue,
      shouldReleaseKeyboardAvoidMode: true,
      shouldHideTextInput: true,
      webStatusBarRestoreReason: snapshot.webBottomAddressFocused ? 'address-keyboard-hidden' : ''
    };
  }

  buildSubmitPlan(rawInput: string, snapshot: BrowserRootAddressInputSessionSnapshot): BrowserRootAddressInputSubmitPlan {
    const webMode = !snapshot.isHomeMode;
    return {
      rawInput: rawInput,
      shouldResetSearchOverlay: snapshot.homeSearchOverlayVisible ||
        snapshot.searchSuggestionsVisible ||
        snapshot.homeSearchFocused ||
        snapshot.webBottomAddressFocused,
      shouldClearHomeSearchFocus: snapshot.isHomeMode && snapshot.homeSearchFocused,
      shouldClearHomeAddressInput: snapshot.isHomeMode,
      shouldClearWebAddressFocus: webMode && snapshot.webBottomAddressFocused,
      shouldClearWebAddressDraft: webMode,
      shouldCollapsePanel: true,
      shouldReleaseKeyboardAvoidMode: true,
      shouldHideTextInput: true,
      shouldRestoreScrollPresentation: webMode,
      webStatusBarRestoreReason: webMode ? 'address-submit' : ''
    };
  }

  private hasInputSessionResidue(snapshot: BrowserRootAddressInputSessionSnapshot): boolean {
    return snapshot.homeSearchFocused ||
      snapshot.homeSearchOverlayVisible ||
      snapshot.searchSuggestionsVisible ||
      snapshot.webBottomAddressFocused ||
      snapshot.webBottomAddressDraft.trim().length > 0 ||
      snapshot.keyboardOverlayInsetVp > 0 ||
      (snapshot.isHomeMode && snapshot.homeAddressInput.trim().length > 0);
  }

  private hasActiveInputIntent(snapshot: BrowserRootAddressInputSessionSnapshot): boolean {
    return snapshot.homeSearchFocused ||
      snapshot.webBottomAddressFocused ||
      (snapshot.isHomeMode && snapshot.homeAddressInput.trim().length > 0) ||
      snapshot.webBottomAddressDraft.trim().length > 0;
  }
}
