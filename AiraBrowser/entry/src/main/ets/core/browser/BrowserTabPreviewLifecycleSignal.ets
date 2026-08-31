export const BROWSER_TAB_PREVIEW_LIFECYCLE_CAPTURE_REVISION_KEY: string =
  'aira.browser.tabPreview.lifecycleCaptureRevision';

export class BrowserTabPreviewLifecycleSignal {
  static requestCapture(): number {
    const nextRevision = (AppStorage.get<number>(BROWSER_TAB_PREVIEW_LIFECYCLE_CAPTURE_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(BROWSER_TAB_PREVIEW_LIFECYCLE_CAPTURE_REVISION_KEY, nextRevision);
    return nextRevision;
  }
}
