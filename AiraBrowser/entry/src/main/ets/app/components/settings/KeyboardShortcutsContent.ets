import {
  KeyboardShortcutGroupState,
  KeyboardShortcutRowState,
  KeyboardShortcutsSettingsViewModel
} from '../../../core/settings/KeyboardShortcutsSettingsViewModel';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from './SettingsLayout';
import { SettingsRowPosition } from './SettingsRows';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const SHORTCUT_ROW_HORIZONTAL_PADDING = 16;
const SHORTCUT_ROW_VERTICAL_PADDING = 14;
const SHORTCUT_BADGE_HORIZONTAL_PADDING = 10;
const SHORTCUT_BADGE_MIN_HEIGHT = 28;
const SHORTCUT_BADGE_RADIUS = 8;
const SHORTCUT_ROW_CORNER_RADIUS = 18;

/**
 * Large-screen embedded body of the keyboard shortcuts page (no page scaffold /
 * back bar — the settings workspace header provides those). Phone keeps using
 * KeyboardShortcutsSettingsPage untouched.
 */
@Component
export struct KeyboardShortcutsContent {
  private viewModel: KeyboardShortcutsSettingsViewModel = new KeyboardShortcutsSettingsViewModel();
  @Prop desktopPresentation: boolean = false;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private groups: KeyboardShortcutGroupState[] = this.viewModel.buildGroups();

  build() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      bottomPadding: 18
    }) {
      Column({ space: 16 }) {
        ForEach(this.groups, (group: KeyboardShortcutGroupState) => {
          this.buildGroup(group)
        }, (group: KeyboardShortcutGroupState) => group.id)

        SettingsFooterText({
          text: '快捷键在外接键盘或桌面/平板键盘环境下使用。',
          secondaryTextColor: this.storedSecondaryTextColor
        })
      }
      .width('100%')
    }
  }

  @Builder
  private buildGroup(group: KeyboardShortcutGroupState) {
    SettingsSection({
      title: group.title,
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(group.rows, (row: KeyboardShortcutRowState, index: number) => {
          this.buildShortcutRow(row, this.resolveRowPosition(index, group.rows.length))
          if (index < group.rows.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (row: KeyboardShortcutRowState) => row.id)
      }
    }
  }

  @Builder
  private buildShortcutRow(row: KeyboardShortcutRowState, rowPosition: SettingsRowPosition) {
    Row({ space: 12 }) {
      Text(row.title)
        .layoutWeight(1)
        .fontSize(this.desktopPresentation ? 15 : 16)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(row.shortcut)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .padding({
          left: SHORTCUT_BADGE_HORIZONTAL_PADDING,
          right: SHORTCUT_BADGE_HORIZONTAL_PADDING
        })
        .constraintSize({ minHeight: SHORTCUT_BADGE_MIN_HEIGHT })
        .backgroundColor(this.storedPressedBackgroundColor)
        .borderRadius(SHORTCUT_BADGE_RADIUS)
    }
    .width('100%')
    .padding({
      left: SHORTCUT_ROW_HORIZONTAL_PADDING,
      right: SHORTCUT_ROW_HORIZONTAL_PADDING,
      top: SHORTCUT_ROW_VERTICAL_PADDING,
      bottom: SHORTCUT_ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .borderRadius(this.resolveRowBorderRadius(rowPosition))
    .clip(true)
  }

  private resolveRowBorderRadius(_position: SettingsRowPosition): BorderRadiuses {
    return {
      topLeft: this.desktopPresentation ? 8 : SHORTCUT_ROW_CORNER_RADIUS,
      topRight: this.desktopPresentation ? 8 : SHORTCUT_ROW_CORNER_RADIUS,
      bottomLeft: this.desktopPresentation ? 8 : SHORTCUT_ROW_CORNER_RADIUS,
      bottomRight: this.desktopPresentation ? 8 : SHORTCUT_ROW_CORNER_RADIUS
    };
  }

  private resolveRowPosition(index: number, count: number): SettingsRowPosition {
    if (count <= 1) {
      return 'single';
    }
    if (index <= 0) {
      return 'first';
    }
    if (index >= count - 1) {
      return 'last';
    }
    return 'middle';
  }
}
