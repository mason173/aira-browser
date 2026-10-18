import { hasAppResourceText, resolveAppResourceText } from '../../../core/resources/AppResourceText';
import { resolveBookmarkNodeDisplayTitle } from '../../../core/resources/HistoryBookmarkDisplayText';
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
  BookmarkDesktopRecordActionGroup,
  BookmarkDesktopRecordActionId,
  BookmarkDesktopRecordActionView,
  BookmarkRecordActionViewModel
} from '../../../core/bookmarks/BookmarkRecordActionViewModel';
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
  private readonly recordActionViewModel: BookmarkRecordActionViewModel = new BookmarkRecordActionViewModel();
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
  @State private recordContextMenuNodeId: string = '';
  @State private recordContextMenuGroups: BookmarkDesktopRecordActionGroup[] = [];
  private suppressNextRecordRowClick: boolean = false;
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
      searchPlaceholder: $r('app.string.bookmark_search'),
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
        label: $r('app.string.ui_select_all'),
        isEnabled: !this.snapshot.busy && this.hasSelectableRows(),
        onAction: (): void => {
          this.snapshot = this.coordinator.selectAllRows();
        }
      })
      ManagementLargeScreenTextButton({
        label: $r('app.string.settings_delete'),
        isEnabled: !this.snapshot.busy && this.snapshot.selectedNodeIds.length > 0,
        onAction: (): void => {
          this.confirmDeleteSelection();
        }
      })
      ManagementLargeScreenTextButton({
        label: $r('app.string.ui_done'),
        onAction: (): void => {
          this.exitSelectionMode();
        }
      })
    } else {
    if (!this.shouldShowFullSearch()) {
      ManagementLargeScreenIconButton({
        iconId: 'settings.search',
        label: $r('app.string.bookmark_search'),
        onAction: (): void => {
          this.compactSearchVisible = true;
          this.focusSearchInput();
        }
      })
    }

    ManagementLargeScreenActionGroup() {
      ManagementLargeScreenIconButton({
        iconId: 'browser.tabs.add',
        label: $r('app.string.bookmark_new_folder'),
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
    .accessibilityText($r('app.string.bookmark_actions'))
    .bindMenu([
      {
        value: $r('app.string.bookmark_multi_select_label'),
        action: (): void => {
          this.enterSelectionMode();
        }
      },
      {
        value: $r('app.string.bookmark_import_action'),
        action: (): void => {
          void this.importBookmarkHtml();
        }
      },
      {
        value: $r('app.string.bookmark_export_action'),
        action: (): void => {
          void this.exportBookmarkHtml();
        }
      }
    ])
    }
  }

  @Builder
  private buildFolderTree() {
    ManagementLargeScreenNavSection({ title: $r('app.string.app_shortcut_bookmarks') })
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
        .accessibilityText(folder.expanded ? $r('app.string.bookmark_collapse_folder') : $r('app.string.bookmark_expand_folder'))
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
      if (hasAppResourceText(this.snapshot.message)) {
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
          Text(this.snapshot.query.length > 0 ? $r('app.string.bookmark_no_match') : $r('app.string.bookmark_folder_empty'))
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
          Text(resolveBookmarkNodeDisplayTitle(node.id, node.title))
            .width('100%')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(node.type === 'folder' ? $r('app.string.bookmark_drag_folder') : (node.url ?? ''))
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
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.suppressNextRecordRowClick = false;
      }
    })
    .onClick((event: ClickEvent): void => {
      // Opening the touch menu must not also open the bookmark on release.
      if (event.source === SourceType.TouchScreen && this.suppressNextRecordRowClick) {
        this.suppressNextRecordRowClick = false;
        return;
      }
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
      if (event.button === MouseButton.Right && event.action === MouseAction.Release) {
        event.stopPropagation();
        this.openRecordContextMenu(node);
        return;
      }
      if (event.button === MouseButton.Middle && event.action === MouseAction.Press) {
        event.stopPropagation();
        this.snapshot = this.coordinator.selectNode(node.id, 'replace');
        this.openNode(node, true);
      }
    })
    .priorityGesture(
      LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
        .onAction((event: GestureEvent): void => {
          if (event.source === SourceType.TouchScreen) {
            this.openRecordContextMenu(node);
          }
        })
    )
    .draggable(!isBookmarkRootNodeId(node.id))
    // Long press opens the menu without lifting a second copy of the row above it.
    .dragPreviewOptions({}, { isLiftingDisabled: true })
    .onDragStart((_event?: DragEvent, _extraParams?: string): DragItemInfo => {
      this.recordContextMenuNodeId = '';
      this.getUIContext().getContextMenuController().close();
      if (!this.snapshot.selectedNodeIds.includes(node.id)) {
        this.snapshot = this.coordinator.selectNode(node.id, 'replace');
      }
      this.draggingNodeIds = this.snapshot.selectedNodeIds.slice();
      this.draggingTitle = this.draggingNodeIds.length > 1 ? resolveAppResourceText($r('app.string.bookmark_drag_count', this.draggingNodeIds.length)) : node.title;
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
    .bindContextMenu(this.recordContextMenuNodeId === node.id, this.buildRecordContextMenu(node), buildBrowserDesktopMenuOptions({
      preview: MenuPreviewMode.NONE,
      onAppear: (): void => {
        this.suppressNextRecordRowClick = true;
      },
      onDisappear: (): void => {
        if (this.recordContextMenuNodeId === node.id) {
          this.recordContextMenuNodeId = '';
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

  private openRecordContextMenu(node: BookmarkNode): void {
    if (!this.snapshot.selectedNodeIds.includes(node.id)) {
      this.snapshot = this.coordinator.selectNode(node.id, 'replace');
    }
    this.recordContextMenuGroups = this.recordActionViewModel.buildDesktopGroups(node, {
      selectionMode: this.selectionMode,
      selectedNodeIds: this.snapshot.selectedNodeIds
    });
    this.suppressNextRecordRowClick = true;
    this.recordContextMenuNodeId = node.id;
  }

  private handleRecordContextMenuAction(node: BookmarkNode, actionId: BookmarkDesktopRecordActionId): void {
    this.recordContextMenuNodeId = '';
    switch (actionId) {
      case 'open':
        this.openNode(node, false);
        break;
      case 'open_new_tab':
        this.openNode(node, true);
        break;
      case 'edit':
        this.beginEditingNode(node);
        break;
      case 'enter_selection':
        this.enterSelectionMode();
        this.snapshot = this.coordinator.selectNode(node.id, 'replace');
        break;
      case 'toggle_selection':
        this.snapshot = this.coordinator.selectNode(node.id, 'toggle');
        break;
      case 'delete':
        this.confirmDeleteNode(node);
        break;
      case 'delete_selection':
        this.confirmDeleteSelection();
        break;
    }
  }

  @Builder
  private buildRecordContextMenu(node: BookmarkNode) {
    BrowserDesktopContextMenu() {
      ForEach(this.recordContextMenuGroups, (group: BookmarkDesktopRecordActionGroup) => {
        MenuItemGroup() {
          ForEach(group.actions, (item: BookmarkDesktopRecordActionView) => {
            BrowserDesktopContextMenuItem({
              label: item.title,
              shortcut: item.shortcut ?? '',
              onAction: (): void => {
                this.handleRecordContextMenuAction(node, item.id);
              }
            })
          }, (item: BookmarkDesktopRecordActionView) => `${node.id}-${item.id}`)
        }
      }, (group: BookmarkDesktopRecordActionGroup) => `${node.id}-${group.id}`)
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
        this.showMessageDialog($r('app.string.history_cannot_open'), this.stringifyError(error as Error));
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
      title: node.type === 'folder' ? $r('app.string.bookmark_delete_folder') : $r('app.string.bookmark_delete_bookmark'),
      message: node.type === 'folder'
        ? $r('app.string.bookmark_delete_folder_confirm', node.title)
        : $r('app.string.bookmark_delete_one_confirm', node.title),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.settings_account_cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.settings_delete'),
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

  private showMessageDialog(title: ResourceStr, message: ResourceStr): void {
    showCenteredAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      confirm: {
        value: $r('app.string.settings_pro_got_it'),
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

  private resolveWorkspaceTitle(): ResourceStr {
    if (this.selectionMode) {
      return $r('app.string.bookmark_selected', this.snapshot.selectedNodeIds.length);
    }
    if (this.snapshot.query.length > 0) {
      return $r('app.string.settings_search_results');
    }
    return this.snapshot.currentFolderTitle.length > 0 ? resolveBookmarkNodeDisplayTitle(this.snapshot.currentFolderId, this.snapshot.currentFolderTitle) : $r('app.string.app_shortcut_bookmarks');
  }

  private resolveWorkspaceBadge(): ResourceStr {
    if (this.selectionMode) {
      return '';
    }
    if (this.privateMode) {
      return $r('app.string.settings_private_badge');
    }
    return $r('app.string.bookmark_item_count', this.snapshot.rows.length);
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
      title: selectedCount > 1 ? $r('app.string.bookmark_delete_selected_title') : $r('app.string.bookmark_delete_item_title'),
      message: selectedCount > 1
        ? $r('app.string.bookmark_delete_selected_confirm', selectedCount)
        : $r('app.string.bookmark_delete_selected_generic'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.settings_account_cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.settings_delete'),
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
    return title.length > 0 ? title.substring(0, 1).toUpperCase() : resolveAppResourceText($r('app.string.bookmark_fallback_glyph'));
  }
}
