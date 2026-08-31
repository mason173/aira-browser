import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import {
  StartupWelcomeIntroIllustrationKind,
  StartupWelcomeIntroSlideState,
  StartupWelcomeIntroViewModel
} from '../../core/onboarding/StartupWelcomeIntroViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../components/common/AppLayoutTokens';
import { sharedStartupWelcomeIntroRepository } from '../bootstrap/BrowserAppRuntime';
import { BROWSER_SHELL_ROUTE } from '../router/AppRoutes';

const STARTUP_WELCOME_TOP_PADDING: number = 36;
const STARTUP_WELCOME_BOTTOM_PADDING: number = 28;
const STARTUP_WELCOME_CONTENT_MAX_WIDTH: number = 430;
const STARTUP_WELCOME_ILLUSTRATION_HEIGHT: number = 330;
const STARTUP_WELCOME_BADGE_WIDTH: number = 52;
const STARTUP_WELCOME_BADGE_HEIGHT: number = 28;
const STARTUP_WELCOME_PRIMARY_ACTION_HEIGHT: number = 44;
const STARTUP_WELCOME_SWIPER_DURATION_MS: number = 260;
const STARTUP_WELCOME_DOT_SIZE: number = 7;
const STARTUP_WELCOME_DOT_ACTIVE_WIDTH: number = 18;

@Entry
@Component
struct StartupWelcomeIntroPage {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private currentIndex: number = 0;
  @State private actionBusy: boolean = false;
  private swiperController: SwiperController = new SwiperController();
  private viewModel: StartupWelcomeIntroViewModel = new StartupWelcomeIntroViewModel();

  onBackPress(): boolean {
    return true;
  }

  build() {
    Column() {
      Column({ space: 0 }) {
        Swiper(this.swiperController) {
          ForEach(this.viewModel.buildState().slides, (slide: StartupWelcomeIntroSlideState) => {
            this.buildSlide(slide)
          }, (slide: StartupWelcomeIntroSlideState) => slide.id)
        }
        .width('100%')
        .layoutWeight(1)
        .indicator(this.resolveSwiperIndicator())
        .loop(false)
        .duration(STARTUP_WELCOME_SWIPER_DURATION_MS)
        .onChange((index: number) => {
          this.currentIndex = index;
        })

        this.buildPrimaryAction()
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: STARTUP_WELCOME_CONTENT_MAX_WIDTH })
      .padding({
        left: APP_STANDARD_HORIZONTAL_PADDING,
        right: APP_STANDARD_HORIZONTAL_PADDING,
        top: STARTUP_WELCOME_TOP_PADDING,
        bottom: STARTUP_WELCOME_BOTTOM_PADDING
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildSlide(slide: StartupWelcomeIntroSlideState) {
    Column({ space: 0 }) {
      Row() {
        this.buildIllustration(slide.illustrationKind)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 0 }) {
        this.buildIndexBadge(slide.indexLabel)

        Text(slide.title)
          .width('100%')
          .fontSize(28)
          .lineHeight(37)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .margin({ top: 24 })

        Text(slide.subtitle)
          .width('100%')
          .fontSize(15)
          .lineHeight(22)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .margin({ top: 14 })
      }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 104 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildIndexBadge(label: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .lineHeight(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedOnPrimaryColor)
        .textAlign(TextAlign.Center)
    }
    .width(STARTUP_WELCOME_BADGE_WIDTH)
    .height(STARTUP_WELCOME_BADGE_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedAccentColor)
    .borderRadius(STARTUP_WELCOME_BADGE_HEIGHT / 2)
  }

  @Builder
  private buildIllustration(kind: StartupWelcomeIntroIllustrationKind) {
    Image(this.resolveIllustrationResource(kind))
      .width('100%')
      .height(STARTUP_WELCOME_ILLUSTRATION_HEIGHT)
      .objectFit(ImageFit.Contain)
      .interpolation(ImageInterpolation.High)
  }

  @Builder
  private buildPrimaryAction() {
    Button(this.resolveActionLabel())
      .type(ButtonType.Normal)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .width('100%')
      .height(STARTUP_WELCOME_PRIMARY_ACTION_HEIGHT)
      .borderRadius(STARTUP_WELCOME_PRIMARY_ACTION_HEIGHT / 2)
      .backgroundColor(this.storedAccentColor)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedOnPrimaryColor)
      .stateEffect(true)
      .enabled(!this.actionBusy)
      .opacity(this.actionBusy ? 0.58 : 1)
      .onClick(() => {
        this.handlePrimaryAction();
      })
  }

  private handlePrimaryAction(): void {
    const slides = this.viewModel.buildState().slides;
    if (this.currentIndex < slides.length - 1) {
      this.swiperController.showNext();
      return;
    }
    this.completeWelcomeIntro();
  }

  private completeWelcomeIntro(): void {
    if (this.actionBusy) {
      return;
    }
    this.actionBusy = true;
    sharedStartupWelcomeIntroRepository.completeCurrentVersion()
      .then(() => {
        this.goToBrowserShell();
      })
      .catch((_error: Error) => {
        this.actionBusy = false;
        this.goToBrowserShell();
      });
  }

  private resolveSwiperIndicator(): DotIndicator {
    return new DotIndicator()
      .bottom(28)
      .itemWidth(STARTUP_WELCOME_DOT_SIZE)
      .itemHeight(STARTUP_WELCOME_DOT_SIZE)
      .selectedItemWidth(STARTUP_WELCOME_DOT_ACTIVE_WIDTH)
      .selectedItemHeight(STARTUP_WELCOME_DOT_SIZE)
      .color(this.storedDividerColor)
      .selectedColor(this.storedAccentColor);
  }

  private goToBrowserShell(): void {
    router.replaceUrl({
      url: BROWSER_SHELL_ROUTE
    }).catch((_error: Error) => {
      this.actionBusy = false;
    });
  }

  private resolveActionLabel(): string {
    const state = this.viewModel.buildState();
    return this.currentIndex >= state.slides.length - 1 ? state.finalActionLabel : state.nextActionLabel;
  }

  private resolveIllustrationResource(kind: StartupWelcomeIntroIllustrationKind): Resource {
    if (kind === 'speed') {
      return $r('app.media.startup_welcome_speed');
    }
    if (kind === 'privacy') {
      return $r('app.media.startup_welcome_privacy');
    }
    if (kind === 'extensions') {
      return $r('app.media.startup_welcome_extensions');
    }
    return $r('app.media.startup_welcome_sync');
  }
}
