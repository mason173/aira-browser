import { BookmarkAddDraft, createBookmarkAddDraft } from '../../../core/bookmarks/BookmarkAddDraft';
import { HistoryBookmarkAddCoordinator } from '../../../core/bookmarks/HistoryBookmarkAddCoordinator';
import { BrowserBookmarkFolderSelectionAction } from '../../../core/browser/BrowserBookmarkActionCoordinator';
import { localizeHistoryHost } from '../../../core/resources/HistoryBookmarkDisplayText';
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
  HISTORY_SELECTION_MORE_EMPTY_MESSAGE,
  HistorySelectionMoreActionId,
  HistorySelectionMoreMenuItem,
  planHistorySelectionMoreMenu
} from '../../../features/history/HistorySelectionMoreMenu';
import { HistoryVisitContextActionId } from '../../../features/history/HistoryVisitContextAction';
import { hasAppResourceText, resolveAppResourceText } from '../../../core/resources/AppResourceText';
import {
  HistoryManagerScreenController,
  HistoryTimelineDeletionCompletion,
  HistoryTimelineDeletionTransaction,
  HistoryTimelineVisibleContent
} from '../../../features/history/HistoryManagerScreenController';
import { HistorySitePageController, HistorySitePageStatus } from '../../../features/history/HistorySitePageController';
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
import {
  FloatingSelectionToolbar,
  FloatingSelectionToolbarMenuItem
} from '../common/FloatingSelectionToolbar';
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
import { applyDesktopDialogSheetChrome } from '../common/DesktopDialogSheetChrome';

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
const HISTORY_TITLE_ACTION_ELEVATE_OFFSET: number = 8;

interface HistoryIconStateTarget {
  id: string;
  url: string;
  domain?: string;
}

interface HistorySelectionMoreAction {
  airaIconId: AiraRenderableIconId;
  title: ResourceStr;
  action: () => void;
  enabled: boolean;
}

interface HistoryOverlayMenuState {
  title: ResourceStr;
  message: ResourceStr;
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
  private singleBookmarkAddCoordinator: HistoryBookmarkAddCoordinator = new HistoryBookmarkAddCoordinator({
    applyDraft: (draft: BookmarkAddDraft): void => { this.singleBookmarkDraft = draft; },
    resolveFolders: (): BookmarkFolderOptionView[] => this.bookmarkFolderSelectionOptions,
    hasBookmark: (url: string): boolean => this.bookmarkManagementFeature.hasBookmarkForUrl(url),
    isFolderAvailable: (folderId: string): boolean => {
      const folder = this.bookmarkManagementFeature.findNodeById(folderId);
      return folder !== undefined && folder.type === 'folder';
    },
    previewFolder: (folderId: string): void => { void this.prepareBookmarkFolderSelectionFolderPreview(folderId); },
    dismiss: (): void => { this.dismissBookmarkFolderSelection(); },
    beginSave: (title: string, url: string, folderId: string) => {
      return this.bookmarkManagementFeature.beginCreateRegularBookmarkIfMissing({
        type: 'bookmark', title: title, url: url, parentId: folderId
      });
    },
    refreshBookmarks: (): void => {
      sharedBookmarkFolderSelectionPreparationCoordinator.invalidate('regular');
      void sharedBookmarkFolderSelectionPreparationCoordinator.prepare('regular', true).catch(() => undefined);
      if (this.isActive) { this.refreshBookmarkMarkers(this.visits); }
    },
    onSyncPreparationFailed: (): void => {
      if (this.isActive) { this.showNativeToast($r('app.string.bookmark_add_saved_sync_pending')); }
    },
    onSaved: (): void => {
      this.dismissBookmarkFolderSelection();
      this.exitSelectionMode();
      this.showNativeToast($r('app.string.bottom_panel_bookmark_added'));
    }
  });
  private homeShortcutToggleService: HomeShortcutToggleService = new HomeShortcutToggleService(sharedShortcutRepository);
  private webPageShareService: WebPageShareService = new WebPageShareService();
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  private deferredEnterWork: DeferredEnterWork = new DeferredEnterWork();
  private historyViewModel: HistoryViewModel = new HistoryViewModel();
  private historyTimelineDataSource: HistoryTimelineDataSource = new HistoryTimelineDataSource();
  private historySiteListDataSource: HistorySiteListDataSource = new HistorySiteListDataSource();
  private historySiteScroller: Scroller = new Scroller();
  private sitePageController: HistorySitePageController = new HistorySitePageController(this.historyFeature);
  private isActive: boolean = false;
  private timelineScrollOffset: number = 0;
  private siteScrollOffset: number = 0;
  private scrollRestoreTimer: number = -1;
  private privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService =
    new BrowserPrivateBoundaryNavigationService();
  @State rawVisits: HistoryVisit[] = [];
  @State visits: HistoryDisplayVisit[] = [];
  @State sites: HistorySiteGroup[] = [];
  @State searchQuery: string = '';
  @State isSearchMode: boolean = false;
  @State searchReturnMode: HistoryViewMode = 'timeline';
  @State titleActionsElevated: boolean = false;
  @State viewMode: HistoryViewMode = 'timeline';
  @State isTimelineLoading: boolean = false;
  @State isSiteLoading: boolean = false;
  @State timelineLoadError: ResourceStr = '';
  @State siteLoadError: ResourceStr = '';
  @State drilldownReturnQuery: string = '';
  @State drilldownReturnMode: HistoryViewMode = 'timeline';
  @State drilldownHost: string = '';
  @State isSelectionMode: boolean = false;
  @State selectedVisitIds: string[] = [];
  @State selectedSiteKeys: string[] = [];
  @State pressedVisitId: string = '';
  @State contextMenuVisitId: string = '';
  @State timelineIconStates: SiteIconListRenderState[] = [];
  @State siteIconStates: SiteIconListRenderState[] = [];
  @State bookmarkedVisitIds: string[] = [];
  @State homeShortcutVisitIds: string[] = [];
  @State isTransferBusy: boolean = false;
  @State pendingHistoryMutations: number = 0;
  @State visitDetailRows: HistoryDetailRow[] = [];
  @State visitDetailUrl: string = '';
  @State visitDetailsSheetVisible: boolean = false;
  @State selectionMenuVisible: boolean = false;
  @State selectionMenuHostWidth: number = 0;
  @State selectionMenuHostHeight: number = 0;
  @State private singleBookmarkDraft: BookmarkAddDraft = createBookmarkAddDraft();
  @State private editSingleBookmark: boolean = false;
  @State private singleBookmarkSessionVersion: number = 0;
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
  private pendingBookmarkVisits: HistoryDisplayVisit[] = [];
  private bookmarkFolderSelectionOverlayGeneration: number = 0;
  private selectionMenuRevealSequence: number = 0;
  private siteVisibleStartIndex: number = 0;
  private siteVisibleEndIndex: number = 20;
  private visibleIconResolveTimer: number = -1;
  private inactiveIconResolveTimer: number = -1;
  @State isSessionEphemeral: boolean = false;
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private topSafeInsetVp: number = 0;
  aboutToAppear(): void {
    this.isActive = true;
    this.sitePageController = new HistorySitePageController(this.historyFeature);
    this.sitePageController.setStatusListener((status: HistorySitePageStatus): void => {
      this.isSiteLoading = status.loading;
      this.siteLoadError = status.error;
    });
    this.controller.setTimelineErrorListener((message: ResourceStr): void => {
      this.timelineLoadError = message;
    });
    this.controller.setTimelineLoadingListener((loading: boolean): void => {
      this.isTimelineLoading = loading;
    });
    this.controller.setBackHandler((): boolean => {
      if (this.bookmarkFolderSelectionVisible) {
        if (this.editSingleBookmark) {
          this.singleBookmarkAddCoordinator.handleAction({ type: 'back' });
        } else {
          this.dismissBookmarkFolderSelection();
        }
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
      (): SiteIconListTarget[] => this.buildIconTargets(this.viewMode),
      (result: SiteIconListResolvedIcon) => {
        this.applyDomainIconUpdate(result);
      }
    );
    if (!this.seedStressHistoryIfRequested()) {
      this.deferredEnterWork.schedule((): void => {
        this.loadCurrentModeFirstPage();
      });
    }
  }

  aboutToDisappear(): void {
    this.isActive = false;
    this.singleBookmarkAddCoordinator.cancel();
    this.bookmarkFolderSelectionOverlayGeneration += 1;
    this.bookmarkFolderSelectionVisible = false;
    this.bookmarkFolderSelectionSheetVisible = false;
    this.deferredEnterWork.cancel();
    this.cancelHistoryScrollRestore();
    this.sitePageController.setStatusListener(undefined);
    this.sitePageController.invalidate();
    this.controller.clearBackHandler();
    this.cancelVisibleIconResolve();
    this.cancelInactiveIconResolve();
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
          elevateTitleActions: this.titleActionsElevated,
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
    .bindSheet($$this.visitDetailsSheetVisible, this.buildVisitDetailsSheet(), applyDesktopDialogSheetChrome({
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.visitDetailsSheetVisible = false;
      }
    }, 'm'))
  }

  @Builder
  private buildVisitDetailsSheet() {
    HistoryVisitDetailsSheet({
      rows: this.visitDetailRows,
      copyLink: () => {
        this.copyTextToClipboard(this.visitDetailUrl, $r('app.string.history_copy_empty'), $r('app.string.history_link_copied_period'));
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
    const hasHistory = this.visits.length > 0 || this.sites.length > 0;
    const canEdit = !this.isViewModeEmpty(this.viewMode) && !this.isTransferBusy &&
      this.pendingHistoryMutations === 0;
    const actions: ManagementHdsMenuAction[] = [
      {
        label: $r('app.string.settings_sync_search'),
        icon: $r('sys.symbol.magnifyingglass'),
        action: () => {
          this.enterSearchMode();
        }
      },
      {
        label: $r('app.string.ui_edit'),
        icon: $r('sys.symbol.checkmark_circle_fill'),
        enabled: canEdit,
        action: () => {
          this.enterSelectionMode();
        }
      },
      {
        label: $r('app.string.history_cleanup_by_site'),
        icon: $r('sys.symbol.trash_fill'),
        enabled: hasHistory && !this.isTransferBusy,
        action: () => {
          this.openSiteCleanupMode();
        }
      },
      {
        label: $r('app.string.history_import'),
        icon: $r('sys.symbol.arrow_down'),
        enabled: !this.isTransferBusy,
        action: () => {
          this.importHistoryBundle();
        }
      },
      {
        label: $r('app.string.history_export'),
        icon: $r('sys.symbol.arrow_up'),
        enabled: hasHistory && !this.isTransferBusy,
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
            if (hasAppResourceText(this.overlayMenuState.title)) {
              Column({ space: 4 }) {
                Text(this.overlayMenuState.title)
                  .width('100%')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.storedPrimaryTextColor)
                if (hasAppResourceText(this.overlayMenuState.message)) {
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
            }, (item: HistorySelectionMoreAction, index: number) => `overlay-${index}-${item.airaIconId}`)
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
    Stack({ alignContent: Alignment.Top }) {
      this.buildHistoryPage()
      this.buildHistoryLoadStatus()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildHistoryLoadStatus() {
    if (hasAppResourceText(this.resolveHistoryLoadError())) {
      Row({ space: 8 }) {
        Text(this.resolveHistoryLoadError())
          .fontSize(14)
          .fontColor(this.storedSecondaryTextColor)
        Button($r('app.string.settings_sync_retry'))
          .onClick(() => this.reloadVisits())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: this.resolveHistoryContentTopInset() + 8, bottom: 8 })
      .backgroundColor(this.storedPageBackgroundColor)
    } else if (this.isCurrentModeLoading() && this.isViewModeEmpty(this.viewMode)) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(32)
          .height(32)
        Text($r('app.string.history_loading_ellipsis'))
          .fontSize(14)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  private isCurrentModeLoading(): boolean {
    return this.viewMode === 'sites' ? this.isSiteLoading : this.isTimelineLoading;
  }

  private resolveHistoryLoadError(): ResourceStr {
    return this.viewMode === 'sites' ? this.siteLoadError : this.timelineLoadError;
  }

  // Read this.viewMode inside the observed builder bodies (not as a by-value
  // parameter) so ArkUI subscribes the list subtree to the view-mode state.
  @Builder
  private buildHistoryPage() {
    if (this.isSearchMode && this.searchQuery.trim().length === 0) {
      this.buildIdleSearchList()
    } else {
      Stack({ alignContent: Alignment.Top }) {
        // Keep a loaded list mounted. Visibility.None leaves it created but
        // out of layout; Hidden would still measure the inactive LazyForEach.
        if (this.viewMode === 'timeline' || this.visits.length > 0) {
          Column() {
            this.buildTimelineList()
          }
          .width('100%')
          .height('100%')
          .zIndex(this.viewMode === 'timeline' ? 1 : 0)
          .visibility(this.viewMode === 'timeline' ? Visibility.Visible : Visibility.None)
          .hitTestBehavior(this.viewMode === 'timeline' ? HitTestMode.Default : HitTestMode.None)
        }
        if (this.viewMode === 'sites' || this.sites.length > 0) {
          Column() {
            this.buildSiteList()
          }
          .width('100%')
          .height('100%')
          .zIndex(this.viewMode === 'sites' ? 1 : 0)
          .visibility(this.viewMode === 'sites' ? Visibility.Visible : Visibility.None)
          .hitTestBehavior(this.viewMode === 'sites' ? HitTestMode.Default : HitTestMode.None)
        }
        if (this.shouldShowHistoryEmptyState(this.viewMode)) {
          this.buildEmptyState(this.viewMode)
        }
      }
      .width('100%')
      .height('100%')
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
  private buildSiteList() {
    HistorySiteList({
        dataSource: this.historySiteListDataSource,
        listScroller: this.historySiteScroller,
        icons: this.siteIconStates,
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
          this.resolveHistoryPixelMapAfterUriFailure('sites', target, currentUri, sourceRevision);
        },
        onScrollVisibleRange: (start: number, end: number) => {
          this.updateSiteVisibleRange(start, end);
        },
        onScrollOffsetChange: (offset: number) => {
          if (this.viewMode === 'sites') {
            this.updateTitleActionsElevationFromOffset(offset);
          }
        }
      })
      .onAppear(() => this.scheduleHistoryScrollRestore('sites'))
  }

  @Builder
  private buildTimelineList() {
    HistoryTimelineList({
        dataSource: this.historyTimelineDataSource,
        listScroller: this.controller.getTimelineScroller(),
        icons: this.timelineIconStates,
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
        onContextAction: (visit: HistoryDisplayVisit, actionId: HistoryVisitContextActionId) => {
          this.handleContextAction(visit, actionId);
        },
        onIconLoadError: (
          target: SiteIconListTarget,
          currentUri: string,
          sourceRevision: number
        ) => {
          this.resolveHistoryPixelMapAfterUriFailure('timeline', target, currentUri, sourceRevision);
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
        onScrollOffsetChange: (offset: number) => {
          if (this.viewMode === 'timeline') {
            this.updateTitleActionsElevationFromOffset(offset);
          }
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
      .onAppear(() => this.scheduleHistoryScrollRestore('timeline'))
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
          title: $r('app.string.ui_select_all'),
          action: () => {
            this.selectAllVisibleVisits();
          }
        },
        {
          airaIconId: 'browser.tabs.delete',
          title: $r('app.string.settings_delete'),
          action: () => {
            this.confirmDeleteSelectedVisits();
          }
        },
        {
          airaIconId: 'browser.toolbar.more',
          title: $r('app.string.settings_sync_more'),
          menu: this.buildHistorySelectionMoreMenuItems()
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
      editSingleBookmark: this.editSingleBookmark,
      draft: this.singleBookmarkDraft,
      sessionVersion: this.singleBookmarkSessionVersion,
      onAction: (action: BrowserBookmarkFolderSelectionAction): void => {
        this.singleBookmarkAddCoordinator.handleAction(action);
      },
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
    if (!this.isActive) {
      return;
    }
    this.controller.invalidateTimelineCache();
    this.sitePageController.invalidate();
    if (this.viewMode === 'sites' && !this.shouldHoldEmptySearchResults()) {
      // A failed deletion must recover the optimistic removal, so the stale
      // visible rows cannot be preserved across the recovery read.
      this.loadSiteFirstPage(false);
      return;
    }
    this.loadCurrentModeFirstPage();
  }

  private loadCurrentModeFirstPage(allowReuse: boolean = false): void {
    this.deferredEnterWork.cancel();
    if (this.shouldHoldEmptySearchResults()) {
      this.clearHistoryViewState();
      return;
    }
    if (this.viewMode === 'sites') {
      if (!allowReuse) {
        this.controller.cancelTimelineRequests();
      }
      if (allowReuse && this.sitePageController.canReuse(this.searchQuery)) {
        this.scheduleHistoryScrollRestore('sites');
        this.scheduleVisibleIconResolve();
        return;
      }
      // A background prefetch is already filling this snapshot. Restarting it
      // would drop the in-flight page and make the click wait again.
      if (allowReuse && this.isSiteLoading) {
        return;
      }
      this.loadSiteFirstPage();
      return;
    }
    if (!allowReuse) {
      this.sitePageController.cancel();
    }
    if (allowReuse && this.controller.canReuseTimeline(this.searchQuery)) {
      this.scheduleHistoryScrollRestore('timeline');
      this.scheduleVisibleIconResolve();
      return;
    }
    if (allowReuse && this.isTimelineLoading) {
      return;
    }
    this.loadVisitsProgressively();
  }

  private loadVisitsProgressively(preserveContent: boolean = false, cancelSites: boolean = true): void {
    this.deferredEnterWork.cancel();
    if (cancelSites) {
      this.sitePageController.cancel();
    }
    if (this.shouldHoldEmptySearchResults()) {
      this.clearHistoryViewState();
      return;
    }
    const query = this.searchQuery.trim();
    if (!preserveContent) {
      this.rawVisits = [];
      this.visits = [];
      this.historyTimelineDataSource.replaceGroups([]);
      this.timelineScrollOffset = 0;
    }
    this.controller.loadTimelineFirstPage(
      query,
      HISTORY_INITIAL_RENDER_LIMIT,
      (visits: HistoryVisit[]) => {
        if (this.isActive && query === this.searchQuery.trim()) {
          this.applyLoadedVisits(visits, false);
        }
      }
    );
  }

  private applyLoadedVisits(visits: HistoryVisit[], shouldApplyRetention: boolean): void {
    this.rawVisits = visits.slice();
    this.applyHistoryViewState();
    if (this.viewMode === 'timeline') {
      this.controller.scrollTimelineToStart();
      this.resetTitleActionsElevation();
    }
    this.pruneSelectedVisits();
    this.refreshBookmarkMarkers(this.visits);
    this.refreshHomeShortcutMarkers(this.visits);
    if (this.viewMode === 'timeline') {
      this.scheduleVisibleIconResolve();
    } else {
      this.scheduleInactiveIconResolve('timeline');
    }
    if (shouldApplyRetention) {
      this.applyRetentionPolicyIfNeeded();
    }
    this.prefetchInactiveHistoryMode();
  }

  private clearHistoryViewState(): void {
    this.controller.clearTimelineState();
    this.sitePageController.invalidate();
    this.timelineLoadError = '';
    this.siteLoadError = '';
    this.timelineScrollOffset = 0;
    this.siteScrollOffset = 0;
    this.rawVisits = [];
    this.visits = [];
    this.sites = [];
    this.timelineIconStates = [];
    this.siteIconStates = [];
    this.bookmarkedVisitIds = [];
    this.homeShortcutVisitIds = [];
    this.siteVisibleStartIndex = 0;
    this.siteVisibleEndIndex = 0;
    this.historyTimelineDataSource.replaceGroups([]);
    this.historySiteListDataSource.replaceSites([]);
  }

  private applyHistoryViewState(): void {
    const state: HistoryViewState = this.historyViewModel.buildTimelineViewState(this.rawVisits, this.searchQuery);
    this.visits = state.visits;
    this.historyTimelineDataSource.replaceGroups(state.groups);
    if (this.viewMode === 'timeline') {
      this.scheduleVisibleIconResolve();
    }
  }

  private refreshLoadedHistoryViewState(visits: HistoryVisit[]): number {
    this.rawVisits = visits.slice();
    this.applyHistoryViewState();
    this.refreshBookmarkMarkers(this.visits);
    this.refreshHomeShortcutMarkers(this.visits);
    return this.visits.length;
  }

  private loadNextTimelinePage(): void {
    if (this.viewMode !== 'timeline' || !this.isActive || hasAppResourceText(this.timelineLoadError)) {
      return;
    }
    this.controller.requestNextTimelinePages(
      HISTORY_RENDER_INCREMENT,
      this.visits.length,
      (visits: HistoryVisit[]): number => this.refreshLoadedHistoryViewState(visits)
    );
  }

  private loadSiteFirstPage(preserveContent: boolean = false, cancelTimeline: boolean = true): void {
    this.deferredEnterWork.cancel();
    if (cancelTimeline) {
      this.controller.cancelTimelineRequests();
    }
    if (!preserveContent) {
      this.siteScrollOffset = 0;
      this.sites = [];
      this.historySiteListDataSource.replaceSites([]);
    }
    this.sitePageController.loadFirstPage(
      this.searchQuery,
      HISTORY_INITIAL_RENDER_LIMIT,
      this.buildHistoryManagementBoundary(),
      (sites: HistorySiteAggregate[], append: boolean) => this.applyLoadedSites(sites, append)
    );
  }

  private applyLoadedSites(sites: HistorySiteAggregate[], append: boolean): void {
    if (!this.isActive) {
      return;
    }
    const showingSites = this.viewMode === 'sites';
    if (!append && showingSites) {
      this.resetTitleActionsElevation();
      this.siteScrollOffset = 0;
      this.siteVisibleStartIndex = 0;
      this.siteVisibleEndIndex = 20;
    }
    const siteGroups = this.historyViewModel.buildSiteGroupsFromAggregates(sites);
    this.sites = append ? this.mergeLoadedSites(siteGroups) : siteGroups;
    this.historySiteListDataSource.replaceSites(this.sites);
    this.pruneSelectedSites();
    if (showingSites) {
      this.scheduleVisibleIconResolve();
    } else {
      this.scheduleInactiveIconResolve('sites');
    }
    this.prefetchInactiveHistoryMode();
  }

  private prefetchInactiveHistoryMode(): void {
    if (!this.isActive || this.searchQuery.trim().length > 0 || this.pendingHistoryMutations > 0) {
      return;
    }
    if (this.viewMode !== 'sites' && !this.isSiteLoading &&
      !this.sitePageController.canReuse(this.searchQuery)) {
      this.loadSiteFirstPage(true, false);
    }
    if (this.viewMode !== 'timeline' && !this.isTimelineLoading &&
      !this.controller.canReuseTimeline(this.searchQuery)) {
      this.loadVisitsProgressively(true, false);
    }
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
    if (this.viewMode !== 'sites' || !this.isActive || hasAppResourceText(this.siteLoadError)) {
      return;
    }
    const remainingRows = this.sites.length - this.siteVisibleEndIndex;
    if (remainingRows >= HISTORY_RENDER_PREFETCH_REMAINING_ROWS) {
      return;
    }
    this.sitePageController.loadNextPage(
      HISTORY_RENDER_INCREMENT,
      this.buildHistoryManagementBoundary(),
      (sites: HistorySiteAggregate[], append: boolean) => this.applyLoadedSites(sites, append)
    );
  }

  private resolveTitle(): ResourceStr {
    const selectedCount = this.viewMode === 'sites' ? this.selectedSiteKeys.length : this.selectedVisitIds.length;
    if (this.isSelectionMode) {
      return this.isSessionEphemeral
        ? $r('app.string.history_regular_selected_short', selectedCount)
        : $r('app.string.history_selected_short', selectedCount);
    }
    const filtered = this.searchQuery.trim().length > 0;
    if (this.viewMode === 'sites') {
      if (this.isSessionEphemeral) {
        return filtered
          ? $r('app.string.history_regular_site_count', this.sites.length)
          : $r('app.string.history_regular_by_site');
      }
      return filtered ? $r('app.string.history_site_count', this.sites.length) : $r('app.string.history_by_site');
    }
    if (this.isSessionEphemeral) {
      return filtered
        ? $r('app.string.history_regular_search_count', this.visits.length)
        : $r('app.string.history_regular_title');
    }
    return filtered
      ? $r('app.string.history_search_count', this.visits.length)
      : $r('app.string.app_shortcut_history');
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

  private handleContextAction(visit: HistoryDisplayVisit, actionId: HistoryVisitContextActionId): void {
    if (actionId === 'multi_select') {
      if (this.isSearchMode) {
        return;
      }
      this.runAfterContextMenuDismiss(() => {
        this.enterSelectionMode(visit.id);
      });
      return;
    }
    if (actionId === 'add_bookmark') {
      if (this.isVisitBookmarked(visit.id)) {
        return;
      }
      this.runAfterContextMenuDismiss(() => {
        this.addVisitToBookmarks(visit);
      });
      return;
    }
    if (actionId === 'remove_bookmark') {
      this.runAfterContextMenuDismiss(() => {
        this.removeVisitFromBookmarks(visit);
      });
      return;
    }
    if (actionId === 'add_to_home' || actionId === 'remove_from_home') {
      this.runAfterContextMenuDismiss(() => {
        this.toggleVisitHomeShortcut(visit);
      });
      return;
    }
    if (actionId === 'share') {
      this.runAfterContextMenuDismiss(() => {
        this.shareVisit(visit);
      });
      return;
    }
    if (actionId === 'copy_link') {
      this.runAfterContextMenuDismiss(() => {
        this.copyVisitUrl(visit);
      });
      return;
    }
    if (actionId === 'details') {
      this.runAfterContextMenuDismiss(() => {
        this.showVisitDetails(visit);
      });
      return;
    }
    if (actionId === 'open') {
      this.runAfterContextMenuDismiss(() => {
        this.openVisit(visit);
      });
      return;
    }
    if (actionId === 'open_new_tab') {
      this.runAfterContextMenuDismiss(() => {
        this.openVisitWithIntent(visit, 'new_tab');
      });
      return;
    }
    if (actionId === 'open_background') {
      this.runAfterContextMenuDismiss(() => {
        this.openVisitWithIntent(visit, 'background_tab');
      });
      return;
    }
    if (actionId === 'delete_site') {
      this.runAfterContextMenuDismiss(() => {
        this.confirmDeleteSiteForVisit(visit);
      });
      return;
    }
    if (actionId === 'delete') {
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
      this.showDialog($r('app.string.history_cannot_open'), this.stringifyError(error as Error));
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

  private updateTitleActionsElevationFromOffset(offset: number): void {
    const nextElevated = Number.isFinite(offset) && offset > HISTORY_TITLE_ACTION_ELEVATE_OFFSET;
    if (this.titleActionsElevated === nextElevated) {
      return;
    }
    this.titleActionsElevated = nextElevated;
  }

  private resetTitleActionsElevation(): void {
    if (!this.titleActionsElevated) {
      return;
    }
    this.titleActionsElevated = false;
  }

  private shouldShowHistoryEmptyState(mode: HistoryViewMode): boolean {
    if (this.shouldHoldEmptySearchResults()) {
      return false;
    }
    if ((mode === 'timeline' ? this.isTimelineLoading : this.isSiteLoading) ||
      hasAppResourceText(this.resolveHistoryLoadError())) {
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
    this.resetTitleActionsElevation();
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
    if (this.drilldownHost.length === 0 && this.drilldownReturnQuery.length === 0 &&
      this.drilldownReturnMode === 'timeline') {
      return;
    }
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
      this.showDialog($r('app.string.history_bookmark_added'), $r('app.string.history_already_bookmarked'));
      return;
    }
    this.openBookmarkFolderSelection([visit]);
  }

  private shareVisit(visit: HistoryDisplayVisit): void {
    try {
      this.historyFeature.authorizeShareForManagement(this.buildHistoryManagementBoundary());
    } catch (error) {
      this.showDialog($r('app.string.history_cannot_share'), this.stringifyError(error as Error));
      return;
    }
    this.webPageShareService.shareWebPage(this.getPickerContext(), {
      title: visit.title,
      url: visit.url
    }).catch((error: Error) => {
      this.showDialog($r('app.string.history_share_failed'), $r('app.string.history_share_failed_detail', this.stringifyError(error)));
    });
  }

  private copyVisitUrl(visit: HistoryDisplayVisit): void {
    try {
      this.historyFeature.authorizeShareForManagement(this.buildHistoryManagementBoundary());
    } catch (error) {
      this.showDialog($r('app.string.history_cannot_copy'), this.stringifyError(error as Error));
      return;
    }
    this.copyTextToClipboard(visit.url, $r('app.string.history_copy_empty'), $r('app.string.history_link_copied_period'));
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
      title: $r('app.string.history_delete_site_menu'),
      message: $r('app.string.history_delete_site_count_confirm', resolveAppResourceText(localizeHistoryHost(site.host)), site.visitCount),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.settings_account_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.settings_delete'),
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
    this.showNativeToast($r('app.string.history_site_deleted'));
    this.historyFeature.deleteVisitsByHostForManagement(host, this.buildHistoryManagementBoundary())
      .then((removed: number) => {
        this.finishTimelineDeletion(deletionTransactionId, removed > 0);
      })
      .catch((error: Error) => {
        this.finishTimelineDeletion(deletionTransactionId, false);
        this.showDialog($r('app.string.history_delete_failed'), $r('app.string.history_delete_site_failed_detail', this.stringifyError(error)));
      });
  }

  private confirmDeleteVisit(visit: HistoryDisplayVisit): void {
    showCenteredAlertDialog({
      title: $r('app.string.history_delete_title'),
      message: this.historyViewModel.buildDeleteVisitMessage(visit),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.settings_account_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.settings_delete'),
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
    this.showNativeToast($r('app.string.history_deleted'));
    this.historyFeature.deleteVisitsByIdsForManagement(deletingIds, this.buildHistoryManagementBoundary())
      .then((removed: number) => {
        if (removed <= 0) {
          this.finishTimelineDeletion(deletionTransactionId, false);
          this.showDialog($r('app.string.history_delete_failed'), $r('app.string.history_missing'));
          return;
        }
        this.finishTimelineDeletion(deletionTransactionId, true);
      })
      .catch((error: Error) => {
        this.finishTimelineDeletion(deletionTransactionId, false);
        this.showDialog($r('app.string.history_delete_failed'), $r('app.string.history_delete_failed_detail', this.stringifyError(error)));
      });
  }

  private enterSelectionMode(initialVisitId?: string): void {
    if (this.isSearchMode || this.isViewModeEmpty(this.viewMode) || this.pendingHistoryMutations > 0) {
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
    // A new empty array is a different state value and refreshes every row that
    // receives it. Tab switches call this even when nothing is selected.
    if (!this.isSelectionMode && this.selectedVisitIds.length === 0 &&
      this.selectedSiteKeys.length === 0 && this.contextMenuVisitId.length === 0) {
      return;
    }
    if (this.isSelectionMode) {
      this.isSelectionMode = false;
    }
    if (this.selectedVisitIds.length > 0) {
      this.selectedVisitIds = [];
    }
    if (this.selectedSiteKeys.length > 0) {
      this.selectedSiteKeys = [];
    }
    if (this.contextMenuVisitId.length > 0) {
      this.contextMenuVisitId = '';
    }
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
        this.showNativeToast(result.added ? $r('app.string.history_home_added') : $r('app.string.history_home_removed'));
      })
      .catch((error: Error) => {
        this.showDialog($r('app.string.history_action_failed'), $r('app.string.history_home_failed_detail', this.stringifyError(error)));
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
    this.pendingHistoryMutations += 1;
    this.sitePageController.beginMutation();
    const removingIds = new Set<string>(visitIds);
    const transaction: HistoryTimelineDeletionTransaction = this.controller.beginTimelineDeletion(visitIds);
    this.rawVisits = transaction.visits;
    this.applyHistoryViewState();
    this.pruneSelectedVisits();
    this.bookmarkedVisitIds = this.bookmarkedVisitIds.filter((id: string) => !removingIds.has(id));
    this.homeShortcutVisitIds = this.homeShortcutVisitIds.filter((id: string) => !removingIds.has(id));
    if (this.timelineIconStates.length > 0) {
      const nextTimelineIcons = this.timelineIconStates
        .filter((item: SiteIconListRenderState) => !removingIds.has(item.id));
      if (nextTimelineIcons.length !== this.timelineIconStates.length) {
        this.timelineIconStates = nextTimelineIcons;
      }
    }
    this.pruneSelectedSites();
    if (removingIds.has(this.contextMenuVisitId)) {
      this.contextMenuVisitId = '';
    }
    return transaction.id;
  }

  private finishTimelineDeletion(transactionId: number, committed: boolean): void {
    this.pendingHistoryMutations = Math.max(0, this.pendingHistoryMutations - 1);
    this.sitePageController.finishMutation();
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
    if (this.siteIconStates.length > 0) {
      const removingKeys = new Set<string>();
      this.sites.forEach((site: HistorySiteGroup) => {
        if (removingHosts.has(site.host)) {
          removingKeys.add(site.key);
        }
      });
      const nextSiteIcons = this.siteIconStates.filter((item: SiteIconListRenderState) =>
        !removingKeys.has(item.id));
      if (nextSiteIcons.length !== this.siteIconStates.length) {
        this.siteIconStates = nextSiteIcons;
      }
    }
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
      title: $r('app.string.history_delete_title'),
      message: $r('app.string.history_delete_many', selectedCount),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.settings_account_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.settings_delete'),
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
    this.showNativeToast($r('app.string.history_deleted_count', uniqueDeletingIds.length));
    this.historyFeature.deleteVisitsByIdsForManagement(uniqueDeletingIds, this.buildHistoryManagementBoundary())
      .then((removed: number) => {
        this.finishTimelineDeletion(deletionTransactionId, removed > 0);
      })
      .catch((error: Error) => {
        this.finishTimelineDeletion(deletionTransactionId, false);
        this.showDialog($r('app.string.history_delete_failed'), $r('app.string.history_delete_failed_detail', this.stringifyError(error)));
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
    this.showNativeToast($r('app.string.history_deleted_sites', uniqueDeletingHosts.length));
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
          this.showDialog($r('app.string.history_delete_failed'), $r('app.string.history_delete_failed_detail', deletionErrorMessage));
          return;
        }
        this.finishTimelineDeletion(deletionTransactionId, removed.some((count: number) => count > 0));
      });
  }

  private buildHistorySelectionMoreMenuItems(): FloatingSelectionToolbarMenuItem[] {
    const includeRemoveBookmarks = this.viewMode === 'timeline';
    const selectedCount = this.viewMode === 'sites' ? this.selectedSiteKeys.length : this.selectedVisitIds.length;
    const plannedItems = planHistorySelectionMoreMenu(this.viewMode, selectedCount, includeRemoveBookmarks).items;
    const menuItems: FloatingSelectionToolbarMenuItem[] = [];
    plannedItems.forEach((item: HistorySelectionMoreMenuItem) => {
      const actionId = item.id;
      const title = item.title;
      menuItems.push({
        value: title,
        action: (): void => {
          this.runHistorySelectionMoreAction(actionId);
        }
      });
    });
    return menuItems;
  }

  private runHistorySelectionMoreAction(actionId: HistorySelectionMoreActionId): void {
    const selectedCount = this.viewMode === 'sites' ? this.selectedSiteKeys.length : this.selectedVisitIds.length;
    if (selectedCount <= 0) {
      this.showNativeToast(HISTORY_SELECTION_MORE_EMPTY_MESSAGE);
      return;
    }
    if (actionId === 'copy_links') {
      this.copySelectedVisitUrls();
      return;
    }
    if (actionId === 'add_bookmarks') {
      this.addSelectedVisitsToBookmarks();
      return;
    }
    if (actionId === 'remove_bookmarks') {
      this.removeSelectedVisitsFromBookmarks();
      return;
    }
    if (actionId === 'share_links') {
      this.shareSelectedVisitUrls();
      return;
    }
    if (actionId === 'delete_selected_sites') {
      this.confirmDeleteSelectedVisits();
    }
  }

  private showSelectionMoreMenu(): void {
    const selectedCount = this.viewMode === 'sites' ? this.selectedSiteKeys.length : this.selectedVisitIds.length;
    if (selectedCount <= 0) {
      this.showNativeToast(HISTORY_SELECTION_MORE_EMPTY_MESSAGE);
      return;
    }
    const sheets: HistorySelectionMoreAction[] = [];
    if (this.viewMode === 'timeline') {
      const copyAction: HistorySelectionMoreAction = {
        airaIconId: 'browser.toolbar.copyLink',
        title: $r('app.string.history_batch_copy'),
        enabled: true,
        action: () => {
          this.requestCloseOverlayMenu();
          this.copySelectedVisitUrls();
        }
      };
      sheets.push(copyAction);
      const bookmarkAction: HistorySelectionMoreAction = {
        airaIconId: 'browser.toolbar.addBookmark',
        title: $r('app.string.history_batch_add_bookmarks'),
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
          title: $r('app.string.history_batch_remove_bookmarks'),
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
        title: $r('app.string.history_batch_share'),
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
        title: $r('app.string.history_delete_selected_sites'),
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
    this.copyTextToClipboard(uniqueUrls.join('\n'), $r('app.string.history_copy_empty'), $r('app.string.history_copied_many', uniqueUrls.length));
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
      this.showNativeToast($r('app.string.history_already_all_bookmarked'));
      return;
    }
    this.openBookmarkFolderSelection(pendingVisits);
  }

  private removeVisitFromBookmarks(visit: HistoryDisplayVisit): void {
    if (!this.bookmarkManagementFeature.hasBookmarkForUrl(visit.url)) {
      this.refreshBookmarkMarkers(this.visits);
      this.showNativeToast($r('app.string.history_not_bookmarked'));
      return;
    }
    this.unmarkVisitsBookmarkedByUrls([visit]);
    this.bookmarkManagementFeature.deleteRegularBookmarksByUrls([visit.url])
      .then((removedCount: number) => {
        this.showNativeToast(removedCount > 0 ? $r('app.string.history_bookmark_removed') : $r('app.string.history_not_bookmarked'));
      })
      .catch((error: Error) => {
        this.refreshBookmarkMarkers(this.visits);
        this.showDialog($r('app.string.history_remove_bookmark_failed'), $r('app.string.history_remove_bookmark_failed_detail', this.stringifyError(error)));
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
      this.showNativeToast($r('app.string.history_selected_not_bookmarked'));
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
        this.showNativeToast(removedCount > 0 ? $r('app.string.history_removed_bookmark_count', removedCount) : $r('app.string.history_selected_not_bookmarked'));
      })
      .catch((error: Error) => {
        this.refreshBookmarkMarkers(this.visits);
        this.showDialog($r('app.string.history_remove_bookmark_failed'), $r('app.string.history_batch_remove_failed_detail', this.stringifyError(error)));
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
        this.showNativeToast(addedCount > 0 ? $r('app.string.history_added_bookmark_count', addedCount) : $r('app.string.history_already_all_bookmarked'));
      })
      .catch((error: Error) => {
        this.refreshBookmarkMarkers(this.visits);
        this.showDialog($r('app.string.history_batch_add_failed'), $r('app.string.history_batch_add_failed_detail', this.stringifyError(error)));
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
    this.editSingleBookmark = visits.length === 1;
    this.singleBookmarkSessionVersion += 1;
    if (this.editSingleBookmark) {
      this.singleBookmarkAddCoordinator.begin(visits[0].title, visits[0].url);
    } else {
      this.singleBookmarkAddCoordinator.cancel();
      this.singleBookmarkDraft = createBookmarkAddDraft();
    }
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
    if (this.editSingleBookmark && this.singleBookmarkDraft.saving) {
      return;
    }
    this.singleBookmarkAddCoordinator.cancel();
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
        this.showDialog($r('app.string.history_cannot_add_bookmark'), $r('app.string.history_no_bookmark_folder'));
        return;
      }
      this.bookmarkFolderSelectionOptions = options;
      if (this.editSingleBookmark) { this.singleBookmarkAddCoordinator.refreshFolders(); }
      this.bookmarkFolderSelectionPreparing = false;
    } catch (error) {
      if (this.bookmarkFolderSelectionOverlayGeneration !== overlayGeneration ||
        !this.bookmarkFolderSelectionVisible) {
        return;
      }
      this.bookmarkFolderSelectionPreparing = false;
      this.showDialog($r('app.string.history_load_failed'), $r('app.string.history_folder_load_failed_detail', this.stringifyError(error as Error)));
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
      if (this.editSingleBookmark) { this.singleBookmarkAddCoordinator.refreshFolders(); }
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
      this.showDialog($r('app.string.history_cannot_share'), this.stringifyError(error as Error));
      return;
    }
    const uniqueVisits = this.deduplicateDisplayVisitsByUrl(visits);
    const summaryTitle = uniqueVisits.length === 1
      ? uniqueVisits[0].title
      : resolveAppResourceText($r('app.string.history_share_many'), uniqueVisits.length);
    const summaryUrls = uniqueVisits.map((visit: HistoryDisplayVisit) => visit.url).join('\n');
    this.webPageShareService.sharePlainText(this.getPickerContext(), summaryTitle, summaryUrls).catch((error: Error) => {
      this.showDialog(
        $r('app.string.history_share_failed'),
        $r('app.string.history_batch_share_failed_detail', this.stringifyError(error))
      );
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
    if (this.isTransferBusy || this.pendingHistoryMutations > 0) {
      return;
    }
    this.captureHistoryScrollOffset();
    this.clearDrilldownState();
    this.isSearchMode = false;
    this.searchQuery = '';
    this.viewMode = 'sites';
    this.loadCurrentModeFirstPage(true);
    // Selection can start before the first site page arrives.
    this.isSelectionMode = true;
    this.contextMenuVisitId = '';
    this.showNativeToast($r('app.string.history_select_sites_then_delete'));
  }

  private isViewModeEmpty(mode: HistoryViewMode): boolean {
    if (mode === 'sites') {
      return this.sites.length === 0;
    }
    return this.visits.length === 0;
  }

  private getEmptyTitle(mode: HistoryViewMode = this.viewMode): ResourceStr {
    if (this.isSearchMode) {
      return this.searchQuery.trim().length > 0 ? $r('app.string.history_no_match') : $r('app.string.history_search');
    }
    return this.searchQuery.trim().length > 0 ? $r('app.string.history_no_match') : $r('app.string.history_empty');
  }

  private getEmptyMessage(mode: HistoryViewMode = this.viewMode): ResourceStr {
    if (this.isSearchMode) {
      return this.searchQuery.trim().length > 0 ? $r('app.string.history_try_another') : $r('app.string.history_search_hint');
    }
    return this.searchQuery.trim().length > 0 ? $r('app.string.history_try_another') : $r('app.string.history_empty_message');
  }

  private switchViewMode(mode: HistoryViewMode): void {
    if (this.viewMode === mode) {
      return;
    }
    this.captureHistoryScrollOffset();
    this.controller.resetTimelineSwipeActions();
    this.viewMode = mode;
    this.clearDrilldownState();
    this.exitSelectionMode();
    this.resetTitleActionsElevation();
    this.loadCurrentModeFirstPage(true);
  }

  private captureHistoryScrollOffset(): void {
    try {
      if (this.viewMode === 'sites') {
        this.siteScrollOffset = this.historySiteScroller.currentOffset().yOffset;
      } else {
        this.timelineScrollOffset = this.controller.getTimelineScroller().currentOffset().yOffset;
      }
    } catch (_error) {
    }
  }

  private cancelHistoryScrollRestore(): void {
    if (this.scrollRestoreTimer >= 0) {
      clearTimeout(this.scrollRestoreTimer);
      this.scrollRestoreTimer = -1;
    }
  }

  private scheduleHistoryScrollRestore(mode: HistoryViewMode): void {
    const offset = mode === 'sites' ? this.siteScrollOffset : this.timelineScrollOffset;
    if (!(offset > 0)) {
      return;
    }
    this.cancelHistoryScrollRestore();
    this.scrollRestoreTimer = setTimeout(() => {
      this.scrollRestoreTimer = -1;
      if (!this.isActive || this.viewMode !== mode) {
        return;
      }
      const offset = mode === 'sites' ? this.siteScrollOffset : this.timelineScrollOffset;
      // The list is created only after its rows exist. scrollTo(0) at that moment
      // lands before contentStartOffset settles and pulls the first rows to the
      // physical top, above the floating header. A zero offset is already the
      // natural start, so only a real previous scroll is restored.
      if (!(offset > 0)) {
        return;
      }
      try {
        if (mode === 'sites') {
          this.historySiteScroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
        } else {
          this.controller.getTimelineScroller().scrollTo({ xOffset: 0, yOffset: offset, animation: false });
        }
        this.updateTitleActionsElevationFromOffset(offset);
      } catch (_error) {
      }
    }, 0);
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
        this.showDialog($r('app.string.history_stress_failed'), $r('app.string.history_stress_failed_detail', this.stringifyError(error)));
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
    let importStage = $r('app.string.history_import_stage_picker');
    this.pickOpenUri()
      .then((uri: string | undefined) => {
        if (uri === undefined) {
          return Promise.resolve(undefined);
        }
        importStage = $r('app.string.history_import_stage_read');
        return this.readTextFromUri(uri)
          .then((payload: string) => {
            importStage = $r('app.string.history_import_stage_write');
            return this.historyFeature.importVisitsForManagement(payload, this.buildHistoryManagementBoundary());
          });
      })
      .then((result: HistoryImportResult | undefined) => {
        if (result === undefined) {
          return;
        }
        this.reloadVisits();
        this.showDialog($r('app.string.history_import_success'), $r('app.string.history_import_summary', result.importedCount, result.skippedCount));
      })
      .catch((error: Error) => {
        this.showDialog($r('app.string.history_import_failed'), $r('app.string.history_import_failed_detail', resolveAppResourceText(importStage), this.stringifyError(error)));
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
          this.showDialog($r('app.string.history_export_success'), $r('app.string.history_export_done'));
        });
      })
      .catch((error: Error) => {
        this.showDialog($r('app.string.history_export_failed'), $r('app.string.history_export_failed_detail', this.stringifyError(error)));
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
    this.resolveIconsForMode(this.viewMode);
  }

  private resolveIconsForMode(mode: HistoryViewMode): void {
    this.siteIconListPresenter.resolveTargets(
      this.buildIconTargets(mode),
      (result: SiteIconListResolvedIcon): void => {
        if (result.uri.length > 0) {
          this.applyResolvedSiteIcon(mode, result);
        }
      }
    );
  }

  private buildIconTargets(mode: HistoryViewMode): HistoryIconStateTarget[] {
    if (mode === 'sites') {
      const endIndex = this.siteVisibleEndIndex > this.siteVisibleStartIndex ?
        this.siteVisibleEndIndex : this.siteVisibleStartIndex + 12;
      return this.historySiteListDataSource
        .getIconTargetsAround(this.siteVisibleStartIndex, endIndex, 8)
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

  private scheduleInactiveIconResolve(mode: HistoryViewMode): void {
    this.cancelInactiveIconResolve();
    this.inactiveIconResolveTimer = setTimeout(() => {
      this.inactiveIconResolveTimer = -1;
      if (!this.isActive || this.viewMode === mode || this.searchQuery.trim().length > 0) {
        return;
      }
      this.resolveIconsForMode(mode);
    }, HISTORY_VISIBLE_ICON_RESOLVE_DELAY_MS);
  }

  private cancelInactiveIconResolve(): void {
    if (this.inactiveIconResolveTimer >= 0) {
      clearTimeout(this.inactiveIconResolveTimer);
      this.inactiveIconResolveTimer = -1;
    }
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

  private applyDomainIconUpdate(result: SiteIconListResolvedIcon): void {
    if (this.sites.some((site: HistorySiteGroup) => site.key === result.id)) {
      this.applyResolvedSiteIcon('sites', result);
    }
    if (this.visits.some((visit: HistoryDisplayVisit) => visit.id === result.id)) {
      this.applyResolvedSiteIcon('timeline', result);
    }
  }

  private applyResolvedSiteIcon(mode: HistoryViewMode, result: SiteIconListResolvedIcon): void {
    const current = mode === 'sites' ? this.siteIconStates : this.timelineIconStates;
    const next = this.siteIconListPresenter.applyResolvedIcon(current, result);
    if (next === current) {
      return;
    }
    if (mode === 'sites') {
      this.siteIconStates = next;
      return;
    }
    this.timelineIconStates = next;
  }

  private resolveHistoryPixelMapAfterUriFailure(
    mode: HistoryViewMode,
    target: SiteIconListTarget,
    currentUri: string,
    sourceRevision: number
  ): void {
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      target,
      currentUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(mode, result)
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

  private copyTextToClipboard(value: string, emptyMessage: ResourceStr, successMessage: ResourceStr): void {
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
          this.showNativeToast($r('app.string.ui_copy_failed'));
        });
    } catch (_error) {
      this.showNativeToast($r('app.string.ui_copy_failed'));
    }
  }

  private showNativeToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
    }
  }

  private showDialog(title: ResourceStr, message: ResourceStr): void {
    showCenteredAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      confirm: {
        value: $r('app.string.settings_pro_got_it'),
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
    return serialized.length > 0 ? serialized : resolveAppResourceText($r('app.string.ui_unknown_error'));
  }
}
