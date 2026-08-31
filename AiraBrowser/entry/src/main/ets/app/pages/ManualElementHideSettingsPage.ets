import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { ManualElementHideHost } from '../components/adblock/ManualElementHideHost';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';

interface ManualElementHideSettingsPageParams extends BrowserBoundaryRouteState {
}

@Entry
@Component
struct ManualElementHideSettingsPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private pageShowRevision: number = 0;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as ManualElementHideSettingsPageParams | undefined;
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: params?.dataScope ?? this.dataScope,
      privacyMode: params?.privacyMode ?? this.privacyMode,
      boundarySource: params?.boundarySource ?? this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
  }

  onPageShow(): void {
    this.pageShowRevision += 1;
  }

  build() {
    Column() {
      ManualElementHideHost({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        refreshRevision: this.pageShowRevision,
        onBack: () => {
          this.getUIContext().getRouter().back();
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
