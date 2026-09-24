import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import {
  OfflinePageDeleteResult,
  OfflinePageListItem,
  OfflinePageListState
} from '../../../common/models/OfflinePageModels';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import { OfflinePageListCoordinator } from '../../../core/offline/OfflinePageListCoordinator';
import { OfflinePageListViewModel } from '../../../core/offline/OfflinePageListViewModel';
import { AppChromeIconTone, AppIconResources } from '../../../core/resources/AppIconResources';
import {
  SiteIconListPresenter,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { OfflinePageExportResult, OfflinePageExportService } from '../../../services/offline/OfflinePageExportService';
import { OfflinePageLinkActionResult, OfflinePageLinkActionService } from '../../../services/offline/OfflinePageLinkActionService';
import { sharedOfflinePageRepository } from '../../bootstrap/BrowserAppRuntime';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { WebsiteIconView } from '../common/WebsiteIconView';
import {
  ManagementHdsMenuAction,
  ManagementHdsScaffold
} from '../common/ManagementHdsScaffold';
import { AppEmptyState } from '../common/AppEmptyState';
import {
  BrowserDesktopContextMenu,
  BrowserDesktopContextMenuItem,
  buildBrowserDesktopMenuOptions
} from '../browser/BrowserDesktopContextMenu';
import {
  MANAGEMENT_LARGE_SCREEN_ROW_GAP,
  MANAGEMENT_LARGE_SCREEN_ROW_INSET,
  MANAGEMENT_LARGE_SCREEN_ROW_RADIUS,
  ManagementLargeScreenIconButton,
  ManagementLargeScreenShell
} from '../common/ManagementLargeScreenShell';
import {
  requestOpenBrowserUrlWithRouteParams
} from '../../../core/navigation/BrowserNativeNavigationRequestCenter';
import { buildSavedPageWebTabUrl } from '../../../core/offline/SavedPageWebTabUrl';
import { BROWSER_SHELL_ROUTE, OFFLINE_PAGE_VIEWER_ROUTE } from '../../router/AppRoutes';

const OFFLINE_PAGES_BOTTOM_PADDING: number = 28;

interface OfflinePageIconState {
  id: string;
  path: string;
}

@Component
export struct OfflinePagesScreen {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private coordinator: OfflinePageListCoordinator = new OfflinePageListCoordinator({
    repository: sharedOfflinePageRepository
  });
  private viewModel: OfflinePageListViewModel = new OfflinePageListViewModel();
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  private linkActionService: OfflinePageLinkActionService = new OfflinePageLinkActionService();
  private exportService: OfflinePageExportService = new OfflinePageExportService(sharedOfflinePageRepository);

  @Prop presentationMode: 'page' | 'native_tab' = 'page';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  onOpenOriginalPage: (url: string) => void = (_url: string): void => {};
  onOpenSavedPage: (url: string, title: string) => void = (_url: string, _title: string): void => {};
  @State listState: OfflinePageListState = this.viewModel.buildLoadingState();
  @State iconStates: OfflinePageIconState[] = [];
  @State desktopQuery: string = '';
  @State hoveredItemId: string = '';
  @State desktopMenuItemId: string = '';

  aboutToAppear(): void {
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildSiteIconTargets(this.listState.items),
      (result: SiteIconListResolvedIcon): void => {
        this.setIconPath(result.id, result.uri);
      }
    );
    this.refresh();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
  }

  build() {
    if (this.presentationMode === 'native_tab') {
      this.buildDesktopWorkspace()
    } else {
      this.buildPhonePage()
    }
  }

  @Builder
  private buildPhonePage() {
    Column() {
      ManagementHdsScaffold({
        title: this.isSessionEphemeral() ? '常规离线页面' : '已保存的页面',
        backIconKind: 'back',
        showBackButton: this.presentationMode !== 'native_tab',
        useTopSafeInset: this.presentationMode !== 'native_tab',
        pageBackground: this.storedPageBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: this.isSessionEphemeral(),
        menuActions: this.buildHeaderMenuActions(),
        onBack: () => {
          router.back();
        }
      }) {
        Column() {
          if (this.listState.loading) {
            this.buildStatus(this.listState.message)
          } else if (this.listState.empty) {
            this.buildStatus(this.listState.message)
          } else {
            Scroll() {
              Column({ space: 10 }) {
                ForEach(this.listState.items, (item: OfflinePageListItem) => {
                  this.buildItem(item)
                }, (item: OfflinePageListItem): string => item.id)
              }
              .width('100%')
              .constraintSize({ minHeight: '100%' })
              .justifyContent(FlexAlign.Start)
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 16, right: 16, top: 14, bottom: OFFLINE_PAGES_BOTTOM_PADDING })
            }
            .layoutWeight(1)
            .width('100%')
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .scrollBar(BarState.Auto)
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.storedPageBackgroundColor)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildDesktopWorkspace() {
    ManagementLargeScreenShell({
      title: this.isSessionEphemeral() ? '常规离线页面' : '我的网页',
      badge: this.listState.loading ? '' : `${this.resolveDesktopItems().length} 项`,
      searchPlaceholder: '搜索网页',
      searchQuery: this.desktopQuery,
      showSidebar: false,
      onSearchChange: (value: string): void => {
        this.desktopQuery = value;
      },
      toolbarActions: (): void => {
        this.buildDesktopToolbarActions()
      },
      content: (): void => {
        this.buildDesktopContent()
      }
    })
  }

  @Builder
  private buildDesktopToolbarActions() {
    ManagementLargeScreenIconButton({
      iconId: 'reader.refresh',
      label: '刷新',
      onAction: (): void => {
        this.refresh();
      }
    })
  }

  @Builder
  private buildDesktopContent() {
    if (this.listState.loading) {
      this.buildStatus(this.listState.message)
    } else if (this.resolveDesktopItems().length === 0) {
      this.buildStatus(this.desktopQuery.trim().length > 0 ? '没有匹配的网页' : this.listState.message)
    } else {
      List({ space: MANAGEMENT_LARGE_SCREEN_ROW_GAP }) {
        ForEach(this.resolveDesktopItems(), (item: OfflinePageListItem) => {
          ListItem() {
            this.buildDesktopItem(item)
          }
        }, (item: OfflinePageListItem): string => item.id)
      }
      .width('100%')
      .height('100%')
      .padding({
        left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
        right: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
        top: 8,
        bottom: MANAGEMENT_LARGE_SCREEN_ROW_INSET
      })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
    }
  }

  @Builder
  private buildDesktopItem(item: OfflinePageListItem) {
    Row({ space: 12 }) {
      WebsiteIconView({
        iconUri: this.shouldShowImageIcon(item.id) ? this.getIconPath(item.id) : '',
        fallbackLabel: this.resolvePageFallbackLabel(item),
        variant: 'list',
        iconSize: 28,
        cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
        fallbackFontSize: 13,
        containerBackgroundColor: this.storedControlBackgroundColor,
        frameBorderColor: this.storedDividerColor,
        textColor: this.storedPrimaryTextColor
      })

      Column({ space: 2 }) {
        Text(item.title)
          .width('100%')
          .fontSize(14)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${item.siteName} · ${item.savedAtText}`)
          .width('100%')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.isDesktopItemActive(item.id)) {
        this.buildDesktopOverflowButton(item)
      }
    }
    .width('100%')
    .height(52)
    .padding({
      left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
      right: MANAGEMENT_LARGE_SCREEN_ROW_INSET
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.isDesktopItemActive(item.id)
      ? this.storedControlBackgroundColor
      : $r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(MANAGEMENT_LARGE_SCREEN_ROW_RADIUS)
    .clip(true)
    .onHover((hovered: boolean): void => {
      this.handleDesktopItemHover(item.id, hovered);
    })
    .onClick((): void => {
      if (this.desktopMenuItemId === item.id) {
        return;
      }
      this.openOfflinePageIfAvailable(item);
    })
    .bindContextMenu(this.buildDesktopItemMenu(item), ResponseType.RightClick, buildBrowserDesktopMenuOptions({
      onAppear: (): void => {
        this.desktopMenuItemId = item.id;
      },
      onDisappear: (): void => {
        this.dismissDesktopItemMenu(item.id);
      }
    }))
  }

  private buildHeaderMenuActions(): ManagementHdsMenuAction[] {
    const actions: ManagementHdsMenuAction[] = [
      {
        label: '刷新',
        icon: $r('sys.symbol.arrow_clockwise'),
        action: () => {
          this.refresh();
        }
      }
    ];
    return actions;
  }

  @Builder
  private buildStatus(message: string) {
    AppEmptyState({
      airaIconId: 'browser.toolbar.offline',
      title: message,
      message: this.listState.loading ? '' : '保存网页后，这里会显示可离线打开的页面。',
      fillHeight: true
    })
    .layoutWeight(1)
  }

  private resolveChromeIconTone(): AppChromeIconTone {
    return AppIconResources.chromeToneForResolvedThemeMode(this.storedResolvedThemeMode);
  }

  @Builder
  private buildItem(item: OfflinePageListItem) {
    Button() {
      Row({ space: 12 }) {
        this.buildPageIcon(item)

        Column({ space: 5 }) {
          Text(item.title)
            .width('100%')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.siteName)
            .width('100%')
            .fontSize(13)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${item.savedAtText} · ${item.sizeText}`)
            .width('100%')
            .fontSize(12)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.buildOverflowButton(item)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .type(ButtonType.Normal)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(22)
    .padding(14)
    .stateEffect(true)
    .onClick(() => {
      this.openOfflinePageIfAvailable(item);
    })
  }

  @Builder
  private buildPageIcon(item: OfflinePageListItem) {
    WebsiteIconView({
      iconUri: this.shouldShowImageIcon(item.id) ? this.getIconPath(item.id) : '',
      fallbackLabel: this.resolvePageFallbackLabel(item),
      variant: 'list',
      iconSize: 46,
      cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      fallbackFontSize: 18,
      containerBackgroundColor: this.storedControlBackgroundColor,
      frameBorderColor: this.storedDividerColor,
      textColor: this.storedPrimaryTextColor
    })
  }

  @Builder
  private buildDesktopOverflowButton(item: OfflinePageListItem) {
    Button() {
      Image($r('sys.media.ohos_ic_public_more'))
        .width(18)
        .height(18)
        .fillColor(this.storedSecondaryTextColor)
    }
      .width(36)
      .height(36)
      .type(ButtonType.Normal)
      .backgroundColor(this.storedControlBackgroundColor)
      .borderRadius(18)
      .stateEffect(false)
      .accessibilityText('更多离线页面操作')
      .onClick((): void => {
        this.desktopMenuItemId = item.id;
      })
      .bindMenu(this.buildDesktopItemMenu(item), buildBrowserDesktopMenuOptions({
        placement: Placement.BottomRight,
        showInSubWindow: false,
        onAppear: (): void => {
          this.desktopMenuItemId = item.id;
        },
        onDisappear: (): void => {
          this.dismissDesktopItemMenu(item.id);
        }
      }))
      .bindContextMenu(this.buildDesktopItemMenu(item), ResponseType.RightClick, buildBrowserDesktopMenuOptions({
        onAppear: (): void => {
          this.desktopMenuItemId = item.id;
        },
        onDisappear: (): void => {
          this.dismissDesktopItemMenu(item.id);
        }
      }))
  }

  @Builder
  private buildDesktopItemMenu(item: OfflinePageListItem) {
    BrowserDesktopContextMenu() {
      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          label: '打开离线页面',
          onAction: (): void => {
            this.openOfflinePageIfAvailable(item);
          }
        })
        BrowserDesktopContextMenuItem({
          label: '打开原网页',
          onAction: (): void => {
            this.openOriginalPage(item.originalUrl);
          }
        })
        BrowserDesktopContextMenuItem({
          label: '复制链接',
          onAction: (): void => {
            this.copyOriginalUrl(item.originalUrl);
          }
        })
        BrowserDesktopContextMenuItem({
          label: '分享',
          onAction: (): void => {
            this.shareOriginalUrl(item);
          }
        })
        BrowserDesktopContextMenuItem({
          label: '导出网页',
          onAction: (): void => {
            this.exportOfflinePage(item);
          }
        })
      }
      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          label: '删除',
          onAction: (): void => {
            this.confirmDeleteItem(item);
          }
        })
      }
    }
  }

  @Builder
  private buildOverflowButton(item: OfflinePageListItem) {
    Button() {
      Image($r('sys.media.ohos_ic_public_more'))
        .width(18)
        .height(18)
        .fillColor(this.storedSecondaryTextColor)
    }
      .width(36)
      .height(36)
      .type(ButtonType.Normal)
      .backgroundColor(this.storedControlBackgroundColor)
      .borderRadius(18)
      .stateEffect(false)
      .accessibilityText('更多离线页面操作')
      .bindMenu([
        {
          value: '打开离线页面',
          action: () => {
            this.openOfflinePageIfAvailable(item);
          }
        },
        {
          value: '打开原网页',
          action: () => {
            this.openOriginalPage(item.originalUrl);
          }
        },
        {
          value: '复制链接',
          action: () => {
            this.copyOriginalUrl(item.originalUrl);
          }
        },
        {
          value: '分享',
          action: () => {
            this.shareOriginalUrl(item);
          }
        },
        {
          value: '导出网页',
          action: () => {
            this.exportOfflinePage(item);
          }
        },
        {
          value: '删除',
          action: () => {
            this.confirmDeleteItem(item);
          }
        }
      ])
  }

  private isDesktopItemActive(itemId: string): boolean {
    return this.hoveredItemId === itemId || this.desktopMenuItemId === itemId;
  }

  private handleDesktopItemHover(itemId: string, hovered: boolean): void {
    if (hovered) {
      this.hoveredItemId = itemId;
      return;
    }
    if (this.hoveredItemId === itemId) {
      this.hoveredItemId = '';
    }
  }

  private dismissDesktopItemMenu(itemId: string): void {
    if (this.desktopMenuItemId === itemId) {
      this.desktopMenuItemId = '';
    }
  }

  private refresh(): void {
    this.listState = this.viewModel.buildLoadingState();
    this.coordinator.load(this.dataScope, this.privacyMode)
      .then((state: OfflinePageListState) => {
        this.listState = state;
        this.syncSiteIcons();
      })
      .catch((_error: Error) => {
        this.listState = this.viewModel.buildFailureState('已保存页面读取失败');
      });
  }

  private deleteItem(pageId: string): void {
    this.coordinator.delete(pageId, this.dataScope, this.privacyMode)
      .then((result: OfflinePageDeleteResult) => {
        this.showToast(result.message);
        this.refresh();
      })
      .catch((_error: Error) => {
        this.showToast('删除离线页面失败');
      });
  }

  private confirmDeleteItem(item: OfflinePageListItem): void {
    showCenteredAlertDialog({
      title: '删除离线页面',
      message: `确定删除“${item.title}”的离线副本吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.deleteItem(item.id);
        }
      }
    });
  }

  private openOfflinePage(item: OfflinePageListItem): void {
    if (!this.coordinator.canNavigate(this.dataScope, this.privacyMode)) {
      this.showToast('当前隐私策略不允许打开离线页面');
      return;
    }
    if (this.presentationMode === 'native_tab') {
      this.onOpenSavedPage(
        buildSavedPageWebTabUrl(item.id, this.dataScope, this.privacyMode, item.originalUrl),
        item.title
      );
      return;
    }
    router.pushUrl({
      url: OFFLINE_PAGE_VIEWER_ROUTE,
      params: {
        pageId: item.id,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      }
    }).catch((_error: Error) => {
      this.showToast('离线页面打开失败');
    });
  }

  private openOfflinePageIfAvailable(item: OfflinePageListItem): void {
    if (!item.canOpen) {
      this.showToast(item.openStatusText);
      return;
    }
    this.openOfflinePage(item);
  }

  private syncSiteIcons(): void {
    this.iconStates = this.iconStates.filter((icon: OfflinePageIconState) => {
      return this.listState.items.some((item: OfflinePageListItem) => item.id === icon.id);
    });
    this.siteIconListPresenter.resolveTargets(
      this.buildSiteIconTargets(this.listState.items),
      (result: SiteIconListResolvedIcon): void => {
        if (result.uri.length > 0) {
          this.setIconPath(result.id, result.uri);
        }
      },
      {
        resolutionPolicy: this.isSessionEphemeral() ? 'memoryOnly' : 'remoteAllowed',
        shouldSkipTarget: (target: SiteIconListTarget): boolean => this.shouldShowImageIcon(target.id)
      }
    );
  }

  private buildSiteIconTargets(items: OfflinePageListItem[]): SiteIconListTarget[] {
    const targets: SiteIconListTarget[] = [];
    items.forEach((item: OfflinePageListItem) => {
      if (item.originalUrl.length === 0) {
        return;
      }
      targets.push({
        id: item.id,
        url: item.originalUrl,
        domain: this.resolveDomainHint(item.host),
        initialIconUri: item.faviconUri
      });
    });
    return targets;
  }

  private resolveDomainHint(host: string): string {
    let normalized = host.trim().toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.slice(4);
    }
    if (normalized.length === 0 || !/^[a-z0-9.-]+$/.test(normalized)) {
      return '';
    }
    return normalized;
  }

  private resolvePageFallbackLabel(item: OfflinePageListItem): string {
    const secondary = item.siteName.length > 0 ? item.siteName : item.host;
    return resolveSiteIconFallbackLabel(item.title, secondary);
  }

  private getIconPath(pageId: string): string {
    const state = this.iconStates.find((item: OfflinePageIconState) => item.id === pageId);
    return state === undefined ? '' : state.path;
  }

  private shouldShowImageIcon(pageId: string): boolean {
    const state = this.iconStates.find((item: OfflinePageIconState) => item.id === pageId);
    return state !== undefined && state.path.length > 0;
  }

  private resolveDesktopItems(): OfflinePageListItem[] {
    const query = this.desktopQuery.trim().toLowerCase();
    if (query.length === 0) {
      return this.listState.items;
    }
    return this.listState.items.filter((item: OfflinePageListItem): boolean => {
      return item.title.toLowerCase().includes(query) ||
        item.siteName.toLowerCase().includes(query) ||
        item.host.toLowerCase().includes(query) ||
        item.originalUrl.toLowerCase().includes(query);
    });
  }

  private setIconPath(pageId: string, path: string): void {
    const existing = this.iconStates.find((item: OfflinePageIconState) => item.id === pageId);
    if (existing !== undefined && existing.path === path) {
      return;
    }
    const next = this.iconStates.filter((item: OfflinePageIconState) => item.id !== pageId);
    this.iconStates = next.concat([{ id: pageId, path: path }]);
  }

  private openOriginalPage(url: string): void {
    if (!this.coordinator.canNavigate(this.dataScope, this.privacyMode)) {
      this.showToast('当前隐私策略不允许打开原网页');
      return;
    }
    if (this.presentationMode === 'native_tab') {
      this.onOpenOriginalPage(url);
      return;
    }
    router.back({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(url, 'current_tab', '', 'offline', {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      })
    });
  }

  private copyOriginalUrl(url: string): void {
    this.linkActionService.copyOriginalUrl(url, this.dataScope, this.privacyMode)
      .then((result: OfflinePageLinkActionResult) => {
        this.showToast(result.message);
      });
  }

  private shareOriginalUrl(item: OfflinePageListItem): void {
    this.linkActionService.shareOriginalUrl(
      this.getPickerContext(),
      item.title,
      item.originalUrl,
      this.dataScope,
      this.privacyMode
    )
      .then((result: OfflinePageLinkActionResult) => {
        if (!result.ok) {
          this.showToast(result.message);
        }
      });
  }

  private exportOfflinePage(item: OfflinePageListItem): void {
    this.exportService.exportPage(this.getPickerContext(), item.id, this.dataScope, this.privacyMode)
      .then((result: OfflinePageExportResult) => {
        this.showToast(result.message);
      });
  }

  private getPickerContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
    }
  }

  private isSessionEphemeral(): boolean {
    return this.dataScope === 'session_ephemeral' || this.privacyMode === 'private';
  }
}
