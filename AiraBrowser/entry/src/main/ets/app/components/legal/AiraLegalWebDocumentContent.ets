import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { webview } from '@kit.ArkWeb';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraLegalWebStyleService } from '../../../services/legal/AiraLegalWebStyleService';

@Component
export struct AiraLegalWebDocumentContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) @Watch('applyWebPageStyle')
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) @Watch('applyWebPageStyle')
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) @Watch('applyWebPageStyle')
  private storedSecondaryTextColor: string = '#5F6875';
  @Prop documentUrl: string = '';
  @Prop styleId: string = 'aira-legal-document-style';
  private webController: webview.WebviewController = new webview.WebviewController();
  private webStyleService: AiraLegalWebStyleService = new AiraLegalWebStyleService();
  @State private webLoading: boolean = true;

  aboutToAppear(): void {
    this.webLoading = this.hasDocumentUrl();
  }

  build() {
    if (this.hasDocumentUrl()) {
      Stack() {
        Web({
          src: this.documentUrl,
          controller: this.webController
        })
          .width('100%')
          .height('100%')
          .backgroundColor(this.storedPageBackgroundColor)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageBegin((_event: OnPageBeginEvent) => {
            this.webLoading = true;
          })
          .onPageEnd((_event: OnPageEndEvent) => {
            this.finishWebLoading();
            this.applyWebPageStyle();
          })
          .onLoadFinished(() => {
            this.finishWebLoading();
            this.applyWebPageStyle();
          })

        if (this.webLoading) {
          this.buildWebLoadingOverlay()
        }
      }
      .width('100%')
      .height('100%')
    } else {
      this.buildPendingLinkState()
    }
  }

  @Builder
  private buildWebLoadingOverlay() {
    Column() {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(this.storedAccentColor)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildPendingLinkState() {
    Column() {
      Column({ space: 10 }) {
        Text('链接待配置')
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)

        Text('该协议将以公开网页形式提供。公网地址上线后，此入口会直接打开对应页面。')
          .width('100%')
          .fontSize(14)
          .lineHeight(22)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 22, bottom: 22 })
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .borderRadius(22)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 24 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  private hasDocumentUrl(): boolean {
    return this.documentUrl.trim().length > 0;
  }

  private finishWebLoading(): void {
    this.webLoading = false;
  }

  private applyWebPageStyle(): void {
    if (!this.hasDocumentUrl()) {
      return;
    }
    this.webStyleService.apply(this.webController, {
      styleId: this.styleId,
      pageBackground: this.storedPageBackgroundColor,
      primaryText: this.storedPrimaryTextColor,
      secondaryText: this.storedSecondaryTextColor
    });
  }
}
