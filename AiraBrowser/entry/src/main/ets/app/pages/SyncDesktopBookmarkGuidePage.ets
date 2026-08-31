import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import {
  SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE
} from '../../services/sync/SyncDesktopBookmarkGuideMarkdownService';
import { sharedPreferencesRepository } from '../bootstrap/BrowserAppRuntime';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SyncDesktopBookmarkGuideContent } from '../components/sync/SyncDesktopBookmarkGuideContent';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

@Entry
@Component
struct SyncDesktopBookmarkGuidePage {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = '#F6F8FB';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.refreshState();
  }

  onPageShow(): void {
    this.refreshState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE,
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SyncDesktopBookmarkGuideContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private refreshState(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      this.navigationCoordinator.back();
      return;
    }
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
  }

}
