import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { SearchBuiltInEnginesHost } from '../components/search/SearchBuiltInEnginesHost';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { readSettingsTargetRouteState } from '../../common/utils/RouteParamUtils';

@Entry
@Component
struct SearchBuiltInEnginesPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private settingsRevealTargetId: string = '';

  aboutToAppear(): void {
    this.settingsRevealTargetId = readSettingsTargetRouteState().settingsRevealTargetId;
  }

  build() {
    Column() {
      SearchBuiltInEnginesHost({
        revealTargetId: this.settingsRevealTargetId,
        revealRevision: this.settingsRevealTargetId.length > 0 ? 1 : 0
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
