import { display, PathShape } from '@kit.ArkUI';
import { AiraBrandLogoViewModel } from '../../../core/brand/AiraBrandLogoViewModel';
import {
  SettingsAboutOverviewLayoutState,
  SettingsAboutOverviewLayoutViewModel
} from '../../../core/settings/SettingsAboutOverviewLayoutViewModel';
import { SettingsAboutOverviewState } from '../../../core/settings/SettingsAboutOverviewViewModel';
import { BROWSER_THEME_STORAGE_ACCENT_KEY, BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { SettingsActionButton } from './SettingsRows';

const ABOUT_OVERVIEW_VERSION_OPACITY: number = 0.7;
const ABOUT_OVERVIEW_HERO_IMAGE_ENTER_MS: number = 5000;
const ABOUT_OVERVIEW_HERO_IMAGE_ENTER_SCALE: number = 1.18;

@Component
export struct SettingsAboutOverviewContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop state: SettingsAboutOverviewState = {
    appTitle: 'Aira',
    versionTitle: '当前版本',
    versionText: '',
    moreButtonTitle: '查看更多'
  };
  @Prop surfaceBackground: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  scroller?: Scroller;
  onOpenChangelog?: () => void;
  onShowMore?: () => void;
  private logoViewModel: AiraBrandLogoViewModel = new AiraBrandLogoViewModel();
  private layoutViewModel: SettingsAboutOverviewLayoutViewModel = new SettingsAboutOverviewLayoutViewModel();
  private heroImageEnterTimer: number = -1;
  @State private heroImageScale: number = ABOUT_OVERVIEW_HERO_IMAGE_ENTER_SCALE;
  @State private layoutState: SettingsAboutOverviewLayoutState =
    this.layoutViewModel.buildState({
      viewportWidth: 390,
      viewportHeight: 844,
      horizontalPadding: APP_STANDARD_HORIZONTAL_PADDING
    });

  aboutToAppear(): void {
    this.startHeroImageEnterAnimation();
  }

  aboutToDisappear(): void {
    this.clearHeroImageEnterTimer();
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: this.layoutState.actionGap }) {
        this.buildHeroPanel()
        this.buildInlineAction()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: APP_STANDARD_HORIZONTAL_PADDING,
        right: APP_STANDARD_HORIZONTAL_PADDING,
        top: this.layoutState.topPadding,
        bottom: this.layoutState.bottomPadding
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateResponsiveLayout(
        this.parseAreaDimension(newArea.width),
        this.parseAreaDimension(newArea.height)
      );
    })
  }

  @Builder
  private buildHeroPanel() {
    Stack() {
      Image(this.resolveHeroImage())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .scale({
          x: this.heroImageScale,
          y: this.heroImageScale
        })
        .animation({
          duration: ABOUT_OVERVIEW_HERO_IMAGE_ENTER_MS,
          curve: Curve.EaseOut
        })

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.resolveHeroTintColor())

      Column() {
        Blank()
          .layoutWeight(1)

        this.buildStaticLogo()

        Text(this.state.appTitle)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resolveOverlayTextColor())
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: this.layoutState.titleTopMargin })

        Blank()
          .layoutWeight(1)

        this.buildVersionEntry()

        Text(this.state.versionText)
          .fontSize(15)
          .fontColor(this.resolveOverlayTextColor())
          .opacity(ABOUT_OVERVIEW_VERSION_OPACITY)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 10 })
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.layoutState.heroHorizontalPadding,
        right: this.layoutState.heroHorizontalPadding,
        top: this.layoutState.heroTopPadding,
        bottom: this.layoutState.heroBottomPadding
      })
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.layoutState.cardWidth)
    .height(this.layoutState.cardHeight)
    .backgroundColor(this.surfaceBackground)
    .borderRadius(this.layoutState.cardRadius)
    .clip(true)
  }

  @Builder
  private buildStaticLogo() {
    Row()
      .width(this.layoutState.logoSize)
      .height(this.layoutState.logoSize)
      .backgroundColor(this.resolveOverlayTextColor())
      .clipShape(new PathShape({
        commands: this.logoViewModel.buildGradientState('#FFFFFF', this.resolveLogoMaskSizePx()).maskCommands
      }))
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildVersionEntry() {
    Button() {
      Row({ space: 4 }) {
        Text(this.state.versionTitle)
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveOverlayTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.resolveOverlayTextColor()])
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .constraintSize({ maxWidth: '100%' })
    }
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .borderRadius(999)
    .clip(true)
    .stateEffect(true)
    .onClick(() => {
      this.onOpenChangelog?.();
    })
  }

  private resolveLogoMaskSizePx(): number {
    try {
      return this.layoutState.logoSize * display.getDefaultDisplaySync().densityPixels;
    } catch (_error) {
      return this.layoutState.logoSize;
    }
  }

  private resolveOverlayTextColor(): ResourceColor {
    return $r('app.color.browser_brand_on_primary');
  }

  private resolveHeroImage(): Resource {
    if (this.storedResolvedThemeMode === 'dark') {
      return $r('app.media.about_overview_background_dark');
    }
    return $r('app.media.about_overview_background');
  }

  private resolveHeroTintColor(): ResourceColor {
    return this.withAlpha(this.storedAccentColor, '2A');
  }

  private withAlpha(color: string, alphaHex: string): ResourceColor {
    const normalizedColor = color.trim();
    if (!normalizedColor.startsWith('#')) {
      return color;
    }
    const hexColor = normalizedColor.substring(1);
    if (hexColor.length === 6 && this.isHexColor(hexColor) && this.isHexColor(alphaHex) && alphaHex.length === 2) {
      return `#${alphaHex}${hexColor}`;
    }
    if (hexColor.length === 8 && this.isHexColor(hexColor) && this.isHexColor(alphaHex) && alphaHex.length === 2) {
      return `#${alphaHex}${hexColor.substring(2)}`;
    }
    return color;
  }

  private isHexColor(value: string): boolean {
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      const isDigit = code >= 48 && code <= 57;
      const isUpperHex = code >= 65 && code <= 70;
      const isLowerHex = code >= 97 && code <= 102;
      if (!isDigit && !isUpperHex && !isLowerHex) {
        return false;
      }
    }
    return true;
  }

  private startHeroImageEnterAnimation(): void {
    this.clearHeroImageEnterTimer();
    this.heroImageScale = ABOUT_OVERVIEW_HERO_IMAGE_ENTER_SCALE;
    this.heroImageEnterTimer = setTimeout(() => {
      this.heroImageEnterTimer = -1;
      this.heroImageScale = 1;
    }, 0);
  }

  private clearHeroImageEnterTimer(): void {
    if (this.heroImageEnterTimer < 0) {
      return;
    }
    clearTimeout(this.heroImageEnterTimer);
    this.heroImageEnterTimer = -1;
  }

  @Builder
  private buildInlineAction() {
    Column() {
      SettingsActionButton({
        title: this.state.moreButtonTitle,
        emphasis: 'primary',
        variant: 'filled',
        isEnabled: true,
        accentColor: this.accentColor,
        pressedBackgroundColor: this.pressedBackground,
        onAction: () => {
          this.onShowMore?.();
        }
      })
    }
    .width(this.layoutState.actionWidth)
  }

  private updateResponsiveLayout(viewportWidth: number, viewportHeight: number): void {
    if (viewportWidth <= 0 || viewportHeight <= 0) {
      return;
    }
    const nextState = this.layoutViewModel.buildState({
      viewportWidth,
      viewportHeight,
      horizontalPadding: APP_STANDARD_HORIZONTAL_PADDING
    });
    if (this.layoutViewModel.buildRenderKey(nextState) ===
      this.layoutViewModel.buildRenderKey(this.layoutState)) {
      return;
    }
    this.layoutState = nextState;
  }

  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
