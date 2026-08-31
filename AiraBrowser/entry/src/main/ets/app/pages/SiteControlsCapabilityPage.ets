import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { SiteControlsCapabilityScreen } from '../components/sitecontrols/SiteControlsCapabilityScreen';
import {
  SiteControlsCapabilityDefaultState,
  SiteControlsCoordinator,
  SiteControlsFilterId,
  SiteControlsListRowState,
  SiteControlsListState
} from '../../core/sitecontrols/SiteControlsCoordinator';
import {
  sharedPreferencesRepository
} from '../bootstrap/BrowserAppRuntime';
import {
  sharedBrowserSitePrivacyRuleRepository,
  sharedBrowserUserAgentSettingsRepository,
  sharedSavedSiteSettingRepository
} from '../bootstrap/BrowserAppRuntime';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import { BrowserProfileId, DEFAULT_BROWSER_PROFILE_ID } from '../../common/models/BrowserModels';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { SiteCustomizationManagementCoordinator } from '../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import { SiteCustomizationCapabilityFilterId } from '../../services/web/SiteCapabilityCatalogService';
import {
  SiteControlsNavigationDecision,
  SiteControlsSiteNavigationTarget
} from '../../core/sitecontrols/SiteControlsNavigationDecision';

interface SiteControlsCapabilityPageParams {
  kind?: string;
  customizationKind?: string;
  profileId?: string;
  capabilityTitle?: string;
  dataScope?: string;
  privacyMode?: string;
  boundarySource?: string;
}

@Entry
@Component
struct SiteControlsCapabilityPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private navigationDecision: SiteControlsNavigationDecision = new SiteControlsNavigationDecision();
  private coordinator: SiteControlsCoordinator = new SiteControlsCoordinator(sharedPreferencesRepository);
  private siteCustomizationCoordinator: SiteCustomizationManagementCoordinator = new SiteCustomizationManagementCoordinator(
    sharedPreferencesRepository,
    sharedBrowserUserAgentSettingsRepository,
    sharedBrowserSitePrivacyRuleRepository,
    undefined,
    sharedSavedSiteSettingRepository
  );
  @State private query: string = '';
  @State private filterId: SiteControlsFilterId = 'camera';
  @State private customizationFilterId: SiteCustomizationCapabilityFilterId | '' = '';
  @State private state: SiteControlsListState =
    this.coordinator.buildListState(DEFAULT_BROWSER_PROFILE_ID, '', 'camera');
  @State private defaultState: SiteControlsCapabilityDefaultState =
    this.coordinator.buildCapabilityDefaultState('camera');
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private pageTitle: string = '';
  @State private profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID;

  aboutToAppear(): void {
    this.refreshState();
  }

  onPageShow(): void {
    this.refreshList();
  }

  build() {
    Column() {
      SiteControlsCapabilityScreen({
        state: this.state,
        defaultState: this.defaultState,
        pageTitle: this.pageTitle,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        showDefaultSection: this.customizationFilterId.length === 0,
        showAddSiteAction: this.customizationFilterId === 'javascript',
        onOpenDefault: () => {
          this.openDefault();
        },
        onOpenSite: (host: string, origin: string) => {
          this.openSite(host, origin);
        },
        onQueryChange: (query: string) => {
          this.query = query;
          this.refreshList();
        },
        resolveManualOriginError: (value: string): string => {
          return this.siteCustomizationCoordinator.resolveManualTarget(value).errorMessage;
        },
        onOpenManualOrigin: (value: string): void => {
          this.openManualOrigin(value);
        },
        onClose: () => {
          this.navigationCoordinator.back();
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private refreshState(): void {
    const params = router.getParams() as SiteControlsCapabilityPageParams | undefined;
    this.customizationFilterId = this.normalizeCustomizationFilterId(params?.customizationKind ?? '');
    this.filterId = this.normalizeFilterId(params?.kind ?? this.filterId);
    this.profileId = (params?.profileId as BrowserProfileId) ?? this.profileId;
    this.pageTitle = params?.capabilityTitle ?? '';
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.refreshList();
  }

  private refreshList(): void {
    if (this.customizationFilterId.length > 0) {
      this.state = this.buildCustomizationListState(this.customizationFilterId as SiteCustomizationCapabilityFilterId);
    } else {
      this.state = this.coordinator.buildListState(this.profileId, this.query, this.filterId);
    }
    this.defaultState =
      this.coordinator.buildCapabilityDefaultState(this.filterId);
  }

  private openDefault(): void {
    if (this.filterId === 'open_app') {
      this.navigationCoordinator.openSiteControlsExternalNavigationDefault(this.buildBoundaryState());
      return;
    }
    this.navigationCoordinator.openSitePermissionDefault(this.filterId, this.buildBoundaryState());
  }

  private openSite(host: string, origin: string): void {
    const boundary = this.buildBoundaryState();
    boundary.subpage = 'site_controls';
    const target = this.navigationDecision.resolveSiteTarget(this.filterId, this.customizationFilterId);
    this.openSiteTarget(host, origin, boundary, target);
  }

  private openManualOrigin(value: string): void {
    const result = this.siteCustomizationCoordinator.resolveManualTarget(value);
    if (result.target === undefined) {
      return;
    }
    this.openSite(result.target.displayHost, result.target.canonicalOrigin);
  }

  private openSiteTarget(
    host: string,
    origin: string,
    boundary: BrowserBoundaryRouteState,
    target: SiteControlsSiteNavigationTarget
  ): void {
    if (target.kind === 'site_permission' && target.permissionKind !== undefined) {
      this.navigationCoordinator.openSiteCustomizationPermission(host, origin, this.profileId, target.permissionKind, boundary);
      return;
    }
    if (target.kind === 'desktop_site') {
      this.navigationCoordinator.openSiteCustomizationDesktopSite(host, origin, this.profileId, boundary);
      return;
    }
    if (target.kind === 'focused_site_customization') {
      this.navigationCoordinator.openSiteCustomizationDetail(
        host,
        origin,
        this.profileId,
        boundary,
        target.focusCapability
      );
      return;
    }
    this.navigationCoordinator.openSiteCustomizationDetail(host, origin, this.profileId, boundary);
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private normalizeFilterId(value: string): SiteControlsFilterId {
    if (
      value === 'camera' ||
      value === 'microphone' ||
        value === 'location' ||
        value === 'sensor' ||
        value === 'clipboard' ||
        value === 'open_app'
    ) {
      return value;
    }
    return 'camera';
  }

  private normalizeCustomizationFilterId(value: string): SiteCustomizationCapabilityFilterId | '' {
    if (
      value === 'external_actions' ||
        value === 'desktop_site' ||
        value === 'private_site' ||
        value === 'javascript'
    ) {
      return value;
    }
    return '';
  }

  private buildCustomizationListState(capabilityId: SiteCustomizationCapabilityFilterId): SiteControlsListState {
    const listState = this.siteCustomizationCoordinator.buildCapabilityListState(this.profileId, capabilityId, this.query);
    return {
      query: this.query,
      totalCount: listState.totalCount,
      filteredCount: listState.filteredCount,
      filterOptions: [],
      rows: listState.rows.map((row): SiteControlsListRowState => {
        const rowState: SiteControlsListRowState = {
          id: row.id,
          host: row.host,
          origin: row.origin,
          title: row.title,
          value: row.value,
          helperText: '',
          updatedAt: row.updatedAt
        };
        return rowState;
      }),
      hasRows: listState.hasRows,
      hasFilteredRows: listState.hasFilteredRows,
      summaryLine: '',
      listTitle: this.pageTitle,
      emptyTitle: `还没有${this.pageTitle}规则`,
      emptyMessage: `有站点改过${this.pageTitle}规则后，会出现在这里`
    };
  }
}
