import { window } from '@kit.ArkUI';
import {
  WebVideoFullscreenOrientationModel,
  WebVideoFullscreenOrientationMode
} from './WebVideoFullscreenOrientationModel';

export type BrowserWebFullscreenSource = 'web_content' | 'video_takeover' | 'video_web_fullscreen';

export interface BrowserWebFullscreenEnterInput {
  tabId: string;
  activeTabId: string;
  webPageVisible: boolean;
  homePageVisible: boolean;
  tabsSheetVisible: boolean;
  source: BrowserWebFullscreenSource;
  restoreOrientation: window.Orientation;
  payloadJson?: string;
  videoWidth?: number;
  videoHeight?: number;
}

export interface BrowserWebFullscreenExitInput {
  tabId: string;
  activeTabId: string;
  source?: BrowserWebFullscreenSource;
}

export interface BrowserWebFullscreenState {
  active: boolean;
  tabId: string;
  source: BrowserWebFullscreenSource;
  orientationMode: WebVideoFullscreenOrientationMode;
  restoreOrientation: window.Orientation;
}

export interface BrowserWebFullscreenEnterDecision {
  accepted: boolean;
  state: BrowserWebFullscreenState;
  orientation: window.Orientation;
}

export interface BrowserWebFullscreenExitDecision {
  accepted: boolean;
  state: BrowserWebFullscreenState;
  restoreChrome: boolean;
  restoreOrientation: window.Orientation;
}

export class BrowserWebFullscreenPresentationCoordinator {
  private readonly orientationModel: WebVideoFullscreenOrientationModel;

  constructor(orientationModel: WebVideoFullscreenOrientationModel = new WebVideoFullscreenOrientationModel()) {
    this.orientationModel = orientationModel;
  }

  createInactiveState(): BrowserWebFullscreenState {
    return {
      active: false,
      tabId: '',
      source: 'web_content',
      orientationMode: 'landscape',
      restoreOrientation: window.Orientation.AUTO_ROTATION_UNSPECIFIED
    };
  }

  enter(
    state: BrowserWebFullscreenState,
    input: BrowserWebFullscreenEnterInput
  ): BrowserWebFullscreenEnterDecision {
    if (!this.canEnter(input)) {
      return {
        accepted: false,
        state,
        orientation: window.Orientation.AUTO_ROTATION_LANDSCAPE
      };
    }
    const orientationMode = input.source === 'video_takeover' || input.source === 'video_web_fullscreen' ?
      this.orientationModel.resolveModeFromPayloadJson(input.payloadJson ?? '{}') :
      this.orientationModel.resolveMode({
        videoWidth: input.videoWidth ?? 0,
        videoHeight: input.videoHeight ?? 0
      });
    const nextState: BrowserWebFullscreenState = {
      active: true,
      tabId: input.tabId,
      source: input.source,
      orientationMode,
      restoreOrientation: input.restoreOrientation
    };
    return {
      accepted: true,
      state: nextState,
      orientation: this.toWindowOrientation(orientationMode)
    };
  }

  exit(
    state: BrowserWebFullscreenState,
    input: BrowserWebFullscreenExitInput
  ): BrowserWebFullscreenExitDecision {
    if (!state.active) {
      return {
        accepted: false,
        state,
        restoreChrome: false,
        restoreOrientation: state.restoreOrientation
      };
    }
    if (input.source !== undefined && input.source !== state.source) {
      return {
        accepted: false,
        state,
        restoreChrome: false,
        restoreOrientation: state.restoreOrientation
      };
    }
    if (!this.isEventForActiveFullscreen(state, input.tabId, input.activeTabId)) {
      return {
        accepted: false,
        state,
        restoreChrome: false,
        restoreOrientation: state.restoreOrientation
      };
    }
    return {
      accepted: true,
      state: this.createInactiveState(),
      restoreChrome: true,
      restoreOrientation: state.restoreOrientation
    };
  }

  resolveOrientationFromPayloadJson(payloadJson: string): window.Orientation {
    return this.toWindowOrientation(this.orientationModel.resolveModeFromPayloadJson(payloadJson));
  }

  isActiveForSource(state: BrowserWebFullscreenState, source: BrowserWebFullscreenSource): boolean {
    return state.active && state.source === source;
  }

  getActiveSource(state: BrowserWebFullscreenState): BrowserWebFullscreenSource | undefined {
    return state.active ? state.source : undefined;
  }

  private canEnter(input: BrowserWebFullscreenEnterInput): boolean {
    if (input.tabId.length <= 0 || input.tabId !== input.activeTabId) {
      return false;
    }
    return input.webPageVisible && !input.homePageVisible && !input.tabsSheetVisible;
  }

  private isEventForActiveFullscreen(
    state: BrowserWebFullscreenState,
    tabId: string,
    activeTabId: string
  ): boolean {
    if (tabId.length <= 0) {
      return state.tabId === activeTabId;
    }
    return tabId === state.tabId;
  }

  private toWindowOrientation(mode: WebVideoFullscreenOrientationMode): window.Orientation {
    return mode === 'portrait' ? window.Orientation.PORTRAIT : window.Orientation.AUTO_ROTATION_LANDSCAPE;
  }
}
