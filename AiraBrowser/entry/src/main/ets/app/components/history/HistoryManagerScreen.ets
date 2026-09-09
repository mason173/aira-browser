import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import router from '@ohos.router';
import buffer from '@ohos.buffer';
import vibrator from '@ohos.vibrator';
import {
  BookmarkCreateNodeCommand,
  BookmarkNode,
  BrowserDataBoundaryInput,
  HistoryImportResult,
  HistorySiteAggregate,
  HistoryVisit
} from '../../../common/models/BrowserModels';
import { BrowserAppUrlOpenIntent } from '../../../core/browser/BrowserAppUrlOpenCoordinator';
import { BookmarksFeature } from '../../../features/bookmarks/BookmarksFeature';
import { HistoryFeature, HistoryManagementBoundary } from '../../../features/history/HistoryFeature';
import {
  BookmarkManagementBoundary,
  BookmarkManagementFeature
} from '../../../features/bookmarks/BookmarkManagementFeature';
import {
  HistoryDetailRow,
  HistoryDisplayVisit,
  HistorySiteGroup,
  HistoryViewMode,
  HistoryViewModel,
  HistoryViewState
} from '../../../features/history/HistoryViewModel';
import {
  HistoryManagerScreenController,
  HistoryTimelineDeletionCompletion,
  HistoryTimelineDeletionTransaction,
  HistoryTimelineVisibleContent
} from '../../../features/history/HistoryManagerScreenController';
import { DeferredEnterWork } from '../../../common/utils/DeferredEnterWork';
import {
  sharedBrowserDatabase,
  sharedBookmarkFolderSelectionPreparationCoordinator,
  sharedBookmarkRepository,
  sharedHistoryRepository,
  sharedPreferencesRepository,
  sharedRecentlyClosedTabRepository,
  sharedShortcutRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  requestOpenBrowserUrlWithRouteParams
} from '../../../core/navigation/BrowserNativeNavigationRequestCenter';
import { BROWSER_SHELL_ROUTE } from '../../router/AppRoutes';
import { AppEmptyState } from '../common/AppEmptyState';
import {
  SiteIconListPresenter,
  SiteIconListRenderState,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { BookmarkMutationService } from '../../../services/bookmarks/BookmarkMutationService';
import { BookmarkFolderOptionView } from '../../../core/browser/BookmarkFolderSelectionViewModel';
import {
  HomeShortcutToggleResult,
  HomeShortcutToggleService
} from '../../../services/shortcuts/HomeShortcutToggleService';
import { WebPageShareService } from '../../../services/share/WebPageShareService';
import { HistoryManagerHeader } from './HistoryManagerHeader';
import { HistoryManagerSearchHeader } from './HistoryManagerSearchHeader';
import { HistoryTimelineList } from './HistoryTimelineList';
import { HistoryTimelineDataSource, HistoryTimelineIconTarget } from '../../../features/history/HistoryTimelineDataSource';
import { HistorySiteIconTarget, HistorySiteListDataSource } from '../../../features/history/HistorySiteListDataSource';
import { FloatingSelectionToolbar } from '../common/FloatingSelectionToolbar';
import { HistorySiteList } from './HistorySiteList';
import { HistoryVisitDetailsSheet } from './HistoryVisitDetailsSheet';
import { HistoryBookmarkFolderSelectionOverlay } from './HistoryBookmarkFolderSelectionOverlay';
import { BookmarkMoveFolderSelectionResult } from '../bookmarks/BookmarkMoveFolderSelectionSheet';
import { BrowserPrivateBoundaryNavigationService } from '../../../core/browser/BrowserPrivateBoundaryNavigationService';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import {
  ManagementHdsMenuAction,
  ManagementHdsScaffold,
  resolveManagementImmersiveTitleBottomInset
} from '../common/ManagementHdsScaffold';
import { BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY } from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';
import {
  BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS,
  BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS
} from '../browser/BrowserModalBottomSheet';

const HISTORY_CONTEXT_MENU_DISMISS_DELAY_MS: number = 240;
const HISTORY_SELECTION_MENU_PANEL_WIDTH: number = 224;
const HISTORY_SELECTION_MENU_MIN_PANEL_WIDTH: number = 204;
const HISTORY_SELECTION_MENU_SIDE_MARGIN: number = 14;
const HISTORY_SELECTION_MENU_TOP_MARGIN: number = 86;
const HISTORY_SELECTION_MENU_BOTTOM_MARGIN: number = 96;
const HISTORY_SELECTION_MENU_PANEL_RADIUS: number = 24;
const HISTORY_SELECTION_MENU_ROW_HEIGHT: number = 48;
const HISTORY_SELECTION_MENU_ICON_SIZE: number = 21;
const HISTORY_SELECTION_MENU_TEXT_SIZE: number = 15;
const HISTORY_SELECTION_MENU_DISABLED_OPACITY: number = 0.42;
const HISTORY_SELECTION_MENU_CONTENT_INSET: number = 18;
const HISTORY_SELECTION_MENU_VERTICAL_PADDING: number = 8;
const HISTORY_SELECTION_MENU_ENTER_OFFSET_Y: number = 18;
const HISTORY_SELECTION_MENU_ITEM_ENTER_OFFSET_Y: number = 12;
const HISTORY_SELECTION_MENU_EXIT_DELAY_MS: number = 180;
const HISTORY_VISIBLE_ICON_RESOLVE_DELAY_MS: number = 90;
const HISTORY_SELECTION_TOOLBAR_FLOAT_BOTTOM: number = 36;
const HISTORY_INITIAL_RENDER_LIMIT: number = 40;
const HISTORY_RENDER_INCREMENT: number = 40;
const HISTORY_RENDER_PREFETCH_REMAINING_ROWS: number = 8;
const HISTORY_IMMERSIVE_TITLE_TO_HEADER_GAP: number = 12;
const HISTORY_IMMERSIVE_HEADER_HEIGHT: number = 44;
const HISTORY_IMMERSIVE_HEADER_TO_CONTENT_GAP: number = 4;
const HISTORY_IMMERSIVE_SEARCH_TOP_INSET: number = 8;
const HISTORY_IMMERSIVE_SEARCH_HEADER_HEIGHT: number = 64;
const HISTORY_IMMERSIVE_SEARCH_TO_CONTENT_GAP: number = 8;
const HISTORY_IMMERSIVE_TOP_BLUR_RADIUS: number = 20;

interface HistoryIconStateTarget {
  id: string;
  url: string;
  domain?: string;
}

interface HistorySelectionMoreAction {
  airaIconId: AiraRenderableIconId;
  title: string;
  action: () => void;
  enabled: boolean;
}

interface HistoryOverlayMenuState {
  title: string;
  message: string;
  actions: HistorySelectionMoreAction[];
  alignToTop: boolean;
  anchorRight: number;
  topMargin: number;
  bottomMargin: number;
}

@Component
export struct HistoryManagerScreen {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  historyFeature: HistoryFeature =
    new HistoryFeature(sharedHistoryRepository, sharedPreferencesRepository, sharedRecentlyClosedTabRepository);
  controller: HistoryManagerScreenController = new HistoryManagerScreenController(this.historyFeature);
  private bookmarkManagementFeature: BookmarkManagementFeature = new BookmarkManagementFeature(
    new BookmarksFeature(sharedBookmarkRepository),
    new BookmarkMutationService(sharedBookmarkRepository)
  );
  private homeShortcutToggleService: HomeShortcutToggleService = new HomeShortcutToggleService(sharedShortcutRepository);
  private webPageShareService: WebPageShareService = new WebPageShareService();
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  private deferredEnterWork: DeferredEnterWork = new DeferredEnterWork();
  private historyViewModel: HistoryViewModel = new HistoryViewModel();
  private historyTimelineDataSource: HistoryTimelineDataSource = new HistoryTimelineDataSource();
  private historySiteListDataSource: HistorySiteListDataSource = new HistorySiteListDataSource();
  private historySiteScroller: Scroller = new Scroller();
  private privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService =
    new BrowserPrivateBoundaryNavigationService();
  @State rawVisits: HistoryVisit[] = [];
  @State visits: HistoryDisplayVisit[] = [];
  @State sites: HistorySiteGroup[] = [];
  @State searchQuery: string = '';
  @State isSearchMode: boolean = false;
  @State searchReturnMode: HistoryViewMode = 'timeline';
  @State viewMode: HistoryViewMode = 'timeline';
  @State isTimelineLoading: boolean = false;
  @State drilldownReturnQuery: string = '';
  @State drilldownReturnMode: HistoryViewMode = 'timeline';
  @State drilldownHost: string = '';
  @State isSelectionMode: boolean = false;
  @State selectedVisitIds: string[] = [];
  @State selectedSiteKeys: string[] = [];
  @State pressedVisitId: string = '';
  @State contextMenuVisitId: string = '';
  @State iconStates: SiteIconListRenderState[] = [];
  @State bookmarkedVisitIds: string[] = [];
  @State homeShortcutVisitIds: string[] = [];
  @State isTransferBusy: boolean = false;
  @State visitDetailRows: HistoryDetailRow[] = [];
  @State visitDetailUrl: string = '';
  @State visitDetailsSheetVisible: boolean = false;
  @State selectionMenuVisible: boolean = false;
  @State selectionMenuHostWidth: number = 0;
  @State selectionMenuHostHeight: number = 0;
  @State bookmarkFolderSelectionVisible: boolean = false;
  @State bookmarkFolderSelectionSheetVisible: boolean = false;
  @State bookmarkFolderSelectionPreparing: boolean = false;
  @State private bookmarkFolderSelectionOptions: BookmarkFolderOptionView[] = [];
  @State overlayMenuState: HistoryOverlayMenuState = {
    title: '',
    message: '',
    actions: [],
    alignToTop: false,
    anchorRight: HISTORY_SELECTION_MENU_SIDE_MARGIN,
    topMargin: HISTORY_SELECTION_MENU_TOP_MARGIN,
    bottomMargin: HISTORY_SELECTION_MENU_BOTTOM_MARGIN
  };
  private isApplyingRetentionPolicy: boolean = false;
  private isSeedingStressHistory: boolean = false;
  private handledStressHistorySeedCount: number = 0;
  private siteReloadSequence: number = 0;
  private pendingBookmarkVisits: HistoryDisplayVisit[] = [];
  private bookmarkFolderSelectionOverlayGeneration: number = 0;
  private selectionMenuRevealSequence: number = 0;
  private siteVisibleStartIndex: number = 0;
  private siteVisibleEndIndex: number = 20;
  private visibleIconResolveTimer: number = -1;
  @State isSessionEphemeral: boolean = false;
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private topSafeInsetVp: number = 0;
  private hasLoadedAllSites: boolean = false;
  private isLoadingMoreSites: boolean = false;

  aboutToAppear(): void {
    this.controller.setTimelineLoadingListener((loading: boolean): void => {
      this.isTimelineLoading = loading;
    });
    this.controller.setBackHandler((): boolean => {
      if (this.bookmarkFolderSelectionVisible) {
        this.dismissBookmarkFolderSelection();
        return true;
      }
      if (this.controller.closeTimelineSwipeActions()) {
        return true;
      }
      if (this.isSelectionMode) {
        this.exitSelectionMode();
        return true;
      }
      if (this.isSearchMode) {
        this.exitSearchMode();
        return true;
      }
      if (this.canNavigateBack()) {
        this.navigateBack();
        return true;
      }
      return false;
    });
    this.isSessionEphemeral = this.privateBoundaryNavigationService.isSessionEphemeralRoute(
      router.getParams() as Record<string, string | undefined> | undefined
    );
    const managementBoundary = this.buildHistoryManagementBoundary();
    this.controller.setManagementBoundary(managementBoundary);
    this.bookmarkManagementFeature.configure(
      new BookmarkManagementBoundary(managementBoundary.dataScope, managementBoundary.privacyMode),
      'regular'
    );
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildVisibleIconTargets(),
      (result: SiteIconListResolvedIcon) => {
        this.applyResolvedSiteIcon(result);
      }
    );
    if (!this.seedStressHistoryIfRequested()) {
      this.deferredEnterWork.schedule((): void => {
        this.loadVisitsProgressively();
      });
    }
  }

  aboutToDisappear(): void {
    this.deferredEnterWork.cancel();
    this.controller.clearBackHandler();
    this.cancelVisibleIconResolve();
    this.siteIconListPresenter.dispose();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        ManagementHdsScaffold({
          title: this.resolveTitle(),
          backIconKind: this.resolveBackIconKind(),
          pageBackground: this.storedPageBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          dividerColor: this.storedDividerColor,
          showPrivateIndicator: this.isSessionEphemeral,
          showTitleBar: !this.isSearchMode,
          useTopSafeInset: !this.isSearchMode,
          menuActions: this.buildHeaderMenuActions(),
          titleBarMenuMaxCount: 2,
          immersiveContent: true,
          topSafeInsetVpOverride: this.topSafeInsetVp,
          scrollers: [this.controller.getTimelineScroller(), this.historySiteScroller],
          onBack: () => {
            this.handleLeadingClick();
          }
        }) {
          Stack({ alignContent: Alignment.TopStart }) {
            this.buildHistoryList()

            Column() {
              this.buildHeader()
            }
            .width('100%')
            .position({ x: 0, y: this.resolveFloatingHeaderTopInset() })
            .zIndex(2)
          }
          .width('100%')
          .height('100%')
          .backgroundColor(this.storedPageBackgroundColor)
        }
      }
      .width('100%')
      .height('100%')

      this.buildSelectionToolbarOverlay()
      this.buildOverlayMenu()
      this.buildBookmarkFolderSelectionOverlay()
    }
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const nextWidth = Number(newValue.width);
      const nextHeight = Number(newValue.height);
      this.selectionMenuHostWidth = Number.isFinite(nextWidth) ? nextWidth : 360;
      this.selectionMenuHostHeight = Number.isFinite(nextHeight) ? nextHeight : 720;
    })
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
    .bindSheet($$this.visitDetailsSheetVisible, this.buildVisitDetailsSheet(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.visitDetailsSheetVisible = false;
      }
    })
  }

  @Builder
  private buildVisitDetailsSheet() {
    HistoryVisitDetailsSheet({
      rows: this.visitDetailRows,
      copyLink: () => {
        this.copyTextToClipboard(this.visitDetailUrl, '当前没有可复制的链接。', '链接已复制。');
      },
      onClose: () => {
        this.visitDetailsSheetVisible = false;
      }
    })
  }

  @Builder
  private buildHeader() {
    if (this.isSearchMode) {
      HistoryManagerSearchHeader({
        query: this.searchQuery,
        onQueryChange: (query: string) => {
          this.updateSearchQuery(query);
        },
        onClose: () => {
          this.exitSearchMode();
        }
      })
    } else {
      HistoryManagerHeader({
        viewMode: this.viewMode,
        onChangeViewMode: (mode: HistoryViewMode) => {
          this.switchViewMode(mode);
        }
      })
    }
  }

  private resolveBackIconKind(): 'close' | 'back' {
    return 'back';
  }

  private buildHeaderMenuActions(): ManagementHdsMenuAction[] {
    if (this.isSelectionMode || this.isSearchMode) {
      return [];
    }
    const hasVisits = this.rawVisits.length > 0;
    const actions: ManagementHdsMenuAction[] = [
      {
        label: '搜索',
        icon: $r('sys.symbol.magnifyingglass'),
        action: () => {
          this.enterSearchMode();
        }
      },
      {
        label: '编辑',
        icon: $r('sys.symbol.checkmark_circle_fill'),
        enabled: hasVisits,
        action: () => {
          this.enterSelectionMode();
        }
      },
      {
        label: '按站点清理',
        icon: $r('sys.symbol.trash_fill'),
        enabled: hasVisits,
        action: () => {
          this.openSiteCleanupMode();
        }
      },
      {
        label: '导入历史',
        icon: $r('sys.symbol.arrow_down'),
        enabled: !this.isTransferBusy,
        action: () => {
          this.importHistoryBundle();
        }
      },
      {
        label: '导出历史',
        icon: $r('sys.symbol.arrow_up'),
        enabled: hasVisits && !this.isTransferBusy,
        action: () => {
          this.exportHistoryBundle();
        }
      }
    ];
    return actions;
  }

  @Builder
  private buildOverlayMenu() {
    if (this.overlayMenuState.actions.length > 0) {
      Stack({ alignContent: this.overlayMenuState.alignToTop ? Alignment.TopEnd : Alignment.BottomEnd }) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.browser_overlay_scrim'))
          .opacity(this.selectionMenuVisible ? 1 : 0)
          .animation({
            duration: 180,
            curve: Curve.EaseOut
          })
          .onClick(() => {
            this.requestCloseOverlayMenu();
          })

        Column() {
          Column({ space: 0 }) {
            if (this.overlayMenuState.title.length > 0) {
              Column({ space: 4 }) {
                Text(this.overlayMenuState.title)
                  .width('100%')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.storedPrimaryTextColor)
                if (this.overlayMenuState.message.length > 0) {
                  Text(this.overlayMenuState.message)
                    .width('100%')
                    .fontSize(12)
                    .fontColor(this.storedSecondaryTextColor)
                }
              }
              .width('100%')
              .padding({
                left: HISTORY_SELECTION_MENU_CONTENT_INSET,
                right: HISTORY_SELECTION_MENU_CONTENT_INSET,
                top: HISTORY_SELECTION_MENU_CONTENT_INSET,
                bottom: 10
              })
            }

            ForEach(this.overlayMenuState.actions, (item: HistorySelectionMoreAction, index: number) => {
              this.buildOverlayMenuItem(item, index)
            }, (item: HistorySelectionMoreAction) => item.title)
          }
          .width('100%')
          .padding({ top: HISTORY_SELECTION_MENU_VERTICAL_PADDING, bottom: HISTORY_SELECTION_MENU_VERTICAL_PADDING })
        }
        .width(this.resolveOverlayMenuWidth())
        .backgroundColor(this.storedFloatingSurfaceColor)
        .borderRadius(HISTORY_SELECTION_MENU_PANEL_RADIUS)
        .clip(true)
        .opacity(this.selectionMenuVisible ? 1 : 0)
        .translate({ y: this.selectionMenuVisible ? 0 : HISTORY_SELECTION_MENU_ENTER_OFFSET_Y })
        .animation({
          duration: 220,
          curve: Curve.EaseOut
        })
        .margin({
          right: this.overlayMenuState.anchorRight,
          top: this.overlayMenuState.alignToTop ? this.overlayMenuState.topMargin : 0,
          bottom: this.overlayMenuState.alignToTop ? 0 : this.overlayMenuState.bottomMargin
        })
      }
        .width('100%')
        .height('100%')
        .zIndex(80)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  private buildOverlayMenuItem(item: HistorySelectionMoreAction, index: number) {
    Button() {
      Row({ space: 6 }) {
        AiraIcon({
          airaIconId: item.airaIconId,
          iconSize: HISTORY_SELECTION_MENU_ICON_SIZE,
          iconColor: this.resolveOverlayMenuItemColor(item.enabled)
        })

        Text(item.title)
          .fontSize(HISTORY_SELECTION_MENU_TEXT_SIZE)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.resolveOverlayMenuItemColor(item.enabled))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(HISTORY_SELECTION_MENU_ROW_HEIGHT)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(HISTORY_SELECTION_MENU_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .padding({ left: HISTORY_SELECTION_MENU_CONTENT_INSET, right: HISTORY_SELECTION_MENU_CONTENT_INSET })
    .borderRadius(0)
    .stateEffect(item.enabled)
    .enabled(item.enabled)
    .opacity(this.selectionMenuVisible ? (item.enabled ? 1 : HISTORY_SELECTION_MENU_DISABLED_OPACITY) : 0)
    .translate({ y: this.selectionMenuVisible ? 0 : this.resolveOverlayMenuItemEnterOffset(index) })
    .animation({
      duration: 260,
      curve: Curve.EaseOut,
      delay: this.selectionMenuVisible ? this.resolveOverlayMenuItemEnterDelay(index) : 0
    })
    .onClick(() => {
      item.action();
    })
  }

  @Builder
  private buildHistoryList() {
    this.buildHistoryPage(this.viewMode)
    }

  @Builder
  private buildHistoryPage(mode: HistoryViewMode) {
    if (this.isSearchMode && this.searchQuery.trim().length === 0) {
      this.buildIdleSearchList()
    } else if (mode === 'timeline') {
      Stack({ alignContent: Alignment.Top }) {
        this.buildHistoryContent(mode)
        if (this.shouldShowHistoryEmptyState(mode)) {
          this.buildEmptyState(mode)
        }
      }
      .width('100%')
      .height('100%')
    } else if (!this.isViewModeEmpty(mode)) {
      this.buildHistoryContent(mode)
    } else {
      this.buildEmptyState(mode)
    }
  }

  @Builder
  private buildIdleSearchList() {
    List() {
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 4 })
    .contentStartOffset(this.resolveHistoryContentTopInset())
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildHistoryContent(mode: HistoryViewMode) {
    if (mode === 'sites') {
      HistorySiteList({
        dataSource: this.historySiteListDataSource,
        listScroller: this.historySiteScroller,
        icons: this.iconStates,
        selectedSiteKeys: this.selectedSiteKeys,
        isSelectionMode: this.isSelectionMode,
        contentStartOffset: this.resolveHistoryContentTopInset(),
        onOpenSite: (site: HistorySiteGroup) => {
          this.openSite(site);
        },
        onDeleteSite: (site: HistorySiteGroup) => {
          this.confirmDeleteSite(site);
        },
        onToggleSiteSelection: (siteKey: string) => {
          this.toggleSiteSelection(siteKey);
        },
        onSetSiteSelected: (siteKey: string, selected: boolean) => {
          this.setSiteSelected(siteKey, selected);
        },
        onIconLoadError: (
          target: SiteIconListTarget,
          currentUri: string,
          sourceRevision: number
        ) => {
          this.resolveHistoryPixelMapAfterUriFailure(target, currentUri, sourceRevision);
        },
        onScrollVisibleRange: (start: number, end: number) => {
          this.updateSiteVisibleRange(start, end);
        }
      })
    } else {
      HistoryTimelineList({
        dataSource: this.historyTimelineDataSource,
        listScroller: this.controller.getTimelineScroller(),
        icons: this.iconStates,
        bookmarkedVisitIds: this.bookmarkedVisitIds,
        homeShortcutVisitIds: this.homeShortcutVisitIds,
        selectedVisitIds: this.selectedVisitIds,
        pressedVisitId: this.pressedVisitId,
        contextMenuVisitId: this.contextMenuVisitId,
        isSelectionMode: this.isSelectionMode,
        allowMultiSelect: !this.isSearchMode,
        contentStartOffset: this.resolveHistoryContentTopInset(),
        onOpenVisit: (visit: HistoryDisplayVisit) => {
          this.openVisit(visit);
        },
        onOpenContextMenu: (visitId: string) => {
          this.openContextMenu(visitId);
        },
        onUpdatePressedVisit: (visitId: string, type: TouchType) => {
          this.updatePressedVisit(visitId, type);
        },
        onToggleVisitSelection: (visitId: string) => {
          this.toggleVisitSelection(visitId);
        },
        onSetVisitSelected: (visitId: string, selected: boolean) => {
          this.setVisitSelected(visitId, selected);
        },
        onContextAction: (visit: HistoryDisplayVisit, title: string) => {
          this.handleContextAction(visit, title);
        },
        onIconLoadError: (
          target: SiteIconListTarget,
          currentUri: string,
          sourceRevision: number
        ) => {
          this.resolveHistoryPixelMapAfterUriFailure(target, currentUri, sourceRevision);
        },
        onContextAppear: () => {
          this.performLongPressFeedback();
        },
        onContextDisappear: () => {
          this.contextMenuVisitId = '';
        },
        onScrollVisibleContentChange: (
          startGroupIndex: number,
          startItemIndex: number,
          endGroupIndex: number,
          endItemIndex: number
        ) => {
          this.updateTimelineVisibleContent(
            startGroupIndex,
            startItemIndex,
            endGroupIndex,
            endItemIndex
          );
        },
        onReachEnd: () => {
          this.loadNextTimelinePage();
        },
        onDeleteVisit: (visit: HistoryDisplayVisit) => {
          this.controller.closeTimelineSwipeActions();
          this.confirmDeleteVisit(visit);
        },
        onSwipeActionStateChange: (visitId: string, open: boolean) => {
          this.controller.setTimelineSwipeActionOpen(visitId, open);
        }
      })
    }
  }

  @Builder
  private buildEmptyState(mode: HistoryViewMode) {
    Column() {
      AppEmptyState({
        airaIconId: this.isSearchMode || this.searchQuery.trim().length > 0
          ? 'settings.search'
          : 'browser.shortcut.history',
        title: this.getEmptyTitle(mode),
        message: this.getEmptyMessage(mode),
        topPadding: 0,
        bottomPadding: 0
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private resolveFloatingHeaderTopInset(): number {
    if (this.isSearchMode) {
      return Math.max(0, Math.ceil(this.topSafeInsetVp)) + HISTORY_IMMERSIVE_SEARCH_TOP_INSET;
    }
    return resolveManagementImmersiveTitleBottomInset(this.topSafeInsetVp) +
      HISTORY_IMMERSIVE_TITLE_TO_HEADER_GAP;
  }

  private resolveHistoryContentTopInset(): number {
    if (this.isSearchMode) {
      return this.resolveFloatingHeaderTopInset() + HISTORY_IMMERSIVE_SEARCH_HEADER_HEIGHT +
        HISTORY_IMMERSIVE_SEARCH_TO_CONTENT_GAP;
    }
    return this.resolveFloatingHeaderTopInset() + HISTORY_IMMERSIVE_HEADER_HEIGHT +
      HISTORY_IMMERSIVE_HEADER_TO_CONTENT_GAP;
  }

  @Builder
  private buildSelectionToolbar() {
    FloatingSelectionToolbar({
      actions: [
        {
          airaIconId: 'browser.toolbar.selectAll',
          title: '全选',
          action: () => {
            this.selectAllVisibleVisits();
          }
        },
        {
          airaIconId: 'browser.tabs.delete',
          title: '删除',
          action: () => {
            this.confirmDeleteSelectedVisits();
          }
        },
        {
          airaIconId: 'browser.toolbar.more',
          title: '更多',
          action: () => {
            this.showSelectionMoreMenu();
          }
        }
      ]
    })
  }

  @Builder
  private buildSelectionToolbarOverlay() {
    if (this.isSelectionMode) {
      Stack({ alignContent: Alignment.Bottom }) {
        this.buildSelectionToolbar()
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: HISTORY_SELECTION_TOOLBAR_FLOAT_BOTTOM })
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(60)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  private buildBookmarkFolderSelectionOverlay() {
    HistoryBookmarkFolderSelectionOverlay({
      visible: this.bookmarkFolderSelectionVisible,
      sheetVisible: this.bookmarkFolderSelectionSheetVisible,
      options: this.bookmarkFolderSelectionOptions,
      isPreparing: this.bookmarkFolderSelectionPreparing,
      onDismiss: () => {
        this.dismissBookmarkFolderSelection();
      },
      onFolderOpened: (folderId: string) => {
        this.prepareBookmarkFolderSelectionFolderPreview(folderId);
      },
      onConfirm: (result: BookmarkMoveFolderSelectionResult) => {
        this.confirmSelectedBookmarkFolder(result);
      }
    })
  }

  private reloadVisits(): void {
    this.loadCurrentModeFirstPage();
  }

  private loadCurrentModeFirstPage(): void {
    if (this.shouldHoldEmptySearchResults()) {
      this.clearHistoryViewState();
      return;
    }
    if (this.viewMode === 'sites') {
      this.loadSiteFirstPage();
      return;
    }
    this.loadVisitsProgressively();
  }

  private loadVisitsProgressively(): void {
    this.siteReloadSequence += 1;
    this.isLoadingMoreSites = false;
    if (this.shouldHoldEmptySearchResults()) {
      this.clearHistoryViewState();
      return;
    }
    const query = this.searchQuery.trim();
    if (query.length > 0) {
      this.applyHistoryViewState();
    }
    this.controller.loadTimelineFirstPage(
      query,
      HISTORY_INITIAL_RENDER_LIMIT,
      (visits: HistoryVisit[]) => {
        this.applyLoadedVisits(visits, false);
      }
    );
  }

  private applyLoadedVisits(visits: HistoryVisit[], shouldApplyRetention: boolean): void {
    this.rawVisits = visits.slice();
    this.applyHistoryViewState();
    this.controller.scrollTimelineToStart();
    this.pruneSelectedVisits();
    this.refreshBookmarkMarkers(this.visits);
    this.refreshHomeShortcutMarkers(this.visits);
    this.scheduleVisibleIconResolve();
    if (shouldApplyRetention) {
      this.applyRetentionPolicyIfNeeded();
    }
  }

  private clearHistoryViewState(): void {
    this.controller.clearTimelineState();
    this.hasLoadedAllSites = false;
    this.isLoadingMoreSites = false;
    this.rawVisits = [];
    this.visits = [];
    this.sites = [];
    this.iconStates = [];
    this.bookmarkedVisitIds = [];
    this.homeShortcutVisitIds = [];
    this.siteVisibleStartIndex = 0;
    this.siteVisibleEndIndex = 0;
    this.historyTimelineDataSource.replaceGroups([]);
    this.historySiteListDataSource.replaceSites([]);
  }

  private applyHistoryViewState(): void {
    const state: HistoryViewState = this.historyViewModel.buildViewState(this.rawVisits, this.searchQuery, this.viewMode);
    this.visits = state.visits;
    this.sites = state.sites;
    this.historyTimelineDataSource.replaceGroups(state.groups);
    this.historySiteListDataSource.replaceSites(state.sites);
    this.pruneSelectedSites();
    this.scheduleVisibleIconResolve();
  }

  private refreshLoadedHistoryViewState(visits: HistoryVisit[]): number {
    this.rawVisits = visits.slice();
    this.applyHistoryViewState();
    this.refreshBookmarkMarkers(this.visits);
    this.refreshHomeShortcutMarkers(this.visits);
    return this.visits.length;
  }

  private loadNextTimelinePage(): void {
    this.controller.requestNextTimelinePages(
      HISTORY_RENDER_INCREMENT,
      this.visits.length,
      (visits: HistoryVisit[]): number => this.refreshLoadedHistoryViewState(visits)
    );
  }

  private loadSiteFirstPage(): void {
    this.controller.cancelTimelineRequests();
    const sequence = ++this.siteReloadSequence;
    const query = this.searchQuery.trim();
    this.hasLoadedAllSites = false;
    this.isLoadingMoreSites = false;
    this.historyFeature.refreshSitePageForManagement(
      query,
      0,
      HISTORY_INITIAL_RENDER_LIMIT,
      this.buildHistoryManagementBoundary()
    )
      .then((sites: HistorySiteAggregate[]) => {
        if (sequence !== this.siteReloadSequence || query !== this.searchQuery.trim()) {
          return;
        }
        this.applyLoadedSites(sites, sites.length < HISTORY_INITIAL_RENDER_LIMIT, false);
      })
      .catch((_error: Error) => {
      });
  }

  private applyLoadedSites(sites: HistorySiteAggregate[], hasLoadedAll: boolean, append: boolean): void {
    const siteGroups = this.historyViewModel.buildSiteGroupsFromAggregates(sites);
    this.sites = append ? this.mergeLoadedSites(siteGroups) : siteGroups;
    this.hasLoadedAllSites = hasLoadedAll;
    this.historySiteListDataSource.replaceSites(this.sites);
    this.siteVisibleStartIndex = 0;
    this.siteVisibleEndIndex = 20;
    this.pruneSelectedSites();
    this.scheduleVisibleIconResolve();
  }

  private mergeLoadedSites(nextSites: HistorySiteGroup[]): HistorySiteGroup[] {
    const sitesByHost = new Map<string, HistorySiteGroup>();
    this.sites.forEach((site: HistorySiteGroup) => {
      sitesByHost.set(site.host, site);
    });
    nextSites.forEach((site: HistorySiteGroup) => {
      sitesByHost.set(site.host, site);
    });
    return Array.from(sitesByHost.values())
      .sort((left: HistorySiteGroup, right: HistorySiteGroup) => right.latestVisitedAt - left.latestVisitedAt);
  }

  private requestMoreSiteRowsIfNeeded(): void {
    if (this.viewMode !== 'sites' || this.hasLoadedAllSites || this.isLoadingMoreSites) {
      return;
    }
    const remainingRows = this.sites.length - this.siteVisibleEndIndex;
    if (remainingRows >= HISTORY_RENDER_PREFETCH_REMAINING_ROWS) {
      return;
    }
    const sequence = this.siteReloadSequence;
    const query = this.searchQuery.trim();
    const offset = this.sites.length;
    this.isLoadingMoreSites = true;
    this.historyFeature.refreshSitePageForManagement(
      query,
      offset,
      HISTORY_RENDER_INCREMENT,
      this.buildHistoryManagementBoundary()
    )
      .then((sites: HistorySiteAggregate[]) => {
        if (sequence !== this.siteReloadSequence || query !== this.searchQuery.trim()) {
          return;
        }
        this.applyLoadedSites(sites, sites.length < HISTORY_RENDER_INCREMENT, true);
      })
      .catch((_error: Error) => {
      })
      .finally(() => {
        if (sequence === this.siteReloadSequence) {
          this.isLoadingMoreSites = false;
        }
      });
  }

  private resolveTitle(): string {
    const regularProfileLabel = this.isSessionEphemeral ? '常规历史 · ' : '';
    if (this.isSelectionMode) {
      const selectedCount = this.viewMode === 'sites' ? this.selectedSiteKeys.length : this.selectedVisitIds.length;
      return `${regularProfileLabel}已选 ${selectedCount} 项`;
    }
    const filtered = this.searchQuery.trim().length > 0;
    if (this.viewMode === 'sites') {
      return `${regularProfileLabel}${filtered ? `站点 · ${this.sites.length}` : '按站点'}`;
    }
    return `${regularProfileLabel}${filtered ? `搜索结果 · ${this.visits.length}` : '历史记录'}`;
  }

  private handleLeadingClick(): void {
    if (this.isSelectionMode) {
      this.exitSelectionMode();
      return;
    }
    if (this.isSearchMode) {
      this.exitSearchMode();
      return;
    }
    if (this.canNavigateBack()) {
      this.navigateBack();
      return;
    }
    router.back();
  }

  private handleContextAction(visit: HistoryDisplayVisit, title: string): void {
    if (title === '多选') {
      if (this.isSearchMode) {
        return;
      }
      this.runAfterContextMenuDismiss(() => {
        this.enterSelectionMode(visit.id);
      });
      return;
    }
    if (title === '添加书签') {
      if (this.isVisitBookmarked(visit.id)) {
        return;
      }
      this.runAfterContextMenuDismiss(() => {
        this.addVisitToBookmarks(visit);
      });
      return;
    }
    if (title === '取消书签') {
      this.runAfterContextMenuDismiss(() => {
        this.removeVisitFromBookmarks(visit);
      });
      return;
    }
    if (title === '添加到主页' || title === '从主页移除') {
      this.runAfterContextMenuDismiss(() => {
        this.toggleVisitHomeShortcut(visit);
      });
      return;
    }
    if (title === '分享') {
      this.runAfterContextMenuDismiss(() => {
        this.shareVisit(visit);
      });
      return;
    }
    if (title === '复制链接') {
      this.runAfterContextMenuDismiss(() => {
        this.copyVisitUrl(visit);
      });
      return;
    }
    if (title === '详情') {
      this.runAfterContextMenuDismiss(() => {
        this.showVisitDetails(visit);
      });
      return;
    }
    if (title === '打开') {
      this.runAfterContextMenuDismiss(() => {
        this.openVisit(visit);
      });
      return;
    }
    if (title === '新标签页打开') {
      this.runAfterContextMenuDismiss(() => {
        this.openVisitWithIntent(visit, 'new_tab');
      });
      return;
    }
    if (title === '后台打开') {
      this.runAfterContextMenuDismiss(() => {
        this.openVisitWithIntent(visit, 'background_tab');
      });
      return;
    }
    if (title === '删除该站点记录') {
      this.runAfterContextMenuDismiss(() => {
        this.confirmDeleteSiteForVisit(visit);
      });
      return;
    }
    if (title === '删除') {
      this.runAfterContextMenuDismiss(() => {
        this.confirmDeleteVisit(visit);
      });
    }
  }

  private runAfterContextMenuDismiss(action: () => void): void {
    this.contextMenuVisitId = '';
    setTimeout(action, HISTORY_CONTEXT_MENU_DISMISS_DELAY_MS);
  }

  private openVisit(visit: HistoryDisplayVisit): void {
    this.openVisitWithIntent(visit, 'current_tab');
  }

  private openVisitWithIntent(visit: HistoryDisplayVisit, intent: BrowserAppUrlOpenIntent): void {
    try {
      this.historyFeature.authorizeNavigationForManagement(this.buildHistoryManagementBoundary());
    } catch (error) {
      this.showDialog('无法打开', this.stringifyError(error as Error));
      return;
    }
    router.back({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(visit.url, intent, visit.title, 'history')
    });
  }

  private openSite(site: HistorySiteGroup): void {
    this.drilldownReturnQuery = this.searchQuery;
    this.drilldownReturnMode = this.viewMode;
    this.drilldownHost = site.host;
    this.searchQuery = site.host;
    this.viewMode = 'timeline';
    this.exitSelectionMode();
    this.loadVisitsProgressively();
  }

  private shouldHoldEmptySearchResults(): boolean {
    return this.isSearchMode && this.searchQuery.trim().length === 0;
  }

  private shouldShowHistoryEmptyState(mode: HistoryViewMode): boolean {
    if (this.shouldHoldEmptySearchResults()) {
      return false;
    }
    if (mode === 'timeline' && this.isTimelineLoading) {
      return false;
    }
    return this.isViewModeEmpty(mode);
  }

  private updateSearchQuery(query: string): void {
    this.searchQuery = query;
    this.clearDrilldownIfQueryChanged();
    this.loadCurrentModeFirstPage();
  }

  private enterSearchMode(): void {
    if (this.isSearchMode) {
      return;
    }
    this.exitSelectionMode();
    this.searchReturnMode = this.drilldownHost.length > 0 ? this.drilldownReturnMode : this.viewMode;
    this.clearDrilldownState();
    this.searchQuery = '';
    this.viewMode = 'timeline';
    this.clearHistoryViewState();
    this.isSearchMode = true;
  }

  private exitSearchMode(): void {
    if (!this.isSearchMode) {
      return;
    }
    this.isSearchMode = false;
    this.searchQuery = '';
    this.viewMode = this.searchReturnMode;
    this.exitSelectionMode();
    this.loadCurrentModeFirstPage();
  }

  private clearDrilldownIfQueryChanged(): void {
    if (this.drilldownHost.length === 0 || this.searchQuery === this.drilldownHost) {
      return;
    }
    this.clearDrilldownState();
  }

  private clearDrilldownState(): void {
    this.drilldownReturnQuery = '';
    this.drilldownReturnMode = 'timeline';
    this.drilldownHost = '';
  }

  private canNavigateBack(): boolean {
    return this.drilldownHost.length > 0;
  }

  private navigateBack(): void {
    if (!this.canNavigateBack()) {
      return;
    }
    const previousQuery = this.drilldownReturnQuery;
    const previousMode = this.drilldownReturnMode;
    this.clearDrilldownState();
    this.searchQuery = previousQuery;
    this.viewMode = previousMode;
    this.exitSelectionMode();
    this.loadCurrentModeFirstPage();
  }

  private addVisitToBookmarks(visit: HistoryDisplayVisit): void {
    if (this.bookmarkManagementFeature.hasBookmarkForUrl(visit.url)) {
      this.refreshBookmarkMarkers(this.visits);
      this.showDialog('已添加书签', '这条历史记录已经在书签里。');
      return;
    }
    this.openBookmarkFolderSelection([visit]);
  }

  private shareVisit(visit: HistoryDisplayVisit): void {
    try {
      this.historyFeature.authorizeShareForManagement(this.buildHistoryManagementBoundary());
    } catch (error) {
      this.showDialog('无法分享', this.stringifyError(error as Error));
      return;
    }
    this.webPageShareService.shareWebPage(this.getPickerContext(), {
      title: visit.title,
      url: visit.url
    }).catch((error: Error) => {
      this.showDialog('分享失败', `分享失败：${this.stringifyError(error)}`);
    });
  }

  private copyVisitUrl(visit: HistoryDisplayVisit): void {
    try {
      this.historyFeature.authorizeShareForManagement(this.buildHistoryManagementBoundary());
    } catch (error) {
      this.showDialog('无法复制', this.stringifyError(error as Error));
      return;
    }
    this.copyTextToClipboard(visit.url, '当前没有可复制的链接。', '链接已复制。');
  }

  private showVisitDetails(visit: HistoryDisplayVisit): void {
    this.visitDetailRows = this.historyViewModel.buildDetailRows(visit);
    this.visitDetailUrl = visit.url;
    this.visitDetailsSheetVisible = true;
  }

  private confirmDeleteSiteForVisit(visit: HistoryDisplayVisit): void {
    const site = this.sites.find((item: HistorySiteGroup) => item.host === visit.host);
    if (site !== undefined) {
      this.confirmDeleteSite(site);
      return;
    }
    this.confirmDeleteSite({
      key: visit.host,
      host: visit.host,
      origin: visit.origin,
      title: visit.host,
      latestTitle: visit.title,
      latestUrl: visit.url,
      latestVisitedAt: visit.visitedAt,
      visitCount: visit.visitCount,
      uniqueUrlCount: 1,
      visits: [visit]
    });
  }

  private confirmDeleteSite(site: HistorySiteGroup): void {
    showCenteredAlertDialog({
      title: '删除站点历史',
      message: `确定删除 ${site.host} 的 ${site.visitCount} 条历史记录吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.deleteSiteVisits(site.host);
        }
      }
    });
  }

  private deleteSiteVisits(host: string): void {
    const removingSourceIds = this.collectSourceVisitIds(
      this.visits.filter((visit: HistoryDisplayVisit) => visit.host === host)
    );
    const deletionTransactionId = this.removeVisitsFromLocalState(removingSourceIds);
    this.removeSitesFromLocalState([host]);
    this.exitSelectionMode();
    this.showNativeToast('站点历史已删除。');
    this.historyFeature.deleteVisitsByHostForManagement(host, this.buildHistoryManagementBoundary())
      .then((removed: number) => {
        this.finishTimelineDeletion(deletionTransactionId, removed > 0);
      })
      .catch((error: Error) => {
        this.finishTimelineDeletion(deletionTransactionId, false);
        this.showDialog('删除失败', `删除站点历史失败：${this.stringifyError(error)}`);
      });
  }

  private confirmDeleteVisit(visit: HistoryDisplayVisit): void {
    showCenteredAlertDialog({
      title: '删除历史记录',
      message: this.historyViewModel.buildDeleteVisitMessage(visit),
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.deleteVisit(visit.id);
        }
      }
    });
  }

  private deleteVisit(visitId: string): void {
    const removingVisit = this.visits.find((visit: HistoryDisplayVisit) => visit.id === visitId);
    const deletingIds = removingVisit === undefined ? [visitId] : this.historyViewModel.getVisitSourceIds(removingVisit);
    const deletionTransactionId = this.removeVisitsFromLocalState(deletingIds);
    this.showNativeToast('历史记录已删除。');
    this.historyFeature.deleteVisitsByIdsForManagement(deletingIds, this.buildHistoryManagementBoundary())
      .then((removed: number) => {
        if (removed <= 0) {
          this.finishTimelineDeletion(deletionTransactionId, false);
          this.showDialog('删除失败', '没有找到这条历史记录，可能已经被删除。');
          return;
        }
        this.finishTimelineDeletion(deletionTransactionId, true);
      })
      .catch((error: Error) => {
        this.finishTimelineDeletion(deletionTransactionId, false);
        this.showDialog('删除失败', `删除失败：${this.stringifyError(error)}`);
      });
  }

  private enterSelectionMode(initialVisitId?: string): void {
    if (this.isSearchMode) {
      return;
    }
    this.controller.closeTimelineSwipeActions();
    this.isSelectionMode = true;
    this.contextMenuVisitId = '';
    if (initialVisitId !== undefined && initialVisitId.length > 0 && !this.isVisitSelected(initialVisitId)) {
      this.selectedVisitIds = this.selectedVisitIds.concat([initialVisitId]);
    }
  }

  private exitSelectionMode(): void {
    this.isSelectionMode = false;
    this.selectedVisitIds = [];
    this.selectedSiteKeys = [];
    this.contextMenuVisitId = '';
  }

  private isVisitSelected(visitId: string): boolean {
    return this.selectedVisitIds.indexOf(visitId) >= 0;
  }

  private setVisitSelected(visitId: string, isSelected: boolean): void {
    const selected = this.selectedVisitIds.slice();
    const index = selected.indexOf(visitId);
    if (isSelected && index < 0) {
      selected.push(visitId);
    } else if (!isSelected && index >= 0) {
      selected.splice(index, 1);
    }
    this.selectedVisitIds = selected;
  }

  private toggleVisitSelection(visitId: string): void {
    this.setVisitSelected(visitId, !this.isVisitSelected(visitId));
  }

  private isSiteSelected(siteKey: string): boolean {
    return this.selectedSiteKeys.indexOf(siteKey) >= 0;
  }

  private setSiteSelected(siteKey: string, isSelected: boolean): void {
    const selected = this.selectedSiteKeys.slice();
    const index = selected.indexOf(siteKey);
    if (isSelected && index < 0) {
      selected.push(siteKey);
    } else if (!isSelected && index >= 0) {
      selected.splice(index, 1);
    }
    this.selectedSiteKeys = selected;
  }

  private toggleSiteSelection(siteKey: string): void {
    this.setSiteSelected(siteKey, !this.isSiteSelected(siteKey));
  }

  private selectAllVisibleVisits(): void {
    if (this.viewMode === 'sites') {
      this.selectedSiteKeys = this.sites.map((site: HistorySiteGroup) => site.key);
      return;
    }
    this.selectedVisitIds = this.visits.map((visit: HistoryDisplayVisit) => visit.id);
  }

  private collectSourceVisitIds(visits: HistoryDisplayVisit[]): string[] {
    const ids: string[] = [];
    visits.forEach((visit: HistoryDisplayVisit) => {
      visit.sourceVisitIds.forEach((id: string) => {
        ids.push(id);
      });
    });
    return Array.from(new Set<string>(ids));
  }

  private refreshBookmarkMarkers(visits: HistoryDisplayVisit[]): void {
    const bookmarkedIds: string[] = [];
    visits.forEach((visit: HistoryDisplayVisit) => {
      if (this.bookmarkManagementFeature.hasBookmarkForUrl(visit.url)) {
        bookmarkedIds.push(visit.id);
      }
    });
    this.bookmarkedVisitIds = bookmarkedIds;
  }

  private refreshHomeShortcutMarkers(visits: HistoryDisplayVisit[]): void {
    this.homeShortcutToggleService.refreshForManagement(this.buildManagementBoundaryInput())
      .then((shortcuts) => {
        const addedVisitIds: string[] = [];
        visits.forEach((visit: HistoryDisplayVisit) => {
          if (this.homeShortcutToggleService.isUrlAddedToScenario(visit.url, shortcuts)) {
            addedVisitIds.push(visit.id);
          }
        });
        this.homeShortcutVisitIds = addedVisitIds;
      })
      .catch(() => {
        this.homeShortcutVisitIds = [];
      });
  }

  private isVisitBookmarked(visitId: string): boolean {
    return this.bookmarkedVisitIds.indexOf(visitId) >= 0;
  }

  private markVisitsBookmarked(visits: HistoryDisplayVisit[]): void {
    const nextIds = this.bookmarkedVisitIds.slice();
    visits.forEach((visit: HistoryDisplayVisit) => {
      if (nextIds.indexOf(visit.id) < 0) {
        nextIds.push(visit.id);
      }
    });
    this.bookmarkedVisitIds = nextIds;
  }

  private unmarkVisitsBookmarkedByUrls(visits: HistoryDisplayVisit[]): void {
    const urls = new Set<string>();
    visits.forEach((visit: HistoryDisplayVisit) => {
      const url = this.normalizeBookmarkMarkerUrl(visit.url);
      if (url.length > 0) {
        urls.add(url);
      }
    });
    if (urls.size === 0) {
      return;
    }
    this.bookmarkedVisitIds = this.visits
      .filter((visit: HistoryDisplayVisit) => {
        return this.bookmarkedVisitIds.indexOf(visit.id) >= 0 &&
          !urls.has(this.normalizeBookmarkMarkerUrl(visit.url));
      })
      .map((visit: HistoryDisplayVisit) => visit.id);
  }

  private normalizeBookmarkMarkerUrl(url: string): string {
    return url.trim().toLowerCase();
  }

  private toggleVisitHomeShortcut(visit: HistoryDisplayVisit): void {
    this.homeShortcutToggleService.toggleForManagement({
      title: visit.title,
      url: visit.url
    }, this.buildManagementBoundaryInput())
      .then((result: HomeShortcutToggleResult) => {
        this.applyHomeShortcutToggleResult(result, visit);
        this.showNativeToast(result.added ? '已添加到主页。' : '已从主页移除。');
      })
      .catch((error: Error) => {
        this.showDialog('操作失败', `更新主页快捷方式失败：${this.stringifyError(error)}`);
      });
  }

  private applyHomeShortcutToggleResult(result: HomeShortcutToggleResult, visit: HistoryDisplayVisit): void {
    if (!result.changed) {
      return;
    }
    const matchingIds: string[] = [];
    this.visits.forEach((item: HistoryDisplayVisit) => {
      if (this.homeShortcutToggleService.normalizeUrlKey(item.url) ===
        this.homeShortcutToggleService.normalizeUrlKey(visit.url)) {
        matchingIds.push(item.id);
      }
    });
    if (result.added) {
      const nextIds = this.homeShortcutVisitIds.slice();
      matchingIds.forEach((id: string) => {
        if (nextIds.indexOf(id) < 0) {
          nextIds.push(id);
        }
      });
      this.homeShortcutVisitIds = nextIds;
      return;
    }
    this.homeShortcutVisitIds = this.homeShortcutVisitIds.filter((id: string) => matchingIds.indexOf(id) < 0);
  }

  private removeVisitsFromLocalState(visitIds: string[]): number {
    if (visitIds.length === 0) {
      return 0;
    }
    this.siteReloadSequence += 1;
    this.isLoadingMoreSites = false;
    const removingIds = new Set<string>(visitIds);
    const transaction: HistoryTimelineDeletionTransaction = this.controller.beginTimelineDeletion(visitIds);
    this.rawVisits = transaction.visits;
    this.applyHistoryViewState();
    this.pruneSelectedVisits();
    this.bookmarkedVisitIds = this.bookmarkedVisitIds.filter((id: string) => !removingIds.has(id));
    this.homeShortcutVisitIds = this.homeShortcutVisitIds.filter((id: string) => !removingIds.has(id));
    this.iconStates = this.iconStates.filter((item: SiteIconListRenderState) => !removingIds.has(item.id));
    this.pruneSelectedSites();
    if (removingIds.has(this.contextMenuVisitId)) {
      this.contextMenuVisitId = '';
    }
    return transaction.id;
  }

  private finishTimelineDeletion(transactionId: number, committed: boolean): void {
    const completion: HistoryTimelineDeletionCompletion =
      this.controller.finishTimelineDeletion(transactionId, committed);
    if (completion.shouldReload) {
      this.reloadVisits();
    }
  }

  private removeSitesFromLocalState(hosts: string[]): void {
    if (hosts.length === 0) {
      return;
    }
    const removingHosts = new Set<string>(hosts);
    this.sites = this.sites.filter((site: HistorySiteGroup) => !removingHosts.has(site.host));
    this.historySiteListDataSource.replaceSites(this.sites);
    const visibleSiteKeys = this.sites.map((site: HistorySiteGroup) => site.key);
    this.selectedSiteKeys = this.selectedSiteKeys.filter((key: string) => visibleSiteKeys.indexOf(key) >= 0);
  }

  private pruneSelectedVisits(): void {
    if (this.selectedVisitIds.length === 0) {
      return;
    }
    const visibleIds = this.visits.map((visit: HistoryDisplayVisit) => visit.id);
    this.selectedVisitIds = this.selectedVisitIds.filter((id: string) => visibleIds.indexOf(id) >= 0);
    this.pruneSelectedSites();
  }

  private pruneSelectedSites(): void {
    if (this.selectedSiteKeys.length === 0) {
      return;
    }
    const visibleSiteKeys = this.sites.map((site: HistorySiteGroup) => site.key);
    this.selectedSiteKeys = this.selectedSiteKeys.filter((key: string) => visibleSiteKeys.indexOf(key) >= 0);
  }

  private confirmDeleteSelectedVisits(): void {
    const selectedCount = this.viewMode === 'sites' ? this.selectedSiteKeys.length : this.selectedVisitIds.length;
    if (selectedCount === 0) {
      return;
    }
    showCenteredAlertDialog({
      title: '删除历史记录',
      message: `确定删除选中的 ${selectedCount} 项历史记录吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.deleteSelectedVisits();
        }
      }
    });
  }

  private deleteSelectedVisits(): void {
    if (this.viewMode === 'sites') {
      this.deleteSelectedSites();
      return;
    }
    const deletingIds = this.resolveSelectedSourceVisitIds();
    if (deletingIds.length === 0) {
      return;
    }
    const uniqueDeletingIds = Array.from(new Set<string>(deletingIds));
    const deletionTransactionId = this.removeVisitsFromLocalState(uniqueDeletingIds);
    this.exitSelectionMode();
    this.showNativeToast(`已删除 ${uniqueDeletingIds.length} 条历史记录。`);
    this.historyFeature.deleteVisitsByIdsForManagement(uniqueDeletingIds, this.buildHistoryManagementBoundary())
      .then((removed: number) => {
        this.finishTimelineDeletion(deletionTransactionId, removed > 0);
      })
      .catch((error: Error) => {
        this.finishTimelineDeletion(deletionTransactionId, false);
        this.showDialog('删除失败', `删除失败：${this.stringifyError(error)}`);
      });
  }

  private deleteSelectedSites(): void {
    const deletingHosts = this.sites
      .filter((site: HistorySiteGroup) => this.selectedSiteKeys.indexOf(site.key) >= 0)
      .map((site: HistorySiteGroup) => site.host)
      .filter((host: string) => host.length > 0);
    if (deletingHosts.length === 0) {
      return;
    }
    const uniqueDeletingHosts = Array.from(new Set<string>(deletingHosts));
    const removingSourceIds = this.collectSourceVisitIds(
      this.visits.filter((visit: HistoryDisplayVisit) => uniqueDeletingHosts.indexOf(visit.host) >= 0)
    );
    const deletionTransactionId = this.removeVisitsFromLocalState(removingSourceIds);
    this.removeSitesFromLocalState(uniqueDeletingHosts);
    this.exitSelectionMode();
    this.showNativeToast(`已删除 ${uniqueDeletingHosts.length} 个站点历史。`);
    let deletionErrorMessage: string = '';
    const deletionTasks: Promise<number>[] = uniqueDeletingHosts.map((host: string): Promise<number> => {
      return this.historyFeature.deleteVisitsByHostForManagement(host, this.buildHistoryManagementBoundary())
        .catch((error: Error): number => {
          if (deletionErrorMessage.length === 0) {
            deletionErrorMessage = this.stringifyError(error);
          }
          return -1;
        });
    });
    Promise.all(deletionTasks)
      .then((removed: number[]) => {
        if (deletionErrorMessage.length > 0) {
          this.finishTimelineDeletion(deletionTransactionId, false);
          this.showDialog('删除失败', `删除失败：${deletionErrorMessage}`);
          return;
        }
        this.finishTimelineDeletion(deletionTransactionId, removed.some((count: number) => count > 0));
      });
  }

  private showSelectionMoreMenu(): void {
    const selectedCount = this.viewMode === 'sites' ? this.selectedSiteKeys.length : this.selectedVisitIds.length;
    if (selectedCount <= 0) {
      return;
    }
    const sheets: HistorySelectionMoreAction[] = [];
    if (this.viewMode === 'timeline') {
      const copyAction: HistorySelectionMoreAction = {
        airaIconId: 'browser.toolbar.copyLink',
        title: '批量复制链接',
        enabled: true,
        action: () => {
          this.requestCloseOverlayMenu();
          this.copySelectedVisitUrls();
        }
      };
      sheets.push(copyAction);
      const bookmarkAction: HistorySelectionMoreAction = {
        airaIconId: 'browser.toolbar.addBookmark',
        title: '批量添加到书签',
        enabled: true,
        action: () => {
          this.requestCloseOverlayMenu();
          this.addSelectedVisitsToBookmarks();
        }
      };
      sheets.push(bookmarkAction);
      if (this.hasSelectedBookmarkedVisits()) {
        const removeBookmarkAction: HistorySelectionMoreAction = {
          airaIconId: 'browser.toolbar.addBookmark',
          title: '批量取消书签',
          enabled: true,
          action: () => {
            this.requestCloseOverlayMenu();
            this.removeSelectedVisitsFromBookmarks();
          }
        };
        sheets.push(removeBookmarkAction);
      }
      const shareAction: HistorySelectionMoreAction = {
        airaIconId: 'browser.toolbar.sharePage',
        title: '批量分享链接',
        enabled: true,
        action: () => {
          this.requestCloseOverlayMenu();
          this.shareSelectedVisitUrls();
        }
      };
      sheets.push(shareAction);
    }
    if (this.viewMode === 'sites') {
      const deleteSitesAction: HistorySelectionMoreAction = {
        airaIconId: 'browser.tabs.delete',
        title: '删除所选站点历史',
        enabled: true,
        action: () => {
          this.requestCloseOverlayMenu();
          this.confirmDeleteSelectedVisits();
        }
      };
      sheets.push(deleteSitesAction);
    }
    if (sheets.length === 0) {
      return;
    }
    this.openOverlayMenu({
      title: '',
      message: '',
      actions: sheets,
      alignToTop: false,
      anchorRight: HISTORY_SELECTION_MENU_SIDE_MARGIN,
      topMargin: HISTORY_SELECTION_MENU_TOP_MARGIN,
      bottomMargin: HISTORY_SELECTION_MENU_BOTTOM_MARGIN
    });
  }

  private copySelectedVisitUrls(): void {
    const visits = this.getSelectedDisplayVisits();
    if (visits.length === 0) {
      return;
    }
    const uniqueUrls = Array.from(new Set<string>(visits.map((visit: HistoryDisplayVisit) => visit.url).filter((url: string) => url.length > 0)));
    this.copyTextToClipboard(uniqueUrls.join('\n'), '当前没有可复制的链接。', `已复制 ${uniqueUrls.length} 条链接。`);
  }

  private hasSelectedBookmarkedVisits(): boolean {
    return this.getSelectedDisplayVisits().some((visit: HistoryDisplayVisit) => {
      return this.bookmarkManagementFeature.hasBookmarkForUrl(visit.url);
    });
  }

  private addSelectedVisitsToBookmarks(): void {
    const visits = this.getSelectedDisplayVisits();
    if (visits.length === 0) {
      return;
    }
    const uniqueVisits = this.deduplicateDisplayVisitsByUrl(visits);
    const existingBookmarkVisits: HistoryDisplayVisit[] = [];
    const pendingVisits = uniqueVisits.filter((visit: HistoryDisplayVisit) => {
      if (this.bookmarkManagementFeature.hasBookmarkForUrl(visit.url)) {
        existingBookmarkVisits.push(visit);
        return false;
      }
      return true;
    });
    if (existingBookmarkVisits.length > 0) {
      this.markVisitsBookmarked(existingBookmarkVisits);
    }
    if (pendingVisits.length === 0) {
      this.exitSelectionMode();
      this.showNativeToast('这些链接已经都在书签里了。');
      return;
    }
    this.openBookmarkFolderSelection(pendingVisits);
  }

  private removeVisitFromBookmarks(visit: HistoryDisplayVisit): void {
    if (!this.bookmarkManagementFeature.hasBookmarkForUrl(visit.url)) {
      this.refreshBookmarkMarkers(this.visits);
      this.showNativeToast('这条历史记录没有书签。');
      return;
    }
    this.unmarkVisitsBookmarkedByUrls([visit]);
    this.bookmarkManagementFeature.deleteRegularBookmarksByUrls([visit.url])
      .then((removedCount: number) => {
        this.showNativeToast(removedCount > 0 ? '已取消书签。' : '这条历史记录没有书签。');
      })
      .catch((error: Error) => {
        this.refreshBookmarkMarkers(this.visits);
        this.showDialog('取消失败', `取消书签失败：${this.stringifyError(error)}`);
      });
  }

  private removeSelectedVisitsFromBookmarks(): void {
    const visits = this.getSelectedDisplayVisits();
    if (visits.length === 0) {
      return;
    }
    const bookmarkedVisits = this.deduplicateDisplayVisitsByUrl(visits)
      .filter((visit: HistoryDisplayVisit) => this.bookmarkManagementFeature.hasBookmarkForUrl(visit.url));
    if (bookmarkedVisits.length === 0) {
      this.exitSelectionMode();
      this.refreshBookmarkMarkers(this.visits);
      this.showNativeToast('选中的链接没有书签。');
      return;
    }
    this.unmarkVisitsBookmarkedByUrls(bookmarkedVisits);
    this.exitSelectionMode();
    this.bookmarkManagementFeature.deleteRegularBookmarksByUrls(
      bookmarkedVisits.map((visit: HistoryDisplayVisit) => visit.url)
    )
      .then((removedCount: number) => {
        if (removedCount > 0) {
          sharedBookmarkFolderSelectionPreparationCoordinator.invalidate('regular');
          void sharedBookmarkFolderSelectionPreparationCoordinator.prepare('regular', true);
        }
        this.showNativeToast(removedCount > 0 ? `已取消 ${removedCount} 个书签。` : '选中的链接没有书签。');
      })
      .catch((error: Error) => {
        this.refreshBookmarkMarkers(this.visits);
        this.showDialog('取消失败', `批量取消书签失败：${this.stringifyError(error)}`);
      });
  }

  private addVisitsToBookmarks(visits: HistoryDisplayVisit[], parentId: string): void {
    const commands: BookmarkCreateNodeCommand[] = visits.map((visit: HistoryDisplayVisit) => {
      const command: BookmarkCreateNodeCommand = {
        type: 'bookmark',
        title: visit.title,
        url: visit.url,
        parentId: parentId.length > 0 ? parentId : undefined
      };
      return command;
    });
    this.bookmarkManagementFeature.createRegularBookmarksIfMissing(commands)
      .then((bookmarks: BookmarkNode[]) => {
        if (bookmarks.length > 0) {
          sharedBookmarkFolderSelectionPreparationCoordinator.invalidate('regular');
          void sharedBookmarkFolderSelectionPreparationCoordinator.prepare('regular', true);
        }
        this.markVisitsBookmarked(visits);
        const addedCount = bookmarks.length;
        this.showNativeToast(addedCount > 0 ? `已添加 ${addedCount} 个书签。` : '这些链接已经都在书签里了。');
      })
      .catch((error: Error) => {
        this.refreshBookmarkMarkers(this.visits);
        this.showDialog('添加失败', `批量添加书签失败：${this.stringifyError(error)}`);
      });
  }

  private openBookmarkFolderSelection(visits: HistoryDisplayVisit[]): void {
    const overlayGeneration = this.bookmarkFolderSelectionOverlayGeneration + 1;
    this.bookmarkFolderSelectionOverlayGeneration = overlayGeneration;
    this.pendingBookmarkVisits = visits.slice();
    this.bookmarkFolderSelectionOptions =
      sharedBookmarkFolderSelectionPreparationCoordinator.getResponsiveOptions('regular');
    this.bookmarkFolderSelectionPreparing =
      sharedBookmarkFolderSelectionPreparationCoordinator.getCachedOptions('regular').length <= 0;
    this.bookmarkFolderSelectionSheetVisible = false;
    this.bookmarkFolderSelectionVisible = true;
    void this.prepareBookmarkFolderSelectionOptions(overlayGeneration);
    setTimeout(() => {
      if (this.bookmarkFolderSelectionOverlayGeneration !== overlayGeneration) {
        return;
      }
      if (this.bookmarkFolderSelectionVisible) {
        this.bookmarkFolderSelectionSheetVisible = true;
      }
    }, BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS);
  }

  private dismissBookmarkFolderSelection(): void {
    const overlayGeneration = this.bookmarkFolderSelectionOverlayGeneration + 1;
    this.bookmarkFolderSelectionOverlayGeneration = overlayGeneration;
    this.bookmarkFolderSelectionSheetVisible = false;
    setTimeout(() => {
      if (this.bookmarkFolderSelectionOverlayGeneration !== overlayGeneration) {
        return;
      }
      this.bookmarkFolderSelectionVisible = false;
      this.bookmarkFolderSelectionPreparing = false;
      this.bookmarkFolderSelectionOptions = [];
      this.pendingBookmarkVisits = [];
    }, BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS);
  }

  private confirmSelectedBookmarkFolder(result: BookmarkMoveFolderSelectionResult): void {
    const visits = this.pendingBookmarkVisits.slice();
    const parentId = result.targetFolderId;
    this.bookmarkFolderSelectionOverlayGeneration += 1;
    this.bookmarkFolderSelectionSheetVisible = false;
    this.bookmarkFolderSelectionVisible = false;
    this.bookmarkFolderSelectionPreparing = false;
    this.bookmarkFolderSelectionOptions = [];
    this.pendingBookmarkVisits = [];
    if (visits.length === 0) {
      return;
    }
    this.markVisitsBookmarked(visits);
    this.exitSelectionMode();
    setTimeout(() => {
      this.addVisitsToBookmarks(visits, parentId);
    }, 0);
  }

  private async prepareBookmarkFolderSelectionOptions(overlayGeneration: number): Promise<void> {
    try {
      const options = await sharedBookmarkFolderSelectionPreparationCoordinator.prepare('regular');
      if (this.bookmarkFolderSelectionOverlayGeneration !== overlayGeneration ||
        !this.bookmarkFolderSelectionVisible) {
        return;
      }
      if (options.length === 0) {
        this.bookmarkFolderSelectionPreparing = false;
        this.bookmarkFolderSelectionVisible = false;
        this.bookmarkFolderSelectionOptions = [];
        this.pendingBookmarkVisits = [];
        this.showDialog('无法添加书签', '当前没有可保存书签的文件夹。');
        return;
      }
      this.bookmarkFolderSelectionOptions = options;
      this.bookmarkFolderSelectionPreparing = false;
    } catch (error) {
      if (this.bookmarkFolderSelectionOverlayGeneration !== overlayGeneration ||
        !this.bookmarkFolderSelectionVisible) {
        return;
      }
      this.bookmarkFolderSelectionPreparing = false;
      this.showDialog('加载失败', `文件夹加载失败：${this.stringifyError(error as Error)}`);
    }
  }

  private async prepareBookmarkFolderSelectionFolderPreview(folderId: string): Promise<void> {
    const overlayGeneration = this.bookmarkFolderSelectionOverlayGeneration;
    try {
      const options = await sharedBookmarkFolderSelectionPreparationCoordinator.prepareFolderPreview(
        'regular',
        folderId,
        this.bookmarkFolderSelectionOptions
      );
      if (this.bookmarkFolderSelectionOverlayGeneration !== overlayGeneration ||
        !this.bookmarkFolderSelectionVisible) {
        return;
      }
      this.bookmarkFolderSelectionOptions = options;
    } catch (_error) {
    }
  }

  private shareSelectedVisitUrls(): void {
    const visits = this.getSelectedDisplayVisits();
    if (visits.length === 0) {
      return;
    }
    try {
      this.historyFeature.authorizeShareForManagement(this.buildHistoryManagementBoundary());
    } catch (error) {
      this.showDialog('无法分享', this.stringifyError(error as Error));
      return;
    }
    const uniqueVisits = this.deduplicateDisplayVisitsByUrl(visits);
    const summaryTitle = uniqueVisits.length === 1 ? uniqueVisits[0].title : `分享 ${uniqueVisits.length} 条历史链接`;
    const summaryUrls = uniqueVisits.map((visit: HistoryDisplayVisit) => visit.url).join('\n');
    this.webPageShareService.sharePlainText(this.getPickerContext(), summaryTitle, summaryUrls).catch((error: Error) => {
      this.showDialog('分享失败', `批量分享失败：${this.stringifyError(error)}`);
    });
  }

  private getSelectedDisplayVisits(): HistoryDisplayVisit[] {
    if (this.viewMode === 'sites') {
      return this.sites
        .filter((site: HistorySiteGroup) => this.selectedSiteKeys.indexOf(site.key) >= 0)
        .flatMap((site: HistorySiteGroup) => site.visits.slice());
    }
    return this.visits.filter((visit: HistoryDisplayVisit) => this.selectedVisitIds.indexOf(visit.id) >= 0);
  }

  private deduplicateDisplayVisitsByUrl(visits: HistoryDisplayVisit[]): HistoryDisplayVisit[] {
    const seen = new Set<string>();
    const results: HistoryDisplayVisit[] = [];
    visits.forEach((visit: HistoryDisplayVisit) => {
      const key = visit.url.trim().toLowerCase();
      if (key.length === 0 || seen.has(key)) {
        return;
      }
      seen.add(key);
      results.push(visit);
    });
    return results;
  }

  private resolveSelectedSourceVisitIds(): string[] {
    const deletingIds: string[] = [];
    this.visits
      .filter((visit: HistoryDisplayVisit) => this.selectedVisitIds.indexOf(visit.id) >= 0)
      .forEach((visit: HistoryDisplayVisit) => {
        this.historyViewModel.getVisitSourceIds(visit).forEach((id: string) => deletingIds.push(id));
      });
    return Array.from(new Set<string>(deletingIds));
  }

  private openOverlayMenu(state: HistoryOverlayMenuState): void {
    this.selectionMenuRevealSequence += 1;
    this.overlayMenuState = {
      title: state.title,
      message: state.message,
      actions: state.actions.slice(),
      alignToTop: state.alignToTop,
      anchorRight: state.anchorRight,
      topMargin: state.topMargin,
      bottomMargin: state.bottomMargin
    };
    const sequence = this.selectionMenuRevealSequence;
    this.selectionMenuVisible = false;
    setTimeout(() => {
      if (sequence === this.selectionMenuRevealSequence) {
        this.selectionMenuVisible = true;
      }
    }, 24);
  }

  private requestCloseOverlayMenu(): void {
    this.selectionMenuRevealSequence += 1;
    this.selectionMenuVisible = false;
    setTimeout(() => {
      this.overlayMenuState = {
        title: '',
        message: '',
        actions: [],
        alignToTop: false,
        anchorRight: HISTORY_SELECTION_MENU_SIDE_MARGIN,
        topMargin: HISTORY_SELECTION_MENU_TOP_MARGIN,
        bottomMargin: HISTORY_SELECTION_MENU_BOTTOM_MARGIN
      };
    }, HISTORY_SELECTION_MENU_EXIT_DELAY_MS);
  }

  private openSiteCleanupMode(): void {
    if (!this.controller.hasLoadedTimelineVisits()) {
      return;
    }
    this.clearDrilldownState();
    this.isSearchMode = false;
    this.searchQuery = '';
    this.viewMode = 'sites';
    this.loadSiteFirstPage();
    this.enterSelectionMode();
    this.showNativeToast('选择站点后点删除。');
  }

  private isViewModeEmpty(mode: HistoryViewMode): boolean {
    if (mode === 'sites') {
      return this.sites.length === 0;
    }
    return this.visits.length === 0;
  }

  private getEmptyTitle(mode: HistoryViewMode = this.viewMode): string {
    if (this.isSearchMode) {
      return this.searchQuery.trim().length > 0 ? '没有匹配的历史记录' : '搜索历史记录';
    }
    return this.searchQuery.trim().length > 0 ? '没有匹配的历史记录' : '还没有历史记录';
  }

  private getEmptyMessage(mode: HistoryViewMode = this.viewMode): string {
    if (this.isSearchMode) {
      return this.searchQuery.trim().length > 0 ? '换个关键词试试。' : '输入标题或网址开始搜索';
    }
    return this.searchQuery.trim().length > 0 ? '换个关键词试试。' : '从搜索栏打开网页后，这里会自动记录。';
  }

  private switchViewMode(mode: HistoryViewMode): void {
    if (this.viewMode === mode) {
      return;
    }
    this.controller.resetTimelineSwipeActions();
    this.viewMode = mode;
    this.clearDrilldownState();
    this.exitSelectionMode();
    this.loadCurrentModeFirstPage();
  }

  private applyRetentionPolicyIfNeeded(): void {
    const settings = this.historyFeature.getHistoryRetentionSettings();
    if (!settings.enabled || this.rawVisits.length === 0 || this.isApplyingRetentionPolicy) {
      return;
    }
    this.isApplyingRetentionPolicy = true;
    this.historyFeature.applyRetentionPolicyForManagement(
      settings,
      this.buildHistoryManagementBoundary()
    )
      .then((removed: number) => {
        if (removed > 0) {
          this.reloadVisits();
        }
      })
      .catch((_error: Error) => {
      })
      .finally(() => {
        this.isApplyingRetentionPolicy = false;
      });
  }

  private seedStressHistoryIfRequested(): boolean {
    if (this.isSeedingStressHistory) {
      return true;
    }
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    const seedCount = Number(params?.seedHistoryCount ?? 0);
    if (!Number.isFinite(seedCount) || seedCount <= 0) {
      return false;
    }
    if (this.handledStressHistorySeedCount === seedCount) {
      return false;
    }
    this.handledStressHistorySeedCount = seedCount;
    this.isSeedingStressHistory = true;
    this.historyFeature.seedStressFixtureForManagement(
      sharedBrowserDatabase,
      seedCount,
      this.buildHistoryManagementBoundary()
    )
      .then(() => {
        this.reloadVisits();
      })
      .catch((error: Error) => {
        this.showDialog('生成压测历史失败', `生成 5 万条历史记录失败：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.isSeedingStressHistory = false;
      });
    return true;
  }

  private importHistoryBundle(): void {
    if (this.isTransferBusy) {
      return;
    }
    this.isTransferBusy = true;
    let importStage = '打开文件选择器';
    this.pickOpenUri()
      .then((uri: string | undefined) => {
        if (uri === undefined) {
          return Promise.resolve(undefined);
        }
        importStage = '读取文件';
        return this.readTextFromUri(uri)
          .then((payload: string) => {
            importStage = '写入历史';
            return this.historyFeature.importVisitsForManagement(payload, this.buildHistoryManagementBoundary());
          });
      })
      .then((result: HistoryImportResult | undefined) => {
        if (result === undefined) {
          return;
        }
        this.reloadVisits();
        this.showDialog('导入成功', `已导入 ${result.importedCount} 条历史记录，跳过 ${result.skippedCount} 条重复记录。`);
      })
      .catch((error: Error) => {
        this.showDialog('导入失败', `导入失败（${importStage}）：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.isTransferBusy = false;
      });
  }

  private exportHistoryBundle(): void {
    if (this.isTransferBusy) {
      return;
    }
    this.isTransferBusy = true;
    const fileName = `aira-history-${this.resolveFileTimestamp()}.json`;
    this.pickSaveUri(fileName)
      .then((uri: string | undefined) => {
        if (uri === undefined) {
          return Promise.resolve();
        }
        const payload = this.historyFeature.exportVisitsForManagement(this.buildHistoryManagementBoundary());
        return this.writeTextToUri(uri, payload).then(() => {
          this.showDialog('导出成功', '历史记录已导出。');
        });
      })
      .catch((error: Error) => {
        this.showDialog('导出失败', `导出失败：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.isTransferBusy = false;
      });
  }

  private buildHistoryManagementBoundary(): HistoryManagementBoundary {
    return new HistoryManagementBoundary(
      this.isSessionEphemeral ? 'session_ephemeral' : 'profile_persistent',
      this.isSessionEphemeral ? 'private' : 'regular'
    );
  }

  private buildManagementBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.isSessionEphemeral ? 'session_ephemeral' : 'profile_persistent',
      privacyMode: this.isSessionEphemeral ? 'private' : 'regular'
    };
  }

  private updatePressedVisit(visitId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedVisitId = visitId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedVisitId = '';
    }
  }

  private openContextMenu(visitId: string): void {
    if (this.isSelectionMode) {
      return;
    }
    this.pressedVisitId = '';
    this.contextMenuVisitId = visitId;
  }

  private resolveVisibleIcons(): void {
    this.visibleIconResolveTimer = -1;
    this.siteIconListPresenter.resolveTargets(
      this.buildVisibleIconTargets(),
      (result: SiteIconListResolvedIcon): void => {
        if (result.uri.length > 0) {
          this.applyResolvedSiteIcon(result);
        }
      }
    );
  }

  private buildVisibleIconTargets(): HistoryIconStateTarget[] {
    if (this.viewMode === 'sites') {
      return this.historySiteListDataSource
        .getIconTargetsAround(this.siteVisibleStartIndex, this.siteVisibleEndIndex, 8)
        .map((item: HistorySiteIconTarget): HistoryIconStateTarget => {
          return {
            id: item.id,
            url: item.url,
            domain: item.domain
          };
        });
    }
    const visibleContent = this.controller.getTimelineVisibleContent();
    return this.historyTimelineDataSource
      .getIconTargetsAroundVisibleContent(
        visibleContent.startGroupIndex,
        visibleContent.startItemIndex,
        visibleContent.endGroupIndex,
        visibleContent.endItemIndex,
        8
      )
      .map((item: HistoryTimelineIconTarget): HistoryIconStateTarget => {
        return {
          id: item.id,
          url: item.url,
          domain: item.domain
        };
      });
  }

  private updateTimelineVisibleContent(
    startGroupIndex: number,
    startItemIndex: number,
    endGroupIndex: number,
    endItemIndex: number
  ): void {
    const visibleContent: HistoryTimelineVisibleContent = {
      startGroupIndex: startGroupIndex,
      startItemIndex: startItemIndex,
      endGroupIndex: endGroupIndex,
      endItemIndex: endItemIndex
    };
    if (!this.controller.updateTimelineVisibleContent(visibleContent)) {
      return;
    }
    this.scheduleVisibleIconResolve();
  }

  private updateSiteVisibleRange(start: number, end: number): void {
    if (this.siteVisibleStartIndex === start && this.siteVisibleEndIndex === end) {
      return;
    }
    this.siteVisibleStartIndex = start;
    this.siteVisibleEndIndex = end;
    this.requestMoreSiteRowsIfNeeded();
    this.scheduleVisibleIconResolve();
  }

  private scheduleVisibleIconResolve(): void {
    this.cancelVisibleIconResolve();
    this.visibleIconResolveTimer = setTimeout(() => {
      this.resolveVisibleIcons();
    }, HISTORY_VISIBLE_ICON_RESOLVE_DELAY_MS);
  }

  private cancelVisibleIconResolve(): void {
    if (this.visibleIconResolveTimer >= 0) {
      clearTimeout(this.visibleIconResolveTimer);
      this.visibleIconResolveTimer = -1;
    }
  }

  private resolveOverlayMenuWidth(): number {
    const hostWidth = this.selectionMenuHostWidth > 0 ? this.selectionMenuHostWidth : 360;
    return Math.max(HISTORY_SELECTION_MENU_MIN_PANEL_WIDTH,
      Math.min(HISTORY_SELECTION_MENU_PANEL_WIDTH, hostWidth - HISTORY_SELECTION_MENU_SIDE_MARGIN * 2));
  }

  private resolveOverlayMenuItemEnterOffset(index: number): number {
    return HISTORY_SELECTION_MENU_ITEM_ENTER_OFFSET_Y + Math.min(index, 8) * 2;
  }

  private resolveOverlayMenuItemEnterDelay(index: number): number {
    return Math.min(index, 8) * 22;
  }

  private resolveOverlayMenuItemColor(enabled: boolean): ResourceColor {
    return enabled ? this.storedPrimaryTextColor : this.storedSecondaryTextColor;
  }

  private applyResolvedSiteIcon(result: SiteIconListResolvedIcon): void {
    const next = this.siteIconListPresenter.applyResolvedIcon(this.iconStates, result);
    if (next !== this.iconStates) {
      this.iconStates = next;
    }
  }

  private resolveHistoryPixelMapAfterUriFailure(
    target: SiteIconListTarget,
    currentUri: string,
    sourceRevision: number
  ): void {
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      target,
      currentUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
  }

  private getPickerContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private pickOpenUri(): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(this.getPickerContext());
    return documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.json']
    }).then((uris: Array<string>) => uris.length > 0 ? uris[0] : undefined);
  }

  private pickSaveUri(fileName: string): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(this.getPickerContext());
    return documentPicker.save({
      newFileNames: [fileName],
      fileSuffixChoices: ['JSON|.json']
    }).then((uris: Array<string>) => uris.length > 0 ? uris[0] : undefined);
  }

  private async readTextFromUri(uri: string): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const chunks: string[] = [];
    const chunkSize = 64 * 1024;
    try {
      let bytesRead = 0;
      do {
        const data = new ArrayBuffer(chunkSize);
        bytesRead = await fileIo.read(file.fd, data);
        if (bytesRead > 0) {
          chunks.push(buffer.from(data, 0, bytesRead).toString('utf8'));
        }
      } while (bytesRead === chunkSize);
    } finally {
      await fileIo.close(file);
    }
    return chunks.join('');
  }

  private async writeTextToUri(uri: string, payload: string): Promise<void> {
    const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, payload);
    } finally {
      await fileIo.close(file);
    }
  }

  private resolveFileTimestamp(): string {
    const now = new Date();
    const year = String(now.getFullYear());
    const month = this.padTwoDigits(now.getMonth() + 1);
    const day = this.padTwoDigits(now.getDate());
    const hour = this.padTwoDigits(now.getHours());
    const minute = this.padTwoDigits(now.getMinutes());
    return `${year}${month}${day}-${hour}${minute}`;
  }

  private padTwoDigits(value: number): string {
    const normalized = Math.max(0, Math.round(value));
    return normalized < 10 ? `0${normalized}` : String(normalized);
  }

  private copyTextToClipboard(value: string, emptyMessage: string, successMessage: string): void {
    if (value.length === 0) {
      this.showNativeToast(emptyMessage);
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      pasteboard.getSystemPasteboard().setData(data)
        .then(() => {
          this.showNativeToast(successMessage);
        })
        .catch((_error: Error) => {
          this.showNativeToast('复制失败，请稍后重试。');
        });
    } catch (_error) {
      this.showNativeToast('复制失败，请稍后重试。');
    }
  }

  private showNativeToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
    }
  }

  private showDialog(title: string, message: string): void {
    showCenteredAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      confirm: {
        value: '知道了',
        action: () => {
        }
      }
    });
  }

  private performLongPressFeedback(): void {
    vibrator.startVibration({
      type: 'time',
      duration: 18
    }, {
      usage: 'touch'
    }).catch((_error: Error) => {
    });
  }

  private stringifyError(error: Error): string {
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    const serialized = JSON.stringify(error);
    return serialized.length > 0 ? serialized : '未知错误';
  }
}
