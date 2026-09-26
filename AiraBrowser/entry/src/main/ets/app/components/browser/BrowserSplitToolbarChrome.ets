import {
  ExternalAppSearchPreferences,
  ExternalAppSearchTargetId,
  SearchEngineId,
  SearchEngineRecord,
  SearchSuggestion
} from '../../../common/models/BrowserModels';
import { BrowserSearchEnginePresentationViewModel } from '../../../core/browser/BrowserSearchEnginePresentationViewModel';
import {
  SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
  SPLIT_TOOLBAR_BOTTOM_BAR_VP,
  SPLIT_TOOLBAR_SCROLL_COLLAPSE_DURATION_MS
} from '../../../core/browser/BrowserToolbarChromeStylePolicy';
import { BrowserSplitToolbarButtonPresentation } from '../../../core/browser/BrowserSplitToolbarCustomizationViewModel';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserSearchSuggestionsPanel } from './BrowserSearchSuggestionsPanel';
import { BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT } from '../../../core/browser/BrowserSearchListSurfaceLayoutViewModel';
import { ExternalAppSearchStrip } from './ExternalAppSearchStrip';
import {
  ExternalAppSearchService,
  ExternalAppSearchTarget
} from '../../../services/search/ExternalAppSearchService';
import { sharedExternalAppSearchPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';

const SPLIT_TOOLBAR_PILL_HEIGHT: number = 46;
const SPLIT_TOOLBAR_SEARCH_PILL_BORDER: number = 2;
const SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN: number = 16;
const SPLIT_TOOLBAR_TAB_COUNT_LIMIT: number = 99;
const SPLIT_TOOLBAR_SELECT_ALL_DELAY_MS: number = 40;
const SPLIT_TOOLBAR_NAV_BUTTON_WIDTH: number = 48;
const SPLIT_TOOLBAR_NAV_BUTTON_HEIGHT: number = 44;
const SPLIT_TOOLBAR_NAV_PRESS_RADIUS: number = 12;
const SPLIT_TOOLBAR_ICON_SIZE: number = 25;
const SPLIT_TOOLBAR_TAB_BADGE_SIZE: number = 21;
const SPLIT_TOOLBAR_TAB_BADGE_RADIUS: number = 5.25;
const SPLIT_TOOLBAR_TAB_BADGE_STROKE: number = 2;
const SPLIT_TOOLBAR_SEARCH_INPUT_ID: string = 'split-toolbar-search-input';

/** `search_only` reuses this search page without mounting the split navigation bar. */
export type BrowserSplitToolbarSessionMode = 'chrome' | 'search_only';

@Component
export struct BrowserSplitToolbarChrome {
  private searchEnginePresentation: BrowserSearchEnginePresentationViewModel =
    new BrowserSearchEnginePresentationViewModel();
  private searchInputController: TextInputController = new TextInputController();
  private appliedSearchDismissVersion: number = 0;
  private appliedSearchOpenRequestVersion: number = 0;
  private externalAppSearchService: ExternalAppSearchService = new ExternalAppSearchService();
  @State private searching: boolean = false;
  @State private query: string = '';
  @State private engineMenuOpen: boolean = false;
  @Prop homeScene: boolean = true;
  @Prop displayAddress: string = '';
  @Prop editableAddress: string = '';
  @Prop secure: boolean = true;
  @Prop tabCount: number = 1;
  @Prop pageLoading: boolean = false;
  @Prop suggestions: SearchSuggestion[] = [];
  @Prop searchEngines: SearchEngineRecord[] = [];
  @Prop selectedEngineId: SearchEngineId = 'bing';
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomSafeInsetVp: number = 0;
  @Prop keyboardInsetVp: number = 0;
  @Prop @Watch('handleSearchDismissRequest') searchDismissVersion: number = 0;
  @Prop @Watch('handleSearchOpenRequest') searchOpenRequestVersion: number = 0;
  @Prop sessionMode: BrowserSplitToolbarSessionMode = 'chrome';
  /**
   * Centered homepage already has a search field. Hide this address row on that home so the two
   * do not stack. Search still uses the row; web pages keep it.
   */
  @Prop suppressHomeAddressBar: boolean = false;
  /** Existing scroll presentation asked both bars to leave. Search keeps the address row. */
  @Prop barsCollapsed: boolean = false;
  /** Negative keeps the split bottom-bar reserve. A homepage search session passes its own. */
  @Prop bottomChromeReserveVp: number = -1;
  @Prop pageBackgroundColor: ResourceColor = '#FFFFFF';
  @Prop barBackgroundColor: ResourceColor = '#FFFFFF';
  @Prop pressedBackgroundColor: ResourceColor = '#14000000';
  @Prop textColor: ResourceColor = '#111111';
  @Prop secondaryTextColor: ResourceColor = '#8A8A8E';
  onSearchSessionChange: (active: boolean, query: string) => void =
    (_active: boolean, _query: string) => {};
  onSubmit: (rawInput: string) => void = (_rawInput: string) => {};
  onSelectEngine: (engineId: SearchEngineId) => void = (_engineId: SearchEngineId) => {};
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
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

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.searching || this.sessionMode === 'search_only') {
        this.buildSearchSheet()
      }
      Column() {
        if (this.shouldShowTopBar()) {
          this.buildTopBar()
        }
        Blank()
        if (this.shouldShowBottomBar()) {
          this.buildBottomBar()
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildTopBar() {
    Column() {
      if (this.searching || this.sessionMode === 'search_only') {
        this.buildSearchPill()
      } else if (this.homeScene) {
        this.buildHomePill()
      } else {
        this.buildAddressPill()
      }
      if (this.engineMenuOpen) {
        this.buildEngineMenu()
      }
    }
    .width('100%')
    .padding({
      top: this.resolveTopInset(),
      left: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
      right: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN,
      bottom: 8
    })
    .backgroundColor(this.resolveBarBackground())
    .hitTestBehavior(this.shouldCollapseBars() ? HitTestMode.None : HitTestMode.BLOCK_HIERARCHY)
    .translate({ y: this.shouldCollapseBars() ? -this.resolveCollapsedTopTravel() : 0 })
    .opacity(this.shouldCollapseBars() ? 0 : 1)
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
          this.openSearch('');
        })

      Row() {
        Row({ space: 8 }) {
          AiraIcon({
            airaIconId: 'browser.toolbar.search',
            iconSize: 18,
            iconColor: this.textColor
          })
          Text('首页')
            .fontSize(16)
            .fontColor(this.textColor)
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
            iconSize: 18,
            iconColor: this.textColor
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
    .border({ width: 1.5, color: this.textColor })
    .borderRadius(23)
    .backgroundColor(this.resolveBarBackground())
    .clip(true)
  }

  @Builder
  private buildAddressPill() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.openSearch(this.editableAddress);
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

        Text(this.displayAddress)
          .layoutWeight(1)
          .fontSize(16)
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .hitTestBehavior(HitTestMode.None)

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
  private buildSearchPill() {
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

      TextInput({ text: this.query, placeholder: '搜索或输入网址', controller: this.searchInputController })
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
          focusControl.requestFocus(SPLIT_TOOLBAR_SEARCH_INPUT_ID);
        })
        .onChange((value: string) => {
          this.query = value;
          this.onSearchSessionChange(true, value);
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          this.submitQuery(this.query);
        })

      Button('取消')
        .fontSize(15)
        .fontColor(this.textColor)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(Color.Transparent)
        .padding({ left: 8, right: 10 })
        .flexShrink(0)
        .onClick(() => {
          this.closeSearch();
        })
    }
    .width('100%')
    .height(SPLIT_TOOLBAR_PILL_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 8, right: 0 })
    .border({ width: SPLIT_TOOLBAR_SEARCH_PILL_BORDER, color: this.textColor })
    .borderRadius(23)
    .clip(true)
    .backgroundColor(this.pageBackgroundColor)
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
            Text('当前')
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

      if (this.resolveExternalSearchTargets().length > 0) {
        ExternalAppSearchStrip({
          targets: this.resolveExternalSearchTargets(),
          query: this.query,
          onSearch: (targetId: ExternalAppSearchTargetId, query: string) => {
            this.searching = false;
            this.engineMenuOpen = false;
            this.query = '';
            this.onSearchSessionChange(false, '');
            this.onExternalSearch(targetId, query);
          }
        })
      }
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
  }

  @Builder
  private buildBottomBar() {
    Stack() {
      BrowserSplitToolbarButtonRow({
        buttons: this.buttons,
        homeScene: this.homeScene,
        tabCount: this.tabCount,
        textColor: this.textColor,
        secondaryTextColor: this.secondaryTextColor,
        pressedBackgroundColor: this.pressedBackgroundColor,
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

  private openSearch(prefill: string): void {
    this.query = prefill;
    this.searching = true;
    this.engineMenuOpen = false;
    this.onSearchSessionChange(true, prefill);
    setTimeout(() => {
      if (!this.searching) {
        return;
      }
      focusControl.requestFocus(SPLIT_TOOLBAR_SEARCH_INPUT_ID);
      if (prefill.length > 0) {
        this.searchInputController.setTextSelection(0, prefill.length, {
          menuPolicy: MenuPolicy.HIDE
        });
      }
    }, SPLIT_TOOLBAR_SELECT_ALL_DELAY_MS);
  }

  private handleSearchDismissRequest(): void {
    if (this.searchDismissVersion === this.appliedSearchDismissVersion) {
      return;
    }
    this.appliedSearchDismissVersion = this.searchDismissVersion;
    this.closeSearch();
  }

  private handleSearchOpenRequest(): void {
    if (this.searchOpenRequestVersion <= 0 ||
      this.searchOpenRequestVersion === this.appliedSearchOpenRequestVersion) {
      return;
    }
    this.appliedSearchOpenRequestVersion = this.searchOpenRequestVersion;
    this.openSearch('');
  }

  private closeSearch(): void {
    const sessionOpen = this.searching || this.engineMenuOpen || this.sessionMode === 'search_only';
    if (!sessionOpen) {
      return;
    }
    this.searching = false;
    this.engineMenuOpen = false;
    this.query = '';
    this.onSearchSessionChange(false, '');
  }

  private submitQuery(rawInput: string): void {
    const trimmed = rawInput.trim();
    if (trimmed.length <= 0) {
      return;
    }
    this.searching = false;
    this.engineMenuOpen = false;
    this.query = '';
    this.onSearchSessionChange(false, '');
    this.onSubmit(trimmed);
  }

  private openSuggestion(suggestion: SearchSuggestion): void {
    this.searching = false;
    this.engineMenuOpen = false;
    this.query = '';
    this.onSearchSessionChange(false, '');
    this.onOpenSuggestion(suggestion);
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
    return this.searching ? this.pageBackgroundColor : this.barBackgroundColor;
  }

  private shouldShowBottomBar(): boolean {
    return this.sessionMode !== 'search_only' && !this.searching;
  }

  private shouldShowTopBar(): boolean {
    if (this.searching || this.sessionMode === 'search_only') {
      return true;
    }
    return !(this.homeScene && this.suppressHomeAddressBar);
  }

  private shouldCollapseBars(): boolean {
    return this.barsCollapsed && !this.searching && this.sessionMode !== 'search_only';
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
    return SPLIT_TOOLBAR_BOTTOM_BAR_VP + this.resolveBottomInset();
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
    .backgroundColor(this.pressedSlotId === button.slotId ? this.pressedBackgroundColor : Color.Transparent)
    .borderRadius(SPLIT_TOOLBAR_NAV_PRESS_RADIUS)
    .clip(true)
    .stateEffect(false)
    .enabled(button.enabled)
    .accessibilityText(button.title)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(button.slotId, event.type, button.enabled);
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

  private updatePressed(slotId: string, type: TouchType, enabled: boolean): void {
    if (!enabled) {
      this.pressedSlotId = '';
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
