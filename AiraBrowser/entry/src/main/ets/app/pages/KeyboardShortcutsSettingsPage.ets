import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  KeyboardShortcutGroupState,
  KeyboardShortcutRowState,
  KeyboardShortcutsSettingsViewModel
} from '../../core/settings/KeyboardShortcutsSettingsViewModel';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../components/settings/SettingsLayout';
import {
  SettingsRowPosition
} from '../components/settings/SettingsRows';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

const SHORTCUT_ROW_HORIZONTAL_PADDING = 16;
const SHORTCUT_ROW_VERTICAL_PADDING = 14;
const SHORTCUT_BADGE_HORIZONTAL_PADDING = 10;
const SHORTCUT_BADGE_MIN_HEIGHT = 28;
const SHORTCUT_BADGE_RADIUS = 8;
const SHORTCUT_ROW_CORNER_RADIUS = 18;

@Entry
@Component
struct KeyboardShortcutsSettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private viewModel: KeyboardShortcutsSettingsViewModel = new KeyboardShortcutsSettingsViewModel();
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private groups: KeyboardShortcutGroupState[] = this.viewModel.buildGroups();

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '键盘快捷键',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({ topPadding: 16 }) {
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildGroup(group: KeyboardShortcutGroupState) {
    SettingsSection({
      title: group.title,
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
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
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
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
      topLeft: SHORTCUT_ROW_CORNER_RADIUS,
      topRight: SHORTCUT_ROW_CORNER_RADIUS,
      bottomLeft: SHORTCUT_ROW_CORNER_RADIUS,
      bottomRight: SHORTCUT_ROW_CORNER_RADIUS
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
