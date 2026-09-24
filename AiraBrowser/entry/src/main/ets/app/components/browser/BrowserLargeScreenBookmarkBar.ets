import { KeyCode } from '@kit.InputKit';
import { BookmarkNode, BookmarkStorageScope } from '../../../common/models/BrowserModels';
import { sharedBookmarkRepository } from '../../bootstrap/BrowserAppRuntime';
import {
  BrowserDesktopBookmarkBarSnapshot,
  BrowserDesktopBookmarkBarAction,
  BrowserDesktopBookmarkBarViewModel,
  DESKTOP_BOOKMARK_BAR_LAYOUT
} from '../../../core/browser/BrowserDesktopBookmarkBarViewModel';
import {
  BrowserDesktopBookmarkBarMenuItem,
  BrowserDesktopBookmarkBarMenuItemId,
  BrowserDesktopBookmarkBarMenuModel,
  buildDesktopBookmarkBarBlankMenuModel,
  buildDesktopBookmarkBarMenuModel,
  resolveDesktopBookmarkBarVisibilityForMenuItem
} from '../../../core/browser/BrowserDesktopBookmarkBarMenuModel';
import { normalizeDesktopBookmarkBarVisibility } from '../../../common/models/BrowserModels';
import { DESKTOP_BOOKMARK_CLIPBOARD_HAS_CONTENT_KEY } from '../../../core/bookmarks/DesktopBookmarkClipboardSignal';
import { BookmarkStatsVersionSignal, BOOKMARK_STATS_VERSION_KEY } from '../../../core/bookmarks/BookmarkStatsVersionSignal';
import { SiteIconListPresenter, SiteIconListRenderState, SiteIconListTarget } from '../../../core/siteicons/SiteIconListPresenter';
import { SiteIconView } from '../common/SiteIconView';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserDesktopContextMenu, BrowserDesktopContextMenuItem, buildBrowserDesktopMenuOptions } from './BrowserDesktopContextMenu';
import {
  alignDesktopSubmenuTop,
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
  BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
  BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP,
  BROWSER_DESKTOP_MENU_SHADOW_OFFSET_Y_VP,
  BROWSER_DESKTOP_MENU_SHADOW_RADIUS_VP,
  BROWSER_DESKTOP_MENU_TEXT_SIZE_FP,
  BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
  BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
  BROWSER_DESKTOP_MENU_WIDTH_VP,
  desktopSubmenuRowTop
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBILITY_KEY,
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';

export { BrowserDesktopBookmarkBarAction } from '../../../core/browser/BrowserDesktopBookmarkBarViewModel';

const EMPTY_BAR_SNAPSHOT: BrowserDesktopBookmarkBarSnapshot = {
  scope: 'regular',
  rootId: '',
  allItems: [],
  visibleItems: [],
  overflowItems: []
};
const EMPTY_BOOKMARK_BAR_MENU_MODEL: BrowserDesktopBookmarkBarMenuModel = { groups: [] };
const BOOKMARK_BAR_ENTRY_HEIGHT_VP: number = 28;
/** Matches bindContextMenu's long-press threshold so the release click does not also navigate. */
const BOOKMARK_BAR_LONG_PRESS_CLICK_SUPPRESS_MS: number = 500;

function isBookmarkBarLongPressRelease(source: SourceType, touchDownAtMs: number): boolean {
  if (source !== SourceType.TouchScreen || touchDownAtMs <= 0) {
    return false;
  }
  const heldMs = Date.now() - touchDownAtMs;
  return heldMs >= BOOKMARK_BAR_LONG_PRESS_CLICK_SUPPRESS_MS && heldMs < 10000;
}

const BOOKMARK_FOLDER_MENU_GAP_VP: number = 8;
const BOOKMARK_FOLDER_MENU_MAX_HEIGHT_VP: number = 520;
const BOOKMARK_FOLDER_MENU_ICON_SIZE_VP: number = 16;
const EMPTY_BOOKMARK_FOLDER_ITEMS: BookmarkNode[] = [];

@Component
struct BrowserLargeScreenBookmarkFolderCascade {
  @Prop rootFolderId: string = '';
  @Prop rootItems: BookmarkNode[] = EMPTY_BOOKMARK_FOLDER_ITEMS;
  @Prop privateMode: boolean = false;
  onOpenBookmark: (node: BookmarkNode) => void = (_node: BookmarkNode): void => {};
  @State private openedFolderIds: string[] = [];
  @State private submenuTops: number[] = [];
  @State private hoveredId: string = '';
  @StorageProp(BOOKMARK_STATS_VERSION_KEY)
  private storedBookmarkStatsVersion: number = 0;
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY)
  private storedFloatingSurfaceColor: string = DEFAULT_THEME_PALETTE.light.floatingSurface;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;
  private columnScrollOffsets: number[] = [];

  build() {
    Row({ space: BOOKMARK_FOLDER_MENU_GAP_VP }) {
      ForEach(this.columnKeys(), (parentKey: string, columnIndex: number): void => {
        this.buildColumn(parentKey, columnIndex)
      }, (parentKey: string): string => `${this.storedBookmarkStatsVersion}:${parentKey}`)
    }
    .alignItems(VerticalAlign.Top)
    .padding({
      right: BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP,
      bottom: BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP
    })
  }

  @Builder
  private buildColumn(parentKey: string, columnIndex: number) {
    Column() {
      Scroll() {
        Column() {
          if (this.columnItems(parentKey).length === 0) {
            Text('此文件夹是空的')
              .width('100%')
              .constraintSize({ minHeight: BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP })
              .padding({
                left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
                right: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
                top: 12,
                bottom: 12
              })
              .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
              .fontColor(this.storedSecondaryTextColor)
          }
          ForEach(this.columnItems(parentKey), (node: BookmarkNode, rowIndex: number): void => {
            this.buildItem(node, columnIndex, rowIndex)
          }, (node: BookmarkNode): string => node.id)
        }
        .width('100%')
        .padding({
          left: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
          right: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
          top: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
          bottom: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
        })
      }
      .width('100%')
      .constraintSize({ maxHeight: BOOKMARK_FOLDER_MENU_MAX_HEIGHT_VP })
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
      .clip(true)
      .borderRadius(BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP)
      .onScroll((_xOffset: number, yOffset: number): void => {
        this.rememberColumnScroll(columnIndex, yOffset);
      })
    }
    .width(BROWSER_DESKTOP_MENU_WIDTH_VP)
    .margin({ top: columnIndex === 0 ? 0 : this.submenuTop(columnIndex - 1) })
    .backgroundColor(this.resolveSurfaceColor())
    .backgroundBlurStyle(BlurStyle.NONE)
    .borderRadius(BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP)
    .clip(false)
    .shadow({
      radius: BROWSER_DESKTOP_MENU_SHADOW_RADIUS_VP,
      color: $r('app.color.elevation_shadow'),
      offsetX: 0,
      offsetY: BROWSER_DESKTOP_MENU_SHADOW_OFFSET_Y_VP
    })
  }

  @Builder
  private buildItemIcon(node: BookmarkNode) {
    AiraIcon({
      airaIconId: node.type === 'folder' ? 'bookmarks.folder' : 'browser.toolbar.siteInfo',
      iconSize: BOOKMARK_FOLDER_MENU_ICON_SIZE_VP,
      iconColor: this.storedSecondaryTextColor
    })
  }

  @Builder
  private buildItem(node: BookmarkNode, columnIndex: number, rowIndex: number) {
    Row({ space: 10 }) {
      this.buildItemIcon(node)
      Text(node.title)
        .layoutWeight(1)
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.hasChildren(node)) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.storedSecondaryTextColor])
      }
    }
    .width('100%')
    .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
    .padding({
      left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
      right: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP
    })
    .backgroundColor(this.hoveredId === node.id ? this.storedPageBackgroundColor : Color.Transparent)
    .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
    .clip(true)
    .hoverEffect(HoverEffect.None)
    .accessibilityText(node.type === 'folder' ? `文件夹 ${node.title}` : node.title)
    .onHover((hovered: boolean): void => {
      this.hoveredId = hovered ? node.id : (this.hoveredId === node.id ? '' : this.hoveredId);
      if (!hovered) {
        return;
      }
      if (this.hasChildren(node)) {
        this.openFolder(columnIndex, node.id, rowIndex);
        return;
      }
      this.retainDepth(columnIndex);
    })
    .onClick((): void => {
      if (node.type === 'bookmark') {
        this.onOpenBookmark(node);
        return;
      }
      if (this.hasChildren(node)) {
        this.openFolder(columnIndex, node.id, rowIndex);
      }
    })
  }

  private resolveSurfaceColor(): ResourceColor {
    return this.storedFloatingSurfaceColor.length > 0
      ? this.storedFloatingSurfaceColor
      : DEFAULT_THEME_PALETTE.light.floatingSurface;
  }

  private columnKeys(): string[] {
    const keys: string[] = [''];
    this.openedFolderIds.forEach((id: string): void => {
      keys.push(id);
    });
    return keys;
  }

  private columnItems(parentKey: string): BookmarkNode[] {
    if (this.storedBookmarkStatsVersion < 0) {
      return [];
    }
    if (parentKey.length === 0) {
      return this.rootFolderId.length > 0 ? this.listChildren(this.rootFolderId) : this.rootItems;
    }
    return this.listChildren(parentKey);
  }

  private hasChildren(node: BookmarkNode): boolean {
    return node.type === 'folder' && this.listChildren(node.id).length > 0;
  }

  private listChildren(folderId: string): BookmarkNode[] {
    const scope: BookmarkStorageScope = this.privateMode ? 'private' : 'regular';
    const visible: BookmarkNode[] = [];
    sharedBookmarkRepository.listChildren(folderId, scope).forEach((node: BookmarkNode): void => {
      if (node.sync.deletedAt === undefined) {
        visible.push(node);
      }
    });
    return visible;
  }

  private openFolder(depth: number, folderId: string, rowIndex: number): void {
    const sameFolder = this.openedFolderIds.length > depth && this.openedFolderIds[depth] === folderId;
    if (!sameFolder) {
      const next: string[] = [];
      for (let index = 0; index < depth && index < this.openedFolderIds.length; index += 1) {
        next.push(this.openedFolderIds[index]);
      }
      next.push(folderId);
      this.openedFolderIds = next;
    }
    this.writeSubmenuTop(depth, this.resolveSubmenuTop(depth, folderId, rowIndex));
  }

  private retainDepth(depth: number): void {
    if (this.openedFolderIds.length <= depth) {
      return;
    }
    const next: string[] = [];
    for (let index = 0; index < depth; index += 1) {
      next.push(this.openedFolderIds[index]);
    }
    this.openedFolderIds = next;
    this.submenuTops = this.submenuTops.slice(0, depth);
  }

  private writeSubmenuTop(depth: number, topVp: number): void {
    const next: number[] = [];
    for (let index = 0; index < depth && index < this.submenuTops.length; index += 1) {
      next.push(this.submenuTops[index]);
    }
    next.push(topVp);
    if (next.length === this.submenuTops.length && next[depth] === this.submenuTops[depth]) {
      return;
    }
    this.submenuTops = next;
  }

  private submenuTop(index: number): number {
    return index >= 0 && index < this.submenuTops.length ? this.submenuTops[index] : 0;
  }

  private resolveSubmenuTop(columnIndex: number, folderId: string, rowIndex: number): number {
    const rowTop = desktopSubmenuRowTop(
      columnIndex === 0 ? 0 : this.submenuTop(columnIndex - 1),
      BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
      rowIndex,
      this.columnScrollOffset(columnIndex)
    );
    return alignDesktopSubmenuTop(rowTop, this.estimateSubmenuHeight(folderId), BOOKMARK_FOLDER_MENU_MAX_HEIGHT_VP);
  }

  private estimateSubmenuHeight(folderId: string): number {
    const rows = Math.max(this.listChildren(folderId).length, 1);
    const content = BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP * 2 + rows * BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP;
    return Math.min(BOOKMARK_FOLDER_MENU_MAX_HEIGHT_VP, content);
  }

  private rememberColumnScroll(columnIndex: number, offset: number): void {
    while (this.columnScrollOffsets.length <= columnIndex) {
      this.columnScrollOffsets.push(0);
    }
    this.columnScrollOffsets[columnIndex] = offset;
  }

  private columnScrollOffset(columnIndex: number): number {
    return columnIndex >= 0 && columnIndex < this.columnScrollOffsets.length
      ? this.columnScrollOffsets[columnIndex]
      : 0;
  }
}

/**
 * One bookmark or folder chip. Long press and right click open the same context menu, because a
 * tablet can show this desktop bar while the pointer is a finger.
 */
@Component
struct BrowserLargeScreenBookmarkBarEntry {
  @Prop node: BookmarkNode;
  @Prop itemWidthVp: number = 0;
  @Prop iconUri: string = '';
  @Prop iconRevision: number = 0;
  @Prop fallbackLabel: string = '';
  @Prop iconCornerRatio: number = 0.3;
  @Prop primaryTextColor: string = '';
  @Prop secondaryTextColor: string = '';
  @Prop controlBackgroundColor: string = '';
  @Prop folderMenuOpen: boolean = false;
  @Prop privateMode: boolean = false;
  @Prop menuModel: BrowserDesktopBookmarkBarMenuModel = EMPTY_BOOKMARK_BAR_MENU_MODEL;
  onOpenBookmark: () => void = (): void => {};
  onOpenFolderMenu: () => void = (): void => {};
  onCloseFolderMenu: () => void = (): void => {};
  onOpenMenuBookmark: (node: BookmarkNode) => void = (_node: BookmarkNode): void => {};
  onMenuItem: (id: BrowserDesktopBookmarkBarMenuItemId) => void =
    (_id: BrowserDesktopBookmarkBarMenuItemId): void => {};
  private touchDownAtMs: number = 0;

  @Builder
  private buildFolderPopup() {
    BrowserLargeScreenBookmarkFolderCascade({
      rootFolderId: this.node.id,
      privateMode: this.privateMode,
      onOpenBookmark: (child: BookmarkNode): void => {
        this.onOpenMenuBookmark(child);
      }
    })
  }

  @Builder
  private buildContextMenu(responseType: ResponseType) {
    if (responseType === ResponseType.LongPress || responseType === ResponseType.RightClick) {
      BrowserDesktopContextMenu({ menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP }) {
        ForEach(this.menuModel.groups, (group: BrowserDesktopBookmarkBarMenuItem[], groupIndex: number): void => {
          MenuItemGroup() {
            ForEach(group, (item: BrowserDesktopBookmarkBarMenuItem): void => {
              BrowserDesktopContextMenuItem({
                menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
                label: item.label,
                itemEnabled: item.enabled,
                checked: item.checked,
                onAction: (): void => this.onMenuItem(item.id)
              })
            }, (item: BrowserDesktopBookmarkBarMenuItem): string => item.id)
          }
        }, (_group: BrowserDesktopBookmarkBarMenuItem[], groupIndex: number): string => `${this.node.id}-${groupIndex}`)
      }
    }
  }

  build() {
    Button() {
      Row({ space: 6 }) {
        if (this.node.type === 'folder') {
          AiraIcon({ airaIconId: 'bookmarks.folder', iconSize: 16, iconColor: this.primaryTextColor })
        } else {
          SiteIconView({
            iconUri: this.iconUri,
            fallbackLabel: this.fallbackLabel,
            iconSize: 16,
            cornerRadiusRatio: this.iconCornerRatio,
            frameBorderWidth: 0,
            textColor: this.secondaryTextColor,
            containerBackgroundColor: this.controlBackgroundColor,
            sourceRevision: this.iconRevision
          })
        }
        Text(this.node.title)
          .layoutWeight(1)
          .fontSize(13)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(BOOKMARK_BAR_ENTRY_HEIGHT_VP)
      .clip(true)
    }
    .width(this.itemWidthVp)
    .height(BOOKMARK_BAR_ENTRY_HEIGHT_VP)
    .padding({ left: 8, right: 8 })
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText(this.node.type === 'folder' ? `文件夹 ${this.node.title}` : this.node.title)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.touchDownAtMs = Date.now();
      }
    })
    .onClick((event: ClickEvent): void => {
      if (isBookmarkBarLongPressRelease(event.source, this.touchDownAtMs)) {
        return;
      }
      if (this.node.type === 'folder') {
        this.onOpenFolderMenu();
        return;
      }
      this.onOpenBookmark();
    })
    .bindContextMenuWithResponse(this.buildContextMenu, buildBrowserDesktopMenuOptions({
      preview: MenuPreviewMode.NONE
    }))
    // The builder reference must stay in this literal. Passing it through a function drops the
    // component instance, and opening the folder then crashes.
    .bindPopup(this.folderMenuOpen, {
      builder: this.buildFolderPopup,
      placement: Placement.BottomLeft,
      popupColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      radius: 0,
      borderWidth: 0,
      outlineWidth: 0,
      shadow: {
        radius: 0,
        color: '#00000000',
        offsetX: 0,
        offsetY: 0
      },
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible) {
          this.onCloseFolderMenu();
        }
      }
    })
  }
}

@Component
export struct BrowserLargeScreenBookmarkBar {
  @Prop privateMode: boolean = false;
  /** Bookmark-bar content width in vp; the parent surface owns bar visibility. */
  @Prop @Watch('handleLayoutChanged') availableWidthVp: number = 0;
  onAction: (action: BrowserDesktopBookmarkBarAction) => void =
    (_action: BrowserDesktopBookmarkBarAction): void => {};

  @StorageProp(BOOKMARK_STATS_VERSION_KEY)
  @Watch('handleBookmarkStatsChanged')
  private storedBookmarkStatsVersion: number = 0;
  @StorageProp(BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBILITY_KEY)
  private storedBarVisibility: string = 'always';
  @StorageProp(DESKTOP_BOOKMARK_CLIPBOARD_HAS_CONTENT_KEY)
  private storedClipboardHasContent: boolean = false;
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY)
  private storedIconCornerRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;

  @State private snapshot: BrowserDesktopBookmarkBarSnapshot = EMPTY_BAR_SNAPSHOT;
  @State private iconStates: SiteIconListRenderState[] = [];
  @State private openFolderMenuId: string = '';
  @State private overflowMenuOpen: boolean = false;
  private preparationVersion: number = 0;
  private managerTouchDownAtMs: number = 0;
  private readonly viewModel: BrowserDesktopBookmarkBarViewModel =
    new BrowserDesktopBookmarkBarViewModel(sharedBookmarkRepository);
  private readonly iconPresenter: SiteIconListPresenter = new SiteIconListPresenter();

  aboutToAppear(): void {
    this.refresh();
    this.prepareRepository();
    this.iconPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildIconTargets(),
      (result): void => {
        this.iconStates = this.iconPresenter.applyResolvedIcon(this.iconStates, result);
      }
    );
  }

  aboutToDisappear(): void {
    this.preparationVersion += 1;
    this.iconPresenter.dispose();
  }

  build() {
    Column() {
      Row({ space: DESKTOP_BOOKMARK_BAR_LAYOUT.itemGapVp }) {
        this.buildManagerEntry()
        ForEach(this.snapshot.visibleItems, (node: BookmarkNode): void => {
          this.buildBookmarkEntry(node)
        }, (node: BookmarkNode): string => node.id)
        if (this.snapshot.overflowItems.length > 0) {
          this.buildOverflowEntry()
        }
      }
      .width('100%')
      .height(DESKTOP_BOOKMARK_BAR_LAYOUT.heightVp)
      .padding({ left: DESKTOP_BOOKMARK_BAR_LAYOUT.horizontalInsetVp, right: DESKTOP_BOOKMARK_BAR_LAYOUT.horizontalInsetVp })
      .backgroundColor(this.storedPageBackgroundColor)
      .border({ width: { bottom: 1 }, color: this.storedDividerColor })
      .bindContextMenuWithResponse(this.buildBlankAreaContextMenuResponse, buildBrowserDesktopMenuOptions({
        preview: MenuPreviewMode.NONE
      }))
    }
    .width('100%')
    .height(DESKTOP_BOOKMARK_BAR_LAYOUT.heightVp)
    .focusable(true)
    .onKeyEvent((event: KeyEvent): boolean => this.handleKeyEvent(event))
  }

  private refresh(): void {
    const scope: BookmarkStorageScope = this.privateMode ? 'private' : 'regular';
    this.snapshot = this.viewModel.buildSnapshot(scope, this.availableWidthVp);
    if (this.openFolderMenuId.length > 0 &&
      !this.snapshot.visibleItems.some((node: BookmarkNode): boolean => node.id === this.openFolderMenuId)) {
      this.openFolderMenuId = '';
    }
    this.iconStates = [];
    this.iconPresenter.resolveTargets(this.buildIconTargets(), (result): void => {
      this.iconStates = this.iconPresenter.applyResolvedIcon(this.iconStates, result);
    }, { resolutionPolicy: 'remoteAllowed' });
  }

  private prepareRepository(): void {
    const requestVersion = ++this.preparationVersion;
    void this.viewModel.prepare().then((): void => {
      if (requestVersion === this.preparationVersion) {
        this.refresh();
      }
    }, (_error: Error): void => {});
  }

  private handleLayoutChanged(): void {
    this.refresh();
  }

  private handleBookmarkStatsChanged(): void {
    if (this.storedBookmarkStatsVersion === BookmarkStatsVersionSignal.readVersion()) {
      this.refresh();
    }
  }

  private buildIconTargets(): SiteIconListTarget[] {
    return this.snapshot.allItems
      .filter((node: BookmarkNode): boolean => node.type === 'bookmark' && (node.url ?? '').trim().length > 0)
      .map((node: BookmarkNode): SiteIconListTarget => {
        return { id: node.id, url: node.url ?? '' };
      });
  }

  @Builder
  private buildManagerEntry() {
    Button() {
      AiraIcon({ airaIconId: 'browser.shortcut.bookmarks', iconSize: 17, iconColor: this.storedSecondaryTextColor })
    }
    .width(DESKTOP_BOOKMARK_BAR_LAYOUT.leadingEntryWidthVp)
    .height(28)
    .type(ButtonType.Circle)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .accessibilityText('打开书签管理')
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.managerTouchDownAtMs = Date.now();
      }
    })
    .onClick((event: ClickEvent): void => {
      if (isBookmarkBarLongPressRelease(event.source, this.managerTouchDownAtMs)) {
        return;
      }
      this.onAction({ kind: 'open_bookmarks' });
    })
    .bindContextMenuWithResponse(this.buildManagerContextMenuResponse, buildBrowserDesktopMenuOptions({
      preview: MenuPreviewMode.NONE
    }))
  }

  @Builder
  private buildBookmarkEntry(node: BookmarkNode) {
    BrowserLargeScreenBookmarkBarEntry({
      node: node,
      itemWidthVp: this.viewModel.resolveItemWidth(node),
      iconUri: this.resolveIconUri(node.id),
      iconRevision: this.resolveIconRevision(node.id),
      fallbackLabel: this.resolveFallbackLabel(node),
      iconCornerRatio: this.storedIconCornerRatio,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      controlBackgroundColor: this.storedControlBackgroundColor,
      folderMenuOpen: node.type === 'folder' && this.openFolderMenuId === node.id,
      menuModel: this.buildMenuModel(node),
      onOpenBookmark: (): void => {
        this.onAction({ kind: 'open_bookmark', node: node, target: 'current' });
      },
      onOpenFolderMenu: (): void => {
        this.openFolderMenuId = node.id;
      },
      onCloseFolderMenu: (): void => {
        if (this.openFolderMenuId === node.id) {
          this.openFolderMenuId = '';
        }
      },
      privateMode: this.privateMode,
      onOpenMenuBookmark: (child: BookmarkNode): void => {
        this.openFolderMenuId = '';
        this.onAction({ kind: 'open_bookmark', node: child, target: 'current' });
      },
      onMenuItem: (id: BrowserDesktopBookmarkBarMenuItemId): void => {
        this.dispatchMenuItem(node, id);
      }
    })
  }

  @Builder
  private buildOverflowEntry() {
    Button() {
      AiraIcon({ airaIconId: 'browser.toolbar.more', iconSize: 17, iconColor: this.storedSecondaryTextColor })
    }
    .width(DESKTOP_BOOKMARK_BAR_LAYOUT.overflowEntryWidthVp)
    .height(28)
    .type(ButtonType.Circle)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .accessibilityText('更多书签')
    .onClick((): void => {
      this.overflowMenuOpen = true;
    })
    .bindPopup(this.overflowMenuOpen, {
      builder: this.buildOverflowMenu,
      placement: Placement.BottomLeft,
      popupColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      radius: 0,
      borderWidth: 0,
      outlineWidth: 0,
      shadow: {
        radius: 0,
        color: '#00000000',
        offsetX: 0,
        offsetY: 0
      },
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible) {
          this.overflowMenuOpen = false;
        }
      }
    })
  }

  @Builder
  private buildBlankAreaContextMenuResponse(responseType: ResponseType) {
    if (responseType === ResponseType.LongPress || responseType === ResponseType.RightClick) {
      this.buildBlankAreaContextMenu()
    }
  }

  @Builder
  private buildManagerContextMenuResponse(responseType: ResponseType) {
    if (responseType === ResponseType.LongPress || responseType === ResponseType.RightClick) {
      this.buildManagerContextMenu()
    }
  }

  @Builder
  private buildManagerContextMenu() {
    BrowserDesktopContextMenu() {
      BrowserDesktopContextMenuItem({ label: '打开书签管理器', onAction: (): void => this.onAction({ kind: 'open_bookmarks' }) })
    }
  }

  /**
   * Empty-area menu of the bar row. Items and folders own their own menus, so a right click or
   * long press that lands on those entries never reaches this list.
   */
  @Builder
  private buildBlankAreaContextMenu() {
    BrowserDesktopContextMenu({ menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP }) {
      ForEach(this.buildBlankMenuModel().groups, (group: BrowserDesktopBookmarkBarMenuItem[]): void => {
        MenuItemGroup() {
          ForEach(group, (item: BrowserDesktopBookmarkBarMenuItem): void => {
            BrowserDesktopContextMenuItem({
              menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
              label: item.label,
              itemEnabled: item.enabled,
              checked: item.checked,
              onAction: (): void => this.dispatchBlankMenuItem(item.id)
            })
          }, (item: BrowserDesktopBookmarkBarMenuItem): string => item.id)
        }
      }, (group: BrowserDesktopBookmarkBarMenuItem[], groupIndex: number): string => `bar-blank-${groupIndex}`)
    }
  }

  private buildBlankMenuModel(): BrowserDesktopBookmarkBarMenuModel {
    return buildDesktopBookmarkBarBlankMenuModel({
      barVisibility: normalizeDesktopBookmarkBarVisibility(this.storedBarVisibility)
    });
  }

  /** Bar-wide commands resolve against the toolbar root that this bar renders. */
  private dispatchBlankMenuItem(id: BrowserDesktopBookmarkBarMenuItemId): void {
    const visibility = resolveDesktopBookmarkBarVisibilityForMenuItem(id);
    if (visibility !== undefined) {
      this.onAction({ kind: 'set_bar_visibility', visibility: visibility });
      return;
    }
    const scope: BookmarkStorageScope = this.privateMode ? 'private' : 'regular';
    if (id === 'add_bookmark') {
      this.onAction({ kind: 'add_bookmark_to_bar', scope: scope });
      return;
    }
    if (id === 'add_folder') {
      this.onAction({ kind: 'add_folder_to_bar', scope: scope });
      return;
    }
    if (id === 'open_manager') {
      this.onAction({ kind: 'open_bookmarks' });
    }
  }

  private buildMenuModel(node: BookmarkNode): BrowserDesktopBookmarkBarMenuModel {
    return buildDesktopBookmarkBarMenuModel({
      node: node,
      barVisibility: normalizeDesktopBookmarkBarVisibility(this.storedBarVisibility),
      hasClipboardContent: this.storedClipboardHasContent
    });
  }

  private dispatchMenuItem(node: BookmarkNode, id: BrowserDesktopBookmarkBarMenuItemId): void {
    const visibility = resolveDesktopBookmarkBarVisibilityForMenuItem(id);
    if (visibility !== undefined) {
      this.onAction({ kind: 'set_bar_visibility', visibility: visibility });
      return;
    }
    if (id === 'open_new_tab') {
      this.onAction({ kind: 'open_bookmark', node: node, target: 'new' });
      return;
    }
    if (id === 'open_new_window') {
      this.onAction({ kind: 'open_bookmark', node: node, target: 'new_window' });
      return;
    }
    if (id === 'open_private_window') {
      this.onAction({ kind: 'open_bookmark', node: node, target: 'private_window' });
      return;
    }
    if (id === 'open_manager') {
      this.onAction({ kind: 'open_bookmarks' });
      return;
    }
    if (id === 'rename_node') {
      this.onAction({ kind: 'rename_node', node: node });
      return;
    }
    if (id === 'delete_node') {
      this.onAction({ kind: 'delete_node', node: node });
      return;
    }
    if (id === 'add_bookmark') {
      this.onAction({ kind: 'add_bookmark', node: node });
      return;
    }
    if (id === 'add_folder') {
      this.onAction({ kind: 'add_folder', node: node });
      return;
    }
    if (id === 'cut_node') {
      this.onAction({ kind: 'cut_node', node: node });
      return;
    }
    if (id === 'copy_node') {
      this.onAction({ kind: 'copy_node', node: node });
      return;
    }
    this.onAction({ kind: 'paste_node', node: node });
  }

  @Builder
  private buildOverflowMenu() {
    BrowserLargeScreenBookmarkFolderCascade({
      rootItems: this.snapshot.overflowItems,
      privateMode: this.privateMode,
      onOpenBookmark: (child: BookmarkNode): void => {
        this.overflowMenuOpen = false;
        this.onAction({ kind: 'open_bookmark', node: child, target: 'current' });
      }
    })
  }

  private resolveIconUri(id: string): string {
    return this.iconStates.find((item: SiteIconListRenderState): boolean => item.id === id)?.path ?? '';
  }

  private resolveIconRevision(id: string): number {
    return this.iconStates.find((item: SiteIconListRenderState): boolean => item.id === id)?.sourceRevision ?? 0;
  }

  private resolveFallbackLabel(node: BookmarkNode): string {
    const title = node.title.trim();
    return title.length > 0 ? title.substring(0, 1).toUpperCase() : '书';
  }

  private handleKeyEvent(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    return event.keyCode === KeyCode.KEYCODE_ESCAPE;
  }
}
