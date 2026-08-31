import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  CrossDeviceTabPresenceDevice,
  CrossDeviceTabPresencePanelState,
  CrossDeviceTabPresenceTab
} from '../../../core/deviceTabs/CrossDeviceTabPresenceModels';
import {
  SiteIconListPresenter,
  SiteIconListRenderState,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import {
  sharedCrossDeviceTabPresenceCoordinator
} from '../../../core/deviceTabs/CrossDeviceTabPresenceCoordinator';
import { AiraIcon } from '../common/AiraIcon';
import {
  RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
  RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
  RECORD_LIST_ROW_FAVICON_SIZE,
  RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
  RECORD_LIST_ROW_HEIGHT,
  RECORD_LIST_ROW_HORIZONTAL_INSET,
  RECORD_LIST_ROW_RADIUS
} from '../common/RecordListTokens';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';

const EMPTY_PANEL_STATE: CrossDeviceTabPresencePanelState = {
  status: 'loading',
  enabled: false,
  deviceName: '',
  devices: [],
  message: '',
  serverTime: 0,
  onlineWindowMs: 120000
};

@Component
export struct BrowserCrossDeviceTabsSheet {
  private readonly siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;

  @State private panelState: CrossDeviceTabPresencePanelState = EMPTY_PANEL_STATE;
  @State private siteIconStates: SiteIconListRenderState[] = [];
  @State private pressedTabId: string = '';
  @State private loading: boolean = false;

  onOpenRemoteTab: (url: string, title: string) => void = (_url: string, _title: string) => {};

  aboutToAppear(): void {
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildSiteIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
    void this.refresh();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
  }

  build() {
    Column() {
      this.buildRemoteDeviceContent()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 18 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildRemoteDeviceContent() {
    Column() {
      if (this.loading) {
        this.buildMessageState('正在读取在线电脑...', true)
      } else if (this.panelState.status === 'signed_out') {
        this.buildMessageState(this.panelState.message, false)
      } else if (this.panelState.status === 'error') {
        this.buildMessageState(this.panelState.message, false)
      } else if (this.panelState.devices.length === 0) {
        this.buildMessageState('当前没有在线电脑', false)
      } else {
        List({ space: 12 }) {
          ForEach(this.panelState.devices, (device: CrossDeviceTabPresenceDevice) => {
            ListItem() {
              this.buildDeviceGroup(device)
            }
            .width('100%')
          }, (device: CrossDeviceTabPresenceDevice): string => device.deviceId)
        }
        .width('100%')
        .height('100%')
        .padding({ bottom: 2 })
        .alignListItem(ListItemAlign.Start)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .clip(true)
  }

  @Builder
  private buildMessageState(message: string, showLoading: boolean) {
    Column({ space: 12 }) {
      if (showLoading) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(this.storedAccentColor)
      } else {
        AiraIcon({
          airaIconId: 'settings.themeMode.system',
          iconSize: 26,
          iconColor: this.storedSecondaryTextColor
        })
      }

      Text(message)
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(3)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildDeviceGroup(device: CrossDeviceTabPresenceDevice) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text(this.resolveDeviceTitle(device))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })

        Text(`${device.tabCount} 个`)
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
      }
      .width('100%')
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)

      if (device.tabs.length > 0) {
        Column({ space: 8 }) {
          ForEach(device.tabs, (tab: CrossDeviceTabPresenceTab, index: number) => {
            this.buildRemoteTabRow(device, tab, index)
          }, (tab: CrossDeviceTabPresenceTab, index: number): string => this.buildRemoteTabId(device, tab, index))
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private buildRemoteTabRow(
    device: CrossDeviceTabPresenceDevice,
    tab: CrossDeviceTabPresenceTab,
    index: number
  ) {
    WebsiteRecordRow({
      iconUri: this.resolveSiteIconState(this.buildRemoteTabId(device, tab, index))?.path ?? '',
      iconPixelMap: this.resolveSiteIconState(this.buildRemoteTabId(device, tab, index))?.pixelMap,
      fallbackLabel: resolveSiteIconFallbackLabel(tab.title, tab.url),
      title: tab.title.trim().length > 0 ? tab.title : tab.url,
      subtitle: tab.url,
      pressed: this.pressedTabId === this.buildRemoteTabId(device, tab, index),
      leftInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rightInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rowHeight: RECORD_LIST_ROW_HEIGHT,
      rowBorderRadius: RECORD_LIST_ROW_RADIUS,
      iconSize: RECORD_LIST_ROW_FAVICON_SIZE,
      iconSlotSize: RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
      iconContentRatio: RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
      iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      fallbackFontSize: RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
      preferPixelMap: this.resolveSiteIconState(this.buildRemoteTabId(device, tab, index))?.pixelMap !== undefined,
      sourceRevision: this.resolveSiteIconState(this.buildRemoteTabId(device, tab, index))?.sourceRevision ?? 0,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.handleSiteIconLoadError(device, tab, index, iconUri, sourceRevision);
      },
      onTouchAction: (type: TouchType) => {
        this.updatePressedTab(this.buildRemoteTabId(device, tab, index), type);
      },
      onRowClick: () => {
        this.onOpenRemoteTab(tab.url, tab.title);
      }
    })
    .width('100%')
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(RECORD_LIST_ROW_RADIUS)
    .clip(true)
  }

  private async refresh(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      const state = await sharedCrossDeviceTabPresenceCoordinator.loadPanelState();
      this.panelState = state;
      this.syncSiteIcons();
    } finally {
      this.loading = false;
    }
  }

  private resolveDeviceTitle(device: CrossDeviceTabPresenceDevice): string {
    const browserName = device.browserName.trim();
    const platform = device.platform.trim();
    if (browserName.length > 0 && platform.length > 0) {
      return `${browserName} ${platform}`;
    }
    return browserName || platform || device.deviceName.trim() || device.model.trim() || '电脑';
  }

  private syncSiteIcons(): void {
    const targets = this.buildSiteIconTargets();
    this.siteIconStates = this.siteIconStates.filter((state: SiteIconListRenderState): boolean => {
      return targets.some((target: SiteIconListTarget): boolean => target.id === state.id);
    });
    this.siteIconListPresenter.resolveTargets(
      targets,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
  }

  private buildSiteIconTargets(): SiteIconListTarget[] {
    const targets: SiteIconListTarget[] = [];
    this.panelState.devices.forEach((device: CrossDeviceTabPresenceDevice): void => {
      device.tabs.forEach((tab: CrossDeviceTabPresenceTab, index: number): void => {
        targets.push({
          id: this.buildRemoteTabId(device, tab, index),
          url: tab.url
        });
      });
    });
    return targets;
  }

  private applyResolvedSiteIcon(result: SiteIconListResolvedIcon): void {
    this.siteIconStates = this.siteIconListPresenter.applyResolvedIcon(this.siteIconStates, result);
  }

  private handleSiteIconLoadError(
    device: CrossDeviceTabPresenceDevice,
    tab: CrossDeviceTabPresenceTab,
    index: number,
    currentUri: string,
    sourceRevision: number
  ): void {
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      {
        id: this.buildRemoteTabId(device, tab, index),
        url: tab.url
      },
      currentUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
  }

  private resolveSiteIconState(tabId: string): SiteIconListRenderState | undefined {
    return this.siteIconStates.find((state: SiteIconListRenderState): boolean => state.id === tabId);
  }

  private updatePressedTab(tabId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedTabId = tabId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedTabId = '';
    }
  }

  private buildRemoteTabId(
    device: CrossDeviceTabPresenceDevice,
    tab: CrossDeviceTabPresenceTab,
    index: number
  ): string {
    return `${device.deviceId}:${tab.windowOrder}:${tab.tabOrder}:${index}:${tab.url}`;
  }
}
