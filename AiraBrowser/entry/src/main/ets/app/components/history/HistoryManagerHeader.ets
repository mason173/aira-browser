import { HistoryViewMode } from '../../../features/history/HistoryViewModel';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';

const HISTORY_VIEW_MODE_OPTIONS: SegmentedTabOption[] = [
  { id: 'timeline', title: '时间线' },
  { id: 'sites', title: '站点' }
];

@Component
export struct HistoryManagerHeader {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop viewMode: HistoryViewMode = 'timeline';
  onChangeViewMode: (mode: HistoryViewMode) => void = (_mode: HistoryViewMode) => {};

  build() {
    Column() {
      this.buildViewModeBar()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 0, bottom: 8 })
  }

  @Builder
  private buildViewModeBar() {
    FloatingGlassMaterialSurface({
      surfaceWidth: '100%',
      surfaceHeight: 36,
      surfaceRadius: 18,
      tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      fallbackColor: this.storedControlBackgroundColor,
      backgroundBlurEnabled: false
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
