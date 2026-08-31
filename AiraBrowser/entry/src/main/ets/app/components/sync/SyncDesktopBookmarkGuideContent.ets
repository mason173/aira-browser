import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { BrowserWebLoadDataPayload } from '../../../core/browser/BrowserWebLoadCoordinator';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { MarkdownDocumentTheme } from '../../../services/markdown/MarkdownDocumentViewerService';
import { SyncDesktopBookmarkGuideMarkdownService } from '../../../services/sync/SyncDesktopBookmarkGuideMarkdownService';

@Component
export struct SyncDesktopBookmarkGuideContent {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) @Watch('reloadGuide')
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) @Watch('reloadGuide')
  private storedPageBackgroundColor: string = '#F6F8FB';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) @Watch('reloadGuide')
  private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) @Watch('reloadGuide')
  private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) @Watch('reloadGuide')
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) @Watch('reloadGuide')
  private storedSecondaryTextColor: string = '#5F6875';
  private guideMarkdownService: SyncDesktopBookmarkGuideMarkdownService =
    new SyncDesktopBookmarkGuideMarkdownService();
  private webController: webview.WebviewController = new webview.WebviewController();
  private webControllerAttached: boolean = false;

  aboutToDisappear(): void {
    this.webControllerAttached = false;
  }

  build() {
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
        this.loadGuide();
      })
      .onLoadIntercept((event: OnLoadInterceptEvent) => {
        return this.handleGuideLinkRequest(event.data);
      })
      .onOverrideUrlLoading((request: WebResourceRequest) => {
        return this.handleGuideLinkRequest(request);
      })
  }

  private async loadGuide(): Promise<void> {
    if (!this.webControllerAttached) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const payload: BrowserWebLoadDataPayload =
        await this.guideMarkdownService.buildPayload(context, this.buildMarkdownTheme());
      if (!this.webControllerAttached) {
        return;
      }
      this.webController.loadData(
        payload.data,
        payload.mimeType,
        payload.encoding,
        payload.baseUrl,
        payload.historyUrl
      );
    } catch (_error) {
      this.showToast('跨设备指南加载失败');
    }
  }

  private reloadGuide(): void {
    this.loadGuide();
  }

  private buildMarkdownTheme(): MarkdownDocumentTheme {
    return {
      pageBackground: this.storedPageBackgroundColor,
      surfaceBackground: this.storedSurfaceBackgroundColor,
      primaryText: this.storedPrimaryTextColor,
      secondaryText: this.storedSecondaryTextColor,
      divider: this.storedDividerColor,
      pressedBackground: this.storedPressedBackgroundColor
    };
  }

  private handleGuideLinkRequest(request: WebResourceRequest): boolean {
    if (!request.isMainFrame() || !request.isRequestGesture()) {
      return false;
    }
    const url = request.getRequestUrl();
    if (!this.guideMarkdownService.shouldCopyGuideLink(url)) {
      return false;
    }
    this.copyGuideLink(url);
    return true;
  }

  private copyGuideLink(url: string): void {
    this.guideMarkdownService.copyGuideLink(url)
      .then((result) => {
        this.showToast(result.message);
      })
      .catch((_error: Error) => {
        this.showToast('复制失败，请稍后重试。');
      });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_error) {
    }
  }
}
