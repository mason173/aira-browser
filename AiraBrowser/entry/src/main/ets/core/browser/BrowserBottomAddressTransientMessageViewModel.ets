import { formatTopChromeAddress } from './AddressDisplayFormatter';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';

const BOTTOM_ADDRESS_TRANSIENT_MESSAGE_DURATION_MS = 1800;

export interface BrowserBottomAddressTransientMessageState {
  text: string;
  version: number;
  contextKey: string;
  expiresAtMs: number;
}

export const EMPTY_BROWSER_BOTTOM_ADDRESS_TRANSIENT_MESSAGE_STATE: BrowserBottomAddressTransientMessageState = {
  text: '',
  version: 0,
  contextKey: '',
  expiresAtMs: 0
};

export type BrowserBottomAddressTransientMessageSurface = 'home' | 'web';

export interface BrowserBottomAddressTransientMessageContext {
  surface: BrowserBottomAddressTransientMessageSurface;
  tabId: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface BrowserBottomAddressDisplayInput {
  addressInput: string;
  isHomeMode: boolean;
  isDocumentViewerPage: boolean;
  documentTitle: string;
  transientMessageState: BrowserBottomAddressTransientMessageState;
  transientMessageContext: BrowserBottomAddressTransientMessageContext;
  nowMs: number;
}

export interface BrowserBottomAddressPresentationInput extends BrowserBottomAddressDisplayInput {
  homeSearchFocused: boolean;
  webBottomAddressFocused: boolean;
  webBottomAddressInput: string;
}

export interface BrowserBottomAddressSuggestionInput {
  addressInput: string;
  webBottomAddressInput: string;
  webPageVisible: boolean;
  showTabsSheet: boolean;
  showHomePage: boolean;
  webBottomAddressFocused: boolean;
  webBottomAddressPanelDetent: string;
}

export class BrowserBottomAddressTransientMessageViewModel {
  private resolveHomeSurfaceMessage(helperMessage: string): string {
    const message = helperMessage.trim();
    if (message === '回到首页了。' || message === '已回到首页。' || message === '已回到普通模式') {
      return '已回到主页';
    }
    return message;
  }

  applyMessage(
    currentState: BrowserBottomAddressTransientMessageState,
    message: string,
    context: BrowserBottomAddressTransientMessageContext,
    nowMs: number = Date.now()
  ): BrowserBottomAddressTransientMessageState {
    const text = this.resolveHomeSurfaceMessage(message);
    if (text.length === 0) {
      return currentState;
    }
    return {
      text: text,
      version: currentState.version + 1,
      contextKey: this.resolveContextKey(context),
      expiresAtMs: nowMs + BOTTOM_ADDRESS_TRANSIENT_MESSAGE_DURATION_MS
    };
  }

  resolveAddressDisplayText(input: BrowserBottomAddressDisplayInput): string {
    const transientMessage = this.resolveVisibleMessage(
      input.transientMessageState,
      input.transientMessageContext,
      input.nowMs
    );
    if (transientMessage.length > 0) {
      return transientMessage;
    }
    if (!input.isHomeMode && input.isDocumentViewerPage) {
      return input.documentTitle;
    }
    if (input.isHomeMode) {
      return input.addressInput;
    }
    return formatTopChromeAddress(input.addressInput);
  }

  resolveAddressFocused(input: BrowserBottomAddressPresentationInput): boolean {
    return input.isHomeMode ? input.homeSearchFocused : input.webBottomAddressFocused;
  }

  resolveAddressInput(input: BrowserBottomAddressPresentationInput): string {
    if (!input.isHomeMode && input.isDocumentViewerPage) {
      return input.documentTitle;
    }
    return input.isHomeMode ? input.addressInput : input.webBottomAddressInput;
  }

  resolveSuggestionQuery(input: BrowserBottomAddressSuggestionInput): string {
    if (this.isWebSuggestionSurfaceVisible(input)) {
      return input.webBottomAddressInput;
    }
    return input.addressInput;
  }

  isWebSuggestionSurfaceVisible(input: BrowserBottomAddressSuggestionInput): boolean {
    return input.webPageVisible &&
      !input.showTabsSheet &&
      !input.showHomePage &&
      input.webBottomAddressFocused &&
      input.webBottomAddressPanelDetent === 'middle';
  }

  clear(currentState: BrowserBottomAddressTransientMessageState): BrowserBottomAddressTransientMessageState {
    if (currentState.text.length <= 0 &&
      currentState.contextKey.length <= 0 &&
      currentState.expiresAtMs <= 0) {
      return currentState;
    }
    return {
      text: '',
      version: currentState.version + 1,
      contextKey: '',
      expiresAtMs: 0
    };
  }

  clearExpired(
    currentState: BrowserBottomAddressTransientMessageState,
    expectedVersion: number,
    context: BrowserBottomAddressTransientMessageContext,
    nowMs: number = Date.now()
  ): BrowserBottomAddressTransientMessageState {
    if (currentState.version !== expectedVersion) {
      return currentState;
    }
    if (this.resolveVisibleMessage(currentState, context, nowMs).length > 0) {
      return currentState;
    }
    return this.clear(currentState);
  }

  resolveClearDelayMs(
    state: BrowserBottomAddressTransientMessageState,
    context: BrowserBottomAddressTransientMessageContext,
    nowMs: number = Date.now()
  ): number {
    if (this.resolveVisibleMessage(state, context, nowMs).length <= 0) {
      return -1;
    }
    return Math.max(0, state.expiresAtMs - nowMs);
  }

  private resolveVisibleMessage(
    state: BrowserBottomAddressTransientMessageState,
    context: BrowserBottomAddressTransientMessageContext,
    nowMs: number
  ): string {
    const text = state.text.trim();
    if (text.length <= 0 || state.expiresAtMs <= nowMs) {
      return '';
    }
    return state.contextKey === this.resolveContextKey(context) ? text : '';
  }

  private resolveContextKey(context: BrowserBottomAddressTransientMessageContext): string {
    return [
      context.surface,
      context.tabId.trim(),
      context.profileId,
      context.privacyMode,
      context.dataScope
    ].join('|');
  }
}
