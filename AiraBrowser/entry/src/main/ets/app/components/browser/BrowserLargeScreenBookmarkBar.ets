import { KeyCode } from '@kit.InputKit';
import { BookmarkNode, BookmarkStorageScope } from '../../../common/models/BrowserModels';
import { sharedBookmarkRepository } from '../../bootstrap/BrowserAppRuntime';
import {
  BrowserDesktopBookmarkBarSnapshot,
  BrowserDesktopBookmarkBarAction,
  BrowserDesktopBookmarkBarViewModel,
  DESKTOP_BOOKMARK_BAR_LAYOUT
} from '../../../core/browser/BrowserDesktopBookmarkBarViewModel';
import { BookmarkStatsVersionSignal, BOOKMARK_STATS_VERSION_KEY } from '../../../core/bookmarks/BookmarkStatsVersionSignal';
import { SiteIconListPresenter, SiteIconListRenderState, SiteIconListTarget } from '../../../core/siteicons/SiteIconListPresenter';
import { SiteIconView } from '../common/SiteIconView';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserDesktopContextMenu, BrowserDesktopContextMenuItem } from './BrowserDesktopContextMenu';
import { BROWSER_DESKTOP_MENU_WIDTH_VP } from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBLE_KEY,
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
  @Prop @Watch('handleLayoutChanged') availableWidthVp: number = 0;
  @Prop barEnabled: boolean = true;
  onAction: (action: BrowserDesktopBookmarkBarAction) => void =
    (_action: BrowserDesktopBookmarkBarAction): void => {};

  @StorageProp(BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBLE_KEY)
  @Watch('handleStoredVisibilityChanged')
  private storedVisibility: boolean = true;
  @StorageProp(BOOKMARK_STATS_VERSION_KEY)
  @Watch('handleBookmarkStatsChanged')
  private storedBookmarkStatsVersion: number = 0;
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
      if (this.barEnabled && this.storedVisibility) {
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
      }
    }
    .width('100%')
    .height(this.barEnabled && this.storedVisibility ? DESKTOP_BOOKMARK_BAR_LAYOUT.heightVp : 0)
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

  private handleStoredVisibilityChanged(): void {
    this.refresh();
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
    .bindContextMenu(this.buildManagerContextMenu(), ResponseType.RightClick)
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
    .bindContextMenu(this.buildBookmarkContextMenu(node), ResponseType.RightClick)
    .bindMenu(node.type === 'folder' ? this.buildFolderMenu(node) : [])
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
    .bindMenu(this.buildOverflowMenu)
  }

  @Builder
  private buildManagerContextMenu() {
    BrowserDesktopContextMenu() {
      BrowserDesktopContextMenuItem({ label: '进入书签管理', onAction: (): void => this.onAction({ kind: 'open_bookmarks' }) })
    }
  }

  @Builder
  private buildBookmarkContextMenu(node: BookmarkNode) {
    BrowserDesktopContextMenu() {
      if (node.type === 'bookmark') {
        MenuItemGroup() {
          BrowserDesktopContextMenuItem({ label: '当前标签打开', shortcut: 'Enter', onAction: (): void => {
            this.onAction({ kind: 'open_bookmark', node: node, target: 'current' });
          } })
          BrowserDesktopContextMenuItem({ label: '新前台标签打开', onAction: (): void => {
            this.onAction({ kind: 'open_bookmark', node: node, target: 'new' });
          } })
          BrowserDesktopContextMenuItem({ label: '后台标签打开', onAction: (): void => {
            this.onAction({ kind: 'open_bookmark', node: node, target: 'background' });
          } })
        }
      }
      MenuItemGroup() {
        BrowserDesktopContextMenuItem({ label: '进入书签管理', onAction: (): void => this.onAction({ kind: 'open_bookmarks' }) })
      }
    }
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
