import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

interface SyncResultDialogRow {
  key: string;
  label: string;
  value: string;
  isKeyValue: boolean;
}

@CustomDialog
export struct SyncResultDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link title: string;
  @Link message: string;

  build() {
    Column({ space: 16 }) {
      Text(this.title.length > 0 ? this.title : '操作结果')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.buildRows(this.message), (row: SyncResultDialogRow) => {
            if (row.isKeyValue) {
              this.buildKeyValueRow(row.label, row.value)
            } else {
              this.buildParagraphRow(row.value)
            }
          }, (row: SyncResultDialogRow) => row.key)
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 320 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

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
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildKeyValueRow(label: string, value: string) {
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
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Top)

    this.buildDivider()
  }

  @Builder
  private buildParagraphRow(value: string) {
    Text(value)
      .width('100%')
      .fontSize(14)
      .lineHeight(21)
      .fontColor(this.storedPrimaryTextColor)
      .textAlign(TextAlign.Start)
      .maxLines(5)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ top: 10, bottom: 10 })

    this.buildDivider()
  }

  @Builder
  private buildDivider() {
    Divider()
      .width('100%')
      .height(1)
      .color(this.storedDividerColor)
  }

  private buildRows(message: string): SyncResultDialogRow[] {
    const rows: SyncResultDialogRow[] = [];
    const normalized = message.trim().length > 0 ? message.replace(/\r/g, '') : '操作已完成。';
    const lines = normalized.split('\n');
    lines.forEach((line: string, index: number) => {
      const trimmed = line.trim();
      if (trimmed.length === 0 || this.shouldHideTechnicalLine(trimmed)) {
        return;
      }
      const separatorIndex = this.findSeparatorIndex(trimmed);
      if (separatorIndex > 0) {
        rows.push({
          key: `${index}-kv-${trimmed}`,
          label: trimmed.substring(0, separatorIndex),
          value: trimmed.substring(separatorIndex + 1).trim(),
          isKeyValue: true
        });
        return;
      }
      rows.push({
        key: `${index}-p-${trimmed}`,
        label: '',
        value: trimmed,
        isKeyValue: false
      });
    });
    if (rows.length === 0) {
      rows.push({
        key: 'fallback',
        label: '',
        value: '操作已完成。',
        isKeyValue: false
      });
    }
    return rows;
  }

  private findSeparatorIndex(text: string): number {
    const chineseIndex = text.indexOf('：');
    const asciiIndex = text.indexOf(':');
    if (chineseIndex < 0) {
      return asciiIndex;
    }
    if (asciiIndex < 0) {
      return chineseIndex;
    }
    return Math.min(chineseIndex, asciiIndex);
  }

  private shouldHideTechnicalLine(line: string): boolean {
    const normalized = line.trim().toLowerCase();
    if (normalized.length === 0) {
      return true;
    }
    if (normalized.startsWith('commit：') || normalized.startsWith('commit:') ||
      normalized.indexOf(' commit=') >= 0 || normalized.startsWith('当前 uid：') ||
      normalized.startsWith('当前 uid:') || normalized.startsWith('uid：') ||
      normalized.startsWith('uid:') || normalized.startsWith('技术信息：') ||
      normalized.startsWith('技术信息:')) {
      return true;
    }
    return normalized.startsWith('ok ') || normalized.startsWith('fail ');
  }
}
