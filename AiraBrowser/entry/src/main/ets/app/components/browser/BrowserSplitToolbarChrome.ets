import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import {
  ExternalAppSearchPreferences,
  ExternalAppSearchTargetId,
  SearchEngineId,
  SearchEngineRecord,
  SearchSuggestion
} from '../../../common/models/BrowserModels';
import { BrowserSearchEnginePresentationViewModel } from '../../../core/browser/BrowserSearchEnginePresentationViewModel';
import {
  DOCK_TOOLBAR_BOTTOM_BLOCK_VP,
  DOCK_TOOLBAR_NAV_ROW_VP,
  DOCK_TOOLBAR_PILL_ROW_GAP_VP,
  DOCK_TOOLBAR_PILL_ROW_TOP_GAP_VP,
  DOCK_TOOLBAR_PILL_ROW_VP,
  SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
  SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP,
  SPLIT_TOOLBAR_BOTTOM_BAR_VP,
  SPLIT_TOOLBAR_PILL_ROW_VP,
  SPLIT_TOOLBAR_SCROLL_COLLAPSE_DURATION_MS,
  SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP
} from '../../../core/browser/BrowserToolbarChromeStylePolicy';
import { BrowserAddressBarTabSwipeEvent } from '../../../core/browser/BrowserAddressBarTabSwipePolicy';
import {
  CENTERED_HOME_SEARCH_CHROME_FADE_MS,
  CENTERED_HOME_SEARCH_GEOMETRY_FOCUS_DELAY_MS,
  CENTERED_HOME_SEARCH_GEOMETRY_ID
} from '../../../features/newtab/CenteredHomeShortcutLayoutPolicy';
import { BrowserSplitToolbarButtonPresentation } from '../../../core/browser/BrowserSplitToolbarCustomizationViewModel';
import { BrowserSplitToolbarSearchOpen } from '../../../core/search/BrowserSearchInvocationHostPolicy';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserSearchSuggestionsPanel } from './BrowserSearchSuggestionsPanel';
import { BrowserBottomPanelWidthBreakpoint } from '../../../core/browser/BrowserBottomPanelResponsiveViewModel';
import {
  BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT,
  resolveExternalAppSearchPageSize
} from '../../../core/browser/BrowserSearchListSurfaceLayoutViewModel';
import { ExternalAppSearchStrip } from './ExternalAppSearchStrip';
import {
  ExternalAppSearchService,
  ExternalAppSearchTarget
} from '../../../services/search/ExternalAppSearchService';
import { sharedExternalAppSearchPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';

const SPLIT_TOOLBAR_PILL_HEIGHT: number = SPLIT_TOOLBAR_PILL_ROW_VP;
/** Under-pill gap of the top row. The web reserve is built from the policy, so it lives there. */
const SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP: number = SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP;
const SPLIT_TOOLBAR_SEARCH_PILL_BORDER: number = 2;
const SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN: number = SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP;
/** Dock search pill row and gaps, matching the dock block height the policy reserves. */
const DOCK_TOOLBAR_PILL_ROW_HEIGHT: number = DOCK_TOOLBAR_PILL_ROW_VP;
const DOCK_TOOLBAR_NAV_ROW_HEIGHT: number = DOCK_TOOLBAR_NAV_ROW_VP;
const DOCK_TOOLBAR_PILL_ROW_TOP_GAP: number = DOCK_TOOLBAR_PILL_ROW_TOP_GAP_VP;
const DOCK_TOOLBAR_PILL_ROW_GAP: number = DOCK_TOOLBAR_PILL_ROW_GAP_VP;
const DOCK_TOOLBAR_BOTTOM_BLOCK: number = DOCK_TOOLBAR_BOTTOM_BLOCK_VP;
const SPLIT_TOOLBAR_TAB_COUNT_LIMIT: number = 99;
const SPLIT_TOOLBAR_NAV_BUTTON_WIDTH: number = 48;
const SPLIT_TOOLBAR_NAV_BUTTON_HEIGHT: number = 44;
const SPLIT_TOOLBAR_NAV_PRESS_RADIUS: number = 12;
const SPLIT_TOOLBAR_ICON_SIZE: number = 25;
const SPLIT_TOOLBAR_TAB_BADGE_SIZE: number = 21;
const SPLIT_TOOLBAR_TAB_BADGE_RADIUS: number = 5.25;
const SPLIT_TOOLBAR_TAB_BADGE_STROKE: number = 2;
const SPLIT_TOOLBAR_SEARCH_INPUT_ID: string = 'split-toolbar-search-input';
const SPLIT_TOOLBAR_SELECT_ALL_DELAY_MS: number = 50;
/** Dock search page: side inset, editor pill height, and the gap it keeps above the keyboard. */
const DOCK_SEARCH_EDGE_PADDING: number = 16;
const DOCK_SEARCH_EDITOR_HEIGHT: number = 46;
const DOCK_SEARCH_EDITOR_TOP_GAP: number = 10;
const DOCK_SEARCH_EDITOR_BOTTOM_GAP: number = 10;

/** `search_only` reuses this search page without mounting the split navigation bar. */
export type BrowserSplitToolbarSessionMode = 'chrome' | 'search_only';

@Component
export struct BrowserSplitToolbarChrome {
  private searchEnginePresentation: BrowserSearchEnginePresentationViewModel =
    new BrowserSearchEnginePresentationViewModel();
  private searchInputController: TextInputController = new TextInputController();
  private addressSelectAllTimeout: number = -1;
  private searchFocusTimeout: number = -1;
  private seededSelectAll: boolean = false;
  private appliedSearchDismissVersion: number = 0;
  private appliedSearchOpenRequestVersion: number = 0;
  private externalAppSearchService: ExternalAppSearchService = new ExternalAppSearchService();
  @State private searching: boolean = false;
  @State private query: string = '';
  @State private engineMenuOpen: boolean = false;
  @Prop homeScene: boolean = true;
  @Prop displayAddress: string = '';
  @Prop secure: boolean = true;
  @Prop tabCount: number = 1;
  @Prop pageLoading: boolean = false;
  @Prop suggestions: SearchSuggestion[] = [];
  /** Dock search page history list. The floating bar's suggestions arrive through `suggestions`. */
  @Prop dockSearchHistory: SearchSuggestion[] = [];
  @Prop searchEngines: SearchEngineRecord[] = [];
  @Prop selectedEngineId: SearchEngineId = 'bing';
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomSafeInsetVp: number = 0;
  @Prop viewportWidth: number = 0;
  @Prop widthBreakpoint: BrowserBottomPanelWidthBreakpoint = 'sm';
  @Prop keyboardInsetVp: number = 0;
  @Prop @Watch('handleSearchDismissRequest') searchDismissVersion: number = 0;
  /** Version, draft and selection of one open. The field is created from this, not from a hidden copy. */
  @Prop @Watch('handleSearchOpenRequest') searchOpen: BrowserSplitToolbarSearchOpen =
    new BrowserSplitToolbarSearchOpen(0, '', false);
  @Prop sessionMode: BrowserSplitToolbarSessionMode = 'chrome';
  /**
   * The two-row frame has one geometry and two paints. `split` keeps the bordered address pill and
   * its customizable bar; `dock` rests as a search box and leaves the fixed dock to the bottom row.
   */
  @Prop chromeStyle: 'split' | 'dock' = 'split';
  /**
   * The centered homepage already has a search field, so that home hides this row. Minimal keeps
   * the row: the line opens search, and the scan button stays on the right. Web pages keep it too.
   */
  @Prop suppressHomeAddressBar: boolean = false;
  /**
   * Centered and minimal home share the field flight. Minimal still shows the resting top row;
   * that row is not the flight target, or the two search nodes share one geometry id.
   */
  @Prop homeSearchGeometry: boolean = false;
  /**
   * Shell-owned shared-element flag. The centered-home field and this search field swap inside
   * one animateTo, so this prop — not the local searching flag — decides which copy is on screen.
   */
  @Prop centeredSearchPresented: boolean = false;
  /** 1 while the centered-home return has faded the search-page chrome away. */
  @Prop centeredSearchChromeFade: number = 0;
  /** Existing scroll presentation asked both bars to leave. Search keeps the address row. */
  @Prop barsCollapsed: boolean = false;
  /** Top immersion asked only the address row to leave. The bottom bar stays. */
  @Prop addressBarCollapsed: boolean = false;
  /** Same tab swipe as the floating address bar. The shell owns the switch. */
  @Prop tabSwipeEnabled: boolean = false;
  @Prop tabSwipeActive: boolean = false;
  @Prop tabSwipeOffsetRatio: number = 0;
  @Prop tabSwipeTargetAddress: string = '';
  @Prop tabSwipeDirection: number = 0;
  onTabSwipe: (event: BrowserAddressBarTabSwipeEvent) => void =
    (_event: BrowserAddressBarTabSwipeEvent) => {};
  @State private addressSwipeTextWidth: number = 0;
  private tabSwipeGestureStarted: boolean = false;
  private tabSwipeLastOffsetX: number = 0;
  private tabSwipeLastOffsetY: number = 0;
  /** Negative keeps the split bottom-bar reserve. A homepage search session passes its own. */
  @Prop bottomChromeReserveVp: number = -1;
  @Prop pageBackgroundColor: ResourceColor = '#FFFFFF';
  @Prop barBackgroundColor: ResourceColor = '#FFFFFF';
  /**
   * Dock block backplate. The dock paints the neutral page tone so its white search box reads as a
   * floating field, instead of the split row's surface color. A wallpaper home clears it.
   */
  @Prop dockBarBackgroundColor: ResourceColor = '#F2F3F5';
  @Prop pressedBackgroundColor: ResourceColor = '#14000000';
  @Prop textColor: ResourceColor = '#111111';
  @Prop secondaryTextColor: ResourceColor = '#8A8A8E';
  /**
   * Resting home icons follow the wallpaper tone. The search sheet keeps the theme colors, because
   * it paints its own opaque page background.
   */
  @Prop wallpaperIconsActive: boolean = false;
  @Prop wallpaperIconColor: ResourceColor = '#111111';
  @Prop wallpaperSecondaryIconColor: ResourceColor = '#8A8A8E';
  @Prop wallpaperPressedColor: ResourceColor = '#14000000';
  onRequestSearchOpen: () => void = () => {};
  onSearchDraftChange: (query: string) => void = (_query: string) => {};
  onRequestSearchEnd: (reason: string) => void = (_reason: string) => {};
  onSubmit: (rawInput: string) => void = (_rawInput: string) => {};
  onSelectEngine: (engineId: SearchEngineId) => void = (_engineId: SearchEngineId) => {};
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  /** Dock search page clears the stored search terms from its history header. */
  onClearSearchHistory: () => void = () => {};
  onExternalSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string) => {};
  @Prop buttons: BrowserSplitToolbarButtonPresentation[] = [];
  onReload: () => void = () => {};
  onButtonTap: (slotId: string) => void = (_slotId: string) => {};
  onButtonLongPress: (slotId: string) => void = (_slotId: string) => {};
  onOpenSiteInfo: () => void = () => {};
  onScan: () => void = () => {};

  aboutToAppear(): void {
    if (this.sessionMode === 'search_only') {
      this.handleSearchOpenRequest();
    }
  }

  aboutToDisappear(): void {
    this.clearSearchFocusTimeout();
    this.clearAddressSelectAllTimeout();
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.shouldShowSearchSheet()) {
        if (this.chromeStyle === 'dock' && !this.usesHomeSearchGeometry()) {
          this.buildDockSearchPage()
        } else {
          this.buildSearchSheet()
        }
      }
      Column() {
        if (this.shouldShowTopBar()) {
          this.buildTopBar()
        }
        Blank()
        if (this.shouldShowBottomBar()) {
          if (this.chromeStyle === 'dock') {
            this.buildDockBottomBlock()
          } else {
            this.buildBottomBar()
          }
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.shouldMountCenteredSearchGeometryHost()) {
        this.buildCenteredSearchGeometryHost()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /**
   * Stays mounted on the centered homepage so the search field itself is the node that appears
   * and disappears. The shared-element transition only runs for that node.
   */
  @Builder
  private buildCenteredSearchGeometryHost() {
    Column() {
      if (this.shouldShowCenteredSearchGeometryPill()) {
        this.buildSearchPill(true)
      }
      if (this.engineMenuOpen && !this.shouldShowTopBar()) {
        this.buildEngineMenu()
      }
    }
    .width('100%')
    .padding({
      top: this.resolveTopInset(),
      left: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
      right: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN
    })
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(this.shouldShowCenteredSearchGeometryPill() ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private buildTopBar() {
    Column() {
      Stack() {
        // The address pill is the resting page. The search field is born when search opens,
        // so it cannot keep a previous address painted over the next site.
        if (this.searching || this.sessionMode === 'search_only') {
          this.buildSearchPill(false)
        }
        if (!this.searching && this.sessionMode !== 'search_only') {
          if (this.homeScene) {
            this.buildHomePill()
          } else {
            this.buildAddressPill()
          }
        }
      }
      .width('100%')
      .height(SPLIT_TOOLBAR_PILL_HEIGHT)

      if (this.engineMenuOpen) {
        this.buildEngineMenu()
      }
    }
    .width('100%')
    .padding({
      top: this.resolveTopInset(),
      left: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
      right: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
      bottom: SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP
    })
    .backgroundColor(this.resolveBarBackground())
    .hitTestBehavior(this.shouldCollapseAddressBar() ? HitTestMode.None : HitTestMode.BLOCK_HIERARCHY)
    .translate({ y: this.shouldCollapseAddressBar() ? -this.resolveCollapsedTopTravel() : 0 })
    .opacity(this.shouldCollapseAddressBar() ? 0 : 1)
    .animation({
      duration: SPLIT_TOOLBAR_SCROLL_COLLAPSE_DURATION_MS,
      curve: Curve.EaseOut
    })
    .onTouch((_event: TouchEvent) => {
    })
  }

  @Builder
  private buildHomePill() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.onRequestSearchOpen();
        })

      Row() {
        Row({ space: 8 }) {
          AiraIcon({
            airaIconId: 'browser.toolbar.search',
            iconSize: 20,
            iconColor: this.resolveHomeChromeIconColor()
          })
          Text($r('app.string.bottom_panel_action_home'))
            .fontSize(18)
            .fontColor(this.resolveHomeChromeIconColor())
            .maxLines(1)
            .textAlign(TextAlign.Start)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.None)

        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.scanQr',
            iconSize: 20,
            iconColor: this.resolveHomeChromeIconColor()
          })
        }
        .width(32)
        .height(32)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .onClick(() => {
          this.onScan();
        })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 6 })
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height(SPLIT_TOOLBAR_PILL_HEIGHT)
    .borderRadius(23)
    .backgroundColor(this.resolveBarBackground())
    .clip(true)
  }

  /**
   * Dock-style resting row: one rounded search box with a magnifier, centered text and a scan
   * button. It carries no per-button taps, so the whole box opens search. The web scene shows the
   * page address, the home scene the search placeholder.
   */
  @Builder
  private buildDockPill() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.onRequestSearchOpen();
        })

      Row() {
        AiraIcon({
          airaIconId: 'browser.toolbar.search',
          iconSize: 20,
          iconColor: this.secondaryTextColor
        })

        Text(this.resolveDockPillText())
          .layoutWeight(1)
          .fontSize(16)
          .fontColor(this.resolveDockPillIsPlaceholder() ? this.secondaryTextColor : this.textColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .hitTestBehavior(HitTestMode.None)

        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.scanQr',
            iconSize: 20,
            iconColor: this.secondaryTextColor
          })
        }
        .width(32)
        .height(32)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .onClick(() => {
          this.onScan();
        })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 6 })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height(DOCK_TOOLBAR_PILL_ROW_HEIGHT)
    .borderRadius(DOCK_TOOLBAR_PILL_ROW_HEIGHT / 2)
    .backgroundColor(this.pageBackgroundColor)
    .shadow({ radius: 6, color: '#14000000', offsetY: 2 })
    .clip(true)
  }

  private resolveDockPillText(): ResourceStr {
    if (this.resolveDockPillIsPlaceholder()) {
      return $r('app.string.aira_search_card_placeholder');
    }
    return this.displayAddress;
  }

  private resolveDockPillIsPlaceholder(): boolean {
    return this.homeScene || this.displayAddress.trim().length === 0;
  }

  @Builder
  private buildAddressPill() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .gesture(
          GestureGroup(
            GestureMode.Exclusive,
            PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
              .onActionStart((event: GestureEvent) => { this.startTabSwipe(event); })
              .onActionUpdate((event: GestureEvent) => { this.emitTabSwipe('update', event); })
              .onActionEnd((event: GestureEvent) => { this.emitTabSwipe('end', event); })
              .onActionCancel(() => { this.cancelTabSwipe(); }),
            TapGesture().onAction(() => {
              this.onRequestSearchOpen();
            })
          )
        )
        .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent) => {
          return this.judgeTabSwipe(info, event);
        })

      Row() {
        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.connectionSecurity',
            iconSize: 18,
            iconColor: this.textColor
          })
        }
        .width(32)
        .height(32)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(Color.Transparent)
        .opacity(this.secure ? 1 : 0.55)
        .onClick(() => {
          this.onOpenSiteInfo();
        })

        Stack({ alignContent: Alignment.Center }) {
          this.buildCurrentAddressSwipeLine()
          if (this.tabSwipeActive && this.tabSwipeTargetAddress.length > 0) {
            this.buildTargetAddressSwipeLine()
          }
        }
        .layoutWeight(1)
        .height('100%')
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
        .onAreaChange((_old: Area, area: Area) => {
          const width = area.width as number;
          if (Number.isFinite(width) && width > 0 && width !== this.addressSwipeTextWidth) {
            this.addressSwipeTextWidth = width;
          }
        })

        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.refresh',
            iconSize: 18,
            iconColor: this.textColor
          })
        }
        .width(32)
        .height(32)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(Color.Transparent)
        .opacity(this.pageLoading ? 0.55 : 1)
        .onClick(() => {
          this.onReload();
        })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 6, right: 6 })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height(SPLIT_TOOLBAR_PILL_HEIGHT)
    .border({ width: 1.5, color: this.textColor })
    .borderRadius(23)
    .backgroundColor(this.resolveBarBackground())
    .clip(true)
  }

  @Builder
  private buildSearchPill(bindHomeGeometry: boolean) {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.pageBackgroundColor)
        .opacity(this.resolveSearchChromeOpacity())
        .animation({
          duration: this.resolveSearchChromeFadeDuration(),
          curve: Curve.EaseOut
        })
        .hitTestBehavior(HitTestMode.None)

      this.buildSearchInputContent()
    }
    .width('100%')
    .height(SPLIT_TOOLBAR_PILL_HEIGHT)
    .alignContent(Alignment.Center)
    .border({
      width: bindHomeGeometry && !this.suppressHomeAddressBar ? 1.5 : SPLIT_TOOLBAR_SEARCH_PILL_BORDER,
      color: bindHomeGeometry && !this.suppressHomeAddressBar ? this.secondaryTextColor : this.textColor
    })
    .borderRadius(23)
    .clip(true)
    .backgroundColor(Color.Transparent)
    .id(bindHomeGeometry ? 'centered-home-search-target' : 'split-toolbar-search-pill')
    .geometryTransition(bindHomeGeometry ? CENTERED_HOME_SEARCH_GEOMETRY_ID : '')
    .transition(bindHomeGeometry ? this.resolveSearchPillTransition() : TransitionEffect.IDENTITY)
  }

  /** Engine icon, the search field, and the cancel button. Shared by the split and dock search rows. */
  @Builder
  private buildSearchInputContent() {
    Row({ space: 8 }) {
      Button() {
        Image(this.searchEnginePresentation.resolveIcon(this.selectedEngineId))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      }
      .width(32)
      .height(32)
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .backgroundColor(Color.Transparent)
      .opacity(this.resolveSearchChromeOpacity())
      .animation({
        duration: this.resolveSearchChromeFadeDuration(),
        curve: Curve.EaseOut
      })
      .onClick(() => {
        this.engineMenuOpen = !this.engineMenuOpen;
      })

      TextInput({ text: this.query, placeholder: $r('app.string.aira_search_card_placeholder'), controller: this.searchInputController })
        .id(SPLIT_TOOLBAR_SEARCH_INPUT_ID)
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .height(36)
        .fontSize(16)
        .halfLeading(true)
        .fontColor(this.textColor)
        .placeholderColor(this.secondaryTextColor)
        .opacity(this.resolveSearchChromeOpacity())
        .animation({
          duration: this.resolveSearchChromeFadeDuration(),
          curve: Curve.EaseOut
        })
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0, top: 0, bottom: 0 })
        .border({ width: 0, color: Color.Transparent })
        .borderRadius(0)
        .showUnderline(false)
        .maxLines(1)
        .focusable(true)
        .enableKeyboardOnFocus(true)
        .onAppear(() => {
          if (this.searching || this.sessionMode === 'search_only') {
            this.scheduleSearchInputFocus();
          }
        })
        .onEditChange((editing: boolean) => {
          if (editing) {
            this.scheduleSeededSelectAll();
          }
        })
        .onChange((value: string) => {
          if (value === this.query) {
            return;
          }
          this.seededSelectAll = false;
          this.query = value;
          this.onSearchDraftChange(value);
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.submitQuery(this.query);
        })

      Button($r('app.string.settings_custom_home_cancel'))
        .fontSize(15)
        .fontColor(this.textColor)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(Color.Transparent)
        .padding({ left: 8, right: 10 })
        .flexShrink(0)
        .opacity(this.resolveSearchChromeOpacity())
        .animation({
          duration: this.resolveSearchChromeFadeDuration(),
          curve: Curve.EaseOut
        })
        .onClick(() => {
          this.closeSearch();
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 8, right: 0 })
  }

  /**
   * Dock search page. The resting page hides the dock rows and shows the editor at the bottom, with
   * the search history above it and the keyboard below. The suggestions ride above the field while
   * typing, then swap back to the history list when the field is empty.
   */
  @Builder
  private buildDockSearchPage() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.shouldShowDockSuggestions()) {
          BrowserSearchSuggestionsPanel({
            suggestions: this.resolveDockQuerySuggestions(),
            // Grow the list up from the editor: the strongest matches sit next to the field, so the
            // user sees them instead of a top-anchored list hidden behind the keyboard.
            layoutMode: 'bottomUp',
            horizontalPadding: DOCK_SEARCH_EDGE_PADDING,
            scrollEnabled: true,
            blankAreaBackEnabled: false,
            regularRowHeight: BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT,
            regularRowContentFrameHeight: BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT,
            cardBackgroundColor: this.pageBackgroundColor,
            onOpenSuggestion: (suggestion: SearchSuggestion) => {
              this.openSuggestion(suggestion);
            },
            onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => {
              this.onDeleteHistorySuggestion(suggestion);
            }
          })
            .width('100%')
            .layoutWeight(1)
        } else {
          this.buildDockSearchHistory()
        }

        // The editor is a full-width pill; the wrapper owns the side inset so the pill itself
        // never reaches the screen edge (a 100%-wide row plus a margin would overflow instead).
        Column() {
          this.buildDockSearchEditor()
        }
        .width('100%')
        .padding({ left: DOCK_SEARCH_EDGE_PADDING, right: DOCK_SEARCH_EDGE_PADDING })
      }
      .width('100%')
      .height('100%')

      if (this.engineMenuOpen) {
        Column() {
          this.buildEngineMenu()
        }
        .width('100%')
        .padding({ left: DOCK_SEARCH_EDGE_PADDING, right: DOCK_SEARCH_EDGE_PADDING })
        .margin({ bottom: DOCK_SEARCH_EDITOR_TOP_GAP + DOCK_SEARCH_EDITOR_HEIGHT + DOCK_SEARCH_EDITOR_BOTTOM_GAP })
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.resolveTopInset(),
      // The keyboard lifts the editor; the gesture inset keeps it clear when there is none.
      bottom: Math.max(Math.max(0, this.keyboardInsetVp), this.resolveBottomInset())
    })
    .backgroundColor(this.dockBarBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
  }

  /** Search history as a titled card of terms, above the dock editor. */
  @Builder
  private buildDockSearchHistory() {
    Scroll() {
      Column() {
        Row() {
        Text($r('app.string.dock_search_history_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .layoutWeight(1)
          .maxLines(1)
        if (this.dockSearchHistory.length > 0) {
          Button() {
            AiraIcon({
              airaIconId: 'browser.tabs.delete',
              iconSize: 20,
              iconColor: this.secondaryTextColor
            })
          }
          .width(36)
          .height(36)
          .type(ButtonType.Circle)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .backgroundColor(Color.Transparent)
          .stateEffect(false)
          .accessibilityText(resolveAppResourceText($r('app.string.dock_search_history_clear')))
          .onClick(() => {
            this.onClearSearchHistory();
          })
        }
      }
      .width('100%')
      .height(40)
      .alignItems(VerticalAlign.Center)

      if (this.dockSearchHistory.length > 0) {
        Column() {
          ForEach(this.dockSearchHistory, (suggestion: SearchSuggestion, index: number) => {
            this.buildDockHistoryRow(suggestion, index === 0, index === this.dockSearchHistory.length - 1)
          }, (suggestion: SearchSuggestion): string => suggestion.id)
        }
        .width('100%')
        .backgroundColor(this.pageBackgroundColor)
        .borderRadius(16)
        .clip(true)
      }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .padding({ left: DOCK_SEARCH_EDGE_PADDING, right: DOCK_SEARCH_EDGE_PADDING, top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.TopStart)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildDockHistoryRow(suggestion: SearchSuggestion, isFirst: boolean, isLast: boolean) {
    Column() {
      Row({ space: 12 }) {
        AiraIcon({
          airaIconId: 'membership.inviteRecordClock',
          iconSize: 20,
          iconColor: this.secondaryTextColor
        })
        Text(suggestion.title.length > 0 ? suggestion.title : suggestion.target)
          .layoutWeight(1)
          .fontSize(16)
          .fontColor(this.textColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        AiraIcon({
          airaIconId: 'browser.toolbar.fillAddress',
          iconSize: 18,
          iconColor: this.secondaryTextColor
        })
      }
      .width('100%')
      .height(52)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openSuggestion(suggestion);
      })

      if (!isLast) {
        Divider()
          .color(this.secondaryTextColor)
          .opacity(0.2)
          .margin({ left: 46 })
      }
    }
    .width('100%')
    .borderRadius(isFirst || isLast ? 16 : 0)
    .clip(true)
  }

  /** Bottom editor: the search field in a white pill, with the engine icon and the scan shortcut. */
  @Builder
  private buildDockSearchEditor() {
    Row({ space: 8 }) {
      Button() {
        Image(this.searchEnginePresentation.resolveIcon(this.selectedEngineId))
          .width(22)
          .height(22)
          .objectFit(ImageFit.Contain)
      }
      .width(32)
      .height(32)
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.engineMenuOpen = !this.engineMenuOpen;
      })

      TextInput({ text: this.query, placeholder: $r('app.string.aira_search_card_placeholder'), controller: this.searchInputController })
        .id(SPLIT_TOOLBAR_SEARCH_INPUT_ID)
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .height(36)
        .fontSize(16)
        .halfLeading(true)
        .fontColor(this.textColor)
        .placeholderColor(this.secondaryTextColor)
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0, top: 0, bottom: 0 })
        .border({ width: 0, color: Color.Transparent })
        .borderRadius(0)
        .showUnderline(false)
        .maxLines(1)
        .focusable(true)
        .enableKeyboardOnFocus(true)
        .onAppear(() => {
          this.scheduleSearchInputFocus();
        })
        .onEditChange((editing: boolean) => {
          if (editing) {
            this.scheduleSeededSelectAll();
          }
        })
        .onChange((value: string) => {
          if (value === this.query) {
            return;
          }
          this.seededSelectAll = false;
          this.query = value;
          this.onSearchDraftChange(value);
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.submitQuery(this.query);
        })

      Button() {
        AiraIcon({
          airaIconId: 'browser.toolbar.scanQr',
          iconSize: 20,
          iconColor: this.secondaryTextColor
        })
      }
      .width(32)
      .height(32)
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .backgroundColor(Color.Transparent)
      .stateEffect(false)
      .onClick(() => {
        this.onScan();
      })
    }
    .width('100%')
    .height(DOCK_SEARCH_EDITOR_HEIGHT)
    .padding({ left: 10, right: 6 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.pageBackgroundColor)
    .borderRadius(DOCK_SEARCH_EDITOR_HEIGHT / 2)
    .margin({
      // The wrapper owns the side inset; only the vertical gaps live here.
      // Gap above the field, so the last suggestion row never sits flush against it.
      top: DOCK_SEARCH_EDITOR_TOP_GAP,
      bottom: DOCK_SEARCH_EDITOR_BOTTOM_GAP
    })
  }

  @Builder
  private buildEngineMenu() {
    Column() {
      ForEach(this.searchEngines, (engine: SearchEngineRecord) => {
        Row({ space: 10 }) {
          Image(this.searchEnginePresentation.resolveIcon(engine.id))
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
          Text(engine.name)
            .fontSize(15)
            .fontColor(this.textColor)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (engine.id === this.selectedEngineId) {
            Text($r('app.string.browser_ui_browser_split_toolbar_chrome_001'))
              .fontSize(12)
              .fontColor(this.secondaryTextColor)
          }
        }
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.onSelectEngine(engine.id);
          this.engineMenuOpen = false;
        })
      }, (engine: SearchEngineRecord) => `${engine.id}:${engine.name}`)
    }
    .width('100%')
    .constraintSize({ maxHeight: 280 })
    .margin({ top: 8 })
    .backgroundColor(this.pageBackgroundColor)
    .borderRadius(14)
    .border({ width: 1, color: '#14000000' })
    .shadow({ radius: 16, color: '#1A000000', offsetY: 6 })
    .clip(true)
  }

  @Builder
  private buildSearchSheet() {
    Column() {
      // The split search field lives in the top bar. Cross-app icons belong under that field,
      // not in the floating toolbar's bottom dock.
      if (this.resolveExternalSearchTargets().length > 0) {
        Column() {
          ExternalAppSearchStrip({
            targets: this.resolveExternalSearchTargets(),
            query: this.query,
            labelColor: this.secondaryTextColor,
            pageSize: this.resolveExternalSearchPageSize(),
            onSearch: (targetId: ExternalAppSearchTargetId, query: string) => {
              this.searching = false;
              this.engineMenuOpen = false;
              this.query = '';
              this.seededSelectAll = false;
              this.clearAddressSelectAllTimeout();
              this.clearSearchFocusTimeout();
              this.releaseSearchInputFocus();
              this.onRequestSearchEnd('submitted');
              this.onExternalSearch(targetId, query);
            }
          })
        }
        .width('100%')
        .padding({
          left: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
          right: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
          bottom: 8
        })
      }

      BrowserSearchSuggestionsPanel({
        suggestions: this.suggestions,
        layoutMode: 'topDown',
        horizontalPadding: 8,
        scrollEnabled: true,
        blankAreaBackEnabled: false,
        regularRowHeight: BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT,
        regularRowContentFrameHeight: BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT,
        cardBackgroundColor: this.pageBackgroundColor,
        onOpenSuggestion: (suggestion: SearchSuggestion) => {
          this.openSuggestion(suggestion);
        },
        onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => {
          this.onDeleteHistorySuggestion(suggestion);
        }
      })
        .layoutWeight(1)
        .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.resolveTopInset() + SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
      bottom: this.resolveSearchSheetBottomInset() + Math.max(0, this.keyboardInsetVp)
    })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.pageBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
    .transition(this.resolveSearchSheetTransition())
  }

  @Builder
  private buildBottomBar() {
    Stack() {
      BrowserSplitToolbarButtonRow({
        buttons: this.buttons,
        homeScene: this.homeScene,
        tabCount: this.tabCount,
        textColor: this.resolveHomeChromeIconColor(),
        secondaryTextColor: this.resolveHomeChromeSecondaryIconColor(),
        pressedBackgroundColor: this.resolveHomeChromePressedColor(),
        onTap: (slotId: string): void => {
          this.onButtonTap(slotId);
        },
        onLongPress: (slotId: string): void => {
          this.onButtonLongPress(slotId);
        }
      })
        .width('100%')
        .height('100%')
        .padding({ bottom: this.resolveBottomInset() })
    }
    .width('100%')
    .height(this.resolveBottomChromeHeight())
    .backgroundColor(this.resolveBarBackground())
    .hitTestBehavior(this.shouldCollapseBars() ? HitTestMode.None : HitTestMode.BLOCK_HIERARCHY)
    .translate({ y: this.shouldCollapseBars() ? this.resolveBottomChromeHeight() : 0 })
    .opacity(this.shouldCollapseBars() ? 0 : 1)
    .animation({
      duration: SPLIT_TOOLBAR_SCROLL_COLLAPSE_DURATION_MS,
      curve: Curve.EaseOut
    })
    .onTouch((_event: TouchEvent) => {
    })
  }

  /**
   * The dock bottom block: the resting search pill directly above the fixed navigation row, both
   * on one opaque backplate. There is no top bar, so the whole block collapses as one piece when
   * the scroll presentation asks the bars to leave.
   */
  @Builder
  private buildDockBottomBlock() {
    Column() {
      Column() {
        this.buildDockPill()
      }
      .width('100%')
      .padding({
        left: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
        right: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
        top: DOCK_TOOLBAR_PILL_ROW_TOP_GAP,
        bottom: DOCK_TOOLBAR_PILL_ROW_GAP
      })

      BrowserSplitToolbarButtonRow({
        buttons: this.buttons,
        homeScene: this.homeScene,
        tabCount: this.tabCount,
        textColor: this.resolveHomeChromeIconColor(),
        secondaryTextColor: this.resolveHomeChromeSecondaryIconColor(),
        pressedBackgroundColor: this.resolveHomeChromePressedColor(),
        onTap: (slotId: string): void => {
          this.onButtonTap(slotId);
        },
        onLongPress: (slotId: string): void => {
          this.onButtonLongPress(slotId);
        }
      })
        .width('100%')
        .height(DOCK_TOOLBAR_NAV_ROW_HEIGHT)

      Blank()
        .width('100%')
        .height(this.resolveBottomInset())
    }
    .width('100%')
    .height(this.resolveBottomChromeHeight())
    .backgroundColor(this.resolveBarBackground())
    .hitTestBehavior(this.shouldCollapseBars() ? HitTestMode.None : HitTestMode.BLOCK_HIERARCHY)
    .translate({ y: this.shouldCollapseBars() ? this.resolveBottomChromeHeight() : 0 })
    .opacity(this.shouldCollapseBars() ? 0 : 1)
    .animation({
      duration: SPLIT_TOOLBAR_SCROLL_COLLAPSE_DURATION_MS,
      curve: Curve.EaseOut
    })
    .onTouch((_event: TouchEvent) => {
    })
  }

  private openSearch(prefill: string, selectAll: boolean): void {
    this.clearAddressSelectAllTimeout();
    this.query = prefill;
    this.seededSelectAll = selectAll && prefill.length > 0;
    this.searching = true;
    this.engineMenuOpen = false;
    this.onSearchDraftChange(prefill);
  }

  private focusSearchInput(): void {
    if (!this.searching && this.sessionMode !== 'search_only') {
      return;
    }
    focusControl.requestFocus(SPLIT_TOOLBAR_SEARCH_INPUT_ID);
  }

  private scheduleSearchInputFocus(): void {
    this.clearSearchFocusTimeout();
    if (this.shouldBindCenteredSearchGeometry()) {
      // The field is still flying up from the homepage. Focusing now would cover that motion.
      this.searchFocusTimeout = setTimeout(() => {
        this.searchFocusTimeout = -1;
        this.focusSearchInput();
        this.scheduleSeededSelectAll();
      }, CENTERED_HOME_SEARCH_GEOMETRY_FOCUS_DELAY_MS);
      return;
    }
    this.focusSearchInput();
    // The first request often lands before the new field can take the keyboard.
    // Select after that retry, or the focus itself collapses the selection.
    this.searchFocusTimeout = setTimeout(() => {
      this.searchFocusTimeout = -1;
      this.focusSearchInput();
      this.clearAddressSelectAllTimeout();
      this.scheduleSeededSelectAll();
    }, SPLIT_TOOLBAR_SELECT_ALL_DELAY_MS);
  }

  private clearSearchFocusTimeout(): void {
    if (this.searchFocusTimeout < 0) {
      return;
    }
    clearTimeout(this.searchFocusTimeout);
    this.searchFocusTimeout = -1;
  }

  private releaseSearchInputFocus(): void {
    focusControl.requestFocus('');
  }

  private scheduleSeededSelectAll(): void {
    if (!this.seededSelectAll || this.query.length <= 0 || this.addressSelectAllTimeout >= 0) {
      return;
    }
    const length = this.query.length;
    this.addressSelectAllTimeout = setTimeout(() => {
      this.addressSelectAllTimeout = -1;
      if (!this.seededSelectAll || this.query.length !== length) {
        return;
      }
      this.searchInputController.setTextSelection(0, length, {
        menuPolicy: MenuPolicy.HIDE
      });
    }, SPLIT_TOOLBAR_SELECT_ALL_DELAY_MS);
  }

  private clearAddressSelectAllTimeout(): void {
    if (this.addressSelectAllTimeout < 0) {
      return;
    }
    clearTimeout(this.addressSelectAllTimeout);
    this.addressSelectAllTimeout = -1;
  }

  private handleSearchDismissRequest(): void {
    if (this.searchDismissVersion === this.appliedSearchDismissVersion) {
      return;
    }
    this.appliedSearchDismissVersion = this.searchDismissVersion;
    // The shell already started the return flight. Clearing the field here must not start
    // another animation, or the system back key snaps the box instead of flying it home.
    this.clearSearchSessionLocally();
  }

  private handleSearchOpenRequest(): void {
    const request = this.searchOpen;
    if (request.version <= 0 || request.version === this.appliedSearchOpenRequestVersion) {
      return;
    }
    this.appliedSearchOpenRequestVersion = request.version;
    this.openSearch(request.draft, request.selectAll);
    this.scheduleSearchInputFocus();
  }

  private closeSearch(): void {
    const sessionOpen = this.searching || this.engineMenuOpen || this.sessionMode === 'search_only';
    if (!sessionOpen) {
      return;
    }
    // The shell starts the return flight on this stack. Clearing here would snap it.
    this.onRequestSearchEnd('explicit_exit');
  }

  private clearSearchSessionLocally(): void {
    this.seededSelectAll = false;
    this.clearAddressSelectAllTimeout();
    this.clearSearchFocusTimeout();
    this.searchInputController.deleteText();
    this.query = '';
    this.searching = false;
    this.engineMenuOpen = false;
    this.releaseSearchInputFocus();
  }

  private submitQuery(rawInput: string): void {
    const trimmed = rawInput.trim();
    if (trimmed.length <= 0) {
      return;
    }
    this.searching = false;
    this.engineMenuOpen = false;
    this.query = '';
    this.seededSelectAll = false;
    this.clearAddressSelectAllTimeout();
    this.clearSearchFocusTimeout();
    this.releaseSearchInputFocus();
    this.onRequestSearchEnd('submitted');
    this.onSubmit(trimmed);
  }

  private openSuggestion(suggestion: SearchSuggestion): void {
    this.searching = false;
    this.engineMenuOpen = false;
    this.query = '';
    this.seededSelectAll = false;
    this.clearAddressSelectAllTimeout();
    this.clearSearchFocusTimeout();
    this.releaseSearchInputFocus();
    this.onRequestSearchEnd('submitted');
    this.onOpenSuggestion(suggestion);
  }

  private resolveExternalSearchPageSize(): number {
    return resolveExternalAppSearchPageSize(
      this.viewportWidth,
      SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
      this.widthBreakpoint
    );
  }

  private resolveExternalSearchTargets(): ExternalAppSearchTarget[] {
    const preferences: ExternalAppSearchPreferences =
      sharedExternalAppSearchPreferencesRepository.getSettings();
    return this.externalAppSearchService.listVisibleTargets({
      inputEditing: true,
      inputFocused: true,
      preferences: preferences
    });
  }

  private resolveBarBackground(): ResourceColor {
    if (this.chromeStyle === 'dock') {
      return this.dockBarBackgroundColor;
    }
    return this.searching ? this.pageBackgroundColor : this.barBackgroundColor;
  }

  private resolveHomeChromeIconColor(): ResourceColor {
    return this.wallpaperIconsActive ? this.wallpaperIconColor : this.textColor;
  }

  private resolveHomeChromeSecondaryIconColor(): ResourceColor {
    return this.wallpaperIconsActive ? this.wallpaperSecondaryIconColor : this.secondaryTextColor;
  }

  private resolveHomeChromePressedColor(): ResourceColor {
    return this.wallpaperIconsActive ? this.wallpaperPressedColor : this.pressedBackgroundColor;
  }

  private shouldShowBottomBar(): boolean {
    return this.sessionMode !== 'search_only' && !this.searching && !this.centeredSearchPresented;
  }

  private usesHomeSearchGeometry(): boolean {
    return this.homeSearchGeometry && this.homeScene;
  }

  private shouldShowTopBar(): boolean {
    // The dock frame has no top bar at all. Its resting search pill lives in the bottom block, and
    // its search page keeps the field at the bottom above the keyboard, so neither state borrows
    // the top row. The centered-home geometry host is the one exception and keeps the split rule.
    if (this.chromeStyle === 'dock' && !this.usesHomeSearchGeometry()) {
      return false;
    }
    if (this.homeScene && this.suppressHomeAddressBar) {
      return false;
    }
    // The middle field flies into the geometry pill. The resting row would cover that landing spot.
    if (this.usesHomeSearchGeometry() && this.centeredSearchPresented) {
      return false;
    }
    return true;
  }

  private shouldShowSearchSheet(): boolean {
    if (this.usesHomeSearchGeometry() && (this.suppressHomeAddressBar || this.centeredSearchPresented)) {
      return this.searching || this.centeredSearchPresented;
    }
    return this.searching || this.sessionMode === 'search_only';
  }

  /** Typing in the dock search editor swaps the history list for the query suggestions. */
  private shouldShowDockSuggestions(): boolean {
    return this.query.trim().length > 0 && this.resolveDockQuerySuggestions().length > 0;
  }

  /**
   * Query suggestions for the dock page. The panel's history rows are the floating toolbar's
   * history source; the dock keeps history as its own empty-input page, so it drops those rows and
   * shows one history list.
   */
  private resolveDockQuerySuggestions(): SearchSuggestion[] {
    return this.suggestions.filter((suggestion: SearchSuggestion): boolean => {
      return suggestion.source !== 'history' && suggestion.source !== 'search_history';
    });
  }

  private shouldMountCenteredSearchGeometryHost(): boolean {
    return this.usesHomeSearchGeometry();
  }

  private shouldShowCenteredSearchGeometryPill(): boolean {
    if (!this.usesHomeSearchGeometry()) {
      return false;
    }
    if (!this.suppressHomeAddressBar && !this.centeredSearchPresented) {
      return false;
    }
    return this.centeredSearchPresented || this.searching;
  }

  private shouldBindCenteredSearchGeometry(): boolean {
    return this.usesHomeSearchGeometry();
  }

  private shouldReverseCenteredSearchGeometry(): boolean {
    return this.shouldBindCenteredSearchGeometry() && this.centeredSearchPresented;
  }

  private resolveSearchChromeOpacity(): number {
    if (!this.shouldBindCenteredSearchGeometry()) {
      return 1;
    }
    const fade = this.centeredSearchChromeFade;
    if (!Number.isFinite(fade)) {
      return 1;
    }
    return 1 - Math.max(0, Math.min(1, fade));
  }

  private resolveSearchChromeFadeDuration(): number {
    return this.shouldBindCenteredSearchGeometry() ? CENTERED_HOME_SEARCH_CHROME_FADE_MS : 0;
  }

  private resolveSearchPillTransition(): TransitionEffect {
    if (!this.shouldBindCenteredSearchGeometry()) {
      return TransitionEffect.IDENTITY;
    }
    return TransitionEffect.opacity(0.99);
  }

  private resolveSearchSheetTransition(): TransitionEffect {
    if (!this.shouldBindCenteredSearchGeometry()) {
      return TransitionEffect.IDENTITY;
    }
    return TransitionEffect.OPACITY.animation({
      duration: CENTERED_HOME_SEARCH_CHROME_FADE_MS,
      curve: Curve.EaseOut
    });
  }

  private shouldCollapseBars(): boolean {
    return this.barsCollapsed && !this.searching && this.sessionMode !== 'search_only';
  }

  private shouldCollapseAddressBar(): boolean {
    return !this.homeScene && (this.barsCollapsed || this.addressBarCollapsed) &&
      !this.searching && this.sessionMode !== 'search_only';
  }

  /**
   * The address text has to be read here. A @Builder with parameters takes them by value, and two
   * parameters never refresh, so the first painted query would stay after the page changed.
   */
  @Builder
  private buildCurrentAddressSwipeLine() {
    Text(this.displayAddress)
      .width('100%')
      .fontSize(16)
      .fontColor(this.textColor)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .translate({ x: this.resolveAddressSwipeOffset() })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildTargetAddressSwipeLine() {
    Text(this.tabSwipeTargetAddress)
      .width('100%')
      .fontSize(16)
      .fontColor(this.textColor)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .translate({ x: this.resolveTargetAddressSwipeOffset() })
      .hitTestBehavior(HitTestMode.None)
  }

  private resolveAddressSwipeOffset(): number {
    if (!this.tabSwipeActive) {
      return 0;
    }
    const width = this.addressSwipeTextWidth > 0 ? this.addressSwipeTextWidth : 1;
    const ratio = Number.isFinite(this.tabSwipeOffsetRatio) ?
      Math.max(-1, Math.min(1, this.tabSwipeOffsetRatio)) : 0;
    const offset = ratio * width;
    return this.tabSwipeTargetAddress.length > 0 ? offset : Math.max(-24, Math.min(24, offset));
  }

  private resolveTargetAddressSwipeOffset(): number {
    return this.resolveAddressSwipeOffset() - this.tabSwipeDirection * this.addressSwipeTextWidth;
  }

  private judgeTabSwipe(info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult {
    if (info.type !== GestureControl.GestureType.PAN_GESTURE) {
      return this.tabSwipeActive || this.tabSwipeGestureStarted ?
        GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
    }
    if (this.tabSwipeGestureStarted) {
      return GestureJudgeResult.CONTINUE;
    }
    const pan = event as PanGestureEvent;
    return this.tabSwipeEnabled && !this.tabSwipeActive && !this.searching &&
      Math.abs(pan.offsetX) > 1.2 * Math.abs(pan.offsetY) ?
      GestureJudgeResult.CONTINUE : GestureJudgeResult.REJECT;
  }

  private startTabSwipe(event: GestureEvent): void {
    if (!this.tabSwipeEnabled || this.tabSwipeActive || this.searching || this.tabSwipeGestureStarted) {
      return;
    }
    this.tabSwipeGestureStarted = true;
    this.emitTabSwipe('start', event);
  }

  private emitTabSwipe(phase: 'start' | 'update' | 'end', event: GestureEvent): void {
    if (!this.tabSwipeGestureStarted) {
      return;
    }
    this.tabSwipeLastOffsetX = Number.isFinite(event.offsetX) ? event.offsetX : 0;
    this.tabSwipeLastOffsetY = Number.isFinite(event.offsetY) ? event.offsetY : 0;
    if (phase === 'end') {
      this.tabSwipeGestureStarted = false;
    }
    this.onTabSwipe({
      phase,
      offsetX: this.tabSwipeLastOffsetX,
      offsetY: this.tabSwipeLastOffsetY,
      velocityX: Number.isFinite(event.velocityX) ? event.velocityX : 0
    });
  }

  private cancelTabSwipe(): void {
    if (!this.tabSwipeGestureStarted) {
      return;
    }
    this.tabSwipeGestureStarted = false;
    this.onTabSwipe({
      phase: 'cancel',
      offsetX: this.tabSwipeLastOffsetX,
      offsetY: this.tabSwipeLastOffsetY,
      velocityX: 0
    });
  }

  private resolveCollapsedTopTravel(): number {
    return this.resolveTopInset() + SPLIT_TOOLBAR_ADDRESS_BLOCK_VP;
  }

  private resolveTopInset(): number {
    return Math.max(0, this.topSafeInsetVp);
  }

  private resolveBottomInset(): number {
    return Math.max(0, this.bottomSafeInsetVp);
  }

  private resolveBottomChromeHeight(): number {
    if (this.bottomChromeReserveVp >= 0) {
      return this.bottomChromeReserveVp;
    }
    return this.resolveBottomBlockHeight() + this.resolveBottomInset();
  }

  /** The dock stacks its search row over the navigation row; the split frame is the nav row alone. */
  private resolveBottomBlockHeight(): number {
    return this.chromeStyle === 'dock' ? DOCK_TOOLBAR_BOTTOM_BLOCK : SPLIT_TOOLBAR_BOTTOM_BAR_VP;
  }

  private resolveSearchSheetBottomInset(): number {
    if (this.bottomChromeReserveVp >= 0) {
      return this.bottomChromeReserveVp;
    }
    return this.resolveBottomInset();
  }
}

const SPLIT_TOOLBAR_BUTTON_LONG_PRESS_MS: number = 450;

/** The split bottom row, shared by the live bar and the settings preview. */
@Component
export struct BrowserSplitToolbarButtonRow {
  @Prop buttons: BrowserSplitToolbarButtonPresentation[] = [];
  @Prop homeScene: boolean = true;
  @Prop tabCount: number = 1;
  @Prop textColor: ResourceColor = '#111111';
  @Prop secondaryTextColor: ResourceColor = '#8A8A8E';
  @Prop pressedBackgroundColor: ResourceColor = '#14000000';
  onTap: (slotId: string) => void = (_slotId: string) => {};
  onLongPress: (slotId: string) => void = (_slotId: string) => {};
  @State private pressedSlotId: string = '';

  build() {
    Row() {
      ForEach(this.buttons, (button: BrowserSplitToolbarButtonPresentation) => {
        this.buildButton(button)
      }, (button: BrowserSplitToolbarButtonPresentation): string => {
        return `${button.slotId}:${button.actionId}:${button.enabled}:${button.iconId}`;
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildButton(button: BrowserSplitToolbarButtonPresentation) {
    Button() {
      if (button.usesTabBadge) {
        this.buildTabBadge(button.enabled)
      } else {
        AiraIcon({
          airaIconId: button.iconId,
          iconSize: this.resolveNavIconSize(),
          iconColor: button.enabled ? this.textColor : this.secondaryTextColor
        })
      }
    }
    .width(SPLIT_TOOLBAR_NAV_BUTTON_WIDTH)
    .height(SPLIT_TOOLBAR_NAV_BUTTON_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor(this.resolveButtonPressedFill(button))
    .borderRadius(SPLIT_TOOLBAR_NAV_PRESS_RADIUS)
    .clip(true)
    .stateEffect(false)
    .enabled(button.enabled)
    .accessibilityText(resolveAppResourceText(button.title))
    .onTouch((event: TouchEvent) => {
      this.updatePressed(button.slotId, event.type, button.enabled, !this.showsPressedFill(button));
    })
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        LongPressGesture({ fingers: 1, repeat: false, duration: SPLIT_TOOLBAR_BUTTON_LONG_PRESS_MS })
          .onAction(() => {
            if (!button.enabled) {
              return;
            }
            this.onLongPress(button.slotId);
          }),
        TapGesture({ count: 1 })
          .onAction(() => {
            if (!button.enabled) {
              return;
            }
            this.onTap(button.slotId);
          })
      )
    )
  }

  @Builder
  private buildTabBadge(enabled: boolean) {
    Text(this.formatTabCount())
      .fontSize(this.resolveTabBadgeFontSize())
      .fontWeight(FontWeight.Medium)
      .fontColor(enabled ? this.textColor : this.secondaryTextColor)
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .width(this.resolveTabBadgeSize())
      .height(this.resolveTabBadgeSize())
      .borderRadius(this.resolveTabBadgeRadius())
      .border({
        width: SPLIT_TOOLBAR_TAB_BADGE_STROKE,
        color: enabled ? this.textColor : this.secondaryTextColor
      })
      .backgroundColor(Color.Transparent)
  }

  private formatTabCount(): string {
    const count = Math.max(0, Math.floor(this.tabCount));
    if (count > SPLIT_TOOLBAR_TAB_COUNT_LIMIT) {
      return `${SPLIT_TOOLBAR_TAB_COUNT_LIMIT}`;
    }
    return `${count}`;
  }

  private resolveNavIconSize(): number {
    return SPLIT_TOOLBAR_ICON_SIZE;
  }

  private resolveTabBadgeSize(): number {
    return SPLIT_TOOLBAR_TAB_BADGE_SIZE;
  }

  private resolveTabBadgeRadius(): number {
    return SPLIT_TOOLBAR_TAB_BADGE_RADIUS;
  }

  private resolveTabBadgeFontSize(): number {
    return this.formatTabCount().length > 1 ? 11 : 13;
  }

  /**
   * On a webpage the tab button opens the overview immediately. The fill flashes
   * against the page, so only the home tab button keeps the press color.
   */
  private showsPressedFill(button: BrowserSplitToolbarButtonPresentation): boolean {
    return this.homeScene || !button.usesTabBadge;
  }

  private resolveButtonPressedFill(button: BrowserSplitToolbarButtonPresentation): ResourceColor {
    if (!this.showsPressedFill(button) || this.pressedSlotId !== button.slotId) {
      return Color.Transparent;
    }
    return this.pressedBackgroundColor;
  }

  private updatePressed(slotId: string, type: TouchType, enabled: boolean, suppressFill: boolean): void {
    if (!enabled || suppressFill) {
      if (this.pressedSlotId === slotId) {
        this.pressedSlotId = '';
      }
      return;
    }
    if (type === TouchType.Down) {
      this.pressedSlotId = slotId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedSlotId = '';
    }
  }
}
