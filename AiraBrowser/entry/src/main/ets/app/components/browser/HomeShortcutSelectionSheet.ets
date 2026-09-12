import { image } from '@kit.ImageKit';
import {
  HomeSystemShortcutTarget
} from '../../../common/models/BrowserModels';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  HomeShortcutBookmarkSelectionRow,
  HomeShortcutSelectionAction,
  HomeShortcutSelectionState,
  HomeShortcutSystemSelectionRow
} from '../../../core/shortcuts/HomeShortcutSelectionCoordinator';
import {
  SiteIconListPresenter,
  SiteIconListRenderState,
  SiteIconListResolveOptions,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BookmarkFolderIcon } from '../bookmarks/BookmarkFolderIcon';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';
import { AppEmptyState } from '../common/AppEmptyState';
import { AiraIcon } from '../common/AiraIcon';
import { resolveHomeSystemShortcutDefinition } from '../../../services/shortcuts/HomeSystemShortcutCatalog';
import { SettingsGroupCard, SettingsGroupDivider } from '../settings/SettingsLayout';
import { SettingsNavigationRow } from '../settings/SettingsRows';
import {
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetIconButton
} from './BrowserModalBottomSheet';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserFloatingGlassMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';

const HOME_SHORTCUT_SELECTION_TABS: SegmentedTabOption[] = [
  { id: 'system', title: '系统入口' },
  { id: 'bookmarks', title: '书签' }
];
const HOME_SHORTCUT_SELECTION_ROW_HEIGHT: number = 62;
const HOME_SHORTCUT_SELECTION_ICON_SIZE: number = 42;
const HOME_SHORTCUT_SELECTION_ACTION_SIZE: number = 40;
const HOME_SHORTCUT_SELECTION_LIST_CACHE_COUNT: number = 12;
const HOME_SHORTCUT_BOOKMARK_DESTINATION_NAME: string = 'homeShortcutBookmarkDestination';
const HOME_SHORTCUT_SELECTION_RAIL_WIDTH: number = 154;
const HOME_SHORTCUT_SELECTION_WORKSPACE_RADIUS: number = 22;
const HOME_SHORTCUT_SELECTION_CONTENT_TOP_PADDING: number = 112;

export type HomeShortcutSelectionLayoutMode = 'phone' | 'large_screen';

const EMPTY_HOME_SHORTCUT_SELECTION_STATE: HomeShortcutSelectionState = {
  sessionId: 0,
  scenarioId: 'aira_default_scenario',
  activeTab: 'system',
  currentFolderId: '',
  currentFolderTitle: '书签',
  systemRows: [],
  bookmarkRows: [],
  busyKeys: [],
  bookmarksLoading: false
};

class HomeShortcutBookmarkRowDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private rows: HomeShortcutBookmarkSelectionRow[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): HomeShortcutBookmarkSelectionRow {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replaceRows(rows: HomeShortcutBookmarkSelectionRow[]): void {
    this.rows = rows.slice();
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}

class HomeShortcutBookmarkDestinationParams {
  folderId: string = '';

  constructor(folderId: string = '') {
    this.folderId = folderId;
  }
}

@Component
export struct HomeShortcutSelectionSheet {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @Prop state: HomeShortcutSelectionState = EMPTY_HOME_SHORTCUT_SELECTION_STATE;
  onAction: (action: HomeShortcutSelectionAction) => void = (_action: HomeShortcutSelectionAction) => {};
  onClose: () => void = () => {};

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      HomeShortcutSelectionContent({
        state: this.state,
        layoutMode: 'phone',
        onAction: this.onAction,
        onClose: this.onClose
      })
    }
  }
}

@Component
export struct HomeShortcutSelectionContent {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY)
  private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop
  @Watch('syncBookmarkRows')
  state: HomeShortcutSelectionState = EMPTY_HOME_SHORTCUT_SELECTION_STATE;
  @Prop layoutMode: HomeShortcutSelectionLayoutMode = 'phone';
  @State private bookmarkIconStates: SiteIconListRenderState[] = [];
  @State private hoveredNavigationTab: string = '';
  private bookmarkIconLookupSource: SiteIconListRenderState[] = [];
  private bookmarkIconLookup: Record<string, SiteIconListRenderState | undefined> = {};
  private bookmarkNavigationStack: NavPathStack = new NavPathStack();
  private bookmarkRowsSourceByFolderId: Map<string, HomeShortcutBookmarkRowDataSource> = new Map();
  private bookmarkRowsByFolderId: Map<string, HomeShortcutBookmarkSelectionRow[]> = new Map();
  private bookmarkTitleByFolderId: Map<string, string> = new Map();
  private bookmarkNavigationSessionId: number = -1;
  private bookmarkNavigationActionGeneration: number = 0;
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  private siteIconUpdatesBound: boolean = false;

  onAction: (action: HomeShortcutSelectionAction) => void = (_action: HomeShortcutSelectionAction) => {};
  onClose: () => void = () => {};

  aboutToAppear(): void {
    this.bindSiteIconUpdates();
    this.syncBookmarkRows();
  }

  aboutToReuse(_params: Record<string, Object>): void {
    this.bindSiteIconUpdates();
    this.syncBookmarkRows();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
    this.siteIconUpdatesBound = false;
    this.bookmarkNavigationActionGeneration += 1;
  }

  build() {
    if (this.layoutMode === 'large_screen') {
      this.buildLargeScreenLayout()
    } else {
      this.buildPhoneLayout()
    }
  }

  @Builder
  private buildPhoneLayout() {
    BrowserImmersiveSheetLayout({
      scrollContent: () => {
        this.buildActiveSelectionList()
      },
      header: () => {
        this.buildPhoneHeader()
      }
    })
  }

  @Builder
  private buildPhoneHeader() {
    Column({ space: 14 }) {
      BrowserFeatureSheetHeader({
        title: '添加至首页',
        leadingAccessibilityLabel: '关闭添加至首页',
        onLeadingAction: () => {
          this.onClose();
        }
      })

      // Same segmented-tab treatment as the history page: a glass bar surface
      // wrapping SegmentedTabs instead of the bare control.
      FloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: 36,
        surfaceRadius: 18,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        fallbackColor: this.storedControlBackgroundColor,
        backgroundBlurEnabled: false
      }) {
        SegmentedTabs({
          options: HOME_SHORTCUT_SELECTION_TABS,
          selectedId: this.state.activeTab,
          barHeight: 36,
          itemHeight: 30,
          fontSize: 14,
          barPadding: 3,
          fallbackColor: $r('sys.color.ohos_id_color_background_transparent'),
          barMaterialEnabled: false,
          onSelect: (id: string) => {
            this.selectNavigationTab(id);
          }
        })
          .width('100%')
          .height(36)
      }
    }
    .width('100%')
  }

  @Builder
  private buildLargeScreenLayout() {
    Row() {
      Column({ space: 4 }) {
        this.buildLargeScreenNavigationItem('system', 'browser.toolbar.menu', '系统入口')
        this.buildLargeScreenNavigationItem('bookmarks', 'browser.shortcut.bookmarks', '书签')
      }
      .width(HOME_SHORTCUT_SELECTION_RAIL_WIDTH)
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ right: 14 })

      Divider()
        .vertical(true)
        .height('100%')
        .strokeWidth(1)
        .color(this.storedControlBackgroundColor)

      Column() {
        this.buildActiveSelectionList()
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 18 })
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .borderRadius(HOME_SHORTCUT_SELECTION_WORKSPACE_RADIUS)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildLargeScreenNavigationItem(tab: string, iconId: AiraRenderableIconId, title: string) {
    Row({ space: 10 }) {
      AiraIcon({
        airaIconId: iconId,
        iconSize: 19,
        iconColor: this.state.activeTab === tab ? this.storedPrimaryTextColor : this.storedSecondaryTextColor
      })

      Text(title)
        .fontSize(14)
        .fontWeight(this.state.activeTab === tab ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.state.activeTab === tab ? this.storedPrimaryTextColor : this.storedSecondaryTextColor)
        .maxLines(1)
    }
    .width('100%')
    .height(42)
    .padding({ left: 12, right: 10 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.resolveNavigationItemBackground(tab))
    .borderRadius(6)
    .accessibilityText(title)
    .onHover((hovered: boolean) => {
      this.hoveredNavigationTab = hovered ? tab : '';
    })
    .onClick(() => {
      this.selectNavigationTab(tab);
    })
  }

  @Builder
  private buildActiveSelectionList() {
    if (this.state.activeTab === 'system') {
      this.buildSystemList()
    } else {
      this.buildBookmarkNavigation()
    }
  }

  @Builder
  private buildSystemList() {
    Column() {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        List({ space: 0 }) {
          ForEach(this.state.systemRows, (row: HomeShortcutSystemSelectionRow, index: number) => {
            ListItem() {
              this.buildSystemRow(row, index)
            }
            .width('100%')
          }, (row: HomeShortcutSystemSelectionRow) =>
            `${row.target}:${row.added ? 'added' : 'available'}:${this.isBusy(row.busyKey) ? 'busy' : 'idle'}`)
        }
        .width('100%')
        .height('100%')
        .padding({
          top: this.layoutMode === 'phone' ? HOME_SHORTCUT_SELECTION_CONTENT_TOP_PADDING : 0,
          bottom: this.layoutMode === 'phone' ? BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING : 0
        })
        .cachedCount(HOME_SHORTCUT_SELECTION_LIST_CACHE_COUNT)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
  }

  @Builder
  private buildSystemRow(row: HomeShortcutSystemSelectionRow, index: number) {
    WebsiteRecordRow({
      title: row.title,
      subtitle: '',
      rowHeight: HOME_SHORTCUT_SELECTION_ROW_HEIGHT,
      showDivider: index < this.state.systemRows.length - 1,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      leading: () => {
        this.buildSystemIcon(row.target)
      },
      trailing: () => {
        this.buildToggleButton(row.added, this.isBusy(row.busyKey), () => {
          this.onAction({ type: 'toggle_system', target: row.target });
        }, row.added ? `从首页移除${row.title}` : `添加${row.title}至首页`)
      }
    })
  }

  @Builder
  private buildBookmarkNavigation() {
    Navigation(this.bookmarkNavigationStack) {
      this.buildBookmarkPage('')
    }
    .width('100%')
    .layoutWeight(1)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideNavBar(false)
    .navDestination(this.buildBookmarkDestination)
    .backgroundColor(this.resolveSelectionWorkspaceBackground())
  }

  @Builder
  private buildBookmarkDestination(name: string, param: Object) {
    if (name === HOME_SHORTCUT_BOOKMARK_DESTINATION_NAME) {
      NavDestination() {
        this.buildBookmarkPage((param as HomeShortcutBookmarkDestinationParams).folderId)
      }
      .hideTitleBar(true)
      .backgroundColor(this.resolveSelectionWorkspaceBackground())
      .onBackPressed(() => {
        this.navigateBackBookmarkFolder();
        return true;
      })
    }
  }

  @Builder
  private buildBookmarkPage(folderId: string) {
    Column({ space: 10 }) {
      if (folderId.length <= 0 && this.state.bookmarksLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.storedAccentColor)
          Text('正在加载书签…')
            .fontSize(13)
            .fontColor(this.storedSecondaryTextColor)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: this.layoutMode === 'phone' ? HOME_SHORTCUT_SELECTION_CONTENT_TOP_PADDING : 0 })
        .justifyContent(FlexAlign.Center)
      } else if (this.resolveBookmarkRows(folderId).length > 0) {
        this.buildBookmarkList(folderId)
      } else {
        AppEmptyState({
          airaIconId: 'browser.shortcut.bookmarks',
          title: '这里还没有书签',
          message: '',
          topPadding: this.layoutMode === 'phone' ? HOME_SHORTCUT_SELECTION_CONTENT_TOP_PADDING : 48,
          bottomPadding: 80,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.resolveSelectionWorkspaceBackground())
  }

  @Builder
  private buildBookmarkList(folderId: string) {
    Column() {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        List({ space: 0 }) {
          if (folderId.length > 0) {
            ListItem() {
              this.buildBookmarkFolderHeader(folderId)
            }
            .width('100%')
          }

          LazyForEach(this.resolveBookmarkRowsSource(folderId),
            (row: HomeShortcutBookmarkSelectionRow, index: number) => {
            ListItem() {
              this.buildBookmarkRow(row, index, folderId)
            }
            .width('100%')
            .reuseId(row.kind === 'folder' ? 'home_shortcut_folder_row' : 'home_shortcut_bookmark_row')
          }, (row: HomeShortcutBookmarkSelectionRow) =>
            `${row.id}:${row.kind}:${row.added ? 'added' : 'available'}:${this.isBusy(row.busyKey) ? 'busy' : 'idle'}`)
        }
        .width('100%')
        .height('100%')
        .padding({
          top: this.layoutMode === 'phone' ? HOME_SHORTCUT_SELECTION_CONTENT_TOP_PADDING : 0,
          bottom: this.layoutMode === 'phone' ? BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING : 0
        })
        .cachedCount(HOME_SHORTCUT_SELECTION_LIST_CACHE_COUNT, true)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
  }

  @Builder
  private buildBookmarkFolderHeader(folderId: string) {
    Row({ space: 10 }) {
      BrowserSheetIconButton({
        icon: $r('sys.symbol.chevron_left'),
        accessibilityLabel: '返回上一级',
        onAction: () => {
          this.navigateBackBookmarkFolder();
        }
      })

      Text(this.resolveBookmarkFolderTitle(folderId))
        .layoutWeight(1)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildBookmarkRow(row: HomeShortcutBookmarkSelectionRow, index: number, folderId: string) {
    if (row.kind === 'folder') {
      Column() {
        SettingsNavigationRow({
          title: row.title,
          value: '',
          description: '',
          useCustomLeading: true,
          isEnabled: true,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.openBookmarkFolder(row.id);
          },
          customLeading: () => {
            this.buildFolderIcon(row.folderBookmarkCount)
          }
        })

        if (index < this.resolveBookmarkRows(folderId).length - 1) {
          SettingsGroupDivider()
        }
      }
      .width('100%')
    } else {
      WebsiteRecordRow({
        iconUri: this.resolveBookmarkIconUri(row.id),
        iconPixelMap: this.resolveBookmarkIconPixelMap(row.id),
        fallbackLabel: resolveSiteIconFallbackLabel(row.title, row.url),
        title: row.title,
        subtitle: row.url,
        rowHeight: HOME_SHORTCUT_SELECTION_ROW_HEIGHT,
        iconSize: HOME_SHORTCUT_SELECTION_ICON_SIZE,
        iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
        preferPixelMap: this.resolveBookmarkIconPixelMap(row.id) !== undefined,
        sourceRevision: this.resolveBookmarkIconSourceRevision(row.id),
        showDivider: index < this.resolveBookmarkRows(folderId).length - 1,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onIconLoadError: (iconUri: string, sourceRevision: number) => {
          this.resolveBookmarkPixelMapAfterUriFailure(row, iconUri, sourceRevision);
        },
        trailing: () => {
          this.buildToggleButton(row.added, this.isBusy(row.busyKey), () => {
            this.onAction({ type: 'toggle_bookmark', bookmarkId: row.id });
          }, row.added ? `从首页移除${row.title}` : `添加${row.title}至首页`)
        }
      })
    }
  }

  @Builder
  private buildSystemIcon(target: HomeSystemShortcutTarget) {
    Row() {
      AiraIcon({
        airaIconId: resolveHomeSystemShortcutDefinition(target)?.iconId ?? 'browser.toolbar.siteInfo',
        iconSize: 24,
        iconColor: this.storedSecondaryTextColor
      })
    }
    .width(HOME_SHORTCUT_SELECTION_ICON_SIZE)
    .height(HOME_SHORTCUT_SELECTION_ICON_SIZE)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(13)
  }

  @Builder
  private buildFolderIcon(folderBookmarkCount: number) {
    Row() {
      BookmarkFolderIcon({
        widthVp: HOME_SHORTCUT_SELECTION_ICON_SIZE,
        hasContent: folderBookmarkCount > 0,
        animatePaper: false,
        count: folderBookmarkCount
      })
    }
    .width(HOME_SHORTCUT_SELECTION_ICON_SIZE)
    .height(HOME_SHORTCUT_SELECTION_ICON_SIZE)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildToggleButton(
    added: boolean,
    busy: boolean,
    action: () => void,
    accessibilityLabel: string
  ) {
    Stack({ alignContent: Alignment.Center }) {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: HOME_SHORTCUT_SELECTION_ACTION_SIZE,
        surfaceHeight: HOME_SHORTCUT_SELECTION_ACTION_SIZE,
        surfaceRadius: HOME_SHORTCUT_SELECTION_ACTION_SIZE / 2,
        tintColor: resolveBrowserFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        // One backdrop blur per row made opening this sheet janky. The home
        // shortcut tiles opt out for the same reason; the glass fallback color
        // keeps the same look.
        backgroundBlurEnabled: false
      }) {
        if (busy) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.storedAccentColor)
            .hitTestBehavior(HitTestMode.None)
        } else {
          SymbolGlyph(added ? $r('sys.symbol.minus') : $r('sys.symbol.plus'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor([added ? this.storedSecondaryTextColor : this.storedAccentColor])
            .hitTestBehavior(HitTestMode.None)
        }
      }

      Button({ type: ButtonType.Circle })
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .stateEffect(!busy)
        .enabled(!busy)
        .accessibilityText(accessibilityLabel)
        .onClick(() => {
          action();
        })
    }
    .width(HOME_SHORTCUT_SELECTION_ACTION_SIZE)
    .height(HOME_SHORTCUT_SELECTION_ACTION_SIZE)
    .borderRadius(HOME_SHORTCUT_SELECTION_ACTION_SIZE / 2)
    .opacity(busy ? 0.72 : 1)
  }

  private resolveBookmarkRowsSource(folderId: string): HomeShortcutBookmarkRowDataSource {
    const existing = this.bookmarkRowsSourceByFolderId.get(folderId);
    if (existing !== undefined) {
      return existing;
    }
    const source = new HomeShortcutBookmarkRowDataSource();
    source.replaceRows(this.resolveBookmarkRows(folderId));
    this.bookmarkRowsSourceByFolderId.set(folderId, source);
    return source;
  }

  private resolveBookmarkRows(folderId: string): HomeShortcutBookmarkSelectionRow[] {
    return this.bookmarkRowsByFolderId.get(folderId) ?? [];
  }

  private resolveBookmarkFolderTitle(folderId: string): string {
    return this.bookmarkTitleByFolderId.get(folderId) ?? '书签';
  }

  private openBookmarkFolder(folderId: string): void {
    this.bookmarkNavigationActionGeneration += 1;
    const generation = this.bookmarkNavigationActionGeneration;
    const sessionId = this.state.sessionId;
    this.onAction({ type: 'enter_folder', folderId: folderId });
    setTimeout(() => {
      if (generation !== this.bookmarkNavigationActionGeneration || sessionId !== this.state.sessionId) {
        return;
      }
      this.bookmarkNavigationStack.pushPathByName(
        HOME_SHORTCUT_BOOKMARK_DESTINATION_NAME,
        new HomeShortcutBookmarkDestinationParams(folderId),
        this.layoutMode === 'phone'
      );
    }, 0);
  }

  private navigateBackBookmarkFolder(): void {
    this.bookmarkNavigationActionGeneration += 1;
    this.onAction({ type: 'back_folder' });
    this.bookmarkNavigationStack.pop(this.layoutMode === 'phone');
  }

  private ensureBookmarkNavigationSession(): void {
    if (this.bookmarkNavigationSessionId === this.state.sessionId) {
      return;
    }
    this.bookmarkNavigationActionGeneration += 1;
    while (this.bookmarkNavigationStack.pop(false) !== undefined) {
    }
    this.bookmarkRowsSourceByFolderId.clear();
    this.bookmarkRowsByFolderId.clear();
    this.bookmarkTitleByFolderId.clear();
    this.bookmarkNavigationSessionId = this.state.sessionId;
  }

  private syncBookmarkRows(): void {
    this.ensureBookmarkNavigationSession();
    const folderId = this.state.currentFolderId;
    const rows = this.state.bookmarkRows.slice();
    this.bookmarkRowsByFolderId.set(folderId, rows);
    this.bookmarkTitleByFolderId.set(folderId, this.state.currentFolderTitle);
    const source = this.resolveBookmarkRowsSource(folderId);
    source.replaceRows(rows);
    this.pruneBookmarkIconStates();
    this.resolveBookmarkIcons();
  }

  private bindSiteIconUpdates(): void {
    if (this.siteIconUpdatesBound) {
      return;
    }
    this.siteIconUpdatesBound = true;
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildBookmarkIconTargets(),
      (result: SiteIconListResolvedIcon): void => {
        this.applyBookmarkIcon(result);
      }
    );
  }

  private resolveBookmarkIcons(): void {
    const options: SiteIconListResolveOptions = {
      resolutionPolicy: 'memoryOnly'
    };
    this.siteIconListPresenter.resolveTargets(
      this.buildBookmarkIconTargets(),
      (result: SiteIconListResolvedIcon): void => {
        this.applyBookmarkIcon(result);
      },
      options
    );
  }

  private buildBookmarkIconTargets(): SiteIconListTarget[] {
    const targets: SiteIconListTarget[] = [];
    this.state.bookmarkRows.forEach((row: HomeShortcutBookmarkSelectionRow) => {
      if (row.kind === 'bookmark' && row.url.length > 0) {
        targets.push(this.buildBookmarkIconTarget(row));
      }
    });
    return targets;
  }

  private applyBookmarkIcon(result: SiteIconListResolvedIcon): void {
    const next = this.siteIconListPresenter.applyResolvedIcon(this.bookmarkIconStates, result);
    if (next !== this.bookmarkIconStates) {
      this.bookmarkIconStates = next;
    }
  }

  private resolveBookmarkIconUri(bookmarkId: string): string {
    return this.getBookmarkIconState(bookmarkId)?.path ?? '';
  }

  private resolveBookmarkIconPixelMap(bookmarkId: string): image.PixelMap | undefined {
    return this.getBookmarkIconState(bookmarkId)?.pixelMap;
  }

  private resolveBookmarkIconSourceRevision(bookmarkId: string): number {
    return this.getBookmarkIconState(bookmarkId)?.sourceRevision ?? 0;
  }

  private getBookmarkIconState(bookmarkId: string): SiteIconListRenderState | undefined {
    if (this.bookmarkIconLookupSource !== this.bookmarkIconStates) {
      this.bookmarkIconLookupSource = this.bookmarkIconStates;
      this.bookmarkIconLookup = this.buildBookmarkIconLookup(this.bookmarkIconStates);
    }
    return this.bookmarkIconLookup[bookmarkId];
  }

  private resolveBookmarkPixelMapAfterUriFailure(
    row: HomeShortcutBookmarkSelectionRow,
    currentUri: string,
    sourceRevision: number
  ): void {
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      this.buildBookmarkIconTarget(row),
      currentUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyBookmarkIcon(result)
    );
  }

  private buildBookmarkIconTarget(row: HomeShortcutBookmarkSelectionRow): SiteIconListTarget {
    return {
      id: row.id,
      url: row.url
    };
  }

  private pruneBookmarkIconStates(): void {
    const activeBookmarkRows: Record<string, HomeShortcutBookmarkSelectionRow | undefined> = {};
    this.state.bookmarkRows.forEach((row: HomeShortcutBookmarkSelectionRow) => {
      if (row.kind === 'bookmark') {
        activeBookmarkRows[row.id] = row;
      }
    });
    const retainedStates = this.bookmarkIconStates.filter((state: SiteIconListRenderState) => {
      const row = activeBookmarkRows[state.id];
      return row !== undefined && this.siteIconListPresenter.hasResolvedIcon(
        [state],
        this.buildBookmarkIconTarget(row)
      );
    });
    if (retainedStates.length !== this.bookmarkIconStates.length) {
      this.bookmarkIconStates = retainedStates;
    }
  }

  private buildBookmarkIconLookup(
    states: SiteIconListRenderState[]
  ): Record<string, SiteIconListRenderState | undefined> {
    const lookup: Record<string, SiteIconListRenderState | undefined> = {};
    states.forEach((state: SiteIconListRenderState) => {
      lookup[state.id] = state;
    });
    return lookup;
  }

  private selectNavigationTab(id: string): void {
    this.onAction({
      type: 'select_tab',
      tab: id === 'bookmarks' ? 'bookmarks' : 'system'
    });
  }

  private resolveNavigationItemBackground(tab: string): ResourceColor {
    if (this.state.activeTab === tab) {
      return this.storedControlBackgroundColor;
    }
    return this.hoveredNavigationTab === tab ? this.storedPressedBackgroundColor : Color.Transparent;
  }

  private resolveSelectionWorkspaceBackground(): ResourceColor {
    return this.layoutMode === 'large_screen'
      ? this.storedSurfaceBackgroundColor
      : this.storedPageBackgroundColor;
  }

  private isBusy(key: string): boolean {
    return this.state.busyKeys.indexOf(key) >= 0;
  }

}
