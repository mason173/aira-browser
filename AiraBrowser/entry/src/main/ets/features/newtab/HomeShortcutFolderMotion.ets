import { HomeShortcutGridSlot } from './HomeShortcutGridPolicy';

export interface HomeShortcutFolderFrame { x: number; y: number; size: number; }

/** Per-child spatial continuity from the collapsed preview, independent of platform rendering. */
export class HomeShortcutFolderMotion {
  interpolate(source: HomeShortcutFolderFrame, target: HomeShortcutFolderFrame, progress: number): HomeShortcutFolderFrame {
    const value = Math.max(0, Math.min(1, progress));
    return { x: source.x + (target.x - source.x) * value,
      y: source.y + (target.y - source.y) * value,
      size: source.size + (target.size - source.size) * value };
  }

  previewChild(source: HomeShortcutFolderFrame, index: number, large: boolean): HomeShortcutFolderFrame {
    const columns = large ? 3 : 2;
    const gap = 4;
    const padding = 8;
    const size = Math.max(10, (source.size - padding * 2 - gap * (columns - 1)) / columns);
    const slot = large && index >= 8 ? 8 : index % (columns * columns);
    if (large && index >= 8 && index < 12) {
      const small = (size - 2) / 2;
      return { x: source.x + padding + 2 * (size + gap) + ((index - 8) % 2) * (small + 2),
        y: source.y + padding + 2 * (size + gap) + Math.floor((index - 8) / 2) * (small + 2), size: small };
    }
    return { x: source.x + padding + (slot % columns) * (size + gap),
      y: source.y + padding + Math.floor(slot / columns) * (size + gap), size: size };
  }

  expandedChild(slot: HomeShortcutGridSlot, panelX: number, panelY: number, iconSize: number): HomeShortcutFolderFrame {
    return { x: panelX + slot.x + (slot.width - iconSize) / 2,
      y: panelY + 64 + slot.y, size: iconSize };
  }

  childProgress(progress: number, index: number, closing: boolean): number {
    const delay = closing ? 0.02 + index * 0.018 : 0.045 + index * 0.028;
    const boundedDelay = Math.min(0.48, delay);
    return Math.max(0, Math.min(1, (progress - boundedDelay) / (1 - boundedDelay)));
  }
}
