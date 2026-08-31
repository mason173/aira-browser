import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import {
  FLOATING_PROMPT_CARD_ACTION_HEIGHT,
  FLOATING_PROMPT_CARD_ANIMATION_MS,
  FLOATING_PROMPT_CARD_HEIGHT,
  FLOATING_PROMPT_CARD_HIDDEN_OFFSET_Y,
  FLOATING_PROMPT_CARD_TOP_GAP
} from '../common/FloatingPromptCard';
import {
  TOP_FLOATING_OVERLAY_ENTRY_CURVE,
  TopFloatingSurface
} from '../common/TopFloatingSurface';
import {
  ManualElementHideSelectionAction,
  ManualElementHideSelectionPresentation
} from '../../../core/adblock/ManualElementHideRuntimeCoordinator';

const MANUAL_ELEMENT_HIDE_BAR_HEIGHT: number = FLOATING_PROMPT_CARD_HEIGHT + 20;
const MANUAL_ELEMENT_HIDE_BAR_MAX_WIDTH: number = 372;
const MANUAL_ELEMENT_HIDE_BAR_MIN_TOP: number = FLOATING_PROMPT_CARD_TOP_GAP;
const MANUAL_ELEMENT_HIDE_BAR_MIN_LEFT: number = 8;
const MANUAL_ELEMENT_HIDE_BAR_PAN_DISTANCE: number = 3;
const MANUAL_ELEMENT_HIDE_COUNT_BADGE_SIZE: number = FLOATING_PROMPT_CARD_ACTION_HEIGHT;

@Component
export struct ManualElementHideSelectionOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Watch('syncHostHeight')
  @Prop rootViewportWidth: number = 390;
  @Watch('syncHostHeight')
  @Prop rootViewportHeight: number = 0;
  @Watch('syncHostHeight')
  @Prop topOffsetVp: number = 0;
  @Prop
  @Watch('syncPresentation')
  presentation: ManualElementHideSelectionPresentation = {
    active: false,
    selectedCount: 0,
    selectedElementSelector: '',
    host: '',
    busy: false
  };
  zIndexValue: number = 0;
  onAction: (action: ManualElementHideSelectionAction) => void =
    (_action: ManualElementHideSelectionAction) => {};
  @State private barTop: number = 0;
  @State private barLeft: number = 0;
  @State private presented: boolean = false;
  @State private selectedElementSelector: string = '';
  private dragStartTop: number = 0;
  private dragStartLeft: number = 0;
  private presentationTimer: number = 0;

  aboutToAppear(): void {
    this.syncHostHeight();
    this.syncPresentation();
    this.syncPresentedState();
  }

  aboutToDisappear(): void {
    this.clearPresentationTimer();
  }

  build() {
    Column() {
      Column() {
        TopFloatingSurface({
          heightVp: MANUAL_ELEMENT_HIDE_BAR_HEIGHT,
          paddingLeftVp: 12,
          paddingRightVp: 10,
          paddingTopVp: 9,
          paddingBottomVp: 9
        }) {
          Column({ space: 6 }) {
            Text(this.buildSelectedElementLabel())
              .width('100%')
              .fontSize(12)
              .fontWeight(FontWeight.Regular)
              .fontColor(this.storedSecondaryTextColor)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row({ space: 8 }) {
              this.buildSelectionCountBadge()

              this.buildTextButton('扩大', true, false, () => {
                this.onAction('navigate_parent');
              })

              this.buildTextButton('缩小', true, false, () => {
                this.onAction('navigate_child');
              })

              this.buildTextButton('取消', true, false, () => {
                this.onAction('cancel');
              })

              this.buildTextButton('完成', true, true, () => {
                this.onAction('finish');
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .opacity(this.presented ? 1 : 0)
      .translate({ y: this.presented ? 0 : FLOATING_PROMPT_CARD_HIDDEN_OFFSET_Y })
      .animation({
        duration: FLOATING_PROMPT_CARD_ANIMATION_MS,
        curve: TOP_FLOATING_OVERLAY_ENTRY_CURVE
      })
    }
    .width(this.resolveBarWidth())
    .position({ x: this.resolveBarLeft(), y: this.resolveBarTop() })
    .zIndex(this.zIndexValue)
    .accessibilityText(this.buildAccessibilityText())
    .gesture(
      PanGesture({ direction: PanDirection.All, distance: MANUAL_ELEMENT_HIDE_BAR_PAN_DISTANCE })
        .onActionStart(() => {
          this.dragStartTop = this.resolveBarTop();
          this.dragStartLeft = this.resolveBarLeft();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateDragPosition(event);
        })
        .onActionEnd(() => {
          this.dragStartTop = this.resolveBarTop();
          this.dragStartLeft = this.resolveBarLeft();
        })
        .onActionCancel(() => {
          this.dragStartTop = this.resolveBarTop();
          this.dragStartLeft = this.resolveBarLeft();
        }),
      GestureMask.Normal
    )
  }

  @Builder
  private buildSelectionCountBadge() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: MANUAL_ELEMENT_HIDE_COUNT_BADGE_SIZE,
        surfaceHeight: MANUAL_ELEMENT_HIDE_COUNT_BADGE_SIZE,
        surfaceRadius: MANUAL_ELEMENT_HIDE_COUNT_BADGE_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Text(`${this.presentation.selectedCount}`)
          .fontSize(this.presentation.selectedCount >= 100 ? 11 : 13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
      }
    }
    .width(MANUAL_ELEMENT_HIDE_COUNT_BADGE_SIZE)
    .height(MANUAL_ELEMENT_HIDE_COUNT_BADGE_SIZE)
    .borderRadius(MANUAL_ELEMENT_HIDE_COUNT_BADGE_SIZE / 2)
    .accessibilityText(`已选择 ${this.presentation.selectedCount} 个元素`)
  }

  @Builder
  private buildTextButton(label: string, enabled: boolean, primary: boolean, action: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: FLOATING_PROMPT_CARD_ACTION_HEIGHT,
        surfaceRadius: FLOATING_PROMPT_CARD_ACTION_HEIGHT / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        overlayColor: this.storedAccentColor,
        overlayOpacity: primary ? 1 : 0
      }) {
        Button(label)
          .width('100%')
          .height('100%')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(primary ? this.storedOnAccentColor : this.storedAccentColor)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .borderRadius(FLOATING_PROMPT_CARD_ACTION_HEIGHT / 2)
          .stateEffect(true)
          .enabled(enabled && !this.presentation.busy)
          .onClick(() => {
            action();
          })
      }
    }
    .height(FLOATING_PROMPT_CARD_ACTION_HEIGHT)
    .layoutWeight(1)
    .opacity(enabled && !this.presentation.busy ? 1 : 0.42)
  }

  private syncHostHeight(): void {
    this.barTop = this.clampTop(this.resolveDefaultTop());
    this.barLeft = this.clampLeft(this.resolveDefaultLeft());
    this.dragStartTop = this.barTop;
    this.dragStartLeft = this.barLeft;
  }

  private syncPresentation(): void {
    const nextSelector = `${this.presentation.selectedElementSelector ?? ''}`.trim();
    this.selectedElementSelector = nextSelector;
  }

  private updateDragPosition(event: GestureEvent): void {
    const offsetY = Number(event.offsetY);
    if (Number.isFinite(offsetY)) {
      this.barTop = this.clampTop(this.dragStartTop + offsetY);
    }
    const offsetX = Number(event.offsetX);
    if (Number.isFinite(offsetX)) {
      this.barLeft = this.clampLeft(this.dragStartLeft + offsetX);
    }
  }

  private resolveBarTop(): number {
    if (this.barTop > 0) {
      return this.clampTop(this.barTop);
    }
    return this.clampTop(this.resolveDefaultTop());
  }

  private resolveDefaultTop(): number {
    return this.resolveMinTop();
  }

  private resolveBarLeft(): number {
    if (this.barLeft > 0) {
      return this.clampLeft(this.barLeft);
    }
    return this.clampLeft(this.resolveDefaultLeft());
  }

  private resolveDefaultLeft(): number {
    return Math.max(MANUAL_ELEMENT_HIDE_BAR_MIN_LEFT, (this.rootViewportWidth - this.resolveBarWidth()) / 2);
  }

  private clampTop(value: number): number {
    const minTop = this.resolveMinTop();
    const maxTop = Math.max(
      minTop,
      this.rootViewportHeight - MANUAL_ELEMENT_HIDE_BAR_HEIGHT - minTop
    );
    return Math.min(Math.max(minTop, value), maxTop);
  }

  private clampLeft(value: number): number {
    const barWidth = this.resolveBarWidth();
    const maxLeft = Math.max(MANUAL_ELEMENT_HIDE_BAR_MIN_LEFT, this.rootViewportWidth - barWidth);
    return Math.min(Math.max(MANUAL_ELEMENT_HIDE_BAR_MIN_LEFT, value), maxLeft);
  }

  private resolveBarWidth(): number {
    const availableWidth = Math.max(1, this.rootViewportWidth - MANUAL_ELEMENT_HIDE_BAR_MIN_LEFT * 2);
    return Math.min(availableWidth, MANUAL_ELEMENT_HIDE_BAR_MAX_WIDTH);
  }

  private resolveMinTop(): number {
    return Math.max(MANUAL_ELEMENT_HIDE_BAR_MIN_TOP, this.topOffsetVp + FLOATING_PROMPT_CARD_TOP_GAP);
  }

  private syncPresentedState(): void {
    this.clearPresentationTimer();
    this.presented = false;
    this.presentationTimer = setTimeout(() => {
      this.presentationTimer = 0;
      this.presented = true;
    }, 24);
  }

  private clearPresentationTimer(): void {
    if (this.presentationTimer !== 0) {
      clearTimeout(this.presentationTimer);
      this.presentationTimer = 0;
    }
  }

  private buildAccessibilityText(): string {
    const targetHost = this.presentation.host.length > 0 ? this.presentation.host : '当前网站';
    const selectedElement = this.selectedElementSelector.length > 0
      ? `，当前选择器 ${this.selectedElementSelector}`
      : '';
    return `标记广告工具栏，${targetHost}，已选择 ${this.presentation.selectedCount} 个元素${selectedElement}`;
  }

  private buildSelectedElementLabel(): string {
    return this.selectedElementSelector.length > 0
      ? this.selectedElementSelector
      : '尚未选择元素';
  }
}
