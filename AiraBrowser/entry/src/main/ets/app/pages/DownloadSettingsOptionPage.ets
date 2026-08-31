import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import {
  BrowserDownloadSettingsOptionScreen,
  BrowserDownloadSettingsSubpage
} from '../components/browser/BrowserDownloadSettingsScreen';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

@Entry
@Component
struct DownloadSettingsOptionPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State subpage: BrowserDownloadSettingsSubpage = 'auto_clear';

  aboutToAppear(): void {
    const routeParams = router.getParams() as Record<string, string | undefined> | undefined;
    this.subpage = this.resolveSubpage(routeParams?.subpage ?? '');
  }

  build() {
    Column() {
      BrowserDownloadSettingsOptionScreen({
        subpage: this.subpage,
        onBack: () => {
          this.navigationCoordinator.back();
        }
      })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private resolveSubpage(value: string): BrowserDownloadSettingsSubpage {
    switch (value) {
      case 'hls_concurrency':
      case 'auto_clear':
      case 'private_file':
      case 'private_record':
        return value;
      default:
        return 'auto_clear';
    }
  }
}
