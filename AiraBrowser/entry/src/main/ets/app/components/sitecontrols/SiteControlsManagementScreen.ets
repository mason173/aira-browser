import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  SiteControlsFilterOptionState,
  SiteControlsFilterId,
  SiteControlsListState
} from '../../../core/sitecontrols/SiteControlsCoordinator';
import { SiteCustomizationListRowState } from '../../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import { SiteCustomizationCapabilityFilterId } from '../../../services/web/SiteCapabilityCatalogService';
import { AppEmptyState } from '../common/AppEmptyState';
import { SiteControlsWebsiteRecordRow } from './SiteControlsWebsiteRecordRow';
import { SettingsTextField } from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import { SettingsScrollBody, SettingsSectionTitle, SettingsSection } from '../settings/SettingsLayout';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { AiraIcon } from '../common/AiraIcon';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  SiteIconListPresenter,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { SiteControlsManualOriginDialog } from './SiteControlsManualOriginDialog';
import { createCenteredDialogMaterial } from '../common/CenteredDialogSurface';

const SITE_CONTROLS_OVERVIEW_CARD_GAP: number = 10;
const SITE_CONTROLS_OVERVIEW_CARD_HEIGHT: number = 88;
const SITE_CONTROLS_OVERVIEW_CARD_RADIUS: number = 18;
const SITE_CONTROLS_OVERVIEW_ICON_SIZE: number = 30;
const SITE_CONTROLS_SITE_ROW_CARD_RADIUS: number = 22;
const SITE_CONTROLS_SITE_ROW_CARD_PADDING: number = 4;

export interface SiteControlsCustomizationCapabilityState {
  id: SiteCustomizationCapabilityFilterId;
  title: string;
  count: number;
}

interface SiteControlsWebsiteIconState {
  id: string;
  path: string;
}

@Component
export struct SiteControlsManagementScreen {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Watch('syncSiteIcons')
  @Prop state: SiteControlsListState = {
    query: '',
    totalCount: 0,
    filteredCount: 0,
    filterOptions: [],
    rows: [],
    hasRows: false,
    hasFilteredRows: false,
    summaryLine: '',
    listTitle: '站点规则',
    emptyTitle: '还没有站点权限规则',
    emptyMessage: '网站请求权限或被设置打开应用规则后，会出现在这里'
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Watch('syncSiteIcons')
  @Prop siteRows: SiteCustomizationListRowState[] = [];
  @Prop siteRowsTotalCount: number = 0;
  @Prop customizationCapabilities: SiteControlsCustomizationCapabilityState[] = [];
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet = DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  @State private pressedCapabilityId: string = '';
  @State private pressedCustomizationCapabilityId: string = '';
  @State private pressedSiteRowId: string = '';
  @State private iconStates: SiteControlsWebsiteIconState[] = [];
  @State private manualOriginDraft: string = '';
  @State private manualOriginError: string = '';
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  onQueryChange?: (query: string) => void;
  onSelectFilter?: (filterId: SiteControlsFilterId) => void;
  onSelectCustomizationCapability?: (capabilityId: SiteCustomizationCapabilityFilterId) => void;
  onOpenSite?: (host: string, origin: string) => void;
  resolveManualOriginError?: (value: string) => string;
  onOpenManualOrigin?: (value: string) => void;
  onClose?: () => void;
  private manualOriginDialogController: CustomDialogController = new CustomDialogController({
    builder: SiteControlsManualOriginDialog({
      addressDraft: $manualOriginDraft,
      errorText: $manualOriginError,
      confirm: (): boolean => this.confirmManualOrigin()
    }),
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true
  });

  aboutToAppear(): void {
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildSiteIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.setIconPath(result.id, result.uri)
    );
    this.syncSiteIcons();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
  }

  build() {
    SettingsHdsScaffold({
      title: '站点设置',
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      menuActionLabel: '添加站点',
      menuActionAiraIconId: 'browser.tabs.overviewAdd',
      onBack: () => {
        this.onClose?.();
      },
      onMenuAction: (): void => {
        this.openManualOriginDialog();
      }
    }) {
      Column() {
        this.buildPageList()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.storedPageBackgroundColor)
    }
  }

  private openManualOriginDialog(): void {
    this.manualOriginDraft = '';
    this.manualOriginError = '';
    this.manualOriginDialogController.open();
  }

  private confirmManualOrigin(): boolean {
    const error = this.resolveManualOriginError?.(this.manualOriginDraft) ?? '';
    if (error.length > 0) {
      this.manualOriginError = error;
      return false;
    }
    this.onOpenManualOrigin?.(this.manualOriginDraft);
    return true;
  }

  @Builder
  private buildPageList() {
    SettingsScrollBody({
      contentSpace: 18,
      topPadding: 16,
      bottomPadding: 32
    }) {
      this.buildSearchSection()

      if (this.isSearchingSites()) {
        this.buildSearchResultListItems()
      } else {
        this.buildPermissionCapabilitySection()
        this.buildSiteSettingsCapabilitySection()
        this.buildCustomizedSiteListItems()
      }
    }
  }

  @Builder
  private buildSearchSection() {
    Column() {
      SettingsTextField({
        text: this.state.query,
        placeholder: '搜索站点',
        controlBackgroundColor: this.storedSurfaceBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        onChange: (value: string) => {
          this.onQueryChange?.(value);
        }
      })
    }
    .width('100%')
  }

  @Builder
  private buildPermissionCapabilitySection() {
    SettingsSection({ title: '权限' }) {
      Column({ space: SITE_CONTROLS_OVERVIEW_CARD_GAP }) {
        Row({ space: SITE_CONTROLS_OVERVIEW_CARD_GAP }) {
          this.buildCapabilityOverviewCard(this.getCapabilityOption('location', '位置信息'))
          this.buildCapabilityOverviewCard(this.getCapabilityOption('camera', '摄像头'))
        }
        .width('100%')

        Row({ space: SITE_CONTROLS_OVERVIEW_CARD_GAP }) {
          this.buildCapabilityOverviewCard(this.getCapabilityOption('microphone', '麦克风'))
          this.buildCapabilityOverviewCard(this.getCapabilityOption('sensor', '传感器'))
        }
        .width('100%')

        Row({ space: SITE_CONTROLS_OVERVIEW_CARD_GAP }) {
          this.buildCapabilityOverviewCard(this.getCapabilityOption('clipboard', '剪贴板'))
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildSiteSettingsCapabilitySection() {
    SettingsSection({ title: '站点设置' }) {
      Column({ space: SITE_CONTROLS_OVERVIEW_CARD_GAP }) {
        Row({ space: SITE_CONTROLS_OVERVIEW_CARD_GAP }) {
          this.buildCapabilityOverviewCard(this.getCapabilityOption('open_app', '打开应用'))
          this.buildCustomizationCapabilityCard(this.getCustomizationCapabilityOption('external_actions', '外部动作'))
        }
        .width('100%')

        Row({ space: SITE_CONTROLS_OVERVIEW_CARD_GAP }) {
          this.buildCustomizationCapabilityCard(this.getCustomizationCapabilityOption('desktop_site', '网页标识'))
          this.buildCustomizationCapabilityCard(this.getCustomizationCapabilityOption('private_site', '关闭后清除'))
        }
        .width('100%')

        Row({ space: SITE_CONTROLS_OVERVIEW_CARD_GAP }) {
          this.buildCustomizationCapabilityCard(this.getCustomizationCapabilityOption('javascript', 'JavaScript'))
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildSearchResultListItems() {
    if (this.siteRows.length > 0) {
      SettingsSectionTitle({ title: '网站' })
        .margin({ bottom: -8 })

      this.buildSiteRowListItems()
    } else {
      AppEmptyState({
        airaIconId: 'settings.search',
        title: '没有找到这个站点',
        message: '换个关键词再试试',
        topPadding: 92,
        bottomPadding: 92,
        fillHeight: false
      })
    }
  }

  @Builder
  private buildCustomizedSiteListItems() {
    if (this.siteRowsTotalCount > 0) {
      SettingsSectionTitle({ title: '已自定义站点' })
        .margin({ bottom: -8 })

      this.buildSiteRowListItems()
    }
  }

  @Builder
  private buildSiteRowListItems() {
    ForEach(this.siteRows, (row: SiteCustomizationListRowState, index: number) => {
      this.buildSiteRowCard(row, index)
    }, (row: SiteCustomizationListRowState) => row.id)
  }

  @Builder
  private buildSiteRowCard(row: SiteCustomizationListRowState, index: number) {
    Column() {
      SiteControlsWebsiteRecordRow({
        rowId: row.id,
        title: row.title,
        host: row.host,
        origin: row.origin,
        iconUri: this.getIconPath(row.id),
        pressed: this.pressedSiteRowId === row.id,
        rowBorderRadius: this.resolveSiteRowBorderRadius(index),
        iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        showDivider: index < this.siteRows.length - 1,
        onTouchAction: (type: TouchType) => {
          this.updatePressedSiteRow(row.id, type);
        },
        onRowClick: () => {
          this.onOpenSite?.(row.host, row.origin);
        },
        trailing: () => {
          this.buildSiteRowChevron()
        }
      })
    }
    .width('100%')
    .padding({
      left: SITE_CONTROLS_SITE_ROW_CARD_PADDING,
      right: SITE_CONTROLS_SITE_ROW_CARD_PADDING,
      top: index === 0 ? SITE_CONTROLS_SITE_ROW_CARD_PADDING : 0,
      bottom: index >= this.siteRows.length - 1 ? SITE_CONTROLS_SITE_ROW_CARD_PADDING : 0
    })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(this.resolveSiteRowCardRadius(index))
    .clip(true)
  }

  @Builder
  private buildCapabilityOverviewCard(option: SiteControlsFilterOptionState) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        this.buildCapabilityIcon(option.id)

        Text(option.title)
          .layoutWeight(1)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.buildCapabilityCountText(option))
        .width('100%')
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .layoutWeight(1)
    .height(SITE_CONTROLS_OVERVIEW_CARD_HEIGHT)
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .backgroundColor(this.resolveOverviewCardBackgroundColor(option))
    .border({
      width: option.isSelected ? 1.5 : 0,
      color: this.storedAccentColor
    })
    .borderRadius(SITE_CONTROLS_OVERVIEW_CARD_RADIUS)
    .clip(true)
    .alignItems(HorizontalAlign.Start)
    .onTouch((event: TouchEvent) => {
      this.updatePressedCapability(option.id, event.type);
    })
    .onClick(() => {
      this.onSelectFilter?.(option.id);
    })
  }

  @Builder
  private buildCustomizationCapabilityCard(option: SiteControlsCustomizationCapabilityState) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        this.buildCustomizationCapabilityIcon(option.id)

        Text(option.title)
          .layoutWeight(1)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(`${option.count} 个网站`)
        .width('100%')
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .layoutWeight(1)
    .height(SITE_CONTROLS_OVERVIEW_CARD_HEIGHT)
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .backgroundColor(this.resolveCustomizationCapabilityCardBackgroundColor(option.id))
    .borderRadius(SITE_CONTROLS_OVERVIEW_CARD_RADIUS)
    .clip(true)
    .alignItems(HorizontalAlign.Start)
    .onTouch((event: TouchEvent) => {
      this.updatePressedCustomizationCapability(option.id, event.type);
    })
    .onClick(() => {
      this.onSelectCustomizationCapability?.(option.id);
    })
  }

  @Builder
  private buildCapabilityIcon(filterId: SiteControlsFilterId) {
    Row() {
      this.buildOverviewIconContent(
        this.resolveCapabilityIcon(filterId),
        this.resolveCapabilityAiraIconId(filterId),
        19
      )
    }
    .width(SITE_CONTROLS_OVERVIEW_ICON_SIZE)
    .height(SITE_CONTROLS_OVERVIEW_ICON_SIZE)
    .borderRadius(10)
    .backgroundColor(this.resolveCapabilityIconBackgroundColor(filterId))
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildCustomizationCapabilityIcon(filterId: SiteCustomizationCapabilityFilterId) {
    Row() {
      this.buildOverviewIconContent(
        this.resolveCustomizationCapabilityIcon(filterId),
        this.resolveCustomizationCapabilityAiraIconId(filterId),
        18
      )
    }
    .width(SITE_CONTROLS_OVERVIEW_ICON_SIZE)
    .height(SITE_CONTROLS_OVERVIEW_ICON_SIZE)
    .borderRadius(10)
    .backgroundColor(this.resolveCustomizationCapabilityIconBackgroundColor(filterId))
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildOverviewIconContent(
    symbolIcon: Resource,
    airaIconId: AiraRenderableIconId | undefined,
    symbolSize: number
  ) {
    if (airaIconId !== undefined) {
      AiraIcon({
        airaIconId: airaIconId,
        iconSize: 20,
        iconColor: this.storedSurfaceBackgroundColor
      })
    } else {
      SymbolGlyph(symbolIcon)
        .fontSize(symbolSize)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.storedSurfaceBackgroundColor])
    }
  }

  private resolveCapabilityAiraIconId(filterId: SiteControlsFilterId): AiraRenderableIconId | undefined {
    switch (filterId) {
      case 'camera':
        return 'site.permission.camera';
      case 'microphone':
        return 'site.permission.microphone';
      case 'location':
        return 'site.permission.location';
      case 'sensor':
        return 'site.permission.sensor';
      case 'clipboard':
        return 'site.permission.clipboard';
      case 'open_app':
        return 'site.setting.openApp';
      default:
        return undefined;
    }
  }

  private resolveCustomizationCapabilityAiraIconId(
    filterId: SiteCustomizationCapabilityFilterId
  ): AiraRenderableIconId | undefined {
    switch (filterId) {
      case 'external_actions':
        return 'site.setting.externalActions';
      case 'desktop_site':
        return 'settings.userAgent';
      case 'private_site':
        return 'site.setting.clearOnClose';
      case 'javascript':
        return 'settings.userScripts';
      default:
        return undefined;
    }
  }

  @Builder
  private buildSiteRowChevron() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor([this.storedSecondaryTextColor])
  }

  private getCapabilityOption(filterId: SiteControlsFilterId, title: string): SiteControlsFilterOptionState {
    const option = this.state.filterOptions.find((item: SiteControlsFilterOptionState) => item.id === filterId);
    return option ?? {
      id: filterId,
      title: title,
      count: 0,
      isSelected: false
    };
  }

  private getCustomizationCapabilityOption(
    filterId: SiteCustomizationCapabilityFilterId,
    title: string
  ): SiteControlsCustomizationCapabilityState {
    const option = this.customizationCapabilities.find((item: SiteControlsCustomizationCapabilityState) => {
      return item.id === filterId;
    });
    return option ?? {
      id: filterId,
      title: title,
      count: 0
    };
  }

  private buildCapabilityCountText(option: SiteControlsFilterOptionState): string {
    return `${option.count} 个网站`;
  }

  private resolveOverviewCardBackgroundColor(option: SiteControlsFilterOptionState): ResourceColor {
    if (this.pressedCapabilityId === option.id) {
      return this.storedPressedBackgroundColor;
    }
    return option.isSelected ? this.storedPressedBackgroundColor : this.storedSurfaceBackgroundColor;
  }

  private resolveCustomizationCapabilityCardBackgroundColor(filterId: SiteCustomizationCapabilityFilterId): ResourceColor {
    return this.pressedCustomizationCapabilityId === filterId
      ? this.storedPressedBackgroundColor
      : this.storedSurfaceBackgroundColor;
  }

  private updatePressedCapability(filterId: SiteControlsFilterId, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedCapabilityId = filterId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedCapabilityId = '';
    }
  }

  private updatePressedCustomizationCapability(filterId: SiteCustomizationCapabilityFilterId, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedCustomizationCapabilityId = filterId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedCustomizationCapabilityId = '';
    }
  }

  private updatePressedSiteRow(rowId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedSiteRowId = rowId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedSiteRowId = '';
    }
  }

  private syncSiteIcons(): void {
    this.iconStates = this.iconStates.filter((icon: SiteControlsWebsiteIconState): boolean => {
      return this.siteRows.some((row: SiteCustomizationListRowState): boolean => row.id === icon.id);
    });
    this.siteIconListPresenter.resolveTargets(
      this.buildSiteIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.setIconPath(result.id, result.uri),
      {
        shouldSkipTarget: (target: SiteIconListTarget): boolean => this.getIconPath(target.id).length > 0
      }
    );
  }

  private buildSiteIconTargets(): SiteIconListTarget[] {
    return this.siteRows.map((row: SiteCustomizationListRowState): SiteIconListTarget => {
      return {
        id: row.id,
        url: this.resolveSiteIconUrl(row.host, row.origin),
        domain: row.host
      };
    });
  }

  private resolveSiteIconUrl(host: string, origin: string): string {
    const normalizedOrigin = origin.trim();
    if (normalizedOrigin.length > 0) {
      return normalizedOrigin;
    }
    const normalizedHost = host.trim();
    return normalizedHost.length > 0 ? `https://${normalizedHost}` : '';
  }

  private getIconPath(rowId: string): string {
    const state = this.iconStates.find((item: SiteControlsWebsiteIconState): boolean => item.id === rowId);
    return state?.path ?? '';
  }

  private setIconPath(rowId: string, path: string): void {
    const normalizedPath = path.trim();
    if (rowId.length <= 0 || normalizedPath.length <= 0) {
      return;
    }
    const existing = this.iconStates.find((item: SiteControlsWebsiteIconState): boolean => item.id === rowId);
    if (existing !== undefined && existing.path === normalizedPath) {
      return;
    }
    const next = this.iconStates.filter((item: SiteControlsWebsiteIconState): boolean => item.id !== rowId);
    this.iconStates = next.concat([{ id: rowId, path: normalizedPath }]);
  }

  private resolveSiteRowCardRadius(index: number): BorderRadiuses {
    const isFirst = index <= 0;
    const isLast = index >= this.siteRows.length - 1;
    return {
      topLeft: isFirst ? SITE_CONTROLS_SITE_ROW_CARD_RADIUS : 0,
      topRight: isFirst ? SITE_CONTROLS_SITE_ROW_CARD_RADIUS : 0,
      bottomLeft: isLast ? SITE_CONTROLS_SITE_ROW_CARD_RADIUS : 0,
      bottomRight: isLast ? SITE_CONTROLS_SITE_ROW_CARD_RADIUS : 0
    };
  }

  private resolveSiteRowBorderRadius(index: number): BorderRadiuses {
    const isFirst = index <= 0;
    const isLast = index >= this.siteRows.length - 1;
    return {
      topLeft: isFirst ? SITE_CONTROLS_SITE_ROW_CARD_RADIUS : 0,
      topRight: isFirst ? SITE_CONTROLS_SITE_ROW_CARD_RADIUS : 0,
      bottomLeft: isLast ? SITE_CONTROLS_SITE_ROW_CARD_RADIUS : 0,
      bottomRight: isLast ? SITE_CONTROLS_SITE_ROW_CARD_RADIUS : 0
    };
  }

  private resolveCapabilityIcon(filterId: SiteControlsFilterId): Resource {
    if (filterId === 'camera') {
      return $r('sys.symbol.camera_fill');
    }
    if (filterId === 'microphone') {
      return $r('sys.symbol.mic_fill');
    }
    if (filterId === 'location') {
      return $r('sys.symbol.person_shield_fill');
    }
    if (filterId === 'clipboard') {
      return $r('sys.symbol.doc_text_fill');
    }
    if (filterId === 'open_app') {
      return $r('sys.symbol.link');
    }
    return $r('sys.symbol.gearshape_fill');
  }

  private resolveCustomizationCapabilityIcon(filterId: SiteCustomizationCapabilityFilterId): Resource {
    if (filterId === 'external_actions') {
      return $r('sys.symbol.link');
    }
    if (filterId === 'private_site') {
      return $r('sys.symbol.person_shield_fill');
    }
    if (filterId === 'javascript') {
      return $r('sys.symbol.gearshape_fill');
    }
    return $r('sys.symbol.rectangle_on_rectangle_fill');
  }

  private resolveCapabilityIconBackgroundColor(filterId: SiteControlsFilterId): ResourceColor {
    if (filterId === 'location') {
      return this.settingsIconBackgrounds.siteSettings;
    }
    if (filterId === 'camera') {
      return this.settingsIconBackgrounds.experiments;
    }
    if (filterId === 'microphone') {
      return this.settingsIconBackgrounds.siteSettings;
    }
    if (filterId === 'open_app') {
      return this.settingsIconBackgrounds.userAgent;
    }
    if (filterId === 'clipboard') {
      return this.settingsIconBackgrounds.siteCustomization;
    }
    return this.settingsIconBackgrounds.experiments;
  }

  private resolveCustomizationCapabilityIconBackgroundColor(filterId: SiteCustomizationCapabilityFilterId): ResourceColor {
    if (filterId === 'desktop_site') {
      return this.settingsIconBackgrounds.userAgent;
    }
    if (filterId === 'private_site') {
      return this.settingsIconBackgrounds.privacySecurity;
    }
    if (filterId === 'javascript') {
      return this.settingsIconBackgrounds.userScripts;
    }
    return this.settingsIconBackgrounds.siteCustomization;
  }

  private isSearchingSites(): boolean {
    return this.state.query.trim().length > 0;
  }

}
