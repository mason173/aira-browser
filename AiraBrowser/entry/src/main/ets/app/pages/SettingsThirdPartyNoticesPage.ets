import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import { MarkdownDocumentTheme } from '../../services/markdown/MarkdownDocumentViewerService';
import { ThirdPartyNoticesMarkdownService } from '../../services/settings/ThirdPartyNoticesMarkdownService';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';

@Entry
@Component
struct SettingsThirdPartyNoticesPage {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) @Watch('reloadNotices')
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) @Watch('reloadNotices')
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) @Watch('reloadNotices')
  private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) @Watch('reloadNotices')
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) @Watch('reloadNotices')
  private storedSecondaryTextColor: string = '#5F6875';
  private noticesService: ThirdPartyNoticesMarkdownService = new ThirdPartyNoticesMarkdownService();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private webController: webview.WebviewController = new webview.WebviewController();
  private webControllerAttached: boolean = false;

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '第三方开源许可',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
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
            this.loadNotices();
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private loadNotices(): void {
    if (!this.webControllerAttached) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const payload: BrowserWebLoadDataPayload = this.noticesService.buildPayload(
        context,
        this.buildMarkdownTheme()
      );
      this.webController.loadData(
        payload.data,
        payload.mimeType,
        payload.encoding,
        payload.baseUrl,
        payload.historyUrl
      );
    } catch (_error) {
      this.showToast('第三方许可声明加载失败');
    }
  }

  private reloadNotices(): void {
    this.loadNotices();
  }

  private buildMarkdownTheme(): MarkdownDocumentTheme {
    return {
      pageBackground: this.storedPageBackgroundColor,
      primaryText: this.storedPrimaryTextColor,
      secondaryText: this.storedSecondaryTextColor,
      divider: this.storedDividerColor,
      pressedBackground: this.storedPressedBackgroundColor
    };
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
}
