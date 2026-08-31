import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import {
  CustomHomepageDeveloperGuideService,
  CustomHomepageGuideExportResult,
  CustomHomepageGuideTheme
} from '../../services/customhome/CustomHomepageDeveloperGuideService';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { BrowserBoundaryRouteState, readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

@Entry
@Component
struct CustomHomepageDeveloperGuidePage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private guideService: CustomHomepageDeveloperGuideService = new CustomHomepageDeveloperGuideService();
  private webController: webview.WebviewController = new webview.WebviewController();
  private boundaryRouteState: BrowserBoundaryRouteState = readBrowserBoundaryRouteState();
  private webControllerAttached: boolean = false;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) @Watch('reloadGuide')
  private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) @Watch('reloadGuide')
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) @Watch('reloadGuide')
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) @Watch('reloadGuide')
  private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) @Watch('reloadGuide')
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) @Watch('reloadGuide')
  private storedSecondaryTextColor: string = '#5F6875';
  @State private busy: boolean = false;

  aboutToAppear(): void {
    this.boundaryRouteState = readBrowserBoundaryRouteState(this.boundaryRouteState);
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '开发文档',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
        menuActionLabel: '分享文档',
        menuActionAiraIconId: 'browser.toolbar.shareDocument',
        menuActionEnabled: !this.busy,
        onMenuAction: () => {
          this.shareGuide();
        },
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        Web({
          src: '',
          controller: this.webController
        })
          .width('100%')
          .height('100%')
          .backgroundColor(this.storedPageBackgroundColor)
          .javaScriptAccess(true)
          .domStorageAccess(false)
          .onControllerAttached(() => {
            this.webControllerAttached = true;
            this.loadGuideHtml();
          })
          .onLoadIntercept((event: OnLoadInterceptEvent) => {
            return this.handleGuideLinkRequest(event.data);
          })
          .onOverrideUrlLoading((request: WebResourceRequest) => {
            return this.handleGuideLinkRequest(request);
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private reloadGuide(): void {
    this.loadGuideHtml();
  }

  private loadGuideHtml(): void {
    if (!this.webControllerAttached) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const payload: BrowserWebLoadDataPayload = this.guideService.buildPayload(context, this.buildGuideTheme());
      this.webController.loadData(
        payload.data,
        payload.mimeType,
        payload.encoding,
        payload.baseUrl,
        payload.historyUrl
      );
    } catch (_error) {
      this.showToast('开发文档加载失败');
    }
  }

  private buildGuideTheme(): CustomHomepageGuideTheme {
    return {
      pageBackground: this.storedPageBackgroundColor,
      surfaceBackground: this.storedSurfaceBackgroundColor,
      primaryText: this.storedPrimaryTextColor,
      secondaryText: this.storedSecondaryTextColor,
      divider: this.storedDividerColor,
      accent: this.storedAccentColor
    };
  }

  private handleGuideLinkRequest(request: WebResourceRequest): boolean {
    if (!request.isMainFrame() || !request.isRequestGesture()) {
      return false;
    }
    const url = request.getRequestUrl();
    if (!this.guideService.shouldOpenGuideLinkInBrowser(url)) {
      return false;
    }
    this.navigationCoordinator.openBrowserUrlFromGuide(url, this.boundaryRouteState);
    return true;
  }

  private shareGuide(): void {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.guideService.shareMarkdown(context)
      .then((result: CustomHomepageGuideExportResult) => {
        this.showToast(result.message);
      })
      .catch((error: Error) => {
        this.showToast(`分享开发文档失败：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
