import { KeyCode } from '@kit.InputKit';
import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import {
  ExternalAppSearchTargetId,
  SearchSuggestion
} from '../../../common/models/BrowserModels';
import {
  CENTERED_HOME_HEADER_BOTTOM_GAP,
  CENTERED_HOME_LARGE_SCREEN_SEARCH_MAX_WIDTH,
  CENTERED_HOME_SEARCH_GEOMETRY_ID,
  CENTERED_HOME_SEARCH_GEOMETRY_OPEN_KEY,
  CENTERED_HOME_SEARCH_HEIGHT,
  CENTERED_HOME_WORDMARK_HEIGHT,
  CENTERED_HOME_WORDMARK_SEARCH_GAP
} from '../../../features/newtab/CenteredHomeShortcutLayoutPolicy';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserLargeScreenOmniboxSearchSurface } from './BrowserLargeScreenOmniboxSearchSurface';
import { HomeLogoMark } from './HomeLogoMark';

const CENTERED_HOME_SEARCH_RADIUS: number = 24;
const CENTERED_HOME_SEARCH_BORDER_WIDTH: number = 2;
const CENTERED_HOME_INLINE_SEARCH_BLUR_DISMISS_MS: number = 120;

/**
 * Wordmark and search field for the centered homepage.
 *
 * On a phone, tapping the field asks the shell to open the shared search page.
 * On a large screen the field itself is the input: typing stays here, and suggestions
 * drop down under the box instead of replacing the page.
 */
@Component
export struct CenteredHomeHeader {
  @Prop textColor: ResourceColor = '#111111';
  @Prop secondaryTextColor: ResourceColor = '#8A8A8E';
  @Prop fieldBackgroundColor: ResourceColor = Color.Transparent;
  /** True while the phone search page owns the shared field, so this copy can leave. */
  @Prop searchPresented: boolean = false;
  /**
   * Same flag as searchPresented, read here so this field appears in the same frame as the
   * top pill leaves. The @Prop arrives a few frames later and the flight has no destination.
   */
  @StorageLink(CENTERED_HOME_SEARCH_GEOMETRY_OPEN_KEY) private geometryFlightOpen: boolean = false;
  /**
   * Only the split search page shares this field's geometry. The floating toolbar has no pair,
   * and an unpaired geometry transition slides a surface in from the right.
   */
  @Prop searchGeometryEnabled: boolean = true;
  /** Large-screen home types into this field instead of opening the phone search page. */
  @Prop inlineSearch: boolean = false;
  /** Minimal home keeps the field and drops the scan button. */
  @Prop showScanButton: boolean = true;
  /** Minimal uses the secondary text color so the field is not a near-black ring. */
  @Prop softenSearchBorder: boolean = false;
  /** Extra inset so this field's edges match the search-page pill. */
  @Prop searchSideInset: number = 0;
  /** Centered and minimal open homepage settings from this wordmark. */
  @Prop wordmarkOpensSettings: boolean = false;
  @Prop searchSuggestions: SearchSuggestion[] = [];
  @Prop searchViewportHeight: number = 0;
  @Prop searchPopupReservedTop: number = 0;
  @Prop @Watch('applyInlineSearchDismiss') searchDismissVersion: number = 0;
  onOpenSearch: () => void = () => {};
  onOpenSettings: () => void = () => {};
  onScan: () => void = () => {};
  onInlineSearchSession: (active: boolean, query: string) => void =
    (_active: boolean, _query: string) => {};
  onSubmitSearch: (query: string) => void = (_query: string) => {};
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onDeleteSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onClearSuggestions: () => void = () => {};
  onExternalSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string) => {};

  private inlineInputController: TextInputController = new TextInputController();
  private inlineBlurTimer: number = -1;
  private appliedSearchDismissVersion: number = 0;
  @State private inlineQuery: string = '';
  @State private inlineFocused: boolean = false;
  @State private logoMaxWidthVp: number = 320;

  aboutToDisappear(): void {
    this.clearInlineBlurTimer();
  }

  build() {
    Column({ space: CENTERED_HOME_WORDMARK_SEARCH_GAP }) {
      HomeLogoMark({
        heightVp: CENTERED_HOME_WORDMARK_HEIGHT,
        maxWidthVp: this.logoMaxWidthVp,
        tintColor: this.textColor,
        clickable: this.wordmarkOpensSettings,
        label: this.wordmarkOpensSettings ? resolveAppResourceText($r('app.string.home_settings_title')) : 'Aira',
        onLogoClick: () => {
          this.onOpenSettings();
        }
      })

      this.buildSearchSlot()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateLogoMaxWidth(newArea.width);
    })
    .padding({ bottom: CENTERED_HOME_HEADER_BOTTOM_GAP })
    .clip(false)
  }

  @Builder
  private buildSearchSlot() {
    Column() {
      if (this.inlineSearch) {
        this.buildInlineSearchField()
      } else {
        Stack() {
          if (!this.geometryFlightOpen) {
            this.buildSearchField()
          }
        }
        .width('100%')
        .height(CENTERED_HOME_SEARCH_HEIGHT)
      }

      if (this.inlineSearch && this.inlineFocused) {
        BrowserLargeScreenOmniboxSearchSurface({
          editing: true,
          inputFocused: true,
          query: this.inlineQuery,
          suggestions: this.searchSuggestions,
          viewportHeightVp: this.searchViewportHeight,
          popupReservedTopVp: this.searchPopupReservedTop,
          onOpenSuggestion: (suggestion: SearchSuggestion): void => {
            this.commitInlineSuggestion(suggestion);
          },
          onDeleteHistorySuggestion: (suggestion: SearchSuggestion): void => {
            this.clearInlineBlurTimer();
            this.onDeleteSuggestion(suggestion);
          },
          onClearHistorySuggestions: (): void => {
            this.clearInlineBlurTimer();
            this.onClearSuggestions();
          },
          onExternalAppSearch: (targetId: ExternalAppSearchTargetId, query: string): void => {
            this.finishInlineEditing();
            this.onExternalSearch(targetId, query);
          }
        })
          .width('100%')
          .margin({ top: 8 })
          .hitTestBehavior(HitTestMode.Default)
      }
    }
    .width(this.inlineSearch ? CENTERED_HOME_LARGE_SCREEN_SEARCH_MAX_WIDTH : '100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Center)
    .padding({ left: this.searchSideInset, right: this.searchSideInset })
  }

  @Builder
  private buildSearchField() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.onOpenSearch();
        })

      Row() {
        Text($r('app.string.aira_search_card_placeholder'))
          .layoutWeight(1)
          .fontSize(16)
          .fontColor(this.secondaryTextColor)
          .maxLines(1)
          .textAlign(TextAlign.Start)
          .hitTestBehavior(HitTestMode.None)

        if (this.showScanButton) {
          this.buildScanButton()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 18, right: this.showScanButton ? 6 : 18 })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height(CENTERED_HOME_SEARCH_HEIGHT)
    .border({
      width: this.softenSearchBorder ? 1.5 : CENTERED_HOME_SEARCH_BORDER_WIDTH,
      color: this.softenSearchBorder ? this.secondaryTextColor : this.textColor
    })
    .borderRadius(CENTERED_HOME_SEARCH_RADIUS)
    .backgroundColor(this.fieldBackgroundColor)
    .clip(true)
    .id('centered-home-search-source')
    .geometryTransition(this.searchGeometryEnabled ? CENTERED_HOME_SEARCH_GEOMETRY_ID : '')
    .transition(this.searchGeometryEnabled ? TransitionEffect.opacity(0.99) : TransitionEffect.IDENTITY)
  }

  @Builder
  private buildInlineSearchField() {
    Row() {
      TextInput({
        text: this.inlineQuery,
        placeholder: $r('app.string.aira_search_card_placeholder'),
        controller: this.inlineInputController
      })
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .height(CENTERED_HOME_SEARCH_HEIGHT)
        .fontSize(16)
        .halfLeading(true)
        .fontColor(this.textColor)
        .placeholderColor(this.secondaryTextColor)
        .caretColor(this.textColor)
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0, top: 0, bottom: 0 })
        .border({ width: 0, color: Color.Transparent })
        .borderRadius(0)
        .showUnderline(false)
        .maxLines(1)
        .enterKeyType(EnterKeyType.Go)
        .focusable(true)
        .enableKeyboardOnFocus(true)
        .onFocus(() => {
          this.clearInlineBlurTimer();
          this.inlineFocused = true;
          this.onInlineSearchSession(true, this.inlineQuery);
        })
        .onBlur(() => {
          this.scheduleInlineBlurDismiss();
        })
        .onChange((value: string) => {
          if (value === this.inlineQuery) {
            return;
          }
          this.inlineQuery = value;
          this.onInlineSearchSession(true, value);
        })
        .onSubmit((_enterKey: EnterKeyType) => {
          const query = this.inlineQuery;
          this.finishInlineEditing();
          this.onSubmitSearch(query);
        })
        .onKeyPreIme((event: KeyEvent): boolean => {
          if (event.type !== KeyType.Down || event.keyCode !== KeyCode.KEYCODE_ESCAPE) {
            return false;
          }
          this.finishInlineEditing();
          this.onInlineSearchSession(false, '');
          return true;
        })

      if (this.showScanButton) {
        this.buildScanButton()
      }
    }
    .width('100%')
    .height(CENTERED_HOME_SEARCH_HEIGHT)
    .padding({ left: 18, right: this.showScanButton ? 6 : 18 })
    .border({
      width: this.softenSearchBorder ? 1.5 : CENTERED_HOME_SEARCH_BORDER_WIDTH,
      color: this.softenSearchBorder ? this.secondaryTextColor : this.textColor
    })
    .borderRadius(CENTERED_HOME_SEARCH_RADIUS)
    .backgroundColor(this.fieldBackgroundColor)
    .clip(true)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildScanButton() {
    Button() {
      AiraIcon({
        airaIconId: 'browser.toolbar.scanQr',
        iconSize: 20,
        iconColor: this.textColor
      })
    }
    .width(36)
    .height(36)
    .type(ButtonType.Circle)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor(Color.Transparent)
    .stateEffect(false)
    .onClick(() => {
      this.onScan();
    })
  }

  private commitInlineSuggestion(suggestion: SearchSuggestion): void {
    this.finishInlineEditing();
    this.onOpenSuggestion(suggestion);
  }

  private finishInlineEditing(): void {
    this.clearInlineBlurTimer();
    this.inlineFocused = false;
    this.inlineInputController.stopEditing();
  }

  private scheduleInlineBlurDismiss(): void {
    this.clearInlineBlurTimer();
    this.inlineBlurTimer = setTimeout(() => {
      this.inlineBlurTimer = -1;
      if (!this.inlineFocused) {
        return;
      }
      this.inlineFocused = false;
      this.inlineQuery = '';
      this.onInlineSearchSession(false, '');
    }, CENTERED_HOME_INLINE_SEARCH_BLUR_DISMISS_MS);
  }

  private clearInlineBlurTimer(): void {
    if (this.inlineBlurTimer < 0) {
      return;
    }
    clearTimeout(this.inlineBlurTimer);
    this.inlineBlurTimer = -1;
  }

  private updateLogoMaxWidth(width: Length): void {
    const parsed = Number.parseFloat(`${width}`);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return;
    }
    const next = Math.ceil(parsed);
    if (next !== this.logoMaxWidthVp) {
      this.logoMaxWidthVp = next;
    }
  }

  private applyInlineSearchDismiss(): void {
    if (this.searchDismissVersion === this.appliedSearchDismissVersion) {
      return;
    }
    this.appliedSearchDismissVersion = this.searchDismissVersion;
    if (!this.inlineSearch || this.searchDismissVersion <= 0) {
      return;
    }
    this.finishInlineEditing();
    this.inlineQuery = '';
    this.onInlineSearchSession(false, '');
  }
}
