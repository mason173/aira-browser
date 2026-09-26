import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { FeatureIntroGate } from '../components/onboarding/FeatureIntroGate';
import { FeatureIntroSlideVideo } from '../components/onboarding/FeatureIntroSlideVideo';
import { FeatureIntroCoordinator, FeatureIntroHost } from '../../core/onboarding/FeatureIntroCoordinator';
import { FeatureIntroExitDestination } from '../../core/onboarding/FeatureIntroRoutePolicy';
import {
  FeatureIntroLayout,
  resolveFeatureIntroLayout
} from '../../core/onboarding/FeatureIntroLayoutPolicy';
import { FeatureIntroSlide, FeatureIntroViewModel } from '../../core/onboarding/FeatureIntroViewModel';
import { resolveWindowBottomSafeInsetVp, resolveWindowTopSafeInsetVp } from '../../core/browser/BrowserWindowAvoidAreaCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { BROWSER_SHELL_ROUTE, STARTUP_WELCOME_INTRO_ROUTE } from '../router/AppRoutes';

const FEATURE_INTRO_ACTION_HEIGHT: number = 40;
const FEATURE_INTRO_TITLE_TOP_PADDING: number = 28;

@Entry
@Component
struct FeatureIntroPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F2F3F5';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6368';
  @State private gateOpen: boolean = false;
  @State private pageIndex: number = 0;
  @State private windowWidthVp: number = 360;
  @State private windowHeightVp: number = 780;
  @State private topInsetVp: number = 0;
  @State private bottomInsetVp: number = 0;
  private readonly viewModel: FeatureIntroViewModel = new FeatureIntroViewModel();
  private readonly swiperController: SwiperController = new SwiperController();
  private readonly adBlockVideoController: VideoController = new VideoController();
  private readonly videoTakeoverController: VideoController = new VideoController();
  private readonly userScriptsVideoController: VideoController = new VideoController();
  private readonly syncVideoController: VideoController = new VideoController();
  private adBlockVideoReady: boolean = false;
  private videoTakeoverReady: boolean = false;
  private userScriptsVideoReady: boolean = false;
  private syncVideoReady: boolean = false;
  @State private adBlockVideoShown: boolean = false;
  @State private videoTakeoverShown: boolean = false;
  @State private userScriptsVideoShown: boolean = false;
  @State private syncVideoShown: boolean = false;
  private activeIntroVideoId: string = '';
  private introVideoRevealTimer: number = -1;
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
    if (this.gateOpen) {
      this.buildSlides()
    } else {
      FeatureIntroGate({
        label: this.viewModel.gateActionLabel(),
        skipLabel: this.viewModel.gateSkipLabel(),
        topInsetVp: this.topInsetVp,
        bottomInsetVp: this.bottomInsetVp,
        onUnlocked: (): void => {
          this.gateOpen = true;
        },
        onSkip: (): void => {
          this.coordinator.skipToBrowser();
        }
      })
    }
  }

  @Builder
  private buildSlides() {
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
        this.syncIntroVideos(index);
      })

      this.buildFooter()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateWindowSize(newArea);
    })
  }

  @Builder
  private buildSlide(slide: FeatureIntroSlide) {
    Column() {
      FeatureIntroSlideVideo({
        slideId: slide.id,
        controller: this.introVideoController(slide.id),
        shown: this.isIntroVideoShown(slide.id),
        onPrepared: (): void => {
          this.markIntroVideoReady(slide.id);
          this.syncIntroVideos(this.pageIndex);
        },
        onStart: (): void => {
          this.scheduleIntroVideoShown(slide.id);
        }
      })
      .width('100%')
      .height(this.topInsetVp + this.resolveLayout().videoHeightVp)
      .backgroundColor(this.storedPageBackgroundColor)
      .clip(true)

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
    .backgroundColor(this.storedPageBackgroundColor)
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

  private syncIntroVideos(index: number): void {
    const slides = this.viewModel.slides();
    const slideId = index >= 0 && index < slides.length ? slides[index].id : '';
    if (slideId === this.activeIntroVideoId) {
      return;
    }
    if (this.activeIntroVideoId.length > 0) {
      this.hideIntroVideo(this.activeIntroVideoId);
    }
    if (this.activeIntroVideoId === 'ad_block') {
      this.adBlockVideoController.stop();
    } else if (this.activeIntroVideoId === 'video_takeover') {
      this.videoTakeoverController.stop();
    } else if (this.activeIntroVideoId === 'user_scripts') {
      this.userScriptsVideoController.stop();
    } else if (this.activeIntroVideoId === 'sync') {
      this.syncVideoController.stop();
    }
    this.activeIntroVideoId = '';
    if (slideId === 'ad_block' && this.adBlockVideoReady) {
      this.adBlockVideoController.start();
      this.activeIntroVideoId = 'ad_block';
    } else if (slideId === 'video_takeover' && this.videoTakeoverReady) {
      this.videoTakeoverController.start();
      this.activeIntroVideoId = 'video_takeover';
    } else if (slideId === 'user_scripts' && this.userScriptsVideoReady) {
      this.userScriptsVideoController.start();
      this.activeIntroVideoId = 'user_scripts';
    } else if (slideId === 'sync' && this.syncVideoReady) {
      this.syncVideoController.start();
      this.activeIntroVideoId = 'sync';
    }
  }

  private introVideoController(slideId: string): VideoController {
    if (slideId === 'ad_block') {
      return this.adBlockVideoController;
    }
    if (slideId === 'video_takeover') {
      return this.videoTakeoverController;
    }
    if (slideId === 'user_scripts') {
      return this.userScriptsVideoController;
    }
    return this.syncVideoController;
  }

  private isIntroVideoShown(slideId: string): boolean {
    if (slideId === 'ad_block') {
      return this.adBlockVideoShown;
    }
    if (slideId === 'video_takeover') {
      return this.videoTakeoverShown;
    }
    if (slideId === 'user_scripts') {
      return this.userScriptsVideoShown;
    }
    return this.syncVideoShown;
  }

  private scheduleIntroVideoShown(slideId: string): void {
    this.clearIntroVideoRevealTimer();
    this.introVideoRevealTimer = setTimeout((): void => {
      this.introVideoRevealTimer = -1;
      if (slideId === this.activeIntroVideoId) {
        this.markIntroVideoShown(slideId);
      }
    }, 120);
  }

  private clearIntroVideoRevealTimer(): void {
    if (this.introVideoRevealTimer >= 0) {
      clearTimeout(this.introVideoRevealTimer);
      this.introVideoRevealTimer = -1;
    }
  }

  private markIntroVideoShown(slideId: string): void {
    if (slideId === 'ad_block') {
      this.adBlockVideoShown = true;
      return;
    }
    if (slideId === 'video_takeover') {
      this.videoTakeoverShown = true;
      return;
    }
    if (slideId === 'user_scripts') {
      this.userScriptsVideoShown = true;
      return;
    }
    this.syncVideoShown = true;
  }

  private hideIntroVideo(slideId: string): void {
    this.clearIntroVideoRevealTimer();
    if (slideId === 'ad_block') {
      this.adBlockVideoShown = false;
      return;
    }
    if (slideId === 'video_takeover') {
      this.videoTakeoverShown = false;
      return;
    }
    if (slideId === 'user_scripts') {
      this.userScriptsVideoShown = false;
      return;
    }
    this.syncVideoShown = false;
  }

  private markIntroVideoReady(slideId: string): void {
    if (slideId === 'ad_block') {
      this.adBlockVideoReady = true;
      return;
    }
    if (slideId === 'video_takeover') {
      this.videoTakeoverReady = true;
      return;
    }
    if (slideId === 'user_scripts') {
      this.userScriptsVideoReady = true;
      return;
    }
    this.syncVideoReady = true;
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
