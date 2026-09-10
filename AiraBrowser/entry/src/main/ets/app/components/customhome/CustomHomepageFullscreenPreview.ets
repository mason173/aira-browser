import { CustomHomepageChoiceViewState } from '../../../core/customhome/CustomHomepageSettingsViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SiteIconView } from '../common/SiteIconView';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';

const HOMEPAGE_FULLSCREEN_PREVIEW_ENTER_DURATION_MS: number = 260;
const HOMEPAGE_FULLSCREEN_PREVIEW_EXIT_DURATION_MS: number = 220;
const HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_HEIGHT: number = 44;
const HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_RADIUS: number = 22;
const HOMEPAGE_FULLSCREEN_PREVIEW_CLOSE_SIZE: number = 44;
const HOMEPAGE_FULLSCREEN_PREVIEW_PAGE_COUNT_WIDTH: number = 52;
const HOMEPAGE_FULLSCREEN_PREVIEW_PAGE_COUNT_HEIGHT: number = 28;
const HOMEPAGE_FULLSCREEN_PREVIEW_HORIZONTAL_PADDING: number = 18;
const HOMEPAGE_FULLSCREEN_PREVIEW_BOTTOM_PADDING: number = 28;
const HOMEPAGE_FULLSCREEN_PREVIEW_TOP_PADDING: number = 54;
const HOMEPAGE_FULLSCREEN_PREVIEW_START_SCALE: number = 0.86;
const HOMEPAGE_FULLSCREEN_PREVIEW_START_RADIUS: number = 24;
const HOMEPAGE_FULLSCREEN_PREVIEW_SWIPER_DURATION_MS: number = 280;
const HOMEPAGE_FULLSCREEN_PREVIEW_TOP_BAR_HEIGHT: number =
  HOMEPAGE_FULLSCREEN_PREVIEW_TOP_PADDING + HOMEPAGE_FULLSCREEN_PREVIEW_CLOSE_SIZE;
const HOMEPAGE_FULLSCREEN_PREVIEW_BOTTOM_BAR_HEIGHT: number =
  HOMEPAGE_FULLSCREEN_PREVIEW_BOTTOM_PADDING + HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_HEIGHT + 24;
const HOMEPAGE_FULLSCREEN_REMOTE_ICON_SIZE: number = 78;

@Component
export struct CustomHomepageFullscreenPreview {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop choices: CustomHomepageChoiceViewState[] = [];
  @Prop initialIndex: number = 0;
  @Prop selectedChoiceId: string = '';
  @Prop busy: boolean = false;
  @Prop @Watch('syncCloseAnimation') closingTrigger: number = 0;
  @State private entered: boolean = false;
  @State private currentIndex: number = 0;
  private handledClosingTrigger: number = 0;
  private swiperController: SwiperController = new SwiperController();

  onClose: () => void = () => {};
  onClosed: () => void = () => {};
  onUse: (choice: CustomHomepageChoiceViewState) => void = (_choice: CustomHomepageChoiceViewState) => {};

  aboutToAppear(): void {
    this.entered = false;
    this.currentIndex = this.resolveInitialIndex();
    this.handledClosingTrigger = this.closingTrigger;
    setTimeout(() => {
      this.entered = true;
    }, 16);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildPreviewSwiper()
      Column() {
        this.buildTopBar()
        Blank()
          .width('100%')
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.None)
        this.buildBottomBar()
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(this.entered ? 0 : HOMEPAGE_FULLSCREEN_PREVIEW_START_RADIUS)
    .clip(true)
    .opacity(this.entered ? 1 : 0)
    .scale({
      x: this.entered ? 1 : HOMEPAGE_FULLSCREEN_PREVIEW_START_SCALE,
      y: this.entered ? 1 : HOMEPAGE_FULLSCREEN_PREVIEW_START_SCALE
    })
    .animation({
      duration: this.entered ? HOMEPAGE_FULLSCREEN_PREVIEW_ENTER_DURATION_MS :
        HOMEPAGE_FULLSCREEN_PREVIEW_EXIT_DURATION_MS,
      curve: Curve.Friction
    })
    .zIndex(20)
  }

  private syncCloseAnimation(): void {
    if (this.closingTrigger <= 0 || this.closingTrigger === this.handledClosingTrigger) {
      return;
    }
    this.handledClosingTrigger = this.closingTrigger;
    this.entered = false;
    setTimeout(() => {
      this.onClosed();
    }, HOMEPAGE_FULLSCREEN_PREVIEW_EXIT_DURATION_MS);
  }

  @Builder
  private buildTopBar() {
    Row() {
      this.buildCloseButton()

      Blank()

      this.buildPageCount()
    }
    .width('100%')
    .height(HOMEPAGE_FULLSCREEN_PREVIEW_TOP_BAR_HEIGHT)
    .padding({
      left: HOMEPAGE_FULLSCREEN_PREVIEW_HORIZONTAL_PADDING,
      right: HOMEPAGE_FULLSCREEN_PREVIEW_HORIZONTAL_PADDING,
      top: HOMEPAGE_FULLSCREEN_PREVIEW_TOP_PADDING
    })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildBottomBar() {
    Column({ space: 12 }) {
      this.buildPageIndicator()
      if (this.resolveCurrentChoice() !== undefined) {
        this.buildAction()
      }
    }
    .width('100%')
    .height(HOMEPAGE_FULLSCREEN_PREVIEW_BOTTOM_BAR_HEIGHT)
    .padding({
      left: HOMEPAGE_FULLSCREEN_PREVIEW_HORIZONTAL_PADDING,
      right: HOMEPAGE_FULLSCREEN_PREVIEW_HORIZONTAL_PADDING,
      bottom: HOMEPAGE_FULLSCREEN_PREVIEW_BOTTOM_PADDING
    })
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildPreviewSwiper() {
    Swiper(this.swiperController) {
      ForEach(this.choices, (choice: CustomHomepageChoiceViewState) => {
        this.buildPreviewPage(choice)
      }, (choice: CustomHomepageChoiceViewState) => choice.id)
    }
    .index(this.currentIndex)
    .indicator(false)
    .loop(false)
    .duration(HOMEPAGE_FULLSCREEN_PREVIEW_SWIPER_DURATION_MS)
    .cachedCount(1)
    .width('100%')
    .height('100%')
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }

  @Builder
  private buildPreviewPage(choice: CustomHomepageChoiceViewState) {
    Stack() {
      this.buildPreviewImage(choice)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedSurfaceBackgroundColor)
  }

  @Builder
  private buildPreviewImage(choice: CustomHomepageChoiceViewState) {
    if (choice.previewResource !== undefined) {
      Image(choice.previewResource)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
        .hitTestBehavior(HitTestMode.None)
    } else if (choice.previewPath.trim().length > 0) {
      Image(choice.previewPath)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
        .hitTestBehavior(HitTestMode.None)
    } else {
      this.buildPlaceholder(choice)
    }
  }

  @Builder
  private buildPlaceholder(choice: CustomHomepageChoiceViewState) {
    Column({ space: 12 }) {
      SiteIconView({
        iconUri: choice.siteIconPath,
        fallbackLabel: choice.title,
        iconSize: HOMEPAGE_FULLSCREEN_REMOTE_ICON_SIZE,
        cornerRadiusRatio: 0.3,
        frameBorderWidth: choice.siteIconPath.length > 0 ? 0 : 1,
        contentPadding: 0,
        fallbackFontSize: 30,
        containerBackgroundColor: this.storedControlBackgroundColor,
        frameBorderColor: this.storedSurfaceBackgroundColor,
        textColor: this.storedSecondaryTextColor,
        fit: ImageFit.Contain,
        hitTestMode: HitTestMode.None
      })
      Text(choice.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildPageIndicator() {
    if (this.choices.length > 1) {
      Stack() {
        FloatingGlassMaterialSurface({
          surfaceWidth: this.resolvePageIndicatorWidth(),
          surfaceHeight: 16,
          surfaceRadius: 8,
          tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
        }) {
          Row({ space: 6 }) {
            ForEach(this.choices, (_choice: CustomHomepageChoiceViewState, index: number) => {
              Column()
                .width(this.currentIndex === index ? 18 : 6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.currentIndex === index ? this.storedAccentColor : this.storedSurfaceBackgroundColor)
                .opacity(this.currentIndex === index ? 0.95 : 0.62)
                .animation({
                  duration: 180,
                  curve: Curve.EaseOut
                })
            }, (choice: CustomHomepageChoiceViewState) => `fullscreen-page-dot-${choice.id}`)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 10, right: 10 })
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width(this.resolvePageIndicatorWidth())
      .height(16)
      .borderRadius(8)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private buildPageCount() {
    Stack() {
      FloatingGlassMaterialSurface({
        surfaceWidth: HOMEPAGE_FULLSCREEN_PREVIEW_PAGE_COUNT_WIDTH,
        surfaceHeight: HOMEPAGE_FULLSCREEN_PREVIEW_PAGE_COUNT_HEIGHT,
        surfaceRadius: HOMEPAGE_FULLSCREEN_PREVIEW_PAGE_COUNT_HEIGHT / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Text(`${this.currentIndex + 1}/${this.choices.length}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
    }
    .width(HOMEPAGE_FULLSCREEN_PREVIEW_PAGE_COUNT_WIDTH)
    .height(HOMEPAGE_FULLSCREEN_PREVIEW_PAGE_COUNT_HEIGHT)
    .borderRadius(HOMEPAGE_FULLSCREEN_PREVIEW_PAGE_COUNT_HEIGHT / 2)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildCloseButton() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: HOMEPAGE_FULLSCREEN_PREVIEW_CLOSE_SIZE,
        surfaceHeight: HOMEPAGE_FULLSCREEN_PREVIEW_CLOSE_SIZE,
        surfaceRadius: HOMEPAGE_FULLSCREEN_PREVIEW_CLOSE_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([this.storedPrimaryTextColor])
          .hitTestBehavior(HitTestMode.None)
      }

      Button({ type: ButtonType.Circle })
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .enabled(!this.busy)
        .accessibilityText('关闭预览')
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.onClose();
        })
    }
    .width(HOMEPAGE_FULLSCREEN_PREVIEW_CLOSE_SIZE)
    .height(HOMEPAGE_FULLSCREEN_PREVIEW_CLOSE_SIZE)
    .borderRadius(HOMEPAGE_FULLSCREEN_PREVIEW_CLOSE_SIZE / 2)
    .opacity(this.busy ? 0.48 : 1)
  }

  @Builder
  private buildAction() {
    if (this.isCurrentChoiceSelected()) {
      Stack() {
        FloatingGlassMaterialSurface({
          surfaceWidth: '100%',
          surfaceHeight: HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_HEIGHT,
          surfaceRadius: HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_RADIUS,
          tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
        }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(16)
              .fontColor([this.storedAccentColor])
            Text('当前主页')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .padding({ left: 14, right: 14 })
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 360 })
      .height(HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_HEIGHT)
      .border({ width: 0.5, color: this.storedDividerColor })
      .borderRadius(HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_RADIUS)
      .opacity(this.busy ? 0.72 : 1)
      .hitTestBehavior(HitTestMode.None)
      .zIndex(2)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        FloatingGlassMaterialSurface({
          surfaceWidth: '100%',
          surfaceHeight: HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_HEIGHT,
          surfaceRadius: HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_RADIUS,
          tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
          overlayColor: this.storedAccentColor,
          overlayOpacity: 1
        }) {
          Text('使用该主页')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .hitTestBehavior(HitTestMode.None)
        }

        Button({ type: ButtonType.Capsule })
          .width('100%')
          .height('100%')
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .enabled(!this.busy)
          .accessibilityText('使用该主页')
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.handleUseCurrentHomepage();
          })
      }
      .width('100%')
      .constraintSize({ maxWidth: 360 })
      .height(HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_HEIGHT)
      .borderRadius(HOMEPAGE_FULLSCREEN_PREVIEW_ACTION_RADIUS)
      .opacity(this.busy ? 0.48 : 1)
    }
  }

  private resolvePageIndicatorWidth(): number {
    return 20 + 18 + Math.max(0, this.choices.length - 1) * 6 + Math.max(0, this.choices.length - 1) * 6;
  }

  private resolveInitialIndex(): number {
    if (this.choices.length <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(this.initialIndex, this.choices.length - 1));
  }

  private handleUseCurrentHomepage(): void {
    const choice = this.resolveCurrentChoice();
    if (choice === undefined || this.busy) {
      return;
    }
    this.onUse(choice);
  }

  private resolveCurrentChoice(): CustomHomepageChoiceViewState | undefined {
    if (this.choices.length <= 0) {
      return undefined;
    }
    const index = Math.max(0, Math.min(this.currentIndex, this.choices.length - 1));
    return this.choices[index];
  }

  private isCurrentChoiceSelected(): boolean {
    const choice = this.resolveCurrentChoice();
    return choice !== undefined && choice.id === this.selectedChoiceId;
  }
}
