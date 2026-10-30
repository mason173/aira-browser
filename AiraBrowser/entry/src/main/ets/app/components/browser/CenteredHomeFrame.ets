import { util } from '@kit.ArkTS';
import { HomeShortcutDragViewport } from '../../../features/newtab/HomeShortcutDragGeometry';
import { ExternalAppSearchTargetId, SearchSuggestion } from '../../../common/models/BrowserModels';
import {
  createDefaultHomeContentSectionsPresentationState,
  createDefaultHomeContentThemePresentationState,
  HomeContentSectionsPresentationState,
  HomeContentThemePresentationState
} from '../../../core/browser/HomeContentPresentationState';
import { BrowserTabHomeContentAction } from '../../../core/browser/BrowserTabHomeCoordinator';
import { HomeShortcutUserAction } from '../../../features/newtab/HomeShortcutTypes';
import { HomeShortcutViewModel } from '../../../features/newtab/HomeShortcutViewModel';
import { resolveHomeSectionRailWidth } from '../../../features/newtab/HomeFrameSectionWidth';
import {
  HOME_LOGO_SCALE_DEFAULT_RATIO,
  resolveHomeLogoHeightVp
} from '../../../core/settings/HomeLogoSettingsPolicy';
import { HOME_PAGE_PRESENTATION_HOME_LOGO_SCALE_RATIO_KEY } from
  '../../../common/constants/HomePagePresentationStorageKeys';
import {
  CenteredHomeFrame as WordmarkHomeFrameMetrics,
  CENTERED_HOME_ICON_CORNER_RADIUS_RATIO,
  CENTERED_HOME_WORDMARK_HEIGHT,
  resolveCenteredHomeFrame,
  resolveMeasuredCenteredSurfaceHeight,
  shouldCenterCenteredHomePartialRows
} from '../../../features/newtab/CenteredHomeShortcutLayoutPolicy';
import { HomeFavoritesSection } from './HomeFavoritesSection';
import { WordmarkHomeHeaderBlock } from './WordmarkHomeHeaderBlock';

/**
 * 简约主页. Its scroller and measured height belong only to this component.
 * Switching to 经典 or 极简 destroys it, so those frames cannot inherit this offset.
 */
@Component
export struct CenteredHomePageFrame {
  private scroller: Scroller = new Scroller();
  private scrollNodeId: string = `home-scroll-${util.generateRandomUUID()}`;
  private shortcutViewModel: HomeShortcutViewModel = new HomeShortcutViewModel();
  @StorageProp(HOME_PAGE_PRESENTATION_HOME_LOGO_SCALE_RATIO_KEY)
  private storedLogoScaleRatio: number = HOME_LOGO_SCALE_DEFAULT_RATIO;
  @Prop showShortcuts: boolean = true;
  @Prop largeScreenShell: boolean = false;
  @Prop presentation: HomeContentSectionsPresentationState =
    createDefaultHomeContentSectionsPresentationState();
  @Prop theme: HomeContentThemePresentationState = createDefaultHomeContentThemePresentationState();
  @Prop searchPresented: boolean = false;
  @Prop searchGeometryEnabled: boolean = true;
  @Prop inlineSearch: boolean = false;
  @Prop inlineSearchActive: boolean = false;
  @Prop searchSuggestions: SearchSuggestion[] = [];
  @Prop searchDismissVersion: number = 0;
  @Prop viewportHeight: number = 0;
  @Prop topSafeInset: number = 0;
  @Prop bottomReserve: number = 0;
  @Link contextMenuShortcutId: string;
  @State private shortcutDragActive: boolean = false;
  @State private surfaceHeight: number = 0;

  onAction: (action: BrowserTabHomeContentAction) => void = (_action: BrowserTabHomeContentAction) => {};
  onOpenSearch: () => void = () => {};
  onScan: () => void = () => {};
  onInlineSearchSession: (active: boolean, query: string) => void =
    (_active: boolean, _query: string) => {};
  onSubmitSearch: (query: string) => void = (_query: string) => {};
  onOpenSearchSuggestion: (suggestion: SearchSuggestion) => void =
    (_suggestion: SearchSuggestion) => {};
  onDeleteSearchSuggestion: (suggestion: SearchSuggestion) => void =
    (_suggestion: SearchSuggestion) => {};
  onClearSearchSuggestions: () => void = () => {};
  onExternalSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string) => {};
  onDismissInlineSearch: () => void = () => {};

  aboutToAppear(): void {
    this.contextMenuShortcutId = '';
  }

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.resolveFrame().headerTop)

      this.buildHeader()

      Stack() {
        if (this.showShortcuts) {
          Scroll(this.scroller) {
            Column({ space: this.presentation.sectionVerticalGap }) {
              HomeFavoritesSection({
                expanded: true,
                showTitle: false,
                iconCornerRadiusRatio: CENTERED_HOME_ICON_CORNER_RADIUS_RATIO,
                minimumWidth: resolveHomeSectionRailWidth(this.presentation, this.shortcutViewModel),
                alignPartialRowsToStart: false,
                centerPartialRows: shouldCenterCenteredHomePartialRows(this.largeScreenShell),
                showPinnedSettingsEntry: false,
                shortcuts: this.presentation.shortcuts,
                theme: this.theme,
                contextMenuShortcutId: $contextMenuShortcutId,
                shortcutDragActive: $shortcutDragActive,
            getDragViewport: () => this.dragViewport(),
            onDragScroll: (delta: number) => { this.scroller.scrollBy(0, delta); },
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
            .width('100%')
            .constraintSize({ minHeight: '100%' })
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Start)
            .padding({
              left: this.presentation.horizontalPadding,
              right: this.presentation.horizontalPadding,
              top: 4,
              bottom: 12
            })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart)
          .clip(true)
          .scrollBar(BarState.Off)
          .id(this.scrollNodeId)
    .enableScrollInteraction(!this.shortcutDragActive && !this.inlineSearchActive)
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

        if (this.inlineSearch && this.inlineSearchActive) {
          this.buildSearchDismissLayer()
        }
      }
      .layoutWeight(1)
      .width('100%')

      Column()
        .width('100%')
        .height(Math.max(0, this.bottomReserve))
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateSurfaceHeight(newArea);
    })
  }

  @Builder
  private buildHeader() {
    WordmarkHomeHeaderBlock({
      theme: this.theme,
      horizontalPadding: this.presentation.horizontalPadding,
      searchPresented: this.searchPresented,
      searchGeometryEnabled: this.searchGeometryEnabled,
      inlineSearch: this.inlineSearch,
      inlineSearchActive: this.inlineSearchActive,
      searchSuggestions: this.searchSuggestions,
      searchViewportHeight: this.viewportHeight,
      searchPopupReservedTop: this.topSafeInset,
      searchDismissVersion: this.searchDismissVersion,
      showScanButton: true,
      softenSearchBorder: false,
      searchSideInset: 0,
      wordmarkOpensSettings: true,
      onAction: (action: BrowserTabHomeContentAction) => {
        this.onAction(action);
      },
      onOpenSearch: () => {
        this.onOpenSearch();
      },
      onScan: () => {
        this.onScan();
      },
      onInlineSearchSession: (active: boolean, query: string): void => {
        this.onInlineSearchSession(active, query);
      },
      onSubmitSearch: (query: string): void => {
        this.onSubmitSearch(query);
      },
      onOpenSearchSuggestion: (suggestion: SearchSuggestion): void => {
        this.onOpenSearchSuggestion(suggestion);
      },
      onDeleteSearchSuggestion: (suggestion: SearchSuggestion): void => {
        this.onDeleteSearchSuggestion(suggestion);
      },
      onClearSearchSuggestions: (): void => {
        this.onClearSearchSuggestions();
      },
      onExternalSearch: (targetId: ExternalAppSearchTargetId, query: string): void => {
        this.onExternalSearch(targetId, query);
      }
    })
  }

  @Builder
  private buildSearchDismissLayer() {
    Column()
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Default)
      .onClick(() => {
        this.onDismissInlineSearch();
      })
  }

  private resolveFrame(): WordmarkHomeFrameMetrics {
    return resolveCenteredHomeFrame({
      viewportHeight: resolveMeasuredCenteredSurfaceHeight(this.surfaceHeight, this.viewportHeight),
      topSafeInset: this.topSafeInset,
      bottomChromeReserve: Math.max(0, this.bottomReserve),
      logoHeightVp: resolveHomeLogoHeightVp(CENTERED_HOME_WORDMARK_HEIGHT, this.storedLogoScaleRatio)
    });
  }

  private updateSurfaceHeight(area: Area): void {
    const height = parseAreaLength(area.height);
    // Parent and child area callbacks have no fixed order during fullscreen rotation.
    // Keep the raw measurement; resolveFrame clamps it against the latest viewport.
    if (height > 0 && height !== this.surfaceHeight) {
      this.surfaceHeight = height;
    }
  }
  private dragViewport(): HomeShortcutDragViewport | undefined {
    try {
      const rect = this.getUIContext().getComponentUtils().getRectangleById(this.scrollNodeId);
      return { x: this.getUIContext().px2vp(rect.windowOffset.x), y: this.getUIContext().px2vp(rect.windowOffset.y),
        width: this.getUIContext().px2vp(rect.size.width), height: this.getUIContext().px2vp(rect.size.height) };
    } catch (_error) { return undefined; }
  }
}

function parseAreaLength(value: Length): number {
  const parsed = Number(`${value}`.replace('vp', '').replace('px', '').trim());
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;


}
