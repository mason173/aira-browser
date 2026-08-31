import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import {
  DEFAULT_BROWSER_PROFILE_ID,
  SitePermissionKind
} from '../../common/models/BrowserModels';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsWebAppsDetailPanel } from '../components/settings/SettingsWebAppsDetailPanel';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

interface WebAppDetailSettingsPageParams {
  shortcutId?: string;
}

@Entry
@Component
struct WebAppDetailSettingsPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State private shortcutId: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.syncRouteState();
  }

  onPageShow(): void {
    this.syncRouteState();
  }

  build() {
    Column() {
      SettingsWebAppsDetailPanel({
        panelMode: 'compact',
        detailKind: 'web_app_detail',
        shortcutId: this.shortcutId,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        pageBackground: this.storedPageBackgroundColor,
        onBack: () => {
          this.navigationCoordinator.back();
        },
        onOpenPermission: (host: string, origin: string, kind: SitePermissionKind) => {
          this.navigationCoordinator.openSiteCustomizationPermission(
            host,
            origin,
            DEFAULT_BROWSER_PROFILE_ID,
            kind,
            this.buildBoundaryState()
          );
        },
        onOpenDesktopSite: (host: string, origin: string) => {
          this.navigationCoordinator.openSiteCustomizationDesktopSite(
            host,
            origin,
            DEFAULT_BROWSER_PROFILE_ID,
            this.buildBoundaryState()
          );
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

  private syncRouteState(): void {
    const params = router.getParams() as WebAppDetailSettingsPageParams | undefined;
    this.shortcutId = params?.shortcutId?.trim() ?? this.shortcutId;
    const boundary = readBrowserBoundaryRouteState(this.buildBoundaryState());
    this.dataScope = boundary.dataScope;
    this.privacyMode = boundary.privacyMode;
    this.boundarySource = boundary.boundarySource;
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }
}
