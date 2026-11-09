import { MediaResolvedVideoAssistantSession } from '../../../features/mediaDiscovery/MediaSessionResolutionModels';
import { BrowserWebLayerRect } from '../BrowserWebLayerGeometryCache';

export type BrowserVideoActionToolbarAction = 'cast' | 'picture_in_picture' | 'fullscreen';
export const VIDEO_ACTION_BUTTON_SIZE: number = 44;
export const VIDEO_ACTION_BUTTON_GAP: number = 8;
export const VIDEO_ACTION_TOOLBAR_WIDTH: number = VIDEO_ACTION_BUTTON_SIZE * 3 + VIDEO_ACTION_BUTTON_GAP * 2;

export interface BrowserArkWebMediaButtonState {
  visible: boolean;
  identity: string;
  busy: boolean;
  x: number;
  y: number;
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export interface BrowserVideoActionToolbarPosition {
  x: number;
  y: number;
}

export function resolveVideoActionToolbarBottomInset(
  bounds: BrowserWebLayerRect,
  rootHeight: number,
  systemInset: number,
  floatingToolbarOverlap: number
): number {
  const occupied = Math.max(0, Number.isFinite(systemInset) ? systemInset : 0,
    Number.isFinite(floatingToolbarOverlap) ? floatingToolbarOverlap : 0);
  // Split/desktop shells and the optional safe-area mode already shorten the Web layer.
  const reserved = Number.isFinite(rootHeight) && Number.isFinite(bounds.top + bounds.height) ?
    Math.max(0, rootHeight - bounds.top - bounds.height) : 0;
  return Math.max(0, occupied - reserved);
}

export function buildVideoActionToolbarState(
  session: MediaResolvedVideoAssistantSession | undefined,
  identity: string,
  enabled: boolean,
  busy: boolean,
  bounds: BrowserWebLayerRect,
  bottomChromeInset: number = 0
): BrowserArkWebMediaButtonState {
  const margin = 12;
  const bottomInset = Number.isFinite(bottomChromeInset) ? Math.max(0, bottomChromeInset) : 0;
  const validBounds = Number.isFinite(bounds.left) && Number.isFinite(bounds.top) &&
    Number.isFinite(bounds.width) && Number.isFinite(bounds.height) &&
    bounds.width >= VIDEO_ACTION_TOOLBAR_WIDTH + margin * 2 &&
    bounds.height - bottomInset >= VIDEO_ACTION_BUTTON_SIZE + margin * 2;
  const minX = validBounds ? bounds.left + margin : 0;
  const minY = validBounds ? bounds.top + margin : 0;
  const maxX = validBounds ? bounds.left + bounds.width - VIDEO_ACTION_TOOLBAR_WIDTH - margin : 0;
  const maxY = validBounds ? bounds.top + bounds.height - bottomInset - VIDEO_ACTION_BUTTON_SIZE - margin : 0;
  let x = maxX;
  let y = minY + (maxY - minY) * 0.4;
  const geometry = session?.geometry;
  // Child-frame rectangles belong to that frame, not the root Web viewport.
  // Without a top-document transform, use the draggable viewport anchor instead.
  if (validBounds && session?.playbackTargetBinding?.transport === 'document_direct' &&
    geometry !== undefined && geometry.viewportWidth > 0 && geometry.viewportHeight > 0 &&
    Number.isFinite(geometry.x) && Number.isFinite(geometry.y) &&
    Number.isFinite(geometry.width) && Number.isFinite(geometry.height)) {
    const scaleX = bounds.width / geometry.viewportWidth;
    const scaleY = bounds.height / geometry.viewportHeight;
    x = bounds.left + (geometry.x + geometry.width) * scaleX - VIDEO_ACTION_TOOLBAR_WIDTH;
    y = bounds.top + (geometry.y + geometry.height) * scaleY + 20;
  }
  return {
    visible: enabled && validBounds && session !== undefined && identity.length > 0,
    identity: identity,
    busy: busy,
    x: Math.max(minX, Math.min(maxX, x)),
    y: Math.max(minY, Math.min(maxY, y)),
    minX: minX, minY: minY, maxX: maxX, maxY: maxY
  };
}

/** UI drag state is scoped to one resolved playback target and clamped on resize. */
export class BrowserVideoActionToolbarPositionModel {
  private identity: string = '';
  private position?: BrowserVideoActionToolbarPosition = undefined;
  private dragOrigin?: BrowserVideoActionToolbarPosition = undefined;

  resolve(state: BrowserArkWebMediaButtonState): BrowserVideoActionToolbarPosition {
    if (this.identity !== state.identity) {
      this.identity = state.identity;
      this.position = undefined;
      this.dragOrigin = undefined;
    }
    const position = this.position ?? { x: state.x, y: state.y };
    return {
      x: Math.max(state.minX, Math.min(state.maxX, position.x)),
      y: Math.max(state.minY, Math.min(state.maxY, position.y))
    };
  }

  begin(state: BrowserArkWebMediaButtonState): void {
    this.dragOrigin = this.resolve(state);
  }

  move(state: BrowserArkWebMediaButtonState, offsetX: number, offsetY: number): void {
    this.resolve(state);
    if (this.dragOrigin === undefined || !Number.isFinite(offsetX) || !Number.isFinite(offsetY)) {
      return;
    }
    this.position = {
      x: Math.max(state.minX, Math.min(state.maxX, this.dragOrigin.x + offsetX)),
      y: Math.max(state.minY, Math.min(state.maxY, this.dragOrigin.y + offsetY))
    };
  }

  end(): void {
    this.dragOrigin = undefined;
  }
}
