import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { SearchFallbackEngineHost } from '../components/search/SearchFallbackEngineHost';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';

@Entry
@Component
struct SearchFallbackEnginePage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;

  build() {
    Column() {
      SearchFallbackEngineHost()
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
