import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { FeatureIntroCoordinator, FeatureIntroHost } from '../../core/onboarding/FeatureIntroCoordinator';
import { FeatureIntroExitDestination } from '../../core/onboarding/FeatureIntroRoutePolicy';
import {
  FEATURE_INTRO_PAGE_BACKGROUND_COLOR,
  FeatureIntroLayout,
  resolveFeatureIntroLayout
} from '../../core/onboarding/FeatureIntroLayoutPolicy';
import { FeatureIntroSlide, FeatureIntroViewModel } from '../../core/onboarding/FeatureIntroViewModel';
import { resolveWindowBottomSafeInsetVp, resolveWindowTopSafeInsetVp } from '../../core/browser/BrowserWindowAvoidAreaCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { BROWSER_SHELL_ROUTE, STARTUP_WELCOME_INTRO_ROUTE } from '../router/AppRoutes';

const FEATURE_INTRO_ACTION_HEIGHT: number = 40;
const FEATURE_INTRO_TITLE_TOP_PADDING: number = 28;

@Entry
@Component
struct FeatureIntroPage {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6368';
  @State private pageIndex: number = 0;
  @State private windowWidthVp: number = 360;
  @State private windowHeightVp: number = 780;
  @State private topInsetVp: number = 0;
  @State private bottomInsetVp: number = 0;
  private readonly viewModel: FeatureIntroViewModel = new FeatureIntroViewModel();
  private readonly swiperController: SwiperController = new SwiperController();
  private readonly host: FeatureIntroHost = {
    leave: (destination: FeatureIntroExitDestination): void => {
      router.replaceUrl({ url: this.resolveExitRoute(destination) }).catch((_error: Error) => {
        this.coordinator.abandonLeave();
      });
    }
  };
  private readonly coordinator: FeatureIntroCoordinator = new FeatureIntroCoordinator(this.host);

  onBackPress(): boolean {
    if (this.pageIndex > 0) {
      this.swiperController.showPrevious();
    }
    return true;
  }

  onPageShow(): void {
    this.readSafeInsets();
  }

  build() {
    Column() {
      Swiper(this.swiperController) {
        ForEach(this.viewModel.slides(), (slide: FeatureIntroSlide) => {
          this.buildSlide(slide)
        }, (slide: FeatureIntroSlide) => slide.id)
      }
      .index(this.pageIndex)
      .indicator(false)
      .loop(false)
      .duration(280)
      .cachedCount(1)
      .width('100%')
      .layoutWeight(1)
      .onChange((index: number) => {
        this.pageIndex = index;
      })

      this.buildFooter()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(FEATURE_INTRO_PAGE_BACKGROUND_COLOR)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateWindowSize(newArea);
    })
  }

  @Builder
  private buildSlide(slide: FeatureIntroSlide) {
    Column() {
      Column()
        .width('100%')
        .height(this.topInsetVp + this.resolveLayout().videoHeightVp)
        .backgroundColor(FEATURE_INTRO_PAGE_BACKGROUND_COLOR)

      Column() {
        Text(slide.title)
          .width('100%')
          .fontSize(26)
          .lineHeight(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .margin({ top: FEATURE_INTRO_TITLE_TOP_PADDING })

        Text(slide.body)
          .width('100%')
          .fontSize(15)
          .lineHeight(23)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .margin({ top: 10 })
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ maxWidth: this.resolveLayout().contentMaxWidthVp })
      .padding({
        left: this.resolveLayout().horizontalPaddingVp,
        right: this.resolveLayout().horizontalPaddingVp
      })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(FEATURE_INTRO_PAGE_BACKGROUND_COLOR)
  }

  @Builder
  private buildFooter() {
    Column() {
      Row({ space: 6 }) {
        ForEach(this.viewModel.slides(), (slide: FeatureIntroSlide, index: number) => {
          Column()
            .width(index === this.pageIndex ? 16 : 6)
            .height(6)
            .borderRadius(99)
            .backgroundColor(index === this.pageIndex ? this.storedAccentColor : this.storedPrimaryTextColor)
            .opacity(index === this.pageIndex ? 1 : 0.16)
            .onClick(() => {
              this.swiperController.changeIndex(index);
            })
        }, (slide: FeatureIntroSlide) => `dot-${slide.id}`)
      }
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 18 })

      Button(this.viewModel.actionLabel(this.pageIndex))
        .width('100%')
        .height(FEATURE_INTRO_ACTION_HEIGHT)
        .type(ButtonType.Normal)
        .buttonStyle(ButtonStyleMode.NORMAL)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedOnAccentColor)
        .backgroundColor(this.storedAccentColor)
        .borderRadius(FEATURE_INTRO_ACTION_HEIGHT / 2)
        .stateEffect(false)
        .onClick(() => {
          this.handlePrimaryAction();
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: this.resolveLayout().contentMaxWidthVp })
    .padding({
      left: this.resolveLayout().horizontalPaddingVp,
      right: this.resolveLayout().horizontalPaddingVp,
      bottom: this.resolveLayout().bottomPaddingVp
    })
    .alignItems(HorizontalAlign.Center)
  }

  private handlePrimaryAction(): void {
    if (this.viewModel.isLast(this.pageIndex)) {
      this.coordinator.finish();
      return;
    }
    this.swiperController.showNext();
  }

  private resolveLayout(): FeatureIntroLayout {
    return resolveFeatureIntroLayout({
      windowWidthVp: this.windowWidthVp,
      windowHeightVp: this.windowHeightVp,
      topInsetVp: this.topInsetVp,
      bottomInsetVp: this.bottomInsetVp
    });
  }

  private resolveExitRoute(destination: FeatureIntroExitDestination): string {
    return destination === 'startup_welcome' ? STARTUP_WELCOME_INTRO_ROUTE : BROWSER_SHELL_ROUTE;
  }

  private updateWindowSize(area: Area): void {
    const width = this.parseAreaVp(area.width);
    const height = this.parseAreaVp(area.height);
    if (width > 0 && width !== this.windowWidthVp) {
      this.windowWidthVp = width;
    }
    if (height > 0 && height !== this.windowHeightVp) {
      this.windowHeightVp = height;
    }
  }

  private parseAreaVp(value: Length): number {
    const parsed = Number(`${value}`.replace('vp', '').replace('px', ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private readSafeInsets(): void {
    const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(hostContext)
      .then((mainWindow: window.Window) => {
        this.topInsetVp = resolveWindowTopSafeInsetVp(mainWindow);
        this.bottomInsetVp = resolveWindowBottomSafeInsetVp(mainWindow);
      })
      .catch((_error: Error) => undefined);
  }
}
