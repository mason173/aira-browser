import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import { SearchSuggestion } from '../../../common/models/BrowserModels';
import { BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT } from '../../../core/browser/BrowserSearchListSurfaceLayoutViewModel';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserSearchSuggestionsPanel } from './BrowserSearchSuggestionsPanel';

export const DOCK_SEARCH_EDGE_PADDING: number = 16;
export const DOCK_SEARCH_EDITOR_HEIGHT: number = 46;
export const DOCK_SEARCH_EDITOR_TOP_GAP: number = 10;
export const DOCK_SEARCH_EDITOR_BOTTOM_GAP: number = 10;

/** Fixed dock layout. Content revisions never replace or reposition the editor slot. */
@Component
export struct BrowserDockSearchSurface {
  @Prop query: string = '';
  @Prop suggestions: SearchSuggestion[] = [];
  @Prop dockSearchHistory: SearchSuggestion[] = [];
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomSafeInsetVp: number = 0;
  @Prop keyboardInsetVp: number = 0;
  @Prop engineMenuOpen: boolean = false;
  @Prop pageBackgroundColor: ResourceColor = '#FFFFFF';
  @Prop surfaceBackgroundColor: ResourceColor = '#F2F3F5';
  @Prop textColor: ResourceColor = '#111111';
  @Prop secondaryTextColor: ResourceColor = '#8A8A8E';
  @BuilderParam editor: () => void = this.emptyBuilder;
  @BuilderParam engineMenu: () => void = this.emptyBuilder;
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onClearSearchHistory: () => void = () => {};

  @Builder
  private emptyBuilder() {}

  build() {
    this.buildDockSurface()
  }

  @Builder
  private buildDockSurface() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // This viewport stays mounted even when no content is available.
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
                this.onOpenSuggestion(suggestion);
              },
              onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => {
                this.onDeleteHistorySuggestion(suggestion);
              }
            })
              .width('100%')
              .layoutWeight(1)
          } else if (this.dockSearchHistory.length > 0) {
            this.buildDockSearchHistory()
          }

        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({ minHeight: 0 })

        // The editor is a full-width pill; the wrapper owns the side inset so the pill itself
        // never reaches the screen edge (a 100%-wide row plus a margin would overflow instead).
        Column() {
          this.editor()
        }
        .width('100%')
        .padding({ left: DOCK_SEARCH_EDGE_PADDING, right: DOCK_SEARCH_EDGE_PADDING })
      }
      .width('100%')
      .height('100%')
      // Keep the editor at the bottom even while history or suggestions are empty/loading.
      .justifyContent(FlexAlign.End)

      if (this.engineMenuOpen) {
        Column() {
          this.engineMenu()
        }
        .width('100%')
        .padding({ left: DOCK_SEARCH_EDGE_PADDING, right: DOCK_SEARCH_EDGE_PADDING })
        .margin({ bottom: DOCK_SEARCH_EDITOR_TOP_GAP + DOCK_SEARCH_EDITOR_HEIGHT + DOCK_SEARCH_EDITOR_BOTTOM_GAP })
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: Math.max(0, this.topSafeInsetVp),
      // The keyboard lifts the editor; the gesture inset keeps it clear when there is none.
      bottom: Math.max(Math.max(0, this.keyboardInsetVp), Math.max(0, this.bottomSafeInsetVp))
    })
    .backgroundColor(this.surfaceBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
  }

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
      .padding({ left: DOCK_SEARCH_EDGE_PADDING, right: DOCK_SEARCH_EDGE_PADDING, top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    // Rest the history against the editor above the keyboard, not against the top of the page.
    .align(Alignment.BottomStart)
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
        this.onOpenSuggestion(suggestion);
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

  private shouldShowDockSuggestions(): boolean {
    return this.query.trim().length > 0 && this.resolveDockQuerySuggestions().length > 0;
  }

  private resolveDockQuerySuggestions(): SearchSuggestion[] {
    return this.suggestions.filter((suggestion: SearchSuggestion): boolean => {
      return suggestion.source !== 'history' && suggestion.source !== 'search_history';
    });
  }
}
