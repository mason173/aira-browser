import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { ManualElementHideSiteRulesHost } from '../components/adblock/ManualElementHideSiteRulesHost';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';

interface ManualElementHideSiteRulesPageParams extends BrowserBoundaryRouteState {
  host?: string;
}

@Entry
@Component
struct ManualElementHideSiteRulesPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private host: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as ManualElementHideSiteRulesPageParams | undefined;
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: params?.dataScope ?? this.dataScope,
      privacyMode: params?.privacyMode ?? this.privacyMode,
      boundarySource: params?.boundarySource ?? this.boundarySource
    });
    this.host = String(params?.host ?? '').trim().toLowerCase();
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
  }

  build() {
    Column() {
      ManualElementHideSiteRulesHost({
        host: this.host,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        onBack: () => {
          this.back();
        },
        onSiteRemoved: () => {
          this.back();
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

  private back(): void {
    this.getUIContext().getRouter().back();
  }
}
