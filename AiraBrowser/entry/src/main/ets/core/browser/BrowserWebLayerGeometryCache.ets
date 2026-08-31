export interface BrowserWebLayerGeometrySnapshot {
  rootWidth: number;
  rootHeight: number;
  webLeft: number;
  webTop: number;
  webWidth: number;
  webHeight: number;
  layoutTop: number;
  visualTop: number;
  capturedAt: number;
}

export interface BrowserWebLayerGeometryContext {
  rootWidth: number;
  rootHeight: number;
  layoutTop: number;
  visualTop: number;
  now?: number;
}

export interface BrowserWebLayerEffectiveRectInput {
  measured: boolean;
  showHome: boolean;
  webLeft: number;
  webTop: number;
  webWidth: number;
  webHeight: number;
  rootWidth: number;
  rootHeight: number;
  layoutTop: number;
  visualTop: number;
  restored: BrowserWebLayerGeometrySnapshot | undefined;
}

export interface BrowserWebLayerRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

const MAX_GEOMETRY_AGE_MS: number = 7 * 24 * 60 * 60 * 1000;
const ROOT_SIZE_TOLERANCE: number = 2;
const INSET_TOLERANCE: number = 2;

export class BrowserWebLayerGeometryCache {
  buildSnapshot(input: BrowserWebLayerGeometrySnapshot): BrowserWebLayerGeometrySnapshot {
    return {
      rootWidth: this.positiveInteger(input.rootWidth),
      rootHeight: this.positiveInteger(input.rootHeight),
      webLeft: this.nonNegativeInteger(input.webLeft),
      webTop: this.nonNegativeInteger(input.webTop),
      webWidth: this.positiveInteger(input.webWidth),
      webHeight: this.positiveInteger(input.webHeight),
      layoutTop: this.nonNegativeInteger(input.layoutTop),
      visualTop: this.nonNegativeInteger(input.visualTop),
      capturedAt: Math.max(0, Math.floor(input.capturedAt))
    };
  }

  resolveReusableSnapshot(
    snapshot: BrowserWebLayerGeometrySnapshot | undefined,
    context: BrowserWebLayerGeometryContext
  ): BrowserWebLayerGeometrySnapshot | undefined {
    if (snapshot === undefined || !this.isUsable(snapshot)) {
      return undefined;
    }
    const now = Math.max(0, Math.floor(context.now ?? Date.now()));
    if (now - snapshot.capturedAt > MAX_GEOMETRY_AGE_MS) {
      return undefined;
    }
    if (!this.closeEnough(snapshot.rootWidth, context.rootWidth, ROOT_SIZE_TOLERANCE) ||
      !this.closeEnough(snapshot.rootHeight, context.rootHeight, ROOT_SIZE_TOLERANCE)) {
      return undefined;
    }
    if (!this.closeEnough(snapshot.layoutTop, context.layoutTop, INSET_TOLERANCE) ||
      !this.closeEnough(snapshot.visualTop, context.visualTop, INSET_TOLERANCE)) {
      return undefined;
    }
    if (snapshot.webLeft + snapshot.webWidth > context.rootWidth + ROOT_SIZE_TOLERANCE ||
      snapshot.webTop + snapshot.webHeight > context.rootHeight + ROOT_SIZE_TOLERANCE) {
      return undefined;
    }
    return snapshot;
  }

  resolveEffectiveRect(input: BrowserWebLayerEffectiveRectInput): BrowserWebLayerRect {
    const reusable = (input.measured || input.showHome)
      ? undefined
      : this.resolveReusableSnapshot(input.restored, {
        rootWidth: input.rootWidth,
        rootHeight: input.rootHeight,
        layoutTop: input.layoutTop,
        visualTop: input.visualTop
      });
    const left = (input.measured && input.webWidth > 1)
      ? Math.max(0, input.webLeft)
      : (reusable === undefined ? 0 : Math.max(0, reusable.webLeft));
    const top = (input.measured && input.webHeight > 1)
      ? Math.max(0, input.webTop)
      : (reusable === undefined ? input.visualTop : Math.max(0, reusable.webTop));
    const width = (input.measured && input.webWidth > 1)
      ? Math.max(1, input.webWidth)
      : (reusable === undefined ? Math.max(1, input.rootWidth) : Math.max(1, reusable.webWidth));
    const height = (input.measured && input.webHeight > 1)
      ? Math.max(1, input.webHeight)
      : (reusable === undefined ? Math.max(1, input.rootHeight - input.visualTop) : Math.max(1, reusable.webHeight));
    return { left, top, width, height };
  }

  private isUsable(snapshot: BrowserWebLayerGeometrySnapshot): boolean {
    return snapshot.rootWidth > 0 && snapshot.rootHeight > 0 &&
      snapshot.webWidth > 0 && snapshot.webHeight > 0 &&
      snapshot.capturedAt > 0;
  }

  private closeEnough(left: number, right: number, tolerance: number): boolean {
    return Math.abs(Math.round(left) - Math.round(right)) <= tolerance;
  }

  private positiveInteger(value: number): number {
    return Math.max(1, Math.round(value));
  }

  private nonNegativeInteger(value: number): number {
    return Math.max(0, Math.round(value));
  }
}
