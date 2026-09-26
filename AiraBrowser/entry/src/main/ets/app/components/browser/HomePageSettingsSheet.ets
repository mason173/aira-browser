import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { WallpaperMode } from '../../../common/models/WallpaperModels';
import { WallpaperSettingsCoordinator } from '../../../core/wallpaper/WallpaperSettingsCoordinator';
import { WallpaperSettingsViewState } from '../../../core/wallpaper/WallpaperSettingsViewModel';
import { sharedWallpaperRepository } from '../../bootstrap/BrowserAppRuntime';
import { HomeNativeSettingsContent } from '../settings/HomeNativeSettingsContent';
import { SettingsScrollBody } from '../settings/SettingsLayout';
import { WallpaperSettingsContent } from '../wallpaper/WallpaperSettingsScreen';
import {
  BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE,
  BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE,
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BROWSER_SHEET_MODAL_HEADER_BUTTON_TOP,
  resolveBrowserSheetHeaderBlurRadius,
  BrowserBottomSheetSurface,
  BrowserImmersiveSheetLayout,
  BrowserSheetIconButton,
  browserSheetHeaderBlurModifier
} from './BrowserModalBottomSheet';
import { BrowserLargeScreenModalHeader } from './BrowserLargeScreenModalHeader';
import { BrowserPhoneSettingsSheetHeader } from './BrowserPhoneSettingsSheetHeader';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';

export type HomePageSettingsLayoutMode = 'phone' | 'large_screen';
type HomePageSettingsSheetPage = 'main' | 'wallpaper';
const HOME_PAGE_WALLPAPER_DESTINATION: string = 'homePageWallpaperSettings';
const HOME_PAGE_SHEET_POP_GUARD_MS: number = 450;

class HomePageWallpaperParams {
}

/**
 * The system sheet and the large-screen dialog both receive back before the
 * page inside them. This lets that outer dismiss pop the wallpaper page first.
 */
class HomePageSettingsSheetNavigation {
  private consumeBack: (() => boolean) | undefined = undefined;

  bind(consumeBack: () => boolean): void {
    this.consumeBack = consumeBack;
  }

  unbind(consumeBack: () => boolean): void {
    if (this.consumeBack === consumeBack) {
      this.consumeBack = undefined;
    }
  }

  tryConsumeBack(): boolean {
    if (this.consumeBack === undefined) {
      return false;
    }
    return this.consumeBack();
  }
}

export const homePageSettingsSheetNavigation: HomePageSettingsSheetNavigation =
  new HomePageSettingsSheetNavigation();

@Component
export struct HomePageSettingsSheet {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @Prop privateModeVisible: boolean = false;
  onWallpaperChanged: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      HomePageSettingsContent({
        privateModeVisible: this.privateModeVisible,
        layoutMode: 'phone',
        onWallpaperChanged: this.onWallpaperChanged,
        onClose: this.onClose
      })
    }
  }
}

@CustomDialog
export struct HomePageSettingsDialog {
  controller?: CustomDialogController;
  @Link privateModeVisible: boolean;
  onWallpaperChanged: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    CenteredDialogSurface({ fillHeight: true }) {
      HomePageSettingsContent({
        privateModeVisible: this.privateModeVisible,
        layoutMode: 'large_screen',
        onWallpaperChanged: this.onWallpaperChanged,
        onClose: this.onClose
      })
        .width('100%')
        .height('100%')
    }
  }
}

@Component
export struct HomePageSettingsContent {
  private wallpaperCoordinator: WallpaperSettingsCoordinator =
    new WallpaperSettingsCoordinator(sharedWallpaperRepository);
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @Prop privateModeVisible: boolean = false;
  @Prop layoutMode: HomePageSettingsLayoutMode = 'phone';
  onWallpaperChanged: () => void = () => {};
  onClose: () => void = () => {};
  @State private wallpaperState: WallpaperSettingsViewState = this.wallpaperCoordinator.getCurrentState();
  @State private mainBlurRadius: number = 0;
  @State private wallpaperBlurRadius: number = 0;
  private sheetNavigationStack: NavPathStack = new NavPathStack();
  private mainSheetScroller: Scroller = new Scroller();
  private wallpaperSheetScroller: Scroller = new Scroller();
  private sheetNavigationPopGuardUntilMs: number = 0;
  private readonly consumeSheetBack: () => boolean = (): boolean => this.popSheetNavigation();

  aboutToAppear(): void {
    this.refreshWallpaperState();
    homePageSettingsSheetNavigation.bind(this.consumeSheetBack);
  }

  aboutToDisappear(): void {
    homePageSettingsSheetNavigation.unbind(this.consumeSheetBack);
    this.resetSheetNavigation();
  }

  build() {
    if (this.layoutMode === 'large_screen') {
      this.buildLargeScreenLayout()
    } else {
      this.buildImmersivePhoneLayout()
    }
  }

  @Builder
  private buildLargeScreenLayout() {
    Navigation(this.sheetNavigationStack) {
      this.buildLargeScreenPage('main')
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
    .hideNavBar(false)
    .navDestination(this.buildLargeScreenDestination)
    .backgroundColor(this.resolveSheetNavigationBackground())
    .clip(true)
  }

  @Builder
  private buildLargeScreenDestination(name: string, _param: Object) {
    if (name === HOME_PAGE_WALLPAPER_DESTINATION) {
      NavDestination() {
        this.buildLargeScreenPage('wallpaper')
      }
      .width('100%')
      .height('100%')
      .hideTitleBar(true)
      .hideToolBar(true)
      .backgroundColor(this.resolveSheetNavigationBackground())
      .onBackPressed(() => {
        this.popSheetNavigation();
        return true;
      })
    }
  }

  @Builder
  private buildLargeScreenPage(page: HomePageSettingsSheetPage) {
    Column({ space: 0 }) {
      BrowserLargeScreenModalHeader({
        title: page === 'wallpaper' ? '壁纸设置' : '主页设置',
        dialogMode: true,
        showBackButton: page === 'wallpaper',
        onBack: (): void => {
          this.popSheetNavigation();
        },
        onClose: this.onClose
      })

      SettingsScrollBody({
        topPadding: 10,
        bottomPadding: 32,
        clipContent: true
      }) {
        this.buildSettingsBody(page)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildImmersivePhoneLayout() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Navigation(this.sheetNavigationStack) {
        this.buildPhonePage('main')
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .hideTitleBar(true)
      .hideToolBar(true)
      .hideNavBar(false)
      .navDestination(this.buildPhoneDestination)
      .backgroundColor(this.resolveSheetNavigationBackground())
      .clip(true)

      this.buildPhoneCloseButton()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildPhoneDestination(name: string, _param: Object) {
    if (name === HOME_PAGE_WALLPAPER_DESTINATION) {
      NavDestination() {
        this.buildPhonePage('wallpaper')
      }
      .width('100%')
      .height('100%')
      .hideTitleBar(true)
      .hideToolBar(true)
      .backgroundColor(this.resolveSheetNavigationBackground())
      .onBackPressed(() => {
        this.popSheetNavigation();
        return true;
      })
    }
  }

  @Builder
  private buildPhonePage(page: HomePageSettingsSheetPage) {
    BrowserImmersiveSheetLayout({
      horizontalPadding: 0,
      scrollContent: (): void => {
        this.buildPhoneScrollContent(page)
      },
      header: (): void => {
        this.buildPhoneHeader(page)
      }
    })
  }

  @Builder
  private buildPhoneCloseButton() {
    BrowserSheetIconButton({
      icon: $r('sys.symbol.xmark'),
      iconSize: BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE,
      buttonSize: BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE,
      accessibilityLabel: '关闭主页设置',
      immersiveMaterialEnabled: true,
      onAction: (): void => {
        this.onClose();
      }
    })
    .margin({ top: BROWSER_SHEET_MODAL_HEADER_BUTTON_TOP, right: 16 })
    .zIndex(3)
  }

  @Builder
  private buildPhoneScrollContent(page: HomePageSettingsSheetPage) {
    Scroll(this.resolveSheetScroller(page)) {
      Column({ space: 16 }) {
        this.buildSettingsBody(page)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
    .attributeModifier(browserSheetHeaderBlurModifier(this.resolveSheetBlurRadius(page)))
    .onAppear(() => {
      this.updateSheetHeaderBlur(page);
    })
    .onDidScroll(() => {
      this.updateSheetHeaderBlur(page);
    })
  }

  @Builder
  private buildPhoneHeader(page: HomePageSettingsSheetPage) {
    BrowserPhoneSettingsSheetHeader({
      title: page === 'wallpaper' ? '壁纸设置' : '主页设置',
      showBackButton: page === 'wallpaper',
      backAccessibilityText: '返回主页设置',
      onBack: (): void => {
        this.popSheetNavigation();
      }
    })
  }

  @Builder
  private buildSettingsBody(page: HomePageSettingsSheetPage) {
    if (page === 'wallpaper') {
      WallpaperSettingsContent({
        state: this.wallpaperState,
        onModeSelect: (mode: WallpaperMode) => {
          this.applyWallpaperMode(mode);
        },
        onBingRetry: () => {
          this.retryBingPreview();
        }
      })
    } else {
      HomeNativeSettingsContent({
        isEnabled: true,
        iconAppearanceEnabled: !this.privateModeVisible,
        wallpaperLabel: this.wallpaperState.modeTitle,
        dialogPresentation: this.layoutMode === 'large_screen',
        onOpenWallpaperSettings: () => {
          this.openWallpaperSettings();
        }
      })
    }
  }

  private resolveSheetScroller(page: HomePageSettingsSheetPage): Scroller {
    return page === 'wallpaper' ? this.wallpaperSheetScroller : this.mainSheetScroller;
  }

  private resolveSheetBlurRadius(page: HomePageSettingsSheetPage): number {
    return page === 'wallpaper' ? this.wallpaperBlurRadius : this.mainBlurRadius;
  }

  private updateSheetHeaderBlur(page: HomePageSettingsSheetPage): void {
    const offset = Math.max(0, this.resolveSheetScroller(page).currentOffset().yOffset);
    const radius = resolveBrowserSheetHeaderBlurRadius(offset);
    if (page === 'wallpaper') {
      if (radius !== this.wallpaperBlurRadius) {
        this.wallpaperBlurRadius = radius;
      }
      return;
    }
    if (radius !== this.mainBlurRadius) {
      this.mainBlurRadius = radius;
    }
  }

  private resolveSheetNavigationBackground(): ResourceColor {
    return this.layoutMode === 'large_screen' ?
      this.storedFloatingSurfaceColor : this.storedPageBackgroundColor;
  }

  private openWallpaperSettings(): void {
    this.refreshWallpaperState();
    if (this.sheetNavigationStack.size() > 0) {
      return;
    }
    this.sheetNavigationStack.pushPathByName(
      HOME_PAGE_WALLPAPER_DESTINATION,
      new HomePageWallpaperParams()
    );
  }

  private popSheetNavigation(): boolean {
    const now = Date.now();
    if (now < this.sheetNavigationPopGuardUntilMs) {
      return true;
    }
    if (this.sheetNavigationStack.size() <= 0) {
      return false;
    }
    this.sheetNavigationPopGuardUntilMs = now + HOME_PAGE_SHEET_POP_GUARD_MS;
    this.sheetNavigationStack.pop();
    return true;
  }

  private resetSheetNavigation(): void {
    this.sheetNavigationPopGuardUntilMs = 0;
    this.mainBlurRadius = 0;
    this.wallpaperBlurRadius = 0;
    while (this.sheetNavigationStack.pop(false) !== undefined) {
    }
  }

  private refreshWallpaperState(): void {
    this.wallpaperCoordinator.loadState((state: WallpaperSettingsViewState) => {
      this.wallpaperState = state;
    })
      .catch((_error: Error) => {
        this.wallpaperState = this.wallpaperCoordinator.getCurrentState();
      });
  }

  private applyWallpaperMode(mode: WallpaperMode): void {
    this.wallpaperCoordinator.selectMode(mode, (state: WallpaperSettingsViewState) => {
      this.wallpaperState = state;
    })
      .then((state: WallpaperSettingsViewState) => {
        this.wallpaperState = state;
        this.onWallpaperChanged();
      })
      .catch((error: Error) => {
        this.refreshWallpaperState();
        this.showToast(error.message.length > 0 ? error.message : '选择壁纸失败，请稍后重试。');
      });
  }

  private retryBingPreview(): void {
    this.wallpaperCoordinator.retryBingPreview((state: WallpaperSettingsViewState) => {
      this.wallpaperState = state;
    })
      .then((state: WallpaperSettingsViewState) => {
        this.wallpaperState = state;
        this.onWallpaperChanged();
      })
      .catch((_error: Error) => {
        this.wallpaperState = this.wallpaperCoordinator.getCurrentState();
      });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }
}
