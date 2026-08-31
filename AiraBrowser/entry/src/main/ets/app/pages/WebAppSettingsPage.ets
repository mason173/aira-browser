import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsWebAppsDetailPanel } from '../components/settings/SettingsWebAppsDetailPanel';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

@Entry
@Component
struct WebAppSettingsPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private refreshRevision: number = 0;

  aboutToAppear(): void {
    this.syncRouteState();
  }

  onPageShow(): void {
    this.syncRouteState();
    this.refreshRevision += 1;
  }

  build() {
    Column() {
      SettingsWebAppsDetailPanel({
        panelMode: 'compact',
        refreshRevision: this.refreshRevision,
        detailKind: 'web_apps_root',
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        pageBackground: this.storedPageBackgroundColor,
        onBack: () => {
          this.navigationCoordinator.back();
        },
        onOpenWebAppDetail: (shortcutId: string) => {
          this.navigationCoordinator.openWebAppDetailSettings(shortcutId, this.buildBoundaryState());
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
