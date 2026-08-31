import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';
import {
  SiteControlsExternalNavigationDefaultContent
} from '../components/settings/SiteControlsExternalNavigationDefaultContent';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  isPrivateBoundaryRoute,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import {
  BrowserThemeViewState
} from '../../core/theme/BrowserThemeViewState';
import {
  sharedBrowserThemeViewStateFactory,
  sharedPreferencesRepository
} from '../bootstrap/BrowserAppRuntime';

@Entry
@Component
struct SiteControlsExternalNavigationDefaultPage {
  private readonly navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State private theme: BrowserThemeViewState =
    sharedBrowserThemeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @State private isLeaving: boolean = false;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.isLeaving = false;
    this.syncBoundaryRouteState();
    this.theme = sharedBrowserThemeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '外部应用跳转',
        backIconKind: 'back',
        pageBackground: this.theme.pageBackground,
        headerButtonBackground: this.theme.pressedBackground,
        primaryTextColor: this.theme.textPrimary,
        dividerColor: this.theme.divider,
        showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
        onBack: (): void => {
          this.handleBack();
        }
      }) {
        SettingsScrollBody({ bottomPadding: 22 }) {
          SiteControlsExternalNavigationDefaultContent({
            surfaceBackground: this.theme.surfaceBackground,
            dividerColor: this.theme.divider,
            secondaryTextColor: this.theme.textSecondary,
            accentColor: this.theme.accent,
            dataScope: this.dataScope,
            privacyMode: this.privacyMode,
            onPolicyApplied: (): void => {
              this.handleBack();
            }
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
  }

  private syncBoundaryRouteState(): void {
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
  }

  private handleBack(): boolean {
    if (this.isLeaving) {
      return true;
    }
    this.isLeaving = true;
    this.navigationCoordinator.back();
    return true;
  }
}
