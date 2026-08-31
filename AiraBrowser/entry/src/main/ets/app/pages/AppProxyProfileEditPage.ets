import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { AppProxyProfileEditHost } from '../components/settings/AppProxyProfileEditHost';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsKeyboardAvoidModeCoordinator } from '../../core/settings/SettingsKeyboardAvoidModeCoordinator';

@Entry
@Component
struct AppProxyProfileEditPage {
  private keyboardAvoidModeCoordinator: SettingsKeyboardAvoidModeCoordinator =
    new SettingsKeyboardAvoidModeCoordinator();
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private profileId: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private pageShowRevision: number = 0;

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
    this.boundarySource = boundaryState.boundarySource;
  }

  onPageShow(): void {
    this.keyboardAvoidModeCoordinator.activateCaretAwareResize(this.getUIContext());
    this.pageShowRevision += 1;
  }

  onPageHide(): void {
    this.keyboardAvoidModeCoordinator.restore(this.getUIContext());
  }

  aboutToDisappear(): void {
    this.keyboardAvoidModeCoordinator.restore(this.getUIContext());
  }

  build() {
    Column() {
      AppProxyProfileEditHost({
        profileId: this.profileId,
        embedded: false,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        pageShowRevision: this.pageShowRevision
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
