import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  SiteControlsCapabilityDefaultState,
  SiteControlsListRowState,
  SiteControlsListState
} from '../../../core/sitecontrols/SiteControlsCoordinator';
import { AppEmptyState } from '../common/AppEmptyState';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsTextField
} from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsSection,
  SettingsSectionTitle
} from '../settings/SettingsLayout';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SiteControlsWebsiteRecordRow } from './SiteControlsWebsiteRecordRow';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { SiteControlsListRowDataSource } from '../../../features/sitecontrols/SiteControlsWebsiteRowDataSource';
import {
  SiteIconListPresenter,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { SiteControlsManualOriginDialog } from './SiteControlsManualOriginDialog';
import { createCenteredDialogMaterial } from '../common/CenteredDialogSurface';

const SITE_CONTROLS_CAPABILITY_LIST_CACHE_COUNT: number = 8;
const SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS: number = 22;
const SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_PADDING: number = 4;

interface SiteControlsCapabilityWebsiteIconState {
  id: string;
  path: string;
}

@Component
export struct SiteControlsCapabilityScreen {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
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
  @Prop defaultState: SiteControlsCapabilityDefaultState = {
    title: '默认设置',
    valueLabel: '询问',
    isEnabled: true
  };
  @Prop pageTitle: string = '';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop showDefaultSection: boolean = true;
  @Prop showAddSiteAction: boolean = false;
  @State private iconStates: SiteControlsCapabilityWebsiteIconState[] = [];
  @State private manualOriginDraft: string = '';
  @State private manualOriginError: string = '';
  private rowsDataSource: SiteControlsListRowDataSource = new SiteControlsListRowDataSource();
  private rowsDataSourceRows: SiteControlsListRowState[] = [];
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  onOpenDefault?: () => void;
  onOpenSite?: (host: string, origin: string) => void;
  onQueryChange?: (query: string) => void;
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
    this.manualOriginDialogController.close();
  }

  build() {
    SettingsHdsScaffold({
      title: this.resolveTitle(),
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      onBack: () => {
        this.onClose?.();
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

  @Builder
  private buildPageList() {
    List({ space: 18 }) {
      ListItem() {
        this.buildSearchSection()
      }
      .width('100%')

      if (this.showDefaultSection) {
        ListItem() {
          this.buildDefaultSection()
        }
        .width('100%')
      }

      if (this.showAddSiteAction) {
        ListItem() {
          SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            SettingsActionButton({
              title: '添加网站例外',
              pressedBackgroundColor: this.storedPressedBackgroundColor,
              onAction: (): void => {
                this.openManualOriginDialog();
              }
            })
          }
        }
        .width('100%')
      }

      this.buildWebsiteListItems()
    }
    .layoutWeight(1)
    .width('100%')
    .padding({
      left: APP_STANDARD_HORIZONTAL_PADDING,
      right: APP_STANDARD_HORIZONTAL_PADDING,
      top: 16,
      bottom: 28
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Auto)
    .cachedCount(SITE_CONTROLS_CAPABILITY_LIST_CACHE_COUNT)
  }

  @Builder
  private buildSearchSection() {
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

  @Builder
  private buildDefaultSection() {
    SettingsSection({ title: '默认' }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsNavigationRow({
          title: this.defaultState.title,
          value: this.defaultState.valueLabel,
          rowPosition: 'single',
          isEnabled: this.defaultState.isEnabled,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onOpenDefault?.();
          }
        })
      }
    }
  }

  @Builder
  private buildWebsiteListItems() {
    if (this.state.hasFilteredRows) {
      ListItem() {
        SettingsSectionTitle({ title: '网站' })
      }
      .width('100%')
      .margin({ bottom: -8 })

      LazyForEach(this.getRowsDataSource(), (row: SiteControlsListRowState, index: number) => {
        ListItem() {
          this.buildWebsiteRowCard(row, index)
        }
        .width('100%')
        .reuseId('site_controls_capability_site_row')
      }, (row: SiteControlsListRowState) => row.id)
    } else {
      ListItem() {
        AppEmptyState({
          airaIconId: 'settings.siteSettings',
          title: this.state.emptyTitle,
          message: this.state.emptyMessage,
          topPadding: 92,
          bottomPadding: 92,
          fillHeight: false
        })
      }
      .width('100%')
    }
  }

  @Builder
  private buildWebsiteRowCard(row: SiteControlsListRowState, index: number) {
    Column() {
      SiteControlsWebsiteRecordRow({
        rowId: row.id,
        title: row.title,
        host: row.host,
        origin: row.origin,
        iconUri: this.getIconPath(row.id),
        rowHeight: 58,
        rowBorderRadius: this.resolveWebsiteRowBorderRadius(index),
        iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        showDivider: index < this.state.rows.length - 1,
        onRowClick: () => {
          this.onOpenSite?.(row.host, row.origin);
        },
        trailing: () => {
          this.buildWebsiteRowTrailing()
        }
      })
    }
    .width('100%')
    .padding({
      left: SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_PADDING,
      right: SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_PADDING,
      top: index === 0 ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_PADDING : 0,
      bottom: index >= this.state.rows.length - 1 ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_PADDING : 0
    })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(this.resolveWebsiteRowCardRadius(index))
    .clip(true)
  }

  @Builder
  private buildWebsiteRowTrailing() {
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor([this.storedSecondaryTextColor])
  }

  private openManualOriginDialog(): void {
    this.manualOriginDraft = '';
    this.manualOriginError = '';
    this.manualOriginDialogController.open();
  }

  private confirmManualOrigin(): boolean {
    const errorMessage = this.resolveManualOriginError?.(this.manualOriginDraft) ?? '';
    if (errorMessage.length > 0) {
      this.manualOriginError = errorMessage;
      return false;
    }
    const value = this.manualOriginDraft.trim();
    if (value.length === 0) {
      this.manualOriginError = '请输入站点地址。';
      return false;
    }
    this.onOpenManualOrigin?.(value);
    return true;
  }

  private resolveTitle(): string {
    if (this.pageTitle.trim().length > 0) {
      return this.pageTitle;
    }
    return this.state.listTitle.length > 0 ? this.state.listTitle : '权限';
  }

  private getRowsDataSource(): SiteControlsListRowDataSource {
    if (this.rowsDataSourceRows !== this.state.rows) {
      this.rowsDataSourceRows = this.state.rows;
      this.rowsDataSource.replaceRows(this.state.rows);
    }
    return this.rowsDataSource;
  }

  private syncSiteIcons(): void {
    this.iconStates = this.iconStates.filter((icon: SiteControlsCapabilityWebsiteIconState): boolean => {
      return this.state.rows.some((row: SiteControlsListRowState): boolean => row.id === icon.id);
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
    return this.state.rows.map((row: SiteControlsListRowState): SiteIconListTarget => {
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
    const state = this.iconStates.find((item: SiteControlsCapabilityWebsiteIconState): boolean => item.id === rowId);
    return state?.path ?? '';
  }

  private setIconPath(rowId: string, path: string): void {
    const normalizedPath = path.trim();
    if (rowId.length <= 0 || normalizedPath.length <= 0) {
      return;
    }
    const existing = this.iconStates.find((item: SiteControlsCapabilityWebsiteIconState): boolean => item.id === rowId);
    if (existing !== undefined && existing.path === normalizedPath) {
      return;
    }
    const next = this.iconStates.filter((item: SiteControlsCapabilityWebsiteIconState): boolean => item.id !== rowId);
    this.iconStates = next.concat([{ id: rowId, path: normalizedPath }]);
  }

  private resolveWebsiteRowCardRadius(index: number): BorderRadiuses {
    const isFirst = index <= 0;
    const isLast = index >= this.state.rows.length - 1;
    return {
      topLeft: isFirst ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS : 0,
      topRight: isFirst ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS : 0,
      bottomLeft: isLast ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS : 0,
      bottomRight: isLast ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS : 0
    };
  }

  private resolveWebsiteRowBorderRadius(index: number): BorderRadiuses {
    const isFirst = index <= 0;
    const isLast = index >= this.state.rows.length - 1;
    return {
      topLeft: isFirst ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS : 0,
      topRight: isFirst ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS : 0,
      bottomLeft: isLast ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS : 0,
      bottomRight: isLast ? SITE_CONTROLS_CAPABILITY_SITE_ROW_CARD_RADIUS : 0
    };
  }

}
