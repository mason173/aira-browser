import { ExternalAppSearchTargetId, SearchSuggestion } from '../../../common/models/BrowserModels';
import { ExternalAppSearchTarget } from '../../../services/search/ExternalAppSearchService';
import { BrowserBottomPanelWidthBreakpoint } from '../../../core/browser/BrowserBottomPanelResponsiveViewModel';
import {
  SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
  SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP
} from '../../../core/browser/BrowserToolbarChromeStylePolicy';
import {
  BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT,
  resolveExternalAppSearchPageSize
} from '../../../core/browser/BrowserSearchListSurfaceLayoutViewModel';
import { BrowserSearchSuggestionsPanel } from './BrowserSearchSuggestionsPanel';
import { ExternalAppSearchStrip } from './ExternalAppSearchStrip';

/** Fixed top-input search content. The native chrome retains the editor's geometry-transition node. */
@Component
export struct BrowserSplitSearchSurface {
  @Prop query: string = '';
  @Prop suggestions: SearchSuggestion[] = [];
  @Prop externalTargets: ExternalAppSearchTarget[] = [];
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomReserveVp: number = 0;
  @Prop keyboardInsetVp: number = 0;
  @Prop viewportWidth: number = 0;
  @Prop widthBreakpoint: BrowserBottomPanelWidthBreakpoint = 'sm';
  @Prop pageBackgroundColor: ResourceColor = '#FFFFFF';
  @Prop secondaryTextColor: ResourceColor = '#8A8A8E';
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onExternalSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string) => {};

  build() {
    this.buildSplitSurface()
  }

  @Builder
  private buildSplitSurface() {
    Column() {
      // The split search field lives in the top bar. Cross-app icons belong under that field,
      // not in the floating toolbar's bottom dock.
      if (this.externalTargets.length > 0) {
        Column() {
          ExternalAppSearchStrip({
            targets: this.externalTargets,
            query: this.query,
            labelColor: this.secondaryTextColor,
            pageSize: resolveExternalAppSearchPageSize(
              this.viewportWidth, SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP, this.widthBreakpoint
            ),
            onSearch: (targetId: ExternalAppSearchTargetId, query: string) => {
              this.onExternalSearch(targetId, query);
            }
          })
        }
        .width('100%')
        .padding({
          left: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP,
          right: SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP,
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
          this.onOpenSuggestion(suggestion);
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
      top: Math.max(0, this.topSafeInsetVp) + SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
      bottom: Math.max(0, this.bottomReserveVp) + Math.max(0, this.keyboardInsetVp)
    })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.pageBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
  }
}
