import { ExternalAppSearchTargetId, SearchSuggestion } from '../../../common/models/BrowserModels';
import {
  BrowserSearchListSurfaceHostLayout,
  BrowserSearchListSurfaceLayoutViewModel,
  BrowserSearchListSurfaceLayoutState
} from '../../../core/browser/BrowserSearchListSurfaceLayoutViewModel';
import {
  BrowserForegroundPresentation,
  createDefaultBrowserForegroundPresentation
} from '../../../core/browser/BrowserForegroundPresentationViewModel';
import { ExternalAppSearchTarget } from '../../../services/search/ExternalAppSearchService';
import { BrowserSearchSuggestionsPanel } from './BrowserSearchSuggestionsPanel';
import { ExternalAppSearchStrip } from './ExternalAppSearchStrip';

export interface BrowserSearchListSurfaceOpenSuggestionIntent {
  kind: 'open_suggestion';
  suggestion: SearchSuggestion;
}

export interface BrowserSearchListSurfaceDeleteHistoryIntent {
  kind: 'delete_history_suggestion';
  suggestion: SearchSuggestion;
}

export interface BrowserSearchListSurfaceBlankBackIntent {
  kind: 'blank_back';
}

export interface BrowserSearchListSurfaceExternalSearchIntent {
  kind: 'external_search';
  targetId: ExternalAppSearchTargetId;
  query: string;
}

export type BrowserSearchListSurfaceIntent =
  BrowserSearchListSurfaceOpenSuggestionIntent |
  BrowserSearchListSurfaceDeleteHistoryIntent |
  BrowserSearchListSurfaceBlankBackIntent |
  BrowserSearchListSurfaceExternalSearchIntent;

export interface BrowserSearchListSurfacePresentation {
  suggestions: SearchSuggestion[];
  externalTargets: ExternalAppSearchTarget[];
  query: string;
  blankAreaBackEnabled: boolean;
  currentTabSuggestionRefId: string;
  hostLayout: BrowserSearchListSurfaceHostLayout;
  pressedBackgroundColor: ResourceColor | undefined;
  foreground: BrowserForegroundPresentation;
}

function buildDefaultBrowserSearchListSurfacePresentation(): BrowserSearchListSurfacePresentation {
  return {
    suggestions: [],
    externalTargets: [],
    query: '',
    blankAreaBackEnabled: false,
    currentTabSuggestionRefId: '',
    hostLayout: {
      surfaceWidth: 360,
      contentHorizontalPadding: 0,
      widthBreakpoint: 'sm',
      heightBreakpoint: 'regular',
      aspectBreakpoint: 'tall'
    },
    pressedBackgroundColor: undefined,
    foreground: createDefaultBrowserForegroundPresentation()
  };
}

@Component
export struct BrowserSearchListSurface {
  private layoutViewModel: BrowserSearchListSurfaceLayoutViewModel = new BrowserSearchListSurfaceLayoutViewModel();
  @Prop presentation: BrowserSearchListSurfacePresentation = buildDefaultBrowserSearchListSurfacePresentation();
  onIntent: (intent: BrowserSearchListSurfaceIntent) => void = (_intent: BrowserSearchListSurfaceIntent) => {};

  build() {
    this.buildSurface(this.layoutViewModel.buildState(this.presentation.hostLayout))
  }

  @Builder
  private buildSurface(layout: BrowserSearchListSurfaceLayoutState) {
    Column({ space: layout.scrollClipSafetyGap }) {
      Column() {
        BrowserSearchSuggestionsPanel({
          suggestions: this.presentation.suggestions,
          layoutMode: 'bottomUp',
          horizontalPadding: 0,
          columns: layout.columns,
          columnGap: layout.columnGap,
          rowGap: layout.rowGap,
          regularRowHeight: layout.rowHeight,
          regularRowContentFrameHeight: layout.rowContentFrameHeight,
          scrollEnabled: true,
          cardBackgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
          pressedBackgroundColor: this.presentation.pressedBackgroundColor,
          useNativeStateEffect: true,
          regularCardHorizontalPadding: 0,
          blankAreaBackEnabled: this.presentation.blankAreaBackEnabled,
          currentTabSuggestionRefId: this.presentation.currentTabSuggestionRefId,
          foreground: this.presentation.foreground,
          onOpenSuggestion: (suggestion: SearchSuggestion) => {
            this.emitSuggestionIntent('open_suggestion', suggestion);
          },
          onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => {
            this.emitSuggestionIntent('delete_history_suggestion', suggestion);
          },
          onBlankAreaBack: () => {
            this.onIntent({ kind: 'blank_back' });
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ minHeight: 0 })

      if (this.presentation.externalTargets.length > 0) {
        ExternalAppSearchStrip({
          targets: this.presentation.externalTargets,
          query: this.presentation.query,
          labelColor: this.presentation.foreground.primaryTextColor,
          stripHeight: layout.externalStripHeight,
          itemWidth: layout.externalItemWidth,
          actionSize: layout.externalActionSize,
          columnGap: layout.externalColumnGap,
          pageSize: layout.externalPageSize,
          onSearch: (targetId: ExternalAppSearchTargetId, query: string) => {
            this.onIntent({
              kind: 'external_search',
              targetId: targetId,
              query: query
            });
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: layout.contentHorizontalPadding,
      right: layout.contentHorizontalPadding,
      top: layout.contentVerticalPadding,
      bottom: layout.contentVerticalPadding
    })
  }

  private emitSuggestionIntent(
    kind: 'open_suggestion' | 'delete_history_suggestion',
    suggestion: SearchSuggestion
  ): void {
    if (kind === 'open_suggestion') {
      this.onIntent({
        kind: 'open_suggestion',
        suggestion: suggestion
      });
      return;
    }
    this.onIntent({
      kind: 'delete_history_suggestion',
      suggestion: suggestion
    });
  }
}
