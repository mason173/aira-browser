import { ShortcutRecord } from '../../common/models/BrowserModels';
import { HomeShortcutFolderCommand } from '../../services/shortcuts/HomeShortcutFolderService';
import { HomeShortcutGridPolicy, HomeShortcutGridSpec, HomeShortcutGridSlot } from './HomeShortcutGridPolicy';

export interface HomeShortcutDragPoint { x: number; y: number; }
export interface HomeShortcutDragState {
  activeId: string;
  targetId: string;
  center: boolean;
  orderedIds: string[];
}

/** LeafTab's two intents: pending center feedback never discards the confirmed layout projection. */
export class HomeShortcutDragSession {
  private policy: HomeShortcutGridPolicy = new HomeShortcutGridPolicy();
  private items: ShortcutRecord[] = [];
  private projected: ShortcutRecord[] = [];
  private spec?: HomeShortcutGridSpec;
  private activeId: string = '';
  private addEntry: boolean = false;
  private allowMerge: boolean = true;
  private parentId: string = '';
  private pendingKey: string = '';
  private pendingSince: number = 0;
  private pendingPoint: HomeShortcutDragPoint = { x: 0, y: 0 };
  private targetId: string = '';
  private center: boolean = false;
  private confirmedCenterId: string = '';
  private sourceSlot?: HomeShortcutGridSlot;

  begin(activeId: string, items: ShortcutRecord[], spec: HomeShortcutGridSpec, parentId: string, addEntry: boolean = false, allowMerge: boolean = true): void {
    this.cancel();
    this.activeId = activeId;
    this.items = items.slice();
    this.projected = items.slice();
    this.spec = spec;
    this.parentId = parentId;
    this.addEntry = addEntry;
    this.allowMerge = allowMerge;
    this.sourceSlot = this.policy.layout(items, spec, addEntry).slots.find((slot: HomeShortcutGridSlot): boolean => slot.id === activeId);
  }

  update(offset: HomeShortcutDragPoint, now: number): HomeShortcutDragState {
    if (!this.sourceSlot || !this.spec) return this.snapshot();
    const lane = (this.spec.width - (this.spec.columns - 1) * this.spec.columnGap) / this.spec.columns;
    const iconHeight = (this.spec.iconSize ?? this.spec.rowHeight) +
      (this.sourceSlot.span - 1) * (lane + this.spec.columnGap);
    const point: HomeShortcutDragPoint = {
      x: this.sourceSlot.x + this.sourceSlot.width / 2 + offset.x,
      y: this.sourceSlot.y + iconHeight / 2 + offset.y
    };
    const slots = this.policy.layout(this.projected, this.spec, this.addEntry).slots;
    const target = slots.find((slot: HomeShortcutGridSlot): boolean => point.x >= slot.x &&
      point.x <= slot.x + slot.width && point.y >= slot.y && point.y <= slot.y + slot.height);
    const active = this.items.find((item: ShortcutRecord): boolean => item.id === this.activeId);
    if (!target || target.id === '__home_add__' || target.id === '__home_settings__' || target.id === this.activeId || !active) {
      this.targetId = '';
      this.center = false;
      this.confirmedCenterId = '';
      this.pendingKey = '';
      return this.snapshot();
    }
    const inset = target.span === 2 ? 0.12 : 0.24;
    const targetIconSize = (this.spec.iconSize ?? this.spec.rowHeight) +
      (target.span - 1) * (lane + this.spec.columnGap);
    const targetIconX = target.x + (target.width - targetIconSize) / 2;
    const core = this.allowMerge && target.id !== '__home_add__' && active.kind !== 'folder' && this.parentId.length === 0 &&
      point.x >= targetIconX + targetIconSize * inset && point.x <= targetIconX + targetIconSize * (1 - inset) &&
      point.y >= target.y + targetIconSize * inset && point.y <= target.y + targetIconSize * (1 - inset);
    const previousCenter = this.center && this.targetId === target.id;
    this.targetId = target.id;
    this.center = core;
    if (!core || this.confirmedCenterId !== target.id) this.confirmedCenterId = '';
    const key = `${core ? 'center' : 'reorder'}:${target.id}`;
    const moved = Math.hypot(point.x - this.pendingPoint.x, point.y - this.pendingPoint.y) > 4;
    if (key !== this.pendingKey || (!core && moved)) {
      this.pendingKey = key;
      this.pendingSince = now;
      this.pendingPoint = point;
    }
    if (core && now - this.pendingSince >= 100) {
      this.confirmedCenterId = target.id;
    } else if (!core && (previousCenter || now - this.pendingSince >= 200)) {
      this.projected = this.policy.reorder(this.projected, this.activeId, target.id);
      this.pendingSince = now;
    }
    return this.snapshot();
  }

  snapshot(): HomeShortcutDragState {
    return { activeId: this.activeId, targetId: this.targetId, center: this.center,
      orderedIds: this.projected.map((item: ShortcutRecord): string => item.id) };
  }

  release(): HomeShortcutFolderCommand | undefined {
    if (this.confirmedCenterId.length > 0) {
      const target = this.items.find((item: ShortcutRecord): boolean => item.id === this.confirmedCenterId);
      return target?.kind === 'folder'
        ? { operation: 'move', shortcutId: this.activeId, parentId: target.id }
        : { operation: 'merge', shortcutId: this.activeId, targetId: this.confirmedCenterId };
    }
    if (this.projected.some((item: ShortcutRecord, index: number): boolean => item.id !== this.items[index]?.id)) {
      return { operation: 'reorder', shortcutId: this.activeId, parentId: this.parentId,
        orderedIds: this.projected.map((item: ShortcutRecord): string => item.id) };
    }
    return undefined;
  }

  cancel(): void {
    this.items = [];
    this.projected = [];
    this.spec = undefined;
    this.activeId = '';
    this.targetId = '';
    this.center = false;
    this.confirmedCenterId = '';
    this.pendingKey = '';
    this.sourceSlot = undefined;
  }
}
