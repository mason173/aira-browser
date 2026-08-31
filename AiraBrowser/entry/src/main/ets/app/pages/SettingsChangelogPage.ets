import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import {
  SettingsChangelogState,
  SettingsChangelogViewModel
} from '../../core/settings/SettingsChangelogViewModel';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { MarkdownDocumentTheme } from '../../services/markdown/MarkdownDocumentViewerService';
import { SettingsChangelogMarkdownService } from '../../services/settings/SettingsChangelogMarkdownService';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';

@Entry
@Component
struct SettingsChangelogPage {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) @Watch('reloadChangelog')
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) @Watch('reloadChangelog')
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) @Watch('reloadChangelog')
  private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) @Watch('reloadChangelog')
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) @Watch('reloadChangelog')
  private storedSecondaryTextColor: string = '#5F6875';
  private viewModel: SettingsChangelogViewModel = new SettingsChangelogViewModel();
  private changelogService: SettingsChangelogMarkdownService = new SettingsChangelogMarkdownService();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private webController: webview.WebviewController = new webview.WebviewController();
  private webControllerAttached: boolean = false;
  @State private state: SettingsChangelogState = this.viewModel.buildState();

  aboutToAppear(): void {
    this.state = this.viewModel.buildState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: this.state.title,
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
            this.loadChangelog();
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private loadChangelog(): void {
    if (!this.webControllerAttached) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const payload: BrowserWebLoadDataPayload = this.changelogService.buildPayload(context, this.buildMarkdownTheme());
      this.webController.loadData(
        payload.data,
        payload.mimeType,
        payload.encoding,
        payload.baseUrl,
        payload.historyUrl
      );
    } catch (_error) {
      this.showToast('更新日志加载失败');
    }
  }

  private reloadChangelog(): void {
    this.loadChangelog();
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
