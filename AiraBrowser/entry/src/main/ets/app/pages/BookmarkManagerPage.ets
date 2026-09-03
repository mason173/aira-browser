import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../components/common/CenteredDialogSurface';
import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import router from '@ohos.router';
import vibrator from '@ohos.vibrator';
import {
  BookmarkNode,
  BookmarkStorageScope,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import { BrowserAppUrlOpenIntent } from '../../core/browser/BrowserAppUrlOpenCoordinator';
import { AiraBookmarkImportApplyResult } from '../../common/models/AiraSyncModels';
import {
  sharedAiraLocalBookmarkOverviewCacheRepository,
  sharedBookmarkFolderCountCacheRepository,
  sharedBookmarkRepository,
  sharedBrowserDatabase,
  sharedShortcutRepository
} from '../bootstrap/BrowserAppRuntime';
import { BookmarksFeature } from '../../features/bookmarks/BookmarksFeature';
import {
  BookmarkManagementBoundary,
  BookmarkManagementFeature
} from '../../features/bookmarks/BookmarkManagementFeature';
import { BookmarkListDataSource, BookmarkListIconTarget } from '../../features/bookmarks/BookmarkListDataSource';
import { BookmarkMutationService } from '../../services/bookmarks/BookmarkMutationService';
import {
  SyncOperationProgressController,
  SyncOperationProgressUiState
} from '../../core/sync/SyncOperationProgressController';
import {
  BookmarkFolderOptionView,
  BookmarkFolderSelectionViewModel
} from '../../core/browser/BookmarkFolderSelectionViewModel';
import {
  BookmarkFolderCountState,
  BookmarkFolderCountViewModel
} from '../../core/bookmarks/BookmarkFolderCountViewModel';
import { BookmarkFolderOptimisticCreateViewModel } from '../../core/bookmarks/BookmarkFolderOptimisticCreateViewModel';
import { BookmarkManagerHeaderActionViewModel } from '../../core/bookmarks/BookmarkManagerHeaderActionViewModel';
import {
  BookmarkManagerSearchResult,
  BookmarkManagerSearchState,
  BookmarkManagerSearchViewModel
} from '../../core/bookmarks/BookmarkManagerSearchViewModel';
import { BookmarkOpenActionViewModel } from '../../core/bookmarks/BookmarkOpenActionViewModel';
import {
  BookmarkRecordActionId,
  BookmarkRecordActionView,
  BookmarkRecordActionViewModel
} from '../../core/bookmarks/BookmarkRecordActionViewModel';
import {
  HomeShortcutToggleResult,
  HomeShortcutToggleService
} from '../../services/shortcuts/HomeShortcutToggleService';
import { WebPageShareService } from '../../services/share/WebPageShareService';
import {
  SiteIconListPresenter,
  SiteIconListRenderState,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../core/siteicons/SiteIconListPresenter';
import { requestOpenBrowserUrlWithRouteParams } from '../../core/navigation/BrowserNativeNavigationRequestCenter';
import {
  BrowserPrivateBoundaryNavigationService,
  BrowserPrivateBoundaryRouteParams
} from '../../core/browser/BrowserPrivateBoundaryNavigationService';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID,
  isBookmarkRootNodeId
} from '../../data/repositories/BookmarkRepositoryCore';
import {
  BrowserBookmarkScopeRouteParams,
  BrowserBookmarkScopeService
} from '../../core/browser/BrowserBookmarkScopeService';
import { BookmarkRecordList } from '../components/bookmarks/BookmarkRecordList';
import {
  BookmarkManagerCreateFolderDialog,
  BookmarkManagerEditNodeDialog
} from '../components/bookmarks/BookmarkManagerDialogs';
import { readBookmarkTextFromUri } from '../../services/bookmarks/BookmarkHtmlTransferApplicationService';
import { BookmarkImportResultDialog } from '../components/bookmarks/BookmarkImportResultDialog';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import {
  ManagementHdsMenuAction,
  ManagementHdsScaffold
} from '../components/common/ManagementHdsScaffold';
import { AppEmptyState } from '../components/common/AppEmptyState';
import { FloatingSelectionToolbar } from '../components/common/FloatingSelectionToolbar';
import { SyncOperationProgressDialog } from '../components/sync/SyncOperationProgressDialog';
import {
  BookmarkMoveFolderSelectionResult,
  BookmarkMoveFolderSelectionSheet
} from '../components/bookmarks/BookmarkMoveFolderSelectionSheet';
import { BookmarkRootTabs } from '../components/bookmarks/BookmarkRootTabs';
import { BookmarkManagerImmersiveHost, BookmarkManagerImmersiveLayoutContext } from '../components/bookmarks/BookmarkManagerImmersiveHost';
import { BOOKMARK_MANAGER_ROUTE, BROWSER_SHELL_ROUTE } from '../router/AppRoutes';
import { BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY } from '../../core/browser/BrowserWindowAvoidAreaCoordinator';

const BOOKMARK_CONTEXT_MENU_DISMISS_DELAY_MS: number = 240;
const BOOKMARK_IMPORT_PROGRESS_FRAME_DELAY_MS: number = 80;
const BOOKMARK_FOLDER_COUNT_REFRESH_DELAY_MS: number = 80;
const BOOKMARK_VISIBLE_AUX_REFRESH_DELAY_MS: number = 96;
const BOOKMARK_SELECTION_TOOLBAR_FLOAT_BOTTOM: number = 36;
const BOOKMARK_MOVE_TO_FOLDER_END_INDEX: number = 2147483647;
const BOOKMARK_MOVE_FOLDER_TARGET_PREPARE_DELAY_MS: number = 16;

interface BookmarkManagerRouteParams {
  folderId?: string;
  folderTitle?: string;
  dataScope?: string;
  privacyMode?: string;
  boundarySource?: string;
  bookmarkScope?: string;
}
@Entry({ useSharedStorage: true })
@Component
struct BookmarkManagerPage {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private bookmarksFeature: BookmarksFeature = new BookmarksFeature(sharedBookmarkRepository);
  private bookmarkListDataSource: BookmarkListDataSource = new BookmarkListDataSource();
  private bookmarkManagementFeature: BookmarkManagementFeature = new BookmarkManagementFeature(
    this.bookmarksFeature,
    new BookmarkMutationService(sharedBookmarkRepository, sharedBrowserDatabase)
  );
  private homeShortcutToggleService: HomeShortcutToggleService = new HomeShortcutToggleService(sharedShortcutRepository);
  private webPageShareService: WebPageShareService = new WebPageShareService();
  private privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService = new BrowserPrivateBoundaryNavigationService();
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  private bookmarkScopeService: BrowserBookmarkScopeService = new BrowserBookmarkScopeService();
  private bookmarkFolderSelectionViewModel: BookmarkFolderSelectionViewModel = new BookmarkFolderSelectionViewModel();
  private bookmarkFolderCountViewModel: BookmarkFolderCountViewModel = new BookmarkFolderCountViewModel();
  private bookmarkFolderOptimisticCreateViewModel: BookmarkFolderOptimisticCreateViewModel = new BookmarkFolderOptimisticCreateViewModel();
  private bookmarkManagerHeaderActionViewModel: BookmarkManagerHeaderActionViewModel =
    new BookmarkManagerHeaderActionViewModel();
  private bookmarkManagerSearchViewModel: BookmarkManagerSearchViewModel =
    new BookmarkManagerSearchViewModel(this.bookmarkManagementFeature);
  private bookmarkOpenActionViewModel: BookmarkOpenActionViewModel = new BookmarkOpenActionViewModel();
  private bookmarkRecordActionViewModel: BookmarkRecordActionViewModel = new BookmarkRecordActionViewModel();
  private bookmarkListScroller: Scroller = new Scroller();
  private bookmarkNodes: BookmarkNode[] = [];
  @State bookmarkNodeCount: number = 0;
  @State currentFolderId: string = '';
  @State currentFolderTitle: string = '书签管理';
  @State private selectedRootId: string = BOOKMARK_TOOLBAR_ROOT_ID;
  @State message: string = '';
  @State newFolderTitle: string = '';
  @State editingNodeId: string = '';
  @State editingNodeType: string = 'bookmark';
  @State editingTitle: string = '';
  @State editingUrl: string = '';
  @State editingIconPath: string = '';
  @State isSelectionMode: boolean = false;
  @State selectedNodeIds: string[] = [];
  @State isTransferBusy: boolean = false;
  @State iconStates: SiteIconListRenderState[] = [];
  @State homeShortcutNodeIds: string[] = [];
  @State private moveFolderSheetVisible: boolean = false;
  @State private moveFolderTargetOptions: BookmarkFolderOptionView[] = [];
  @State private pendingMoveNodeIds: string[] = [];
  @State private moveFolderSheetMessage: string = '';
  @State private moveFolderTargetPreparing: boolean = false;
  @State private isInitialBookmarkLoadPending: boolean = true;
  @State private folderBookmarkCountState: BookmarkFolderCountState =
    this.bookmarkFolderCountViewModel.createInitialState();
  @State private bookmarkSearchState: BookmarkManagerSearchState =
    this.bookmarkManagerSearchViewModel.createInitialState();
  private bookmarkVisibleStartIndex: number = 0;
  private bookmarkVisibleEndIndex: number = 20;
  private homeShortcutCache: ShortcutRecord[] = [];
  private folderBookmarkCountRefreshTimer: number = -1;
  private folderBookmarkCountRefreshGeneration: number = 0;
  private visibleAuxRefreshTimer: number = -1;
  private visibleAuxRefreshGeneration: number = 0;
  private moveFolderTargetPrepareTimer: number = -1;
  private moveFolderTargetPrepareGeneration: number = 0;
  @State pressedNodeId: string = '';
  @State contextMenuNodeId: string = '';
  @State private bookmarkTransferTitle: string = '';
  @State private bookmarkTransferSubtitle: string = '';
  @State private bookmarkTransferProgress: number = 0;
  @State private bookmarkTransferInProgress: boolean = false;
  @State private bookmarkTransferDetailsText: string = '';
  @State private bookmarkTransferDetailOpacity: number = 1;
  @State private bookmarkImportResultSummary: string = '';
  @State private bookmarkImportResultBatchId: string = '';
  @State private bookmarkImportResultFolderCount: number = 0;
  @State private bookmarkImportResultBookmarkCount: number = 0;
  @State private bookmarkImportResultDuplicateCount: number = 0;
  @State private bookmarkImportResultSkippedCount: number = 0;
  @State private routeDataScope: string = '';
  @State private routePrivacyMode: string = '';
  @State private routeBoundarySource: string = '';
  @State private bookmarkScope: BookmarkStorageScope = 'regular';
  @State isSessionEphemeral: boolean = false;
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private topSafeInsetVp: number = 0;
  private createFolderDialogController: CustomDialogController = new CustomDialogController({
    builder: BookmarkManagerCreateFolderDialog({
      folderTitle: $newFolderTitle,
      confirm: (title: string) => {
        this.confirmCreateFolder(title);
      }
    }),
    customStyle: true,
    autoCancel: true
  });
  private editNodeDialogController: CustomDialogController = new CustomDialogController({
    builder: BookmarkManagerEditNodeDialog({
      nodeTitle: $editingTitle,
      nodeUrl: $editingUrl,
      nodeType: $editingNodeType,
      iconPath: $editingIconPath,
      confirm: () => {
        this.confirmEditNode();
      }
    }),
    customStyle: true,
    autoCancel: true
  });
  private bookmarkTransferProgressDialogOpen: boolean = false;
  private bookmarkTransferProgressDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncOperationProgressDialog({
      inProgress: $bookmarkTransferInProgress,
      title: $bookmarkTransferTitle,
      subtitle: $bookmarkTransferSubtitle,
      progress: $bookmarkTransferProgress,
      details: $bookmarkTransferDetailsText,
      detailOpacity: $bookmarkTransferDetailOpacity
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: true,
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      if (!this.bookmarkTransferInProgress) {
        dismissDialogAction.dismiss();
      }
    }
  });
  private bookmarkImportResultDialogController: CustomDialogController = new CustomDialogController({
    builder: BookmarkImportResultDialog({
      summary: $bookmarkImportResultSummary,
      importedFolderCount: $bookmarkImportResultFolderCount,
      importedBookmarkCount: $bookmarkImportResultBookmarkCount,
      duplicateCount: $bookmarkImportResultDuplicateCount,
      skippedNodeCount: $bookmarkImportResultSkippedCount
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: true
  });
  private bookmarkTransferProgressController: SyncOperationProgressController = new SyncOperationProgressController(
    (state: SyncOperationProgressUiState): void => {
      this.bookmarkTransferTitle = state.title;
      this.bookmarkTransferSubtitle = state.subtitle;
      this.bookmarkTransferProgress = state.progress;
      this.bookmarkTransferInProgress = state.inProgress;
      this.bookmarkTransferDetailsText = state.details;
      this.bookmarkTransferDetailOpacity = state.detailOpacity;
    },
    (): boolean => this.bookmarkTransferProgressDialogOpen,
    (): void => {
      this.openBookmarkTransferProgressDialog();
    },
    (): void => {
      this.closeBookmarkTransferProgressDialog();
    },
    (title: string, subtitle: string): void => {
      this.showBookmarkTransferResultDialog(title, subtitle);
    }
  );

  aboutToAppear(): void {
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildVisibleBookmarkIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
    this.resetAndReload();
  }

  aboutToDisappear(): void {
    this.cancelScheduledFolderBookmarkCountsRefresh();
    this.cancelScheduledVisibleAuxRefresh();
    this.siteIconListPresenter.dispose();
    this.cancelScheduledMoveFolderTargetPreparation();
    this.bookmarkTransferProgressController.dispose();
  }

  onBackPress(): boolean {
    if (this.bookmarkSearchState.isSearchMode) {
      this.exitBookmarkSearchMode();
      return true;
    }
    if (this.isSelectionMode) {
      this.exitSelectionMode();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      ManagementHdsScaffold({
        title: this.resolveTitle(),
        backIconKind: this.resolveBackIconKind(),
        pageBackground: this.storedPageBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: this.isSessionEphemeral,
        showTitleBar: !this.bookmarkSearchState.isSearchMode,
        useTopSafeInset: !this.bookmarkSearchState.isSearchMode,
        immersiveContent: true,
        topSafeInsetVpOverride: this.topSafeInsetVp,
        menuActions: this.buildHeaderMenuActions(),
        titleBarMenuMaxCount: 2,
        scrollers: [this.bookmarkListScroller],
        onBack: () => {
          this.handleLeadingClick();
        }
      }) {
        BookmarkManagerImmersiveHost({
          isSearchMode: this.bookmarkSearchState.isSearchMode,
          showRootTabs: this.shouldShowRootTabs(),
          query: this.bookmarkSearchState.query,
          pageBackground: this.storedPageBackgroundColor,
          topSafeInsetVp: this.topSafeInsetVp,
          onQueryChange: (query: string): void => {
            this.applyBookmarkSearchResult(this.bookmarkManagerSearchViewModel.setQuery(query));
          },
          onCloseSearch: (): void => {
            this.exitBookmarkSearchMode();
          },
          content: (context: BookmarkManagerImmersiveLayoutContext): void => {
            this.buildList(context)
          }
        })
      }

      this.buildSelectionToolbarOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.moveFolderSheetVisible, this.buildMoveFolderSelectionSheet(), {
      preferType: SheetType.BOTTOM,
      height: '92%',
      dragBar: false,
      showClose: false,
      onDisappear: () => {
        this.clearMoveFolderSelectionSheet();
      }
    })
  }
  @Builder
  private buildList(layout: BookmarkManagerImmersiveLayoutContext) {
    if (this.shouldShowRootTabs()) {
      BookmarkRootTabs({
          scope: this.bookmarkScope,
          selectedId: this.selectedRootId,
          tabsTopInset: layout.tabsTopInset,
          onSelect: (id: string): void => {
            this.switchBookmarkRoot(id);
          }
        }) {
          this.buildBookmarkListContent(layout.contentTopInset)
        }
    } else {
      this.buildBookmarkListContent(layout.contentTopInset)
    }
  }

  @Builder
  private buildBookmarkListContent(contentTopInset: number) {
    if (this.bookmarkNodeCount === 0) {
      Column() {
        if (this.isInitialBookmarkLoadPending) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(32)
              .height(32)
              .color(this.storedSecondaryTextColor)

            Text('正在加载书签')
              .fontSize(14)
              .fontColor(this.storedSecondaryTextColor)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          AppEmptyState({
            airaIconId: this.bookmarkSearchState.isSearchMode
              ? 'settings.search'
              : 'browser.shortcut.bookmarks',
            title: this.bookmarkSearchState.emptyTitle,
            message: this.bookmarkSearchState.emptyMessage,
            fillHeight: true
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: contentTopInset })
    } else {
      BookmarkRecordList({
        dataSource: this.bookmarkListDataSource,
        icons: this.iconStates,
        selectedNodeIds: this.selectedNodeIds,
        pressedNodeId: this.pressedNodeId,
        contextMenuNodeId: this.contextMenuNodeId,
        isSelectionMode: this.isSelectionMode,
        clipToViewport: this.bookmarkSearchState.isSearchMode,
        contentStartOffset: contentTopInset,
        scroller: this.bookmarkListScroller,
        resolveSubtitle: (node: BookmarkNode) => this.resolveRowSubtitle(node),
        resolveFolderHasContent: (node: BookmarkNode) =>
          this.bookmarkFolderCountViewModel.hasFolderContent(this.folderBookmarkCountState, node.id),
        resolveFolderBookmarkCount: (node: BookmarkNode) =>
          this.bookmarkFolderCountViewModel.resolveCount(this.folderBookmarkCountState, node.id),
        resolveContextActions: (node: BookmarkNode) => this.resolveContextActions(node),
        onOpenNode: (node: BookmarkNode) => {
          this.handleNodeClick(node);
        },
        onToggleNodeSelection: (nodeId: string) => {
          this.toggleNodeSelection(nodeId);
        },
        onSetNodeSelected: (nodeId: string, selected: boolean) => {
          this.setNodeSelected(nodeId, selected);
        },
        onReorderNodes: (orderedNodeIds: string[]) => {
          return this.bookmarkManagementFeature.reorderChildren({
            parentId: this.resolveActiveFolderId(),
            childIds: orderedNodeIds
          });
        },
        onReorderApplied: (nodes: BookmarkNode[]) => {
          this.setCurrentFolderNodes(nodes);
        },
        onReorderError: (error: Error) => {
          this.showDialog('排序失败', `书签顺序保存失败：${this.stringifyError(error)}`);
        },
        onUpdatePressedNode: (nodeId: string, type: TouchType) => {
          this.updatePressedNode(nodeId, type);
        },
        onOpenContextMenu: (nodeId: string) => {
          this.openContextMenu(nodeId);
        },
        onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId) => {
          this.handleContextAction(node, actionId);
        },
        onContextAppear: () => {
          this.performLongPressFeedback();
        },
        onContextDisappear: () => {
          this.contextMenuNodeId = '';
        },
        onIconLoadError: (
          target: SiteIconListTarget,
          currentUri: string,
          sourceRevision: number
        ) => {
          this.resolveBookmarkPixelMapAfterUriFailure(target, currentUri, sourceRevision);
        },
        onScrollVisibleRange: (start: number, end: number) => {
          this.updateBookmarkVisibleRange(start, end);
        }
      })
    }
  }

  private openBookmarkMoveFolderSelectionForSelectedNodes(): void {
    if (this.selectedNodeIds.length === 0) {
      this.showDialog('暂无可整理项', '请先选择要整理的书签或文件夹。');
      return;
    }
    this.openBookmarkMoveFolderSelection(this.selectedNodeIds.slice());
  }

  private openBookmarkMoveFolderSelection(nodeIds: string[]): void {
    if (nodeIds.length === 0) {
      return;
    }
    if (nodeIds.some((id: string) => isBookmarkRootNodeId(id))) {
      this.showDialog('无法移动', '系统根节点不可移动，请取消选择根节点后重试。');
      return;
    }
    this.pendingMoveNodeIds = nodeIds.slice();
    this.moveFolderTargetOptions = [];
    this.moveFolderSheetMessage = '';
    this.moveFolderTargetPreparing = true;
    this.moveFolderSheetVisible = true;
    this.scheduleMoveFolderTargetPreparation(nodeIds);
  }

  private async moveNodesToFolder(nodeIds: string[], targetFolderId: string, targetFolderTitle: string = ''): Promise<void> {
    try {
      await this.bookmarkManagementFeature.moveSubtrees({
        nodeIds: nodeIds,
        parentId: targetFolderId,
        targetIndex: BOOKMARK_MOVE_TO_FOLDER_END_INDEX
      });
      this.exitSelectionMode();
      this.reloadNodes();
      this.showNativeToast(nodeIds.length > 1
        ? `已移动 ${nodeIds.length} 项。`
        : `已移动到“${targetFolderTitle.length > 0 ? targetFolderTitle : '目标文件夹'}”。`);
    } catch (error) {
      this.showDialog('移动失败', `移动失败：${this.stringifyError(error as Error)}`);
    }
  }

  private confirmBookmarkMoveFolderSelection(result: BookmarkMoveFolderSelectionResult): void {
    const movingIds = this.pendingMoveNodeIds.slice();
    if (movingIds.length === 0 || result.targetFolderId.length === 0) {
      return;
    }
    this.moveFolderSheetVisible = false;
    this.clearMoveFolderSelectionSheet();
    this.moveNodesToFolder(movingIds, result.targetFolderId, result.targetFolderTitle);
  }

  private clearMoveFolderSelectionSheet(): void {
    if (this.moveFolderSheetVisible) {
      return;
    }
    this.cancelScheduledMoveFolderTargetPreparation();
    this.pendingMoveNodeIds = [];
    this.moveFolderTargetOptions = [];
    this.moveFolderSheetMessage = '';
    this.moveFolderTargetPreparing = false;
  }

  private scheduleMoveFolderTargetPreparation(nodeIds: string[]): void {
    this.cancelScheduledMoveFolderTargetPreparation();
    const generation = this.moveFolderTargetPrepareGeneration + 1;
    this.moveFolderTargetPrepareGeneration = generation;
    this.moveFolderTargetPrepareTimer = setTimeout(() => {
      this.moveFolderTargetPrepareTimer = -1;
      if (generation !== this.moveFolderTargetPrepareGeneration || !this.moveFolderSheetVisible) {
        return;
      }
      void this.prepareMoveFolderTargetOptions(generation, nodeIds);
    }, BOOKMARK_MOVE_FOLDER_TARGET_PREPARE_DELAY_MS);
  }

  private async prepareMoveFolderTargetOptions(generation: number, nodeIds: string[]): Promise<void> {
    try {
      const snapshot = this.bookmarkManagementFeature.getSnapshot(false);
      const counts = await this.bookmarkManagementFeature.buildFolderBookmarkCountsAsync();
      const options = await this.bookmarkFolderSelectionViewModel.buildMoveTargetOptionsFromDataAsync(
        snapshot.nodes,
        nodeIds,
        counts
      );
      if (generation !== this.moveFolderTargetPrepareGeneration || !this.moveFolderSheetVisible) {
        return;
      }
      if (options.length === 0) {
        this.moveFolderTargetPreparing = false;
        this.moveFolderSheetVisible = false;
        this.clearMoveFolderSelectionSheet();
        this.showDialog('无法移动', '当前没有可移动到的文件夹。');
        return;
      }
      this.moveFolderTargetOptions = options;
      this.moveFolderTargetPreparing = false;
    } catch (error) {
      if (generation !== this.moveFolderTargetPrepareGeneration || !this.moveFolderSheetVisible) {
        return;
      }
      this.moveFolderTargetPreparing = false;
      this.moveFolderSheetMessage = `文件夹加载失败：${this.stringifyError(error as Error)}`;
    }
  }

  private cancelScheduledMoveFolderTargetPreparation(): void {
    this.moveFolderTargetPrepareGeneration += 1;
    if (this.moveFolderTargetPrepareTimer < 0) {
      return;
    }
    clearTimeout(this.moveFolderTargetPrepareTimer);
    this.moveFolderTargetPrepareTimer = -1;
  }

  @Builder
  private buildMoveFolderSelectionSheet() {
    BookmarkMoveFolderSelectionSheet({
      options: this.moveFolderTargetOptions,
      message: this.moveFolderSheetMessage,
      isPreparing: this.moveFolderTargetPreparing,
      onDismiss: () => {
        this.moveFolderSheetVisible = false;
      },
      onConfirm: (result: BookmarkMoveFolderSelectionResult) => {
        this.confirmBookmarkMoveFolderSelection(result);
      }
    })
  }

  @Builder
  private buildSelectionToolbar() {
    FloatingSelectionToolbar({
      actions: [
        {
          airaIconId: 'bookmarks.edit.selectAll',
          title: '全选',
          action: () => {
            this.selectAllVisibleNodes();
          }
        },
        {
          airaIconId: 'browser.tabs.delete',
          title: '删除',
          action: () => {
            this.confirmDeleteSelectedNodes();
          }
        },
        {
          airaIconId: 'bookmarks.edit.move',
          title: '移动',
          action: () => {
            this.openBookmarkMoveFolderSelectionForSelectedNodes();
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
      .padding({ bottom: BOOKMARK_SELECTION_TOOLBAR_FLOAT_BOTTOM })
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(60)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }

  private resetAndReload(): void {
    const params = router.getParams() as BookmarkManagerRouteParams | undefined;
    const boundaryParams: BrowserPrivateBoundaryRouteParams = {
      dataScope: params?.dataScope,
      privacyMode: params?.privacyMode,
      boundarySource: params?.boundarySource
    };
    this.isSessionEphemeral = this.privateBoundaryNavigationService.isSessionEphemeralRoute(boundaryParams);
    this.routeDataScope = params?.dataScope ?? '';
    this.routePrivacyMode = params?.privacyMode ?? '';
    this.routeBoundarySource = params?.boundarySource ?? '';
    const bookmarkScopeParams: BrowserBookmarkScopeRouteParams = {
      dataScope: params?.dataScope,
      privacyMode: params?.privacyMode,
      bookmarkScope: params?.bookmarkScope
    };
    this.bookmarkScope = this.bookmarkScopeService.resolveScopeFromRoute(bookmarkScopeParams);
    this.bookmarkManagementFeature.configure(this.buildBookmarkManagementBoundary(), this.bookmarkScope);
    this.applyRouteFolder(params);
    this.isSelectionMode = false;
    this.selectedNodeIds = [];
    this.message = '';
    this.prefillBookmarkNodesFromCache();
    this.loadCachedFolderBookmarkCounts();
    this.reloadNodes();
  }

  private reloadNodes(): void {
    this.bookmarkManagementFeature.refresh()
      .then(() => {
        this.setCurrentFolderNodes(this.resolveCurrentChildren());
        this.pruneSelectedNodes();
        this.scheduleFolderBookmarkCountsRefresh();
        this.scheduleVisibleAuxRefresh(0);
        if (this.bookmarkScope === 'regular') {
          this.refreshHomeShortcutCacheAndMarkers();
        }
        this.isInitialBookmarkLoadPending = false;
      })
      .catch((error: Error) => {
        this.message = `书签加载失败：${JSON.stringify(error)}`;
        this.applyBookmarkSearchResult(this.bookmarkManagerSearchViewModel.reset());
        this.homeShortcutCache = [];
        this.homeShortcutNodeIds = [];
        this.isInitialBookmarkLoadPending = false;
        this.folderBookmarkCountState = this.bookmarkFolderCountViewModel.createInitialState();
      });
  }

  private prefillBookmarkNodesFromCache(): void {
    if (!sharedBookmarkRepository.isInitialized()) {
      this.isInitialBookmarkLoadPending = true;
      this.loadBookmarkPreviewNodes();
      return;
    }
    this.setCurrentFolderNodes(this.resolveCurrentChildren());
    this.scheduleFolderBookmarkCountsRefresh();
    if (this.bookmarkNodeCount === 0) {
      this.iconStates = [];
      this.homeShortcutNodeIds = [];
      this.isInitialBookmarkLoadPending = true;
      return;
    }
    this.isInitialBookmarkLoadPending = false;
    this.scheduleVisibleAuxRefresh(0);
  }

  private loadBookmarkPreviewNodes(): void {
    this.bookmarkManagementFeature.listPreviewChildren(
      this.resolveActiveFolderId(),
      50
    ).then((nodes: BookmarkNode[]) => {
      if (!this.isInitialBookmarkLoadPending) {
        return;
      }
      if (nodes.length === 0) {
        this.clearBookmarkNodes();
        this.iconStates = [];
        this.homeShortcutNodeIds = [];
        this.folderBookmarkCountState = this.bookmarkFolderCountViewModel.createInitialState();
        return;
      }
      this.setCurrentFolderNodes(nodes);
      this.scheduleFolderBookmarkCountsRefresh();
      this.scheduleVisibleAuxRefresh(0);
    }).catch(() => {
      if (this.isInitialBookmarkLoadPending) {
        this.clearBookmarkNodes();
      }
    });
  }

  private resolveCurrentChildren(): BookmarkNode[] {
    return this.bookmarkManagementFeature.listDisplayChildren(this.resolveActiveFolderId());
  }

  private resolveActiveFolderId(): string {
    return this.currentFolderId.length > 0 ? this.currentFolderId : this.selectedRootId;
  }

  private shouldShowRootTabs(): boolean {
    return this.currentFolderId.length === 0 && !this.bookmarkSearchState.isSearchMode;
  }

  private switchBookmarkRoot(rootId: string): void {
    const validRootIds = new Set<string>([
      this.bookmarkScope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID,
      this.bookmarkScope === 'private' ? PRIVATE_BOOKMARK_OTHER_ROOT_ID : BOOKMARK_OTHER_ROOT_ID
    ]);
    if (!validRootIds.has(rootId)) {
      return;
    }
    if (this.currentFolderId.length > 0) {
      return;
    }
    if (this.selectedRootId === rootId) {
      return;
    }
    this.selectedRootId = rootId;
    this.exitSelectionMode();
    this.message = '';
    this.prefillBookmarkNodesFromCache();
    this.reloadNodes();
  }

  private handleNodeClick(node: BookmarkNode): void {
    this.exitSelectionMode();
    if (node.type === 'folder') {
      this.openFolderPage(node);
      return;
    }
    this.openBookmarkNode(node);
  }

  private openBookmarkNode(node: BookmarkNode, intent: BrowserAppUrlOpenIntent = 'current_tab'): void {
    if (node.url === undefined || node.url.length === 0) {
      this.message = '这个书签没有可打开的网址。';
      return;
    }
    try {
      this.bookmarkManagementFeature.authorizeNavigation();
    } catch (error) {
      this.showDialog('无法打开', this.stringifyError(error as Error));
      return;
    }
    router.back({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(node.url, intent, node.title, 'bookmark',
        { privacyMode: this.routePrivacyMode, dataScope: this.routeDataScope })
    });
  }

  private handleLeadingClick(): void {
    if (this.isSelectionMode) {
      this.exitSelectionMode();
      return;
    }
    router.back();
  }

  private createFolder(): void {
    if (this.resolveActiveFolderId().length === 0) {
      this.showDialog('无法新建', '请先进入书签栏或其他书签，再新建文件夹。');
      return;
    }
    this.newFolderTitle = this.buildNewFolderTitle();
    this.createFolderDialogController.open();
  }

  private confirmCreateFolder(folderTitle: string): void {
    if (this.resolveActiveFolderId().length === 0) {
      this.showDialog('无法新建', '请先进入书签栏或其他书签，再新建文件夹。');
      return;
    }
    const normalizedTitle = folderTitle.trim();
    if (normalizedTitle.length === 0) {
      this.showDialog('新建失败', '请输入文件夹名称。');
      return;
    }
    const parentId = this.resolveActiveFolderId();
    const optimisticResult =
      this.bookmarkFolderOptimisticCreateViewModel.createInsertResult(
        normalizedTitle,
        parentId,
        this.bookmarkManagerSearchViewModel.getCurrentFolderNodes(),
        this.folderBookmarkCountState
      );
    this.setCurrentFolderNodes(optimisticResult.nodes);
    this.folderBookmarkCountState = optimisticResult.folderCountState;
    this.scheduleVisibleAuxRefresh(0);
    this.bookmarkManagementFeature.createNode({
      type: 'folder',
      title: normalizedTitle,
      parentId: parentId,
      scope: this.bookmarkScope
    })
      .then(() => {
        this.message = '';
        this.reloadNodes();
      })
      .catch((error: Error) => {
        const removeResult =
          this.bookmarkFolderOptimisticCreateViewModel.createRemoveResult(
            this.bookmarkManagerSearchViewModel.getCurrentFolderNodes(),
            optimisticResult.pendingNode.id,
            this.folderBookmarkCountState
          );
        this.setCurrentFolderNodes(removeResult.nodes);
        this.folderBookmarkCountState = removeResult.folderCountState;
        this.scheduleVisibleAuxRefresh(0);
        this.showDialog('新建失败', `新建文件夹失败：${JSON.stringify(error)}`);
      });
  }

  private buildNewFolderTitle(): string {
    return this.bookmarkManagementFeature.buildNextFolderTitle(this.resolveActiveFolderId());
  }

  private canEnterSelectionMode(): boolean {
    return !this.bookmarkSearchState.isSearchMode &&
      this.bookmarkNodes.some((node: BookmarkNode) => {
        return this.canSelectNode(node.id);
      });
  }

  private canSelectNode(nodeId: string): boolean {
    return !this.bookmarkSearchState.isSearchMode && !isBookmarkRootNodeId(nodeId);
  }

  private resolveTitle(): string {
    let title: string;
    if (this.isSelectionMode) {
      title = `已选 ${this.selectedNodeIds.length} 项`;
    } else {
      title = this.currentFolderTitle;
    }
    return this.isSessionEphemeral && this.bookmarkScope === 'regular'
      ? `常规书签 · ${title}`
      : title;
  }

  private resolveBackIconKind(): 'close' | 'back' {
    return 'back';
  }

  private buildHeaderMenuActions(): ManagementHdsMenuAction[] {
    return this.bookmarkManagerHeaderActionViewModel.buildActions({
      isSelectionMode: this.isSelectionMode,
      isSearchMode: this.bookmarkSearchState.isSearchMode,
      hasCurrentFolder: this.resolveActiveFolderId().length > 0,
      canEnterSelectionMode: this.canEnterSelectionMode(),
      isTransferBusy: this.isTransferBusy
    }, {
      openSearch: () => this.enterBookmarkSearchMode(),
      createFolder: () => this.createFolder(),
      enterSelectionMode: () => this.enterSelectionMode(),
      importBookmarks: () => this.importBookmarkHtml(),
      exportBookmarks: () => this.exportBookmarkHtml()
    });
  }

  private enterBookmarkSearchMode(): void {
    this.applyBookmarkSearchResult(this.bookmarkManagerSearchViewModel.enterSearchMode());
  }

  private exitBookmarkSearchMode(): void {
    this.applyBookmarkSearchResult(this.bookmarkManagerSearchViewModel.exitSearchMode());
  }

  private applyRouteFolder(params: BookmarkManagerRouteParams | undefined): void {
    this.currentFolderId = params?.folderId ?? '';
    const defaultTitle = this.bookmarkScopeService.buildTitle('书签管理', this.bookmarkScope);
    this.selectedRootId = this.bookmarkScope === 'private'
      ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
      : BOOKMARK_TOOLBAR_ROOT_ID;
    this.currentFolderTitle = params?.folderTitle ?? (this.currentFolderId.length > 0 ? '文件夹' : defaultTitle);
  }

  private openFolderPage(folder: BookmarkNode): void {
    router.pushUrl({
      url: BOOKMARK_MANAGER_ROUTE,
      params: {
        folderId: folder.id,
        folderTitle: folder.title,
        dataScope: this.routeDataScope,
        privacyMode: this.routePrivacyMode,
        boundarySource: this.routeBoundarySource,
        bookmarkScope: this.bookmarkScope
      }
    }).catch((_error: Error) => {
      this.showNativeToast('打开文件夹失败。');
    });
  }

  private enterSelectionMode(initialNodeId?: string): void {
    if (!this.canEnterSelectionMode()) {
      this.showDialog('无法编辑', '当前没有可编辑的书签或文件夹。');
      return;
    }
    this.isSelectionMode = true;
    this.contextMenuNodeId = '';
    this.message = '';
    if (initialNodeId !== undefined && initialNodeId.length > 0 && this.canSelectNode(initialNodeId) &&
      !this.isNodeSelected(initialNodeId)) {
      this.selectedNodeIds = this.selectedNodeIds.concat([initialNodeId]);
    }
  }

  private exitSelectionMode(): void {
    this.isSelectionMode = false;
    this.selectedNodeIds = [];
    this.contextMenuNodeId = '';
    this.message = '';
  }

  private isNodeSelected(nodeId: string): boolean {
    return this.selectedNodeIds.indexOf(nodeId) >= 0;
  }

  private setNodeSelected(nodeId: string, isSelected: boolean): void {
    if (!this.canSelectNode(nodeId)) {
      this.selectedNodeIds = this.selectedNodeIds.filter((id: string) => id !== nodeId);
      return;
    }
    const selected = this.selectedNodeIds.slice();
    const index = selected.indexOf(nodeId);
    if (isSelected && index < 0) {
      selected.push(nodeId);
    } else if (!isSelected && index >= 0) {
      selected.splice(index, 1);
    }
    this.selectedNodeIds = selected;
  }

  private toggleNodeSelection(nodeId: string): void {
    this.setNodeSelected(nodeId, !this.isNodeSelected(nodeId));
  }

  private selectAllVisibleNodes(): void {
    const ids: string[] = [];
    this.bookmarkNodes.forEach((node: BookmarkNode) => {
      if (this.canSelectNode(node.id)) {
        ids.push(node.id);
      }
    });
    this.selectedNodeIds = ids;
  }

  private pruneSelectedNodes(): void {
    if (this.selectedNodeIds.length === 0) {
      return;
    }
    const visibleIds = this.bookmarkNodes
      .filter((node: BookmarkNode) => this.canSelectNode(node.id))
      .map((node: BookmarkNode) => node.id);
    this.selectedNodeIds = this.selectedNodeIds.filter((id: string) => visibleIds.indexOf(id) >= 0);
  }

  private confirmDeleteSelectedNodes(): void {
    if (this.selectedNodeIds.length === 0) {
      return;
    }
    if (this.selectedNodeIds.some((id: string) => isBookmarkRootNodeId(id))) {
      this.showDialog('无法删除', '系统根节点不可删除，请先进入根节点后整理其中的书签。');
      return;
    }
    showCenteredAlertDialog({
      title: '删除书签',
      message: `确定删除选中的 ${this.selectedNodeIds.length} 项吗？文件夹内的书签也会一起删除。`,
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
          this.deleteSelectedNodes();
        }
      }
    });
  }

  private deleteSelectedNodes(): void {
    if (this.isTransferBusy) {
      return;
    }
    const deletingIds = this.selectedNodeIds.slice();
    if (deletingIds.length === 0) {
      return;
    }
    if (deletingIds.some((id: string) => isBookmarkRootNodeId(id))) {
      this.showDialog('无法删除', '系统根节点不可删除，请先进入根节点后整理其中的书签。');
      return;
    }
    this.isTransferBusy = true;
    this.exitSelectionMode();
    this.removeBookmarkNodesByIds(deletingIds);
    this.scheduleVisibleAuxRefresh(0);
    this.showNativeToast(`已删除 ${deletingIds.length} 项。`);
    this.bookmarkManagementFeature.deleteNodes(deletingIds)
      .then((deletedCount: number) => {
        if (deletedCount !== deletingIds.length) {
          this.reloadNodes();
        }
      })
      .catch((error: Error) => {
        this.reloadNodes();
        this.showDialog('删除失败', `删除失败：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.isTransferBusy = false;
      });
  }

  private importBookmarkHtml(): void {
    if (this.isTransferBusy) {
      return;
    }
    this.isTransferBusy = true;
    let importStage = '打开文件选择器';
    this.pickOpenUri()
      .then((uri: string | undefined) => {
        if (uri === undefined) {
          return Promise.resolve();
        }
        this.beginBookmarkTransferProgress('正在导入书签', '正在读取书签文件');
        return this.waitForBookmarkProgressFrame()
          .then(() => {
            importStage = '读取文件';
            this.updateBookmarkTransferProgress('正在导入书签', '正在读取书签文件', 18);
            return this.readTextFromUri(uri);
          })
          .then((payload: string) => {
            importStage = '解析文件';
            this.updateBookmarkTransferProgress('正在导入书签', '正在检查书签内容', 36);
            return this.waitForBookmarkProgressFrame().then(() => payload);
          })
          .then((payload: string) => {
            importStage = '写入数据库';
            this.updateBookmarkTransferProgress('正在导入书签', '正在写入本地书签', 68);
            return this.waitForBookmarkProgressFrame()
              .then(() => this.bookmarkManagementFeature.applyHtmlImport(payload));
          })
          .then((result: AiraBookmarkImportApplyResult) => {
            importStage = '刷新书签';
            this.updateBookmarkTransferProgress('正在导入书签', '正在刷新书签列表', 88);
            this.setCurrentFolderNodes(this.resolveCurrentChildren());
            this.scheduleVisibleAuxRefresh(0);
            this.applyBookmarkImportResult(result);
            this.finishBookmarkTransferProgress('导入成功', result.summary);
          });
      })
      .catch((error: Error) => {
        this.completeBookmarkTransferProgressDialog();
        this.showDialog('导入失败', `导入失败（${importStage}）：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.isTransferBusy = false;
      });
  }

  private exportBookmarkHtml(): void {
    if (this.isTransferBusy) {
      return;
    }
    this.isTransferBusy = true;
    const fileName = `aira-bookmarks-${this.resolveFileTimestamp()}.html`;
    this.pickSaveUri(fileName)
      .then((uri: string | undefined) => {
        if (uri === undefined) {
          return Promise.resolve();
        }
        const payload = this.bookmarkManagementFeature.buildHtmlExport();
        return this.writeTextToUri(uri, payload).then(() => {
          this.showDialog('导出成功', '书签已导出为浏览器通用 HTML 文件。');
        });
      })
      .catch((error: Error) => {
        this.showDialog('导出失败', `导出失败：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.isTransferBusy = false;
      });
  }

  private pickOpenUri(): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(this.getPickerContext());
    return documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.html', '.htm']
    }).then((uris: Array<string>) => uris.length > 0 ? uris[0] : undefined);
  }

  private pickSaveUri(fileName: string): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(this.getPickerContext());
    return documentPicker.save({
      newFileNames: [fileName],
      fileSuffixChoices: ['HTML|.html']
    }).then((uris: Array<string>) => uris.length > 0 ? uris[0] : undefined);
  }

  private getPickerContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private beginBookmarkTransferProgress(title: string, subtitle: string): void {
    this.bookmarkTransferProgressController.begin(title, subtitle);
  }

  private updateBookmarkTransferProgress(title: string, subtitle: string, progress: number): void {
    this.bookmarkTransferProgressController.update(title, subtitle, progress);
  }

  private finishBookmarkTransferProgress(
    title: string,
    subtitle: string,
    onComplete?: () => void,
    showResultDialog: boolean = true
  ): void {
    this.bookmarkTransferProgressController.finish(title, subtitle, onComplete, showResultDialog);
  }

  private completeBookmarkTransferProgressDialog(): void {
    this.bookmarkTransferProgressController.complete();
  }

  private openBookmarkTransferProgressDialog(): void {
    if (this.bookmarkTransferProgressDialogOpen) {
      return;
    }
    this.bookmarkTransferProgressDialogOpen = true;
    this.bookmarkTransferProgressDialogController.open();
  }

  private closeBookmarkTransferProgressDialog(): void {
    if (!this.bookmarkTransferProgressDialogOpen) {
      return;
    }
    this.bookmarkTransferProgressDialogOpen = false;
    this.bookmarkTransferProgressDialogController.close();
  }

  private waitForBookmarkProgressFrame(): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, BOOKMARK_IMPORT_PROGRESS_FRAME_DELAY_MS);
    });
  }

  private refreshHomeShortcutCacheAndMarkers(): void {
    this.homeShortcutToggleService.refreshForManagement({
      dataScope: this.routeDataScope,
      privacyMode: this.routePrivacyMode
    })
      .then((shortcuts) => {
        this.homeShortcutCache = shortcuts;
        this.scheduleVisibleAuxRefresh(0);
      })
      .catch(() => {
        this.homeShortcutCache = [];
        this.homeShortcutNodeIds = [];
      });
  }

  private refreshVisibleHomeShortcutMarkers(): void {
    const shortcutUrlKeys = new Set<string>();
    this.homeShortcutCache.forEach((shortcut: ShortcutRecord) => {
      if (shortcut.sync?.deletedAt !== undefined) {
        return;
      }
      const key = this.homeShortcutToggleService.normalizeUrlKey(shortcut.url);
      if (key.length > 0) {
        shortcutUrlKeys.add(key);
      }
    });
    const addedNodeIds: string[] = [];
    this.buildVisibleBookmarkNodes().forEach((node: BookmarkNode) => {
      const key = this.homeShortcutToggleService.normalizeUrlKey(node.url ?? '');
      if (key.length > 0 && shortcutUrlKeys.has(key)) {
        addedNodeIds.push(node.id);
      }
    });
    if (this.areStringArraysEqual(this.homeShortcutNodeIds, addedNodeIds)) {
      return;
    }
    this.homeShortcutNodeIds = addedNodeIds;
  }

  private isBookmarkAddedToHome(nodeId: string): boolean {
    return this.homeShortcutNodeIds.indexOf(nodeId) >= 0;
  }

  private areStringArraysEqual(left: string[], right: string[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) {
        return false;
      }
    }
    return true;
  }

  private toggleBookmarkHomeShortcut(node: BookmarkNode): void {
    if (node.type !== 'bookmark') {
      return;
    }
    this.homeShortcutToggleService.toggleForManagement({
      title: node.title,
      url: node.url ?? ''
    }, {
      dataScope: this.routeDataScope,
      privacyMode: this.routePrivacyMode
    })
      .then((result: HomeShortcutToggleResult) => {
        this.homeShortcutCache = result.shortcuts;
        this.applyHomeShortcutToggleResult(result, node);
        this.showNativeToast(result.added ? '已添加到主页。' : '已从主页移除。');
      })
      .catch((error: Error) => {
        this.showDialog('操作失败', `更新主页快捷方式失败：${this.stringifyError(error)}`);
      });
  }

  private applyHomeShortcutToggleResult(result: HomeShortcutToggleResult, node: BookmarkNode): void {
    if (!result.changed) {
      return;
    }
    const targetKey = this.homeShortcutToggleService.normalizeUrlKey(node.url ?? '');
    const matchingIds: string[] = [];
    this.bookmarkNodes.forEach((item: BookmarkNode) => {
      if (item.type === 'bookmark' &&
        this.homeShortcutToggleService.normalizeUrlKey(item.url ?? '') === targetKey) {
        matchingIds.push(item.id);
      }
    });
    if (result.added) {
      const nextIds = this.homeShortcutNodeIds.slice();
      matchingIds.forEach((id: string) => {
        if (nextIds.indexOf(id) < 0) {
          nextIds.push(id);
        }
      });
      this.homeShortcutNodeIds = nextIds;
      return;
    }
    this.homeShortcutNodeIds = this.homeShortcutNodeIds.filter((id: string) => matchingIds.indexOf(id) < 0);
  }

  private showNativeToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
      this.message = message;
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

  private showBookmarkTransferResultDialog(title: string, subtitle: string): void {
    if (title === '导入成功' && this.bookmarkImportResultBatchId.length > 0) {
      this.bookmarkImportResultDialogController.open();
      return;
    }
    this.showDialog(title, subtitle);
  }

  private async readTextFromUri(uri: string): Promise<string> {
    return readBookmarkTextFromUri(uri);
  }

  private async writeTextToUri(uri: string, payload: string): Promise<void> {
    const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, payload);
    } finally {
      await fileIo.close(file);
    }
  }

  private updatePressedNode(nodeId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedNodeId = nodeId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedNodeId = '';
    }
  }

  private openContextMenu(nodeId: string): void {
    if (this.isSelectionMode) {
      return;
    }
    if (isBookmarkRootNodeId(nodeId)) {
      return;
    }
    this.pressedNodeId = '';
    this.contextMenuNodeId = nodeId;
  }

  private resolveVisibleIcons(): void {
    this.siteIconListPresenter.resolveTargets(
      this.buildVisibleBookmarkIconTargets(),
      (result: SiteIconListResolvedIcon): void => {
        if (result.uri.length > 0) {
          this.applyResolvedSiteIcon(result);
        }
      },
      {
        shouldSkipTarget: (target: SiteIconListTarget): boolean =>
          this.siteIconListPresenter.hasResolvedIcon(this.iconStates, target)
      }
    );
  }

  private buildVisibleBookmarkIconTargets(): BookmarkListIconTarget[] {
    return this.bookmarkListDataSource.getIconTargetsAround(
      this.bookmarkVisibleStartIndex,
      this.bookmarkVisibleEndIndex,
      8
    );
  }

  private buildVisibleBookmarkNodes(): BookmarkNode[] {
    const start = Math.max(0, Math.min(this.bookmarkVisibleStartIndex, this.bookmarkVisibleEndIndex) - 8);
    const end = Math.min(
      this.bookmarkListDataSource.totalCount() - 1,
      Math.max(this.bookmarkVisibleStartIndex, this.bookmarkVisibleEndIndex) + 8
    );
    const nodes: BookmarkNode[] = [];
    for (let index = start; index <= end; index += 1) {
      const node = this.bookmarkListDataSource.getData(index);
      if (node.type === 'bookmark') {
        nodes.push(node);
      }
    }
    return nodes;
  }

  private updateBookmarkVisibleRange(start: number, end: number): void {
    if (this.bookmarkVisibleStartIndex === start && this.bookmarkVisibleEndIndex === end) {
      return;
    }
    this.bookmarkVisibleStartIndex = start;
    this.bookmarkVisibleEndIndex = end;
    this.scheduleVisibleAuxRefresh();
  }

  private scheduleVisibleAuxRefresh(delayMs: number = BOOKMARK_VISIBLE_AUX_REFRESH_DELAY_MS): void {
    this.cancelScheduledVisibleAuxRefresh();
    const generation = this.visibleAuxRefreshGeneration + 1;
    this.visibleAuxRefreshGeneration = generation;
    this.visibleAuxRefreshTimer = setTimeout(() => {
      if (generation !== this.visibleAuxRefreshGeneration) {
        return;
      }
      this.visibleAuxRefreshTimer = -1;
      this.resolveVisibleIcons();
      this.refreshVisibleHomeShortcutMarkers();
    }, delayMs);
  }

  private cancelScheduledVisibleAuxRefresh(): void {
    this.visibleAuxRefreshGeneration += 1;
    if (this.visibleAuxRefreshTimer < 0) {
      return;
    }
    clearTimeout(this.visibleAuxRefreshTimer);
    this.visibleAuxRefreshTimer = -1;
  }

  private setCurrentFolderNodes(nodes: BookmarkNode[]): void {
    this.applyBookmarkSearchResult(this.bookmarkManagerSearchViewModel.setCurrentFolderNodes(nodes));
  }

  private applyBookmarkSearchResult(result: BookmarkManagerSearchResult): void {
    this.bookmarkSearchState = result.state;
    this.bookmarkNodes = result.nodes;
    this.bookmarkNodeCount = result.nodes.length;
    this.bookmarkListDataSource.replaceNodes(result.nodes);
    this.bookmarkVisibleStartIndex = 0;
    this.bookmarkVisibleEndIndex = Math.min(20, Math.max(0, result.nodes.length - 1));
    this.contextMenuNodeId = '';
    this.pressedNodeId = '';
    this.scheduleVisibleAuxRefresh(0);
  }
  private clearBookmarkNodes(): void {
    this.setCurrentFolderNodes([]);
  }

  private removeBookmarkNodesByIds(nodeIds: string[]): void {
    if (nodeIds.length === 0) {
      return;
    }
    this.applyBookmarkSearchResult(this.bookmarkManagerSearchViewModel.removeNodesByIds(nodeIds));
  }

  private applyResolvedSiteIcon(result: SiteIconListResolvedIcon): void {
    const next = this.siteIconListPresenter.applyResolvedIcon(this.iconStates, result);
    if (next !== this.iconStates) {
      this.iconStates = next;
    }
  }

  private resolveBookmarkPixelMapAfterUriFailure(
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

  private resolveContextActions(node: BookmarkNode): BookmarkRecordActionView[] {
    return this.bookmarkRecordActionViewModel.buildActions(node, {
      scope: this.bookmarkScope,
      canSelect: this.canSelectNode(node.id),
      isAddedToHome: this.isBookmarkAddedToHome(node.id)
    });
  }

  private handleContextAction(node: BookmarkNode, actionId: BookmarkRecordActionId): void {
    if (actionId === 'enter_edit_mode') {
      this.runAfterContextMenuDismiss(() => {
        this.enterSelectionMode(node.id);
      });
      return;
    }
    if (actionId === 'add_to_home' || actionId === 'remove_from_home') {
      this.runAfterContextMenuDismiss(() => {
        this.toggleBookmarkHomeShortcut(node);
      });
      return;
    }
    if (actionId === 'share') {
      this.runAfterContextMenuDismiss(() => {
        this.shareNode(node);
      });
      return;
    }
    const openIntent = this.bookmarkOpenActionViewModel.resolveIntent(actionId);
    if (openIntent !== undefined) {
      this.runAfterContextMenuDismiss(() => {
        this.openBookmarkNode(node, openIntent);
      });
      return;
    }
    if (actionId === 'edit_bookmark' || actionId === 'edit_folder') {
      this.runAfterContextMenuDismiss(() => {
        this.openEditDialog(node);
      });
      return;
    }
    if (actionId === 'move') {
      this.runAfterContextMenuDismiss(() => {
        this.openBookmarkMoveFolderSelection([node.id]);
      });
      return;
    }
    if (actionId === 'delete') {
      this.runAfterContextMenuDismiss(() => {
        this.confirmDeleteNode(node);
      });
    }
  }

  private runAfterContextMenuDismiss(action: () => void): void {
    this.contextMenuNodeId = '';
    setTimeout(action, BOOKMARK_CONTEXT_MENU_DISMISS_DELAY_MS);
  }

  private openEditDialog(node: BookmarkNode): void {
    if (isBookmarkRootNodeId(node.id)) {
      this.showDialog('无法编辑', '系统根节点不可编辑，请进入根节点后整理其中的内容。');
      return;
    }
    this.editingNodeId = node.id;
    this.editingNodeType = node.type;
    this.editingTitle = node.title;
    this.editingUrl = node.url ?? '';
    this.editingIconPath = node.type === 'bookmark'
      ? this.siteIconListPresenter.getResolvedIconPath(this.iconStates, node.id)
      : '';
    this.editNodeDialogController.open();
  }

  private confirmEditNode(): void {
    const node = this.findNodeById(this.editingNodeId);
    if (node === undefined) {
      return;
    }
    if (isBookmarkRootNodeId(node.id)) {
      this.showDialog('无法编辑', '系统根节点不可编辑，请进入根节点后整理其中的内容。');
      return;
    }
    const normalizedTitle = this.editingTitle.trim();
    const normalizedUrl = this.editingUrl.trim();
    if (normalizedTitle.length === 0) {
      this.showDialog('保存失败', '请输入名称。');
      return;
    }
    if (node.type === 'bookmark' && normalizedUrl.length === 0) {
      this.showDialog('保存失败', '请输入网址。');
      return;
    }
    const operation = this.bookmarkManagementFeature.beginUpdateNode({
      id: node.id,
      title: normalizedTitle,
      url: node.type === 'bookmark' ? normalizedUrl : node.url
    });
    operation.localCommit.then(
      (updatedNode: BookmarkNode | undefined) => {
        if (updatedNode === undefined) return;
        if (updatedNode.id === this.currentFolderId) {
          this.currentFolderTitle = updatedNode.title;
        }
        this.applyBookmarkSearchResult(this.bookmarkManagerSearchViewModel.replaceNode(updatedNode));
      },
      () => undefined
    );
    operation.completion
      .then((updatedNode: BookmarkNode | undefined) => {
        if (updatedNode === undefined) {
          throw new Error('未找到要编辑的书签。');
        }
      })
      .catch((error: Error) => {
        this.showDialog('保存失败', `保存失败：${this.stringifyError(error)}`);
      });
  }

  private confirmDeleteNode(node: BookmarkNode): void {
    if (isBookmarkRootNodeId(node.id)) {
      this.showDialog('无法删除', '系统根节点不可删除，请整理根节点中的内容。');
      return;
    }
    showCenteredAlertDialog({
      title: node.type === 'folder' ? '删除文件夹' : '删除书签',
      message: node.type === 'folder'
        ? `确定删除“${node.title}”吗？文件夹内的书签也会一起删除。`
        : `确定删除“${node.title}”吗？`,
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
          this.deleteNode(node.id);
        }
      }
    });
  }

  private deleteNode(nodeId: string): void {
    if (this.isTransferBusy) {
      return;
    }
    if (isBookmarkRootNodeId(nodeId)) {
      this.showDialog('无法删除', '系统根节点不可删除，请整理根节点中的内容。');
      return;
    }
    const deletingNode = this.findNodeById(nodeId);
    this.isTransferBusy = true;
    this.removeBookmarkNodesByIds([nodeId]);
    this.scheduleVisibleAuxRefresh(0);
    this.showNativeToast(deletingNode?.type === 'folder' ? '已删除文件夹。' : '已删除书签。');
    this.bookmarkManagementFeature.deleteNode(nodeId)
      .then((deleted: boolean) => {
        if (!deleted) {
          this.reloadNodes();
        }
      })
      .catch((error: Error) => {
        this.reloadNodes();
        this.showDialog('删除失败', `删除失败：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.isTransferBusy = false;
      });
  }

  private shareNode(node: BookmarkNode): void {
    if (node.type !== 'bookmark' || node.url === undefined || node.url.length === 0) {
      return;
    }
    try {
      this.bookmarkManagementFeature.authorizeShare();
    } catch (error) {
      this.showDialog('无法分享', this.stringifyError(error as Error));
      return;
    }
    this.webPageShareService.shareWebPage(this.getPickerContext(), {
      title: node.title,
      url: node.url
    }).catch((error: Error) => {
      this.showDialog('分享失败', `分享失败：${this.stringifyError(error)}`);
    });
  }

  private findNodeById(nodeId: string): BookmarkNode | undefined {
    return this.bookmarkManagementFeature.findNodeById(nodeId);
  }

  private buildBookmarkManagementBoundary(): BookmarkManagementBoundary {
    return new BookmarkManagementBoundary(this.routeDataScope, this.routePrivacyMode);
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

  private resolveRowSubtitle(node: BookmarkNode): string {
    if (node.type === 'folder') {
      return '';
    }
    return node.url ?? '';
  }

  private refreshFolderBookmarkCounts(): void {
    if (this.bookmarkScope === 'private') {
      this.folderBookmarkCountState = this.bookmarkFolderCountViewModel.refreshRealState(
        this.folderBookmarkCountState,
        this.bookmarkManagementFeature
      );
      return;
    }
    this.folderBookmarkCountState = this.bookmarkFolderCountViewModel.refreshAndSaveCaches(
      this.folderBookmarkCountState,
      this.bookmarkManagementFeature,
      sharedBookmarkFolderCountCacheRepository,
      sharedAiraLocalBookmarkOverviewCacheRepository
    );
  }

  private scheduleFolderBookmarkCountsRefresh(): void {
    this.cancelScheduledFolderBookmarkCountsRefresh();
    const generation = this.folderBookmarkCountRefreshGeneration + 1;
    this.folderBookmarkCountRefreshGeneration = generation;
    this.folderBookmarkCountRefreshTimer = setTimeout(() => {
      if (generation !== this.folderBookmarkCountRefreshGeneration) {
        return;
      }
      this.folderBookmarkCountRefreshTimer = -1;
      this.refreshFolderBookmarkCounts();
    }, BOOKMARK_FOLDER_COUNT_REFRESH_DELAY_MS);
  }

  private cancelScheduledFolderBookmarkCountsRefresh(): void {
    this.folderBookmarkCountRefreshGeneration += 1;
    if (this.folderBookmarkCountRefreshTimer < 0) {
      return;
    }
    clearTimeout(this.folderBookmarkCountRefreshTimer);
    this.folderBookmarkCountRefreshTimer = -1;
  }

  private loadCachedFolderBookmarkCounts(): void {
    this.bookmarkFolderCountViewModel.loadCache(
      this.folderBookmarkCountState,
      sharedBookmarkFolderCountCacheRepository,
      (state: BookmarkFolderCountState): void => {
        this.folderBookmarkCountState = state;
      }
    );
  }

  private resolveFileTimestamp(): string {
    return new Date().toISOString()
      .replace(/[:.]/g, '-')
      .replace('T', '_')
      .replace('Z', '');
  }

  private applyBookmarkImportResult(result: AiraBookmarkImportApplyResult): void {
    this.bookmarkImportResultSummary = result.summary;
    this.bookmarkImportResultBatchId = result.batchId;
    this.bookmarkImportResultFolderCount = result.importedFolderCount;
    this.bookmarkImportResultBookmarkCount = result.importedBookmarkCount;
    this.bookmarkImportResultDuplicateCount = result.duplicateCount;
    this.bookmarkImportResultSkippedCount = result.skippedNodeCount;
  }

  private stringifyError(error: Error): string {
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    const serialized = JSON.stringify(error);
    return serialized.length > 0 ? serialized : '未知错误';
  }
}
