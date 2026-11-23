import { BrowserLargeScreenTabStripIntent } from '../../../core/browser/BrowserLargeScreenShellIntentApplication';
import { BrowserLargeScreenTabProjection } from '../../../core/browser/BrowserLargeScreenTabStripViewModel';

interface TabSlot {
  id: string;
  start: number;
  size: number;
}

export const DESKTOP_TAB_PAN_TAG: string = 'desktop-tab-reorder';

@Observed
export class BrowserDesktopTabDrag {
  sourceId: string = '';
  private pressedId: string = '';
  private suppressReleaseTabId: string = '';
  private slots: TabSlot[] = [];
  private indices: Map<string, number> = new Map<string, number>();
  private firstSlotIndex: number = 0;
  private pinned: boolean = false;
  private privateMode: boolean = false;
  private from: number = 0;
  private to: number = 0;
  private offset: number = 0;
  private viewportTop: number = 0;
  private viewportHeight: number = 0;
  private startScroll: number = 0;
  private pointerOffset: number = 0;
  private edgeStep: number = 0;
  private scrollTimer: number = -1;

  private readonly rowStride: number;
  private readonly readTabs: () => BrowserLargeScreenTabProjection[];
  private readonly onIntent: (intent: BrowserLargeScreenTabStripIntent) => void;
  private readonly scroller?: Scroller;

  // A zero stride uses the individual widths of horizontal tabs.
  constructor(rowStride: number, readTabs: () => BrowserLargeScreenTabProjection[],
    onIntent: (intent: BrowserLargeScreenTabStripIntent) => void, scroller?: Scroller) {
    this.rowStride = rowStride;
    this.readTabs = readTabs;
    this.onIntent = onIntent;
    this.scroller = scroller;
  }

  judge(event: BaseGestureEvent, recognizer: GestureRecognizer): GestureJudgeResult {
    if (recognizer.getTag() === DESKTOP_TAB_PAN_TAG && (!this.pressedId ||
      (event.axisHorizontal ?? 0) !== 0 || (event.axisVertical ?? 0) !== 0)) {
      return GestureJudgeResult.REJECT;
    }
    return GestureJudgeResult.CONTINUE;
  }

  noteMouse(tabId: string, event: MouseEvent): void {
    if (event.action === MouseAction.Press) {
      this.pressedId = event.button === MouseButton.Left ? tabId : '';
      this.suppressReleaseTabId = '';
    } else if (event.action === MouseAction.Release) {
      this.pressedId = '';
    }
  }

  noteTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down && event.source !== SourceType.Mouse) {
      this.pressedId = '';
      this.suppressReleaseTabId = '';
    }
  }

  suppressesRelease(tabId: string): boolean {
    return this.suppressReleaseTabId === tabId;
  }

  start(event: GestureEvent): void {
    const tabs = this.readTabs();
    const from = tabs.findIndex((tab: BrowserLargeScreenTabProjection): boolean => tab.id === this.pressedId);
    if (from < 0 || event.source !== SourceType.Mouse ||
      (event.axisHorizontal ?? 0) !== 0 || (event.axisVertical ?? 0) !== 0) {
      return;
    }
    const source = tabs[from];
    let first = from;
    while (first > 0 && tabs[first - 1].pinned === source.pinned &&
      tabs[first - 1].privateMode === source.privateMode) {
      first--;
    }
    const slots: TabSlot[] = [];
    let start = 0;
    this.indices.clear();
    for (let i = first; i < tabs.length && tabs[i].pinned === source.pinned &&
      tabs[i].privateMode === source.privateMode; i++) {
      const size = this.rowStride || tabs[i].widthVp;
      this.indices.set(tabs[i].id, slots.length);
      slots.push({ id: tabs[i].id, start: start, size: size });
      start += size;
    }
    if (slots.length <= 1) {
      return;
    }
    this.firstSlotIndex = first;
    this.pinned = source.pinned;
    this.privateMode = source.privateMode;
    this.slots = slots;
    this.from = from - first;
    this.to = this.from;
    this.sourceId = source.id;
    this.suppressReleaseTabId = source.id;
    this.startScroll = this.scroller?.currentOffset()?.yOffset ?? 0;
    this.update(event);
  }

  update(event: GestureEvent): void {
    if (!this.sourceId) {
      return;
    }
    this.pointerOffset = this.rowStride > 0 ? event.offsetY : event.offsetX;
    this.updateSlots();
    this.trackScrollEdge(event.fingerList[0]?.globalY);
  }

  private updateSlots(): void {
    const source = this.slots[this.from];
    const last = this.slots[this.slots.length - 1];
    const scrollDelta = (this.scroller?.currentOffset()?.yOffset ?? 0) - this.startScroll;
    this.offset = Math.max(-source.start, Math.min(last.start + last.size - source.start - source.size,
      this.pointerOffset + scrollDelta));
    let target = this.from;
    const leading = source.start + this.offset;
    while (this.offset < 0 && target > 0 && leading <= this.slots[target - 1].start + this.slots[target - 1].size / 2) {
      target--;
    }
    while (this.offset > 0 && target < this.slots.length - 1 &&
      leading + source.size >= this.slots[target + 1].start + this.slots[target + 1].size / 2) {
      target++;
    }
    this.to = target;
  }

  reconcileLayout(): void {
    if (!this.sourceId) {
      return;
    }
    const tabs = this.readTabs();
    const changed = this.slots.some((slot: TabSlot, index: number): boolean => {
      const tab = tabs[this.firstSlotIndex + index];
      return tab === undefined || tab.id !== slot.id || tab.pinned !== this.pinned ||
        tab.privateMode !== this.privateMode || (this.rowStride || tab.widthVp) !== slot.size;
    });
    if (changed) {
      this.clear();
    }
  }

  offsetFor(tabId: string): number {
    if (!this.sourceId) {
      return 0;
    }
    if (tabId === this.sourceId) {
      return this.offset;
    }
    const index = this.indices.get(tabId);
    if (index !== undefined && index > this.from && index <= this.to) {
      return -this.slots[this.from].size;
    }
    if (index !== undefined && index < this.from && index >= this.to) {
      return this.slots[this.from].size;
    }
    return 0;
  }

  setViewport(area: Area): void {
    this.viewportTop = Number(area.globalPosition.y);
    this.viewportHeight = Number(area.height);
  }

  private trackScrollEdge(pointerY?: number): void {
    if (!this.scroller || pointerY === undefined || this.viewportHeight <= 0) {
      return;
    }
    const y = pointerY - this.viewportTop;
    const edge = Math.min(this.rowStride / 2, this.viewportHeight / 4);
    this.edgeStep = y < edge ? -8 : (y > this.viewportHeight - edge ? 8 : 0);
    if (!this.edgeStep || (this.edgeStep < 0 && this.to === 0) ||
      (this.edgeStep > 0 && this.to === this.slots.length - 1)) {
      this.stopScroll();
    } else if (this.scrollTimer < 0) {
      this.scrollTimer = setInterval((): void => {
        this.scroller?.scrollBy(0, this.edgeStep);
        this.updateSlots();
        if ((this.edgeStep < 0 && this.to === 0) || (this.edgeStep > 0 && this.to === this.slots.length - 1)) {
          this.stopScroll();
        }
      }, 24);
    }
  }

  private stopScroll(): void {
    if (this.scrollTimer >= 0) {
      clearInterval(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  finish(event: GestureEvent): void {
    if (!this.sourceId) {
      return;
    }
    this.update(event);
    const sourceId = this.sourceId;
    const targetId = this.slots[this.to].id;
    this.clear();
    if (sourceId !== targetId) {
      this.onIntent({ kind: 'reorder_tab', tabId: sourceId, targetTabId: targetId });
    }
  }

  clear(): void {
    this.stopScroll();
    this.sourceId = '';
    this.pressedId = '';
    this.offset = 0;
    this.slots = [];
    this.indices.clear();
  }
}
