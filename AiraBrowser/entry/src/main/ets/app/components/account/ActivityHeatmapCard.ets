import vibrator from '@ohos.vibrator';
import {
  AiraActivityHeatmapCellState,
  AiraActivityHeatmapViewState
} from '../../../common/models/ActivityModels';
import {
  BrowserActivityHeatmapTokenSet,
  DEFAULT_BROWSER_ACTIVITY_HEATMAP_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';

const HEATMAP_DAYS_PER_WEEK: number = 7;
const HEATMAP_MIN_CELL_SIZE: number = 14;
const HEATMAP_MAX_CELL_SIZE: number = 21;
const HEATMAP_MIN_COLUMN_GAP: number = 4;
const HEATMAP_MIN_ROW_GAP: number = 5;
const HEATMAP_MAX_ROW_GAP: number = 7;
const HEATMAP_COLUMNS: number = 12;
const HEATMAP_ROWS: number = 7;
const HEATMAP_MAX_WIDTH: number = 330;
const HEATMAP_FALLBACK_WIDTH: number = 296;
const HEATMAP_REVEAL_MIN_ANIMATION_MS: number = 1100;
const HEATMAP_REVEAL_MAX_ANIMATION_MS: number = 1600;
const HEATMAP_REVEAL_DELAY_SPAN_MS: number = 1400;
const HEATMAP_REVEAL_ACTIVE_MIN_OPACITY: number = 0;
const HEATMAP_REVEAL_EMPTY_MIN_OPACITY: number = 0;
const HEATMAP_REVEAL_START_DELAY_MS: number = 120;
const HEATMAP_SELECTION_HAPTIC_DURATION_MS: number = 18;
const HEATMAP_SELECTION_FRAME_INSET: number = 2;
const HEATMAP_TOOLTIP_DISMISS_MS: number = 2600;

export type ActivityHeatmapTooltipPresentation = 'popup' | 'none';

@Component
export struct ActivityHeatmapCard {
  @Prop state: AiraActivityHeatmapViewState;
  @Prop surfaceColor: ResourceColor = '';
  @Prop tooltipTextColor: ResourceColor = '';
  @Prop heatmapColors: BrowserActivityHeatmapTokenSet = DEFAULT_BROWSER_ACTIVITY_HEATMAP_TOKENS;
  @Prop tooltipPresentation: ActivityHeatmapTooltipPresentation = 'popup';
  @State private measuredHeatmapWidth: number = 0;
  @State private heatmapHeight: number = 0;
  @State private revealVisible: boolean = false;
  @State private revealFinished: boolean = false;
  @State private selectedDate: string = '';
  @State private tooltipDate: string = '';
  @State private tooltipVisible: boolean = false;
  @State private heatmapTouchTracking: boolean = false;

  build() {
    Column() {
      Column({ space: this.resolveRowGap() }) {
        ForEach(this.buildRowIndexes(), (dayIndex: number) => {
          Row() {
            ForEach(this.buildColumnIndexes(), (weekIndex: number) => {
              this.buildCell(this.resolveCell(weekIndex, dayIndex), weekIndex, dayIndex)
            }, (weekIndex: number) => `${dayIndex}-${weekIndex}`)
          }
          .width('100%')
          .height(this.resolveCellSize())
          .justifyContent(FlexAlign.SpaceBetween)
        }, (dayIndex: number) => `${dayIndex}`)
      }
      .width('100%')
      .constraintSize({ maxWidth: HEATMAP_MAX_WIDTH })
      .height(this.resolveGridHeight())
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#00000000')
      .hitTestBehavior(this.tooltipPresentation === 'none' ? HitTestMode.None : HitTestMode.Block)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const nextWidth = this.parseAreaDimension(newArea.width);
        this.measuredHeatmapWidth = Number.isFinite(nextWidth) ? Math.max(0, nextWidth) : 0;
        this.heatmapHeight = this.parseAreaDimension(newArea.height);
      })
      .onTouch((event: TouchEvent) => {
        this.handleHeatmapTouch(event);
      })

    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.surfaceColor)
    .borderRadius(22)
    .onAppear(() => {
      this.startRevealAnimation();
    })
  }

  @Builder
  private buildCell(cell: AiraActivityHeatmapCellState, weekIndex: number, dayIndex: number) {
    Row() {
      Blank()
        .width(this.resolveInnerCellSize())
        .height(this.resolveInnerCellSize())
        .borderRadius(this.resolveInnerCellRadius())
        .backgroundColor(this.resolveLevelColor(cell.level))
        .opacity(this.resolveCellRevealOpacity(cell, weekIndex, dayIndex))
        .animation({
          duration: this.resolveCellRevealDurationMs(weekIndex, dayIndex),
          curve: Curve.Smooth,
          delay: this.revealVisible ? this.resolveCellRevealDelayMs(weekIndex, dayIndex) : 0
        })
    }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(this.resolveCellSize())
      .height(this.resolveCellSize())
      .borderRadius(this.resolveCellRadius())
      .border({
        width: this.resolveSelectedBorderWidth(this.isCellSelected(cell) && this.revealFinished),
        color: this.heatmapColors.todayBorder
      })
      .accessibilityText(cell.accessibilityText)
      .onClick(() => {
        this.showHeatmapTooltip(cell, false);
      })
      .bindPopup(this.isCellTooltipVisible(cell), {
        message: cell.tooltipText,
        placement: Placement.Top,
        enableArrow: true,
        autoCancel: true,
        mask: false,
        targetSpace: 8,
        popupColor: this.surfaceColor,
        messageOptions: {
          textColor: this.tooltipTextColor,
          font: {
            size: 13,
            weight: FontWeight.Medium
          }
        },
        radius: 14,
        width: 168,
        onStateChange: (event: PopupStateChangeParam) => {
          if (!event.isVisible && this.tooltipDate === cell.date) {
            this.tooltipVisible = false;
          }
        }
      })
  }

  private resolveCell(weekIndex: number, dayIndex: number): AiraActivityHeatmapCellState {
    const index = weekIndex * HEATMAP_DAYS_PER_WEEK + dayIndex;
    return this.state.cells[index];
  }

  private buildRowIndexes(): number[] {
    const indexes: number[] = [];
    for (let index = 0; index < HEATMAP_ROWS; index += 1) {
      indexes.push(index);
    }
    return indexes;
  }

  private buildColumnIndexes(): number[] {
    const indexes: number[] = [];
    for (let index = 0; index < HEATMAP_COLUMNS; index += 1) {
      indexes.push(index);
    }
    return indexes;
  }

  private resolveGridHeight(): number {
    return HEATMAP_ROWS * this.resolveCellSize() + (HEATMAP_ROWS - 1) * this.resolveRowGap();
  }

  private resolveLevelColor(level: number): ResourceColor {
    if (level <= 0) {
      return this.heatmapColors.empty;
    }
    if (level === 1) {
      return this.heatmapColors.level1;
    }
    if (level === 2) {
      return this.heatmapColors.level2;
    }
    if (level === 3) {
      return this.heatmapColors.level3;
    }
    return this.heatmapColors.level4;
  }

  private resolveCellSize(): number {
    const usableWidth = this.resolveUsableHeatmapWidth();
    const size = Math.floor(
      (usableWidth - HEATMAP_MIN_COLUMN_GAP * (HEATMAP_COLUMNS - 1)) / HEATMAP_COLUMNS
    );
    return Math.max(HEATMAP_MIN_CELL_SIZE, Math.min(HEATMAP_MAX_CELL_SIZE, size));
  }

  private resolveCellRadius(): number {
    return Math.max(4, Math.floor(this.resolveCellSize() / 3));
  }

  private resolveRowGap(): number {
    const gap = Math.floor(this.resolveCellSize() / 3);
    return Math.max(HEATMAP_MIN_ROW_GAP, Math.min(HEATMAP_MAX_ROW_GAP, gap));
  }

  private resolveInnerCellSize(): number {
    return Math.max(8, this.resolveCellSize() - HEATMAP_SELECTION_FRAME_INSET * 2);
  }

  private resolveInnerCellRadius(): number {
    return Math.max(3, this.resolveCellRadius() - HEATMAP_SELECTION_FRAME_INSET);
  }

  private resolveSelectedBorderWidth(isSelected: boolean): number {
    return isSelected ? 1.5 : 0;
  }

  private isCellSelected(cell: AiraActivityHeatmapCellState): boolean {
    return cell.date === this.resolveCurrentSelectedDate();
  }

  private handleHeatmapTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.heatmapTouchTracking = this.selectHeatmapCellAtTouch(event, true);
      if (this.heatmapTouchTracking) {
        this.consumeTouchEvent(event);
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (this.heatmapTouchTracking) {
        this.selectHeatmapCellAtTouch(event, false);
        this.consumeTouchEvent(event);
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.heatmapTouchTracking) {
        if (event.type === TouchType.Up) {
          this.showHeatmapTooltipAtTouch(event);
        }
        this.consumeTouchEvent(event);
      }
      this.heatmapTouchTracking = false;
    }
  }

  private selectHeatmapCellAtTouch(event: TouchEvent, forceFeedback: boolean): boolean {
    const cellIndex = this.resolveTouchCellIndex(event);
    if (cellIndex < 0 || cellIndex >= this.state.cells.length) {
      return false;
    }
    this.selectHeatmapCell(this.state.cells[cellIndex].date, true, forceFeedback);
    this.tooltipVisible = false;
    return true;
  }

  private selectHeatmapCell(date: string, shouldFeedback: boolean, forceFeedback: boolean): void {
    if (date.length <= 0) {
      return;
    }
    const wasSelected = date === this.resolveCurrentSelectedDate();
    this.selectedDate = date;
    if (shouldFeedback && (forceFeedback || !wasSelected)) {
      this.performCellSelectionFeedback();
    }
  }

  private resolveCurrentSelectedDate(): string {
    if (this.selectedDate.length > 0) {
      return this.selectedDate;
    }
    for (let index = 0; index < this.state.cells.length; index += 1) {
      if (this.state.cells[index].isToday) {
        return this.state.cells[index].date;
      }
    }
    return '';
  }

  private isCellTooltipVisible(cell: AiraActivityHeatmapCellState): boolean {
    return this.tooltipPresentation === 'popup' && this.tooltipVisible && this.tooltipDate === cell.date;
  }

  private showHeatmapTooltip(cell: AiraActivityHeatmapCellState, forceFeedback: boolean): void {
    this.selectHeatmapCell(cell.date, true, forceFeedback);
    this.tooltipDate = cell.date;
    if (this.tooltipPresentation === 'none') {
      this.tooltipVisible = false;
      return;
    }
    this.tooltipVisible = true;
    setTimeout(() => {
      if (this.tooltipDate === cell.date) {
        this.tooltipVisible = false;
      }
    }, HEATMAP_TOOLTIP_DISMISS_MS);
  }

  private showHeatmapTooltipAtTouch(event: TouchEvent): void {
    const cellIndex = this.resolveTouchCellIndex(event);
    if (cellIndex < 0 || cellIndex >= this.state.cells.length) {
      return;
    }
    this.showHeatmapTooltip(this.state.cells[cellIndex], false);
  }

  private resolveTouchCellIndex(event: TouchEvent): number {
    const localX = this.resolveTouchLocalX(event);
    const localY = this.resolveTouchLocalY(event);
    const gridWidth = this.resolveUsableHeatmapWidth();
    const gridHeight = this.heatmapHeight > 0 ? this.heatmapHeight : this.resolveGridHeight();
    if (localX < 0 || localX > gridWidth || localY < 0 || localY > gridHeight) {
      return -1;
    }
    const weekIndex = this.resolveTouchColumnIndex(localX, gridWidth);
    const dayIndex = this.resolveTouchRowIndex(localY);
    return weekIndex * HEATMAP_DAYS_PER_WEEK + dayIndex;
  }

  private resolveTouchColumnIndex(localX: number, gridWidth: number): number {
    const cellSize = this.resolveCellSize();
    const gap = HEATMAP_COLUMNS > 1 ?
      Math.max(0, (gridWidth - cellSize * HEATMAP_COLUMNS) / (HEATMAP_COLUMNS - 1)) : 0;
    const stride = cellSize + gap;
    const rawIndex = stride > 0 ? Math.round((localX - cellSize / 2) / stride) : 0;
    return Math.max(0, Math.min(HEATMAP_COLUMNS - 1, rawIndex));
  }

  private resolveTouchRowIndex(localY: number): number {
    const cellSize = this.resolveCellSize();
    const stride = cellSize + this.resolveRowGap();
    const rawIndex = stride > 0 ? Math.round((localY - cellSize / 2) / stride) : 0;
    return Math.max(0, Math.min(HEATMAP_ROWS - 1, rawIndex));
  }

  private resolveTouchLocalX(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return Number(event.touches[0].x);
    }
    if (event.changedTouches.length > 0) {
      return Number(event.changedTouches[0].x);
    }
    return -1;
  }

  private resolveTouchLocalY(event: TouchEvent): number {
    if (event.touches.length > 0) {
      return Number(event.touches[0].y);
    }
    if (event.changedTouches.length > 0) {
      return Number(event.changedTouches[0].y);
    }
    return -1;
  }

  private consumeTouchEvent(event: TouchEvent): void {
    event.stopPropagation();
  }

  private performCellSelectionFeedback(): void {
    vibrator.startVibration({
      type: 'time',
      duration: HEATMAP_SELECTION_HAPTIC_DURATION_MS
    }, {
      usage: 'touch'
    }).catch((_error: Error) => {
    });
  }

  private startRevealAnimation(): void {
    this.revealVisible = false;
    this.revealFinished = false;
    setTimeout(() => {
      this.revealVisible = true;
      setTimeout(() => {
        this.revealFinished = true;
      }, HEATMAP_REVEAL_DELAY_SPAN_MS + HEATMAP_REVEAL_MAX_ANIMATION_MS);
    }, HEATMAP_REVEAL_START_DELAY_MS);
  }

  private resolveCellRevealOpacity(
    cell: AiraActivityHeatmapCellState,
    weekIndex: number,
    dayIndex: number
  ): number {
    const minOpacity = cell.level > 0 ? HEATMAP_REVEAL_ACTIVE_MIN_OPACITY : HEATMAP_REVEAL_EMPTY_MIN_OPACITY;
    return this.revealVisible ? 1 : minOpacity;
  }

  private resolveCellRevealDelayMs(weekIndex: number, dayIndex: number): number {
    return Math.round(this.resolveCellStarSeed(weekIndex, dayIndex) * HEATMAP_REVEAL_DELAY_SPAN_MS);
  }

  private resolveCellRevealDurationMs(weekIndex: number, dayIndex: number): number {
    const inverseSeed = 1 - this.resolveCellStarSeed(dayIndex, weekIndex);
    return Math.round(
      HEATMAP_REVEAL_MIN_ANIMATION_MS +
      (HEATMAP_REVEAL_MAX_ANIMATION_MS - HEATMAP_REVEAL_MIN_ANIMATION_MS) * inverseSeed
    );
  }

  private resolveCellStarSeed(weekIndex: number, dayIndex: number): number {
    const cellIndex = weekIndex * HEATMAP_DAYS_PER_WEEK + dayIndex;
    const seed = (cellIndex * 73 + weekIndex * 41 + dayIndex * 97 + 17) % 101;
    return seed / 100;
  }

  private resolveUsableHeatmapWidth(): number {
    if (this.measuredHeatmapWidth > 0) {
      return Math.min(HEATMAP_MAX_WIDTH, this.measuredHeatmapWidth);
    }
    return HEATMAP_FALLBACK_WIDTH;
  }

  private parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`.replace('vp', '').replace('px', ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }

}
