import {
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { AiraIcon } from '../common/AiraIcon';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import { BrowserSheetResponsiveLayoutViewModel } from '../../../core/browser/BrowserSheetResponsiveLayoutViewModel';
import {
  DESKTOP_DIALOG_ACTION_FONT_SIZE_FP,
  DESKTOP_DIALOG_ACTION_HEIGHT_VP,
  DESKTOP_DIALOG_DESTRUCTIVE_FILL,
  DESKTOP_DIALOG_DESTRUCTIVE_TEXT,
  DESKTOP_DIALOG_SECONDARY_FILL,
  DesktopDialogTier
} from '../../../core/browser/BrowserDialogPresentationTokens';
import { DesktopDialogWidthViewModel } from '../../../core/browser/DesktopDialogWidthViewModel';
import { isLargeScreenDialogShell } from '../common/DesktopDialogSheetChrome';

export const BROWSER_MODAL_BOTTOM_SHEET_Z_INDEX: number = 220;
export const BROWSER_MODAL_BOTTOM_SHEET_ENTER_OFFSET_Y: number = 48;
export const BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS: number = 220;
export const BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS: number = 0;
export const BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS: number = 28;
export const BROWSER_MODAL_BOTTOM_SHEET_HORIZONTAL_PADDING: number = APP_STANDARD_HORIZONTAL_PADDING;
export const BROWSER_MODAL_BOTTOM_SHEET_TOP_PADDING: number = 26;
export const BROWSER_MODAL_BOTTOM_SHEET_BOTTOM_PADDING: number = 24;
export const BROWSER_MODAL_BOTTOM_SHEET_ACTION_HEIGHT: number = 44;
export const BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS: number = 20;
export const BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING: number = 24;
export const BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE: number = 110;
/** Half-modal title bar: 8vp top padding, 56vp bar, 64vp backplate. */
export const BROWSER_SHEET_MODAL_TOP_PADDING: number = 8;
export const BROWSER_SHEET_MODAL_TITLE_BAR_HEIGHT: number = 56;
export const BROWSER_SHEET_MODAL_HEADER_BUTTON_TOP: number = BROWSER_SHEET_MODAL_TOP_PADDING +
  (BROWSER_SHEET_MODAL_TITLE_BAR_HEIGHT - 40) / 2;
export const BROWSER_SHEET_BLUR_SCROLL_RANGE_VP: number = 8;
export const BROWSER_IMMERSIVE_SHEET_HEADER_TOP_INSET: number = BROWSER_SHEET_MODAL_TOP_PADDING;
export const BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET: number =
  BROWSER_SHEET_MODAL_TOP_PADDING + BROWSER_SHEET_MODAL_TITLE_BAR_HEIGHT;
export const BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE: number = 40;
export const BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE: number = 20;
export const BROWSER_FEATURE_SHEET_HEADER_TITLE_SIZE: number = 21;
export const BROWSER_FEATURE_SHEET_HEADER_ROW_HEIGHT: number = BROWSER_SHEET_MODAL_TITLE_BAR_HEIGHT;

const BROWSER_SHEET_HEADER_BLUR_STOPS: Array<[number, number]> = [[1, 0], [1, 0.05], [0, 0.14], [0, 1]];

/**
 * Blur stays off at rest and finishes within the first 8vp of upward scroll.
 * Pass the Scroll or List's currentOffset().yOffset, not an accumulated frame delta.
 * Apply the result with browserSheetHeaderBlurModifier on that scroller. A parent
 * wrapper does not blur a scrolling child, and attaching linearGradientBlur at
 * radius 0 still creates a blur node, so the modifier omits it until the radius
 * is above 0.
 */
export function resolveBrowserSheetHeaderBlurRadius(offset: number): number {
  if (!Number.isFinite(offset) || offset <= 0) {
    return 0;
  }
  const progress = Math.min(1, offset / BROWSER_SHEET_BLUR_SCROLL_RANGE_VP);
  return BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS * progress;
}

/** Skips the blur node entirely while the title area is at rest. */
export class BrowserSheetHeaderBlurModifier implements AttributeModifier<CommonAttribute> {
  private readonly radius: number;
  private readonly fractionStops: Array<[number, number]>;

  constructor(radius: number, fractionStops?: Array<[number, number]>) {
    this.radius = radius;
    this.fractionStops = fractionStops !== undefined ? fractionStops : BROWSER_SHEET_HEADER_BLUR_STOPS;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (this.radius <= 0) {
      return;
    }
    instance.linearGradientBlur(this.radius, {
      fractionStops: this.fractionStops,
      direction: GradientDirection.Bottom
    });
  }
}

export function browserSheetHeaderBlurModifier(
  radius: number,
  fractionStops?: Array<[number, number]>
): BrowserSheetHeaderBlurModifier {
  return new BrowserSheetHeaderBlurModifier(radius, fractionStops);
}
const BROWSER_MODAL_BOTTOM_OVERLAY_LOCAL_REVEAL_DELAY_MS: number = 16;

export type BrowserBottomSheetSurfacePresentation = 'bottom_sheet' | 'flat_content';

@Component
export struct BrowserModalBottomOverlay {
  @State private presentationVisible: boolean = false;
  private revealTimer: number = -1;
  @Prop @Watch('syncVisible') visible: boolean = false;
  @Prop dismissOnOutsideTap: boolean = true;
  @Prop showScrim: boolean = true;
  /**
   * Where the sheet lane sits in the viewport. Bottom keeps the standard sheet
   * anchor; a centered lane presents the same content as a floating card.
   */
  @Prop sheetAlignment: Alignment = Alignment.Bottom;
  @Prop tier: DesktopDialogTier = 'm';
  sheetHeight: Length = '';
  @State private viewportWidthVp: number = 0;
  @State private viewportHeightVp: number = 0;
  private readonly desktopDialogWidthViewModel: DesktopDialogWidthViewModel =
    new DesktopDialogWidthViewModel();
  zIndexValue: number = BROWSER_MODAL_BOTTOM_SHEET_Z_INDEX;
  animationDurationMs: number = BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS;
  enterOffsetY: number = BROWSER_MODAL_BOTTOM_SHEET_ENTER_OFFSET_Y;
  onDismiss: () => void = () => {};
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.presentationVisible = false;
    this.syncVisible();
  }

  aboutToDisappear(): void {
    this.clearRevealTimer();
  }

  build() {
    Stack({ alignContent: this.shouldPresentCentered() ? Alignment.Center : this.sheetAlignment }) {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor(this.showScrim ? $r('app.color.browser_overlay_scrim') : Color.Transparent)
        .opacity(this.presentationVisible && this.showScrim ? 1 : 0)
        .animation({
          duration: this.animationDurationMs,
          curve: Curve.EaseOut
        })
        // A scrim that does not dismiss must still swallow the tap, otherwise the press
        // lands on the page behind the modal and the user interacts with what they cannot see.
        .hitTestBehavior(this.presentationVisible
          ? (this.dismissOnOutsideTap ? HitTestMode.Default : HitTestMode.Block)
          : HitTestMode.None)
        .onClick(() => {
          if (this.dismissOnOutsideTap) {
            this.onDismiss();
          }
        })

      if (this.shouldPresentCentered()) {
        this.buildCenteredCard()
      } else {
        this.buildBottomCard()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewportSize(newArea);
    })
    .hitTestBehavior(this.presentationVisible
      ? (this.dismissOnOutsideTap ? HitTestMode.Default : HitTestMode.Transparent)
      : HitTestMode.None)
    .zIndex(this.zIndexValue)
  }

  @Builder
  private buildBottomCard() {
    Column() {
      this.content()
    }
    .width('100%')
    .height(this.sheetHeight)
    .opacity(this.presentationVisible ? 1 : 0)
    .translate({ y: this.presentationVisible ? 0 : this.enterOffsetY })
    .animation({
      duration: this.animationDurationMs,
      curve: this.presentationVisible ? 'interpolatingSpring(0, 1, 360, 30)' : Curve.EaseIn
    })
    .hitTestBehavior(this.presentationVisible
      ? (this.dismissOnOutsideTap ? HitTestMode.Default : HitTestMode.BLOCK_HIERARCHY)
      : HitTestMode.None)
  }

  @Builder
  private buildCenteredCard() {
    Column() {
      this.content()
    }
    .width(this.resolveCenteredWidth())
    .constraintSize({ maxHeight: this.resolveCenteredMaxHeight() })
    .backgroundColor(this.resolveCenteredSurfaceColor())
    .borderRadius(this.resolveCenteredRadius())
    .clip(true)
    .shadow({ radius: 28, color: '#21101420', offsetX: 0, offsetY: 8 })
    .opacity(this.presentationVisible ? 1 : 0)
    .animation({ duration: 120, curve: Curve.EaseOut })
    .hitTestBehavior(this.presentationVisible
      ? (this.dismissOnOutsideTap ? HitTestMode.Default : HitTestMode.BLOCK_HIERARCHY)
      : HitTestMode.None)
    .keyboardShortcut(FunctionKey.ESC, [], (): void => {
      if (this.dismissOnOutsideTap) {
        this.onDismiss();
      }
    })
  }

  private shouldPresentCentered(): boolean {
    return this.sheetAlignment === Alignment.Bottom && isLargeScreenDialogShell();
  }

  private resolveCenteredWidth(): number {
    return this.desktopDialogWidthViewModel.resolve(
      this.tier, this.viewportWidthVp, this.viewportHeightVp).widthVp;
  }

  private resolveCenteredMaxHeight(): number {
    return this.desktopDialogWidthViewModel.resolve(
      this.tier, this.viewportWidthVp, this.viewportHeightVp).maxHeightVp;
  }

  private resolveCenteredRadius(): number {
    return this.desktopDialogWidthViewModel.resolve(
      this.tier, this.viewportWidthVp, this.viewportHeightVp).cornerRadiusVp;
  }

  private resolveCenteredSurfaceColor(): ResourceColor {
    const storedColor = AppStorage.get<string>(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY);
    if (storedColor === undefined || storedColor.length === 0) {
      return $r('app.color.surface_floating_background');
    }
    return storedColor;
  }

  private updateViewportSize(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0 && width !== this.viewportWidthVp) {
      this.viewportWidthVp = width;
    }
    if (Number.isFinite(height) && height > 0 && height !== this.viewportHeightVp) {
      this.viewportHeightVp = height;
    }
  }

  private syncVisible(): void {
    this.clearRevealTimer();
    if (!this.visible) {
      this.presentationVisible = false;
      return;
    }
    this.presentationVisible = false;
    this.revealTimer = setTimeout(() => {
      this.revealTimer = -1;
      if (this.visible) {
        this.presentationVisible = true;
      }
    }, BROWSER_MODAL_BOTTOM_OVERLAY_LOCAL_REVEAL_DELAY_MS);
  }

  private clearRevealTimer(): void {
    if (this.revealTimer < 0) {
      return;
    }
    clearTimeout(this.revealTimer);
    this.revealTimer = -1;
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct BrowserBottomSheetSurface {
  private responsiveLayoutViewModel: BrowserSheetResponsiveLayoutViewModel =
    new BrowserSheetResponsiveLayoutViewModel();
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @Prop fullHeight: boolean = false;
  @Prop presentation: BrowserBottomSheetSurfacePresentation = 'bottom_sheet';
  @Prop contentJustifyContent: FlexAlign = FlexAlign.Center;
  @Prop horizontalPadding: number = BROWSER_MODAL_BOTTOM_SHEET_HORIZONTAL_PADDING;
  @Prop topPadding: number = BROWSER_MODAL_BOTTOM_SHEET_TOP_PADDING;
  @Prop bottomPadding: number = BROWSER_MODAL_BOTTOM_SHEET_BOTTOM_PADDING;
  @Prop topCornerRadius: number = BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS;
  @Prop topBorderColor: ResourceColor = Color.Transparent;
  @Prop topBorderWidth: number = 0;
  @Prop shadowRadius: number = 0;
  @Prop shadowColor: ResourceColor = Color.Transparent;
  @Prop shadowOffsetY: number = 0;
  @Prop surfaceColor: ResourceColor = '';
  @Prop maxWidth: number = 0;
  @State private containerWidth: number = 390;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Column({ space: 0 }) {
      Column() {
        this.content()
      }
      .width('100%')
      .height(this.fullHeight ? '100%' : '')
      .constraintSize(this.resolveConstraintSize())
      .justifyContent(this.contentJustifyContent)
      .padding({
        left: this.horizontalPadding,
        right: this.horizontalPadding,
        top: this.topPadding,
        bottom: this.bottomPadding
      })
      .backgroundColor(this.presentation === 'flat_content' ? Color.Transparent : this.resolveSurfaceColor())
      // Immersive sheets blur the top edge. FAST corner clipping samples the mask there.
      .borderRadius({
        topLeft: this.presentation === 'flat_content' ? 0 : this.topCornerRadius,
        topRight: this.presentation === 'flat_content' ? 0 : this.topCornerRadius,
        bottomLeft: 0,
        bottomRight: 0
      }, this.presentation === 'flat_content' ? RenderStrategy.FAST : RenderStrategy.OFFSCREEN)
      .border({
        width: { top: this.presentation === 'flat_content' ? 0 : this.topBorderWidth },
        color: this.topBorderColor
      })
      .shadow({
        radius: this.presentation === 'flat_content' ? 0 : this.shadowRadius,
        color: this.shadowColor,
        offsetX: 0,
        offsetY: this.presentation === 'flat_content' ? 0 : this.shadowOffsetY
      })
      .clip(true)
    }
    .width('100%')
    .height(this.fullHeight ? '100%' : '')
    .backgroundColor(Color.Transparent)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const nextWidth = Math.max(1, Math.round(this.parseAreaDimension(newArea.width)));
      if (nextWidth !== this.containerWidth) {
        this.containerWidth = nextWidth;
      }
    })
  }

  private resolveSurfaceColor(): ResourceColor {
    return `${this.surfaceColor}`.length > 0 ? this.surfaceColor : this.storedFloatingSurfaceColor;
  }

  private resolveConstraintSize(): ConstraintSizeOptions {
    if (this.presentation === 'flat_content') {
      return {};
    }
    const surfaceMaxWidth = this.responsiveLayoutViewModel.buildState({
      containerWidth: this.containerWidth,
      explicitMaxWidth: this.maxWidth
    }).surfaceMaxWidth;
    if (surfaceMaxWidth > 0) {
      return { maxWidth: surfaceMaxWidth };
    }
    return {};
  }

  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct BrowserImmersiveSheetLayout {
  @Prop headerTopInset: number = BROWSER_IMMERSIVE_SHEET_HEADER_TOP_INSET;
  @Prop horizontalPadding: number = BROWSER_MODAL_BOTTOM_SHEET_HORIZONTAL_PADDING;
  @Prop footerBottomPadding: number = BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING;
  @Prop footerVisible: boolean = false;
  @Prop closeVisible: boolean = false;
  @Prop closeAccessibilityLabel: string = '关闭';
  onClose: () => void = () => {};
  @BuilderParam scrollContent: () => void = this.emptyContent;
  @BuilderParam header: () => void = this.emptyContent;
  @BuilderParam footer: () => void = this.emptyContent;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          this.scrollContent()
        }
        .width('100%')
        .height('100%')

        Column() {
          this.header()
        }
        .width('100%')
        .padding({
          left: this.horizontalPadding,
          right: this.horizontalPadding,
          top: this.headerTopInset
        })
        .zIndex(2)
      }
      .width('100%')
      .height('100%')

      if (this.footerVisible) {
        Row() {
          this.footer()
        }
        .width('100%')
        .padding({
          left: this.horizontalPadding,
          right: this.horizontalPadding,
          bottom: this.footerBottomPadding
        })
        .zIndex(3)
      }

      if (this.closeVisible) {
        Stack({ alignContent: Alignment.TopEnd }) {
          BrowserSheetIconButton({
            icon: $r('sys.symbol.xmark'),
            iconSize: BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE,
            buttonSize: BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE,
            accessibilityLabel: this.closeAccessibilityLabel,
            immersiveMaterialEnabled: true,
            onAction: (): void => {
              this.onClose();
            }
          })
            .margin({ top: BROWSER_SHEET_MODAL_HEADER_BUTTON_TOP, right: 16 })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(4)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct BrowserSheetActionButton {
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop label: string = '';
  @Prop emphasis: 'primary' | 'secondary' | 'destructive' = 'secondary';
  @Prop actionEnabled: boolean = true;
  @Prop accentColor: ResourceColor = '';
  @Prop textColor: ResourceColor = '';
  @Prop fillAvailableWidth: boolean = true;
  /** Set by callers that stack actions in a Column, where no width weight is wanted. */
  @Prop stacked: boolean = false;
  @Prop buttonWidth: Length = 56;
  @Prop buttonHeight: number = BROWSER_MODAL_BOTTOM_SHEET_ACTION_HEIGHT;
  @Prop fontSize: number = 16;
  @Prop loading: boolean = false;
  onAction: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.useFlatFill()) {
        Button() {
          this.buildButtonLabel()
        }
          .width('100%')
          .height('100%')
          .type(ButtonType.Normal)
          .backgroundColor(this.resolveFlatFill())
          .borderRadius(this.resolveRenderedHeight() / 2)
          .stateEffect(this.actionEnabled)
          .enabled(this.actionEnabled)
          .onClick(() => {
            this.onAction();
          })
      } else {
        FloatingGlassMaterialSurface({
          surfaceWidth: '100%',
          surfaceHeight: this.resolveRenderedHeight(),
          surfaceRadius: this.resolveRenderedHeight() / 2,
          tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
          overlayColor: this.resolveOverlayColor(),
          overlayOpacity: this.emphasis === 'primary' ? 1 : 0
        }) {
          Button() {
            this.buildButtonLabel()
          }
            .width('100%')
            .height('100%')
            .type(ButtonType.Normal)
            .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
            .borderRadius(this.resolveRenderedHeight() / 2)
            .stateEffect(this.actionEnabled)
            .enabled(this.actionEnabled)
            .onClick(() => {
              this.onAction();
            })
        }
      }
    }
    .width(this.fillAvailableWidth ? '100%' : this.buttonWidth)
    .height(this.resolveRenderedHeight())
    // layoutWeight splits a Row's width. It is the main-axis weight, so the same value
    // inside a Column would stretch the button vertically and blow the dialog height up;
    // stacked callers opt out and keep the fixed height instead.
    .layoutWeight(this.fillAvailableWidth && !this.stacked ? 1 : 0)
    .opacity(this.resolveStackOpacity())
  }

  @Builder
  private buildButtonLabel() {
    Row({ space: 8 }) {
      if (this.loading) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.resolveTextColor())
      }
      Text(this.label)
        .fontSize(this.resolveRenderedFontSize())
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolveTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  private useFlatFill(): boolean {
    return this.emphasis === 'destructive' || isLargeScreenDialogShell();
  }

  private resolveRenderedHeight(): number {
    return this.useFlatFill() ? DESKTOP_DIALOG_ACTION_HEIGHT_VP : this.buttonHeight;
  }

  private resolveRenderedFontSize(): number {
    return this.useFlatFill() ? DESKTOP_DIALOG_ACTION_FONT_SIZE_FP : this.fontSize;
  }

  private resolveFlatFill(): ResourceColor {
    if (this.emphasis === 'destructive') {
      return DESKTOP_DIALOG_DESTRUCTIVE_FILL;
    }
    if (this.emphasis === 'primary') {
      return this.resolvePrimaryBackgroundColor();
    }
    return DESKTOP_DIALOG_SECONDARY_FILL;
  }

  private resolveTextColor(): ResourceColor {
    if (this.emphasis === 'destructive') {
      return DESKTOP_DIALOG_DESTRUCTIVE_TEXT;
    }
    if (this.isPrimaryDisabled()) {
      return this.storedSecondaryTextColor;
    }
    if (`${this.textColor}`.length > 0) {
      return this.textColor;
    }
    return this.emphasis === 'primary' ? this.storedOnPrimaryColor : this.storedPrimaryTextColor;
  }

  private resolveOverlayColor(): ResourceColor {
    if (this.isPrimaryDisabled()) {
      // Keep the disabled primary surface neutral so the label stays legible;
      // fading the whole control leaves white text on washed-out brand blue.
      return this.storedPressedBackgroundColor;
    }
    return this.resolvePrimaryBackgroundColor();
  }

  private resolveStackOpacity(): number {
    if (this.actionEnabled) {
      return 1;
    }
    return this.emphasis === 'primary' ? 1 : 0.42;
  }

  private isPrimaryDisabled(): boolean {
    return !this.actionEnabled && this.emphasis === 'primary';
  }

  private resolvePrimaryBackgroundColor(): ResourceColor {
    if (`${this.accentColor}`.length > 0) {
      return this.accentColor;
    }
    return $r('app.color.browser_brand_primary');
  }
}

@Component
export struct BrowserSheetIconButton {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop icon: Resource = $r('sys.symbol.circle');
  @Prop airaIconId: AiraRenderableIconId | undefined = undefined;
  @Prop iconSize: number = 18;
  @Prop iconColor: ResourceColor = '';
  @Prop buttonSize: number = 36;
  @Prop actionEnabled: boolean = true;
  @Prop accessibilityLabel: string = '';
  /**
   * Opt-in immersive light-sense backplate. Off by default because this button is shared by
   * many sheets and overlays; the settings sheet header is the surface that opted in.
   */
  @Prop immersiveMaterialEnabled: boolean = false;
  onAction: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterial()) {
        HdsImmersiveMaterialSurface({
          plateWidth: this.buttonSize,
          plateHeight: this.buttonSize,
          plateRadius: this.buttonSize / 2
        })
      }
      FloatingGlassMaterialSurface({
        surfaceWidth: this.buttonSize,
        surfaceHeight: this.buttonSize,
        surfaceRadius: this.buttonSize / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        hostMaterialActive: this.shouldUseHdsMaterial()
      }) {
        Button() {
          if (this.airaIconId !== undefined) {
            AiraIcon({
              airaIconId: this.airaIconId,
              iconSize: this.iconSize,
              iconColor: this.resolveIconColor()
            })
          } else {
            SymbolGlyph(this.icon)
              .fontSize(this.iconSize)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.resolveIconColor()])
          }
        }
        .width('100%')
        .height('100%')
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(this.buttonSize / 2)
        .stateEffect(this.actionEnabled)
        .enabled(this.actionEnabled)
        .accessibilityText(this.accessibilityLabel)
        .onClick(() => {
          this.onAction();
        })
      }
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .opacity(this.actionEnabled ? 1 : 0.42)
  }

  private resolveIconColor(): ResourceColor {
    if (`${this.iconColor}`.trim().length > 0) {
      return this.iconColor;
    }
    return this.storedPrimaryTextColor;
  }

  private shouldUseHdsMaterial(): boolean {
    return this.immersiveMaterialEnabled && isHdsMaterialAvailable();
  }
}

@Component
export struct BrowserFeatureSheetHeader {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop title: string = '';
  @Prop titleColor: ResourceColor = '';
  @Prop showLeadingButton: boolean = false;
  @Prop leadingAccessibilityLabel: string = '返回';
  @Prop trailingVisible: boolean = false;
  @BuilderParam trailing: () => void = this.emptyContent;
  onLeadingAction: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      if (this.showLeadingButton) {
        BrowserSheetIconButton({
          icon: $r('sys.symbol.chevron_left'),
          iconSize: BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE,
          iconColor: this.resolveTitleColor(),
          buttonSize: BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE,
          accessibilityLabel: this.leadingAccessibilityLabel,
          immersiveMaterialEnabled: true,
          onAction: this.onLeadingAction
        })
      }

      Text(this.title)
        .layoutWeight(1)
        .fontSize(BROWSER_FEATURE_SHEET_HEADER_TITLE_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolveTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.trailingVisible) {
        this.trailing()
      }
    }
    .width('100%')
    .height(BROWSER_FEATURE_SHEET_HEADER_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ right: 56 })
  }

  private resolveTitleColor(): ResourceColor {
    return `${this.titleColor}`.trim().length > 0 ? this.titleColor : this.storedPrimaryTextColor;
  }

  @Builder
  private emptyContent() {
  }
}
