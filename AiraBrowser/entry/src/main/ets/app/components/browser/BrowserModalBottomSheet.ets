import {
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { AiraIcon } from '../common/AiraIcon';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import { BrowserSheetResponsiveLayoutViewModel } from '../../../core/browser/BrowserSheetResponsiveLayoutViewModel';

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
export const BROWSER_IMMERSIVE_SHEET_HEADER_TOP_INSET: number = 12;
export const BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET: number = 76;
export const BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE: number = 40;
export const BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE: number = 20;
export const BROWSER_FEATURE_SHEET_HEADER_TITLE_SIZE: number = 24;
const BROWSER_MODAL_BOTTOM_OVERLAY_LOCAL_REVEAL_DELAY_MS: number = 16;

export type BrowserBottomSheetSurfacePresentation = 'bottom_sheet' | 'flat_content';

@Component
export struct BrowserModalBottomOverlay {
  @State private presentationVisible: boolean = false;
  private revealTimer: number = -1;
  @Prop @Watch('syncVisible') visible: boolean = false;
  @Prop dismissOnOutsideTap: boolean = true;
  @Prop showScrim: boolean = true;
  sheetHeight: Length = '';
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
    Stack({ alignContent: Alignment.Bottom }) {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor(this.showScrim ? $r('app.color.browser_overlay_scrim') : Color.Transparent)
        .opacity(this.presentationVisible && this.showScrim ? 1 : 0)
        .animation({
          duration: this.animationDurationMs,
          curve: Curve.EaseOut
        })
        .hitTestBehavior(this.presentationVisible && this.dismissOnOutsideTap ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => {
          if (this.dismissOnOutsideTap) {
            this.onDismiss();
          }
        })

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
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.presentationVisible
      ? (this.dismissOnOutsideTap ? HitTestMode.Default : HitTestMode.Transparent)
      : HitTestMode.None)
    .zIndex(this.zIndexValue)
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
      .borderRadius({
        topLeft: this.presentation === 'flat_content' ? 0 : this.topCornerRadius,
        topRight: this.presentation === 'flat_content' ? 0 : this.topCornerRadius,
        bottomLeft: 0,
        bottomRight: 0
      })
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
        .linearGradientBlur(BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS, {
          fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
          direction: GradientDirection.Bottom
        })

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
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop label: string = '';
  @Prop emphasis: 'primary' | 'secondary' = 'secondary';
  @Prop actionEnabled: boolean = true;
  @Prop accentColor: ResourceColor = '';
  @Prop textColor: ResourceColor = '';
  @Prop fillAvailableWidth: boolean = true;
  @Prop buttonWidth: Length = 56;
  @Prop buttonHeight: number = BROWSER_MODAL_BOTTOM_SHEET_ACTION_HEIGHT;
  @Prop fontSize: number = 16;
  @Prop loading: boolean = false;
  onAction: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: this.buttonHeight,
        surfaceRadius: this.buttonHeight / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        overlayColor: this.resolvePrimaryBackgroundColor(),
        overlayOpacity: this.emphasis === 'primary' ? 1 : 0
      }) {
        Button() {
          Row({ space: 8 }) {
            if (this.loading) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(this.resolveTextColor())
            }
            Text(this.label)
              .fontSize(this.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.resolveTextColor())
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
          .width('100%')
          .height('100%')
          .type(ButtonType.Normal)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .borderRadius(this.buttonHeight / 2)
          .stateEffect(this.actionEnabled)
          .enabled(this.actionEnabled)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width(this.fillAvailableWidth ? '100%' : this.buttonWidth)
    .height(this.buttonHeight)
    .layoutWeight(this.fillAvailableWidth ? 1 : 0)
    .opacity(this.actionEnabled ? 1 : 0.42)
  }

  private resolveTextColor(): ResourceColor {
    if (`${this.textColor}`.length > 0) {
      return this.textColor;
    }
    return this.emphasis === 'primary' ? this.storedOnPrimaryColor : this.storedPrimaryTextColor;
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
  onAction: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: this.buttonSize,
        surfaceHeight: this.buttonSize,
        surfaceRadius: this.buttonSize / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
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
}

@Component
export struct BrowserFeatureSheetHeader {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop title: string = '';
  @Prop titleColor: ResourceColor = '';
  @Prop leadingAccessibilityLabel: string = '返回';
  @Prop trailingVisible: boolean = false;
  @BuilderParam trailing: () => void = this.emptyContent;
  onLeadingAction: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      BrowserSheetIconButton({
        airaIconId: 'browser.toolbar.back',
        iconSize: BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE,
        iconColor: this.resolveTitleColor(),
        buttonSize: BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE,
        accessibilityLabel: this.leadingAccessibilityLabel,
        onAction: this.onLeadingAction
      })

      Text(this.title)
        .layoutWeight(1)
        .fontSize(BROWSER_FEATURE_SHEET_HEADER_TITLE_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolveTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.trailingVisible) {
        this.trailing()
      } else {
        Blank()
          .width(BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE)
          .height(BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE)
      }
    }
    .width('100%')
    .height(BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE)
    .alignItems(VerticalAlign.Center)
  }

  private resolveTitleColor(): ResourceColor {
    return `${this.titleColor}`.trim().length > 0 ? this.titleColor : this.storedPrimaryTextColor;
  }

  @Builder
  private emptyContent() {
  }
}
