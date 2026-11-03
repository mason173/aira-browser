import { BookmarkNode, BookmarkStorageScope } from '../../../common/models/BrowserModels';
import { BookmarkListDataSource } from '../../../features/bookmarks/BookmarkListDataSource';
import { BookmarkRootPageStore } from '../../../features/bookmarks/BookmarkRootPageStore';
import {
  SiteIconListRenderState,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import {
  BookmarkRecordActionId,
  BookmarkRecordActionView
} from '../../../core/bookmarks/BookmarkRecordActionViewModel';
import { AppEmptyState } from '../common/AppEmptyState';
import { FloatingSelectionToolbar } from '../common/FloatingSelectionToolbar';
import { BookmarkRecordList } from './BookmarkRecordList';
import { BookmarkRootTabs } from './BookmarkRootTabs';

const BOOKMARK_ROOT_PAGE_SWIPE_DURATION_MS: number = 280;
const BOOKMARK_SELECTION_TOOLBAR_FLOAT_BOTTOM: number = 36;

@Component
export struct BookmarkSelectionToolbarOverlay {
  @Prop visible: boolean = false;
  onSelectAll: () => void = (): void => {};
  onDelete: () => void = (): void => {};
  onMove: () => void = (): void => {};

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Bottom }) {
        FloatingSelectionToolbar({
          actions: [
            {
              airaIconId: 'bookmarks.edit.selectAll',
              title: $r('app.string.ui_select_all'),
              action: (): void => {
                this.onSelectAll();
              }
            },
            {
              airaIconId: 'browser.tabs.delete',
              title: $r('app.string.settings_delete'),
              action: (): void => {
                this.onDelete();
              }
            },
            {
              airaIconId: 'bookmarks.edit.move',
              title: $r('app.string.ui_move'),
              action: (): void => {
                this.onMove();
              }
            }
          ]
        })
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: BOOKMARK_SELECTION_TOOLBAR_FLOAT_BOTTOM })
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(60)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }
}

@Component
export struct BookmarkManagerListPane {
  @Prop contentTopInset: number = 0;
  @Prop nodeCount: number = 0;
  @Prop isInitialLoadPending: boolean = false;
  @Prop isSearchMode: boolean = false;
  @Prop isSelectionMode: boolean = false;
  @Prop canReorder: boolean = true;
  @Prop secondaryTextColor: string = '#5F6875';
  @Prop emptyTitle: ResourceStr = '';
  @Prop emptyMessage: ResourceStr = '';
  @Prop icons: SiteIconListRenderState[] = [];
  @Prop selectedNodeIds: string[] = [];
  @Prop pressedNodeId: string = '';
  @Prop contextMenuNodeId: string = '';
  dataSource: BookmarkListDataSource = new BookmarkListDataSource();
  scroller: Scroller = new Scroller();
  pageRootId: string = '';
  resolveSubtitle: (node: BookmarkNode) => string = (_node: BookmarkNode): string => '';
  resolveFolderHasContent: (node: BookmarkNode) => boolean = (_node: BookmarkNode): boolean => false;
  resolveFolderBookmarkCount: (node: BookmarkNode) => number = (_node: BookmarkNode): number => -1;
  resolveContextActions: (node: BookmarkNode) => BookmarkRecordActionView[] =
    (_node: BookmarkNode): BookmarkRecordActionView[] => [];
  onOpenNode: (node: BookmarkNode) => void = (_node: BookmarkNode): void => {};
  onToggleNodeSelection: (nodeId: string) => void = (_nodeId: string): void => {};
  onSetNodeSelected: (nodeId: string, selected: boolean) => void = (_nodeId: string, _selected: boolean): void => {};
  onReorderNodes: (parentId: string, orderedNodeIds: string[]) => Promise<BookmarkNode[]> =
    (_parentId: string, _orderedNodeIds: string[]): Promise<BookmarkNode[]> => Promise.resolve([]);
  onReorderApplied: (nodes: BookmarkNode[]) => void = (_nodes: BookmarkNode[]): void => {};
  onReorderError: (error: Error) => void = (_error: Error): void => {};
  onUpdatePressedNode: (nodeId: string, type: TouchType) => void = (_nodeId: string, _type: TouchType): void => {};
  onOpenContextMenu: (nodeId: string) => void = (_nodeId: string): void => {};
  onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId) => void =
    (_node: BookmarkNode, _actionId: BookmarkRecordActionId): void => {};
  onContextAppear: () => void = (): void => {};
  onContextDisappear: () => void = (): void => {};
  onIconLoadError: (target: SiteIconListTarget, currentUri: string, sourceRevision: number) => void =
    (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number): void => {};
  onScrollVisibleRange: (pageRootId: string, dataSource: BookmarkListDataSource, start: number, end: number) => void =
    (_pageRootId: string, _dataSource: BookmarkListDataSource, _start: number, _end: number): void => {};
  onScrollOffsetChange: (pageRootId: string, offset: number) => void =
    (_pageRootId: string, _offset: number): void => {};

  build() {
    if (this.nodeCount === 0) {
      this.buildEmptyPage()
    } else {
      this.buildRecordList()
    }
  }

  @Builder
  private buildEmptyPage() {
    Column() {
      if (this.isInitialLoadPending) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.secondaryTextColor)
          Text($r('app.string.bookmark_loading'))
            .fontSize(14)
            .fontColor(this.secondaryTextColor)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        AppEmptyState({
          airaIconId: this.isSearchMode ? 'settings.search' : 'browser.shortcut.bookmarks',
          title: this.emptyTitle,
          message: this.emptyMessage,
          fillHeight: true
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.contentTopInset })
  }

  @Builder
  private buildRecordList() {
    BookmarkRecordList({
      dataSource: this.dataSource,
      icons: this.icons,
      selectedNodeIds: this.selectedNodeIds,
      pressedNodeId: this.pressedNodeId,
      contextMenuNodeId: this.contextMenuNodeId,
      isSelectionMode: this.isSelectionMode,
      canReorder: this.canReorder,
      clipToViewport: this.isSearchMode,
      contentStartOffset: this.contentTopInset,
      scroller: this.scroller,
      resolveSubtitle: (node: BookmarkNode): string => this.resolveSubtitle(node),
      resolveFolderHasContent: (node: BookmarkNode): boolean => this.resolveFolderHasContent(node),
      resolveFolderBookmarkCount: (node: BookmarkNode): number => this.resolveFolderBookmarkCount(node),
      resolveContextActions: (node: BookmarkNode): BookmarkRecordActionView[] => this.resolveContextActions(node),
      onOpenNode: (node: BookmarkNode): void => {
        this.onOpenNode(node);
      },
      onToggleNodeSelection: (nodeId: string): void => {
        this.onToggleNodeSelection(nodeId);
      },
      onSetNodeSelected: (nodeId: string, selected: boolean): void => {
        this.onSetNodeSelected(nodeId, selected);
      },
      onReorderNodes: (orderedNodeIds: string[]): Promise<BookmarkNode[]> => {
        return this.onReorderNodes(this.pageRootId, orderedNodeIds);
      },
      onReorderApplied: (nodes: BookmarkNode[]): void => {
        this.onReorderApplied(nodes);
      },
      onReorderError: (error: Error): void => {
        this.onReorderError(error);
      },
      onUpdatePressedNode: (nodeId: string, type: TouchType): void => {
        this.onUpdatePressedNode(nodeId, type);
      },
      onOpenContextMenu: (nodeId: string): void => {
        this.onOpenContextMenu(nodeId);
      },
      onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId): void => {
        this.onContextAction(node, actionId);
      },
      onContextAppear: (): void => {
        this.onContextAppear();
      },
      onContextDisappear: (): void => {
        this.onContextDisappear();
      },
      onIconLoadError: (target: SiteIconListTarget, currentUri: string, sourceRevision: number): void => {
        this.onIconLoadError(target, currentUri, sourceRevision);
      },
      onScrollVisibleRange: (start: number, end: number): void => {
        this.onScrollVisibleRange(this.pageRootId, this.dataSource, start, end);
      },
      onScrollOffsetChange: (offset: number): void => {
        this.onScrollOffsetChange(this.pageRootId, offset);
      }
    })
  }
}

@Component
struct BookmarkRootSwipePage {
  @Prop pageRootId: string = '';
  @Prop nodeCount: number = 0;
  @Prop contentTopInset: number = 0;
  @Prop isInitialLoadPending: boolean = false;
  @Prop isSelectionMode: boolean = false;
  @Prop canReorder: boolean = true;
  @Prop secondaryTextColor: string = '#5F6875';
  @Prop emptyTitle: ResourceStr = '';
  @Prop emptyMessage: ResourceStr = '';
  @Prop icons: SiteIconListRenderState[] = [];
  @Prop selectedNodeIds: string[] = [];
  @Prop pressedNodeId: string = '';
  @Prop contextMenuNodeId: string = '';
  dataSource: BookmarkListDataSource = new BookmarkListDataSource();
  scroller: Scroller = new Scroller();
  resolveSubtitle: (node: BookmarkNode) => string = (_node: BookmarkNode): string => '';
  resolveFolderHasContent: (node: BookmarkNode) => boolean = (_node: BookmarkNode): boolean => false;
  resolveFolderBookmarkCount: (node: BookmarkNode) => number = (_node: BookmarkNode): number => -1;
  resolveContextActions: (node: BookmarkNode) => BookmarkRecordActionView[] =
    (_node: BookmarkNode): BookmarkRecordActionView[] => [];
  onOpenNode: (node: BookmarkNode) => void = (_node: BookmarkNode): void => {};
  onToggleNodeSelection: (nodeId: string) => void = (_nodeId: string): void => {};
  onSetNodeSelected: (nodeId: string, selected: boolean) => void = (_nodeId: string, _selected: boolean): void => {};
  onReorderNodes: (parentId: string, orderedNodeIds: string[]) => Promise<BookmarkNode[]> =
    (_parentId: string, _orderedNodeIds: string[]): Promise<BookmarkNode[]> => Promise.resolve([]);
  onReorderApplied: (nodes: BookmarkNode[]) => void = (_nodes: BookmarkNode[]): void => {};
  onReorderError: (error: Error) => void = (_error: Error): void => {};
  onUpdatePressedNode: (nodeId: string, type: TouchType) => void = (_nodeId: string, _type: TouchType): void => {};
  onOpenContextMenu: (nodeId: string) => void = (_nodeId: string): void => {};
  onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId) => void =
    (_node: BookmarkNode, _actionId: BookmarkRecordActionId): void => {};
  onContextAppear: () => void = (): void => {};
  onContextDisappear: () => void = (): void => {};
  onIconLoadError: (target: SiteIconListTarget, currentUri: string, sourceRevision: number) => void =
    (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number): void => {};
  onScrollVisibleRange: (pageRootId: string, dataSource: BookmarkListDataSource, start: number, end: number) => void =
    (_pageRootId: string, _dataSource: BookmarkListDataSource, _start: number, _end: number): void => {};
  onScrollOffsetChange: (pageRootId: string, offset: number) => void =
    (_pageRootId: string, _offset: number): void => {};

  build() {
    BookmarkManagerListPane({
      contentTopInset: this.contentTopInset,
      nodeCount: this.nodeCount,
      isInitialLoadPending: this.isInitialLoadPending,
      isSearchMode: false,
      isSelectionMode: this.isSelectionMode,
      canReorder: this.canReorder,
      secondaryTextColor: this.secondaryTextColor,
      emptyTitle: this.emptyTitle,
      emptyMessage: this.emptyMessage,
      icons: this.icons,
      selectedNodeIds: this.selectedNodeIds,
      pressedNodeId: this.pressedNodeId,
      contextMenuNodeId: this.contextMenuNodeId,
      dataSource: this.dataSource,
      scroller: this.scroller,
      pageRootId: this.pageRootId,
      resolveSubtitle: this.resolveSubtitle,
      resolveFolderHasContent: this.resolveFolderHasContent,
      resolveFolderBookmarkCount: this.resolveFolderBookmarkCount,
      resolveContextActions: this.resolveContextActions,
      onOpenNode: this.onOpenNode,
      onToggleNodeSelection: this.onToggleNodeSelection,
      onSetNodeSelected: this.onSetNodeSelected,
      onReorderNodes: this.onReorderNodes,
      onReorderApplied: this.onReorderApplied,
      onReorderError: this.onReorderError,
      onUpdatePressedNode: this.onUpdatePressedNode,
      onOpenContextMenu: this.onOpenContextMenu,
      onContextAction: this.onContextAction,
      onContextAppear: this.onContextAppear,
      onContextDisappear: this.onContextDisappear,
      onIconLoadError: this.onIconLoadError,
      onScrollVisibleRange: this.onScrollVisibleRange,
      onScrollOffsetChange: this.onScrollOffsetChange
    })
  }
}

@Component
export struct BookmarkRootPageSwiper {
  @Prop contentTopInset: number = 0;
  @Prop scope: BookmarkStorageScope = 'regular';
  @Prop @Watch('handleSelectedRootChanged') selectedRootId: string = '';
  @Prop isSelectionMode: boolean = false;
  @Prop canReorder: boolean = true;
  @Prop isInitialLoadPending: boolean = false;
  @Prop secondaryTextColor: string = '#5F6875';
  @Prop emptyTitle: ResourceStr = '';
  @Prop emptyMessage: ResourceStr = '';
  @Prop icons: SiteIconListRenderState[] = [];
  @Prop selectedNodeIds: string[] = [];
  @Prop pressedNodeId: string = '';
  @Prop contextMenuNodeId: string = '';
  @Prop toolbarNodeCount: number = 0;
  @Prop otherNodeCount: number = 0;
  rootPages: BookmarkRootPageStore = new BookmarkRootPageStore();
  resolveSubtitle: (node: BookmarkNode) => string = (_node: BookmarkNode): string => '';
  resolveFolderHasContent: (node: BookmarkNode) => boolean = (_node: BookmarkNode): boolean => false;
  resolveFolderBookmarkCount: (node: BookmarkNode) => number = (_node: BookmarkNode): number => -1;
  resolveContextActions: (node: BookmarkNode) => BookmarkRecordActionView[] =
    (_node: BookmarkNode): BookmarkRecordActionView[] => [];
  onOpenNode: (node: BookmarkNode) => void = (_node: BookmarkNode): void => {};
  onToggleNodeSelection: (nodeId: string) => void = (_nodeId: string): void => {};
  onSetNodeSelected: (nodeId: string, selected: boolean) => void = (_nodeId: string, _selected: boolean): void => {};
  onReorderNodes: (parentId: string, orderedNodeIds: string[]) => Promise<BookmarkNode[]> =
    (_parentId: string, _orderedNodeIds: string[]): Promise<BookmarkNode[]> => Promise.resolve([]);
  onReorderApplied: (nodes: BookmarkNode[]) => void = (_nodes: BookmarkNode[]): void => {};
  onReorderError: (error: Error) => void = (_error: Error): void => {};
  onUpdatePressedNode: (nodeId: string, type: TouchType) => void = (_nodeId: string, _type: TouchType): void => {};
  onOpenContextMenu: (nodeId: string) => void = (_nodeId: string): void => {};
  onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId) => void =
    (_node: BookmarkNode, _actionId: BookmarkRecordActionId): void => {};
  onContextAppear: () => void = (): void => {};
  onContextDisappear: () => void = (): void => {};
  onIconLoadError: (target: SiteIconListTarget, currentUri: string, sourceRevision: number) => void =
    (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number): void => {};
  onScrollVisibleRange: (pageRootId: string, dataSource: BookmarkListDataSource, start: number, end: number) => void =
    (_pageRootId: string, _dataSource: BookmarkListDataSource, _start: number, _end: number): void => {};
  onScrollOffsetChange: (pageRootId: string, offset: number) => void =
    (_pageRootId: string, _offset: number): void => {};
  onRootSelected: (rootId: string) => void = (_rootId: string): void => {};
  private swiperController: SwiperController = new SwiperController();
  private swiperAttached: boolean = false;
  private programmaticIndex: number = -1;
  private displayedIndex: number = 0;

  build() {
    Swiper(this.swiperController) {
      this.buildToolbarRootPage()
      this.buildOtherRootPage()
    }
    .indicator(false)
    .loop(false)
    .duration(BOOKMARK_ROOT_PAGE_SWIPE_DURATION_MS)
    .curve(Curve.EaseOut)
    .cachedCount(1)
    .disableSwipe(this.isSelectionMode)
    .width('100%')
    .height('100%')
    .shouldBuiltInRecognizerParallelWith((current: GestureRecognizer, others: Array<GestureRecognizer>): GestureRecognizer => {
      return this.bindRootPagePan(current, others);
    })
    .onAppear(() => {
      this.swiperAttached = true;
      this.syncIndex(false);
    })
    .onChange((index: number) => {
      this.handleIndexChange(index);
    })
  }

  @Builder
  private buildToolbarRootPage() {
    BookmarkRootSwipePage({
      pageRootId: this.rootPages.toolbarRootId(this.scope),
      nodeCount: this.toolbarNodeCount,
      dataSource: this.rootPages.toolbarDataSource,
      scroller: this.rootPages.toolbarScroller,
      contentTopInset: this.contentTopInset,
      isInitialLoadPending: this.isInitialLoadPending,
      isSelectionMode: this.isSelectionMode,
      canReorder: this.canReorder,
      secondaryTextColor: this.secondaryTextColor,
      emptyTitle: this.emptyTitle,
      emptyMessage: this.emptyMessage,
      icons: this.icons,
      selectedNodeIds: this.selectedNodeIds,
      pressedNodeId: this.pressedNodeId,
      contextMenuNodeId: this.contextMenuNodeId,
      resolveSubtitle: this.resolveSubtitle,
      resolveFolderHasContent: this.resolveFolderHasContent,
      resolveFolderBookmarkCount: this.resolveFolderBookmarkCount,
      resolveContextActions: this.resolveContextActions,
      onOpenNode: this.onOpenNode,
      onToggleNodeSelection: this.onToggleNodeSelection,
      onSetNodeSelected: this.onSetNodeSelected,
      onReorderNodes: this.onReorderNodes,
      onReorderApplied: this.onReorderApplied,
      onReorderError: this.onReorderError,
      onUpdatePressedNode: this.onUpdatePressedNode,
      onOpenContextMenu: this.onOpenContextMenu,
      onContextAction: this.onContextAction,
      onContextAppear: this.onContextAppear,
      onContextDisappear: this.onContextDisappear,
      onIconLoadError: this.onIconLoadError,
      onScrollVisibleRange: this.onScrollVisibleRange,
      onScrollOffsetChange: this.onScrollOffsetChange
    })
  }

  @Builder
  private buildOtherRootPage() {
    BookmarkRootSwipePage({
      pageRootId: this.rootPages.otherRootId(this.scope),
      nodeCount: this.otherNodeCount,
      dataSource: this.rootPages.otherDataSource,
      scroller: this.rootPages.otherScroller,
      contentTopInset: this.contentTopInset,
      isInitialLoadPending: this.isInitialLoadPending,
      isSelectionMode: this.isSelectionMode,
      canReorder: this.canReorder,
      secondaryTextColor: this.secondaryTextColor,
      emptyTitle: this.emptyTitle,
      emptyMessage: this.emptyMessage,
      icons: this.icons,
      selectedNodeIds: this.selectedNodeIds,
      pressedNodeId: this.pressedNodeId,
      contextMenuNodeId: this.contextMenuNodeId,
      resolveSubtitle: this.resolveSubtitle,
      resolveFolderHasContent: this.resolveFolderHasContent,
      resolveFolderBookmarkCount: this.resolveFolderBookmarkCount,
      resolveContextActions: this.resolveContextActions,
      onOpenNode: this.onOpenNode,
      onToggleNodeSelection: this.onToggleNodeSelection,
      onSetNodeSelected: this.onSetNodeSelected,
      onReorderNodes: this.onReorderNodes,
      onReorderApplied: this.onReorderApplied,
      onReorderError: this.onReorderError,
      onUpdatePressedNode: this.onUpdatePressedNode,
      onOpenContextMenu: this.onOpenContextMenu,
      onContextAction: this.onContextAction,
      onContextAppear: this.onContextAppear,
      onContextDisappear: this.onContextDisappear,
      onIconLoadError: this.onIconLoadError,
      onScrollVisibleRange: this.onScrollVisibleRange,
      onScrollOffsetChange: this.onScrollOffsetChange
    })
  }

  private bindRootPagePan(current: GestureRecognizer, others: Array<GestureRecognizer>): GestureRecognizer {
    for (let i = 0; i < others.length; i++) {
      if (others[i].isBuiltIn() && others[i].getType() === GestureControl.GestureType.PAN_GESTURE) {
        return others[i];
      }
    }
    return current;
  }

  private handleSelectedRootChanged(): void {
    const index = this.resolveSelectedIndex();
    if (!this.swiperAttached || index === this.displayedIndex) {
      return;
    }
    this.programmaticIndex = index;
    this.swiperController.changeIndex(index, true);
  }

  private syncIndex(withAnimation: boolean): void {
    const index = this.resolveSelectedIndex();
    this.displayedIndex = index;
    this.programmaticIndex = index;
    this.swiperController.changeIndex(index, withAnimation);
  }

  private resolveSelectedIndex(): number {
    return this.selectedRootId === this.rootPages.otherRootId(this.scope) ? 1 : 0;
  }

  private handleIndexChange(index: number): void {
    this.displayedIndex = index;
    if (!this.swiperAttached || index === this.programmaticIndex) {
      this.programmaticIndex = -1;
      return;
    }
    this.programmaticIndex = -1;
    const rootId = index === 1 ? this.rootPages.otherRootId(this.scope) : this.rootPages.toolbarRootId(this.scope);
    this.onRootSelected(rootId);
  }
}

@Component
export struct BookmarkManagerPages {
  @Prop showRootTabs: boolean = false;
  @Prop scope: BookmarkStorageScope = 'regular';
  @Prop selectedRootId: string = '';
  @Prop contentTopInset: number = 0;
  @Prop tabsTopInset: number = 0;
  @Prop isSelectionMode: boolean = false;
  @Prop canReorder: boolean = true;
  @Prop isInitialLoadPending: boolean = false;
  @Prop isSearchMode: boolean = false;
  @Prop secondaryTextColor: string = '#5F6875';
  @Prop emptyTitle: ResourceStr = '';
  @Prop emptyMessage: ResourceStr = '';
  @Prop icons: SiteIconListRenderState[] = [];
  @Prop selectedNodeIds: string[] = [];
  @Prop pressedNodeId: string = '';
  @Prop contextMenuNodeId: string = '';
  @Prop nodeCount: number = 0;
  @Prop toolbarNodeCount: number = 0;
  @Prop otherNodeCount: number = 0;
  dataSource: BookmarkListDataSource = new BookmarkListDataSource();
  scroller: Scroller = new Scroller();
  rootPages: BookmarkRootPageStore = new BookmarkRootPageStore();
  resolveSubtitle: (node: BookmarkNode) => string = (_node: BookmarkNode): string => '';
  resolveFolderHasContent: (node: BookmarkNode) => boolean = (_node: BookmarkNode): boolean => false;
  resolveFolderBookmarkCount: (node: BookmarkNode) => number = (_node: BookmarkNode): number => -1;
  resolveContextActions: (node: BookmarkNode) => BookmarkRecordActionView[] =
    (_node: BookmarkNode): BookmarkRecordActionView[] => [];
  onOpenNode: (node: BookmarkNode) => void = (_node: BookmarkNode): void => {};
  onToggleNodeSelection: (nodeId: string) => void = (_nodeId: string): void => {};
  onSetNodeSelected: (nodeId: string, selected: boolean) => void = (_nodeId: string, _selected: boolean): void => {};
  onReorderNodes: (parentId: string, orderedNodeIds: string[]) => Promise<BookmarkNode[]> =
    (_parentId: string, _orderedNodeIds: string[]): Promise<BookmarkNode[]> => Promise.resolve([]);
  onReorderApplied: (nodes: BookmarkNode[]) => void = (_nodes: BookmarkNode[]): void => {};
  onReorderError: (error: Error) => void = (_error: Error): void => {};
  onUpdatePressedNode: (nodeId: string, type: TouchType) => void = (_nodeId: string, _type: TouchType): void => {};
  onOpenContextMenu: (nodeId: string) => void = (_nodeId: string): void => {};
  onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId) => void =
    (_node: BookmarkNode, _actionId: BookmarkRecordActionId): void => {};
  onContextAppear: () => void = (): void => {};
  onContextDisappear: () => void = (): void => {};
  onIconLoadError: (target: SiteIconListTarget, currentUri: string, sourceRevision: number) => void =
    (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number): void => {};
  onScrollVisibleRange: (pageRootId: string, dataSource: BookmarkListDataSource, start: number, end: number) => void =
    (_pageRootId: string, _dataSource: BookmarkListDataSource, _start: number, _end: number): void => {};
  onScrollOffsetChange: (pageRootId: string, offset: number) => void =
    (_pageRootId: string, _offset: number): void => {};
  onRootSelected: (rootId: string) => void = (_rootId: string): void => {};

  build() {
    if (this.showRootTabs) {
      BookmarkRootTabs({
        scope: this.scope,
        selectedId: this.selectedRootId,
        tabsTopInset: this.tabsTopInset,
        onSelect: (id: string): void => {
          this.onRootSelected(id);
        }
      }) {
        BookmarkRootPageSwiper({
          contentTopInset: this.contentTopInset,
          scope: this.scope,
          selectedRootId: this.selectedRootId,
          isSelectionMode: this.isSelectionMode,
          canReorder: this.canReorder,
          isInitialLoadPending: this.isInitialLoadPending,
          secondaryTextColor: this.secondaryTextColor,
          emptyTitle: this.emptyTitle,
          emptyMessage: this.emptyMessage,
          icons: this.icons,
          selectedNodeIds: this.selectedNodeIds,
          pressedNodeId: this.pressedNodeId,
          contextMenuNodeId: this.contextMenuNodeId,
          toolbarNodeCount: this.toolbarNodeCount,
          otherNodeCount: this.otherNodeCount,
          rootPages: this.rootPages,
          resolveSubtitle: (node: BookmarkNode): string => this.resolveSubtitle(node),
          resolveFolderHasContent: (node: BookmarkNode): boolean => this.resolveFolderHasContent(node),
          resolveFolderBookmarkCount: (node: BookmarkNode): number => this.resolveFolderBookmarkCount(node),
          resolveContextActions: (node: BookmarkNode): BookmarkRecordActionView[] => this.resolveContextActions(node),
          onOpenNode: (node: BookmarkNode): void => {
            this.onOpenNode(node);
          },
          onToggleNodeSelection: (nodeId: string): void => {
            this.onToggleNodeSelection(nodeId);
          },
          onSetNodeSelected: (nodeId: string, selected: boolean): void => {
            this.onSetNodeSelected(nodeId, selected);
          },
          onReorderNodes: (parentId: string, orderedNodeIds: string[]): Promise<BookmarkNode[]> => {
            return this.onReorderNodes(parentId, orderedNodeIds);
          },
          onReorderApplied: (nodes: BookmarkNode[]): void => {
            this.onReorderApplied(nodes);
          },
          onReorderError: (error: Error): void => {
            this.onReorderError(error);
          },
          onUpdatePressedNode: (nodeId: string, type: TouchType): void => {
            this.onUpdatePressedNode(nodeId, type);
          },
          onOpenContextMenu: (nodeId: string): void => {
            this.onOpenContextMenu(nodeId);
          },
          onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId): void => {
            this.onContextAction(node, actionId);
          },
          onContextAppear: (): void => {
            this.onContextAppear();
          },
          onContextDisappear: (): void => {
            this.onContextDisappear();
          },
          onIconLoadError: (target: SiteIconListTarget, currentUri: string, sourceRevision: number): void => {
            this.onIconLoadError(target, currentUri, sourceRevision);
          },
          onScrollVisibleRange: (pageRootId: string, pageDataSource: BookmarkListDataSource, start: number, end: number): void => {
            this.onScrollVisibleRange(pageRootId, pageDataSource, start, end);
          },
          onScrollOffsetChange: (pageRootId: string, offset: number): void => {
            this.onScrollOffsetChange(pageRootId, offset);
          },
          onRootSelected: (rootId: string): void => {
            this.onRootSelected(rootId);
          }
        })
      }
    } else {
      BookmarkManagerListPane({
        contentTopInset: this.contentTopInset,
        nodeCount: this.nodeCount,
        isInitialLoadPending: this.isInitialLoadPending,
        isSearchMode: this.isSearchMode,
        isSelectionMode: this.isSelectionMode,
        canReorder: this.canReorder,
        secondaryTextColor: this.secondaryTextColor,
        emptyTitle: this.emptyTitle,
        emptyMessage: this.emptyMessage,
        icons: this.icons,
        selectedNodeIds: this.selectedNodeIds,
        pressedNodeId: this.pressedNodeId,
        contextMenuNodeId: this.contextMenuNodeId,
        dataSource: this.dataSource,
        scroller: this.scroller,
        pageRootId: '',
        resolveSubtitle: (node: BookmarkNode): string => this.resolveSubtitle(node),
        resolveFolderHasContent: (node: BookmarkNode): boolean => this.resolveFolderHasContent(node),
        resolveFolderBookmarkCount: (node: BookmarkNode): number => this.resolveFolderBookmarkCount(node),
        resolveContextActions: (node: BookmarkNode): BookmarkRecordActionView[] => this.resolveContextActions(node),
        onOpenNode: (node: BookmarkNode): void => {
          this.onOpenNode(node);
        },
        onToggleNodeSelection: (nodeId: string): void => {
          this.onToggleNodeSelection(nodeId);
        },
        onSetNodeSelected: (nodeId: string, selected: boolean): void => {
          this.onSetNodeSelected(nodeId, selected);
        },
        onReorderNodes: (parentId: string, orderedNodeIds: string[]): Promise<BookmarkNode[]> => {
          return this.onReorderNodes(parentId, orderedNodeIds);
        },
        onReorderApplied: (nodes: BookmarkNode[]): void => {
          this.onReorderApplied(nodes);
        },
        onReorderError: (error: Error): void => {
          this.onReorderError(error);
        },
        onUpdatePressedNode: (nodeId: string, type: TouchType): void => {
          this.onUpdatePressedNode(nodeId, type);
        },
        onOpenContextMenu: (nodeId: string): void => {
          this.onOpenContextMenu(nodeId);
        },
        onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId): void => {
          this.onContextAction(node, actionId);
        },
        onContextAppear: (): void => {
          this.onContextAppear();
        },
        onContextDisappear: (): void => {
          this.onContextDisappear();
        },
        onIconLoadError: (target: SiteIconListTarget, currentUri: string, sourceRevision: number): void => {
          this.onIconLoadError(target, currentUri, sourceRevision);
        },
        onScrollVisibleRange: (pageRootId: string, pageDataSource: BookmarkListDataSource, start: number, end: number): void => {
          this.onScrollVisibleRange(pageRootId, pageDataSource, start, end);
        },
        onScrollOffsetChange: (pageRootId: string, offset: number): void => {
          this.onScrollOffsetChange(pageRootId, offset);
        }
      })
    }
  }
}
