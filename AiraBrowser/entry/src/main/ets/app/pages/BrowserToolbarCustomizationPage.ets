import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { BrowserToolbarCustomizationScreen } from '../components/settings/BrowserToolbarCustomizationScreen';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

@Entry
@Component
struct BrowserToolbarCustomizationPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.syncBoundaryRouteState();
  }

  build() {
    Column() {
      BrowserToolbarCustomizationScreen({
        showTitleBar: true,
        showBackButton: true,
        useTopSafeInset: true,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        onBack: () => {
          this.navigationCoordinator.back();
        },
        onOpenScrollBehavior: () => {
          this.navigationCoordinator.openBrowserToolbarScrollBehavior({
            dataScope: this.dataScope,
            privacyMode: this.privacyMode,
            boundarySource: this.boundarySource
          });
        }
      })
        .width('100%')
        .height('100%')
    }
      .width('100%')
      .height('100%')
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
}
