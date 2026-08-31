import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { AppProxyProtocolSettingsHost } from '../components/settings/AppProxyProtocolSettingsHost';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';

@Entry
@Component
struct AppProxyProtocolSettingsPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private profileId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    this.profileId = params?.profileId ?? '';
  }

  build() {
    Column() {
      AppProxyProtocolSettingsHost({
        profileId: this.profileId,
        embedded: false
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
