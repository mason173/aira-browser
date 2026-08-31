import vibrator from '@ohos.vibrator';
import { ExternalAppSearchTargetId } from '../../../common/models/BrowserModels';
import { AppIconResources } from '../../../core/resources/AppIconResources';
import { BrowserThemeViewState } from '../../../core/theme/BrowserThemeViewState';
import { ExternalAppSearchTarget } from '../../../services/search/ExternalAppSearchService';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';
import {
  SettingsRowPosition,
  SettingsSwitchRow
} from '../settings/SettingsRows';

const EXTERNAL_APP_SEARCH_ROW_HEIGHT: number = 62;
const EXTERNAL_APP_SEARCH_DIVIDER_HEIGHT: number = 1;
const EXTERNAL_APP_SEARCH_SETTINGS_ICON_SIZE: number = 34;
const EXTERNAL_APP_SEARCH_SETTINGS_ICON_RADIUS: number = 10;
const EXTERNAL_APP_SEARCH_ROW_STRIDE: number =
  EXTERNAL_APP_SEARCH_ROW_HEIGHT + EXTERNAL_APP_SEARCH_DIVIDER_HEIGHT;
const EXTERNAL_APP_SEARCH_DROP_ANIMATION_MS: number = 150;
const EXTERNAL_APP_SEARCH_REORDER_HAPTIC_DURATION_MS: number = 18;
const EXTERNAL_APP_SEARCH_REORDER_HAPTIC_MIN_INTERVAL_MS: number = 45;

@Component
export struct ExternalAppSearchTargetList {
  @Prop featureEnabled: boolean = true;
  @Prop selectedTargetIds: ExternalAppSearchTargetId[] = [];
  @Prop targets: ExternalAppSearchTarget[] = [];
  @Prop theme: BrowserThemeViewState;
  @Prop desktopPresentation: boolean = false;
  @State private draggingTargetId: string = '';
  @State private dragOffsetY: number = 0;
  @State private dragOriginalIndex: number = -1;
  @State private dragCurrentIndex: number = -1;
  @State private droppingTargetId: string = '';
  @State private commitInProgress: boolean = false;
  private dropTimer: number = -1;
  private commitTimer: number = -1;
  private lastReorderFeedbackAt: number = 0;
  onTargetEnabledChange: (targetId: ExternalAppSearchTargetId, enabled: boolean) => void =
    (_targetId: ExternalAppSearchTargetId, _enabled: boolean) => {};
  onTargetOrderChange: (targetOrder: ExternalAppSearchTargetId[]) => void =
    (_targetOrder: ExternalAppSearchTargetId[]) => {};

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
        ForEach(this.targets, (target: ExternalAppSearchTarget, index: number) => {
          this.buildTargetRow(target, index, this.targets.length)
        }, (target: ExternalAppSearchTarget) => target.id)
      }
      .width('100%')
      .height(this.resolveListHeight())
    }
  }

  @Builder
  private buildTargetRow(target: ExternalAppSearchTarget, index: number, total: number) {
    Column() {
      SettingsSwitchRow({
        title: target.title,
        desktopPresentation: this.desktopPresentation,
        checked: this.isTargetSelected(target.id),
        imageIcon: AppIconResources.externalAppSearch(target.id),
        imageIconSize: EXTERNAL_APP_SEARCH_SETTINGS_ICON_SIZE,
        imageIconCornerRadius: EXTERNAL_APP_SEARCH_SETTINGS_ICON_RADIUS,
        iconBackgroundColor: this.theme.surfaceBackground,
        rowPosition: this.resolveRowPosition(index, total),
        isEnabled: this.featureEnabled,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        pressedBackgroundColor: this.theme.pressedBackground,
        dragHandleIcon: $r('sys.symbol.line_3_horizontal'),
        dragHandleAccessibilityText: `拖动调整${target.title}顺序`,
        dragHandleBackgroundColor: this.theme.controlBackground,
        onChange: (enabled: boolean) => {
          this.onTargetEnabledChange(target.id, enabled);
        },
        onDragHandleStart: () => {
          this.beginDrag(target);
        },
        onDragHandleUpdate: (event: GestureEvent) => {
          this.updateDrag(target, event);
        },
        onDragHandleEnd: () => {
          this.finishDrag(true);
        },
        onDragHandleCancel: () => {
          this.finishDrag(false);
        }
      })
      .height(EXTERNAL_APP_SEARCH_ROW_HEIGHT)

      if (index < total - 1) {
        SettingsGroupDivider({ dividerColor: this.theme.divider })
      }
    }
    .width('100%')
    .height(this.resolveTargetContainerHeight(index, total))
    .position({
      x: 0,
      y: this.resolveRowPositionY(target)
    })
    .zIndex(this.draggingTargetId === target.id ? 8 : 0)
    .scale({
      x: this.draggingTargetId === target.id ? 1.015 : 1,
      y: this.draggingTargetId === target.id ? 1.015 : 1
    })
    .backgroundColor(this.theme.surfaceBackground)
    .animation({
      duration: this.resolveRowAnimationDuration(target),
      curve: Curve.EaseOut
    })
  }

  private beginDrag(target: ExternalAppSearchTarget): void {
    if (!this.featureEnabled) {
      return;
    }
    this.cancelDropTimer();
    this.cancelCommitTimer();
    this.draggingTargetId = target.id;
    this.droppingTargetId = '';
    this.commitInProgress = false;
    this.dragOffsetY = 0;
    this.dragOriginalIndex = this.findTargetIndex(target.id);
    this.dragCurrentIndex = this.dragOriginalIndex;
  }

  private updateDrag(target: ExternalAppSearchTarget, event: GestureEvent): void {
    if (this.draggingTargetId !== target.id) {
      return;
    }
    this.dragOffsetY = Number(event.offsetY);
    this.reorderDuringDrag();
  }

  private finishDrag(shouldSave: boolean): void {
    const targetId = this.draggingTargetId;
    const targetIndex = this.dragCurrentIndex;
    const originalIndex = this.dragOriginalIndex;
    if (targetId.length > 0 && shouldSave && targetIndex >= 0 &&
      originalIndex >= 0 && targetIndex !== originalIndex) {
      this.dropTargetToIndex(targetId, targetIndex);
      return;
    }
    this.clearDragState();
  }

  private dropTargetToIndex(targetId: string, targetIndex: number): void {
    this.cancelDropTimer();
    this.droppingTargetId = targetId;
    animateTo({
      duration: EXTERNAL_APP_SEARCH_DROP_ANIMATION_MS,
      curve: Curve.EaseOut
    }, () => {
      this.dragOffsetY = this.resolveDropOffsetY();
    });
    this.dropTimer = setTimeout(() => {
      this.dropTimer = -1;
      const nextOrder = this.moveTargetToIndex(targetId, targetIndex);
      this.commitInProgress = true;
      this.clearDragState();
      this.onTargetOrderChange(nextOrder);
      this.commitTimer = setTimeout(() => {
        this.commitTimer = -1;
        this.commitInProgress = false;
      }, 40);
    }, EXTERNAL_APP_SEARCH_DROP_ANIMATION_MS);
  }

  private moveTargetToIndex(targetId: string, targetIndex: number): ExternalAppSearchTargetId[] {
    const nextOrder = this.targets.map((target: ExternalAppSearchTarget): ExternalAppSearchTargetId => target.id);
    const currentIndex = nextOrder.indexOf(targetId as ExternalAppSearchTargetId);
    if (currentIndex < 0 || targetIndex < 0 || targetIndex >= nextOrder.length || currentIndex === targetIndex) {
      return nextOrder;
    }
    const movedTargetIds = nextOrder.splice(currentIndex, 1);
    if (movedTargetIds.length > 0) {
      nextOrder.splice(targetIndex, 0, movedTargetIds[0]);
    }
    return nextOrder;
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
    const movedRows = Math.round(this.dragOffsetY / EXTERNAL_APP_SEARCH_ROW_STRIDE);
    const maxIndex = Math.max(0, this.targets.length - 1);
    return Math.max(0, Math.min(maxIndex, this.dragOriginalIndex + movedRows));
  }

  private findTargetIndex(targetId: string): number {
    for (let index = 0; index < this.targets.length; index += 1) {
      if (this.targets[index].id === targetId) {
        return index;
      }
    }
    return -1;
  }

  private resolveListHeight(): number {
    return this.targets.length * EXTERNAL_APP_SEARCH_ROW_HEIGHT +
      Math.max(0, this.targets.length - 1) * EXTERNAL_APP_SEARCH_DIVIDER_HEIGHT;
  }

  private resolveTargetContainerHeight(index: number, total: number): number {
    return EXTERNAL_APP_SEARCH_ROW_HEIGHT + (index < total - 1 ? EXTERNAL_APP_SEARCH_DIVIDER_HEIGHT : 0);
  }

  private resolveRowPositionY(target: ExternalAppSearchTarget): number {
    const index = this.findTargetIndex(target.id);
    if (this.draggingTargetId === target.id) {
      return this.dragOriginalIndex * EXTERNAL_APP_SEARCH_ROW_STRIDE + this.dragOffsetY;
    }
    return this.resolvePreviewIndex(index) * EXTERNAL_APP_SEARCH_ROW_STRIDE;
  }

  private resolvePreviewIndex(index: number): number {
    if (this.draggingTargetId.length <= 0 || this.dragOriginalIndex < 0 ||
      this.dragCurrentIndex < 0 || index < 0 || index === this.dragOriginalIndex) {
      return index;
    }
    if (this.dragCurrentIndex > this.dragOriginalIndex && index > this.dragOriginalIndex &&
      index <= this.dragCurrentIndex) {
      return index - 1;
    }
    if (this.dragCurrentIndex < this.dragOriginalIndex && index >= this.dragCurrentIndex &&
      index < this.dragOriginalIndex) {
      return index + 1;
    }
    return index;
  }

  private resolveRowAnimationDuration(target: ExternalAppSearchTarget): number {
    if (this.commitInProgress) {
      return 0;
    }
    if (this.draggingTargetId === target.id) {
      return this.droppingTargetId === target.id ? EXTERNAL_APP_SEARCH_DROP_ANIMATION_MS : 0;
    }
    return 170;
  }

  private resolveDropOffsetY(): number {
    if (this.dragOriginalIndex < 0 || this.dragCurrentIndex < 0) {
      return this.dragOffsetY;
    }
    return (this.dragCurrentIndex - this.dragOriginalIndex) * EXTERNAL_APP_SEARCH_ROW_STRIDE;
  }

  private clearDragState(): void {
    this.draggingTargetId = '';
    this.droppingTargetId = '';
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
    if (now - this.lastReorderFeedbackAt < EXTERNAL_APP_SEARCH_REORDER_HAPTIC_MIN_INTERVAL_MS) {
      return;
    }
    this.lastReorderFeedbackAt = now;
    vibrator.startVibration({
      type: 'time',
      duration: EXTERNAL_APP_SEARCH_REORDER_HAPTIC_DURATION_MS
    }, {
      usage: 'touch'
    }).catch((_error: Error) => {
    });
  }

  private isTargetSelected(targetId: ExternalAppSearchTargetId): boolean {
    return this.selectedTargetIds.indexOf(targetId) >= 0;
  }

  private resolveRowPosition(index: number, total: number): SettingsRowPosition {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index >= total - 1) {
      return 'last';
    }
    return 'middle';
  }
}
