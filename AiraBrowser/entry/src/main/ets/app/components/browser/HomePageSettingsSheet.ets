import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { WallpaperMode } from '../../../common/models/WallpaperModels';
import { WallpaperSettingsCoordinator } from '../../../core/wallpaper/WallpaperSettingsCoordinator';
import { WallpaperSettingsViewState } from '../../../core/wallpaper/WallpaperSettingsViewModel';
import { sharedWallpaperRepository } from '../../bootstrap/BrowserAppRuntime';
import { HomeNativeSettingsContent } from '../settings/HomeNativeSettingsContent';
import { SettingsScrollBody } from '../settings/SettingsLayout';
import { WallpaperSettingsContent } from '../wallpaper/WallpaperSettingsScreen';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserImmersiveSheetLayout
} from './BrowserModalBottomSheet';
import { BrowserLargeScreenModalHeader } from './BrowserLargeScreenModalHeader';
import { BrowserPhoneSettingsSheetHeader } from './BrowserPhoneSettingsSheetHeader';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';

type HomePageSettingsSheetView = 'main' | 'wallpaper';
export type HomePageSettingsLayoutMode = 'phone' | 'large_screen';

@Component
export struct HomePageSettingsSheet {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @Prop privateModeVisible: boolean = false;
  onWallpaperChanged: () => void = () => {};

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
        onWallpaperChanged: this.onWallpaperChanged
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
    CenteredDialogSurface({ fillHeight: true, materialEnabled: false }) {
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
  @Prop privateModeVisible: boolean = false;
  @Prop layoutMode: HomePageSettingsLayoutMode = 'phone';
  onWallpaperChanged: () => void = () => {};
  onClose: () => void = () => {};
  @State private activeView: HomePageSettingsSheetView = 'main';
  @State private wallpaperState: WallpaperSettingsViewState = this.wallpaperCoordinator.getCurrentState();

  aboutToAppear(): void {
    this.refreshWallpaperState();
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
    Column({ space: 0 }) {
      BrowserLargeScreenModalHeader({
        title: this.activeView === 'wallpaper' ? '壁纸设置' : '主页设置',
        dialogMode: true,
        showBackButton: this.activeView === 'wallpaper',
        onBack: () => {
          this.activeView = 'main';
        },
        onClose: this.onClose
      })

      SettingsScrollBody({
        topPadding: 10,
        bottomPadding: 32,
        clipContent: true
      }) {
        this.buildActiveSettingsContent()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildImmersivePhoneLayout() {
    BrowserImmersiveSheetLayout({
      scrollContent: () => {
        this.buildPhoneScrollContent()
      },
      header: () => {
        this.buildPhoneHeader()
      }
    })
  }

  @Builder
  private buildPhoneScrollContent() {
    Scroll() {
      Column({ space: 16 }) {
        this.buildActiveSettingsContent()
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
  }

  @Builder
  private buildPhoneHeader() {
    BrowserPhoneSettingsSheetHeader({
      title: this.activeView === 'wallpaper' ? '壁纸设置' : '主页设置',
      showBackButton: this.activeView === 'wallpaper',
      backAccessibilityText: '返回主页设置',
      onBack: (): void => {
        this.activeView = 'main';
      }
    })
  }

  @Builder
  private buildActiveSettingsContent() {
    if (this.activeView === 'wallpaper') {
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
        onOpenWallpaperSettings: () => {
          this.activeView = 'wallpaper';
          this.refreshWallpaperState();
        }
      })
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
