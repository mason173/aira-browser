import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { HistoryViewMode } from '../../../features/history/HistoryViewModel';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { AiraIcon } from '../common/AiraIcon';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';

export const HISTORY_LARGE_SCREEN_SEARCH_FOCUS_KEY: string = 'history-large-screen-search';
const HISTORY_VIEW_MODE_OPTIONS: SegmentedTabOption[] = [
  { id: 'timeline', title: '时间线' },
  { id: 'sites', title: '按站点' }
];

@Component
export struct HistoryLargeScreenHeader {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY)
  private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;

  @Prop query: string = '';
  @Prop viewMode: HistoryViewMode = 'timeline';
  @Prop site: string = '';
  @Prop visitCount: number = 0;
  @Prop selectedCount: number = 0;
  @Prop loading: boolean = false;
  @Prop busy: boolean = false;
  @Prop privateMode: boolean = false;
  @State private clearAllHovered: boolean = false;
  onQueryChange: (query: string) => void = (_query: string): void => {};
  onViewModeChange: (viewMode: HistoryViewMode) => void = (_viewMode: HistoryViewMode): void => {};
  onOpenSelection: () => void = (): void => {};
  onDeleteSelection: () => void = (): void => {};
  onClearSelection: () => void = (): void => {};
  onClearAll: () => void = (): void => {};

  build() {
    Column({ space: 10 }) {
      this.buildTitleRow()

      if (this.selectedCount === 0) {
        this.buildSearchField()

        FloatingGlassMaterialSurface({
          surfaceWidth: '100%',
          surfaceHeight: 36,
          surfaceRadius: 18,
          tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
          fallbackColor: $r('app.color.browser_bottom_toolbar_glass_background'),
          backgroundBlurEnabled: true
        }) {
          SegmentedTabs({
            options: HISTORY_VIEW_MODE_OPTIONS,
            selectedId: this.viewMode,
            barHeight: 36,
            itemHeight: 30,
            fontSize: 14,
            barPadding: 3,
            fallbackColor: $r('sys.color.ohos_id_color_background_transparent'),
            barMaterialEnabled: false,
            onSelect: (id: string): void => {
              this.onViewModeChange(id as HistoryViewMode);
            }
          })
            .width('100%')
            .height(36)
        }
      }
    }
    .width('100%')
    .padding({ top: 14, bottom: 12 })
  }

  @Builder
  private buildTitleRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.site.length > 0 ? this.site : '历史记录')
          .width('100%')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.site.length > 0) {
          Text('站点历史记录')
            .fontSize(12)
            .fontColor(this.storedSecondaryTextColor)
        } else if (this.selectedCount > 0) {
          Text(this.privateMode ? `常规历史 · 已选择 ${this.selectedCount} 项` : `已选择 ${this.selectedCount} 项`)
            .fontSize(12)
            .fontColor(this.storedSecondaryTextColor)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.privateMode && this.selectedCount === 0) {
        Text('常规历史')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedAccentColor)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.storedControlBackgroundColor)
          .borderRadius(10)
      } else if (this.selectedCount > 0) {
        Button('打开')
          .height(36)
          .fontSize(13)
          .fontColor(this.storedPrimaryTextColor)
          .type(ButtonType.Normal)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .backgroundColor(this.storedControlBackgroundColor)
          .borderRadius(18)
          .enabled(!this.busy)
          .onClick((): void => {
            this.onOpenSelection();
          })

        Button('删除')
          .height(36)
          .fontSize(13)
          .fontColor(this.storedPrimaryTextColor)
          .type(ButtonType.Normal)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .backgroundColor(this.storedControlBackgroundColor)
          .borderRadius(18)
          .enabled(!this.busy)
          .onClick((): void => {
            this.onDeleteSelection();
          })

        Button('完成')
          .height(36)
          .fontSize(13)
          .fontColor(this.storedAccentColor)
          .type(ButtonType.Normal)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .backgroundColor(this.storedControlBackgroundColor)
          .borderRadius(18)
          .onClick((): void => {
            this.onClearSelection();
          })
      } else {
        if (!this.loading) {
          Text(`${this.visitCount} 项`)
            .fontSize(12)
            .fontColor(this.storedSecondaryTextColor)
        }

        Button() {
          Row({ space: 6 }) {
            AiraIcon({
              airaIconId: 'browser.tabs.delete',
              iconSize: 15,
              iconColor: this.storedSecondaryTextColor
            })
            Text('清除')
              .fontSize(13)
              .fontColor(this.storedSecondaryTextColor)
          }
        }
        .height(36)
        .type(ButtonType.Normal)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.clearAllHovered
          ? this.storedPressedBackgroundColor
          : this.storedControlBackgroundColor)
        .borderRadius(18)
        .clip(true)
        .stateEffect(false)
        .hoverEffect(HoverEffect.None)
        .enabled(!this.busy && this.visitCount > 0)
        .onHover((hovered: boolean): void => {
          this.clearAllHovered = hovered;
        })
        .onClick((): void => {
          this.onClearAll();
        })
      }
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSearchField() {
    FloatingGlassMaterialSurface({
      surfaceWidth: '100%',
      surfaceHeight: 40,
      surfaceRadius: 20,
      tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      fallbackColor: $r('app.color.browser_bottom_toolbar_glass_background'),
      backgroundBlurEnabled: true
    }) {
      Row({ space: 8 }) {
        AiraIcon({
          airaIconId: 'settings.search',
          iconSize: 16,
          iconColor: this.storedSecondaryTextColor
        })

        TextInput({ text: this.query, placeholder: '搜索历史记录' })
          .key(HISTORY_LARGE_SCREEN_SEARCH_FOCUS_KEY)
          .layoutWeight(1)
          .height(36)
          .fontSize(15)
          .fontColor(this.storedPrimaryTextColor)
          .placeholderColor(this.storedSecondaryTextColor)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .padding(0)
          .onChange((value: string): void => {
            this.onQueryChange(value);
          })

        if (this.query.length > 0) {
          Button() {
            AiraIcon({
              airaIconId: 'browser.toolbar.clearInput',
              iconSize: 14,
              iconColor: this.storedSecondaryTextColor
            })
          }
          .width(30)
          .height(30)
          .type(ButtonType.Circle)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .accessibilityText('清除搜索')
          .onClick((): void => {
            this.onQueryChange('');
          })
        }
      }
      .width('100%')
      .height(40)
      .padding({ left: 14, right: 5 })
    }
  }
}
