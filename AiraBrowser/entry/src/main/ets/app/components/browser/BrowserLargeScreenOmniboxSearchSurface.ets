import {
  ExternalAppSearchPreferences,
  ExternalAppSearchTargetId,
  SearchEngineId,
  SearchEngineRecord,
  SearchSuggestion
} from '../../../common/models/BrowserModels';
import {
  EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY
} from '../../../common/constants/SearchPreferenceKeys';
import {
  BrowserLargeScreenOmniboxSearchPresentation,
  BrowserLargeScreenOmniboxSearchViewModel,
  omniboxSuggestionSelectionKey
} from '../../../core/browser/BrowserLargeScreenOmniboxSearchViewModel';
import {
  BrowserSearchEngineChromePresentation
} from '../../../core/browser/BrowserSearchEnginePresentationViewModel';
import {
  BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP
} from '../../../core/browser/BrowserModalPresentationTokens';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { sharedExternalAppSearchPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';
import { SearchEngineIconResources } from '../search/SearchEngineIconResources';
import { AiraIcon } from '../common/AiraIcon';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { ExternalAppSearchStrip } from './ExternalAppSearchStrip';
import { AppWindowModalLayoutService } from '../../../services/layout/AppWindowModalLayoutService';

const LARGE_SCREEN_SEARCH_SURFACE_GAP_VP: number = 8;
const LARGE_SCREEN_SEARCH_CARD_PADDING_VP: number = 8;
const LARGE_SCREEN_SEARCH_CARD_RADIUS_VP: number = 20;
const LARGE_SCREEN_EXTERNAL_SEARCH_CARD_HEIGHT_VP: number = 86;
const LARGE_SCREEN_SUGGESTION_MAX_HEIGHT_VP: number = 296;
const LARGE_SCREEN_SUGGESTION_EMPTY_HEIGHT_VP: number = 64;
const LARGE_SCREEN_SUGGESTION_ROW_HEIGHT_VP: number = 34;
const LARGE_SCREEN_SUGGESTION_ROW_GAP_VP: number = 2;
const LARGE_SCREEN_SUGGESTION_ROW_RADIUS_VP: number =
  LARGE_SCREEN_SEARCH_CARD_RADIUS_VP - LARGE_SCREEN_SEARCH_CARD_PADDING_VP;
const LARGE_SCREEN_SUGGESTION_ROW_HORIZONTAL_PADDING_VP: number = 12;
const LARGE_SCREEN_SUGGESTION_HEADER_HEIGHT_VP: number = 30;
const LARGE_SCREEN_SUGGESTION_HEADER_TITLE_SIZE: number = 12;
const LARGE_SCREEN_SUGGESTION_HEADER_ACTION_SIZE: number = 12;
const LARGE_SCREEN_SUGGESTION_HEADER_ACTION_HEIGHT_VP: number = 24;
const LARGE_SCREEN_SUGGESTION_LEADING_ICON_SIZE_VP: number = 18;
const LARGE_SCREEN_SUGGESTION_LEADING_ICON_GAP_VP: number = 8;
const LARGE_SCREEN_SUGGESTION_DELETE_BUTTON_SIZE_VP: number = 28;
const LARGE_SCREEN_SUGGESTION_DELETE_ICON_SIZE_VP: number = 16;
const LARGE_SCREEN_SEARCH_ENGINE_BUTTON_SIZE_VP: number = 28;
const LARGE_SCREEN_SEARCH_ENGINE_ICON_SIZE_VP: number = 18;
const LARGE_SCREEN_SEARCH_ENGINE_POPUP_WIDTH_VP: number = 236;
const LARGE_SCREEN_SEARCH_ENGINE_POPUP_ROW_HEIGHT_VP: number = 46;
const LARGE_SCREEN_SEARCH_ENGINE_POPUP_MAX_VISIBLE_ROWS: number = 6;
const LARGE_SCREEN_SEARCH_ENGINE_POPUP_PADDING_VP: number = 6;
const LARGE_SCREEN_SEARCH_ENGINE_POPUP_ROW_RADIUS_VP: number = 12;

function createDefaultSearchEnginePresentation(): BrowserSearchEngineChromePresentation {
  return new BrowserSearchEngineChromePresentation('bing', [], '搜索或输入网址');
}

@Component
struct BrowserLargeScreenSuggestionRow {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';

  @Prop suggestion: SearchSuggestion = {
    id: '',
    title: '',
    source: 'search_history',
    target: ''
  };
  @Prop selected: boolean = false;
  @State private deleteHovered: boolean = false;
  onOpen: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion): void => {};
  onDelete: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion): void => {};
  onHighlight: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion): void => {};

  build() {
    Row({ space: 8 }) {
      Button() {
        Row({ space: LARGE_SCREEN_SUGGESTION_LEADING_ICON_GAP_VP }) {
          // The source icon leads the row so it reads as part of the entry, with
          // the label immediately after it; the delete action keeps the far edge.
          AiraIcon({
            airaIconId: this.isHistorySuggestion() ? 'membership.inviteRecordClock' : 'browser.toolbar.search',
            iconSize: LARGE_SCREEN_SUGGESTION_LEADING_ICON_SIZE_VP,
            iconColor: this.storedSecondaryTextColor
          })
            .hitTestBehavior(HitTestMode.None)

          Text(this.suggestion.title)
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 0 })
      .height('100%')
      .padding({ left: LARGE_SCREEN_SUGGESTION_ROW_HORIZONTAL_PADDING_VP })
      .type(ButtonType.Normal)
      .backgroundColor(Color.Transparent)
      .stateEffect(false)
      .hoverEffect(HoverEffect.None)
      .focusable(false)
      .focusOnTouch(false)
      .accessibilityText(this.suggestion.title)
      .onClick((): void => {
        this.onOpen(this.suggestion);
      })

      if (this.isHistorySuggestion()) {
        Button() {
          AiraIcon({
            airaIconId: 'browser.tabs.delete',
            iconSize: LARGE_SCREEN_SUGGESTION_DELETE_ICON_SIZE_VP,
            iconColor: this.storedSecondaryTextColor
          })
            .hitTestBehavior(HitTestMode.None)
        }
        .width(LARGE_SCREEN_SUGGESTION_DELETE_BUTTON_SIZE_VP)
        .height(LARGE_SCREEN_SUGGESTION_DELETE_BUTTON_SIZE_VP)
        .padding(0)
        .type(ButtonType.Circle)
        .backgroundColor(this.deleteHovered ? this.storedControlBackgroundColor : Color.Transparent)
        .stateEffect(false)
        .hoverEffect(HoverEffect.None)
        .focusable(false)
        .focusOnTouch(false)
        .accessibilityText('删除搜索记录')
        .onHover((hovered: boolean): void => {
          this.deleteHovered = hovered;
        })
        .onClick((): void => {
          this.onDelete(this.suggestion);
        })
      }
    }
    .width('100%')
    .height(LARGE_SCREEN_SUGGESTION_ROW_HEIGHT_VP)
    .padding({ right: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.selected ? this.storedControlBackgroundColor : Color.Transparent)
    .borderRadius(LARGE_SCREEN_SUGGESTION_ROW_RADIUS_VP)
    .clip(true)
    .onHover((hovered: boolean): void => {
      if (hovered) {
        this.onHighlight(this.suggestion);
      }
    })
  }

  private isHistorySuggestion(): boolean {
    return this.suggestion.source === 'search_history';
  }
}

@Component
export struct BrowserLargeScreenSearchEngineButton {
  @Prop presentation: BrowserSearchEngineChromePresentation = createDefaultSearchEnginePresentation();
  @Prop viewportWidthVp: number = 0;
  @Prop viewportHeightVp: number = 0;
  @Prop popupReservedTopVp: number = 0;
  onSelectSearchEngine: (engineId: SearchEngineId) => void = (_engineId: SearchEngineId): void => {};

  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';

  @State private popupVisible: boolean = false;
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();

  build() {
    Button({ type: ButtonType.Circle }) {
      if (SearchEngineIconResources.builtInIcon(this.presentation.selectedSearchEngine) !== undefined) {
        Image(SearchEngineIconResources.builtInIcon(this.presentation.selectedSearchEngine) as Resource)
          .width(LARGE_SCREEN_SEARCH_ENGINE_ICON_SIZE_VP)
          .height(LARGE_SCREEN_SEARCH_ENGINE_ICON_SIZE_VP)
          .objectFit(ImageFit.Contain)
          .hitTestBehavior(HitTestMode.None)
      } else {
        AiraIcon({
          airaIconId: 'browser.toolbar.search',
          iconSize: LARGE_SCREEN_SEARCH_ENGINE_ICON_SIZE_VP,
          iconColor: this.storedPrimaryTextColor
        })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(LARGE_SCREEN_SEARCH_ENGINE_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_SEARCH_ENGINE_BUTTON_SIZE_VP)
    .backgroundColor(Color.Transparent)
    .stateEffect(true)
    .accessibilityText('切换搜索引擎')
    .onClick((): void => {
      this.popupVisible = !this.popupVisible;
    })
    .bindPopup(this.popupVisible, {
      builder: this.buildSearchEnginePopup,
      placement: Placement.BottomLeft,
      popupColor: this.storedSurfaceBackgroundColor,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: 6,
      width: this.resolvePopupWidth(),
      radius: BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP,
      shadow: {
        radius: 20,
        color: $r('app.color.elevation_shadow'),
        offsetX: 0,
        offsetY: 8
      },
      onStateChange: (event: PopupStateChangeParam): void => {
        this.popupVisible = event.isVisible;
      }
    })
  }

  @Builder
  private buildSearchEnginePopup() {
    Scroll() {
      Column({ space: 0 }) {
        ForEach(this.presentation.searchEngines, (engine: SearchEngineRecord) => {
          this.buildSearchEngineRow(engine)
        }, (engine: SearchEngineRecord): string => engine.id)
      }
      .width('100%')
    }
    .width('100%')
    .height(this.resolvePopupHeight())
    .padding(LARGE_SCREEN_SEARCH_ENGINE_POPUP_PADDING_VP)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
  }

  @Builder
  private buildSearchEngineRow(engine: SearchEngineRecord) {
    Button() {
      Row({ space: 12 }) {
        if (SearchEngineIconResources.builtInIcon(engine.id) !== undefined) {
          Image(SearchEngineIconResources.builtInIcon(engine.id) as Resource)
            .width(LARGE_SCREEN_SEARCH_ENGINE_ICON_SIZE_VP)
            .height(LARGE_SCREEN_SEARCH_ENGINE_ICON_SIZE_VP)
            .objectFit(ImageFit.Contain)
            .hitTestBehavior(HitTestMode.None)
        } else {
          AiraIcon({
            airaIconId: 'browser.toolbar.search',
            iconSize: LARGE_SCREEN_SEARCH_ENGINE_ICON_SIZE_VP,
            iconColor: this.storedPrimaryTextColor
          })
            .hitTestBehavior(HitTestMode.None)
        }

        Text(engine.name)
          .layoutWeight(1)
          .fontSize(14)
          .fontWeight(this.isSelected(engine.id) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height(LARGE_SCREEN_SEARCH_ENGINE_POPUP_ROW_HEIGHT_VP)
    .type(ButtonType.Normal)
    .backgroundColor(this.isSelected(engine.id) ? this.storedControlBackgroundColor : Color.Transparent)
    .borderRadius(LARGE_SCREEN_SEARCH_ENGINE_POPUP_ROW_RADIUS_VP)
    .stateEffect(true)
    .focusable(false)
    .focusOnTouch(false)
    .accessibilityText(`切换到${engine.name}`)
    .onClick((): void => {
      this.popupVisible = false;
      this.onSelectSearchEngine(engine.id);
    })
  }

  private resolvePopupHeight(): number {
    const visibleRows = Math.max(1, Math.min(
      LARGE_SCREEN_SEARCH_ENGINE_POPUP_MAX_VISIBLE_ROWS,
      this.presentation.searchEngines.length
    ));
    const preferredHeight = visibleRows * LARGE_SCREEN_SEARCH_ENGINE_POPUP_ROW_HEIGHT_VP +
      LARGE_SCREEN_SEARCH_ENGINE_POPUP_PADDING_VP * 2;
    return this.modalLayoutService.resolvePopupHeight(
      this.viewportHeightVp,
      preferredHeight,
      this.popupReservedTopVp
    );
  }

  private resolvePopupWidth(): number {
    return this.modalLayoutService.resolvePopupWidth(
      this.viewportWidthVp,
      LARGE_SCREEN_SEARCH_ENGINE_POPUP_WIDTH_VP
    );
  }

  private isSelected(engineId: SearchEngineId): boolean {
    return this.presentation.selectedSearchEngine === engineId;
  }
}

@Component
export struct BrowserLargeScreenOmniboxSearchSurface {
  @StorageLink(EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY)
  @Watch('refreshExternalAppSearchPreferences')
  private externalAppSearchPreferencesRevision: number = 0;
  // The dropdown reads as an opaque menu: white in light mode, dark in dark mode. The glass tint
  // cannot carry that, because a translucent blur leaves the page legible behind the suggestions.
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY)
  private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';

  @Prop editing: boolean = false;
  @Prop inputFocused: boolean = false;
  @Prop query: string = '';
  @Prop suggestions: SearchSuggestion[] = [];
  @Prop @Watch('scrollSelectedSuggestionIntoView') selectedSuggestionKey: string = '';
  @Prop viewportHeightVp: number = 0;
  @Prop popupReservedTopVp: number = 0;
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion): void => {};
  onHighlightSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion): void => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void =
    (_suggestion: SearchSuggestion): void => {};
  onClearHistorySuggestions: () => void = (): void => {};
  onExternalAppSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string): void => {};

  @State private surfaceWidthVp: number = 0;
  @State private clearHovered: boolean = false;
  @State private externalAppSearchPreferences: ExternalAppSearchPreferences =
    sharedExternalAppSearchPreferencesRepository.getSettings();
  private readonly viewModel: BrowserLargeScreenOmniboxSearchViewModel =
    new BrowserLargeScreenOmniboxSearchViewModel();
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();
  private readonly suggestionScroller: Scroller = new Scroller();

  build() {
    if (this.resolvePresentation().visible) {
      Column({ space: LARGE_SCREEN_SEARCH_SURFACE_GAP_VP }) {
        if (this.resolvePresentation().externalAppSearchTargets.length > 0) {
          this.buildExternalAppSearchCard()
        }
        this.buildSuggestionCard()
      }
      .width('100%')
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const width = Number(newArea.width);
        if (Number.isFinite(width) && width > 0 && width !== this.surfaceWidthVp) {
          this.surfaceWidthVp = width;
        }
      })
    }
  }

  @Builder
  private buildExternalAppSearchCard() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: LARGE_SCREEN_EXTERNAL_SEARCH_CARD_HEIGHT_VP,
        surfaceRadius: LARGE_SCREEN_SEARCH_CARD_RADIUS_VP,
        fallbackColor: this.storedFloatingSurfaceColor,
        materialBorderWidth: 1,
        materialBorderColor: this.storedDividerColor
      }) {
        Column() {
          ExternalAppSearchStrip({
            targets: this.resolvePresentation().externalAppSearchTargets,
            query: this.query,
            labelColor: this.storedSecondaryTextColor,
            stripHeight: 66,
            itemWidth: 48,
            actionSize: 42,
            columnGap: this.resolveExternalAppSearchColumnGap(),
            pageSize: this.resolvePresentation().externalAppSearchPageSize,
            onSearch: (targetId: ExternalAppSearchTargetId, query: string): void => {
              this.onExternalAppSearch(targetId, query);
            }
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      }
    }
    .width('100%')
    .height(LARGE_SCREEN_EXTERNAL_SEARCH_CARD_HEIGHT_VP)
    .borderRadius(LARGE_SCREEN_SEARCH_CARD_RADIUS_VP)
    .shadow({
      radius: 16,
      color: $r('app.color.elevation_shadow'),
      offsetX: 0,
      offsetY: 6
    })
  }

  @Builder
  private buildSuggestionCard() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: this.resolveSuggestionCardHeight(),
        surfaceRadius: LARGE_SCREEN_SEARCH_CARD_RADIUS_VP,
        fallbackColor: this.storedFloatingSurfaceColor,
        materialBorderWidth: 1,
        materialBorderColor: this.storedDividerColor
      }) {
        Column() {
          if (this.resolvePresentation().searchSuggestions.length > 0) {
            if (this.resolvePresentation().hasHistorySuggestions) {
              this.buildHistoryHeaderRow()
            }
            this.buildSuggestionList()
          } else {
            Row({ space: 10 }) {
              Text(this.resolveEmptySuggestionLabel())
                .layoutWeight(1)
                .fontSize(14)
                .fontColor(this.storedSecondaryTextColor)

              // Only the query state keeps a trailing glyph. The empty list with
              // no query is the "history is empty" state, where a clock icon
              // would claim history the user may have just cleared.
              if (this.query.trim().length > 0) {
                AiraIcon({
                  airaIconId: 'browser.toolbar.search',
                  iconSize: 18,
                  iconColor: this.storedSecondaryTextColor
                })
              }
            }
            .width('100%')
            .height(LARGE_SCREEN_SUGGESTION_EMPTY_HEIGHT_VP - LARGE_SCREEN_SEARCH_CARD_PADDING_VP * 2)
            .padding({ left: 14, right: 14 })
          }
        }
        .width('100%')
        .height('100%')
        .padding(LARGE_SCREEN_SEARCH_CARD_PADDING_VP)
      }
    }
    .width('100%')
    .height(this.resolveSuggestionCardHeight())
    .borderRadius(LARGE_SCREEN_SEARCH_CARD_RADIUS_VP)
    .shadow({
      radius: 16,
      color: $r('app.color.elevation_shadow'),
      offsetX: 0,
      offsetY: 6
    })
  }

  @Builder
  private buildHistoryHeaderRow() {
    Row() {
      Text('搜索历史')
        .fontSize(LARGE_SCREEN_SUGGESTION_HEADER_TITLE_SIZE)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)

      Blank()

      Button() {
        Text('清空')
          .fontSize(LARGE_SCREEN_SUGGESTION_HEADER_ACTION_SIZE)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
      }
      .height(LARGE_SCREEN_SUGGESTION_HEADER_ACTION_HEIGHT_VP)
      .padding({ left: 8, right: 8 })
      .type(ButtonType.Normal)
      .borderRadius(LARGE_SCREEN_SUGGESTION_HEADER_ACTION_HEIGHT_VP / 2)
      .backgroundColor(this.clearHovered ? this.storedControlBackgroundColor : Color.Transparent)
      .stateEffect(false)
      .hoverEffect(HoverEffect.None)
      .focusable(false)
      .focusOnTouch(false)
      .accessibilityText('清空搜索历史')
      .onHover((hovered: boolean): void => {
        this.clearHovered = hovered;
      })
      .onClick((): void => {
        this.onClearHistorySuggestions();
      })
    }
    .width('100%')
    .height(LARGE_SCREEN_SUGGESTION_HEADER_HEIGHT_VP)
    .padding({ left: LARGE_SCREEN_SUGGESTION_ROW_HORIZONTAL_PADDING_VP, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSuggestionList() {
    Scroll(this.suggestionScroller) {
      Column({ space: LARGE_SCREEN_SUGGESTION_ROW_GAP_VP }) {
        ForEach(this.resolvePresentation().searchSuggestions, (suggestion: SearchSuggestion) => {
          BrowserLargeScreenSuggestionRow({
            suggestion: suggestion,
            selected: omniboxSuggestionSelectionKey(suggestion) === this.selectedSuggestionKey,
            onOpen: (nextSuggestion: SearchSuggestion): void => {
              this.onOpenSuggestion(nextSuggestion);
            },
            onDelete: (nextSuggestion: SearchSuggestion): void => {
              this.onDeleteHistorySuggestion(nextSuggestion);
            },
            onHighlight: (nextSuggestion: SearchSuggestion): void => {
              this.onHighlightSuggestion(nextSuggestion);
            }
          })
        }, (suggestion: SearchSuggestion): string => omniboxSuggestionSelectionKey(suggestion))
      }
      .width('100%')
    }
    .width('100%')
    .height(this.resolveSuggestionListHeight())
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.None)
  }

  private scrollSelectedSuggestionIntoView(): void {
    const suggestions = this.resolvePresentation().searchSuggestions;
    const index = suggestions.findIndex((suggestion: SearchSuggestion): boolean => {
      return omniboxSuggestionSelectionKey(suggestion) === this.selectedSuggestionKey;
    });
    if (index < 0) {
      return;
    }
    const stride = LARGE_SCREEN_SUGGESTION_ROW_HEIGHT_VP + LARGE_SCREEN_SUGGESTION_ROW_GAP_VP;
    const rowTop = index * stride;
    const rowBottom = rowTop + LARGE_SCREEN_SUGGESTION_ROW_HEIGHT_VP;
    const viewport = this.resolveSuggestionListHeight();
    let currentOffset = 0;
    try {
      currentOffset = this.suggestionScroller.currentOffset().yOffset;
    } catch (_error) {
      return;
    }
    if (rowTop < currentOffset) {
      this.suggestionScroller.scrollTo({ xOffset: 0, yOffset: rowTop, animation: false });
      return;
    }
    if (rowBottom > currentOffset + viewport) {
      this.suggestionScroller.scrollTo({
        xOffset: 0,
        yOffset: Math.max(0, rowBottom - viewport),
        animation: false
      });
    }
  }

  private resolvePresentation(): BrowserLargeScreenOmniboxSearchPresentation {
    return this.viewModel.resolve({
      editing: this.editing,
      inputFocused: this.inputFocused,
      surfaceWidthVp: this.surfaceWidthVp,
      suggestions: this.suggestions,
      externalAppSearchPreferences: this.externalAppSearchPreferences
    });
  }

  private resolveExternalAppSearchColumnGap(): number {
    const pageSize = this.resolvePresentation().externalAppSearchPageSize;
    if (pageSize <= 1) {
      return 0;
    }
    const availableWidth = Math.max(0, this.surfaceWidthVp - 24);
    const spareWidth = availableWidth - pageSize * 48;
    return Math.max(8, Math.min(26, Math.floor(spareWidth / (pageSize - 1))));
  }

  private resolveSuggestionCardHeight(): number {
    return this.resolveSuggestionListHeight() + this.resolveSuggestionHeaderHeight() +
      LARGE_SCREEN_SEARCH_CARD_PADDING_VP * 2;
  }

  private resolveSuggestionHeaderHeight(): number {
    const count = this.resolvePresentation().searchSuggestions.length;
    return count > 0 && this.resolvePresentation().hasHistorySuggestions ?
      LARGE_SCREEN_SUGGESTION_HEADER_HEIGHT_VP : 0;
  }

  /**
   * Height of the scrolling list only. The header is a sibling above it, so the
   * list gets the card's budget minus the header band rather than the total.
   */
  private resolveSuggestionListHeight(): number {
    const availableHeight = Math.max(1, this.resolveSuggestionCardAvailableHeight() -
      LARGE_SCREEN_SEARCH_CARD_PADDING_VP * 2 - this.resolveSuggestionHeaderHeight());
    const count = this.resolvePresentation().searchSuggestions.length;
    if (count <= 0) {
      return Math.min(
        availableHeight,
        LARGE_SCREEN_SUGGESTION_EMPTY_HEIGHT_VP - LARGE_SCREEN_SEARCH_CARD_PADDING_VP * 2
      );
    }
    const listBudget = Math.max(
      LARGE_SCREEN_SUGGESTION_ROW_HEIGHT_VP,
      Math.min(availableHeight, LARGE_SCREEN_SUGGESTION_MAX_HEIGHT_VP)
    );
    const contentHeight = count * LARGE_SCREEN_SUGGESTION_ROW_HEIGHT_VP +
      Math.max(0, count - 1) * LARGE_SCREEN_SUGGESTION_ROW_GAP_VP;
    return Math.min(listBudget, contentHeight);
  }

  private resolveSuggestionCardAvailableHeight(): number {
    const externalSearchHeight = this.resolvePresentation().externalAppSearchTargets.length > 0 ?
      LARGE_SCREEN_EXTERNAL_SEARCH_CARD_HEIGHT_VP + LARGE_SCREEN_SEARCH_SURFACE_GAP_VP : 0;
    return this.modalLayoutService.resolvePopupHeight(
      this.viewportHeightVp,
      LARGE_SCREEN_SUGGESTION_MAX_HEIGHT_VP + LARGE_SCREEN_SEARCH_CARD_PADDING_VP * 2,
      this.popupReservedTopVp + externalSearchHeight
    );
  }

  private resolveEmptySuggestionLabel(): string {
    return this.query.trim().length > 0 ? '暂无搜索建议' : '暂无搜索历史';
  }

  private refreshExternalAppSearchPreferences(): void {
    void this.externalAppSearchPreferencesRevision;
    this.externalAppSearchPreferences = sharedExternalAppSearchPreferencesRepository.getSettings();
  }
}
