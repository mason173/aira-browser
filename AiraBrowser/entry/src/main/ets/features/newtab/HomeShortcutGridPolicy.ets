import { ShortcutRecord } from '../../common/models/BrowserModels';

export interface HomeShortcutGridSlot {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  span: number;
}

export interface HomeShortcutGridSpec {
  columns: number;
  width: number;
  columnGap: number;
  rowGap: number;
  rowHeight: number;
  iconSize?: number;
  pinnedSettings?: boolean;
  centerPartialRows: boolean;
}

export interface HomeShortcutGridLayout {
  slots: HomeShortcutGridSlot[];
  height: number;
}

/** Deterministic slots shared by hit testing and animation; animated geometry is never remeasured. */
export class HomeShortcutGridPolicy {
  footprint(items: ShortcutRecord[]): number {
    return items.reduce((count: number, item: ShortcutRecord): number => count +
      (item.kind === 'folder' && item.folderDisplayMode === 'large' ? 4 : 1), 0);
  }

  layout(items: ShortcutRecord[], spec: HomeShortcutGridSpec, addEntry: boolean = false): HomeShortcutGridLayout {
    const columns = Math.max(1, spec.columns);
    const lane = Math.max(1, (spec.width - (columns - 1) * spec.columnGap) / columns);
    const occupied: boolean[][] = [];
    const slots: HomeShortcutGridSlot[] = [];
    const ids = items.map((item: ShortcutRecord): string => item.id);
    if (spec.pinnedSettings) ids.push('__home_settings__');
    if (addEntry) ids.push('__home_add__');
    ids.forEach((id: string, index: number): void => {
      const item = items[index];
      const span = columns >= 2 && item?.kind === 'folder' && item.folderDisplayMode === 'large' ? 2 : 1;
      let cell = 0;
      while (!this.fits(occupied, Math.floor(cell / columns), cell % columns, span, columns)) cell++;
      const row = Math.floor(cell / columns);
      const column = cell % columns;
      for (let r = row; r < row + span; r++) {
        if (!occupied[r]) occupied[r] = [];
        for (let c = column; c < column + span; c++) occupied[r][c] = true;
      }
      slots.push({ id: id, x: column * (lane + spec.columnGap), y: row * (spec.rowHeight + spec.rowGap),
        width: lane * span + spec.columnGap * (span - 1),
        height: spec.rowHeight * span + spec.rowGap * (span - 1), span: span });
    });
    if (spec.centerPartialRows && !slots.some((slot: HomeShortcutGridSlot): boolean => slot.span > 1)) {
      const remainder = slots.length % columns;
      if (remainder > 0 && slots.length > columns) {
        const shift = (columns - remainder) * (lane + spec.columnGap) / 2;
        slots.slice(slots.length - remainder).forEach((slot: HomeShortcutGridSlot): void => { slot.x += shift; });
      }
    }
    return { slots: slots, height: Math.max(spec.rowHeight,
      occupied.length * (spec.rowHeight + spec.rowGap) - spec.rowGap) };
  }

  reorder(items: ShortcutRecord[], activeId: string, targetId: string): ShortcutRecord[] {
    const active = items.find((item: ShortcutRecord): boolean => item.id === activeId);
    const targetIndex = items.findIndex((item: ShortcutRecord): boolean => item.id === targetId);
    if (!active || targetIndex < 0) return items;
    const movingSmall = !(active.kind === 'folder' && active.folderDisplayMode === 'large');
    const movable = items.filter((item: ShortcutRecord): boolean =>
      !movingSmall || !(item.kind === 'folder' && item.folderDisplayMode === 'large'));
    if (!movable.some((item: ShortcutRecord): boolean => item.id === targetId)) return items;
    const destination = movable.findIndex((item: ShortcutRecord): boolean => item.id === targetId);
    const ordered = movable.filter((item: ShortcutRecord): boolean => item.id !== activeId);
    ordered.splice(destination, 0, active);
    let cursor = 0;
    return items.map((item: ShortcutRecord): ShortcutRecord =>
      movingSmall && item.kind === 'folder' && item.folderDisplayMode === 'large' ? item : ordered[cursor++]);
  }

  private fits(occupied: boolean[][], row: number, column: number, span: number, columns: number): boolean {
    if (column + span > columns) return false;
    for (let r = row; r < row + span; r++) {
      for (let c = column; c < column + span; c++) if (occupied[r]?.[c]) return false;
    }
    return true;
  }
}
