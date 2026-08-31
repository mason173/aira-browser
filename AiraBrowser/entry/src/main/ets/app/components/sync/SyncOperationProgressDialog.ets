import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct SyncOperationProgressDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link inProgress: boolean;
  @Link title: string;
  @Link subtitle: string;
  @Link progress: number;
  @Link details: string;
  @Link detailOpacity: number;

  build() {
    Column({ space: 16 }) {
      if (this.inProgress) {
        LoadingProgress()
          .width(72)
          .height(72)
          .color(this.storedAccentColor)
      } else {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(72)
          .fontColor([this.storedAccentColor])
      }

      Text(`${this.title.length > 0 ? this.title : '正在处理'}${this.resolveProgress()}%`)
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.details.length > 0 ? this.details : (this.subtitle.length > 0 ? this.subtitle : '请稍候'))
        .width('100%')
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .opacity(this.detailOpacity)
        .animation({ duration: 240, curve: Curve.EaseInOut })
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }

  private resolveProgress(): number {
    return Math.max(0, Math.min(100, Math.round(this.progress)));
  }
}
