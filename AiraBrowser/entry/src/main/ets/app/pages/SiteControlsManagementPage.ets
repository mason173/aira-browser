import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { SiteControlsManagementScreen } from '../components/sitecontrols/SiteControlsManagementScreen';
import { SiteControlsCustomizationCapabilityState } from '../components/sitecontrols/SiteControlsManagementScreen';
import {
  SiteControlsCoordinator,
  SiteControlsFilterId,
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
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../core/theme/BrowserThemeViewState';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  SiteCustomizationListState,
  SiteCustomizationManagementCoordinator,
  SiteCustomizationManualTargetResult
} from '../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import { SiteCustomizationCapabilityFilterId } from '../../services/web/SiteCapabilityCatalogService';

interface SiteControlsManagementPageParams {
  dataScope?: string;
  privacyMode?: string;
  boundarySource?: string;
  profileId?: string;
}

@Entry
@Component
struct SiteControlsManagementPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private themePreferencesListenerKey: string = '';
  private coordinator: SiteControlsCoordinator = new SiteControlsCoordinator(sharedPreferencesRepository);
  private siteCustomizationCoordinator: SiteCustomizationManagementCoordinator = new SiteCustomizationManagementCoordinator(
    sharedPreferencesRepository,
    sharedBrowserUserAgentSettingsRepository,
    sharedBrowserSitePrivacyRuleRepository,
    undefined,
    sharedSavedSiteSettingRepository
  );
  @State private query: string = '';
  @State private state: SiteControlsListState = this.coordinator.buildListState(DEFAULT_BROWSER_PROFILE_ID, '');
  @State private siteListState: SiteCustomizationListState =
    this.siteCustomizationCoordinator.buildListState(DEFAULT_BROWSER_PROFILE_ID, '');
  @State private customizationCapabilities: SiteControlsCustomizationCapabilityState[] = [];
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID;

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  onPageShow(): void {
    this.refreshState();
  }

  build() {
    Column() {
      SiteControlsManagementScreen({
        state: this.state,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        siteRows: this.siteListState.rows,
        siteRowsTotalCount: this.siteListState.totalCount,
        customizationCapabilities: this.customizationCapabilities,
        settingsIconBackgrounds: this.theme.settingsIconBackgrounds,
        onQueryChange: (query: string) => {
          this.query = query;
          this.refreshList();
        },
        onSelectFilter: (filterId: SiteControlsFilterId) => {
          this.openCapability(filterId);
        },
        onSelectCustomizationCapability: (capabilityId: SiteCustomizationCapabilityFilterId) => {
          this.openCustomizationCapability(capabilityId);
        },
        onOpenSite: (host: string, origin: string) => {
          this.openSite(host, origin);
        },
        resolveManualOriginError: (value: string): string => {
          return this.resolveManualOrigin(value).errorMessage;
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
    const params = router.getParams() as SiteControlsManagementPageParams | undefined;
    this.profileId = (params?.profileId as BrowserProfileId) ?? this.profileId;
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.refreshThemeState();
    this.refreshList();
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private refreshList(): void {
    this.state = this.coordinator.buildListState(this.profileId, this.query, 'all');
    this.siteListState = this.siteCustomizationCoordinator.buildListState(this.profileId, this.query);
    this.customizationCapabilities = this.buildCustomizationCapabilities();
  }

  private openCapability(filterId: SiteControlsFilterId): void {
    if (filterId === 'all') {
      return;
    }
    this.navigationCoordinator.openSiteControlsCapability(filterId, this.profileId, this.buildBoundaryState());
  }

  private openCustomizationCapability(capabilityId: SiteCustomizationCapabilityFilterId): void {
    this.navigationCoordinator.openSiteControlsCustomizationCapability(
      capabilityId,
      this.profileId,
      this.buildBoundaryState(),
      this.resolveCustomizationCapabilityTitle(capabilityId)
    );
  }

  private openSite(host: string, origin: string): void {
    const boundary = this.buildBoundaryState();
    boundary.subpage = 'site_controls';
    this.navigationCoordinator.openSiteCustomizationDetail(host, origin, this.profileId, boundary);
  }

  private resolveManualOrigin(value: string): SiteCustomizationManualTargetResult {
    return this.siteCustomizationCoordinator.resolveManualTarget(value);
  }

  private openManualOrigin(value: string): void {
    const result = this.resolveManualOrigin(value);
    if (result.target === undefined) {
      return;
    }
    this.openSite(result.target.displayHost, result.target.canonicalOrigin);
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private buildCustomizationCapabilities(): SiteControlsCustomizationCapabilityState[] {
    const capabilityIds: SiteCustomizationCapabilityFilterId[] = [
      'external_actions',
      'desktop_site',
      'private_site',
      'javascript'
    ];
    return capabilityIds.map((capabilityId: SiteCustomizationCapabilityFilterId): SiteControlsCustomizationCapabilityState => {
      const state: SiteControlsCustomizationCapabilityState = {
        id: capabilityId,
        title: this.resolveCustomizationCapabilityTitle(capabilityId),
        count: this.siteCustomizationCoordinator.buildCapabilityListState(this.profileId, capabilityId, '').totalCount
      };
      return state;
    });
  }

  private resolveCustomizationCapabilityTitle(capabilityId: SiteCustomizationCapabilityFilterId): string {
    if (capabilityId === 'external_actions') {
      return '外部动作';
    }
    if (capabilityId === 'private_site') {
      return '关闭后清除';
    }
    if (capabilityId === 'javascript') {
      return 'JavaScript';
    }
    return '网页标识';
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((_preferences, scope) => {
      if (scope === 'theme_mode' || scope === 'appearance') {
        this.refreshThemeState();
      }
    });
  }

  private unbindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length <= 0) {
      return;
    }
    sharedPreferencesRepository.unsubscribe(this.themePreferencesListenerKey);
    this.themePreferencesListenerKey = '';
  }
}
