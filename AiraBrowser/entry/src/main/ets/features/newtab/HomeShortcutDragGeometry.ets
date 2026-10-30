import { HomeShortcutGridSpec } from './HomeShortcutGridPolicy';
import { ShortcutRecord } from '../../common/models/BrowserModels';

export interface HomeShortcutDragViewport { x: number; y: number; width: number; height: number; }
export interface HomeShortcutGridAnchor {
  x: number;
  y: number;
  spec: HomeShortcutGridSpec;
  addEntry: boolean;
}

export interface HomeShortcutFloatingIcon {
  shortcut?: ShortcutRecord;
  x: number;
  y: number;
  size: number;
  settling: boolean;
}

/** Window coordinates keep the grab point stable across scrolling and folder extraction. */
export class HomeShortcutDragGeometry {
  outside(x: number, y: number, viewport: HomeShortcutDragViewport, margin: number = 24): boolean {
    return x < viewport.x - margin || x > viewport.x + viewport.width + margin ||
      y < viewport.y - margin || y > viewport.y + viewport.height + margin;
  }

  scrollStep(y: number, viewport: HomeShortcutDragViewport): number {
    const edge = Math.min(56, viewport.height / 4);
    if (y < viewport.y || y > viewport.y + viewport.height) return 0;
    if (y < viewport.y + edge) return -12 * (1 - (y - viewport.y) / edge);
    if (y > viewport.y + viewport.height - edge) return 12 * (1 - (viewport.y + viewport.height - y) / edge);
    return 0;
  }
}
