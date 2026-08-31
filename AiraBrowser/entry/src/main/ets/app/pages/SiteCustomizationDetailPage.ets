import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../components/common/CenteredDialogSurface';
import router from '@ohos.router';
import { SiteCustomizationDetailScreen } from '../components/sitecustomization/SiteCustomizationDetailScreen';
import {
  SiteCustomizationDetailViewState,
  SiteCustomizationManagementViewModel
} from '../../core/sitecustomization/SiteCustomizationManagementViewModel';
import {
  SiteCustomizationManagementCoordinator,
  SiteJavaScriptPolicy
} from '../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import {
  sharedBrowserSitePrivacyRuleRepository,
  sharedBrowserUserAgentSettingsRepository,
  sharedPreferencesRepository,
  sharedSitePolicyService,
  sharedSavedSiteSettingRepository
} from '../bootstrap/BrowserAppRuntime';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import {
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID,
  ExternalNavigationAppOpenPolicy,
  SitePermissionKind
} from '../../common/models/BrowserModels';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import {
  SITE_CUSTOMIZATION_REFRESH_REVISION_KEY,
  SiteCustomizationRefreshSignal
} from '../../core/sitecustomization/SiteCustomizationRefreshSignal';
import {
  SiteControlsNavigationDecision,
  SiteCustomizationFocusCapability
} from '../../core/sitecontrols/SiteControlsNavigationDecision';

interface SiteCustomizationDetailPageParams {
  host?: string;
  origin?: string;
  profileId?: string;
  dataScope?: string;
  privacyMode?: string;
  boundarySource?: string;
  subpage?: string;
  focusCapability?: string;
}

@Entry
@Component
struct SiteCustomizationDetailPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private viewModel: SiteCustomizationManagementViewModel = new SiteCustomizationManagementViewModel();
  private coordinator: SiteCustomizationManagementCoordinator = new SiteCustomizationManagementCoordinator(
    sharedPreferencesRepository,
    sharedBrowserUserAgentSettingsRepository,
    sharedBrowserSitePrivacyRuleRepository,
    sharedSitePolicyService,
    sharedSavedSiteSettingRepository
  );
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private navigationDecision: SiteControlsNavigationDecision = new SiteControlsNavigationDecision();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private refreshSignal: SiteCustomizationRefreshSignal = new SiteCustomizationRefreshSignal();
  @StorageLink(SITE_CUSTOMIZATION_REFRESH_REVISION_KEY) @Watch('refreshStateFromSignal')
  private siteCustomizationRefreshRevision: number = 0;
  @State private host: string = '';
  @State private origin: string = '';
  @State private profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private subpage: string = '';
  @State private focusCapability: SiteCustomizationFocusCapability | '' = '';
  @State private state: SiteCustomizationDetailViewState = this.viewModel.buildDetailState(
    this.coordinator.buildDetailState('', '', DEFAULT_BROWSER_PROFILE_ID)
  );

  aboutToAppear(): void {
    this.refreshState();
  }

  onPageShow(): void {
    this.refreshState();
  }

  private refreshStateFromSignal(): void {
    this.refreshState();
  }

  build() {
    Column() {
      SiteCustomizationDetailScreen({
        state: this.state,
        renderVersion: this.siteCustomizationRefreshRevision,
        focusCapability: this.focusCapability,
        onTogglePrivateSite: (enabled: boolean) => {
          this.togglePrivateSite(enabled);
        },
        onTogglePrivateSitePreserveCookies: (enabled: boolean) => {
          this.togglePrivateSitePreserveCookies(enabled);
        },
        onOpenPermission: (kind: string) => {
          this.openPermission(kind as SitePermissionKind);
        },
        onOpenDesktopSite: () => {
          this.openUserAgent();
        },
        onSelectJavaScriptPolicy: (policy: SiteJavaScriptPolicy) => {
          this.selectJavaScriptPolicy(policy);
        },
        onToggleExternalNavigation: (policy: string, followDefault: boolean) => {
          this.toggleExternalNavigation(policy as ExternalNavigationAppOpenPolicy, followDefault);
        },
        onReset: () => {
          this.confirmResetSite();
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
    const params = router.getParams() as SiteCustomizationDetailPageParams | undefined;
    this.subpage = params?.subpage ?? this.subpage;
    this.focusCapability = this.navigationDecision.normalizeFocusCapability(params?.focusCapability ?? this.focusCapability);
    if (!this.isSiteControlsMode() && !this.ensureOptionalServiceRoute()) {
      return;
    }
    this.host = params?.host ?? this.host;
    this.origin = params?.origin ?? this.origin;
    this.profileId = (params?.profileId as BrowserProfileId) ?? this.profileId;
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.state = this.viewModel.buildDetailState(
      this.coordinator.buildDetailState(this.host, this.origin, this.profileId, this.dataScope, this.privacyMode)
    );
  }

  private toggleExternalNavigation(policy: ExternalNavigationAppOpenPolicy, followDefault: boolean): void {
    const operation = followDefault
      ? this.coordinator.resetExternalNavigationPolicy(this.host, this.origin, this.profileId)
      : this.coordinator.updateExternalNavigationPolicy(this.host, this.origin, policy, this.profileId);
    operation
      .then(() => {
        this.refreshState();
        this.refreshSignal.bump('general', this.origin, this.profileId);
      })
      .catch((_error: Error) => {});
  }

  private togglePrivateSite(enabled: boolean): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.coordinator.setPrivateSiteMode(this.host, this.origin, enabled ? 'clear_on_close' : 'default', this.profileId)
      .then(() => {
        this.refreshState();
        this.refreshSignal.bump('privacy', this.origin, this.profileId);
      })
      .catch((_error: Error) => {});
  }

  private togglePrivateSitePreserveCookies(enabled: boolean): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.coordinator.setPrivateSitePreserveCookies(this.host, this.origin, enabled, this.profileId)
      .then(() => {
        this.refreshState();
        this.refreshSignal.bump('cookie', this.origin, this.profileId);
      })
      .catch((_error: Error) => {});
  }

  private selectJavaScriptPolicy(policy: SiteJavaScriptPolicy): void {
    this.coordinator.setJavaScriptPolicy(
      this.host,
      this.origin,
      policy,
      this.profileId,
      this.dataScope,
      this.privacyMode
    )
      .then((): void => {
        this.refreshState();
      })
      .catch((_error: Error): void => {});
  }

  private resetSite(): void {
    if (!this.isSiteControlsMode() && !this.ensureOptionalServiceRoute()) {
      return;
    }
    const operation = this.isSiteControlsMode()
      ? this.coordinator.resetSiteControls(this.host, this.origin, this.profileId, this.dataScope, this.privacyMode)
      : this.coordinator.resetSiteCustomizations(this.host, this.origin, this.profileId, this.dataScope, this.privacyMode);
    operation
      .then(() => {
        this.refreshState();
        this.refreshSignal.bump('reset', this.origin, this.profileId);
      })
      .catch((_error: Error) => {});
  }

  private confirmResetSite(): void {
    showCenteredAlertDialog({
      title: '重置当前站点',
      message: this.state.hasUnreadableEntry
        ? '将删除无法读取的站点设置记录。之后可以重新配置当前站点。'
        : this.isSiteControlsMode()
        ? '将清除这个站点的 JavaScript、设备权限和打开应用规则。'
        : '将清除这个站点的网页标识、JavaScript、关闭后清除、打开应用和权限自定义规则。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '重置',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.resetSite();
        }
      }
    });
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }

  private openPermission(kind: SitePermissionKind): void {
    this.navigationCoordinator.openSiteCustomizationPermission(
      this.host,
      this.origin,
      this.profileId,
      kind,
      {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        subpage: this.subpage
      }
    );
  }

  private openUserAgent(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.navigationCoordinator.openSiteCustomizationDesktopSite(
      this.host,
      this.origin,
      this.profileId,
      {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        subpage: this.subpage
      }
    );
  }

  private isSiteControlsMode(): boolean {
    return this.subpage === 'site_controls';
  }

}
