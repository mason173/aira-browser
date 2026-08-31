import vibrator from '@ohos.vibrator';
import { SearchEngineId } from '../../../common/models/BrowserModels';
import {
  SearchEngineManagementViewModel,
  SearchEngineRowView
} from '../../../core/search/SearchEngineManagementViewModel';
import { BrowserThemeViewState } from '../../../core/theme/BrowserThemeViewState';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';
import { SearchEngineIconResources } from './SearchEngineIconResources';

const SEARCH_ENGINE_ROW_HEIGHT: number = 58;
const SEARCH_ENGINE_DIVIDER_HEIGHT: number = 1;
const SEARCH_ENGINE_ROW_STRIDE: number = SEARCH_ENGINE_ROW_HEIGHT + SEARCH_ENGINE_DIVIDER_HEIGHT;
const SEARCH_ENGINE_DROP_ANIMATION_MS: number = 150;
const SEARCH_ENGINE_REORDER_HAPTIC_DURATION_MS: number = 18;
const SEARCH_ENGINE_REORDER_HAPTIC_MIN_INTERVAL_MS: number = 45;

@Component
export struct SearchDefaultEngineBuiltInList {
  private viewModel: SearchEngineManagementViewModel = new SearchEngineManagementViewModel();
  @Prop engines: SearchEngineRowView[] = [];
  @Prop isEnabled: boolean = true;
  @Prop theme: BrowserThemeViewState;
  @Prop desktopPresentation: boolean = false;
  @State private draggingEngineId: string = '';
  @State private dragOffsetY: number = 0;
  @State private dragOriginalIndex: number = -1;
  @State private dragCurrentIndex: number = -1;
  @State private droppingEngineId: string = '';
  @State private commitInProgress: boolean = false;
  private dropTimer: number = -1;
  private commitTimer: number = -1;
  private lastReorderFeedbackAt: number = 0;
  onSelectEngine: (engineId: SearchEngineId) => void = (_engineId: SearchEngineId) => {};
  onReorderEngines: (engineIds: SearchEngineId[]) => void = (_engineIds: SearchEngineId[]) => {};

  aboutToDisappear(): void {
    this.cancelDropTimer();
    this.cancelCommitTimer();
  }

  build() {
    SettingsGroupCard({
      surfaceColor: this.theme.surfaceBackground,
      desktopPresentation: this.desktopPresentation
    }) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.engines, (engine: SearchEngineRowView, index: number) => {
          this.buildOptionRow(engine, index, this.engines.length)
        }, (engine: SearchEngineRowView) => this.resolveEngineRenderKey(engine))
      }
      .width('100%')
      .height(this.resolveListHeight())
    }
  }

  @Builder
  private buildOptionRow(engine: SearchEngineRowView, index: number, total: number) {
    Column() {
      Row({ space: 12 }) {
        this.buildLeadingIcon(engine)

        Text(engine.title)
          .fontSize(this.desktopPresentation ? 15 : 16)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Radio({
          value: engine.id,
          group: 'default-search-engine'
        })
          .checked(engine.isDefault)
          .enabled(this.isEnabled)
          .hitTestBehavior(HitTestMode.None)
          .radioStyle({
            checkedBackgroundColor: this.theme.accent
          })

        this.buildDragHandle(engine)
      }
      .width('100%')
      .height(SEARCH_ENGINE_ROW_HEIGHT)
      .padding({ left: 16, right: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.isEnabled) {
          this.onSelectEngine(engine.id);
        }
      })

      if (index < total - 1) {
        SettingsGroupDivider({ dividerColor: this.theme.divider })
      }
    }
    .width('100%')
    .height(SEARCH_ENGINE_ROW_STRIDE)
    .position({
      x: 0,
      y: this.resolveRowPositionY(engine)
    })
    .zIndex(this.draggingEngineId === engine.id ? 8 : 0)
    .scale({
      x: this.draggingEngineId === engine.id ? 1.015 : 1,
      y: this.draggingEngineId === engine.id ? 1.015 : 1
    })
    .backgroundColor(this.theme.surfaceBackground)
    .animation({
      duration: this.resolveRowAnimationDuration(engine),
      curve: Curve.EaseOut
    })
  }

  @Builder
  private buildLeadingIcon(engine: SearchEngineRowView) {
    if (SearchEngineIconResources.builtInIcon(engine.id) !== undefined) {
      Stack() {
        Image(SearchEngineIconResources.builtInIcon(engine.id))
          .width(28)
          .height(28)
          .objectFit(ImageFit.Contain)
      }
      .width(38)
      .height(38)
      .borderRadius(12)
      .clip(true)
      .backgroundColor(this.theme.surfaceBackground)
      .borderWidth(1)
      .borderColor(this.theme.divider)
    } else {
      Row() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.theme.accent])
      }
      .width(38)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.theme.controlBackground)
      .borderRadius(12)
    }
  }

  @Builder
  private buildDragHandle(engine: SearchEngineRowView) {
    Button() {
      SymbolGlyph($r('sys.symbol.line_3_horizontal'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.theme.textSecondary])
    }
    .width(34)
    .height(34)
    .type(ButtonType.Circle)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.theme.controlBackground)
    .enabled(this.isEnabled)
    .accessibilityText('拖动调整搜索引擎顺序')
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 1 })
        .onActionStart(() => {
          this.beginDrag(engine);
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateDrag(engine, event);
        })
        .onActionEnd(() => {
          this.finishDrag(true);
        })
        .onActionCancel(() => {
          this.finishDrag(false);
        }),
      GestureMask.Normal
    )
  }

  private beginDrag(engine: SearchEngineRowView): void {
    if (!this.isEnabled) {
      return;
    }
    this.cancelDropTimer();
    this.cancelCommitTimer();
    this.draggingEngineId = engine.id;
    this.droppingEngineId = '';
    this.commitInProgress = false;
    this.dragOffsetY = 0;
    this.dragOriginalIndex = this.findEngineIndex(engine.id);
    this.dragCurrentIndex = this.dragOriginalIndex;
  }

  private updateDrag(engine: SearchEngineRowView, event: GestureEvent): void {
    if (this.draggingEngineId !== engine.id) {
      return;
    }
    this.dragOffsetY = Number(event.offsetY);
    this.reorderDuringDrag();
  }

  private finishDrag(shouldSave: boolean): void {
    const wasDragging = this.draggingEngineId.length > 0;
    const draggedEngineId = this.draggingEngineId;
    const targetIndex = this.dragCurrentIndex;
    const originalIndex = this.dragOriginalIndex;
    if (wasDragging && shouldSave && targetIndex >= 0 && originalIndex >= 0 && targetIndex !== originalIndex) {
      this.dropEngineToTarget(draggedEngineId, targetIndex);
      return;
    }
    this.clearDragState();
  }

  private dropEngineToTarget(engineId: string, targetIndex: number): void {
    this.cancelDropTimer();
    this.droppingEngineId = engineId;
    animateTo({
      duration: SEARCH_ENGINE_DROP_ANIMATION_MS,
      curve: Curve.EaseOut
    }, () => {
      this.dragOffsetY = this.resolveDropOffsetY();
    });
    this.dropTimer = setTimeout(() => {
      this.dropTimer = -1;
      const nextOrder = this.viewModel.moveBuiltInEngineToIndex(this.engines, engineId, targetIndex);
      this.commitInProgress = true;
      this.clearDragState();
      this.onReorderEngines(nextOrder);
      this.commitTimer = setTimeout(() => {
        this.commitTimer = -1;
        this.commitInProgress = false;
      }, 40);
    }, SEARCH_ENGINE_DROP_ANIMATION_MS);
  }

  private reorderDuringDrag(): void {
    const targetIndex = this.resolveDragTargetIndex();
    if (targetIndex < 0 || targetIndex === this.dragCurrentIndex) {
      return;
    }
    this.performReorderFeedback();
    animateTo({
      duration: 170,
      curve: Curve.EaseOut
    }, () => {
      this.dragCurrentIndex = targetIndex;
    });
  }

  private resolveDragTargetIndex(): number {
    if (this.dragOriginalIndex < 0) {
      return -1;
    }
    const movedRows = Math.round(this.dragOffsetY / SEARCH_ENGINE_ROW_STRIDE);
    const maxIndex = Math.max(0, this.engines.length - 1);
    return Math.max(0, Math.min(maxIndex, this.dragOriginalIndex + movedRows));
  }

  private findEngineIndex(engineId: string): number {
    for (let index = 0; index < this.engines.length; index += 1) {
      if (this.engines[index].id === engineId) {
        return index;
      }
    }
    return -1;
  }

  private resolveListHeight(): number {
    const rowCount = this.engines.length;
    return rowCount * SEARCH_ENGINE_ROW_HEIGHT + Math.max(0, rowCount - 1) * SEARCH_ENGINE_DIVIDER_HEIGHT;
  }

  private resolveRowPositionY(engine: SearchEngineRowView): number {
    const index = this.findEngineIndex(engine.id);
    if (this.draggingEngineId === engine.id) {
      return this.dragOriginalIndex * SEARCH_ENGINE_ROW_STRIDE + this.dragOffsetY;
    }
    return this.resolvePreviewIndex(index) * SEARCH_ENGINE_ROW_STRIDE;
  }

  private resolvePreviewIndex(index: number): number {
    if (this.draggingEngineId.length <= 0 ||
      this.dragOriginalIndex < 0 ||
      this.dragCurrentIndex < 0 ||
      index < 0 ||
      index === this.dragOriginalIndex) {
      return index;
    }
    if (this.dragCurrentIndex > this.dragOriginalIndex &&
      index > this.dragOriginalIndex &&
      index <= this.dragCurrentIndex) {
      return index - 1;
    }
    if (this.dragCurrentIndex < this.dragOriginalIndex &&
      index >= this.dragCurrentIndex &&
      index < this.dragOriginalIndex) {
      return index + 1;
    }
    return index;
  }

  private resolveRowAnimationDuration(engine: SearchEngineRowView): number {
    if (this.commitInProgress) {
      return 0;
    }
    if (this.draggingEngineId === engine.id) {
      return this.droppingEngineId === engine.id ? SEARCH_ENGINE_DROP_ANIMATION_MS : 0;
    }
    return 170;
  }

  private resolveDropOffsetY(): number {
    if (this.dragOriginalIndex < 0 || this.dragCurrentIndex < 0) {
      return this.dragOffsetY;
    }
    return (this.dragCurrentIndex - this.dragOriginalIndex) * SEARCH_ENGINE_ROW_STRIDE;
  }

  private clearDragState(): void {
    this.draggingEngineId = '';
    this.droppingEngineId = '';
    this.dragOffsetY = 0;
    this.dragOriginalIndex = -1;
    this.dragCurrentIndex = -1;
  }

  private cancelDropTimer(): void {
    if (this.dropTimer >= 0) {
      clearTimeout(this.dropTimer);
      this.dropTimer = -1;
    }
  }

  private cancelCommitTimer(): void {
    if (this.commitTimer >= 0) {
      clearTimeout(this.commitTimer);
      this.commitTimer = -1;
    }
  }

  private performReorderFeedback(): void {
    const now = Date.now();
    if (now - this.lastReorderFeedbackAt < SEARCH_ENGINE_REORDER_HAPTIC_MIN_INTERVAL_MS) {
      return;
    }
    this.lastReorderFeedbackAt = now;
    vibrator.startVibration({
      type: 'time',
      duration: SEARCH_ENGINE_REORDER_HAPTIC_DURATION_MS
    }, {
      usage: 'touch'
    }).catch((_error: Error) => {
    });
  }

  private resolveEngineRenderKey(engine: SearchEngineRowView): string {
    return `${engine.id}:${engine.isDefault ? '1' : '0'}:${engine.title}`;
  }
}
