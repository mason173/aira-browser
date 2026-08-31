import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { WebLoadErrorPresentation } from '../../../services/web/WebLoadErrorPresentationService';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct BrowserWebErrorSurface {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#C8D0DA';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop presentation: WebLoadErrorPresentation = {
    title: '',
    summary: '',
    host: '',
    primaryActionLabel: '重新加载',
    secondaryActionLabel: '打开首页',
    tertiaryActionLabel: '复制详情',
    detailLabel: '错误详情',
    detailText: '',
    hints: []
  };
  @Prop bottomChromeInsetVp: number = 0;
  @Prop showDetails: boolean = true;
  onReload: () => void = (): void => {};
  onSecondaryAction: () => void = (): void => {};

  build() {
    Column() {
      Blank()
        .layoutWeight(1)

      Column({ space: 28 }) {
        this.buildCopy()
        if (this.showDetails) {
          this.buildDetails()
        }
        this.buildActions()
      }
      .width('100%')
      .padding({ left: 28, right: 28, top: 16, bottom: 16 })

      Blank()
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 28, right: 28, top: 48, bottom: this.resolveBottomPadding() })
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private resolveBottomPadding(): number {
    return Math.max(40, Math.ceil(this.bottomChromeInsetVp) + 20);
  }

  @Builder
  private buildCopy() {
    Column({ space: 8 }) {
      Stack() {
        Circle()
          .width(34)
          .height(34)
          .fill($r('sys.color.ohos_id_color_background_transparent'))
          .stroke(this.storedPrimaryTextColor)
          .strokeWidth(2)

        Divider()
          .width(32)
          .strokeWidth(2)
          .color(this.storedPrimaryTextColor)

        Ellipse()
          .width(14)
          .height(34)
          .fill($r('sys.color.ohos_id_color_background_transparent'))
          .stroke(this.storedPrimaryTextColor)
          .strokeWidth(2)
      }
      .width(64)
      .height(64)
      .borderRadius(18)
      .border({
        width: 1,
        color: this.storedOutlineColor
      })
      .margin({ bottom: 16 })

      Text(this.presentation.title)
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.presentation.summary)
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .lineHeight(21)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildActions() {
    Column({ space: 14 }) {
      Button(this.resolvePrimaryActionLabel())
        .width('100%')
        .height(46)
        .type(ButtonType.Normal)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedOnPrimaryColor)
        .backgroundColor(this.storedAccentColor)
        .borderRadius(23)
        .onClick(() => {
          this.onReload();
        })

      Button(this.resolveSecondaryActionLabel())
        .height(36)
        .type(ButtonType.Normal)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)
        .onClick(() => {
          this.onSecondaryAction();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildDetails() {
    Column({ space: 10 }) {
      if (this.presentation.detailText.trim().length > 0) {
        Text(this.presentation.detailText)
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .lineHeight(18)
          .wordBreak(WordBreak.BREAK_ALL)
          .width('100%')
      }

      ForEach(this.presentation.hints, (hint: string) => {
        Text(hint)
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .lineHeight(18)
          .width('100%')
      }, (hint: string) => hint)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 2, right: 2 })
  }

  private resolvePrimaryActionLabel(): string {
    const label = this.presentation.primaryActionLabel.trim();
    return label.length > 0 ? label : '再试一次';
  }

  private resolveSecondaryActionLabel(): string {
    const label = this.presentation.secondaryActionLabel.trim();
    return label.length > 0 ? label : '转到系统设置';
  }
}
