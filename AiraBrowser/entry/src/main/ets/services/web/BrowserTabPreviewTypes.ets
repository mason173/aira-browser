export type BrowserTabPreviewCaptureSource =
  'window' |
  'surface' |
  'surface-region' |
  'surface-transform' |
  'web' |
  'component' |
  'visible-shell' |
  'visible-tab-surface' |
  'web-page-container' |
  'none';

export type BrowserTabPreviewCaptureScope = 'web-content' | 'full-surface';
export type BrowserTabPreviewTransitionFrame = 'captured-surface' | 'current-web';

export interface BrowserTabPreviewSourceRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface BrowserTabPreviewTransitionSource {
  captureSource: BrowserTabPreviewCaptureSource;
  captureScope: BrowserTabPreviewCaptureScope;
  transitionFrame: BrowserTabPreviewTransitionFrame;
  sourceRect?: BrowserTabPreviewSourceRect;
}
