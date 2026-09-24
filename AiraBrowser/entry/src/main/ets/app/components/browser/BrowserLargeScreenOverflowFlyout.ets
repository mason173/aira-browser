import { BookmarkNode, BookmarkStorageScope } from '../../../common/models/BrowserModels';
import {
  sharedBookmarkRepository,
  sharedHistoryRepository,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  appendOtherBookmarksFolder,
  BROWSER_LARGE_SCREEN_OVERFLOW_BOOKMARK_EMPTY_MESSAGE,
  BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_GAP_VP,
  BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_WIDTH_VP,
  BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_LIMIT,
  BrowserLargeScreenOverflowBookmarkItem,
  BrowserLargeScreenOverflowHistoryItem,
  projectOverflowBookmarkItems,
  projectOverflowHistoryItems,
  resolveOverflowBookmarkOtherRootId,
  resolveOverflowBookmarkScope,
  resolveOverflowBookmarkToolbarRootId,
  resolveOverflowHistoryEmptyMessage
} from '../../../core/browser/BrowserLargeScreenOverflowFlyoutViewModel';
import { toggleDesktopBookmarkBarVisibility } from '../../../core/browser/DesktopBookmarkBarVisibility';
import {
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_SHADOW_OFFSET_Y_VP,
  BROWSER_DESKTOP_MENU_SHADOW_RADIUS_VP,
  BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
  BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP,
  BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
  BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
  BROWSER_DESKTOP_MENU_TEXT_SIZE_FP,
  BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import { BOOKMARK_STATS_VERSION_KEY } from '../../../core/bookmarks/BookmarkStatsVersionSignal';
import {
  BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBLE_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';

const FLYOUT_COLUMN_WIDTH_VP: number =
  BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_WIDTH_VP + BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_GAP_VP;

@Component
struct BrowserLargeScreenOverflowFlyoutPanel {
  @Prop maxHeightVp: number = 320;
  @BuilderParam content: () => void = this.emptyContent;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = '#FFFFFF';

  build() {
    Column() {
      Scroll() {
        Column() {
          this.content()
        }
        .width('100%')
        .padding({
          left: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
          right: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
          top: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
          bottom: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
        })
      }
      .width(BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_WIDTH_VP)
      .constraintSize({ maxHeight: this.maxHeightVp })
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
      .clip(true)
      .borderRadius(BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP)
    }
    .width(BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_WIDTH_VP)
    .backgroundColor(this.storedSurfaceBackgroundColor)
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
  private emptyContent() {
  }
}

@Component
export struct BrowserLargeScreenOverflowFlyoutHost {
  @Prop @Watch('handleKindChanged') kind: string = '';
  @Prop @Watch('handlePrivateModeChanged') privateMode: boolean = false;
  @Prop canAddBookmark: boolean = false;
  @Prop maxHeightVp: number = 320;
  onColumnCountChange: (count: number) => void = (_count: number): void => {};
  onHoverChange: (hovered: boolean) => void = (_hovered: boolean): void => {};
  onOpenHistory: (item: BrowserLargeScreenOverflowHistoryItem) => void =
    (_item: BrowserLargeScreenOverflowHistoryItem): void => {};
  onOpenBookmark: (item: BrowserLargeScreenOverflowBookmarkItem) => void =
    (_item: BrowserLargeScreenOverflowBookmarkItem): void => {};
  onAddBookmark: () => void = (): void => {};
  onOpenManager: () => void = (): void => {};

  @StorageProp(BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBLE_KEY)
  private bookmarkBarVisible: boolean = true;
  @StorageProp(BOOKMARK_STATS_VERSION_KEY)
  @Watch('handleBookmarkStatsChanged')
  private storedBookmarkStatsVersion: number = 0;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';

  @State private historyItems: BrowserLargeScreenOverflowHistoryItem[] = [];
  @State private historyReady: boolean = false;
  @State private bookmarkPath: string[] = [];
  @State private hoveredBookmarkId: string = '';
  @State private bookmarkRevision: number = 0;
  private prepareVersion: number = 0;

  aboutToAppear(): void {
    this.publishColumnCount();
    void this.prepare();
  }

  aboutToDisappear(): void {
    this.prepareVersion += 1;
  }

  build() {
    Row() {
      if (this.kind === 'bookmarks') {
        this.buildBookmarkColumns()
      } else if (this.kind === 'history') {
        this.buildHistoryColumn()
      }
    }
    .alignItems(VerticalAlign.Top)
    .onHover((hovered: boolean): void => {
      this.onHoverChange(hovered);
    })
  }

  @Builder
  private buildHistoryColumn() {
    Column() {
      BrowserLargeScreenOverflowFlyoutPanel({ maxHeightVp: this.maxHeightVp }) {
        if (this.historyItems.length === 0) {
          this.buildMessage(resolveOverflowHistoryEmptyMessage(this.privateMode, this.historyReady))
        }
        ForEach(this.historyItems, (item: BrowserLargeScreenOverflowHistoryItem) => {
          this.buildHistoryRow(item)
        }, (item: BrowserLargeScreenOverflowHistoryItem) => item.id)
      }
    }
    .width(FLYOUT_COLUMN_WIDTH_VP)
    .padding({ right: BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_GAP_VP })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildBookmarkColumns() {
    ForEach(this.bookmarkColumnParentIds(), (parentId: string) => {
      this.buildBookmarkColumn(parentId)
    }, (parentId: string) => `${this.bookmarkRevision}:${this.storedBookmarkStatsVersion}:${parentId}`)
  }

  @Builder
  private buildBookmarkColumn(parentId: string) {
    Column() {
      BrowserLargeScreenOverflowFlyoutPanel({ maxHeightVp: this.maxHeightVp }) {
        if (this.isBookmarkRoot(parentId)) {
          this.buildBookmarkHeader()
          this.buildDivider()
        }
        if (this.bookmarkItems(parentId).length === 0) {
          this.buildMessage(BROWSER_LARGE_SCREEN_OVERFLOW_BOOKMARK_EMPTY_MESSAGE)
        }
        ForEach(this.bookmarkItems(parentId), (item: BrowserLargeScreenOverflowBookmarkItem) => {
          this.buildBookmarkRow(parentId, item)
        }, (item: BrowserLargeScreenOverflowBookmarkItem) => item.id)
      }
    }
    .width(FLYOUT_COLUMN_WIDTH_VP)
    .padding({ right: BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_GAP_VP })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildBookmarkHeader() {
    if (this.canAddBookmark) {
      this.buildCommandRow('browser.toolbar.addBookmark', '添加书签', false, false, 'add')
    }
    this.buildCommandRow('browser.shortcut.bookmarks', '显示书签栏', this.bookmarkBarVisible, false, 'bar')
    this.buildCommandRow('bookmarks.folder', '进入书签管理', false, false, 'manager')
  }

  @Builder
  private buildHistoryRow(item: BrowserLargeScreenOverflowHistoryItem) {
    Row({ space: 10 }) {
      AiraIcon({
        airaIconId: 'browser.shortcut.history',
        iconSize: 18,
        iconColor: this.storedPrimaryTextColor
      })
      Text(item.title)
        .layoutWeight(1)
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
    .padding({
      left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
      right: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP
    })
    .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
    .clip(true)
    .hoverEffect(HoverEffect.Highlight)
    .onClick((): void => {
      this.onOpenHistory(item);
    })
  }

  @Builder
  private buildBookmarkRow(parentId: string, item: BrowserLargeScreenOverflowBookmarkItem) {
    Row({ space: 10 }) {
      AiraIcon({
        airaIconId: this.bookmarkItemIcon(item.folder),
        iconSize: 18,
        iconColor: this.storedPrimaryTextColor
      })
      Text(item.title)
        .layoutWeight(1)
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.folder) {
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
    .backgroundColor(this.hoveredBookmarkId === item.id ? this.storedControlBackgroundColor : Color.Transparent)
    .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
    .clip(true)
    .hoverEffect(HoverEffect.None)
    .onHover((hovered: boolean): void => {
      this.handleBookmarkHover(parentId, item, hovered);
    })
    .onClick((): void => {
      this.handleBookmarkClick(parentId, item);
    })
  }

  @Builder
  private buildCommandRow(
    iconId: AiraRenderableIconId,
    label: string,
    selected: boolean,
    submenu: boolean,
    command: string
  ) {
    Row({ space: 10 }) {
      AiraIcon({
        airaIconId: iconId,
        iconSize: 18,
        iconColor: selected ? this.storedAccentColor : this.storedPrimaryTextColor
      })
      Text(label)
        .layoutWeight(1)
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([this.storedAccentColor])
      }
      if (submenu) {
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
    .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
    .clip(true)
    .hoverEffect(HoverEffect.Highlight)
    .onHover((hovered: boolean): void => {
      if (hovered) {
        this.retainFolderDepth(0);
      }
    })
    .onClick((): void => {
      this.dispatchCommand(command);
    })
  }

  @Builder
  private buildMessage(message: string) {
    Text(message)
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
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private buildDivider() {
    Divider()
      .strokeWidth(BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP)
      .color(this.storedDividerColor)
      .margin({
        left: BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
        right: BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
        top: 4,
        bottom: 4
      })
  }

  private handleKindChanged(): void {
    if (this.kind !== 'bookmarks') {
      this.bookmarkPath = [];
      this.hoveredBookmarkId = '';
    }
    this.publishColumnCount();
    if (this.kind.length > 0) {
      void this.prepare();
    }
  }

  private handlePrivateModeChanged(): void {
    this.bookmarkPath = [];
    this.hoveredBookmarkId = '';
    this.publishColumnCount();
    void this.prepare();
  }

  private handleBookmarkStatsChanged(): void {
    this.bookmarkRevision += 1;
  }

  private dispatchCommand(command: string): void {
    if (command === 'add') {
      this.onAddBookmark();
      return;
    }
    if (command === 'bar') {
      void toggleDesktopBookmarkBarVisibility(sharedPreferencesRepository);
      return;
    }
    if (command === 'manager') {
      this.onOpenManager();
    }
  }

  private bookmarkItemIcon(folder: boolean): AiraRenderableIconId {
    return folder ? 'bookmarks.folder' : 'browser.shortcut.bookmarks';
  }

  private handleBookmarkHover(
    parentId: string,
    item: BrowserLargeScreenOverflowBookmarkItem,
    hovered: boolean
  ): void {
    this.hoveredBookmarkId = hovered
      ? item.id
      : (this.hoveredBookmarkId === item.id ? '' : this.hoveredBookmarkId);
    if (!hovered) {
      return;
    }
    if (item.folder) {
      this.openFolder(this.columnDepth(parentId), item.id);
      return;
    }
    this.retainFolderDepth(this.columnDepth(parentId));
  }

  private handleBookmarkClick(parentId: string, item: BrowserLargeScreenOverflowBookmarkItem): void {
    if (item.folder) {
      this.openFolder(this.columnDepth(parentId), item.id);
      return;
    }
    this.onOpenBookmark(item);
  }

  private async prepare(): Promise<void> {
    const version = this.prepareVersion + 1;
    this.prepareVersion = version;
    const privateMode = this.privateMode;
    try {
      await sharedBookmarkRepository.initialize();
      if (!privateMode) {
        await sharedHistoryRepository.initialize();
        await sharedHistoryRepository.refreshPreview(BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_LIMIT);
      }
    } catch (_error) {
      if (version !== this.prepareVersion) {
        return;
      }
      this.historyReady = true;
      this.historyItems = [];
      return;
    }
    if (version !== this.prepareVersion) {
      return;
    }
    const visits = privateMode ? [] : sharedHistoryRepository.listVisits(BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_LIMIT);
    this.historyItems = projectOverflowHistoryItems(
      visits,
      privateMode,
      BROWSER_LARGE_SCREEN_OVERFLOW_HISTORY_LIMIT
    );
    this.historyReady = true;
    this.bookmarkRevision += 1;
  }

  private publishColumnCount(): void {
    const count = this.kind === 'history' ? 1 : (this.kind === 'bookmarks' ? 1 + this.bookmarkPath.length : 0);
    this.onColumnCountChange(count);
  }

  private bookmarkScope(): BookmarkStorageScope {
    return resolveOverflowBookmarkScope(this.privateMode);
  }

  private toolbarRootId(): string {
    return resolveOverflowBookmarkToolbarRootId(this.bookmarkScope());
  }

  private isBookmarkRoot(parentId: string): boolean {
    return parentId === this.toolbarRootId();
  }

  private bookmarkColumnParentIds(): string[] {
    const ids: string[] = [];
    for (let index = this.bookmarkPath.length - 1; index >= 0; index -= 1) {
      ids.push(this.bookmarkPath[index]);
    }
    ids.push(this.toolbarRootId());
    return ids;
  }

  private columnDepth(parentId: string): number {
    if (this.isBookmarkRoot(parentId)) {
      return 0;
    }
    const index = this.bookmarkPath.indexOf(parentId);
    return index >= 0 ? index + 1 : 0;
  }

  private bookmarkItems(parentId: string): BrowserLargeScreenOverflowBookmarkItem[] {
    const refreshToken = this.bookmarkRevision + this.storedBookmarkStatsVersion;
    if (refreshToken < 0) {
      return [];
    }
    const scope = this.bookmarkScope();
    const items = projectOverflowBookmarkItems(sharedBookmarkRepository.listChildren(parentId, scope));
    if (!this.isBookmarkRoot(parentId)) {
      return items;
    }
    const otherRootId = resolveOverflowBookmarkOtherRootId(scope);
    return appendOtherBookmarksFolder(
      items,
      otherRootId,
      this.countVisibleChildren(sharedBookmarkRepository.listChildren(otherRootId, scope))
    );
  }

  private countVisibleChildren(nodes: BookmarkNode[]): number {
    let count = 0;
    nodes.forEach((node: BookmarkNode): void => {
      if (node.sync.deletedAt === undefined) {
        count += 1;
      }
    });
    return count;
  }

  private openFolder(depth: number, folderId: string): void {
    if (this.bookmarkPath.length > depth && this.bookmarkPath[depth] === folderId) {
      return;
    }
    const next: string[] = [];
    for (let index = 0; index < depth && index < this.bookmarkPath.length; index += 1) {
      next.push(this.bookmarkPath[index]);
    }
    next.push(folderId);
    this.bookmarkPath = next;
    this.publishColumnCount();
  }

  private retainFolderDepth(depth: number): void {
    if (this.bookmarkPath.length <= depth) {
      return;
    }
    const next: string[] = [];
    for (let index = 0; index < depth; index += 1) {
      next.push(this.bookmarkPath[index]);
    }
    this.bookmarkPath = next;
    this.publishColumnCount();
  }
}
