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
  SPLIT_TOOLBAR_BOTTOM_BAR_VP
} from '../../../core/browser/BrowserToolbarChromeStylePolicy';
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
const SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN: number = 16;
const SPLIT_TOOLBAR_TAB_COUNT_LIMIT: number = 99;
const SPLIT_TOOLBAR_SELECT_ALL_DELAY_MS: number = 40;
const SPLIT_TOOLBAR_NAV_BUTTON_WIDTH: number = 48;
const SPLIT_TOOLBAR_NAV_BUTTON_HEIGHT: number = 44;
const SPLIT_TOOLBAR_NAV_PRESS_RADIUS: number = 12;
const SPLIT_TOOLBAR_ICON_SIZE: number = 22;
const SPLIT_TOOLBAR_TAB_BADGE_SIZE: number = 18;
const SPLIT_TOOLBAR_TAB_BADGE_RADIUS: number = 4.5;
const SPLIT_TOOLBAR_TAB_BADGE_STROKE: number = 2;
const SPLIT_TOOLBAR_SEARCH_INPUT_ID: string = 'split-toolbar-search-input';

@Component
export struct BrowserSplitToolbarChrome {
  private searchEnginePresentation: BrowserSearchEnginePresentationViewModel =
    new BrowserSearchEnginePresentationViewModel();
  private searchInputController: TextInputController = new TextInputController();
  private appliedSearchDismissVersion: number = 0;
  private externalAppSearchService: ExternalAppSearchService = new ExternalAppSearchService();
  @State private searching: boolean = false;
  @State private query: string = '';
  @State private engineMenuOpen: boolean = false;
  @State private pressedAction: string = '';
  @Prop homeScene: boolean = true;
  @Prop displayAddress: string = '';
  @Prop editableAddress: string = '';
  @Prop secure: boolean = true;
  @Prop canGoBack: boolean = false;
  @Prop canGoForward: boolean = false;
  @Prop tabCount: number = 1;
  @Prop pageLoading: boolean = false;
  @Prop suggestions: SearchSuggestion[] = [];
  @Prop searchEngines: SearchEngineRecord[] = [];
  @Prop selectedEngineId: SearchEngineId = 'bing';
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomSafeInsetVp: number = 0;
  @Prop keyboardInsetVp: number = 0;
  @Prop @Watch('handleSearchDismissRequest') searchDismissVersion: number = 0;
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
  onBack: () => void = () => {};
  onForward: () => void = () => {};
  onOpenBookmarks: () => void = () => {};
  onOpenHistory: () => void = () => {};
  onHome: () => void = () => {};
  onReload: () => void = () => {};
  onOpenTabs: () => void = () => {};
  onOpenMenu: () => void = () => {};
  onOpenSiteInfo: () => void = () => {};
  onScan: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.searching) {
        this.buildSearchSheet()
      }
      Column() {
        this.buildTopBar()
        Blank()
        this.buildBottomBar()
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
      if (this.searching) {
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
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
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
    .border({ width: 1.5, color: this.textColor })
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
      bottom: this.resolveBottomChromeHeight() + Math.max(0, this.keyboardInsetVp)
    })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.pageBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private buildBottomBar() {
    Stack() {
      Row() {
        if (this.homeScene) {
          this.buildNavButton('browser.shortcut.bookmarks', true, 'bookmarks')
          this.buildNavButton('browser.shortcut.history', true, 'history')
        } else {
          this.buildNavButton('browser.toolbar.back', this.canGoBack, 'back')
          this.buildNavButton('browser.toolbar.forward', this.canGoForward, 'forward')
        }
        this.buildNavButton('browser.toolbar.home', true, 'home')
        this.buildTabButton()
        this.buildNavButton('browser.toolbar.menu', true, 'menu')
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.resolveBottomInset() })
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      .onTouch((_event: TouchEvent) => {
      })
    }
    .width('100%')
    .height(this.resolveBottomChromeHeight())
    .backgroundColor(this.resolveBarBackground())
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onTouch((_event: TouchEvent) => {
    })
  }

  @Builder
  private buildTabButton() {
    Button() {
      Stack({ alignContent: Alignment.Center }) {
        Text(this.formatTabCount())
          .fontSize(this.resolveTabBadgeFontSize())
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
      .width(SPLIT_TOOLBAR_TAB_BADGE_SIZE)
      .height(SPLIT_TOOLBAR_TAB_BADGE_SIZE)
      .borderRadius(SPLIT_TOOLBAR_TAB_BADGE_RADIUS)
      .border({ width: SPLIT_TOOLBAR_TAB_BADGE_STROKE, color: this.textColor })
      .backgroundColor(Color.Transparent)
    }
    .width(SPLIT_TOOLBAR_NAV_BUTTON_WIDTH)
    .height(SPLIT_TOOLBAR_NAV_BUTTON_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor(Color.Transparent)
    .stateEffect(false)
    .onClick(() => {
      this.onOpenTabs();
    })
  }

  @Builder
  private buildNavButton(iconId: AiraRenderableIconId, enabled: boolean, action: string) {
    Button() {
      AiraIcon({
        airaIconId: iconId,
        iconSize: SPLIT_TOOLBAR_ICON_SIZE,
        iconColor: enabled ? this.textColor : this.secondaryTextColor
      })
    }
    .width(SPLIT_TOOLBAR_NAV_BUTTON_WIDTH)
    .height(SPLIT_TOOLBAR_NAV_BUTTON_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor(this.resolvePressedBackground(action))
    .borderRadius(SPLIT_TOOLBAR_NAV_PRESS_RADIUS)
    .clip(true)
    .stateEffect(false)
    .enabled(enabled)
    .onTouch((event: TouchEvent) => {
      this.updatePressedAction(action, event.type, enabled);
    })
    .onClick(() => {
      if (!enabled) {
        return;
      }
      if (action === 'back') {
        this.onBack();
        return;
      }
      if (action === 'forward') {
        this.onForward();
        return;
      }
      if (action === 'bookmarks') {
        this.closeSearch();
        this.onOpenBookmarks();
        return;
      }
      if (action === 'history') {
        this.closeSearch();
        this.onOpenHistory();
        return;
      }
      if (action === 'home') {
        this.closeSearch();
        this.onHome();
        return;
      }
      this.onOpenMenu();
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

  private closeSearch(): void {
    if (!this.searching && !this.engineMenuOpen) {
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

  private formatTabCount(): string {
    const count = Math.max(0, Math.floor(this.tabCount));
    if (count > SPLIT_TOOLBAR_TAB_COUNT_LIMIT) {
      return `${SPLIT_TOOLBAR_TAB_COUNT_LIMIT}`;
    }
    return `${count}`;
  }

  private resolveTabBadgeFontSize(): number {
    return this.formatTabCount().length > 1 ? 10 : 12;
  }

  private resolveBarBackground(): ResourceColor {
    return this.searching ? this.pageBackgroundColor : this.barBackgroundColor;
  }

  private resolvePressedBackground(action: string): ResourceColor {
    return this.pressedAction === action ? this.pressedBackgroundColor : this.resolveBarBackground();
  }

  private updatePressedAction(action: string, type: TouchType, enabled: boolean): void {
    if (!enabled) {
      this.pressedAction = '';
      return;
    }
    if (type === TouchType.Down) {
      this.pressedAction = action;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedAction = '';
    }
  }

  private resolveTopInset(): number {
    return Math.max(0, this.topSafeInsetVp);
  }

  private resolveBottomInset(): number {
    return Math.max(0, this.bottomSafeInsetVp);
  }

  private resolveBottomChromeHeight(): number {
    return SPLIT_TOOLBAR_BOTTOM_BAR_VP + this.resolveBottomInset();
  }
}
