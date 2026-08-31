import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BookmarkNode } from '../../../common/models/BrowserModels';
import {
  BookmarkFolderOptionView,
  BookmarkFolderSelectionViewModel
} from '../../../core/browser/BookmarkFolderSelectionViewModel';
import {
  BrowserBookmarkActionSessionSnapshot,
  BrowserBookmarkFolderSelectionAction
} from '../../../core/browser/BrowserBookmarkActionCoordinator';
import { BookmarkListDataSource } from '../../../features/bookmarks/BookmarkListDataSource';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { ManagementHdsMenuAction, ManagementHdsScaffold } from '../common/ManagementHdsScaffold';
import {
  BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS
} from '../browser/BrowserModalBottomSheet';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
import {
  BOOKMARK_FOLDER_OVERLAY_ANIMATION_DURATION_MS,
  BOOKMARK_FOLDER_OVERLAY_ENTER_OFFSET_Y,
  BOOKMARK_FOLDER_OVERLAY_SHEET_HEIGHT,
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX
} from '../browser/BrowserShellPresentationTokens';
import { AppEmptyState } from '../common/AppEmptyState';
import {
  RECORD_LIST_ROW_HEIGHT,
  RECORD_LIST_ROW_HORIZONTAL_INSET,
  RECORD_LIST_ROW_ICON_RADIUS,
  RECORD_LIST_ROW_ICON_SIZE
} from '../common/RecordListTokens';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';
import { BookmarkFolderIcon } from './BookmarkFolderIcon';

const BOOKMARK_MOVE_FOLDER_DESTINATION_NAME: string = 'bookmarkMoveFolderDestination';
const BOOKMARK_MOVE_FOLDER_LIST_CACHE_COUNT: number = 12;
const BOOKMARK_MOVE_FOLDER_ROW_SPACE: number = 2;
const BOOKMARK_MOVE_FOLDER_INITIAL_RENDER_LIMIT: number = 50;
const BOOKMARK_MOVE_FOLDER_RENDER_INCREMENT: number = 120;
const BOOKMARK_MOVE_FOLDER_RENDER_DELAY_MS: number = 0;
const BOOKMARK_MOVE_FOLDER_CONTENT_TOP_PADDING: number = 0;
const BOOKMARK_MOVE_FOLDER_CONTENT_BOTTOM_PADDING: number = 12;

export interface BookmarkMoveFolderSelectionResult {
  targetFolderId: string;
  targetFolderTitle: string;
}

class BookmarkMoveFolderDestinationParams {
  folderId: string = '';

  constructor(folderId: string = '') {
    this.folderId = folderId;
  }
}

@Component
export struct BookmarkMoveFolderSelectionSheet {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop options: BookmarkFolderOptionView[] = [];
  @Prop message: string = '';
  @Prop isPreparing: boolean = false;
  @Prop rootTitle: string = '移动书签';
  @Prop preparingTitle: string = '正在准备文件夹';
  @Prop rootEmptyTitle: string = '没有可移动到的文件夹';
  @Prop leafEmptyTitle: string = '没有下级文件夹';
  @Prop confirmLabel: string = '移动到这里';
  @Prop showAddToHome: boolean = false;
  @Prop addToHome: boolean = false;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  private folderSelectionViewModel: BookmarkFolderSelectionViewModel = new BookmarkFolderSelectionViewModel();
  private navigationStack: NavPathStack = new NavPathStack();
  @State private activeFolderId: string = '';
  onDismiss: () => void = () => {};
  onAddToHomeChange: (selected: boolean) => void = (_selected: boolean) => {};
  onFolderOpened: (folderId: string) => void = (_folderId: string) => {};
  onConfirm: (result: BookmarkMoveFolderSelectionResult) => void = (_result: BookmarkMoveFolderSelectionResult) => {};

  aboutToAppear(): void {
    this.resetNavigation();
  }

  build() {
    Column() {
      Navigation(this.navigationStack) {
        this.buildDestinationContent('')
      }
      .width('100%')
      .layoutWeight(1)
      .mode(NavigationMode.Stack)
      .hideTitleBar(true)
      .hideNavBar(false)
      .navDestination(this.buildDestination)
      .backgroundColor(this.storedPageBackgroundColor)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .borderRadius(this.layoutMode === 'large_screen' ? 0 : {
      topLeft: BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS,
      topRight: BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS,
      bottomLeft: 0,
      bottomRight: 0
    })
    .clip(true)
  }

  @Builder
  private buildDestination(name: string, param: Object) {
    if (name === BOOKMARK_MOVE_FOLDER_DESTINATION_NAME) {
      this.buildDestinationPage((param as BookmarkMoveFolderDestinationParams).folderId)
    }
  }

  @Builder
  private buildDestinationPage(folderId: string) {
    NavDestination() {
      this.buildDestinationContent(folderId)
    }
    .title(this.resolveTitle(folderId))
    .hideTitleBar(true)
    .onBackPressed(() => {
      this.navigateBackFolder();
      return true;
    })
  }

  @Builder
  private buildDestinationContent(folderId: string) {
    BookmarkMoveFolderDestinationContent({
      folderId: folderId,
      options: this.options,
      message: this.message,
      isPreparing: this.isPreparing,
      folderSelectionViewModel: this.folderSelectionViewModel,
      preparingTitle: this.preparingTitle,
      rootEmptyTitle: this.rootEmptyTitle,
      leafEmptyTitle: this.leafEmptyTitle,
      confirmLabel: this.confirmLabel,
      showAddToHome: this.showAddToHome,
      addToHome: this.addToHome,
      pageBackgroundColor: this.storedPageBackgroundColor,
      controlBackgroundColor: this.storedControlBackgroundColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      dividerColor: this.storedDividerColor,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      title: this.resolveTitle(folderId),
      isRootDestination: folderId.length <= 0,
      onBack: () => {
        if (folderId.length > 0) {
          this.navigateBackFolder();
        } else {
          this.onDismiss();
        }
      },
      onConfirm: () => {
        this.confirmFolder(folderId);
      },
      onAddToHomeChange: (selected: boolean) => {
        this.onAddToHomeChange(selected);
      },
      onOpenFolder: (nextFolderId: string) => {
        this.openFolder(nextFolderId);
      }
    })
  }

  private resetNavigation(): void {
    while (this.navigationStack.pop(false) !== undefined) {
    }
    this.activeFolderId = '';
  }

  private openFolder(folderId: string): void {
    this.activeFolderId = folderId;
    this.onFolderOpened(folderId);
    this.navigationStack.pushPathByName(
      BOOKMARK_MOVE_FOLDER_DESTINATION_NAME,
      new BookmarkMoveFolderDestinationParams(folderId)
    );
  }

  private navigateBackFolder(): void {
    if (this.activeFolderId.length <= 0) {
      this.onDismiss();
      return;
    }
    const parentFolderId = this.folderSelectionViewModel.resolveParentFolderId(this.options, this.activeFolderId);
    this.navigationStack.pop();
    this.activeFolderId = parentFolderId;
  }

  private confirmFolder(folderId: string): void {
    const folder = this.folderSelectionViewModel.findFolder(this.options, folderId);
    if (folder === undefined) {
      return;
    }
    this.onConfirm({
      targetFolderId: folder.id,
      targetFolderTitle: folder.title
    });
  }

  private resolveTitle(folderId: string): string {
    const folder = this.folderSelectionViewModel.findFolder(this.options, folderId);
    return folder === undefined ? this.rootTitle : folder.title;
  }
}

@Component
export struct BookmarkMoveFolderSelectionOverlay {
  @Prop visible: boolean = false;
  @Prop snapshot: BrowserBookmarkActionSessionSnapshot = {
    actionVersion: 0,
    scope: 'regular',
    addToHome: false,
    preparing: false,
    options: []
  };
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: BrowserBookmarkFolderSelectionAction) => void =
    (_action: BrowserBookmarkFolderSelectionAction) => {};

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.visible,
      layoutMode: this.layoutMode,
      showDesktopHeader: false,
      phoneSheetHeight: BOOKMARK_FOLDER_OVERLAY_SHEET_HEIGHT,
      phoneEnterOffsetY: BOOKMARK_FOLDER_OVERLAY_ENTER_OFFSET_Y,
      animationDurationMs: BOOKMARK_FOLDER_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      desktopWidth: '64%',
      desktopHeight: '78%',
      desktopMinWidth: 460,
      desktopMaxWidth: 640,
      desktopMinHeight: 440,
      desktopMaxHeight: 680,
      onDismiss: () => {
        this.onAction({ type: 'dismiss' });
      }
    }) {
      BookmarkMoveFolderSelectionSheet({
        layoutMode: this.layoutMode,
        rootTitle: '添加书签',
        preparingTitle: '正在准备文件夹',
        rootEmptyTitle: '没有可保存书签的文件夹',
        leafEmptyTitle: '没有下级文件夹',
        confirmLabel: '添加到这里',
        showAddToHome: this.snapshot.scope === 'regular',
        addToHome: this.snapshot.addToHome,
        isPreparing: this.snapshot.preparing,
        options: this.snapshot.options,
        onAddToHomeChange: (selected: boolean) => {
          this.onAction({ type: 'set_add_to_home', selected: selected });
        },
        onFolderOpened: (folderId: string) => {
          this.onAction({ type: 'preview_folder', folderId: folderId });
        },
        onDismiss: () => {
          this.onAction({ type: 'dismiss' });
        },
        onConfirm: (result: BookmarkMoveFolderSelectionResult) => {
          this.onAction({ type: 'confirm_add', folderId: result.targetFolderId });
        }
      })
    }
  }
}

@Component
struct BookmarkMoveFolderDestinationContent {
  @Prop folderId: string = '';
  @Prop @Watch('scheduleReloadRows') options: BookmarkFolderOptionView[] = [];
  @Prop message: string = '';
  @Prop @Watch('scheduleReloadRows') isPreparing: boolean = false;
  @Prop preparingTitle: string = '正在准备文件夹';
  @Prop rootEmptyTitle: string = '没有可移动到的文件夹';
  @Prop leafEmptyTitle: string = '没有下级文件夹';
  @Prop confirmLabel: string = '移动到这里';
  @Prop showAddToHome: boolean = false;
  @Prop addToHome: boolean = false;
  @Prop pageBackgroundColor: ResourceColor = '#F6F8FB';
  @Prop controlBackgroundColor: ResourceColor = '#EEF2F6';
  @Prop pressedBackgroundColor: ResourceColor = '#DDE4EC';
  @Prop dividerColor: ResourceColor = '#E3E8EF';
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop secondaryTextColor: ResourceColor = '#5F6875';
  @Prop title: string = '移动书签';
  @Prop isRootDestination: boolean = true;
  folderSelectionViewModel: BookmarkFolderSelectionViewModel = new BookmarkFolderSelectionViewModel();
  private folderListDataSource: BookmarkListDataSource = new BookmarkListDataSource();
  private listScroller: Scroller = new Scroller();
  private childFolders: BookmarkFolderOptionView[] = [];
  private reloadGeneration: number = 0;
  private reloadTimer: number = -1;
  @State private rowCount: number = 0;
  @State private pressedFolderId: string = '';
  @State private visibleRowCount: number = 0;
  onBack: () => void = () => {};
  onConfirm: () => void = () => {};
  onAddToHomeChange: (selected: boolean) => void = (_selected: boolean) => {};
  onOpenFolder: (folderId: string) => void = (_folderId: string) => {};

  aboutToAppear(): void {
    this.scheduleReloadRows();
  }

  aboutToReuse(_params: Record<string, Object>): void {
    this.scheduleReloadRows();
  }

  aboutToDisappear(): void {
    this.cancelScheduledReload();
  }

  build() {
    ManagementHdsScaffold({
      title: this.title,
      backIconKind: this.isRootDestination ? 'close' : 'back',
      pageBackground: this.pageBackgroundColor,
      primaryTextColor: this.primaryTextColor,
      dividerColor: this.dividerColor,
      showPrivateIndicator: false,
      showBackButton: true,
      useTopSafeInset: false,
      menuActions: this.buildHeaderMenuActions(),
      scrollers: [this.listScroller],
      onBack: () => {
        this.onBack();
      }
    }) {
      Column() {
        this.buildContent()
        if (this.showAddToHome) {
          this.buildAddToHomeRow()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageBackgroundColor)
    }
  }

  @Builder
  private buildContent() {
    if (this.rowCount === 0 && this.isPreparing && this.folderId.length > 0) {
      AppEmptyState({
        title: this.preparingTitle,
        message: '',
        fillHeight: true,
        useCustomIcon: true,
        customIcon: () => {
          this.buildEmptyFolderIcon()
        }
      })
      .layoutWeight(1)
    } else if (this.rowCount === 0) {
      AppEmptyState({
        title: this.folderId.length > 0 ? this.leafEmptyTitle : this.rootEmptyTitle,
        message: this.message,
        fillHeight: true,
        useCustomIcon: true,
        customIcon: () => {
          this.buildEmptyFolderIcon()
        }
      })
      .layoutWeight(1)
    } else {
      List({ space: 0, scroller: this.listScroller }) {
        LazyForEach(this.folderListDataSource, (node: BookmarkNode, index: number) => {
          ListItem() {
            this.buildFolderRow(node, index)
          }
          .width('100%')
          .margin({ top: index <= 0 ? 0 : BOOKMARK_MOVE_FOLDER_ROW_SPACE })
          .reuseId('bookmark_move_folder_sheet_row')
        }, (node: BookmarkNode) => node.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: 16,
        right: 16,
        top: BOOKMARK_MOVE_FOLDER_CONTENT_TOP_PADDING,
        bottom: BOOKMARK_MOVE_FOLDER_CONTENT_BOTTOM_PADDING
      })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .cachedCount(BOOKMARK_MOVE_FOLDER_LIST_CACHE_COUNT, true)
      .clip(false)
    }
  }

  @Builder
  private buildAddToHomeRow() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.house_fill'))
          .fontSize(21)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.secondaryTextColor])
      }
      .width(RECORD_LIST_ROW_ICON_SIZE)
      .height(RECORD_LIST_ROW_ICON_SIZE)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.controlBackgroundColor)
      .borderRadius(RECORD_LIST_ROW_ICON_RADIUS)

      Text('同时添加到主页')
        .layoutWeight(1)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 12 })

      Toggle({ type: ToggleType.Switch, isOn: this.addToHome })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(RECORD_LIST_ROW_HEIGHT)
    .padding({
      left: RECORD_LIST_ROW_HORIZONTAL_INSET,
      right: RECORD_LIST_ROW_HORIZONTAL_INSET
    })
    .margin({
      left: 16,
      right: 16,
      bottom: BOOKMARK_MOVE_FOLDER_CONTENT_BOTTOM_PADDING
    })
    .borderRadius(18)
    .backgroundColor(this.pageBackgroundColor)
    .onClick(() => {
      this.onAddToHomeChange(!this.addToHome);
    })
  }

  @Builder
  private buildFolderRow(node: BookmarkNode, index: number) {
    WebsiteRecordRow({
      title: node.title,
      subtitle: this.resolveFolderSubtitle(node.id),
      pressed: this.pressedFolderId === node.id,
      menuVisible: false,
      leftInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rightInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rowHeight: RECORD_LIST_ROW_HEIGHT,
      rowBorderRadius: 18,
      showDivider: index < this.visibleRowCount - 1,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      pressedBackgroundColor: this.pressedBackgroundColor,
      onTouchAction: (type: TouchType) => {
        this.updatePressedFolder(node.id, type);
      },
      onRowClick: () => {
        this.onOpenFolder(node.id);
      },
      leading: () => {
        this.buildFolderIcon(this.hasFolderContent(node.id))
      },
      trailing: () => {
        this.buildFolderTrailing()
      },
      previewTrailing: () => {
        this.buildFolderTrailing()
      }
    })
  }

  @Builder
  private buildFolderIcon(hasContent: boolean) {
    Row() {
      BookmarkFolderIcon({
        widthVp: 42,
        hasContent: hasContent,
        animatePaper: false
      })
    }
    .width(44)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildEmptyFolderIcon() {
    BookmarkFolderIcon({
      widthVp: 88,
      hasContent: false,
      animatePaper: false
    })
  }

  @Builder
  private buildFolderTrailing() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor([this.secondaryTextColor])
  }

  private scheduleReloadRows(): void {
    this.cancelScheduledReload();
    this.reloadGeneration += 1;
    const generation = this.reloadGeneration;
    const folders = this.folderSelectionViewModel.listChildFolders(this.options, this.folderId);
    this.childFolders = folders;
    this.rowCount = folders.length;
    this.visibleRowCount = 0;
    this.folderListDataSource.replaceNodes([]);
    if (folders.length === 0) {
      return;
    }
    this.appendRowsForGeneration(generation, Math.min(folders.length, BOOKMARK_MOVE_FOLDER_INITIAL_RENDER_LIMIT));
  }

  private cancelScheduledReload(): void {
    if (this.reloadTimer >= 0) {
      clearTimeout(this.reloadTimer);
      this.reloadTimer = -1;
    }
  }

  private appendRowsForGeneration(generation: number, nextCount: number): void {
    if (generation !== this.reloadGeneration) {
      return;
    }
    const safeCount = Math.max(0, Math.min(this.childFolders.length, nextCount));
    const rows: BookmarkNode[] = [];
    for (let index = 0; index < safeCount; index += 1) {
      rows.push(this.createFolderNode(this.childFolders[index]));
    }
    this.visibleRowCount = safeCount;
    this.folderListDataSource.replaceNodes(rows);
    if (safeCount >= this.childFolders.length) {
      return;
    }
    this.reloadTimer = setTimeout(() => {
      this.reloadTimer = -1;
      this.appendRowsForGeneration(generation, safeCount + BOOKMARK_MOVE_FOLDER_RENDER_INCREMENT);
    }, BOOKMARK_MOVE_FOLDER_RENDER_DELAY_MS);
  }

  private createFolderNode(folder: BookmarkFolderOptionView): BookmarkNode {
    return {
      id: folder.id,
      type: 'folder',
      parentId: folder.parentId,
      title: folder.title,
      position: 0,
      createdAt: 0,
      updatedAt: 0,
      sync: {
        state: 'local_only',
        source: 'local',
        lastModifiedAt: 0,
        lastModifiedBy: '',
        deviceId: ''
      }
    };
  }

  private buildHeaderMenuActions(): ManagementHdsMenuAction[] {
    if (this.isRootDestination) {
      return [];
    }
    const actions: ManagementHdsMenuAction[] = [
      {
        label: this.confirmLabel,
        icon: $r('sys.symbol.checkmark'),
        enabled: true,
        action: () => {
          this.onConfirm();
        }
      }
    ];
    return actions;
  }

  private updatePressedFolder(folderId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedFolderId = folderId;
      return;
    }
    if (this.pressedFolderId === folderId) {
      this.pressedFolderId = '';
    }
  }

  private resolveFolderSubtitle(folderId: string): string {
    const folder = this.folderSelectionViewModel.findFolder(this.options, folderId);
    if (folder === undefined) {
      return '';
    }
    return folder.childFolderCount > 0
      ? `${folder.bookmarkCountText}，${folder.childFolderCount} 个文件夹`
      : folder.bookmarkCountText;
  }

  private hasFolderContent(folderId: string): boolean {
    const folder = this.folderSelectionViewModel.findFolder(this.options, folderId);
    if (folder === undefined) {
      return false;
    }
    return folder.bookmarkCount > 0 || folder.childFolderCount > 0;
  }
}
