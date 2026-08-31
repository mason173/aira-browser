import {
  BrowserQuickSearchEngineItem,
  BrowserQuickSearchSwitchingPresentation
} from '../../../core/search/BrowserQuickSearchSwitchingCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';

const QUICK_SEARCH_ENGINE_ITEM_MAX_WIDTH: number = 160;
const QUICK_SEARCH_ENGINE_ITEM_HORIZONTAL_PADDING: number = 14;
const QUICK_SEARCH_SELECTED_REVEAL_DELAY_MS: number = 40;

@Component
export struct BrowserQuickSearchSwitchBar {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @Prop surfaceColor: ResourceColor = DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @Prop @Watch('scheduleSelectedEngineReveal') presentation: BrowserQuickSearchSwitchingPresentation = {
    visible: false,
    occupiedHeightPx: 0,
    query: '',
    selectedEngineId: '',
    engines: []
  };
  onSelectEngine: (engineId: string) => void = (_engineId: string) => {};
  private engineScroller: Scroller = new Scroller();
  private visibleStartIndex: number = -1;
  private visibleEndIndex: number = -1;
  private selectedRevealTimer: number = 0;

  aboutToAppear(): void {
    this.scheduleSelectedEngineReveal();
  }

  aboutToDisappear(): void {
    this.clearSelectedEngineRevealTimer();
  }

  build() {
    List({ space: 2, scroller: this.engineScroller }) {
      ForEach(this.presentation.engines, (item: BrowserQuickSearchEngineItem) => {
        ListItem() {
          Button() {
            Text(item.label)
              .fontSize(14)
              .fontWeight(item.selected ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(item.selected ? this.storedAccentColor : this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({
                maxWidth: QUICK_SEARCH_ENGINE_ITEM_MAX_WIDTH -
                  QUICK_SEARCH_ENGINE_ITEM_HORIZONTAL_PADDING * 2
              })
          }
            .height('100%')
            .type(ButtonType.Capsule)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .constraintSize({ minWidth: 48, maxWidth: QUICK_SEARCH_ENGINE_ITEM_MAX_WIDTH })
            .padding({
              left: QUICK_SEARCH_ENGINE_ITEM_HORIZONTAL_PADDING,
              right: QUICK_SEARCH_ENGINE_ITEM_HORIZONTAL_PADDING
            })
            .backgroundColor(this.surfaceColor)
            .stateEffect(!item.selected)
            .accessibilityText(`${item.label}${item.selected ? '，当前搜索引擎' : ''}`)
            .onFocus(() => {
              this.revealEngine(item.engineId);
            })
            .onClick(() => {
              if (!item.selected) {
                this.onSelectEngine(item.engineId);
              }
            })
        }
        .height('100%')
      }, (item: BrowserQuickSearchEngineItem) =>
        `${item.engineId}:${item.label}:${item.selected ? 'selected' : 'unselected'}`)
    }
    .width('100%')
    .height('100%')
    .listDirection(Axis.Horizontal)
    .alignListItem(ListItemAlign.Center)
    .padding({ left: 4, right: 4 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onScrollIndex((start: number, end: number) => {
      this.visibleStartIndex = start;
      this.visibleEndIndex = end;
    })
  }

  private scheduleSelectedEngineReveal(): void {
    this.clearSelectedEngineRevealTimer();
    this.selectedRevealTimer = setTimeout(() => {
      this.selectedRevealTimer = 0;
      const selectedIndex = this.presentation.engines.findIndex((item: BrowserQuickSearchEngineItem): boolean => {
        return item.selected;
      });
      if (selectedIndex < 0 ||
        (selectedIndex >= this.visibleStartIndex && selectedIndex <= this.visibleEndIndex)) {
        return;
      }
      this.engineScroller.scrollToIndex(selectedIndex, true, ScrollAlign.CENTER);
    }, QUICK_SEARCH_SELECTED_REVEAL_DELAY_MS);
  }

  private clearSelectedEngineRevealTimer(): void {
    if (this.selectedRevealTimer === 0) {
      return;
    }
    clearTimeout(this.selectedRevealTimer);
    this.selectedRevealTimer = 0;
  }

  private revealEngine(engineId: string): void {
    const engineIndex = this.presentation.engines.findIndex((item: BrowserQuickSearchEngineItem): boolean => {
      return item.engineId === engineId;
    });
    if (engineIndex < 0 || (engineIndex >= this.visibleStartIndex && engineIndex <= this.visibleEndIndex)) {
      return;
    }
    this.engineScroller.scrollToIndex(engineIndex, true, ScrollAlign.CENTER);
  }
}
