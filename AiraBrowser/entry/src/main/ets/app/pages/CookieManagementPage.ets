import { BrowserThemeViewState } from '../../core/theme/BrowserThemeViewState';
import { BrowserBoundaryRouteState, isPrivateBoundaryRoute, readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { sharedBrowserThemeViewStateFactory, sharedPreferencesRepository } from '../bootstrap/BrowserAppRuntime';
import { CookieManagementContent } from '../components/settings/CookieManagementContent';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

@Entry
@Component
struct CookieManagementPage {
  private readonly navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State private theme: BrowserThemeViewState =
    sharedBrowserThemeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @State private boundary: BrowserBoundaryRouteState = { dataScope: '', privacyMode: '', boundarySource: '' };

  aboutToAppear(): void {
    this.boundary = readBrowserBoundaryRouteState(this.boundary);
    this.theme = sharedBrowserThemeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: 'Cookie 管理',
        backIconKind: 'back',
        pageBackground: this.theme.pageBackground,
        headerButtonBackground: this.theme.pressedBackground,
        primaryTextColor: this.theme.textPrimary,
        dividerColor: this.theme.divider,
        showPrivateIndicator: isPrivateBoundaryRoute(this.boundary.dataScope, this.boundary.privacyMode),
        onBack: (): void => this.navigationCoordinator.back()
      }) {
        SettingsScrollBody({ topPadding: 16, bottomPadding: 22 }) {
          CookieManagementContent({
            surfaceBackground: this.theme.surfaceBackground,
            dividerColor: this.theme.divider,
            accentColor: this.theme.accent,
            pressedBackground: this.theme.pressedBackground,
            primaryTextColor: this.theme.textPrimary,
            secondaryTextColor: this.theme.textSecondary,
            dataScope: this.boundary.dataScope,
            privacyMode: this.boundary.privacyMode
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
  }
}
