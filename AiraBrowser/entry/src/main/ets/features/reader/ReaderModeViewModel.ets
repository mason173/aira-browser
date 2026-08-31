import {
  createDefaultReaderModeOverlayBackState,
  createDefaultReaderModeViewState,
  ReaderModeArticle,
  ReaderModeOverlayBackState,
  ReaderModeSearchState,
  ReaderModeTheme,
  ReaderModeViewState
} from './ReaderModeModels';
import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';

export class ReaderModeViewModel {
  createInitialState(): ReaderModeViewState {
    return createDefaultReaderModeViewState();
  }

  createInitialOverlayBackState(): ReaderModeOverlayBackState {
    return createDefaultReaderModeOverlayBackState();
  }

  resolveEffectiveTheme(theme: ReaderModeTheme, systemTheme: BrowserResolvedThemeMode): ReaderModeTheme {
    return theme === 'system' ? systemTheme : theme;
  }

  buildImagePreviewVisibilityState(
    current: ReaderModeOverlayBackState,
    visible: boolean
  ): ReaderModeOverlayBackState {
    return {
      imagePreviewVisible: visible,
      dismissImagePreviewRequestVersion: current.dismissImagePreviewRequestVersion,
      panelVisible: current.panelVisible,
      dismissPanelRequestVersion: current.dismissPanelRequestVersion
    };
  }

  buildImagePreviewDismissRequest(current: ReaderModeOverlayBackState): ReaderModeOverlayBackState {
    return {
      imagePreviewVisible: current.imagePreviewVisible,
      dismissImagePreviewRequestVersion: current.dismissImagePreviewRequestVersion + 1,
      panelVisible: current.panelVisible,
      dismissPanelRequestVersion: current.dismissPanelRequestVersion
    };
  }

  buildPanelVisibilityState(
    current: ReaderModeOverlayBackState,
    visible: boolean
  ): ReaderModeOverlayBackState {
    return {
      imagePreviewVisible: current.imagePreviewVisible,
      dismissImagePreviewRequestVersion: current.dismissImagePreviewRequestVersion,
      panelVisible: visible,
      dismissPanelRequestVersion: current.dismissPanelRequestVersion
    };
  }

  buildPanelDismissRequest(current: ReaderModeOverlayBackState): ReaderModeOverlayBackState {
    return {
      imagePreviewVisible: current.imagePreviewVisible,
      dismissImagePreviewRequestVersion: current.dismissImagePreviewRequestVersion,
      panelVisible: current.panelVisible,
      dismissPanelRequestVersion: current.dismissPanelRequestVersion + 1
    };
  }

  buildLoadingState(current: ReaderModeViewState): ReaderModeViewState {
    return {
      visible: true,
      loading: true,
      errorMessage: '',
      article: current.article,
      preferences: current.preferences,
      search: this.buildSearchState('', current.article)
    };
  }

  buildArticleState(
    current: ReaderModeViewState,
    article: ReaderModeArticle
  ): ReaderModeViewState {
    return {
      visible: true,
      loading: false,
      errorMessage: '',
      article: article,
      preferences: current.preferences,
      search: this.buildSearchState(current.search.query, article)
    };
  }

  buildErrorState(current: ReaderModeViewState, message: string): ReaderModeViewState {
    return {
      visible: true,
      loading: false,
      errorMessage: message,
      article: current.article,
      preferences: current.preferences,
      search: current.search
    };
  }

  buildClosedState(current: ReaderModeViewState): ReaderModeViewState {
    return {
      visible: false,
      loading: false,
      errorMessage: '',
      article: current.article,
      preferences: current.preferences,
      search: {
        query: '',
        matches: 0,
        activeIndex: -1,
        activeBlockId: '',
        blockMatchCounts: {}
      }
    };
  }

  buildSearchState(query: string, article: ReaderModeArticle): ReaderModeSearchState {
    const normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.length <= 0) {
      return {
        query: query,
        matches: 0,
        activeIndex: -1,
        activeBlockId: '',
        blockMatchCounts: {}
      };
    }
    let matches = 0;
    const blockMatchCounts: Record<string, number> = {};
    let activeBlockId = '';
    article.blocks.forEach((block) => {
      const blockMatches = this.countMatches(block.text.toLowerCase(), normalizedQuery);
      if (blockMatches <= 0) {
        return;
      }
      if (activeBlockId.length <= 0) {
        activeBlockId = block.id;
      }
      blockMatchCounts[block.id] = blockMatches;
      matches += blockMatches;
    });
    return {
      query: query,
      matches: matches,
      activeIndex: matches > 0 ? 0 : -1,
      activeBlockId: matches > 0 ? activeBlockId : '',
      blockMatchCounts: blockMatchCounts
    };
  }

  moveSearchIndex(search: ReaderModeSearchState, step: number, article: ReaderModeArticle): ReaderModeSearchState {
    if (search.matches <= 0) {
      return search;
    }
    const nextIndex = (search.activeIndex + step + search.matches) % search.matches;
    return {
      query: search.query,
      matches: search.matches,
      activeIndex: nextIndex,
      activeBlockId: this.resolveActiveBlockId(article, search, nextIndex),
      blockMatchCounts: search.blockMatchCounts
    };
  }

  private countMatches(text: string, query: string): number {
    let matches = 0;
    let cursor = text.indexOf(query);
    while (cursor >= 0) {
      matches += 1;
      cursor = text.indexOf(query, cursor + query.length);
    }
    return matches;
  }

  private resolveActiveBlockId(
    article: ReaderModeArticle,
    search: ReaderModeSearchState,
    activeIndex: number
  ): string {
    let seenMatches = 0;
    for (let index = 0; index < article.blocks.length; index += 1) {
      const block = article.blocks[index];
      const blockMatches = search.blockMatchCounts[block.id] ?? 0;
      if (blockMatches <= 0) {
        continue;
      }
      if (activeIndex < seenMatches + blockMatches) {
        return block.id;
      }
      seenMatches += blockMatches;
    }
    return '';
  }
}
