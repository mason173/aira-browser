export interface HistoryLargeScreenLayoutSnapshot {
  contentWidthVp: number;
  horizontalPaddingVp: number;
}

const HISTORY_LARGE_SCREEN_MAX_CONTENT_WIDTH: number = 760;

/** Keeps the PC History timeline readable while the browser window resizes. */
export class HistoryLargeScreenLayoutPolicy {
  resolve(viewportWidthVp: number): HistoryLargeScreenLayoutSnapshot {
    const width = Math.max(0, viewportWidthVp);
    if (width < 600) {
      const padding = 16;
      return {
        contentWidthVp: Math.max(0, width - padding * 2),
        horizontalPaddingVp: padding
      };
    }
    if (width < 840) {
      const padding = 24;
      return {
        contentWidthVp: Math.min(HISTORY_LARGE_SCREEN_MAX_CONTENT_WIDTH, Math.max(0, width - padding * 2)),
        horizontalPaddingVp: padding
      };
    }
    const padding = 32;
    return {
      contentWidthVp: Math.min(HISTORY_LARGE_SCREEN_MAX_CONTENT_WIDTH, Math.max(0, width - padding * 2)),
      horizontalPaddingVp: padding
    };
  }
}
