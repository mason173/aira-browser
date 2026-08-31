import { BrowserTabPreviewState } from './BrowserTabPreviewCoordinator';
import { BrowserTabsOverlayRect } from './BrowserTabsOverlayViewModel';
import { BrowserWebLayerGeometrySnapshot } from './BrowserWebLayerGeometryCache';

export interface BrowserSharedSnapshotSelectionContext {
  previewState?: BrowserTabPreviewState;
  hostedWebLayerMeasured: boolean;
}

export interface BrowserSharedSnapshotSelectionDiagnosticContext extends BrowserSharedSnapshotSelectionContext {
  tabId: string;
  reusedGeometry?: BrowserWebLayerGeometrySnapshot;
  webRect?: BrowserTabsOverlayRect;
}

export class BrowserTabSharedSnapshotSelectionPolicy {
  shouldSkipSharedSnapshotExitForTabSelection(context: BrowserSharedSnapshotSelectionContext): boolean {
    const previewState = context.previewState;
    if (previewState === undefined || previewState.transitionReady === false) {
      return true;
    }
    const hasSharedSnapshot = (previewState.sharedSnapshotImageUri?.trim().length ?? 0) > 0 ||
      previewState.sharedSnapshotPixelMap !== undefined;
    return !context.hostedWebLayerMeasured && !hasSharedSnapshot;
  }

  buildSharedSnapshotExitSelectionDiagnostic(context: BrowserSharedSnapshotSelectionDiagnosticContext): string {
    const previewState = context.previewState;
    const transitionSource = previewState?.transitionSource?.captureSource ?? 'none';
    const transitionScope = previewState?.transitionSource?.captureScope ?? 'none';
    const transitionFrame = previewState?.transitionSource?.transitionFrame ?? 'none';
    const captureSource = previewState?.captureSource?.trim() ?? 'none';
    const reusedGeometry = context.reusedGeometry;
    const webRect = context.webRect;
    return [
      `tab=${context.tabId}`,
      `skip=false`,
      `measured=${context.hostedWebLayerMeasured}`,
      `transitionSource=${transitionSource}`,
      `transitionScope=${transitionScope}`,
      `transitionFrame=${transitionFrame}`,
      `captureSource=${captureSource}`,
      `transitionReady=${previewState?.transitionReady === true}`,
      `shared=${this.formatImageSize(previewState?.sharedSnapshotImageWidth, previewState?.sharedSnapshotImageHeight)}`,
      `reused=${reusedGeometry !== undefined}`,
      `reusedRect=${this.formatReusableGeometry(reusedGeometry)}`,
      `webRect=${this.formatRect(webRect)}`
    ].join(' ');
  }

  buildSharedSnapshotExitAnimationDiagnostic(
    tabId: string,
    previewState: BrowserTabPreviewState | undefined,
    webRect: BrowserTabsOverlayRect,
    sourceRect: BrowserTabsOverlayRect,
    targetRect: BrowserTabsOverlayRect,
    useFullWebSnapshot: boolean,
    imageWidth: number,
    imageHeight: number
  ): string {
    return [
      `tab=${tabId}`,
      `transitionSource=${previewState?.transitionSource?.captureSource ?? 'none'}`,
      `transitionScope=${previewState?.transitionSource?.captureScope ?? 'none'}`,
      `transitionFrame=${previewState?.transitionSource?.transitionFrame ?? 'none'}`,
      `captureSource=${previewState?.captureSource?.trim() ?? 'none'}`,
      `useFull=${useFullWebSnapshot}`,
      `image=${Math.max(1, Math.round(imageWidth))}x${Math.max(1, Math.round(imageHeight))}`,
      `webRect=${this.formatRect(webRect)}`,
      `sourceRect=${this.formatRect(sourceRect)}`,
      `targetRect=${this.formatRect(targetRect)}`
    ].join(' ');
  }

  private formatRect(rect?: BrowserTabsOverlayRect): string {
    if (rect === undefined) {
      return 'none';
    }
    return `${this.round(rect.left)},${this.round(rect.top)},${this.round(rect.width)}x${this.round(rect.height)}`;
  }

  private formatReusableGeometry(snapshot?: BrowserWebLayerGeometrySnapshot): string {
    if (snapshot === undefined) {
      return 'none';
    }
    return `${this.round(snapshot.webLeft)},${this.round(snapshot.webTop)},${this.round(snapshot.webWidth)}x${this.round(snapshot.webHeight)}`;
  }

  private formatImageSize(width?: number, height?: number, uri?: string): string {
    if ((width ?? 0) > 0 && (height ?? 0) > 0) {
      return `${this.round(width ?? 0)}x${this.round(height ?? 0)}`;
    }
    if ((uri?.trim().length ?? 0) > 0) {
      return 'uri';
    }
    return 'none';
  }

  private round(value: number): number {
    return Math.max(0, Math.round(value));
  }
}
