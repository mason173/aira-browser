import {
  BROWSER_QUICK_SEARCH_SWITCH_BAR_HEIGHT,
  BrowserQuickSearchSwitchingPresentation
} from '../../../core/search/BrowserQuickSearchSwitchingCoordinator';
import { BROWSER_THEME_STORAGE_DIVIDER_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BrowserQuickSearchSwitchBar } from './BrowserQuickSearchSwitchBar';

@Component
export struct BrowserWebTopChromeOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string =
    DEFAULT_THEME_PALETTE.light.divider;
  @Prop overlayHeightPx: number = 0;
  @Prop surfaceColor: ResourceColor = DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @Prop colorTransitionDurationMs: number = 160;
  @Prop quickSearchPresentation: BrowserQuickSearchSwitchingPresentation = {
    visible: false,
    occupiedHeightPx: 0,
    query: '',
    selectedEngineId: '',
    engines: []
  };
  onSelectQuickSearchEngine: (engineId: string) => void = (_engineId: string) => {};

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Column() {
      }
        .width('100%')
        .height('100%')
        .backgroundColor(this.surfaceColor)
        .animation({ duration: this.colorTransitionDurationMs, curve: Curve.EaseOut })

      if (this.quickSearchPresentation.visible) {
        BrowserQuickSearchSwitchBar({
          presentation: this.quickSearchPresentation,
          surfaceColor: this.surfaceColor,
          onSelectEngine: (engineId: string) => {
            this.onSelectQuickSearchEngine(engineId);
          }
        })
          .width('100%')
          .height(BROWSER_QUICK_SEARCH_SWITCH_BAR_HEIGHT)
          .backgroundColor(this.surfaceColor)

        Divider()
          .width('100%')
          .strokeWidth(1)
          .color(this.storedDividerColor)
      }
    }
    .width('100%')
    .height(this.overlayHeightPx)
    .clip(true)
  }
}
