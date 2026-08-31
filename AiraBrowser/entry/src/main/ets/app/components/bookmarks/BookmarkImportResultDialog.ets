import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct BookmarkImportResultDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link summary: string;
  @Link importedFolderCount: number;
  @Link importedBookmarkCount: number;
  @Link duplicateCount: number;
  @Link skippedNodeCount: number;

  build() {
    Column({ space: 16 }) {
      Text('导入成功')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Column({ space: 0 }) {
        this.buildResultRow('结果', this.buildOutcomeText(), 2)
        this.buildDivider()
        this.buildResultRow('新增内容', this.formatImportedContent(), 2)
        if (this.duplicateCount > 0 || this.skippedNodeCount > 0) {
          this.buildDivider()
          this.buildResultRow('未导入', this.formatSkippedContent(), 2)
        }
      }
      .width('100%')

      BrowserSheetActionButton({
        label: '知道了',
        emphasis: 'primary',
        accentColor: this.storedAccentColor,
        fillAvailableWidth: false,
        buttonWidth: '100%',
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.controller?.close();
        }
      })
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }

  @Builder
  private buildResultRow(label: string, value: string, maxLines: number) {
    Row({ space: 16 }) {
      Text(label)
        .width(86)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(value)
        .layoutWeight(1)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.End)
        .maxLines(maxLines)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildDivider() {
    Divider()
      .width('100%')
      .height(1)
      .color(this.storedDividerColor)
  }

  private buildOutcomeText(): string {
    if (this.importedFolderCount > 0 || this.importedBookmarkCount > 0) {
      return '已添加到本机书签。';
    }
    if (this.duplicateCount > 0) {
      return '没有新增内容，文件里的书签已存在。';
    }
    if (this.skippedNodeCount > 0) {
      return '没有新增内容，部分内容格式不完整。';
    }
    return this.summary.length > 0 ? this.summary : '没有新增内容。';
  }

  private formatImportedContent(): string {
    const segments: string[] = [];
    if (this.importedFolderCount > 0) {
      segments.push(`${Math.max(0, Math.floor(this.importedFolderCount))} 个文件夹`);
    }
    if (this.importedBookmarkCount > 0) {
      segments.push(`${Math.max(0, Math.floor(this.importedBookmarkCount))} 个书签`);
    }
    return segments.length > 0 ? segments.join('，') : '没有新增内容';
  }

  private formatSkippedContent(): string {
    const segments: string[] = [];
    if (this.duplicateCount > 0) {
      segments.push(`${Math.max(0, Math.floor(this.duplicateCount))} 个已存在`);
    }
    if (this.skippedNodeCount > 0) {
      segments.push(`${Math.max(0, Math.floor(this.skippedNodeCount))} 个格式不完整`);
    }
    return segments.length > 0 ? segments.join('，') : '无';
  }
}
