import {
  ElementInspectionAction,
  ElementInspectionPresentation
} from '../../../core/browser/ElementInspectionSessionCoordinator';
import { BrowserTopActionPromptState } from '../../../core/browser/BrowserTopFloatingPromptCoordinator';
import {
  BROWSER_WINDOW_SAFE_BOTTOM_INSET_STORAGE_KEY,
  BROWSER_WINDOW_SAFE_CUTOUT_TOP_INSET_STORAGE_KEY,
  BROWSER_WINDOW_SAFE_SYSTEM_TOP_INSET_STORAGE_KEY,
  BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY
} from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveBrowserBottomFloatingMaterialShadowColor } from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { AiraIcon } from '../common/AiraIcon';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor
} from '../common/FloatingGlassMaterialTokens';
import {
  FLOATING_PROMPT_CARD_ANIMATION_MS,
  FLOATING_PROMPT_CARD_HEIGHT,
  FLOATING_PROMPT_CARD_HIDDEN_OFFSET_Y,
  FLOATING_PROMPT_CARD_HORIZONTAL_MARGIN,
  FLOATING_PROMPT_CARD_TOP_GAP
} from '../common/FloatingPromptCard';
import { TopFloatingOverlayHost } from '../common/TopFloatingSurface';
import {
  BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS,
  BrowserBottomSheetSurface,
  BrowserModalBottomOverlay,
  BrowserSheetActionButton,
  BrowserSheetIconButton
} from './BrowserModalBottomSheet';
import { BrowserTopActionPromptCard } from './BrowserTopActionPromptCard';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import {
  BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT,
  resolveBrowserFloatingGlassMaterialTintForMode
} from './BrowserFloatingGlassMaterialTokens';
import { BROWSER_TOP_FLOATING_PROMPT_HOST_Z_INDEX } from './BrowserTopFloatingPromptHost';
import { ElementInspectionCodePreview } from './ElementInspectionCodePreview';
import { MARKDOWN_CODE_BLOCK_BACKGROUND_COLOR } from '../../../services/markdown/MarkdownDocumentViewerService';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  WEB_PAGE_TOOLS_OVERLAY_ANIMATION_DURATION_MS,
  WEB_PAGE_TOOLS_OVERLAY_ENTER_OFFSET_Y
} from './BrowserShellPresentationTokens';

const ELEMENT_INSPECTION_SHEET_HEIGHT: Length = '64%';
const ELEMENT_INSPECTION_CODE_RADIUS: number = 20;
const ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SIZE: number = 36;
const ELEMENT_INSPECTION_CODE_FLOATING_ACTION_ICON_SIZE: number = 20;
const ELEMENT_INSPECTION_CODE_FLOATING_ACTION_MARGIN: number = 10;
const ELEMENT_INSPECTION_CODE_FLOATING_ACTION_ICON_COLOR: ResourceColor = '#FFFFFFFF';
const ELEMENT_INSPECTION_MONOCHROME_ICON_DARK_COLOR: ResourceColor = '#D9000000';
const ELEMENT_INSPECTION_MONOCHROME_ICON_LIGHT_COLOR: ResourceColor = '#F2FFFFFF';
const ELEMENT_INSPECTION_SELECTING_PROMPT_ICON_BACKGROUND_COLOR: ResourceColor = '#FFFFFFFF';
const ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SHADOW_RADIUS: number = 6;
const ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SHADOW_OFFSET_Y: number = 2;
const ELEMENT_INSPECTION_FULLSCREEN_MIN_TOP_PADDING: number = 16;
const ELEMENT_INSPECTION_FULLSCREEN_SAFE_TOP_GAP: number = 12;
const ELEMENT_INSPECTION_MIN_BOTTOM_PADDING: number = 16;
const ELEMENT_INSPECTION_SAFE_BOTTOM_GAP: number = 12;
const ELEMENT_INSPECTION_FULLSCREEN_Z_INDEX: number = BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX + 10;
const ELEMENT_INSPECTION_TOP_HOST_EXTRA_HEIGHT: number = 28;
const ELEMENT_INSPECTION_TOP_BORDER_WIDTH: number = 1.5;
const ELEMENT_INSPECTION_TOP_SHADOW_RADIUS: number = 22;
const ELEMENT_INSPECTION_TOP_SHADOW_OFFSET_Y: number = -3;
const ELEMENT_INSPECTION_SELECTION_MOVE_THRESHOLD: number = 12;

interface ElementInspectionSelectionPoint {
  x: number;
  y: number;
}

@Component
export struct ElementInspectionOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '';
  @LocalStorageProp(BROWSER_WINDOW_SAFE_BOTTOM_INSET_STORAGE_KEY) private storedBottomSafeInsetVp: number = 0;
  @LocalStorageProp(BROWSER_WINDOW_SAFE_SYSTEM_TOP_INSET_STORAGE_KEY) private storedSystemTopInsetVp: number = 0;
  @LocalStorageProp(BROWSER_WINDOW_SAFE_CUTOUT_TOP_INSET_STORAGE_KEY) private storedCutoutTopInsetVp: number = 0;
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private storedTopSafeInsetVp: number = 0;
  @Prop visible: boolean = false;
  @Prop topOffsetVp: number = 0;
  @Prop webLayerLeftVp: number = 0;
  @Prop webLayerTopVp: number = 0;
  @Prop webLayerWidthVp: number = 1;
  @Prop webLayerHeightVp: number = 1;
  @Prop @Watch('handlePresentationChanged') presentation: ElementInspectionPresentation;
  @State private codeFullscreen: boolean = false;
  @State private selectionTouchTracking: boolean = false;
  @State private selectionTouchMoved: boolean = false;
  @State private selectionTouchStartX: number = 0;
  @State private selectionTouchStartY: number = 0;
  @State private selectionMouseTracking: boolean = false;
  @State private selectionMouseMoved: boolean = false;
  @State private selectionMouseStartX: number = 0;
  @State private selectionMouseStartY: number = 0;
  onAction: (action: ElementInspectionAction) => void = (_action: ElementInspectionAction) => {};
  onSelectNormalizedPoint: (normalizedX: number, normalizedY: number) => void =
    (_normalizedX: number, _normalizedY: number) => {};

  build() {
    Stack({ alignContent: this.codeFullscreen ? Alignment.Bottom : Alignment.Top }) {
      if (this.presentation.active && !this.codeFullscreen) {
        this.buildSelectionInputShield()
      }
      if (this.shouldShowDetails()) {
        if (this.codeFullscreen) {
          this.buildFullscreenCodeOverlay()
        } else {
          this.buildDetailsOverlay()
        }
      } else if (this.presentation.active) {
        this.buildSelectingOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.codeFullscreen ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.Transparent)
    .zIndex(this.codeFullscreen ? ELEMENT_INSPECTION_FULLSCREEN_Z_INDEX : BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX)
  }

  @Builder
  private buildSelectionInputShield() {
    Stack()
      .width(Math.max(1, this.webLayerWidthVp))
      .height(Math.max(1, this.webLayerHeightVp))
      .position({
        x: this.webLayerLeftVp,
        y: this.webLayerTopVp
      })
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Block)
      .focusable(false)
      .onTouch((event: TouchEvent): void => {
        this.handleSelectionTouch(event);
      })
      .onMouse((event: MouseEvent): void => {
        this.handleSelectionMouse(event);
      })
  }

  @Builder
  private buildFullscreenCodeOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor(this.storedFloatingSurfaceColor)

      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Column() {
            Text(this.buildNodeTitle())
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily('monospace')
              .fontColor(this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          BrowserSheetIconButton({
            icon: $r('sys.symbol.xmark'),
            iconSize: 17,
            iconColor: this.resolveSheetIconColor(),
            actionEnabled: !this.presentation.busy,
            accessibilityLabel: '关闭元素审查',
            onAction: () => {
              this.onAction('cancel');
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider()
          .color(this.storedDividerColor)

        this.buildCodePreviewSurface()
      }
      .width('100%')
      .height('100%')
      .padding({
        left: APP_STANDARD_HORIZONTAL_PADDING,
        right: APP_STANDARD_HORIZONTAL_PADDING,
        top: this.resolveFullscreenTopPaddingVp(),
        bottom: this.resolveBottomPaddingVp()
      })
      .backgroundColor(this.storedFloatingSurfaceColor)
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    }
    .width('100%')
    .height('90%')
    .align(Alignment.Bottom)
    .borderRadius({
      topLeft: BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS,
      topRight: BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS,
      bottomLeft: 0,
      bottomRight: 0
    })
    .clip(true)
    .opacity(this.visible ? 1 : 0)
    .animation({
      duration: WEB_PAGE_TOOLS_OVERLAY_ANIMATION_DURATION_MS,
      curve: Curve.EaseOut
    })
    .zIndex(ELEMENT_INSPECTION_FULLSCREEN_Z_INDEX)
  }

  @Builder
  private buildSelectingOverlay() {
    Stack({ alignContent: Alignment.Top }) {
      TopFloatingOverlayHost({
        visible: this.visible,
        topOffsetVp: this.topOffsetVp,
        horizontalMarginVp: FLOATING_PROMPT_CARD_HORIZONTAL_MARGIN,
        topGapVp: FLOATING_PROMPT_CARD_TOP_GAP,
        hiddenOffsetYVp: FLOATING_PROMPT_CARD_HIDDEN_OFFSET_Y,
        zIndexValue: 96,
        animationDurationMs: FLOATING_PROMPT_CARD_ANIMATION_MS,
        visibleHitTestMode: HitTestMode.Block
      }) {
        BrowserTopActionPromptCard({
          visible: this.visible,
          state: this.buildSelectingPromptState(),
          showAction: false
        })
      }
    }
    .width('100%')
    .height(this.resolveSelectingHostHeightVp())
    .hitTestBehavior(HitTestMode.Transparent)
    .zIndex(BROWSER_TOP_FLOATING_PROMPT_HOST_Z_INDEX)
  }

  @Builder
  private buildDetailsOverlay() {
    BrowserModalBottomOverlay({
      visible: this.visible,
      dismissOnOutsideTap: false,
      showScrim: false,
      sheetHeight: ELEMENT_INSPECTION_SHEET_HEIGHT,
      enterOffsetY: WEB_PAGE_TOOLS_OVERLAY_ENTER_OFFSET_Y,
      animationDurationMs: WEB_PAGE_TOOLS_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      onDismiss: () => {
        this.onAction('cancel');
      }
    }) {
      BrowserBottomSheetSurface({
        fullHeight: true,
        contentJustifyContent: FlexAlign.Start,
        topPadding: 18,
        bottomPadding: this.resolveBottomPaddingVp(),
        topBorderColor: $r('app.color.surface_outline'),
        topBorderWidth: ELEMENT_INSPECTION_TOP_BORDER_WIDTH,
        shadowRadius: ELEMENT_INSPECTION_TOP_SHADOW_RADIUS,
        shadowColor: $r('app.color.elevation_shadow'),
        shadowOffsetY: ELEMENT_INSPECTION_TOP_SHADOW_OFFSET_Y
      }) {
        Column({ space: 14 }) {
          this.buildHeader()
          this.buildBreadcrumb()
          this.buildNavigationActions()
          Divider()
            .color(this.storedDividerColor)
          this.buildCodeContent()
        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({ minHeight: 0 })
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  @Builder
  private buildHeader() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(this.buildNodeTitle())
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.presentation.helperText)
          .width('100%')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        this.buildMoreActionButton()

        BrowserSheetIconButton({
          airaIconId: 'browser.elementInspection.reselect',
          iconSize: 17,
          iconColor: this.resolveSheetIconColor(),
          actionEnabled: !this.presentation.busy,
          accessibilityLabel: '重新选择元素',
          onAction: () => {
            this.onAction('reselect');
          }
        })

        BrowserSheetIconButton({
          icon: $r('sys.symbol.xmark'),
          iconSize: 17,
          iconColor: this.resolveSheetIconColor(),
          actionEnabled: !this.presentation.busy,
          accessibilityLabel: '关闭元素审查',
          onAction: () => {
            this.onAction('cancel');
          }
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildBreadcrumb() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.presentation.node?.breadcrumb ?? [], (item: string, index: number) => {
          if (index > 0) {
            Text('›')
              .fontSize(12)
              .fontColor(this.storedSecondaryTextColor)
          }
          Text(item)
            .fontSize(12)
            .fontFamily('monospace')
            .fontColor(index === (this.presentation.node?.breadcrumb.length ?? 0) - 1
              ? this.storedAccentColor
              : this.storedSecondaryTextColor)
            .maxLines(1)
        }, (item: string, index: number) => `${index}:${item}`)
      }
      .padding({ left: 2, right: 2 })
    }
    .width('100%')
    .height(28)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildNavigationActions() {
    Row({ space: 8 }) {
      this.buildNavigationButton('父级', this.presentation.node?.hasParent === true, 'navigate_parent')
      this.buildNavigationButton('子级', this.presentation.node?.hasFirstChild === true, 'navigate_first_child')
      this.buildNavigationButton('上一个', this.presentation.node?.hasPreviousSibling === true,
        'navigate_previous_sibling')
      this.buildNavigationButton('下一个', this.presentation.node?.hasNextSibling === true,
        'navigate_next_sibling')
    }
    .width('100%')
  }

  @Builder
  private buildNavigationButton(label: string, available: boolean, action: ElementInspectionAction) {
    BrowserSheetActionButton({
      label: label,
      buttonHeight: 36,
      fontSize: 13,
      actionEnabled: available && !this.presentation.busy,
      onAction: () => {
        if (available && !this.presentation.busy) {
          this.onAction(action);
        }
      }
    })
  }

  @Builder
  private buildCodeContent() {
    Column() {
      this.buildCodePreviewSurface()
    }
    .width('100%')
    .layoutWeight(1)
    .constraintSize({ minHeight: 0 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildCodePreviewSurface() {
    Stack({ alignContent: Alignment.TopEnd }) {
      ElementInspectionCodePreview({
        code: this.resolveHtmlPreview()
      })

      this.buildFloatingFullscreenButton()
    }
    .width('100%')
    .layoutWeight(1)
    .constraintSize({ minHeight: 0 })
    .backgroundColor(MARKDOWN_CODE_BLOCK_BACKGROUND_COLOR)
    .borderRadius(ELEMENT_INSPECTION_CODE_RADIUS)
    .clip(true)
  }

  @Builder
  private buildFloatingFullscreenButton() {
    Stack({ alignContent: Alignment.Center }) {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SIZE,
        surfaceHeight: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SIZE,
        surfaceRadius: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SIZE / 2,
        tintColor: BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT
      }) {
        AiraIcon({
          airaIconId: this.codeFullscreen
            ? 'browser.elementInspection.exitFullscreen'
            : 'browser.elementInspection.fullscreen',
          iconSize: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_ICON_SIZE,
          iconColor: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_ICON_COLOR
        })
        .hitTestBehavior(HitTestMode.None)
      }

      Button()
        .width('100%')
        .height('100%')
        .type(ButtonType.Circle)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .stateEffect(false)
        .focusable(false)
        .enabled(!this.presentation.busy)
        .accessibilityText(this.codeFullscreen ? '收起全屏代码预览' : '全屏查看代码')
        .onClick(() => {
          this.codeFullscreen = !this.codeFullscreen;
        })
    }
      .width(ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SIZE)
      .height(ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SIZE)
      .borderRadius(ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SIZE / 2)
      .shadow(this.resolveFloatingActionShadow())
      .margin({
        top: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_MARGIN,
        right: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_MARGIN
      })
      .align(Alignment.TopEnd)
  }

  @Builder
  private buildMoreActionButton() {
    Stack({ alignContent: Alignment.Center }) {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: 36,
        surfaceHeight: 36,
        surfaceRadius: 18,
        tintColor: resolveBrowserFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        AiraIcon({
          airaIconId: 'browser.toolbar.more',
          iconSize: 17,
          iconColor: this.resolveSheetIconColor()
        })
        .hitTestBehavior(HitTestMode.None)
      }

      Button({ type: ButtonType.Circle })
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .stateEffect(!this.presentation.busy)
        .enabled(!this.presentation.busy)
        .accessibilityText('更多元素操作')
        .bindMenu(this.buildMoreActionMenu())
    }
    .width(36)
    .height(36)
    .borderRadius(18)
  }

  @Builder
  private buildMoreActionMenu() {
    Menu() {
      MenuItem({ content: '复制选择器' })
        .enabled((this.presentation.node?.selector.length ?? 0) > 0 && !this.presentation.busy)
        .onClick(() => {
          this.onAction('copy_selector');
        })
      MenuItem({ content: '复制 HTML' })
        .enabled(!this.presentation.busy)
        .onClick(() => {
          this.onAction('copy_html');
        })
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .systemMaterial(createFloatingGlassMaterialIfAvailable(
      resolveBrowserFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    ))
  }

  private shouldShowDetails(): boolean {
    return this.presentation.active &&
      this.presentation.node !== undefined &&
      (this.presentation.phase === 'inspected' || this.presentation.phase === 'closing');
  }

  private handlePresentationChanged(): void {
    if (!this.shouldShowDetails()) {
      this.codeFullscreen = false;
    }
  }

  private handleSelectionTouch(event: TouchEvent): void {
    event.stopPropagation();
    const point = this.resolveSelectionTouchPoint(event);
    if (event.type === TouchType.Down) {
      this.selectionTouchTracking = point !== undefined;
      this.selectionTouchMoved = false;
      this.selectionTouchStartX = point?.x ?? 0;
      this.selectionTouchStartY = point?.y ?? 0;
      return;
    }
    if (event.type === TouchType.Move && this.selectionTouchTracking && point !== undefined) {
      if (this.hasSelectionPointerMoved(
        this.selectionTouchStartX,
        this.selectionTouchStartY,
        point.x,
        point.y
      )) {
        this.selectionTouchMoved = true;
      }
      return;
    }
    if (event.type === TouchType.Up && this.selectionTouchTracking &&
      !this.selectionTouchMoved && point !== undefined) {
      this.emitNormalizedSelectionPoint(point.x, point.y);
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.selectionTouchTracking = false;
      this.selectionTouchMoved = false;
    }
  }

  private handleSelectionMouse(event: MouseEvent): void {
    event.stopPropagation();
    const pointX = Number(event.x);
    const pointY = Number(event.y);
    if (!Number.isFinite(pointX) || !Number.isFinite(pointY)) {
      return;
    }
    if (event.action === MouseAction.Press) {
      this.selectionMouseTracking = event.button === MouseButton.Left;
      this.selectionMouseMoved = false;
      this.selectionMouseStartX = pointX;
      this.selectionMouseStartY = pointY;
      return;
    }
    if (event.action === MouseAction.Move && this.selectionMouseTracking) {
      if (this.hasSelectionPointerMoved(
        this.selectionMouseStartX,
        this.selectionMouseStartY,
        pointX,
        pointY
      )) {
        this.selectionMouseMoved = true;
      }
      return;
    }
    if (event.action === MouseAction.Release) {
      if (this.selectionMouseTracking && !this.selectionMouseMoved) {
        this.emitNormalizedSelectionPoint(pointX, pointY);
      }
      this.selectionMouseTracking = false;
      this.selectionMouseMoved = false;
    }
  }

  private resolveSelectionTouchPoint(event: TouchEvent): ElementInspectionSelectionPoint | undefined {
    const touch = event.touches.length > 0 ? event.touches[0] : event.changedTouches[0];
    if (touch === undefined) {
      return undefined;
    }
    const x = Number(touch.x);
    const y = Number(touch.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      return undefined;
    }
    const point: ElementInspectionSelectionPoint = { x: x, y: y };
    return point;
  }

  private emitNormalizedSelectionPoint(localXVp: number, localYVp: number): void {
    const widthVp = Math.max(1, this.webLayerWidthVp);
    const heightVp = Math.max(1, this.webLayerHeightVp);
    const normalizedX = Math.min(1, Math.max(0, localXVp / widthVp));
    const normalizedY = Math.min(1, Math.max(0, localYVp / heightVp));
    this.onSelectNormalizedPoint(normalizedX, normalizedY);
  }

  private hasSelectionPointerMoved(startX: number, startY: number, currentX: number, currentY: number): boolean {
    return Math.abs(currentX - startX) > ELEMENT_INSPECTION_SELECTION_MOVE_THRESHOLD ||
      Math.abs(currentY - startY) > ELEMENT_INSPECTION_SELECTION_MOVE_THRESHOLD;
  }

  private buildSelectingPromptState(): BrowserTopActionPromptState {
    return {
      visible: this.visible && this.presentation.active,
      key: this.resolveSelectingPromptKey(),
      topOffsetVp: this.topOffsetVp,
      title: this.presentation.phase === 'starting' ? '正在启动元素审查' : '选择网页元素',
      subtitle: this.presentation.helperText,
      fallbackLabel: '审',
      iconUri: '',
      airaIconId: 'browser.toolbar.actionElementInspection',
      iconColor: ELEMENT_INSPECTION_MONOCHROME_ICON_DARK_COLOR,
      iconBackgroundColor: ELEMENT_INSPECTION_SELECTING_PROMPT_ICON_BACKGROUND_COLOR,
      actionText: '取消'
    };
  }

  private resolveSheetIconColor(): ResourceColor {
    const brightness = this.resolveHexBrightness(this.storedControlBackgroundColor);
    if (brightness >= 0 && brightness < 128) {
      return ELEMENT_INSPECTION_MONOCHROME_ICON_LIGHT_COLOR;
    }
    return ELEMENT_INSPECTION_MONOCHROME_ICON_DARK_COLOR;
  }

  private resolveHexBrightness(hexColor: string): number {
    let normalized = hexColor.trim();
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    if (normalized.length === 8) {
      normalized = normalized.substring(2);
    }
    if (normalized.length !== 6) {
      return -1;
    }
    const red = parseInt(normalized.substring(0, 2), 16);
    const green = parseInt(normalized.substring(2, 4), 16);
    const blue = parseInt(normalized.substring(4, 6), 16);
    if (!Number.isFinite(red) || !Number.isFinite(green) || !Number.isFinite(blue)) {
      return -1;
    }
    return (red * 299 + green * 587 + blue * 114) / 1000;
  }

  private resolveSelectingPromptKey(): string {
    return `element-inspection:${this.presentation.phase}`;
  }

  private resolveSelectingHostHeightVp(): number {
    return this.topOffsetVp + FLOATING_PROMPT_CARD_TOP_GAP + FLOATING_PROMPT_CARD_HEIGHT +
      ELEMENT_INSPECTION_TOP_HOST_EXTRA_HEIGHT;
  }

  private buildNodeTitle(): string {
    const node = this.presentation.node;
    if (node === undefined) {
      return '<element>';
    }
    let value = `<${node.tagName}`;
    if (node.elementId.length > 0) {
      value += `#${node.elementId}`;
    }
    const classLimit = Math.min(node.classTokens.length, 2);
    for (let index = 0; index < classLimit; index += 1) {
      value += `.${node.classTokens[index]}`;
    }
    return `${value}>`;
  }

  private resolveHtmlPreview(): string {
    const preview = this.presentation.node?.htmlPreview ?? '';
    return preview.length > 0 ? preview : '当前元素没有可显示的 HTML。';
  }

  private resolveFullscreenTopPaddingVp(): number {
    const safeTopInsetVp = Math.max(
      this.storedTopSafeInsetVp,
      this.storedSystemTopInsetVp,
      this.storedCutoutTopInsetVp
    );
    return Math.max(
      ELEMENT_INSPECTION_FULLSCREEN_MIN_TOP_PADDING,
      Math.ceil(safeTopInsetVp) + ELEMENT_INSPECTION_FULLSCREEN_SAFE_TOP_GAP
    );
  }

  private resolveBottomPaddingVp(): number {
    return Math.max(
      ELEMENT_INSPECTION_MIN_BOTTOM_PADDING,
      Math.ceil(this.storedBottomSafeInsetVp) + ELEMENT_INSPECTION_SAFE_BOTTOM_GAP
    );
  }

  private resolveFloatingActionShadow(): ShadowOptions {
    return {
      radius: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SHADOW_RADIUS,
      color: resolveBrowserBottomFloatingMaterialShadowColor('dark'),
      offsetX: 0,
      offsetY: ELEMENT_INSPECTION_CODE_FLOATING_ACTION_SHADOW_OFFSET_Y
    };
  }
}
