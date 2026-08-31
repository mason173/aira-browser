import {
  createDefaultHomeContentSectionsPresentationState,
  HomeContentSectionsPresentationState,
  HomeContentThemePresentationState,
  createDefaultHomeContentThemePresentationState
} from '../../../core/browser/HomeContentPresentationState';
import { HomeShortcutUserAction } from '../../../features/newtab/HomeShortcutTypes';
import { HomeShortcutViewModel } from '../../../features/newtab/HomeShortcutViewModel';
import { BrowserRecentlyClosedUserAction } from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { BrowserTabHomeContentAction } from '../../../core/browser/BrowserTabHomeCoordinator';
import { HomeFavoritesSection } from './HomeFavoritesSection';
import { HomeRecentlyClosedSection } from './HomeRecentlyClosedSection';
import { HomeSettingsActionRow } from './HomeSettingsActionRow';
import {
  HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY
} from '../../../common/constants/HomePagePresentationStorageKeys';

const HOME_SECTION_CONTENT_INSET: number = 10;

@Component
export struct HomeContentSections {
  private homeContentScroller: Scroller = new Scroller();
  private homeShortcutViewModel: HomeShortcutViewModel = new HomeShortcutViewModel();
  @StorageProp(HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY)
  private storedShowFavoritesTitle: boolean = true;
  @StorageProp(HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY)
  private storedShowRecentlyClosedTitle: boolean = true;
  @StorageProp(HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY)
  private storedShowSettingsButton: boolean = true;
  @Prop showShortcuts: boolean = true;
  @Prop recentlyClosedExpanded: boolean = true;
  @Prop presentation: HomeContentSectionsPresentationState =
    createDefaultHomeContentSectionsPresentationState();
  @Prop theme: HomeContentThemePresentationState = createDefaultHomeContentThemePresentationState();
  @Link contextMenuShortcutId: string;
  @State
  private shortcutDragActive: boolean = false;
  @State
  private favoritesExpanded: boolean = true;

  onAction: (action: BrowserTabHomeContentAction) => void = (_action: BrowserTabHomeContentAction) => {};

  build() {
    Scroll(this.homeContentScroller) {
      Column({ space: this.presentation.sectionVerticalGap }) {
        if (this.showShortcuts) {
          HomeFavoritesSection({
            expanded: this.favoritesExpanded,
            showTitle: this.storedShowFavoritesTitle,
            minimumWidth: this.resolveSectionRailWidth(),
            alignPartialRowsToStart: this.presentation.useSharedSectionWidth,
            shortcuts: this.presentation.shortcuts,
            theme: this.theme,
            contextMenuShortcutId: $contextMenuShortcutId,
            shortcutDragActive: $shortcutDragActive,
            onToggle: () => {
              animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
                this.favoritesExpanded = !this.favoritesExpanded;
              });
            },
            onShortcutAction: (action: HomeShortcutUserAction) => {
              this.onAction({ type: 'shortcut', shortcutAction: action });
            },
            onOpenAddEntry: () => {
              this.onAction({ type: 'open_shortcut_picker' });
            },
            onOpenHomeSettings: () => {
              this.onAction({ type: 'open_home_settings' });
            }
          })
        }
        if (this.presentation.showRecentlyClosed) {
          HomeRecentlyClosedSection({
            expanded: this.recentlyClosedExpanded,
            showTitle: this.storedShowRecentlyClosedTitle,
            contentWidth: this.resolveRecentlyClosedContentWidth(),
            minimumWidth: this.resolveSectionRailWidth(),
            alignPartialRowsToStart: this.presentation.useSharedSectionWidth,
            adaptColumnsToContentWidth: this.presentation.useSharedSectionWidth,
            recentlyClosed: this.presentation.recentlyClosed,
            displayLimit: this.presentation.recentlyClosed.limit,
            theme: this.theme,
            onAction: (action: BrowserRecentlyClosedUserAction) => {
              this.onAction({ type: 'recently_closed', recentlyClosedAction: action });
            },
            onRestoreRecord: (recordId: string) => {
              this.onAction({ type: 'restore_recently_closed', recordId: recordId });
            },
            onOpenHomeSettings: () => {
              this.onAction({ type: 'open_home_settings' });
            }
          })
        }
        if (this.storedShowSettingsButton) {
          HomeSettingsActionRow({
            contentWidth: this.resolveSettingsRowWidth(),
            onOpenSettings: () => {
              this.onAction({ type: 'open_home_settings' });
            }
          })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(this.presentation.centerContentVertically ? FlexAlign.Center : FlexAlign.Start)
      .padding({
        left: this.presentation.horizontalPadding,
        right: this.presentation.horizontalPadding,
        top: this.presentation.contentTopPadding,
        bottom: this.presentation.bottomSpacerHeight
      })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .scrollBar(BarState.Off)
    .enableScrollInteraction(!this.shortcutDragActive)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onDidScroll((_scrollDelta: number, _scrollState: ScrollState) => {
      this.onAction({
        type: 'scroll',
        scrollSource: 'system',
        scrollOffsetY: this.homeContentScroller.currentOffset().yOffset,
        scrollAtEnd: this.homeContentScroller.isAtEnd()
      });
    })
    .onScrollStop(() => {
      this.onAction({ type: 'scroll_stop', scrollSource: 'system' });
    })
  }

  private resolveFavoritesSectionWidth(): number {
    const shortcuts = this.presentation.shortcuts;
    const itemCount = shortcuts.shortcuts.length + (shortcuts.showAddEntry ? 1 : 0);
    const gridWidth = Math.max(1, shortcuts.gridWidth);
    const occupiedContentWidth = this.homeShortcutViewModel.getOccupiedGridContentWidth(
      itemCount,
      gridWidth,
      HOME_SECTION_CONTENT_INSET,
      shortcuts.metrics
    );
    return Math.min(gridWidth, occupiedContentWidth + HOME_SECTION_CONTENT_INSET * 2);
  }

  private resolveSectionRailWidth(): number {
    const favoritesWidth = this.resolveFavoritesSectionWidth();
    if (!this.presentation.useSharedSectionWidth) {
      return favoritesWidth;
    }
    return Math.max(1, this.presentation.shortcuts.gridWidth);
  }

  private resolveRecentlyClosedContentWidth(): number {
    if (this.presentation.useSharedSectionWidth) {
      return this.resolveSectionRailWidth();
    }
    return Math.max(1, this.presentation.shortcuts.gridWidth);
  }

  private resolveSettingsRowWidth(): number {
    if (this.presentation.useSharedSectionWidth) {
      return this.resolveSectionRailWidth();
    }
    return Math.max(1, this.presentation.shortcuts.gridWidth);
  }
}
