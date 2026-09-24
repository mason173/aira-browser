import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  resolveCenteredDialogControllerWidth,
  resolveCenteredDialogSurfaceColor,
  CENTERED_DIALOG_CORNER_RADIUS_VP,
  showCenteredAlertDialog
} from '../common/CenteredDialogSurface';
import {
  BookmarkNode,
  BookmarkStorageScope
} from '../../../common/models/BrowserModels';
import {
  BookmarkWorkspaceFolderRow,
  BookmarkWorkspaceSessionCoordinator,
  BookmarkWorkspaceSnapshot,
  createEmptyBookmarkWorkspaceSnapshot
} from '../../../core/bookmarks/BookmarkWorkspaceSessionCoordinator';
import { isBookmarkRootNodeId } from '../../../data/repositories/BookmarkRepositoryCore';
import { BookmarksFeature } from '../../../features/bookmarks/BookmarksFeature';
import {
  BookmarkManagementBoundary,
  BookmarkManagementFeature
} from '../../../features/bookmarks/BookmarkManagementFeature';
import { BookmarkMutationService } from '../../../services/bookmarks/BookmarkMutationService';
import {
  sharedBookmarkRepository,
  sharedBrowserDatabase
} from '../../bootstrap/BrowserAppRuntime';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import {
  MANAGEMENT_LARGE_SCREEN_ROW_GAP,
  MANAGEMENT_LARGE_SCREEN_ROW_INSET,
  MANAGEMENT_LARGE_SCREEN_ROW_RADIUS,
  ManagementLargeScreenActionGroup,
  ManagementLargeScreenIconButton,
  ManagementLargeScreenNavSection,
  ManagementLargeScreenShell,
  ManagementLargeScreenTextButton
} from '../common/ManagementLargeScreenShell';
import {
  BrowserDesktopContextMenu,
  BrowserDesktopContextMenuItem,
  buildBrowserDesktopMenuOptions
} from '../browser/BrowserDesktopContextMenu';
import {
  BookmarkManagerCreateFolderDialog,
  BookmarkManagerEditNodeDialog
} from './BookmarkManagerDialogs';
import { KeyCode } from '@kit.InputKit';
import { common } from '@kit.AbilityKit';
import {
  BookmarkHtmlTransferApplicationResult,
  BookmarkHtmlTransferApplicationService
} from '../../../services/bookmarks/BookmarkHtmlTransferApplicationService';
import { bookmarkWorkspaceSessionRuntime } from '../../runtime/BookmarkWorkspaceSessionRuntime';

const BOOKMARK_WORKSPACE_COMPACT_SEARCH_BREAKPOINT: number = 840;
const BOOKMARK_WORKSPACE_ROW_HEIGHT: number = 52;
const BOOKMARK_WORKSPACE_SEARCH_FOCUS_KEY: string = 'bookmark-large-screen-search';
const BOOKMARK_WORKSPACE_ROUTE_DEBOUNCE_MS: number = 200;

@Component
export struct BookmarkLargeScreenWorkspace {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#ECEDEF';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';

  @Prop @Watch('handleSessionIdentityChanged') tabId: string = '';
  @Prop @Watch('handleRouteUrlChanged') routeUrl: string = '';
  @Prop @Watch('handleSessionIdentityChanged') privateMode: boolean = false;
  onRouteChange: (routeUrl: string) => void = (_routeUrl: string): void => {};
  onOpenBookmark: (url: string, title: string, openInNewTab: boolean) => void =
    (_url: string, _title: string, _openInNewTab: boolean): void => {};

  private readonly bookmarksFeature: BookmarksFeature = new BookmarksFeature(sharedBookmarkRepository);
  private readonly mutationService: BookmarkMutationService =
    new BookmarkMutationService(sharedBookmarkRepository, sharedBrowserDatabase);
  private readonly bookmarkManagementFeature: BookmarkManagementFeature = new BookmarkManagementFeature(
    this.bookmarksFeature,
    this.mutationService
  );
  private coordinator: BookmarkWorkspaceSessionCoordinator =
    new BookmarkWorkspaceSessionCoordinator(
      this.bookmarkManagementFeature,
      new BookmarkManagementBoundary('profile_persistent', 'regular')
    );
  private readonly transferService: BookmarkHtmlTransferApplicationService =
    new BookmarkHtmlTransferApplicationService(this.bookmarkManagementFeature);
  @State private snapshot: BookmarkWorkspaceSnapshot = createEmptyBookmarkWorkspaceSnapshot();
  @State private hoveredFolderId: string = '';
  private suppressNextFolderRowClick: boolean = false;
  @State private hoveredNodeId: string = '';
  @State private newFolderTitle: string = '';
  @State private editingNodeId: string = '';
  @State private editingNodeType: string = 'bookmark';
  @State private editingTitle: string = '';
  @State private editingUrl: string = '';
  @State private editingIconPath: string = '';
  @State private viewportWidth: number = 1024;
  @State private compactSearchVisible: boolean = false;
  @State private shiftPressed: boolean = false;
  @State private controlPressed: boolean = false;
  @State private selectionMode: boolean = false;
  @State private draggingNodeIds: string[] = [];
  @State private draggingTitle: string = '';
  @State private transferBusy: boolean = false;
  private routePublishTimer: number = -1;
  private folderHoverExpandTimer: number = -1;
  private folderHoverExpandTargetId: string = '';
  private sessionBindingRevision: number = 0;

  private createFolderDialogController: CustomDialogController = new CustomDialogController({
    alignment: DialogAlignment.Center,
    builder: BookmarkManagerCreateFolderDialog({
      folderTitle: $newFolderTitle,
      confirm: (title: string): void => {
        void this.createFolder(title);
      }
    }),
    customStyle: false,
    backgroundColor: resolveCenteredDialogSurfaceColor(),
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    width: resolveCenteredDialogControllerWidth('s'),
    autoCancel: true
  });
  private editNodeDialogController: CustomDialogController = new CustomDialogController({
    alignment: DialogAlignment.Center,
    builder: BookmarkManagerEditNodeDialog({
      nodeTitle: $editingTitle,
      nodeUrl: $editingUrl,
      nodeType: $editingNodeType,
      iconPath: $editingIconPath,
      confirm: (): void => {
        void this.saveEditingNode();
      }
    }),
    customStyle: false,
    backgroundColor: resolveCenteredDialogSurfaceColor(),
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    width: resolveCenteredDialogControllerWidth('s'),
    autoCancel: true
  });

  aboutToAppear(): void {
    void this.initialize();
  }

  aboutToDisappear(): void {
    this.cancelRoutePublish();
    this.cancelFolderHoverExpand();
  }

  build() {
    ManagementLargeScreenShell({
      title: this.resolveWorkspaceTitle(),
      badge: this.resolveWorkspaceBadge(),
      searchPlaceholder: '搜索书签',
      searchQuery: this.snapshot.query,
      searchFocusKey: BOOKMARK_WORKSPACE_SEARCH_FOCUS_KEY,
      showSearch: this.shouldShowFullSearch(),
      onSearchChange: (value: string): void => {
        this.snapshot = this.coordinator.setQuery(value);
        this.scheduleRoutePublish();
      },
      sidebar: (): void => {
        this.buildFolderTree()
      },
      toolbarActions: (): void => {
        this.buildToolbarActions()
      },
      content: (): void => {
        this.buildRecordWorkspace()
      }
    })
    .width('100%')
    .height('100%')
    .focusable(true)
    .keyboardShortcut('f', [ModifierKey.CTRL], (): void => {
      this.focusSearchInput();
    })
    .keyboardShortcut('a', [ModifierKey.CTRL], (): void => {
      this.enterSelectionMode();
      this.snapshot = this.coordinator.selectAllRows();
    })
    .keyboardShortcut(FunctionKey.F2, [], (): void => {
      this.beginEditingSelectedNode();
    })
    .onKeyEvent((event: KeyEvent): boolean => this.handleWorkspaceKeyEvent(event))
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const width = Number(newArea.width);
      if (Number.isFinite(width) && width > 0) {
        this.viewportWidth = width;
      }
    })
  }

  @Builder
  private buildToolbarActions() {
    if (this.selectionMode) {
      ManagementLargeScreenTextButton({
        label: '全选',
        isEnabled: !this.snapshot.busy && this.hasSelectableRows(),
        onAction: (): void => {
          this.snapshot = this.coordinator.selectAllRows();
        }
      })
      ManagementLargeScreenTextButton({
        label: '删除',
        isEnabled: !this.snapshot.busy && this.snapshot.selectedNodeIds.length > 0,
        onAction: (): void => {
          this.confirmDeleteSelection();
        }
      })
      ManagementLargeScreenTextButton({
        label: '完成',
        onAction: (): void => {
          this.exitSelectionMode();
        }
      })
    } else {
    if (!this.shouldShowFullSearch()) {
      ManagementLargeScreenIconButton({
        iconId: 'settings.search',
        label: '搜索书签',
        onAction: (): void => {
          this.compactSearchVisible = true;
          this.focusSearchInput();
        }
      })
    }

    ManagementLargeScreenActionGroup() {
      ManagementLargeScreenIconButton({
        iconId: 'browser.tabs.add',
        label: '新建文件夹',
        grouped: true,
        isEnabled: this.snapshot.currentFolderId.length > 0 && !this.snapshot.busy,
        onAction: (): void => {
          this.newFolderTitle = this.coordinator.buildNextFolderTitle();
          this.createFolderDialogController.open();
        }
      })
    }

    Button() {
      AiraIcon({
        airaIconId: 'browser.toolbar.more',
        iconSize: 16,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(34)
    .height(34)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(9)
    .accessibilityText('书签操作')
    .bindMenu([
      {
        value: '多项选择',
        action: (): void => {
          this.enterSelectionMode();
        }
      },
      {
        value: '导入书签',
        action: (): void => {
          void this.importBookmarkHtml();
        }
      },
      {
        value: '导出书签',
        action: (): void => {
          void this.exportBookmarkHtml();
        }
      }
    ])
    }
  }

  @Builder
  private buildFolderTree() {
    ManagementLargeScreenNavSection({ title: '书签' })
    Column({ space: 3 }) {
      ForEach(this.snapshot.folders, (folder: BookmarkWorkspaceFolderRow) => {
        this.buildFolderRow(folder)
      }, (folder: BookmarkWorkspaceFolderRow) =>
        `bookmark-folder-${folder.id}:${folder.expanded ? 1 : 0}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildFolderRow(folder: BookmarkWorkspaceFolderRow) {
    Row({ space: 8 }) {
      if (folder.hasChildren) {
        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.expandHint',
            iconSize: 13,
            iconColor: this.storedSecondaryTextColor
          })
            .rotate({
              angle: folder.expanded ? 180 : 90,
              centerX: '50%',
              centerY: '50%'
            })
        }
        .width(24)
        .height(24)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .accessibilityText(folder.expanded ? '折叠文件夹' : '展开文件夹')
        .onClick((): void => {
          this.suppressNextFolderRowClick = true;
          this.snapshot = this.coordinator.toggleFolder(folder.id);
          setTimeout((): void => {
            this.suppressNextFolderRowClick = false;
          }, 0);
        })
      } else {
        Blank().width(24).height(24)
      }

        AiraIcon({
          airaIconId: 'bookmarks.folder',
          iconSize: 16,
          iconColor: this.storedSecondaryTextColor
        })

        Text(folder.title)
          .layoutWeight(1)
          .fontSize(14)
          .fontWeight(this.snapshot.currentFolderId === folder.id ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)

        Text(`${folder.bookmarkCount}`)
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
    }
    .width('100%')
    .height(34)
    .padding({ left: 8 + Math.min(folder.depth, 5) * 14, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.resolveFolderBackground(folder.id))
    .borderRadius(MANAGEMENT_LARGE_SCREEN_ROW_RADIUS)
    .clip(true)
    .onHover((hovered: boolean): void => {
      this.hoveredFolderId = hovered ? folder.id : '';
    })
    .onClick((): void => {
      if (this.suppressNextFolderRowClick) {
        this.suppressNextFolderRowClick = false;
        return;
      }
      this.snapshot = this.coordinator.selectFolder(folder.id);
      this.publishRouteNow();
    })
    .onDragEnter((_event?: DragEvent, _extraParams?: string): void => {
      this.scheduleFolderHoverExpand(folder);
    })
    .onDragLeave((_event?: DragEvent, _extraParams?: string): void => {
      this.cancelFolderHoverExpand();
    })
    .onDrop((_event?: DragEvent, _extraParams?: string): void => {
      this.cancelFolderHoverExpand();
      void this.moveDraggingSelectionToFolder(folder.id);
    })
  }

  @Builder
  private buildRecordWorkspace() {
    Column({ space: 0 }) {
      if (this.snapshot.message.length > 0) {
        Text(this.snapshot.message)
          .width('100%')
          .fontSize(13)
          .fontColor($r('app.color.permission_blocked'))
          .padding({ left: 24, right: 24, bottom: 8 })
      }

      if (this.snapshot.loading) {
        Row() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.storedAccentColor)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      } else if (this.snapshot.rows.length <= 0) {
        Column({ space: 8 }) {
          AiraIcon({
            airaIconId: 'browser.shortcut.bookmarks',
            iconSize: 30,
            iconColor: this.storedSecondaryTextColor
          })
          Text(this.snapshot.query.length > 0 ? '没有匹配的书签' : '这个文件夹是空的')
            .fontSize(14)
            .fontColor(this.storedSecondaryTextColor)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: MANAGEMENT_LARGE_SCREEN_ROW_GAP }) {
          ForEach(this.snapshot.rows, (node: BookmarkNode, index: number) => {
            ListItem() {
              this.buildRecordRow(node, index)
            }
            .width('100%')
          }, (node: BookmarkNode) => `bookmark-workspace-row-${node.id}-${node.updatedAt}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({
          left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
          right: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
          bottom: MANAGEMENT_LARGE_SCREEN_ROW_INSET
        })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.None)
        .clip(true)
      }
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .clip(true)
  }

  @Builder
  private buildRecordRow(node: BookmarkNode, rowIndex: number) {
    Button() {
      Row({ space: 12 }) {
        if (this.selectionMode && !isBookmarkRootNodeId(node.id)) {
          this.buildSelectionControl(node)
        }
        this.buildRecordLeading(node)

        Column({ space: 3 }) {
          Text(node.title)
            .width('100%')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(node.type === 'folder' ? '文件夹' : (node.url ?? ''))
            .width('100%')
            .fontSize(12)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
        right: MANAGEMENT_LARGE_SCREEN_ROW_INSET
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(BOOKMARK_WORKSPACE_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .backgroundColor(this.resolveRecordBackground(node.id))
    .borderRadius(MANAGEMENT_LARGE_SCREEN_ROW_RADIUS)
    .clip(true)
    .onHover((hovered: boolean): void => {
      this.hoveredNodeId = hovered ? node.id : '';
    })
    .onClick((): void => {
      if (this.selectionMode) {
        if (isBookmarkRootNodeId(node.id)) {
          return;
        }
        this.snapshot = this.coordinator.selectNode(node.id, this.shiftPressed ? 'range' : 'toggle');
        return;
      }
      if (this.shiftPressed) {
        this.snapshot = this.coordinator.selectNode(node.id, 'range');
        return;
      }
      if (this.controlPressed) {
        this.snapshot = this.coordinator.selectNode(node.id, 'replace');
        this.openNode(node, true);
        return;
      }
      this.snapshot = this.coordinator.selectNode(node.id, 'replace');
      this.openNode(node, false);
    })
    .onMouse((event: MouseEvent): void => {
      if (event.button === MouseButton.Middle && event.action === MouseAction.Press) {
        event.stopPropagation();
        this.snapshot = this.coordinator.selectNode(node.id, 'replace');
        this.openNode(node, true);
      }
    })
    .draggable(!isBookmarkRootNodeId(node.id))
    .onDragStart((_event?: DragEvent, _extraParams?: string): DragItemInfo => {
      if (!this.snapshot.selectedNodeIds.includes(node.id)) {
        this.snapshot = this.coordinator.selectNode(node.id, 'replace');
      }
      this.draggingNodeIds = this.snapshot.selectedNodeIds.slice();
      this.draggingTitle = this.draggingNodeIds.length > 1 ? `${this.draggingNodeIds.length} 个项目` : node.title;
      return {
        builder: (): void => {
          this.buildDragPreview();
        },
        extraInfo: node.id
      };
    })
    .onDrop((_event?: DragEvent, _extraParams?: string): void => {
      if (node.type === 'folder') {
        void this.moveDraggingSelectionToFolder(node.id);
        return;
      }
      void this.moveDraggingSelectionToFolder(this.snapshot.currentFolderId, rowIndex);
    })
    .bindContextMenu(this.buildRecordContextMenu(node), ResponseType.RightClick, buildBrowserDesktopMenuOptions({
      onAppear: (): void => {
        if (!this.snapshot.selectedNodeIds.includes(node.id)) {
          this.snapshot = this.coordinator.selectNode(node.id, 'replace');
        }
      }
    }))
  }

  @Builder
  private buildDragPreview() {
    Row({ space: 8 }) {
      AiraIcon({
        airaIconId: 'bookmarks.folder',
        iconSize: 17,
        iconColor: this.storedAccentColor
      })
      Text(this.draggingTitle)
        .fontSize(13)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .constraintSize({ minWidth: 120, maxWidth: 260 })
    .height(40)
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(10)
    .shadow({ radius: 12, color: this.storedDividerColor, offsetX: 0, offsetY: 4 })
  }

  @Builder
  private buildSelectionControl(node: BookmarkNode) {
    Checkbox()
      .width(18)
      .height(18)
      .shape(CheckBoxShape.CIRCLE)
      .select(this.snapshot.selectedNodeIds.includes(node.id))
      .selectedColor(this.storedAccentColor)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildRecordLeading(node: BookmarkNode) {
    Stack({ alignContent: Alignment.Center }) {
      if (node.type === 'folder') {
        AiraIcon({
          airaIconId: 'bookmarks.folder',
          iconSize: 22,
          iconColor: this.storedAccentColor
        })
      } else {
        Text(this.resolveBookmarkFallback(node))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
      }
    }
    .width(32)
    .height(32)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(8)
  }

  @Builder
  private buildRecordContextMenu(node: BookmarkNode) {
    BrowserDesktopContextMenu() {
      MenuItemGroup() {
        if (node.type === 'folder') {
          BrowserDesktopContextMenuItem({
            label: '打开文件夹',
            shortcut: 'Enter',
            onAction: (): void => {
              this.snapshot = this.coordinator.selectFolder(node.id);
            }
          })
        } else {
          BrowserDesktopContextMenuItem({
            label: '打开',
            shortcut: 'Enter',
            onAction: (): void => {
              this.openNode(node, false);
            }
          })
          BrowserDesktopContextMenuItem({
            label: '在新标签页中打开',
            onAction: (): void => {
              this.openNode(node, true);
            }
          })
        }
      }

      if (!this.selectionMode && this.snapshot.selectedNodeIds.length <= 1 && !isBookmarkRootNodeId(node.id)) {
        MenuItemGroup() {
          BrowserDesktopContextMenuItem({
            label: '编辑',
            shortcut: 'F2',
            onAction: (): void => {
              this.beginEditingNode(node);
            }
          })
        }
      }

      if (!isBookmarkRootNodeId(node.id)) {
        MenuItemGroup() {
          if (!this.selectionMode) {
            BrowserDesktopContextMenuItem({
              label: '多选',
              onAction: (): void => {
                this.enterSelectionMode();
                this.snapshot = this.coordinator.selectNode(node.id, 'replace');
              }
            })
          } else if (this.snapshot.selectedNodeIds.includes(node.id)) {
            BrowserDesktopContextMenuItem({
              label: '取消选择',
              onAction: (): void => {
                this.snapshot = this.coordinator.selectNode(node.id, 'toggle');
              }
            })
          } else {
            BrowserDesktopContextMenuItem({
              label: '添加到多选',
              onAction: (): void => {
                this.snapshot = this.coordinator.selectNode(node.id, 'toggle');
              }
            })
          }
        }
      }

      if (this.snapshot.selectedNodeIds.length > 1) {
        MenuItemGroup() {
          BrowserDesktopContextMenuItem({
            label: `删除所选 ${this.snapshot.selectedNodeIds.length} 项`,
            shortcut: 'Delete',
            onAction: (): void => {
              this.confirmDeleteSelection();
            }
          })
        }
      } else if (!isBookmarkRootNodeId(node.id)) {
        MenuItemGroup() {
          BrowserDesktopContextMenuItem({
            label: '删除',
            shortcut: 'Delete',
            onAction: (): void => {
              this.confirmDeleteNode(node);
            }
          })
        }
      }
    }
  }

  private async initialize(): Promise<void> {
    const tabId = this.tabId.trim();
    if (tabId.length <= 0) {
      return;
    }
    const scope: BookmarkStorageScope = this.privateMode ? 'private' : 'regular';
    const boundary = this.buildBookmarkManagementBoundary();
    this.bookmarkManagementFeature.configure(boundary, scope);
    const bindingRevision = ++this.sessionBindingRevision;
    const coordinator = bookmarkWorkspaceSessionRuntime.acquire(tabId, scope, boundary);
    this.coordinator = coordinator;
    const snapshot = await coordinator.activate(scope, this.routeUrl);
    if (bindingRevision !== this.sessionBindingRevision || tabId !== this.tabId.trim()) {
      return;
    }
    this.snapshot = snapshot;
    if (this.routeUrl.trim().length <= 0 || this.routeUrl !== this.snapshot.routeUrl) {
      this.publishRouteNow();
    }
  }

  private handleSessionIdentityChanged(): void {
    this.cancelRoutePublish();
    this.cancelFolderHoverExpand();
    void this.initialize();
  }

  private async createFolder(title: string): Promise<void> {
    this.snapshot = await this.coordinator.createFolder(title);
  }

  private openNode(node: BookmarkNode, openInNewTab: boolean): void {
    if (node.type === 'folder') {
      this.snapshot = this.coordinator.selectFolder(node.id);
      this.publishRouteNow();
      return;
    }
    const url = node.url?.trim() ?? '';
    if (url.length > 0) {
      try {
        this.coordinator.authorizeNavigation();
        this.onOpenBookmark(url, node.title, openInNewTab);
      } catch (error) {
        this.showMessageDialog('无法打开', this.stringifyError(error as Error));
      }
    }
  }

  private beginEditingNode(node: BookmarkNode): void {
    this.editingNodeId = node.id;
    this.editingNodeType = node.type;
    this.editingTitle = node.title;
    this.editingUrl = node.url ?? '';
    this.editingIconPath = '';
    this.editNodeDialogController.open();
  }

  private async saveEditingNode(): Promise<void> {
    this.snapshot = await this.coordinator.updateNode(
      this.editingNodeId,
      this.editingTitle,
      this.editingUrl
    );
  }

  private confirmDeleteNode(node: BookmarkNode): void {
    showCenteredAlertDialog({
      title: node.type === 'folder' ? '删除文件夹' : '删除书签',
      message: node.type === 'folder'
        ? `确定删除“${node.title}”吗？文件夹内的书签也会一起删除。`
        : `确定删除“${node.title}”吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: (): void => {
          void this.deleteNode(node.id);
        }
      }
    });
  }

  private async deleteNode(nodeId: string): Promise<void> {
    this.snapshot = await this.coordinator.deleteNode(nodeId);
  }

  private async deleteSelectedNodes(): Promise<void> {
    this.snapshot = await this.coordinator.deleteSelectedNodes();
  }

  private async moveDraggingSelectionToFolder(targetFolderId: string, targetIndex: number = 2147483647): Promise<void> {
    if (this.draggingNodeIds.length <= 0 || targetFolderId.length <= 0) {
      return;
    }
    this.snapshot = await this.coordinator.moveSelectionToFolder(targetFolderId, targetIndex);
    this.draggingNodeIds = [];
    this.draggingTitle = '';
  }

  private async importBookmarkHtml(): Promise<void> {
    if (this.transferBusy) {
      return;
    }
    this.transferBusy = true;
    const result = await this.transferService.importHtml(this.getPickerContext());
    if (result.completed) {
      this.snapshot = await this.coordinator.refresh();
    }
    this.transferBusy = false;
    this.presentTransferResult(result);
  }

  private async exportBookmarkHtml(): Promise<void> {
    if (this.transferBusy) {
      return;
    }
    this.transferBusy = true;
    const result = await this.transferService.exportHtml(this.getPickerContext());
    this.transferBusy = false;
    this.presentTransferResult(result);
  }

  private getPickerContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private buildBookmarkManagementBoundary(): BookmarkManagementBoundary {
    return new BookmarkManagementBoundary(
      this.privateMode ? 'session_ephemeral' : 'profile_persistent',
      this.privateMode ? 'private' : 'regular'
    );
  }

  private presentTransferResult(result: BookmarkHtmlTransferApplicationResult): void {
    if (result.cancelled) {
      return;
    }
    this.showMessageDialog(result.title, result.message);
  }

  private showMessageDialog(title: string, message: string): void {
    showCenteredAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      confirm: {
        value: '知道了',
        action: (): void => {}
      }
    });
  }

  private stringifyError(error: Error): string {
    return error.message.length > 0 ? error.message : JSON.stringify(error);
  }

  private scheduleFolderHoverExpand(folder: BookmarkWorkspaceFolderRow): void {
    this.cancelFolderHoverExpand();
    if (!folder.hasChildren || folder.expanded || this.draggingNodeIds.length <= 0) {
      return;
    }
    this.folderHoverExpandTargetId = folder.id;
    this.folderHoverExpandTimer = setTimeout((): void => {
      const targetId = this.folderHoverExpandTargetId;
      this.folderHoverExpandTimer = -1;
      this.folderHoverExpandTargetId = '';
      if (targetId.length > 0) {
        this.snapshot = this.coordinator.toggleFolder(targetId);
      }
    }, 1000);
  }

  private cancelFolderHoverExpand(): void {
    if (this.folderHoverExpandTimer >= 0) {
      clearTimeout(this.folderHoverExpandTimer);
    }
    this.folderHoverExpandTimer = -1;
    this.folderHoverExpandTargetId = '';
  }

  private handleRouteUrlChanged(): void {
    if (this.routeUrl.trim().length <= 0 || this.snapshot.loading) {
      return;
    }
    this.cancelRoutePublish();
    this.snapshot = this.coordinator.applyRoute(this.routeUrl);
  }

  private scheduleRoutePublish(): void {
    this.cancelRoutePublish();
    this.routePublishTimer = setTimeout((): void => {
      this.routePublishTimer = -1;
      this.publishRouteNow();
    }, BOOKMARK_WORKSPACE_ROUTE_DEBOUNCE_MS);
  }

  private cancelRoutePublish(): void {
    if (this.routePublishTimer < 0) {
      return;
    }
    clearTimeout(this.routePublishTimer);
    this.routePublishTimer = -1;
  }

  private publishRouteNow(): void {
    this.cancelRoutePublish();
    const nextRoute = this.snapshot.routeUrl.trim();
    if (nextRoute.length > 0 && nextRoute !== this.routeUrl.trim()) {
      this.onRouteChange(nextRoute);
    }
  }

  private shouldShowFullSearch(): boolean {
    return this.viewportWidth >= BOOKMARK_WORKSPACE_COMPACT_SEARCH_BREAKPOINT ||
      this.compactSearchVisible || this.snapshot.query.length > 0;
  }

  private enterSelectionMode(): void {
    if (!this.hasSelectableRows() || this.snapshot.busy) {
      return;
    }
    this.selectionMode = true;
    this.snapshot = this.coordinator.clearNodeSelection();
  }

  private exitSelectionMode(): void {
    this.selectionMode = false;
    this.snapshot = this.coordinator.clearNodeSelection();
  }

  private hasSelectableRows(): boolean {
    return this.snapshot.rows.some((node: BookmarkNode): boolean => !isBookmarkRootNodeId(node.id));
  }

  private resolveWorkspaceTitle(): string {
    if (this.selectionMode) {
      return `已选择 ${this.snapshot.selectedNodeIds.length} 项`;
    }
    if (this.snapshot.query.length > 0) {
      return '搜索结果';
    }
    return this.snapshot.currentFolderTitle.length > 0 ? this.snapshot.currentFolderTitle : '书签';
  }

  private resolveWorkspaceBadge(): string {
    if (this.selectionMode) {
      return '';
    }
    if (this.privateMode) {
      return '私密';
    }
    return `${this.snapshot.rows.length} 项`;
  }

  private focusSearchInput(): void {
    this.compactSearchVisible = true;
    setTimeout((): void => {
      focusControl.requestFocus(BOOKMARK_WORKSPACE_SEARCH_FOCUS_KEY);
    }, 0);
  }

  private handleWorkspaceKeyEvent(event: KeyEvent): boolean {
    const isDown = event.type === KeyType.Down;
    const isUp = event.type === KeyType.Up;
    if (event.keyCode === KeyCode.KEYCODE_SHIFT_LEFT || event.keyCode === KeyCode.KEYCODE_SHIFT_RIGHT) {
      this.shiftPressed = isDown ? true : (isUp ? false : this.shiftPressed);
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_CTRL_LEFT || event.keyCode === KeyCode.KEYCODE_CTRL_RIGHT) {
      this.controlPressed = isDown ? true : (isUp ? false : this.controlPressed);
      return false;
    }
    if (!isDown) {
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_DEL) {
      this.confirmDeleteSelection();
      return this.snapshot.selectedNodeIds.length > 0;
    }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (this.selectionMode) {
        this.exitSelectionMode();
        return true;
      }
      this.snapshot = this.coordinator.clearNodeSelection();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER ||
      event.keyCode === KeyCode.KEYCODE_DPAD_CENTER) {
      this.openSelectedNode();
      return this.snapshot.selectedNodeIds.length > 0;
    }
    return false;
  }

  private openSelectedNode(): void {
    const node = this.coordinator.findNode(this.snapshot.selectedNodeId);
    if (node !== undefined) {
      this.openNode(node, false);
    }
  }

  private beginEditingSelectedNode(): void {
    if (this.snapshot.selectedNodeIds.length !== 1) {
      return;
    }
    const node = this.coordinator.findNode(this.snapshot.selectedNodeIds[0]);
    if (node !== undefined && !isBookmarkRootNodeId(node.id)) {
      this.beginEditingNode(node);
    }
  }

  private confirmDeleteSelection(): void {
    const selectedCount = this.snapshot.selectedNodeIds.length;
    if (selectedCount <= 0) {
      return;
    }
    showCenteredAlertDialog({
      title: selectedCount > 1 ? '删除所选项目' : '删除项目',
      message: selectedCount > 1
        ? `确定删除所选的 ${selectedCount} 项吗？文件夹内的书签也会一起删除。`
        : '确定删除所选项目吗？文件夹内的书签也会一起删除。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: (): void => {
          void this.deleteSelectedNodes();
        }
      }
    });
  }

  private resolveFolderBackground(folderId: string): ResourceColor {
    if (this.snapshot.currentFolderId === folderId || this.hoveredFolderId === folderId) {
      return this.storedPressedBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveRecordBackground(nodeId: string): ResourceColor {
    if (this.snapshot.selectedNodeIds.includes(nodeId)) {
      return this.storedPressedBackgroundColor;
    }
    if (this.hoveredNodeId === nodeId) {
      return this.storedControlBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveBookmarkFallback(node: BookmarkNode): string {
    const title = node.title.trim();
    return title.length > 0 ? title.substring(0, 1).toUpperCase() : '书';
  }
}
