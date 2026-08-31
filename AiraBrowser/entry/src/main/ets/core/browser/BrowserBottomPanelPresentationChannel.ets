import {
  BrowserBottomPanelMotionState,
  DEFAULT_BROWSER_BOTTOM_PANEL_MOTION_STATE
} from './BrowserBottomAddressPanelViewModel';
import {
  BrowserBottomChromePresentation,
  DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION
} from './BrowserBottomChromePresentationViewModel';
import { BrowserBottomPanelActionSnapshot } from './BrowserBottomPanelActionPresentationCoordinator';

export interface BrowserBottomPanelReadingContinuationPresentation {
  visible: boolean;
  title: string;
  loading: boolean;
}

export const HIDDEN_BROWSER_BOTTOM_PANEL_READING_CONTINUATION: BrowserBottomPanelReadingContinuationPresentation = {
  visible: false,
  title: '',
  loading: false
};

export class BrowserBottomPanelLivePresentation {
  panelMotionState: BrowserBottomPanelMotionState;
  bottomChromePresentation: BrowserBottomChromePresentation;
  actionSnapshot?: BrowserBottomPanelActionSnapshot;
  readingContinuation: BrowserBottomPanelReadingContinuationPresentation;
  addressFocused: boolean;
  floatingHeaderVisible: boolean;

  constructor(
    panelMotionState: BrowserBottomPanelMotionState,
    bottomChromePresentation: BrowserBottomChromePresentation,
    actionSnapshot?: BrowserBottomPanelActionSnapshot,
    readingContinuation: BrowserBottomPanelReadingContinuationPresentation =
      HIDDEN_BROWSER_BOTTOM_PANEL_READING_CONTINUATION,
    addressFocused: boolean = false,
    floatingHeaderVisible: boolean = true
  ) {
    this.panelMotionState = panelMotionState;
    this.bottomChromePresentation = bottomChromePresentation;
    this.actionSnapshot = actionSnapshot;
    this.readingContinuation = readingContinuation;
    this.addressFocused = addressFocused;
    this.floatingHeaderVisible = floatingHeaderVisible;
  }
}

export const DEFAULT_BROWSER_BOTTOM_PANEL_LIVE_PRESENTATION: BrowserBottomPanelLivePresentation =
  new BrowserBottomPanelLivePresentation(
    DEFAULT_BROWSER_BOTTOM_PANEL_MOTION_STATE,
    DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION
  );

export type BrowserBottomPanelPresentationListener = (presentation: BrowserBottomPanelLivePresentation) => void;

export class BrowserBottomPanelPresentationChannel {
  private presentation?: BrowserBottomPanelLivePresentation = undefined;
  private listener?: BrowserBottomPanelPresentationListener = undefined;

  publish(presentation: BrowserBottomPanelLivePresentation): void {
    this.presentation = presentation;
    if (this.listener !== undefined) {
      this.listener(presentation);
    }
  }

  current(): BrowserBottomPanelLivePresentation | undefined {
    return this.presentation;
  }

  connect(listener: BrowserBottomPanelPresentationListener): () => boolean {
    this.listener = listener;
    if (this.presentation !== undefined) {
      listener(this.presentation);
    }
    return (): boolean => {
      if (this.listener !== listener) {
        return false;
      }
      this.listener = undefined;
      return true;
    };
  }
}
