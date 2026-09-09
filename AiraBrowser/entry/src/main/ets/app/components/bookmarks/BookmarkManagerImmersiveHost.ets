import { BookmarkManagerSearchHeader } from './BookmarkManagerSearchHeader';
import { resolveManagementImmersiveTitleBottomInset } from '../common/ManagementHdsScaffold';

const BOOKMARK_IMMERSIVE_TITLE_TO_TABS_GAP: number = 12;
const BOOKMARK_IMMERSIVE_TABS_HEIGHT: number = 44;
const BOOKMARK_IMMERSIVE_TABS_TO_CONTENT_GAP: number = 4;
const BOOKMARK_IMMERSIVE_TITLE_TO_CONTENT_GAP: number = 20;
const BOOKMARK_IMMERSIVE_SEARCH_TOP_INSET: number = 8;
const BOOKMARK_IMMERSIVE_SEARCH_HEADER_HEIGHT: number = 64;
const BOOKMARK_IMMERSIVE_SEARCH_TO_CONTENT_GAP: number = 8;

export class BookmarkManagerImmersiveLayoutContext {
  tabsTopInset: number = 0;
  contentTopInset: number = 0;

  constructor(tabsTopInset: number, contentTopInset: number) {
    this.tabsTopInset = tabsTopInset;
    this.contentTopInset = contentTopInset;
  }
}

@Component
export struct BookmarkManagerImmersiveHost {
  @Prop isSearchMode: boolean = false;
  @Prop showRootTabs: boolean = false;
  @Prop query: string = '';
  @Prop pageBackground: ResourceColor = Color.Transparent;
  @Prop topSafeInsetVp: number = 0;
  onQueryChange: (query: string) => void = (_query: string): void => {};
  onCloseSearch: () => void = (): void => {};
  @BuilderParam content: (context: BookmarkManagerImmersiveLayoutContext) => void = this.emptyContent;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content(this.buildLayoutContext())

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

  private resolveTabsTopInset(): number {
    return resolveManagementImmersiveTitleBottomInset(this.topSafeInsetVp) +
      BOOKMARK_IMMERSIVE_TITLE_TO_TABS_GAP;
  }

  private resolveSearchHeaderTopInset(): number {
    return Math.max(0, Math.ceil(this.topSafeInsetVp)) + BOOKMARK_IMMERSIVE_SEARCH_TOP_INSET;
  }

  private resolveContentTopInset(): number {
    if (this.isSearchMode) {
      return this.resolveSearchHeaderTopInset() + BOOKMARK_IMMERSIVE_SEARCH_HEADER_HEIGHT +
        BOOKMARK_IMMERSIVE_SEARCH_TO_CONTENT_GAP;
    }
    if (this.showRootTabs) {
      return this.resolveTabsTopInset() + BOOKMARK_IMMERSIVE_TABS_HEIGHT +
        BOOKMARK_IMMERSIVE_TABS_TO_CONTENT_GAP;
    }
    return resolveManagementImmersiveTitleBottomInset(this.topSafeInsetVp) +
      BOOKMARK_IMMERSIVE_TITLE_TO_CONTENT_GAP;
  }

  private buildLayoutContext(): BookmarkManagerImmersiveLayoutContext {
    return new BookmarkManagerImmersiveLayoutContext(this.resolveTabsTopInset(), this.resolveContentTopInset());
  }

  @Builder
  private emptyContent(_context: BookmarkManagerImmersiveLayoutContext) {
  }
}
