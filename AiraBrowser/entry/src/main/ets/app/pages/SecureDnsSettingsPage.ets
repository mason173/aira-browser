import { BrowserThemeViewState } from '../../core/theme/BrowserThemeViewState';
import { SecureDnsSettingsContent } from '../components/settings/SecureDnsSettingsContent';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';
import {
  sharedBrowserThemeViewStateFactory,
  sharedPreferencesRepository
} from '../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { BrowserBoundaryRouteState, readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';

@Entry
@Component
struct SecureDnsSettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State private theme: BrowserThemeViewState =
    sharedBrowserThemeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @State private boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };

  aboutToAppear(): void {
    this.boundary = readBrowserBoundaryRouteState(this.boundary);
    this.theme = sharedBrowserThemeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '安全 DNS',
        backIconKind: 'back',
        pageBackground: this.theme.pageBackground,
        headerButtonBackground: this.theme.pressedBackground,
        primaryTextColor: this.theme.textPrimary,
        dividerColor: this.theme.divider,
        menuActionLabel: '添加自定义 DNS',
        menuActionAiraIconId: 'browser.tabs.add',
        onBack: (): void => {
          this.navigationCoordinator.back();
        },
        onMenuAction: (): void => {
          this.openProfileEditor();
        }
      }) {
        SettingsScrollBody({ topPadding: 16 }) {
          SecureDnsSettingsContent({
            surfaceBackground: this.theme.surfaceBackground,
            dividerColor: this.theme.divider,
            accentColor: this.theme.accent,
            pressedBackground: this.theme.pressedBackground,
            primaryTextColor: this.theme.textPrimary,
            secondaryTextColor: this.theme.textSecondary,
            dataScope: this.boundary.dataScope,
            privacyMode: this.boundary.privacyMode,
            onEditCustomProfile: (profileId: string): void => {
              this.openProfileEditor(profileId);
            }
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
  }

  private openProfileEditor(profileId?: string): void {
    this.navigationCoordinator.openSecureDnsProfileEdit(this.boundary, profileId);
  }
}
