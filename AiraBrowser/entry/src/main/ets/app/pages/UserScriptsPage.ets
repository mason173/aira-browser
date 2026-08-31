import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { UserScriptManagementHost } from '../components/userscripts/UserScriptManagementHost';
import {
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';

@Entry
@Component
struct UserScriptsPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private pageShowRevision: number = 0;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.resolveBoundary();
  }

  onPageShow(): void {
    this.resolveBoundary();
    this.pageShowRevision += 1;
  }

  build() {
    Column() {
      UserScriptManagementHost({
        presentationMode: 'page',
        refreshRevision: this.pageShowRevision,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        onRequestClose: () => {
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

  private resolveBoundary(): void {
    const boundary = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundary.dataScope;
    this.privacyMode = boundary.privacyMode;
    this.boundarySource = boundary.boundarySource;
  }
}
