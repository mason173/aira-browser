import { BookmarkManagerSearchHeader } from './BookmarkManagerSearchHeader';
import { resolveManagementImmersiveTitleBottomInset } from '../common/ManagementHdsScaffold';

const BOOKMARK_IMMERSIVE_TITLE_TO_TABS_GAP: number = 12;
const BOOKMARK_IMMERSIVE_TABS_HEIGHT: number = 44;
const BOOKMARK_IMMERSIVE_TABS_TO_CONTENT_GAP: number = 4;
const BOOKMARK_IMMERSIVE_TITLE_TO_CONTENT_GAP: number = 20;
const BOOKMARK_IMMERSIVE_SEARCH_TOP_INSET: number = 8;
const BOOKMARK_IMMERSIVE_SEARCH_HEADER_HEIGHT: number = 64;
const BOOKMARK_IMMERSIVE_SEARCH_TO_CONTENT_GAP: number = 8;

function resolveBookmarkSearchHeaderTopInset(topSafeInsetVp: number): number {
  return Math.max(0, Math.ceil(topSafeInsetVp)) + BOOKMARK_IMMERSIVE_SEARCH_TOP_INSET;
}

export function resolveBookmarkManagerTabsTopInset(topSafeInsetVp: number): number {
  return resolveManagementImmersiveTitleBottomInset(topSafeInsetVp) + BOOKMARK_IMMERSIVE_TITLE_TO_TABS_GAP;
}

/** Keep list layout and browse-position restoration in the same coordinate system. */
export function resolveBookmarkManagerContentTopInset(topSafeInsetVp: number, isSearchMode: boolean,
  showRootTabs: boolean): number {
  if (isSearchMode) {
    return resolveBookmarkSearchHeaderTopInset(topSafeInsetVp) + BOOKMARK_IMMERSIVE_SEARCH_HEADER_HEIGHT +
      BOOKMARK_IMMERSIVE_SEARCH_TO_CONTENT_GAP;
  }
  return resolveManagementImmersiveTitleBottomInset(topSafeInsetVp) + (showRootTabs
    ? BOOKMARK_IMMERSIVE_TITLE_TO_TABS_GAP + BOOKMARK_IMMERSIVE_TABS_HEIGHT + BOOKMARK_IMMERSIVE_TABS_TO_CONTENT_GAP
    : BOOKMARK_IMMERSIVE_TITLE_TO_CONTENT_GAP);
}

@Component
export struct BookmarkManagerImmersiveHost {
  @Prop isSearchMode: boolean = false;
  @Prop query: string = '';
  @Prop pageBackground: ResourceColor = Color.Transparent;
  @Prop topSafeInsetVp: number = 0;
  onQueryChange: (query: string) => void = (_query: string): void => {};
  onCloseSearch: () => void = (): void => {};
  // Let the caller read its reactive page state; a by-value layout argument keeps
  // the old folder inset when the same page switches back to root tabs or search.
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()

      if (this.isSearchMode) {
        Column() {
          BookmarkManagerSearchHeader({
            query: this.query,
            onQueryChange: (query: string): void => {
              this.onQueryChange(query);
            },
            onClose: (): void => {
              this.onCloseSearch();
            }
          })
        }
        .width('100%')
        .position({ x: 0, y: this.resolveSearchHeaderTopInset() })
        .zIndex(2)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBackground)
  }

  private resolveSearchHeaderTopInset(): number {
    return resolveBookmarkSearchHeaderTopInset(this.topSafeInsetVp);
  }

  @Builder
  private emptyContent() {
  }
}
