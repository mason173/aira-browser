import {
  createDefaultHomeContentSectionsPresentationState,
  createDefaultHomeContentThemePresentationState,
  HomeContentSectionsPresentationState,
  HomeContentThemePresentationState
} from '../../../core/browser/HomeContentPresentationState';
import { BrowserTabHomeContentAction } from '../../../core/browser/BrowserTabHomeCoordinator';
import { BrowserRecentlyClosedUserAction } from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { HomeShortcutUserAction } from '../../../features/newtab/HomeShortcutTypes';
import { HomeShortcutViewModel } from '../../../features/newtab/HomeShortcutViewModel';
import {
  resolveHomeFullGridWidth,
  resolveHomeSectionRailWidth
} from '../../../features/newtab/HomeFrameSectionWidth';
import {
  HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY
} from '../../../common/constants/HomePagePresentationStorageKeys';
import { HomeFavoritesSection } from './HomeFavoritesSection';
import { HomeRecentlyClosedSection } from './HomeRecentlyClosedSection';
import { HomeSettingsActionRow } from './HomeSettingsActionRow';

/**
 * 经典主页. Scroll, expanded sections, and drag state live here and die with this component.
 * 简约 and 极简 never see them.
 *
 * The favorites section spans the whole grid and packs its tiles from the leading edge, like the
 * recently-closed section and the settings row below it. A block that shrank to its own content
 * would float in the middle of the page: an empty grid would carry its 收藏 header to the centre
 * and leave the add tile alone there, and a partial row would sit between two empty lanes. The
 * centered homepage keeps that outward-from-the-middle look; this frame does not.
 */
@Component
export struct ClassicHomeFrame {
  private scroller: Scroller = new Scroller();
  private shortcutViewModel: HomeShortcutViewModel = new HomeShortcutViewModel();
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
  @State private shortcutDragActive: boolean = false;
  @State private favoritesExpanded: boolean = true;

  onAction: (action: BrowserTabHomeContentAction) => void = (_action: BrowserTabHomeContentAction) => {};

  aboutToAppear(): void {
    this.contextMenuShortcutId = '';
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: this.presentation.sectionVerticalGap }) {
        if (this.showShortcuts) {
          HomeFavoritesSection({
            expanded: this.favoritesExpanded,
            showTitle: this.storedShowFavoritesTitle,
            iconCornerRadiusRatio: -1,
            minimumWidth: resolveHomeFullGridWidth(this.presentation),
            alignPartialRowsToStart: true,
            centerPartialRows: false,
            showPinnedSettingsEntry: false,
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
            minimumWidth: resolveHomeSectionRailWidth(this.presentation, this.shortcutViewModel),
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
        scrollOffsetY: this.scroller.currentOffset().yOffset,
        scrollAtEnd: this.scroller.isAtEnd()
      });
    })
    .onScrollStop(() => {
      this.onAction({ type: 'scroll_stop', scrollSource: 'system' });
    })
  }

  private resolveRecentlyClosedContentWidth(): number {
    if (this.presentation.useSharedSectionWidth) {
      return resolveHomeSectionRailWidth(this.presentation, this.shortcutViewModel);
    }
    return resolveHomeFullGridWidth(this.presentation);
  }

  private resolveSettingsRowWidth(): number {
    if (this.presentation.useSharedSectionWidth) {
      return resolveHomeSectionRailWidth(this.presentation, this.shortcutViewModel);
    }
    return resolveHomeFullGridWidth(this.presentation);
  }
}
