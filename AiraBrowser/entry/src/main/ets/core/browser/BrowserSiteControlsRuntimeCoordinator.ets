import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  SitePermissionKind,
  SitePermissionRule,
  SitePermissionSettings
} from '../../common/models/BrowserModels';
import { BrowserPageReloadReason } from './BrowserRuntimeActionReason';
import {
  BrowserAdBlockCoordinator,
  BrowserAdBlockProtectionAvailabilityState,
  BrowserAdBlockPrivacyCoverageState,
  BrowserAdBlockPageRuntimeContext
} from './BrowserAdBlockCoordinator';
import {
  BrowserWebProtectionFeedbackPresentation,
  BrowserWebProtectionFeedbackSessionCoordinator,
  EMPTY_BROWSER_WEB_PROTECTION_FEEDBACK_PRESENTATION
} from './BrowserWebProtectionFeedbackSessionCoordinator';
import { AdBlockCosmeticInjectionSummary } from '../../services/adblock/AdBlockCosmeticInjectionService';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import {
  SiteCertificatePresentationRuntimeContext,
  SiteCertificatePresentationService,
  SiteCertificatePresentationState
} from '../../services/web/SiteCertificatePresentationService';
import {
  CurrentSiteDataSummary,
  SiteDataClearDialogState,
  SiteDataControlService
} from '../../services/web/SiteDataControlService';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import {
  SiteInteractionLogicService,
  SitePermissionDraftState
} from '../../services/web/SiteInteractionLogicService';
import { BrowserSecurityReportMetricsRepository } from '../../data/browser/BrowserSecurityReportMetricsRepository';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserShellRouteCoordinator } from './BrowserShellRouteCoordinator';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import {
  isSecureCurrentSiteUrl,
  resolveConnectionStatusTitle,
  resolveCurrentSiteHost,
  resolveCurrentSiteUrl
} from './AddressDisplayFormatter';
import { BrowserFingerprintPrivacyPolicyService } from '../../services/privacy/BrowserFingerprintPrivacyPolicyService';

const PROTECTION_DEBUG_DOMAIN: number = 0x0000;
const PROTECTION_DEBUG_TAG: string = 'ProtectionCountDiag';
const PROTECTION_DEBUG_PREFIX: string = '[DEBUG-protection-count-20260808]';

export type BrowserSiteInfoSheetMode =
  'security' |
  'overview' |
  'certificate' |
  'adblock_log' |
  'permission_camera' |
  'permission_microphone' |
  'permission_location' |
  'permission_sensor' |
  'permission_clipboard';

type BrowserSiteControlsNavigationDirection = 'none' | 'forward' | 'backward';

interface BrowserSiteControlsDataState {
  loading: boolean;
  cookieCount: number;
  storageUsageBytes: number;
  storageOrigin: string;
}

interface BrowserSiteControlsProtectionState {
  capabilitySupported: boolean;
  availabilityState: BrowserAdBlockProtectionAvailabilityState;
  summary: string;
  siteToggleEnabled: boolean;
  siteEnabled: boolean;
  blockedCount: number;
  requestBlockingCount: number;
  linkCleaningCount: number;
  elementHidingCount: number;
  privacyCoverageState: BrowserAdBlockPrivacyCoverageState;
  privacyCoverageSummary: string;
}

export class BrowserSiteControlsSessionState {
  mode: BrowserSiteInfoSheetMode = 'overview';
  returnMode: BrowserSiteInfoSheetMode = 'overview';
  navigationDirection: BrowserSiteControlsNavigationDirection = 'none';
  permissionDraft: SitePermissionDraftState = {
    origin: '', camera: 'ask', microphone: 'ask', location: 'ask', sensor: 'ask', clipboard: 'ask'
  };
  savedPermissionDraft: SitePermissionDraftState = {
    origin: '', camera: 'ask', microphone: 'ask', location: 'ask', sensor: 'ask', clipboard: 'ask'
  };
  relatedOrigins: string[] = [];
  data: BrowserSiteControlsDataState = {
    loading: false, cookieCount: 0, storageUsageBytes: 0, storageOrigin: ''
  };
  certificate: SiteCertificatePresentationState = {
    summary: '正在读取证书信息...',
    detailStatus: '正在读取证书信息...',
    subject: '',
    issuer: '',
    validFrom: '',
    validTo: '',
    serialNumber: '',
    signatureAlgorithm: '',
    chainCount: 0
  };
  protection: BrowserSiteControlsProtectionState = {
    capabilitySupported: true,
    availabilityState: 'capability_unavailable',
    summary: '正在读取保护状态...',
    siteToggleEnabled: false,
    siteEnabled: true,
    blockedCount: 0,
    requestBlockingCount: 0,
    linkCleaningCount: 0,
    elementHidingCount: 0,
    privacyCoverageState: 'preparing',
    privacyCoverageSummary: '正在读取隐私规则状态'
  };

}

export interface BrowserSiteControlsApplicationContext {
  activeTabId: string;
  targetTabId: string;
  currentUrl: string;
  addressInput: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  isPrivateMode: boolean;
  controllerAttached: boolean;
  shouldDeferTrackingRefresh: boolean;
  trackingRefreshDelayMs: number;
  strengthenAdBlockingForSmoothScroll: boolean;
}

export interface BrowserSiteControlsApplicationSnapshot {
  session: BrowserSiteControlsSessionState;
  isSecureSite: boolean;
  isPrivateMode: boolean;
  connectionTitle: string;
  siteHost: string;
  siteDataSummary: string;
  siteCookieCount: number;
  canClearCurrentSiteStorage: boolean;
  siteGuardianDays: number;
  certificateChainText: string;
  webProtectionFeedback: BrowserWebProtectionFeedbackPresentation;
  trackingProtectionEnhanced: boolean;
  trackingProtectionSummary: string;
  todayProtectionActionCount: number;
  sevenDayProtectionActionCount: number;
}

export type BrowserSiteControlsUserAction =
  'cancel' |
  'save' |
  'copy_url' |
  'open_permission' |
  'change_permission' |
  'clear_site_data' |
  'confirm_clear_site_data' |
  'open_browsing_data_settings' |
  'open_protection_settings' |
  'open_tracking_protection_settings' |
  'toggle_protection' |
  'open_site_customization' |
  'open_certificate' |
  'open_protection_log' |
  'open_overview' |
  'navigate_back' |
  'close';

export type BrowserSiteControlsActiveSurfaceAction =
  'refresh_permissions' |
  'set_certificate_loading' |
  'refresh_certificate' |
  'refresh_tracking';

export type BrowserSiteControlsMessageKind = 'error' | 'toast';

export interface BrowserSiteControlsRuntimeFacts {
  controllerAttached: boolean;
  shouldDeferTrackingRefresh: boolean;
  trackingRefreshDelayMs: number;
  strengthenAdBlockingForSmoothScroll: boolean;
}

export interface BrowserSiteControlsApplicationShell {
  resolveAbilityContext: () => common.UIAbilityContext;
  readRuntimeFacts: () => BrowserSiteControlsRuntimeFacts;
  publishSnapshot: (snapshot: BrowserSiteControlsApplicationSnapshot) => void;
  presentMessage: (kind: BrowserSiteControlsMessageKind, message: string) => void;
  presentClearSiteDataDialog: (state: SiteDataClearDialogState) => void;
  copyCurrentUrl: () => void;
}

export interface BrowserSiteControlsPageToolsSurface {
  open: (type: 'siteInfo') => void;
  dismiss: () => void;
  isActive: (type: 'siteInfo') => boolean;
}

export interface BrowserSiteControlsApplicationDependencies {
  securityReportMetricsRepository: BrowserSecurityReportMetricsRepository;
  routeCoordinator: BrowserShellRouteCoordinator;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  reloadActive: (reason: BrowserPageReloadReason) => void;
}

export const DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT: BrowserSiteControlsApplicationSnapshot = {
  session: new BrowserSiteControlsSessionState(),
  isSecureSite: false,
  isPrivateMode: false,
  connectionTitle: '站点信息',
  siteHost: '',
  siteDataSummary: 'Cookie 0 个 · 存储 0 B',
  siteCookieCount: 0,
  canClearCurrentSiteStorage: false,
  siteGuardianDays: 0,
  certificateChainText: '',
  webProtectionFeedback: EMPTY_BROWSER_WEB_PROTECTION_FEEDBACK_PRESENTATION,
  trackingProtectionEnhanced: false,
  trackingProtectionSummary: '标准',
  todayProtectionActionCount: 0,
  sevenDayProtectionActionCount: 0
};

export class BrowserSiteControlsRuntimeCoordinator {
  private readonly certificateService: SiteCertificatePresentationService;
  private readonly adBlockCoordinator: BrowserAdBlockCoordinator;
  private readonly siteDataControlService: SiteDataControlService;
  private readonly sitePolicyService: SitePolicyService;
  private readonly siteInteractionLogicService: SiteInteractionLogicService;
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly securityReportMetricsRepository: BrowserSecurityReportMetricsRepository;
  private readonly routeCoordinator: BrowserShellRouteCoordinator;
  private readonly hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  private readonly tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  private readonly reloadActive: (reason: BrowserPageReloadReason) => void;
  private readonly applicationShell: BrowserSiteControlsApplicationShell;
  private pageToolsSurface?: BrowserSiteControlsPageToolsSurface;
  private readonly sessionState: BrowserSiteControlsSessionState = new BrowserSiteControlsSessionState();
  private applicationSnapshot: BrowserSiteControlsApplicationSnapshot =
    DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT;
  private guardianDays: number = 0;
  private pendingTrackingRefreshTimer: number = -1;
  private readonly protectionFeedbackSessionCoordinator: BrowserWebProtectionFeedbackSessionCoordinator;

  constructor(
    certificateService: SiteCertificatePresentationService,
    adBlockCoordinator: BrowserAdBlockCoordinator,
    siteDataControlService: SiteDataControlService,
    sitePolicyService: SitePolicyService,
    siteInteractionLogicService: SiteInteractionLogicService,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    applicationDependencies: BrowserSiteControlsApplicationDependencies,
    applicationShell: BrowserSiteControlsApplicationShell
  ) {
    this.certificateService = certificateService;
    this.adBlockCoordinator = adBlockCoordinator;
    this.siteDataControlService = siteDataControlService;
    this.sitePolicyService = sitePolicyService;
    this.siteInteractionLogicService = siteInteractionLogicService;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.securityReportMetricsRepository = applicationDependencies.securityReportMetricsRepository;
    this.routeCoordinator = applicationDependencies.routeCoordinator;
    this.hostedRuntimeSurfacePort = applicationDependencies.hostedRuntimeSurfacePort;
    this.tabScopedEventContextCoordinator = applicationDependencies.tabScopedEventContextCoordinator;
    this.reloadActive = applicationDependencies.reloadActive;
    this.applicationShell = applicationShell;
    this.protectionFeedbackSessionCoordinator = new BrowserWebProtectionFeedbackSessionCoordinator({
      isTabActive: (tabId: string): boolean => this.resolveApplicationContext().activeTabId === tabId,
      onPresentationChanged: (): void => this.publishApplicationSnapshot()
    });
  }

  getApplicationSnapshot(): BrowserSiteControlsApplicationSnapshot {
    // BrowserShellPage creates its initial @State from this getter before its
    // tab-backed state is available. Keep this boundary a pure snapshot read;
    // runtime context and feedback presentation are refreshed only by their
    // established event paths after the shell has initialized.
    return this.applicationSnapshot;
  }

  bindPageToolsSurface(surface: BrowserSiteControlsPageToolsSurface): void {
    this.pageToolsSurface = surface;
  }

  getRelatedOriginCount(): number {
    return this.sessionState.relatedOrigins.length;
  }

  isAdBlockCapabilitySupported(): boolean {
    return this.sessionState.protection.capabilitySupported;
  }

  open(mode: BrowserSiteInfoSheetMode = 'overview'): void {
    const context = this.resolveApplicationContext();
    // Site Info is now a current-page protection report. Older callers may
    // still ask for the legacy security mode, but they intentionally land on
    // the same report instead of the former permission/data overview.
    this.prepareOpenSession('overview', context);
    this.requirePageToolsSurface().open('siteInfo');
    this.refreshActiveProtectionPresentation();
  }

  handleUserAction(
    action: BrowserSiteControlsUserAction,
    permissionKind?: SitePermissionKind,
    permissionRule?: SitePermissionRule
  ): void {
    const resolvedPermissionKind: SitePermissionKind = permissionKind ?? 'camera';
    const resolvedPermissionRule: SitePermissionRule = permissionRule ?? 'ask';
    switch (action) {
      case 'cancel':
      case 'close':
        this.closeApplicationSurface();
        return;
      case 'save':
        void this.saveApplicationPermissionDraft();
        return;
      case 'copy_url':
        this.applicationShell.copyCurrentUrl();
        return;
      case 'open_permission':
        this.openPermissionRule(resolvedPermissionKind);
        return;
      case 'change_permission':
        this.stagePermissionRule(resolvedPermissionKind, resolvedPermissionRule);
        return;
      case 'clear_site_data':
        this.presentClearCurrentSiteDataConfirmation();
        return;
      case 'confirm_clear_site_data':
        this.clearCurrentSiteData();
        return;
      case 'open_browsing_data_settings':
        this.closeApplicationSurfaceInternal(false);
        this.routeCoordinator.openSettingsDetailPage('privacy_security');
        return;
      case 'open_protection_settings':
        this.closeApplicationSurfaceInternal(false);
        this.routeCoordinator.openAdBlockSettingsPage();
        return;
      case 'open_tracking_protection_settings':
        this.closeApplicationSurfaceInternal(false);
        this.routeCoordinator.openTrackingProtectionSettingsPage();
        return;
      case 'toggle_protection':
        void this.toggleCurrentSiteProtection();
        return;
      case 'open_site_customization':
        this.closeApplicationSurfaceInternal(false);
        this.routeCoordinator.openCurrentSiteControls();
        return;
      case 'open_certificate':
        this.openCertificateDetails();
        return;
      case 'open_protection_log':
        this.openProtectionLog();
        return;
      case 'open_overview':
        this.openOverview();
        return;
      case 'navigate_back':
        this.navigateBack();
        return;
      default:
        return;
    }
  }

  handleActiveSurfaceAction(action: BrowserSiteControlsActiveSurfaceAction): void {
    switch (action) {
      case 'refresh_permissions':
        this.refreshCurrentSitePermissions();
        return;
      case 'set_certificate_loading':
        this.sessionState.certificate = this.certificateService.buildLoadingState();
        this.publishApplicationSnapshot();
        return;
      case 'refresh_certificate':
        this.refreshCertificate();
        return;
      case 'refresh_tracking':
        this.refreshTrackingProtectionStatus();
        return;
      default:
        return;
    }
  }

  refreshCurrentSitePermissions(): void {
    const context = this.resolveApplicationContext();
    if (this.requirePageToolsSurface().isActive('siteInfo')) {
      return;
    }
    this.refreshPermissions(context);
  }

  configureCurrentPageAdBlock(): void {
    const context = this.resolveApplicationContext();
    this.sessionState.protection.capabilitySupported = this.adBlockCoordinator.configureControllerForPage(
      this.buildAdBlockContext(context),
      this.runtimeLifecyclePort
    ).capabilitySupported;
    this.publishApplicationSnapshot();
  }

  refreshTrackingProtectionStatus(force: boolean = false): void {
    const context = this.resolveApplicationContext();
    if (!force && !this.requirePageToolsSurface().isActive('siteInfo') && context.shouldDeferTrackingRefresh) {
      this.scheduleTrackingProtectionStatusRefresh(context.trackingRefreshDelayMs);
      return;
    }
    this.clearTrackingProtectionStatusTimer();
    const status = this.adBlockCoordinator.resolveProtectionStatus(
      this.buildAdBlockContext(context),
      this.runtimeLifecyclePort
    );
    this.sessionState.protection.capabilitySupported = status.capabilitySupported;
    this.sessionState.protection.availabilityState = status.availabilityState;
    this.sessionState.protection.summary = status.summary;
    this.sessionState.protection.siteToggleEnabled = status.siteToggleEnabled;
    this.sessionState.protection.siteEnabled = status.siteEnabled;
    const privacyCoverage = this.adBlockCoordinator.resolvePrivacyCoverage(this.buildAdBlockContext(context));
    this.sessionState.protection.privacyCoverageState = privacyCoverage.state;
    this.sessionState.protection.privacyCoverageSummary = privacyCoverage.summary;
    this.publishApplicationSnapshot();
  }

  refreshActiveProtectionPresentation(): void {
    const context = this.resolveApplicationContext();
    const snapshot = this.adBlockCoordinator.getPageProtectionSnapshot(context.activeTabId);
    this.sessionState.protection.blockedCount = snapshot.totalActionCount;
    this.sessionState.protection.requestBlockingCount = snapshot.requestBlockingCount;
    this.sessionState.protection.linkCleaningCount = snapshot.linkCleaningCount;
    this.sessionState.protection.elementHidingCount = snapshot.elementHidingCount;
    const privacyCoverage = this.adBlockCoordinator.resolvePrivacyCoverage(this.buildAdBlockContext(context));
    this.sessionState.protection.privacyCoverageState = privacyCoverage.state;
    this.sessionState.protection.privacyCoverageSummary = privacyCoverage.summary;
    this.protectionFeedbackSessionCoordinator.observe(snapshot, context.privacyMode);
    hilog.info(
      PROTECTION_DEBUG_DOMAIN,
      PROTECTION_DEBUG_TAG,
      '%{public}s refresh generation=%{public}d total=%{public}d request=%{public}d link=%{public}d element=%{public}d',
      PROTECTION_DEBUG_PREFIX,
      snapshot.navigationGeneration,
      snapshot.totalActionCount,
      snapshot.requestBlockingCount,
      snapshot.linkCleaningCount,
      snapshot.elementHidingCount
    );
    this.publishApplicationSnapshot();
    this.refreshTrackingProtectionStatus();
  }

  resetPageProtectionFeedback(tabId: string): void {
    const context = this.resolveApplicationContext(tabId);
    const snapshot = this.adBlockCoordinator.getPageProtectionSnapshot(tabId);
    this.protectionFeedbackSessionCoordinator.resetForNavigation(snapshot, context.privacyMode);
    if (tabId === context.activeTabId) {
      this.sessionState.protection.blockedCount = 0;
      this.sessionState.protection.requestBlockingCount = 0;
      this.sessionState.protection.linkCleaningCount = 0;
      this.sessionState.protection.elementHidingCount = 0;
      this.publishApplicationSnapshot();
    }
  }

  setLargeScreenAddressEditing(editing: boolean): void {
    this.protectionFeedbackSessionCoordinator.setLargeScreenAddressEditing(editing);
  }

  setPhoneChromeCompact(compact: boolean): void {
    this.protectionFeedbackSessionCoordinator.setPhoneChromeCompact(compact);
  }

  clearPrivateProtectionSession(profileId: BrowserProfileId): void {
    this.adBlockCoordinator.clearPrivateSiteProtectionOverrides(profileId);
    this.protectionFeedbackSessionCoordinator.clearPrivateSessions();
  }

  handleInterceptRequest(tabId: string, request: WebResourceRequest): WebResourceResponse | null {
    const context = this.resolveApplicationContext(tabId);
    const response = this.adBlockCoordinator.handleInterceptRequest({
      tabId: tabId,
      request: request,
      pageUrl: this.resolveContextPageUrl(context),
      capabilitySupported: this.sessionState.protection.capabilitySupported,
      controllerAttached: context.controllerAttached,
      profileId: context.profileId,
      privacyMode: context.privacyMode,
      dataScope: context.dataScope,
      strengthenForSmoothScroll: context.strengthenAdBlockingForSmoothScroll
    });
    if (response !== null && tabId === context.activeTabId) {
      this.refreshActiveProtectionPresentation();
    }
    return response;
  }

  handleAdBlockCosmeticHidden(tabId: string, payloadJson: string): void {
    const context = this.resolveApplicationContext(tabId);
    const result = this.adBlockCoordinator.recordCosmeticHiddenFromPayload({
      tabId: tabId,
      payloadJson: payloadJson,
      currentPageUrl: this.resolveContextPageUrl(context)
    });
    if (result.totalActionCount > 0 && tabId === context.activeTabId) {
      this.refreshActiveProtectionPresentation();
    }
  }

  handleShellDisappear(): void {
    this.clearTrackingProtectionStatusTimer();
    this.closeSession(true);
  }

  resetApplicationSurface(): void {
    this.resetNavigation();
  }

  closeApplicationSurface(): void {
    this.closeApplicationSurfaceInternal(true);
  }

  handleApplicationSurfaceBack(): void {
    if (this.sessionState.mode !== 'security' && this.sessionState.mode !== 'overview') {
      this.navigateBack();
      return;
    }
    this.closeApplicationSurface();
  }

  private requirePageToolsSurface(): BrowserSiteControlsPageToolsSurface {
    if (this.pageToolsSurface === undefined) {
      throw new Error('Browser Site Controls Page Tools surface is not bound.');
    }
    return this.pageToolsSurface;
  }

  private prepareOpenSession(mode: BrowserSiteInfoSheetMode, context: BrowserSiteControlsApplicationContext): void {
    this.refreshPermissions(context);
    this.sessionState.mode = mode;
    this.sessionState.returnMode = mode === 'security' ? 'security' : 'overview';
    this.sessionState.navigationDirection = 'none';
    this.sessionState.savedPermissionDraft = this.copyPermissionDraft(this.sessionState.permissionDraft);
    this.notifySessionChanged();
  }

  private closeSession(revertDraft: boolean): void {
    if (revertDraft) {
      this.sessionState.permissionDraft = this.copyPermissionDraft(this.sessionState.savedPermissionDraft);
    }
    this.notifySessionChanged();
  }

  private resetNavigation(): void {
    this.sessionState.mode = 'overview';
    this.sessionState.returnMode = 'overview';
    this.sessionState.navigationDirection = 'none';
    this.notifySessionChanged();
  }

  private openCertificateDetails(): void {
    this.refreshCertificate();
    this.sessionState.returnMode = this.resolveDetailReturnMode(this.sessionState.mode);
    this.sessionState.mode = 'certificate';
    this.sessionState.navigationDirection = 'forward';
    this.notifySessionChanged();
  }

  private openProtectionLog(): void {
    this.sessionState.returnMode = this.resolveDetailReturnMode(this.sessionState.mode);
    this.sessionState.mode = 'adblock_log';
    this.sessionState.navigationDirection = 'forward';
    this.notifySessionChanged();
  }

  private openOverview(): void {
    this.sessionState.mode = 'overview';
    this.sessionState.navigationDirection = 'forward';
    this.notifySessionChanged();
  }

  private navigateBack(): void {
    this.sessionState.mode = this.sessionState.returnMode === 'security' ? 'security' : 'overview';
    this.sessionState.navigationDirection = 'backward';
    this.notifySessionChanged();
  }

  private openPermissionRule(kind: SitePermissionKind): void {
    this.sessionState.mode = this.resolvePermissionRuleMode(kind);
    this.sessionState.navigationDirection = 'forward';
    this.notifySessionChanged();
  }

  private stagePermissionRule(kind: SitePermissionKind, rule: SitePermissionRule): void {
    const fallbackOrigin = this.resolveCurrentSiteOrigin(this.resolveApplicationContext());
    const draft = this.sessionState.permissionDraft;
    this.sessionState.permissionDraft = this.siteInteractionLogicService.applyRuleToDraft({
      origin: draft.origin.length > 0 ? draft.origin : fallbackOrigin,
      camera: draft.camera,
      microphone: draft.microphone,
      location: draft.location,
      sensor: draft.sensor,
      clipboard: draft.clipboard
    }, kind, rule);
    this.notifySessionChanged();
  }

  private refreshPermissions(context: BrowserSiteControlsApplicationContext): void {
    const currentSiteOrigin = this.resolveCurrentSiteOrigin(context);
    const settings = this.sitePolicyService.getEffectiveSitePermissionSettings(
      currentSiteOrigin,
      context.profileId,
      context.dataScope
    );
    this.sessionState.permissionDraft = this.siteInteractionLogicService.buildDraftFromSettings(settings);
    this.notifySessionChanged();
  }

  addRelatedOrigin(origin: string): void {
    const normalizedOrigin = this.siteInteractionLogicService.normalizeOrigin(origin);
    if (normalizedOrigin.length > 0 && this.sessionState.relatedOrigins.indexOf(normalizedOrigin) < 0) {
      this.sessionState.relatedOrigins = this.sessionState.relatedOrigins.concat([normalizedOrigin]);
      this.notifySessionChanged();
    }
  }

  clearRelatedOrigins(): void {
    this.sessionState.relatedOrigins = [];
    this.notifySessionChanged();
  }

  buildPermissionUpdateOrigins(origin: string, currentOrigin: string): string[] {
    return this.siteInteractionLogicService.buildPermissionUpdateOrigins(
      origin,
      currentOrigin,
      this.sessionState.relatedOrigins
    );
  }

  applyPersistedPermissionSettings(
    origins: string[],
    settings: SitePermissionSettings,
    currentOrigin: string
  ): void {
    const normalizedCurrentOrigin = this.siteInteractionLogicService.normalizeOrigin(currentOrigin);
    const normalizedDraftOrigin = this.siteInteractionLogicService.normalizeOrigin(
      this.sessionState.permissionDraft.origin
    );
    const shouldApply = origins.some((origin: string) => {
      const normalizedOrigin = this.siteInteractionLogicService.normalizeOrigin(origin);
      return normalizedOrigin === normalizedDraftOrigin || normalizedOrigin === normalizedCurrentOrigin;
    });
    if (shouldApply) {
      this.sessionState.permissionDraft = this.siteInteractionLogicService.buildDraftFromSettings(settings);
      this.notifySessionChanged();
    }
  }

  private resolveCertificateChainText(): string {
    return this.certificateService.buildChainDetailText(this.sessionState.certificate.chainCount);
  }

  private resolveSiteDataSummary(): string {
    if (this.sessionState.data.loading) {
      return '读取中';
    }
    return `Cookie ${this.sessionState.data.cookieCount} 个 · 存储 ${
      this.siteInteractionLogicService.formatBytes(this.sessionState.data.storageUsageBytes)
    }`;
  }

  private buildClearCurrentSiteDataDialogState(
    profileId: BrowserProfileId,
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): SiteDataClearDialogState {
    return this.siteDataControlService.buildClearCurrentSiteDataDialogState(profileId, privacyMode, dataScope);
  }

  injectAdBlockCosmeticRulesForPage(
    tabId: string,
    pageUrl: string
  ): Promise<AdBlockCosmeticInjectionSummary> {
    const context = this.resolveApplicationContext(tabId);
    return this.adBlockCoordinator.injectCosmeticRulesForPage({
      tabId: tabId,
      pageUrl: pageUrl,
      capabilitySupported: this.sessionState.protection.capabilitySupported,
      controllerAttached: context.controllerAttached,
      profileId: context.profileId,
      privacyMode: context.privacyMode,
      dataScope: context.dataScope
    }, this.runtimeLifecyclePort);
  }

  private closeApplicationSurfaceInternal(revertDraft: boolean): void {
    this.closeSession(revertDraft);
    this.requirePageToolsSurface().dismiss();
  }

  private async saveApplicationPermissionDraft(): Promise<void> {
    const context = this.resolveApplicationContext();
    const currentOrigin = this.resolveCurrentSiteOrigin(context);
    const draft = this.sessionState.permissionDraft;
    const savedDraft = this.sessionState.savedPermissionDraft;
    const origin = draft.origin.length > 0 ? draft.origin : currentOrigin;
    if (origin.length === 0) {
      this.applicationShell.presentMessage('toast', '当前页面没有可管理的站点权限。');
      return;
    }
    if (!this.siteInteractionLogicService.hasDraftChanged(draft, savedDraft)) {
      this.closeApplicationSurfaceInternal(false);
      return;
    }
    const updateOrigins = this.buildPermissionUpdateOrigins(origin, currentOrigin);
    const cameraChanged = savedDraft.camera !== draft.camera;
    const microphoneChanged = savedDraft.microphone !== draft.microphone;
    const clipboardChanged = savedDraft.clipboard !== draft.clipboard;
    try {
      if (clipboardChanged && draft.clipboard === 'allow') {
        const permissionResult = await this.sitePolicyService.requestAppPermissionsForKinds(
          this.applicationShell.resolveAbilityContext(),
          ['clipboard']
        );
        if (!permissionResult.granted) {
          this.applicationShell.presentMessage(
            'toast',
            permissionResult.settingsRequired
              ? '系统剪贴板权限未开启，请在系统设置中允许后重试。'
              : '需要允许系统剪贴板权限，网页才能读取并粘贴内容。'
          );
          return;
        }
      }
      await this.sitePolicyService.persistPermissionDraftForOrigins(updateOrigins, {
        camera: draft.camera, microphone: draft.microphone, location: draft.location,
        sensor: draft.sensor, clipboard: draft.clipboard
      }, context.profileId, context.dataScope);
      const settings = this.resolveEffectiveSitePermissionSettings(
        origin, currentOrigin, context.profileId, context.dataScope
      );
      this.sessionState.permissionDraft = this.siteInteractionLogicService.buildDraftFromSettings(settings);
      this.sessionState.savedPermissionDraft = this.copyPermissionDraft(this.sessionState.permissionDraft);
      this.notifySessionChanged();
      if (cameraChanged) {
        this.sitePolicyService.stopActiveCameraCaptureFromLifecyclePort(
          this.runtimeLifecyclePort, context.controllerAttached
        );
      }
      if (microphoneChanged) {
        this.sitePolicyService.stopActiveMicrophoneCaptureFromLifecyclePort(
          this.runtimeLifecyclePort, context.controllerAttached
        );
      }
      const appliesToCurrentSite = this.siteInteractionLogicService.isSamePermissionSite(origin, currentOrigin);
      this.applicationShell.presentMessage('toast', '权限设置已保存。');
      if (appliesToCurrentSite && clipboardChanged) {
        this.hostedRuntimeSurfacePort.updateCurrentActiveConfigFromHost();
      }
      if (appliesToCurrentSite) {
        this.reloadActive('site_permission_apply');
      }
      this.closeApplicationSurfaceInternal(false);
    } catch (error) {
      this.applicationShell.presentMessage('error', `权限保存失败：${JSON.stringify(error)}`);
      this.applicationShell.presentMessage('toast', '权限保存失败，请稍后重试。');
    }
  }

  private refreshCertificate(): void {
    const context = this.resolveApplicationContext();
    this.sessionState.certificate = this.certificateService.buildLoadingState();
    this.publishApplicationSnapshot();
    const certificateContext: SiteCertificatePresentationRuntimeContext = {
      controllerAttached: context.controllerAttached,
      secureCurrentSite: isSecureCurrentSiteUrl(context.currentUrl, context.addressInput),
      currentSiteHost: resolveCurrentSiteHost(context.currentUrl, context.addressInput)
    };
    void this.certificateService.resolveCurrentStateFromLifecyclePort(this.runtimeLifecyclePort, certificateContext)
      .then((state: SiteCertificatePresentationState) => {
        this.sessionState.certificate = state;
        this.publishApplicationSnapshot();
      });
  }

  private refreshCurrentSiteData(): void {
    const context = this.resolveApplicationContext();
    const currentUrl = this.resolveContextPageUrl(context);
    const currentSiteOrigin = this.resolveCurrentSiteOrigin(context);
    this.sessionState.data.loading = true;
    this.publishApplicationSnapshot();
    if (currentUrl.length === 0 || currentSiteOrigin.length === 0) {
      this.sessionState.data = this.createEmptyDataState(false);
      this.publishApplicationSnapshot();
      return;
    }
    void this.siteDataControlService.loadCurrentSiteData(
      currentUrl, currentSiteOrigin, context.profileId, context.privacyMode, context.dataScope
    ).then((summary: CurrentSiteDataSummary) => {
      this.sessionState.data = this.buildDataState(summary);
      this.publishApplicationSnapshot();
    }).catch((error: Error) => {
      this.sessionState.data = this.createEmptyDataState(false);
      this.publishApplicationSnapshot();
      this.applicationShell.presentMessage('error', `读取站点数据失败：${JSON.stringify(error)}`);
    });
  }

  private refreshGuardianDays(): void {
    this.guardianDays = this.securityReportMetricsRepository.getGuardianDays();
    this.publishApplicationSnapshot();
    void this.securityReportMetricsRepository.ensureGuardianStarted()
      .then((guardianDays: number) => {
        this.guardianDays = guardianDays;
        this.publishApplicationSnapshot();
      })
      .catch((_error: Error) => {
        this.guardianDays = 0;
        this.publishApplicationSnapshot();
      });
  }

  private presentClearCurrentSiteDataConfirmation(): void {
    const context = this.resolveApplicationContext();
    if (context.dataScope === 'session_ephemeral') {
      this.applicationShell.presentMessage(
        'toast',
        '系统当前不支持按站点清除私密存储，请前往“隐私防护”清除本次私密数据。'
      );
      return;
    }
    if (this.sessionState.data.storageOrigin.length === 0) {
      this.applicationShell.presentMessage('toast', '当前站点没有可按站点清除的本地存储。');
      return;
    }
    this.applicationShell.presentClearSiteDataDialog(
      this.buildClearCurrentSiteDataDialogState(
        context.profileId,
        context.privacyMode,
        context.dataScope
      )
    );
  }

  private clearCurrentSiteData(): void {
    const context = this.resolveApplicationContext();
    const storageOrigin = this.sessionState.data.storageOrigin;
    const result = this.siteDataControlService.clearCurrentSiteData(
      storageOrigin,
      context.profileId,
      context.privacyMode,
      context.dataScope
    );
    if (result.hasError) {
      this.applicationShell.presentMessage('error', result.message);
    }
    this.refreshCurrentSiteData();
    this.reloadActive('site_data_clear_current');
    this.applicationShell.presentMessage(
      'toast',
      result.hasError ? '部分数据清除失败，请稍后重试。' : result.message
    );
  }

  private async toggleCurrentSiteProtection(): Promise<void> {
    const context = this.resolveApplicationContext();
    try {
      const result = await this.adBlockCoordinator.toggleSiteProtection({
        pageUrl: this.resolveContextPageUrl(context),
        capabilitySupported: this.sessionState.protection.capabilitySupported,
        profileId: context.profileId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope
      });
      if (!result.success) {
        this.applicationShell.presentMessage('toast', result.toast);
        return;
      }
      this.sessionState.protection.summary = result.summary;
      this.sessionState.protection.siteEnabled = result.siteEnabled;
      this.closeApplicationSurfaceInternal(false);
      this.reloadActive('site_protection_toggle');
      this.applicationShell.presentMessage('toast', result.toast);
    } catch (_error) {
      this.applicationShell.presentMessage('toast', '本站网页内容过滤保存失败');
    }
  }

  private scheduleTrackingProtectionStatusRefresh(delayMs: number): void {
    this.clearTrackingProtectionStatusTimer();
    this.pendingTrackingRefreshTimer = setTimeout(() => {
      this.pendingTrackingRefreshTimer = -1;
      const context = this.resolveApplicationContext();
      if (context.shouldDeferTrackingRefresh) {
        this.scheduleTrackingProtectionStatusRefresh(context.trackingRefreshDelayMs);
        return;
      }
      this.refreshTrackingProtectionStatus(true);
    }, Math.max(0, delayMs));
  }

  private clearTrackingProtectionStatusTimer(): void {
    if (this.pendingTrackingRefreshTimer < 0) {
      return;
    }
    clearTimeout(this.pendingTrackingRefreshTimer);
    this.pendingTrackingRefreshTimer = -1;
  }

  private buildAdBlockContext(
    context: BrowserSiteControlsApplicationContext
  ): BrowserAdBlockPageRuntimeContext {
    return {
      tabId: context.targetTabId,
      pageUrl: this.resolveContextPageUrl(context),
      capabilitySupported: this.sessionState.protection.capabilitySupported,
      controllerAttached: context.controllerAttached,
      profileId: context.profileId,
      privacyMode: context.privacyMode,
      dataScope: context.dataScope
    };
  }

  private resolveContextPageUrl(context: BrowserSiteControlsApplicationContext): string {
    return resolveCurrentSiteUrl(context.currentUrl, context.addressInput);
  }

  private resolveCurrentSiteOrigin(context: BrowserSiteControlsApplicationContext): string {
    return this.siteInteractionLogicService.resolveOrigin(this.resolveContextPageUrl(context));
  }

  private resolveDetailReturnMode(mode: BrowserSiteInfoSheetMode): BrowserSiteInfoSheetMode {
    return mode === 'security' ? 'security' : 'overview';
  }

  private resolvePermissionRuleMode(kind: SitePermissionKind): BrowserSiteInfoSheetMode {
    if (kind === 'camera') {
      return 'permission_camera';
    }
    if (kind === 'microphone') {
      return 'permission_microphone';
    }
    if (kind === 'location') {
      return 'permission_location';
    }
    if (kind === 'clipboard') {
      return 'permission_clipboard';
    }
    return 'permission_sensor';
  }

  private resolveEffectiveSitePermissionSettings(
    requestOrigin: string,
    currentOrigin: string,
    profileId: BrowserProfileId,
    dataScope: BrowserDataScope
  ): SitePermissionSettings {
    if (currentOrigin.length > 0 &&
      this.siteInteractionLogicService.isSamePermissionSite(currentOrigin, requestOrigin)) {
      return this.sitePolicyService.getEffectiveSitePermissionSettings(currentOrigin, profileId, dataScope);
    }
    return this.sitePolicyService.getEffectiveSitePermissionSettings(requestOrigin, profileId, dataScope);
  }

  private buildDataState(
    summary: CurrentSiteDataSummary
  ): BrowserSiteControlsDataState {
    return {
      loading: false,
      cookieCount: summary.cookieCount,
      storageUsageBytes: summary.storageUsageBytes,
      storageOrigin: summary.storageOrigin
    };
  }

  private createEmptyDataState(loading: boolean): BrowserSiteControlsDataState {
    return {
      loading: loading,
      cookieCount: 0,
      storageUsageBytes: 0,
      storageOrigin: ''
    };
  }

  private copyPermissionDraft(draft: SitePermissionDraftState): SitePermissionDraftState {
    return {
      origin: draft.origin,
      camera: draft.camera,
      microphone: draft.microphone,
      location: draft.location,
      sensor: draft.sensor,
      clipboard: draft.clipboard
    };
  }

  private copySessionState(): BrowserSiteControlsSessionState {
    const snapshot = new BrowserSiteControlsSessionState();
    snapshot.mode = this.sessionState.mode;
    snapshot.returnMode = this.sessionState.returnMode;
    snapshot.navigationDirection = this.sessionState.navigationDirection;
    snapshot.permissionDraft = this.copyPermissionDraft(this.sessionState.permissionDraft);
    snapshot.savedPermissionDraft = this.copyPermissionDraft(this.sessionState.savedPermissionDraft);
    snapshot.relatedOrigins = this.sessionState.relatedOrigins.slice();
    snapshot.data = {
      loading: this.sessionState.data.loading,
      cookieCount: this.sessionState.data.cookieCount,
      storageUsageBytes: this.sessionState.data.storageUsageBytes,
      storageOrigin: this.sessionState.data.storageOrigin
    };
    snapshot.certificate = {
      summary: this.sessionState.certificate.summary,
      detailStatus: this.sessionState.certificate.detailStatus,
      subject: this.sessionState.certificate.subject,
      issuer: this.sessionState.certificate.issuer,
      validFrom: this.sessionState.certificate.validFrom,
      validTo: this.sessionState.certificate.validTo,
      serialNumber: this.sessionState.certificate.serialNumber,
      signatureAlgorithm: this.sessionState.certificate.signatureAlgorithm,
      chainCount: this.sessionState.certificate.chainCount
    };
    snapshot.protection = {
      capabilitySupported: this.sessionState.protection.capabilitySupported,
      availabilityState: this.sessionState.protection.availabilityState,
      summary: this.sessionState.protection.summary,
      siteToggleEnabled: this.sessionState.protection.siteToggleEnabled,
      siteEnabled: this.sessionState.protection.siteEnabled,
      blockedCount: this.sessionState.protection.blockedCount,
      requestBlockingCount: this.sessionState.protection.requestBlockingCount,
      linkCleaningCount: this.sessionState.protection.linkCleaningCount,
      elementHidingCount: this.sessionState.protection.elementHidingCount,
      privacyCoverageState: this.sessionState.protection.privacyCoverageState,
      privacyCoverageSummary: this.sessionState.protection.privacyCoverageSummary
    };
    return snapshot;
  }

  private publishApplicationSnapshot(): void {
    const context = this.resolveApplicationContext();
    const protectionActivity = this.adBlockCoordinator.getProtectionActivitySummary();
    this.applicationSnapshot = {
      session: this.copySessionState(),
      isSecureSite: isSecureCurrentSiteUrl(context.currentUrl, context.addressInput),
      isPrivateMode: context.isPrivateMode,
      connectionTitle: resolveConnectionStatusTitle(context.currentUrl, context.addressInput),
      siteHost: resolveCurrentSiteHost(context.currentUrl, context.addressInput),
      siteDataSummary: this.resolveSiteDataSummary(),
      siteCookieCount: this.sessionState.data.cookieCount,
      canClearCurrentSiteStorage: context.dataScope !== 'session_ephemeral' &&
        this.sessionState.data.storageOrigin.length > 0,
      siteGuardianDays: this.guardianDays,
      certificateChainText: this.resolveCertificateChainText(),
      webProtectionFeedback: this.protectionFeedbackSessionCoordinator.getPresentation(context.activeTabId),
      trackingProtectionEnhanced: BrowserFingerprintPrivacyPolicyService.isEnhancedEnabled(),
      trackingProtectionSummary: BrowserFingerprintPrivacyPolicyService.resolveCurrentSummary(),
      todayProtectionActionCount: protectionActivity.today.totalActionCount,
      sevenDayProtectionActionCount: protectionActivity.lastSevenDays.totalActionCount
    };
    this.applicationShell.publishSnapshot(this.applicationSnapshot);
  }

  private resolveApplicationContext(tabId?: string): BrowserSiteControlsApplicationContext {
    const current = this.tabScopedEventContextCoordinator.resolveCurrentContext();
    const targetTabId = tabId !== undefined && tabId.length > 0 ? tabId : current.activeTabId;
    const target = this.tabScopedEventContextCoordinator.resolveContext(targetTabId);
    const runtimeFacts = this.applicationShell.readRuntimeFacts();
    const missingInactiveTarget = !target.isActiveTab && target.tab === undefined;
    return {
      activeTabId: current.activeTabId,
      targetTabId: targetTabId,
      currentUrl: missingInactiveTarget ? '' : target.currentUrl,
      addressInput: target.addressInput,
      profileId: target.profileId,
      privacyMode: target.privacyMode,
      dataScope: target.dataScope,
      isPrivateMode: target.boundaryPrivate,
      controllerAttached: runtimeFacts.controllerAttached,
      shouldDeferTrackingRefresh: runtimeFacts.shouldDeferTrackingRefresh,
      trackingRefreshDelayMs: runtimeFacts.trackingRefreshDelayMs,
      strengthenAdBlockingForSmoothScroll: runtimeFacts.strengthenAdBlockingForSmoothScroll
    };
  }

  private notifySessionChanged(): void {
    this.publishApplicationSnapshot();
  }

}
