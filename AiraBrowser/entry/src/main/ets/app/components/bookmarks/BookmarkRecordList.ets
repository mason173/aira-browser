import { image } from '@kit.ImageKit';
import vibrator from '@ohos.vibrator';
import { BookmarkNode } from '../../../common/models/BrowserModels';
import { BookmarkListDataSource } from '../../../features/bookmarks/BookmarkListDataSource';
import {
  BookmarkEditReorderPlan,
  BookmarkEditReorderService
} from '../../../services/bookmarks/BookmarkEditReorderService';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
  RECORD_LIST_ROW_FAVICON_SIZE,
  RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
  RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
  RECORD_LIST_ROW_HEIGHT,
  RECORD_LIST_ROW_HORIZONTAL_INSET
} from '../common/RecordListTokens';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';
import { AiraIcon } from '../common/AiraIcon';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BookmarkFolderIcon } from './BookmarkFolderIcon';
import {
  BookmarkRecordActionId,
  BookmarkRecordActionView
} from '../../../core/bookmarks/BookmarkRecordActionViewModel';
import {
  SiteIconListRenderState,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';

const BOOKMARK_LIST_CACHE_COUNT: number = 24;
const BOOKMARK_LIST_ROW_SPACE: number = 2;
const BOOKMARK_LIST_ROW_PRESS_RADIUS: number = 18;
const BOOKMARK_LIST_TOP_PADDING: number = 0;
const BOOKMARK_LIST_TOP_BLUR_RADIUS: number = 20;
const BOOKMARK_FOLDER_ICON_PLAYBACK_WINDOW_MS: number = 1600;
const BOOKMARK_EDIT_ROW_STRIDE: number = RECORD_LIST_ROW_HEIGHT + BOOKMARK_LIST_ROW_SPACE;
const BOOKMARK_EDIT_DROP_ANIMATION_MS: number = 150;
const BOOKMARK_EDIT_REORDER_ANIMATION_MS: number = 170;
const BOOKMARK_EDIT_REORDER_HAPTIC_DURATION_MS: number = 18;
const BOOKMARK_EDIT_REORDER_HAPTIC_MIN_INTERVAL_MS: number = 45;
const BOOKMARK_EDIT_AUTO_SCROLL_EDGE_VP: number = 64;
const BOOKMARK_EDIT_AUTO_SCROLL_STEP_VP: number = 10;
const BOOKMARK_EDIT_AUTO_SCROLL_INTERVAL_MS: number = 16;

@Component
export struct BookmarkRecordList {
  private readonly editReorderService: BookmarkEditReorderService = new BookmarkEditReorderService();
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  dataSource: BookmarkListDataSource = new BookmarkListDataSource();
  @Prop icons: SiteIconListRenderState[] = [];
  @Prop selectedNodeIds: string[] = [];
  @Prop pressedNodeId: string = '';
  @Prop contextMenuNodeId: string = '';
  @Prop @Watch('handleEditModeChanged') isSelectionMode: boolean = false;
  @Prop clipToViewport: boolean = false;
  @Prop contentStartOffset: number = BOOKMARK_LIST_TOP_PADDING;
  scroller: Scroller = new Scroller();
  private iconLookupSource: SiteIconListRenderState[] = [];
  private iconLookup: Record<string, SiteIconListRenderState | undefined> = {};
  private selectedNodeIdLookupSource: string[] = [];
  private selectedNodeIdLookup: Record<string, boolean> = {};
  @State private folderIconPlaybackKey: number = 0;
  @State private folderIconPlaybackActive: boolean = false;
  @State private draggingNodeId: string = '';
  @State private droppingNodeId: string = '';
  @State private dragOffsetY: number = 0;
  @State private dragOriginalIndex: number = -1;
  @State private dragCurrentIndex: number = -1;
  @State private reorderCommitInProgress: boolean = false;
  private animatedFolderIconPlaybackKey: number = -1;
  private animatedFolderIds: Record<string, boolean> = {};
  private folderIconPlaybackTimer: number = -1;
  private dragSnapshotNodes: BookmarkNode[] = [];
  private dropTimer: number = -1;
  private autoScrollTimer: number = -1;
  private lastReorderFeedbackAt: number = 0;
  private listGlobalTop: number = 0;
  private listHeight: number = 0;
  private dragFingerOffsetY: number = 0;
  private dragScrollDeltaY: number = 0;
  private lastScrollOffsetY: number = 0;
  private autoScrollDirection: number = 0;

  resolveSubtitle: (node: BookmarkNode) => string = (_node: BookmarkNode) => '';
  resolveFolderHasContent: (node: BookmarkNode) => boolean = (_node: BookmarkNode) => false;
  resolveFolderBookmarkCount: (node: BookmarkNode) => number = (_node: BookmarkNode) => -1;
  resolveContextActions: (node: BookmarkNode) => BookmarkRecordActionView[] =
    (_node: BookmarkNode) => [];
  onOpenNode: (node: BookmarkNode) => void = (_node: BookmarkNode) => {};
  onToggleNodeSelection: (nodeId: string) => void = (_nodeId: string) => {};
  onSetNodeSelected: (nodeId: string, selected: boolean) => void = (_nodeId: string, _selected: boolean) => {};
  onUpdatePressedNode: (nodeId: string, type: TouchType) => void = (_nodeId: string, _type: TouchType) => {};
  onOpenContextMenu: (nodeId: string) => void = (_nodeId: string) => {};
  onContextAction: (node: BookmarkNode, actionId: BookmarkRecordActionId) => void =
    (_node: BookmarkNode, _actionId: BookmarkRecordActionId) => {};
  onContextAppear: () => void = () => {};
  onContextDisappear: () => void = () => {};
  onReorderNodes: (orderedNodeIds: string[]) => Promise<BookmarkNode[]> =
    (_orderedNodeIds: string[]) => Promise.resolve([]);
  onReorderApplied: (nodes: BookmarkNode[]) => void = (_nodes: BookmarkNode[]) => {};
  onReorderError: (error: Error) => void = (_error: Error) => {};
  onScrollVisibleRange: (start: number, end: number) => void = (_start: number, _end: number) => {};
  onScrollOffsetChange: (offset: number) => void = (_offset: number) => {};
  onIconLoadError: (
    target: SiteIconListTarget,
    currentUri: string,
    sourceRevision: number
  ) => void = (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number) => {};

  aboutToAppear(): void {
    this.startFolderIconPlayback();
  }

  aboutToDisappear(): void {
    this.clearFolderIconPlaybackTimer();
    this.cancelDropTimer();
    this.clearDragState();
  }

  build() {
    List({ space: 0, scroller: this.scroller }) {
      LazyForEach(this.dataSource, (node: BookmarkNode, index: number) => {
        if (node.type === 'folder') {
          ListItem() {
            this.buildFolderRow(node, index)
          }
          .width('100%')
          .margin({ top: this.resolveNodeTopMargin(index) })
          .translate({ x: 0, y: this.resolveRowTranslateY(node, index) })
          .zIndex(this.draggingNodeId === node.id ? 8 : 0)
          .scale({
            x: this.draggingNodeId === node.id ? 1.015 : 1,
            y: this.draggingNodeId === node.id ? 1.015 : 1
          })
          .animation({
            duration: this.resolveRowAnimationDuration(node.id),
            curve: Curve.EaseOut
          })
          .reuseId('bookmark_folder_row')
        } else if (node.type === 'bookmark') {
          ListItem() {
            this.buildBookmarkCardRow(node, index)
          }
          .width('100%')
          .margin({ top: this.resolveNodeTopMargin(index) })
          .translate({ x: 0, y: this.resolveRowTranslateY(node, index) })
          .zIndex(this.draggingNodeId === node.id ? 8 : 0)
          .scale({
            x: this.draggingNodeId === node.id ? 1.015 : 1,
            y: this.draggingNodeId === node.id ? 1.015 : 1
          })
          .animation({
            duration: this.resolveRowAnimationDuration(node.id),
            curve: Curve.EaseOut
          })
          .reuseId('bookmark_record_row')
        }
      }, (node: BookmarkNode) => `${node.id}:${node.updatedAt}`)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 16,
      right: 16
    })
    .contentStartOffset(this.contentStartOffset)
    .linearGradientBlur(BOOKMARK_LIST_TOP_BLUR_RADIUS, {
      fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
      direction: GradientDirection.Bottom
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .enableScrollInteraction(this.draggingNodeId.length === 0)
    .scrollBar(BarState.Off)
    .clip(this.clipToViewport)
    .cachedCount(BOOKMARK_LIST_CACHE_COUNT, true)
    .onScrollIndex((start: number, end: number) => {
      this.onScrollVisibleRange(start, end);
    })
    .onDidScroll((_scrollDelta: number, _scrollState: ScrollState) => {
      this.onScrollOffsetChange(this.scroller.currentOffset().yOffset);
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.listGlobalTop = Number(newArea.globalPosition.y);
      this.listHeight = Number(newArea.height);
    })
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }

  @Builder
  private buildBookmarkCardRow(node: BookmarkNode, index: number) {
    this.buildBookmarkRow(node, index)
  }

  @Builder
  private buildBookmarkRow(node: BookmarkNode, index: number) {
    WebsiteRecordRow({
      iconUri: this.getIconPathById(node.id),
      iconPixelMap: this.getIconPixelMap(node.id),
      fallbackLabel: this.resolveNodeFallbackLabel(node),
      title: node.title,
      subtitle: this.resolveSubtitle(node),
      pressed: this.pressedNodeId === node.id,
      menuVisible: !this.isSelectionMode && this.contextMenuNodeId === node.id,
      leftInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rightInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rowHeight: RECORD_LIST_ROW_HEIGHT,
      rowBorderRadius: BOOKMARK_LIST_ROW_PRESS_RADIUS,
      iconSize: RECORD_LIST_ROW_FAVICON_SIZE,
      iconSlotSize: RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
      iconContentRatio: RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
      iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      fallbackFontSize: RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
      preferPixelMap: this.getIconPixelMap(node.id) !== undefined,
      sourceRevision: this.getIconSourceRevision(node.id),
      showDivider: this.shouldShowBookmarkDivider(index),
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.onIconLoadError({
          id: node.id,
          url: node.url ?? ''
        }, iconUri, sourceRevision);
      },
      onTouchAction: (type: TouchType) => {
        this.onUpdatePressedNode(node.id, type);
      },
      onOpenMenu: () => {
        this.onOpenContextMenu(node.id);
      },
      onRowClick: () => {
        this.handleRowClick(node);
      },
      onMenuAppear: () => {
        this.onContextAppear();
      },
      onMenuDisappear: () => {
        this.onContextDisappear();
      },
      leadingAccessory: () => {
        this.buildEditDragHandle(node)
      },
      trailing: () => {
        this.buildSelectionTrailing(node)
      },
      menuContent: () => {
        this.buildContextMenuItems(node)
      }
    })
  }

  @Builder
  private buildFolderRow(node: BookmarkNode, index: number) {
    WebsiteRecordRow({
      title: node.title,
      subtitle: '',
      pressed: this.pressedNodeId === node.id,
      menuVisible: !this.isSelectionMode && this.contextMenuNodeId === node.id,
      leftInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rightInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rowHeight: RECORD_LIST_ROW_HEIGHT,
      rowBorderRadius: BOOKMARK_LIST_ROW_PRESS_RADIUS,
      showDivider: this.shouldShowDivider(index),
      onTouchAction: (type: TouchType) => {
        this.onUpdatePressedNode(node.id, type);
      },
      onOpenMenu: () => {
        this.onOpenContextMenu(node.id);
      },
      onRowClick: () => {
        this.handleRowClick(node);
      },
      onMenuAppear: () => {
        this.onContextAppear();
      },
      onMenuDisappear: () => {
        this.onContextDisappear();
      },
      leadingAccessory: () => {
        this.buildEditDragHandle(node)
      },
      leading: () => {
        this.buildFolderIcon(node)
      },
      trailing: () => {
        this.buildFolderTrailing(node)
      },
      previewTrailing: () => {
        this.buildFolderPreviewTrailing()
      },
      menuContent: () => {
        this.buildContextMenuItems(node)
      }
    })
  }

  @Builder
  private buildContextMenuItems(node: BookmarkNode) {
    ForEach(this.resolveContextActions(node), (item: BookmarkRecordActionView) => {
      MenuItem({ content: item.title })
        .onClick(() => {
          this.onContextAction(node, item.id);
        })
    }, (item: BookmarkRecordActionView) => item.id)
  }

  @Builder
  private buildSelectionTrailing(node: BookmarkNode) {
    if (this.isSelectionMode) {
      Checkbox()
        .select(this.isNodeSelected(node.id))
        .selectedColor(this.storedAccentColor)
        .onChange((isSelected: boolean) => {
          this.onSetNodeSelected(node.id, isSelected);
        })
    }
  }

  @Builder
  private buildFolderTrailing(node: BookmarkNode) {
    if (!this.isSelectionMode) {
      this.buildFolderPreviewTrailing()
    }
    this.buildSelectionTrailing(node)
  }

  @Builder
  private buildFolderPreviewTrailing() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor([this.storedSecondaryTextColor])
  }

  @Builder
  private buildFolderIcon(node: BookmarkNode) {
    Row() {
      BookmarkFolderIcon({
        widthVp: 42,
        hasContent: this.resolveFolderHasContent(node),
        animatePaper: this.resolveFolderHasContent(node) && this.shouldAnimateFolderIcon(node.id),
        playbackKey: this.folderIconPlaybackKey,
        count: this.resolveFolderBookmarkCount(node)
      })
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onAppear(() => {
      if (this.resolveFolderHasContent(node) && this.shouldAnimateFolderIcon(node.id)) {
        this.markFolderIconAnimated(node.id);
      }
    })
  }

  @Builder
  private buildEditDragHandle(node: BookmarkNode) {
    if (this.isSelectionMode) {
      Row() {
        AiraIcon({
          airaIconId: 'bookmarks.edit.dragHandle',
          iconSize: 22,
          iconColor: this.storedSecondaryTextColor
        })
      }
      .width(30)
      .height(RECORD_LIST_ROW_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
      .accessibilityText(`拖动调整${node.type === 'folder' ? '文件夹' : '书签'}顺序`)
      .gesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 1 })
          .onActionStart(() => {
            this.beginDrag(node);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.updateDrag(node, event);
          })
          .onActionEnd(() => {
            this.finishDrag(true);
          })
          .onActionCancel(() => {
            this.finishDrag(false);
          }),
        GestureMask.Normal
      )
    }
  }

  private beginDrag(node: BookmarkNode): void {
    if (!this.isSelectionMode || this.reorderCommitInProgress) {
      return;
    }
    this.cancelDropTimer();
    const nodes = this.snapshotNodes();
    const plan = this.editReorderService.planMoveByOffset(
      nodes,
      node.id,
      0,
      BOOKMARK_EDIT_ROW_STRIDE
    );
    if (plan.sourceIndex < 0) {
      return;
    }
    this.dragSnapshotNodes = nodes;
    this.draggingNodeId = node.id;
    this.droppingNodeId = '';
    this.dragOffsetY = 0;
    this.dragOriginalIndex = plan.sourceIndex;
    this.dragCurrentIndex = plan.sourceIndex;
    this.dragFingerOffsetY = 0;
    this.dragScrollDeltaY = 0;
    this.lastScrollOffsetY = this.resolveScrollOffsetY();
    this.onUpdatePressedNode(node.id, TouchType.Cancel);
  }

  private updateDrag(node: BookmarkNode, event: GestureEvent): void {
    if (this.draggingNodeId !== node.id) {
      return;
    }
    this.syncDragScrollDelta();
    this.dragFingerOffsetY = Number(event.offsetY);
    this.updateDragPosition();
    this.updateAutoScrollDirection(event);
  }

  private updateDragPosition(): void {
    this.dragOffsetY = this.dragFingerOffsetY + this.dragScrollDeltaY;
    const plan = this.editReorderService.planMoveByOffset(
      this.dragSnapshotNodes,
      this.draggingNodeId,
      this.dragOffsetY,
      BOOKMARK_EDIT_ROW_STRIDE
    );
    if (plan.targetIndex < 0 || plan.targetIndex === this.dragCurrentIndex) {
      return;
    }
    this.performReorderFeedback();
    animateTo({
      duration: BOOKMARK_EDIT_REORDER_ANIMATION_MS,
      curve: Curve.EaseOut
    }, () => {
      this.dragCurrentIndex = plan.targetIndex;
    });
  }

  private finishDrag(shouldSave: boolean): void {
    if (this.draggingNodeId.length <= 0) {
      return;
    }
    this.syncDragScrollDelta();
    this.stopAutoScroll();
    const plan = this.editReorderService.planMoveToIndex(
      this.dragSnapshotNodes,
      this.draggingNodeId,
      this.dragCurrentIndex
    );
    if (!shouldSave || !plan.changed) {
      this.clearDragState();
      return;
    }
    this.dropNodeToTarget(plan);
  }

  private dropNodeToTarget(plan: BookmarkEditReorderPlan): void {
    this.cancelDropTimer();
    const nodeId = this.draggingNodeId;
    this.droppingNodeId = nodeId;
    animateTo({
      duration: BOOKMARK_EDIT_DROP_ANIMATION_MS,
      curve: Curve.EaseOut
    }, () => {
      this.dragOffsetY = (plan.targetIndex - plan.sourceIndex) * BOOKMARK_EDIT_ROW_STRIDE;
    });
    this.dropTimer = setTimeout(() => {
      this.dropTimer = -1;
      const previousNodes = this.dragSnapshotNodes.slice();
      this.dataSource.replaceNodes(plan.orderedNodes);
      this.reorderCommitInProgress = true;
      this.clearDragState();
      try {
        this.onReorderNodes(plan.orderedNodeIds).then((nodes: BookmarkNode[]) => {
          this.dataSource.replaceNodes(nodes);
          this.onReorderApplied(nodes);
          this.reorderCommitInProgress = false;
        }, (error: Error) => {
          this.dataSource.replaceNodes(previousNodes);
          this.reorderCommitInProgress = false;
          this.onReorderError(error);
        });
      } catch (error) {
        this.dataSource.replaceNodes(previousNodes);
        this.reorderCommitInProgress = false;
        this.onReorderError(error as Error);
      }
    }, BOOKMARK_EDIT_DROP_ANIMATION_MS);
  }

  private updateAutoScrollDirection(event: GestureEvent): void {
    if (event.fingerList.length <= 0 || this.listHeight <= 0) {
      this.stopAutoScroll();
      return;
    }
    const fingerY = Number(event.fingerList[0].globalY);
    const distanceFromTop = fingerY - this.listGlobalTop;
    const distanceFromBottom = this.listGlobalTop + this.listHeight - fingerY;
    if (distanceFromTop <= BOOKMARK_EDIT_AUTO_SCROLL_EDGE_VP && this.resolveScrollOffsetY() > 0) {
      this.startAutoScroll(-1);
      return;
    }
    if (distanceFromBottom <= BOOKMARK_EDIT_AUTO_SCROLL_EDGE_VP && !this.resolveIsAtScrollEnd()) {
      this.startAutoScroll(1);
      return;
    }
    this.stopAutoScroll();
  }

  private startAutoScroll(direction: number): void {
    if (this.autoScrollDirection === direction && this.autoScrollTimer >= 0) {
      return;
    }
    this.stopAutoScroll();
    this.autoScrollDirection = direction;
    this.scheduleAutoScrollStep();
  }

  private scheduleAutoScrollStep(): void {
    if (this.autoScrollDirection === 0 || this.draggingNodeId.length <= 0) {
      return;
    }
    this.autoScrollTimer = setTimeout(() => {
      this.autoScrollTimer = -1;
      this.runAutoScrollStep();
    }, BOOKMARK_EDIT_AUTO_SCROLL_INTERVAL_MS);
  }

  private runAutoScrollStep(): void {
    if (this.draggingNodeId.length <= 0 || this.autoScrollDirection === 0) {
      return;
    }
    this.syncDragScrollDelta();
    if ((this.autoScrollDirection < 0 && this.resolveScrollOffsetY() <= 0) ||
      (this.autoScrollDirection > 0 && this.resolveIsAtScrollEnd())) {
      this.stopAutoScroll();
      return;
    }
    this.scroller.scrollBy(0, this.autoScrollDirection * BOOKMARK_EDIT_AUTO_SCROLL_STEP_VP);
    this.scheduleAutoScrollStep();
  }

  private syncDragScrollDelta(): void {
    const nextOffsetY = this.resolveScrollOffsetY();
    const deltaY = nextOffsetY - this.lastScrollOffsetY;
    this.lastScrollOffsetY = nextOffsetY;
    if (Math.abs(deltaY) < 0.1) {
      return;
    }
    this.dragScrollDeltaY += deltaY;
    this.updateDragPosition();
  }

  private stopAutoScroll(): void {
    if (this.autoScrollTimer >= 0) {
      clearTimeout(this.autoScrollTimer);
      this.autoScrollTimer = -1;
    }
    this.autoScrollDirection = 0;
  }

  private resolveScrollOffsetY(): number {
    try {
      return Math.max(0, Number(this.scroller.currentOffset().yOffset));
    } catch (_error) {
      return 0;
    }
  }

  private resolveIsAtScrollEnd(): boolean {
    try {
      return this.scroller.isAtEnd();
    } catch (_error) {
      return true;
    }
  }

  private resolveRowTranslateY(node: BookmarkNode, index: number): number {
    if (this.draggingNodeId === node.id) {
      return this.dragOffsetY;
    }
    if (this.draggingNodeId.length <= 0 || this.dragOriginalIndex < 0 || this.dragCurrentIndex < 0) {
      return 0;
    }
    const previewIndex = this.editReorderService.resolvePreviewIndex(
      index,
      this.dragOriginalIndex,
      this.dragCurrentIndex
    );
    return (previewIndex - index) * BOOKMARK_EDIT_ROW_STRIDE;
  }

  private resolveRowAnimationDuration(nodeId: string): number {
    if (this.reorderCommitInProgress) {
      return 0;
    }
    if (this.draggingNodeId === nodeId) {
      return this.droppingNodeId === nodeId ? BOOKMARK_EDIT_DROP_ANIMATION_MS : 0;
    }
    return BOOKMARK_EDIT_REORDER_ANIMATION_MS;
  }

  private snapshotNodes(): BookmarkNode[] {
    const nodes: BookmarkNode[] = [];
    for (let index = 0; index < this.dataSource.totalCount(); index += 1) {
      nodes.push(this.dataSource.getData(index));
    }
    return nodes;
  }

  private clearDragState(): void {
    this.stopAutoScroll();
    this.draggingNodeId = '';
    this.droppingNodeId = '';
    this.dragOffsetY = 0;
    this.dragOriginalIndex = -1;
    this.dragCurrentIndex = -1;
    this.dragSnapshotNodes = [];
    this.dragFingerOffsetY = 0;
    this.dragScrollDeltaY = 0;
    this.lastScrollOffsetY = 0;
  }

  private cancelDropTimer(): void {
    if (this.dropTimer < 0) {
      return;
    }
    clearTimeout(this.dropTimer);
    this.dropTimer = -1;
  }

  private performReorderFeedback(): void {
    const now = Date.now();
    if (now - this.lastReorderFeedbackAt < BOOKMARK_EDIT_REORDER_HAPTIC_MIN_INTERVAL_MS) {
      return;
    }
    this.lastReorderFeedbackAt = now;
    vibrator.startVibration({
      type: 'time',
      duration: BOOKMARK_EDIT_REORDER_HAPTIC_DURATION_MS
    }, {
      usage: 'touch'
    }).catch((_error: Error) => {
    });
  }

  private handleEditModeChanged(): void {
    if (this.isSelectionMode) {
      return;
    }
    this.cancelDropTimer();
    this.clearDragState();
  }

  private handleRowClick(node: BookmarkNode): void {
    if (this.isSelectionMode) {
      this.onToggleNodeSelection(node.id);
      return;
    }
    this.onOpenNode(node);
  }

  private resolveNodeFallbackLabel(node: BookmarkNode): string {
    return resolveSiteIconFallbackLabel(node.title, node.url ?? '');
  }

  private isNodeSelected(nodeId: string): boolean {
    return this.getSelectedNodeIdLookup()[nodeId] === true;
  }

  private resolveNodeTopMargin(index: number): number {
    if (index <= 0) {
      return 0;
    }
    return BOOKMARK_LIST_ROW_SPACE;
  }

  private shouldShowBookmarkDivider(index: number): boolean {
    return this.shouldShowDivider(index);
  }

  private shouldShowDivider(index: number): boolean {
    if (index >= this.dataSource.totalCount() - 1) {
      return false;
    }
    return true;
  }

  private getIconPathById(nodeId: string): string {
    return this.getIconState(nodeId)?.path ?? '';
  }

  private getIconPixelMap(nodeId: string): image.PixelMap | undefined {
    return this.getIconState(nodeId)?.pixelMap;
  }

  private getIconSourceRevision(nodeId: string): number {
    return this.getIconState(nodeId)?.sourceRevision ?? 0;
  }

  private startFolderIconPlayback(): void {
    this.clearFolderIconPlaybackTimer();
    this.folderIconPlaybackKey += 1;
    this.folderIconPlaybackActive = true;
    this.animatedFolderIconPlaybackKey = this.folderIconPlaybackKey;
    this.animatedFolderIds = {};
    this.folderIconPlaybackTimer = setTimeout(() => {
      this.folderIconPlaybackTimer = -1;
      this.folderIconPlaybackActive = false;
    }, BOOKMARK_FOLDER_ICON_PLAYBACK_WINDOW_MS);
  }

  private shouldAnimateFolderIcon(nodeId: string): boolean {
    return this.folderIconPlaybackActive &&
      this.animatedFolderIconPlaybackKey === this.folderIconPlaybackKey &&
      this.animatedFolderIds[nodeId] !== true;
  }

  private markFolderIconAnimated(nodeId: string): void {
    if (nodeId.length <= 0 || this.animatedFolderIconPlaybackKey !== this.folderIconPlaybackKey) {
      return;
    }
    this.animatedFolderIds[nodeId] = true;
  }

  private clearFolderIconPlaybackTimer(): void {
    if (this.folderIconPlaybackTimer < 0) {
      return;
    }
    clearTimeout(this.folderIconPlaybackTimer);
    this.folderIconPlaybackTimer = -1;
  }

  private getIconState(nodeId: string): SiteIconListRenderState | undefined {
    if (this.iconLookupSource !== this.icons) {
      this.iconLookupSource = this.icons;
      this.iconLookup = this.buildIconLookup(this.icons);
    }
    return this.iconLookup[nodeId];
  }

  private getSelectedNodeIdLookup(): Record<string, boolean> {
    if (this.selectedNodeIdLookupSource !== this.selectedNodeIds) {
      this.selectedNodeIdLookupSource = this.selectedNodeIds;
      this.selectedNodeIdLookup = this.buildIdLookup(this.selectedNodeIds);
    }
    return this.selectedNodeIdLookup;
  }

  private buildIconLookup(icons: SiteIconListRenderState[]): Record<string, SiteIconListRenderState | undefined> {
    const lookup: Record<string, SiteIconListRenderState | undefined> = {};
    icons.forEach((item: SiteIconListRenderState) => {
      lookup[item.id] = item;
    });
    return lookup;
  }

  private buildIdLookup(ids: string[]): Record<string, boolean> {
    const lookup: Record<string, boolean> = {};
    ids.forEach((id: string) => {
      lookup[id] = true;
    });
    return lookup;
  }
}
