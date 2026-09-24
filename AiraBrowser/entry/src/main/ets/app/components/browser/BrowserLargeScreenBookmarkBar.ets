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
import { BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP, BROWSER_DESKTOP_MENU_WIDTH_VP } from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBILITY_KEY,
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
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
  @State private hoveredItemId: string = '';
  private preparationVersion: number = 0;
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
      .bindContextMenu(this.buildBlankAreaContextMenu(), ResponseType.RightClick, buildBrowserDesktopMenuOptions())
    }
    .width('100%')
    .height(DESKTOP_BOOKMARK_BAR_LAYOUT.heightVp)
    .focusable(true)
    .onKeyEvent((event: KeyEvent): boolean => this.handleKeyEvent(event))
  }

  private refresh(): void {
    const scope: BookmarkStorageScope = this.privateMode ? 'private' : 'regular';
    this.snapshot = this.viewModel.buildSnapshot(scope, this.availableWidthVp);
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
    .onClick((): void => this.onAction({ kind: 'open_bookmarks' }))
    .bindContextMenu(this.buildManagerContextMenu(), ResponseType.RightClick, buildBrowserDesktopMenuOptions())
  }

  @Builder
  private buildBookmarkEntry(node: BookmarkNode) {
    Button() {
      Row({ space: 6 }) {
        if (node.type === 'folder') {
          AiraIcon({ airaIconId: 'bookmarks.folder', iconSize: 16, iconColor: this.storedPrimaryTextColor })
        } else {
          SiteIconView({
            iconUri: this.resolveIconUri(node.id),
            fallbackLabel: this.resolveFallbackLabel(node),
            iconSize: 16,
            cornerRadiusRatio: this.storedIconCornerRatio,
            frameBorderWidth: 0,
            textColor: this.storedSecondaryTextColor,
            containerBackgroundColor: this.storedControlBackgroundColor,
            sourceRevision: this.resolveIconRevision(node.id)
          })
        }
        Text(node.title)
          .layoutWeight(1)
          .fontSize(13)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityText(node.title)
      }
      .width('100%')
      .height(28)
      .clip(true)
    }
    .width(this.viewModel.resolveItemWidth(node))
    .height(28)
    .padding({ left: 8, right: 8 })
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText(node.type === 'folder' ? `文件夹 ${node.title}` : node.title)
    .onClick((): void => {
      if (node.type === 'folder') {
        return;
      }
      this.onAction({ kind: 'open_bookmark', node: node, target: 'current' });
    })
    .onHover((hovered: boolean): void => {
      this.hoveredItemId = hovered ? node.id : (this.hoveredItemId === node.id ? '' : this.hoveredItemId);
    })
    .bindPopup(this.hoveredItemId === node.id, {
      message: node.title,
      placement: Placement.Bottom,
      enableArrow: true,
      autoCancel: true,
      mask: false,
      targetSpace: 4,
      popupColor: this.storedControlBackgroundColor,
      messageOptions: {
        textColor: this.storedPrimaryTextColor,
        font: {
          size: 13,
          weight: FontWeight.Regular
        }
      },
      radius: 8,
      width: 240,
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible && this.hoveredItemId === node.id) {
          this.hoveredItemId = '';
        }
      }
    })
    .bindContextMenu(this.buildNodeContextMenu(node), ResponseType.RightClick, buildBrowserDesktopMenuOptions())
    .bindMenu(node.type === 'folder' ? this.buildFolderMenu(node) : [], buildBrowserDesktopMenuOptions())
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
    .bindMenu(this.buildOverflowMenu, buildBrowserDesktopMenuOptions())
  }

  @Builder
  private buildManagerContextMenu() {
    BrowserDesktopContextMenu() {
      BrowserDesktopContextMenuItem({ label: '打开书签管理器', onAction: (): void => this.onAction({ kind: 'open_bookmarks' }) })
    }
  }

  /**
   * Folder and bookmark items share one model-driven menu: the pure model decides which entries
   * belong to the node, this surface only renders groups and dispatches entry ids.
   */
  @Builder
  private buildNodeContextMenu(node: BookmarkNode) {
    BrowserDesktopContextMenu({ menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP }) {
      ForEach(this.buildMenuModel(node).groups, (group: BrowserDesktopBookmarkBarMenuItem[]): void => {
        MenuItemGroup() {
          ForEach(group, (item: BrowserDesktopBookmarkBarMenuItem): void => {
            BrowserDesktopContextMenuItem({
              menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
              label: item.label,
              itemEnabled: item.enabled,
              checked: item.checked,
              onAction: (): void => this.dispatchMenuItem(node, item.id)
            })
          }, (item: BrowserDesktopBookmarkBarMenuItem): string => item.id)
        }
      }, (group: BrowserDesktopBookmarkBarMenuItem[], groupIndex: number): string => `${node.id}-${groupIndex}`)
    }
  }

  /**
   * Empty-area menu of the bar row. Items and folders own their own menus, so a right click that
   * lands on those entries never reaches this list.
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
  private buildFolderMenu(node: BookmarkNode) {
    Menu() {
      ForEach(this.listFolderChildren(node), (child: BookmarkNode): void => {
        this.buildFolderMenuItem(child)
      }, (child: BookmarkNode): string => child.id)
    }
    .width(BROWSER_DESKTOP_MENU_WIDTH_VP)
  }

  @Builder
  private buildFolderMenuItem(node: BookmarkNode) {
    if (node.type === 'folder' && this.listFolderChildren(node).length > 0) {
      MenuItem({
        content: this.viewModel.resolveMenuTitle(node.title),
        endIcon: $r('sys.media.ohos_ic_public_arrow_right'),
        builder: (): void => this.buildFolderMenu(node)
      })
    } else {
      MenuItem({ content: this.viewModel.resolveMenuTitle(node.title) })
        .onClick((): void => {
          if (node.type === 'bookmark') {
            this.onAction({ kind: 'open_bookmark', node: node, target: 'current' });
          }
        })
    }
  }

  private listFolderChildren(node: BookmarkNode): BookmarkNode[] {
    const scope: BookmarkStorageScope = this.privateMode ? 'private' : 'regular';
    return sharedBookmarkRepository.listChildren(node.id, scope);
  }

  @Builder
  private buildOverflowMenu() {
    Menu() {
      ForEach(this.snapshot.overflowItems, (node: BookmarkNode): void => {
        this.buildFolderMenuItem(node)
      }, (node: BookmarkNode): string => node.id)
    }
    .width(BROWSER_DESKTOP_MENU_WIDTH_VP)
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
