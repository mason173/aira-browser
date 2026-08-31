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
  BrowserLargeScreenOmniboxSearchViewModel
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
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { sharedExternalAppSearchPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';
import { SearchEngineIconResources } from '../search/SearchEngineIconResources';
import { AiraIcon } from '../common/AiraIcon';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import { ExternalAppSearchStrip } from './ExternalAppSearchStrip';
import { AppWindowModalLayoutService } from '../../../services/layout/AppWindowModalLayoutService';

const LARGE_SCREEN_SEARCH_SURFACE_GAP_VP: number = 8;
const LARGE_SCREEN_SEARCH_CARD_PADDING_VP: number = 10;
const LARGE_SCREEN_SEARCH_CARD_RADIUS_VP: number = 20;
const LARGE_SCREEN_EXTERNAL_SEARCH_CARD_HEIGHT_VP: number = 86;
const LARGE_SCREEN_SUGGESTION_MAX_HEIGHT_VP: number = 296;
const LARGE_SCREEN_SUGGESTION_EMPTY_HEIGHT_VP: number = 64;
const LARGE_SCREEN_SUGGESTION_ROW_HEIGHT_VP: number = 54;
const LARGE_SCREEN_SUGGESTION_ROW_GAP_VP: number = 4;
const LARGE_SCREEN_SUGGESTION_ROW_RADIUS_VP: number =
  LARGE_SCREEN_SEARCH_CARD_RADIUS_VP - LARGE_SCREEN_SEARCH_CARD_PADDING_VP;
const LARGE_SCREEN_SUGGESTION_ROW_HORIZONTAL_PADDING_VP: number = 12;
const LARGE_SCREEN_SUGGESTION_TRAILING_ICON_SIZE_VP: number = 18;
const LARGE_SCREEN_SUGGESTION_DELETE_BUTTON_SIZE_VP: number = 32;
const LARGE_SCREEN_SUGGESTION_DELETE_ICON_SIZE_VP: number = 17;
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
  @State private hovered: boolean = false;
  @State private deleteHovered: boolean = false;
  onOpen: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion): void => {};
  onDelete: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion): void => {};

  build() {
    Row({ space: 8 }) {
      Button() {
        Row({ space: 12 }) {
          Text(this.suggestion.title)
            .layoutWeight(1)
            .constraintSize({ minWidth: 0 })
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)

          AiraIcon({
            airaIconId: this.isHistorySuggestion() ? 'membership.inviteRecordClock' : 'browser.toolbar.search',
            iconSize: LARGE_SCREEN_SUGGESTION_TRAILING_ICON_SIZE_VP,
            iconColor: this.storedSecondaryTextColor
          })
            .hitTestBehavior(HitTestMode.None)
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
    .backgroundColor(this.hovered && !this.deleteHovered ? this.storedControlBackgroundColor : Color.Transparent)
    .borderRadius(LARGE_SCREEN_SUGGESTION_ROW_RADIUS_VP)
    .clip(true)
    .onHover((hovered: boolean): void => {
      this.hovered = hovered;
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
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY)
  private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';

  @Prop editing: boolean = false;
  @Prop inputFocused: boolean = false;
  @Prop query: string = '';
  @Prop suggestions: SearchSuggestion[] = [];
  @Prop viewportHeightVp: number = 0;
  @Prop popupReservedTopVp: number = 0;
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion): void => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void =
    (_suggestion: SearchSuggestion): void => {};
  onExternalAppSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string): void => {};

  @State private surfaceWidthVp: number = 0;
  @State private externalAppSearchPreferences: ExternalAppSearchPreferences =
    sharedExternalAppSearchPreferencesRepository.getSettings();
  private readonly viewModel: BrowserLargeScreenOmniboxSearchViewModel =
    new BrowserLargeScreenOmniboxSearchViewModel();
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();

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
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
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
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        materialBorderWidth: 1,
        materialBorderColor: this.storedDividerColor
      }) {
        Column() {
          if (this.resolvePresentation().searchSuggestions.length > 0) {
            this.buildSuggestionList()
          } else {
            Row({ space: 10 }) {
              Text(this.resolveEmptySuggestionLabel())
                .layoutWeight(1)
                .fontSize(14)
                .fontColor(this.storedSecondaryTextColor)

              AiraIcon({
                airaIconId: this.query.trim().length > 0 ? 'browser.toolbar.search' : 'browser.shortcut.history',
                iconSize: 18,
                iconColor: this.storedSecondaryTextColor
              })
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
  private buildSuggestionList() {
    Scroll() {
      Column({ space: LARGE_SCREEN_SUGGESTION_ROW_GAP_VP }) {
        ForEach(this.resolvePresentation().searchSuggestions, (suggestion: SearchSuggestion) => {
          BrowserLargeScreenSuggestionRow({
            suggestion: suggestion,
            onOpen: (nextSuggestion: SearchSuggestion): void => {
              this.onOpenSuggestion(nextSuggestion);
            },
            onDelete: (nextSuggestion: SearchSuggestion): void => {
              this.onDeleteHistorySuggestion(nextSuggestion);
            }
          })
        }, (suggestion: SearchSuggestion): string => {
          return `${suggestion.id}:${suggestion.refId ?? ''}:${suggestion.target}`;
        })
      }
      .width('100%')
    }
    .width('100%')
    .height(this.resolveSuggestionContentHeight())
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.None)
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
    return this.resolveSuggestionContentHeight() + LARGE_SCREEN_SEARCH_CARD_PADDING_VP * 2;
  }

  private resolveSuggestionContentHeight(): number {
    const availableHeight = Math.max(1, this.resolveSuggestionCardAvailableHeight() -
      LARGE_SCREEN_SEARCH_CARD_PADDING_VP * 2);
    const count = this.resolvePresentation().searchSuggestions.length;
    if (count <= 0) {
      return Math.min(
        availableHeight,
        LARGE_SCREEN_SUGGESTION_EMPTY_HEIGHT_VP - LARGE_SCREEN_SEARCH_CARD_PADDING_VP * 2
      );
    }
    const contentHeight = count * LARGE_SCREEN_SUGGESTION_ROW_HEIGHT_VP +
      Math.max(0, count - 1) * LARGE_SCREEN_SUGGESTION_ROW_GAP_VP;
    return Math.min(availableHeight, LARGE_SCREEN_SUGGESTION_MAX_HEIGHT_VP, contentHeight);
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
