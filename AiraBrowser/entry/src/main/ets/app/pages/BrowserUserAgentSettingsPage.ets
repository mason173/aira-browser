import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { BrowserUserAgentSettings } from '../../common/models/BrowserModels';
import {
  BrowserUserAgentSettingsViewModel,
  BrowserUserAgentSettingsViewState
} from '../../core/settings/BrowserUserAgentSettingsViewModel';
import { BrowserUserAgentSettingsScreen } from '../components/settings/BrowserUserAgentSettingsScreen';
import { sharedBrowserUserAgentSettingsRepository } from '../bootstrap/BrowserAppRuntime';
import {
  readBrowserBoundaryRouteState,
  readSettingsTargetRouteState
} from '../../common/utils/RouteParamUtils';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';

@Entry
@Component
struct BrowserUserAgentSettingsPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private viewModel: BrowserUserAgentSettingsViewModel = new BrowserUserAgentSettingsViewModel();
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private settingsRevealTargetId: string = '';
  @State private state: BrowserUserAgentSettingsViewState =
    this.viewModel.buildState(sharedBrowserUserAgentSettingsRepository.getSettings());

  aboutToAppear(): void {
    this.settingsRevealTargetId = readSettingsTargetRouteState().settingsRevealTargetId;
    this.refreshState();
  }

  onPageShow(): void {
    this.refreshState();
  }

  build() {
    Column() {
      BrowserUserAgentSettingsScreen({
        state: this.state,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        revealTargetId: this.settingsRevealTargetId,
        revealRevision: this.settingsRevealTargetId.length > 0 ? 1 : 0,
        onSettingsChange: (settings: BrowserUserAgentSettings): void => {
          this.state = this.viewModel.buildState(settings);
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

  private refreshState(): void {
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.state = this.viewModel.buildState(sharedBrowserUserAgentSettingsRepository.getSettings());
  }
}
