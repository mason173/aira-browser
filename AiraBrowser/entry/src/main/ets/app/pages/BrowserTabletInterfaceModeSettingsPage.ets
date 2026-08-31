import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { BrowserTabletInterfaceModeSettingsContent } from '../components/settings/BrowserTabletInterfaceModeSettingsContent';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';
import { SettingsNavigationCoordinator, SettingsRouteParams } from '../router/SettingsNavigationCoordinator';
import { BrowserBoundaryRouteState, readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { BrowserTabletInterfaceMode } from '../../common/models/BrowserDevicePresentationModels';
import { sharedBrowserTabletInterfaceModeRepository } from '../bootstrap/BrowserAppRuntime';
import { sharedBrowserTabletInterfaceModeTransitionOwner } from '../../core/settings/BrowserTabletInterfaceModeTransitionOwner';
import { requestBrowserShellIntent } from '../../core/navigation/BrowserNativeNavigationRequestCenter';

@Entry
@Component
struct BrowserTabletInterfaceModeSettingsPage {
  private readonly navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private tabletInterfaceModeListenerKey: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };

  aboutToAppear(): void {
    this.boundary = readBrowserBoundaryRouteState(this.boundary);
    this.bindTabletInterfaceModeUpdates();
  }

  aboutToDisappear(): void {
    this.unbindTabletInterfaceModeUpdates();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '界面模式',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        onBack: (): void => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({ topPadding: 16 }) {
          BrowserTabletInterfaceModeSettingsContent({
            surfaceBackground: this.storedSurfaceBackgroundColor,
            dividerColor: this.storedDividerColor,
            accentColor: this.storedAccentColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            dataScope: this.boundary.dataScope,
            privacyMode: this.boundary.privacyMode,
            transitionConsumer: 'standalone_settings_route'
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private bindTabletInterfaceModeUpdates(): void {
    if (this.tabletInterfaceModeListenerKey.length > 0) {
      return;
    }
    this.tabletInterfaceModeListenerKey = sharedBrowserTabletInterfaceModeRepository.subscribe(
      (mode: BrowserTabletInterfaceMode): void => {
        if (!sharedBrowserTabletInterfaceModeTransitionOwner.consumeCommitted(
          mode,
          'standalone_settings_route'
        )) {
          return;
        }
        this.returnHomeAfterInterfaceModeCommit();
      }
    );
  }

  private unbindTabletInterfaceModeUpdates(): void {
    if (this.tabletInterfaceModeListenerKey.length <= 0) {
      return;
    }
    sharedBrowserTabletInterfaceModeRepository.unsubscribe(this.tabletInterfaceModeListenerKey);
    this.tabletInterfaceModeListenerKey = '';
  }

  private returnHomeAfterInterfaceModeCommit(): void {
    const params: SettingsRouteParams = {
      dataScope: this.boundary.dataScope,
      privacyMode: this.boundary.privacyMode,
      boundarySource: this.boundary.boundarySource
    };
    requestBrowserShellIntent('return_home');
    this.navigationCoordinator.backToBrowserShell(params);
  }
}
