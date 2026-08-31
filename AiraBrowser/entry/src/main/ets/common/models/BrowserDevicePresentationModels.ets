export type BrowserTabletInterfaceMode = 'auto' | 'touch' | 'desktop';

/**
 * Stable physical fold states used by automatic Shell-family selection.
 * Intermediate hinge angles intentionally do not have a presentation mode;
 * the window keeps its last stable fold decision until the device settles.
 */
export type BrowserFoldPresentationState = 'unknown' | 'folded' | 'expanded';
