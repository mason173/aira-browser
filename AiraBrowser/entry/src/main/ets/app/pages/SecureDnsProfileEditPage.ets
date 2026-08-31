import router from '@ohos.router';
import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsKeyboardAvoidModeCoordinator } from '../../core/settings/SettingsKeyboardAvoidModeCoordinator';
import { SecureDnsProfileEditHost } from '../components/settings/SecureDnsProfileEditHost';

@Entry
@Component
struct SecureDnsProfileEditPage {
  private keyboardAvoidModeCoordinator: SettingsKeyboardAvoidModeCoordinator =
    new SettingsKeyboardAvoidModeCoordinator();
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private profileId: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    this.profileId = params?.profileId ?? '';
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: params?.dataScope ?? '',
      privacyMode: params?.privacyMode ?? '',
      boundarySource: params?.boundarySource ?? ''
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
  }

  onPageShow(): void {
    this.keyboardAvoidModeCoordinator.activateCaretAwareResize(this.getUIContext());
  }

  onPageHide(): void {
    this.keyboardAvoidModeCoordinator.restore(this.getUIContext());
  }

  aboutToDisappear(): void {
    this.keyboardAvoidModeCoordinator.restore(this.getUIContext());
  }

  build() {
    Column() {
      SecureDnsProfileEditHost({
        profileId: this.profileId,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        onBack: (): void => {
          router.back();
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
}
