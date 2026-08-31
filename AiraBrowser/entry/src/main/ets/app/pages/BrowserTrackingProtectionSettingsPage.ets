import { BrowserThemeViewState } from '../../core/theme/BrowserThemeViewState';
import {
  BrowserTrackingProtectionSettingsContent
} from '../components/settings/BrowserTrackingProtectionSettingsContent';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { BrowserBoundaryRouteState, readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import {
  sharedBrowserThemeViewStateFactory,
  sharedPreferencesRepository
} from '../bootstrap/BrowserAppRuntime';

@Entry
@Component
struct BrowserTrackingProtectionSettingsPage {
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
        title: '防跟踪防护',
        backIconKind: 'back',
        pageBackground: this.theme.pageBackground,
        headerButtonBackground: this.theme.pressedBackground,
        primaryTextColor: this.theme.textPrimary,
        dividerColor: this.theme.divider,
        onBack: (): void => this.navigationCoordinator.back()
      }) {
        SettingsScrollBody({ topPadding: 16 }) {
          BrowserTrackingProtectionSettingsContent({
            surfaceBackground: this.theme.surfaceBackground,
            dividerColor: this.theme.divider,
            accentColor: this.theme.accent,
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
