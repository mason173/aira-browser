import { HistoryViewMode } from '../../../features/history/HistoryViewModel';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import {
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';

const HISTORY_VIEW_MODE_OPTIONS: SegmentedTabOption[] = [
  { id: 'timeline', title: '时间线' },
  { id: 'sites', title: '站点' }
];

@Component
export struct HistoryManagerHeader {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop searchQuery: string = '';
  @Prop viewMode: HistoryViewMode = 'timeline';
  onSearchQueryChange: (value: string) => void = (_value: string) => {};
  onClearSearch: () => void = () => {};
  onChangeViewMode: (mode: HistoryViewMode) => void = (_mode: HistoryViewMode) => {};

  build() {
    Column({ space: 10 }) {
      this.buildSearchField()
      this.buildViewModeBar()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 8 })
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
      Stack({ alignContent: Alignment.End }) {
        TextInput({ text: this.searchQuery, placeholder: '搜索历史记录' })
          .width('100%')
          .height(40)
          .type(InputType.Normal)
          .enterKeyType(EnterKeyType.Search)
          .fontSize(15)
          .fontColor(this.storedPrimaryTextColor)
          .placeholderColor(this.storedSecondaryTextColor)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .borderRadius(20)
          .padding({ left: 14, right: this.searchQuery.length > 0 ? 44 : 14 })
          .onChange((value: string) => {
            this.onSearchQueryChange(value);
          })

        if (this.searchQuery.length > 0) {
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.storedSecondaryTextColor])
          }
          .width(34)
          .height(34)
          .margin({ right: 3 })
          .type(ButtonType.Circle)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .accessibilityText('清除搜索内容')
          .stateEffect(true)
          .onClick(() => {
            this.onClearSearch();
          })
        }
      }
      .width('100%')
      .height(40)
    }
  }

  @Builder
  private buildViewModeBar() {
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
        onSelect: (id: string) => {
          this.onChangeViewMode(id as HistoryViewMode);
        }
      })
        .width('100%')
        .height(36)
    }
  }

}
