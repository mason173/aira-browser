import { BrowserDesktopSiteMode } from '../../services/web/BrowserUserAgentService';
import {
  DEFAULT_BROWSER_PROFILE_ID,
  ExternalNavigationAppOpenPolicy,
  SitePermissionKind,
  SitePermissionRule
} from '../../common/models/BrowserModels';
import { BrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { WebAppInstallRepository } from '../../data/webapps/WebAppInstallRepository';
import { DesktopWebEntryRecord } from '../../data/webapps/WebAppInstallModels';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { SiteCapabilityCatalogService } from '../../services/web/SiteCapabilityCatalogService';
import {
  SiteCustomizationDetailViewState,
  SiteCustomizationManagementViewModel
} from '../sitecustomization/SiteCustomizationManagementViewModel';
import {
  SiteCustomizationManagementCoordinator,
  SiteCustomizationPermissionGroupState,
  SiteJavaScriptPolicy
} from '../sitecustomization/SiteCustomizationManagementCoordinator';
import {
  WebAppPinnedShortcutCoordinator,
  WebAppPinnedShortcutState
} from './WebAppPinnedShortcutCoordinator';
import {
  WebAppSettingsDetailState,
  WebAppSettingsListState,
  WebAppSettingsViewModel
} from './WebAppSettingsViewModel';

export type WebAppSettingsSessionEntryKind =
  'web_apps_root' |
  'web_app_detail' |
  'site_permission' |
  'desktop_site' |
  'invalid';
export type WebAppSettingsSessionStatus = 'ready' | 'loading' | 'error';
export type WebAppSettingsSessionNavigationKind = 'none' | 'permission' | 'desktop_site';
export type WebAppSettingsSessionActionKind =
  'set_default_fullscreen' |
  'set_private_site' |
  'set_preserve_cookies' |
  'set_javascript' |
  'set_external_navigation' |
  'open_permission' |
  'open_desktop_site' |
  'select_permission' |
  'select_desktop_site' |
  'reset_site';

export class WebAppSettingsSessionEntry {
  kind: WebAppSettingsSessionEntryKind;
  shortcutId: string;
  host: string;
  origin: string;
  permissionKind: SitePermissionKind;
  boundary: BrowserBoundaryRouteState;

  constructor(
    kind: WebAppSettingsSessionEntryKind,
    shortcutId: string = '',
    host: string = '',
    origin: string = '',
    permissionKind: SitePermissionKind = 'camera',
    boundary: BrowserBoundaryRouteState = { dataScope: '', privacyMode: '', boundarySource: '' }
  ) {
    this.kind = kind;
    this.shortcutId = shortcutId.trim();
    this.host = host.trim();
    this.origin = origin.trim();
    this.permissionKind = permissionKind;
    this.boundary = {
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode,
      boundarySource: boundary.boundarySource
    };
  }
}

export class WebAppSettingsSessionAction {
  kind: WebAppSettingsSessionActionKind;
  enabled: boolean = false;
  permissionKind: SitePermissionKind = 'camera';
  permissionRule: SitePermissionRule = 'ask';
  desktopSiteMode: BrowserDesktopSiteMode = 'default';
  externalNavigationPolicy: ExternalNavigationAppOpenPolicy = 'ask';
  javaScriptPolicy: SiteJavaScriptPolicy = 'default';
  followDefault: boolean = false;

  constructor(kind: WebAppSettingsSessionActionKind) {
    this.kind = kind;
  }
}

export class WebAppSettingsSessionActionResult {
  changed: boolean;
  shouldNavigateBack: boolean;
  navigationKind: WebAppSettingsSessionNavigationKind;
  host: string;
  origin: string;
  permissionKind: SitePermissionKind;

  constructor(
    changed: boolean = false,
    shouldNavigateBack: boolean = false,
    navigationKind: WebAppSettingsSessionNavigationKind = 'none',
    host: string = '',
    origin: string = '',
    permissionKind: SitePermissionKind = 'camera'
  ) {
    this.changed = changed;
    this.shouldNavigateBack = shouldNavigateBack;
    this.navigationKind = navigationKind;
    this.host = host;
    this.origin = origin;
    this.permissionKind = permissionKind;
  }
}

export class WebAppSettingsSessionSnapshot {
  entryKind: WebAppSettingsSessionEntryKind;
  status: WebAppSettingsSessionStatus;
  errorMessage: string;
  listState: WebAppSettingsListState;
  detailState: WebAppSettingsDetailState;
  siteState: SiteCustomizationDetailViewState;
  permissionTitle: string;
  permissionGroup: SiteCustomizationPermissionGroupState;
  desktopSiteMode: BrowserDesktopSiteMode;
  operationBusy: boolean;
  siteRenderVersion: number;

  constructor(
    entryKind: WebAppSettingsSessionEntryKind,
    status: WebAppSettingsSessionStatus,
    errorMessage: string,
    listState: WebAppSettingsListState,
    detailState: WebAppSettingsDetailState,
    siteState: SiteCustomizationDetailViewState,
    permissionTitle: string,
    permissionGroup: SiteCustomizationPermissionGroupState,
    desktopSiteMode: BrowserDesktopSiteMode,
    operationBusy: boolean,
    siteRenderVersion: number
  ) {
    this.entryKind = entryKind;
    this.status = status;
    this.errorMessage = errorMessage;
    this.listState = listState;
    this.detailState = detailState;
    this.siteState = siteState;
    this.permissionTitle = permissionTitle;
    this.permissionGroup = permissionGroup;
    this.desktopSiteMode = desktopSiteMode;
    this.operationBusy = operationBusy;
    this.siteRenderVersion = siteRenderVersion;
  }
}

export type WebAppSettingsSessionObserver = (snapshot: WebAppSettingsSessionSnapshot) => void;

class WebAppSettingsSessionObserverRecord {
  key: string;
  listener: WebAppSettingsSessionObserver | undefined;

  constructor(key: string, listener: WebAppSettingsSessionObserver) {
    this.key = key;
    this.listener = listener;
  }
}

export class WebAppSettingsSessionCoordinator {
  private repository: WebAppInstallRepository;
  private pinnedShortcutCoordinator: WebAppPinnedShortcutCoordinator;
  private siteCoordinator: SiteCustomizationManagementCoordinator;
  private serviceModeGate: AppServiceModeGateService;
  private viewModel: WebAppSettingsViewModel = new WebAppSettingsViewModel();
  private siteViewModel: SiteCustomizationManagementViewModel = new SiteCustomizationManagementViewModel();
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();
  private activeEntry: WebAppSettingsSessionEntry = new WebAppSettingsSessionEntry('invalid');
  private currentStatus: WebAppSettingsSessionStatus = 'ready';
  private errorMessage: string = '';
  private listState: WebAppSettingsListState;
  private detailState: WebAppSettingsDetailState;
  private siteState: SiteCustomizationDetailViewState;
  private permissionTitle: string = '网站权限';
  private permissionGroup: SiteCustomizationPermissionGroupState;
  private desktopSiteMode: BrowserDesktopSiteMode = 'default';
  private operationBusy: boolean = false;
  private siteRenderVersion: number = 0;
  private requestSerial: number = 0;
  private observerSerial: number = 0;
  private observers: WebAppSettingsSessionObserverRecord[] = [];
  private currentSnapshot: WebAppSettingsSessionSnapshot;

  constructor(
    repository: WebAppInstallRepository,
    pinnedShortcutCoordinator: WebAppPinnedShortcutCoordinator,
    siteCoordinator: SiteCustomizationManagementCoordinator,
    serviceModeGate: AppServiceModeGateService
  ) {
    this.repository = repository;
    this.pinnedShortcutCoordinator = pinnedShortcutCoordinator;
    this.siteCoordinator = siteCoordinator;
    this.serviceModeGate = serviceModeGate;
    this.listState = this.viewModel.buildListState([]);
    this.detailState = this.viewModel.buildDetailState(undefined);
    this.siteState = this.buildEmptySiteState();
    this.permissionGroup = this.buildFallbackPermissionGroup('camera');
    this.currentSnapshot = this.buildSnapshot();
  }

  snapshot(): WebAppSettingsSessionSnapshot {
    return this.currentSnapshot;
  }

  observe(listener: WebAppSettingsSessionObserver): string {
    this.observerSerial += 1;
    const key = `web-app-settings-session-${this.observerSerial}`;
    this.observers.push(new WebAppSettingsSessionObserverRecord(key, listener));
    return key;
  }

  unobserve(key: string): void {
    for (let index = 0; index < this.observers.length; index += 1) {
      const record = this.observers[index];
      if (record.key === key) {
        record.listener = undefined;
        return;
      }
    }
  }

  activate(entry: WebAppSettingsSessionEntry): void {
    this.requestSerial += 1;
    const serial = this.requestSerial;
    this.activeEntry = entry;
    this.operationBusy = false;
    this.errorMessage = '';
    if (!this.isValidEntry(entry)) {
      this.currentStatus = 'error';
      this.errorMessage = '这个设置页面暂时无法打开';
      this.publish();
      return;
    }
    if (entry.kind === 'web_apps_root') {
      this.currentStatus = 'loading';
      this.publish();
      void this.loadList(serial);
      return;
    }
    if (entry.kind === 'web_app_detail') {
      this.currentStatus = 'loading';
      this.publish();
      void this.loadDetail(serial);
      return;
    }
    try {
      if (entry.kind === 'site_permission') {
        const permission = this.buildPermissionSnapshot(entry);
        this.permissionTitle = permission.title;
        this.permissionGroup = permission.group;
      } else if (entry.kind === 'desktop_site') {
        this.desktopSiteMode = this.resolveDesktopSiteMode(entry.host, entry.origin);
      }
      this.currentStatus = 'ready';
      this.publish();
    } catch (_error) {
      this.currentStatus = 'error';
      this.errorMessage = '读取网页应用设置失败';
      this.publish();
    }
  }

  async action(action: WebAppSettingsSessionAction): Promise<WebAppSettingsSessionActionResult> {
    if (this.operationBusy || this.currentStatus === 'error') {
      return new WebAppSettingsSessionActionResult();
    }
    if (action.kind === 'open_permission') {
      return this.resolvePermissionNavigation(action.permissionKind);
    }
    if (action.kind === 'open_desktop_site') {
      return this.resolveDesktopSiteNavigation();
    }
    if (action.kind === 'select_permission') {
      return this.applyPermissionRule(action.permissionRule);
    }
    if (action.kind === 'select_desktop_site') {
      return this.applyDesktopSiteMode(action.desktopSiteMode);
    }
    if (this.activeEntry.kind !== 'web_app_detail' || !this.detailState.exists) {
      return new WebAppSettingsSessionActionResult();
    }
    if (action.kind === 'set_default_fullscreen') {
      return this.runDetailMutation(async (): Promise<void> => {
        await this.repository.updateSettings(this.activeEntry.shortcutId, {
          defaultFullscreen: action.enabled
        });
      });
    }
    if (!this.detailState.canOpenSiteSettings) {
      return new WebAppSettingsSessionActionResult();
    }
    if ((action.kind === 'set_private_site' ||
      action.kind === 'set_preserve_cookies') && !this.serviceModeGate.canUseOptionalService()) {
      return new WebAppSettingsSessionActionResult(false, true);
    }
    return this.runSiteDetailMutation(action);
  }

  private async loadList(serial: number): Promise<void> {
    const nextState = await this.queryListState();
    if (!this.isCurrent(serial, 'web_apps_root')) {
      return;
    }
    this.listState = nextState;
    this.currentStatus = 'ready';
    this.publish();
  }

  private async loadDetail(serial: number): Promise<void> {
    const nextDetail = await this.queryDetailState(this.activeEntry.shortcutId, this.activeEntry.boundary);
    if (!this.isCurrent(serial, 'web_app_detail')) {
      return;
    }
    this.detailState = nextDetail.webAppState;
    this.siteState = nextDetail.siteState;
    this.currentStatus = 'ready';
    this.publish();
  }

  private async queryListState(): Promise<WebAppSettingsListState> {
    try {
      const result: [DesktopWebEntryRecord[], WebAppPinnedShortcutState] = await Promise.all([
        this.repository.getAll(),
        this.pinnedShortcutCoordinator.queryPinnedShortcutState()
      ]);
      return this.viewModel.buildListState(result[0], result[1].shortcutIds, result[1].isTrusted);
    } catch (_error) {
      try {
        return this.viewModel.buildListState(await this.repository.getAll());
      } catch (_fallbackError) {
        return this.viewModel.buildListState([]);
      }
    }
  }

  private async queryDetailState(
    shortcutId: string,
    boundary: BrowserBoundaryRouteState
  ): Promise<WebAppSettingsSessionDetailSnapshot> {
    try {
      const record = await this.repository.findByShortcutId(shortcutId);
      return this.buildDetailSnapshot(this.viewModel.buildDetailState(record, shortcutId), boundary);
    } catch (_error) {
      return this.buildDetailSnapshot(this.viewModel.buildDetailState(undefined, shortcutId), boundary);
    }
  }

  private async runSiteDetailMutation(
    action: WebAppSettingsSessionAction
  ): Promise<WebAppSettingsSessionActionResult> {
    const state = this.detailState;
    if (action.kind === 'set_private_site') {
      return this.runDetailMutation(async (): Promise<void> => {
        await this.siteCoordinator.setPrivateSiteMode(
          state.siteHost,
          state.siteOrigin,
          action.enabled ? 'clear_on_close' : 'default',
          DEFAULT_BROWSER_PROFILE_ID
        );
      });
    }
    if (action.kind === 'set_preserve_cookies') {
      return this.runDetailMutation(async (): Promise<void> => {
        await this.siteCoordinator.setPrivateSitePreserveCookies(
          state.siteHost,
          state.siteOrigin,
          action.enabled,
          DEFAULT_BROWSER_PROFILE_ID
        );
      });
    }
    if (action.kind === 'set_external_navigation') {
      return this.runDetailMutation(async (): Promise<void> => {
        if (action.followDefault) {
          await this.siteCoordinator.resetExternalNavigationPolicy(
            state.siteHost,
            state.siteOrigin,
            DEFAULT_BROWSER_PROFILE_ID
          );
        } else {
          await this.siteCoordinator.updateExternalNavigationPolicy(
            state.siteHost,
            state.siteOrigin,
            action.externalNavigationPolicy,
            DEFAULT_BROWSER_PROFILE_ID
          );
        }
      });
    }
    if (action.kind === 'set_javascript') {
      return this.runDetailMutation(async (): Promise<void> => {
        const result = await this.siteCoordinator.setJavaScriptPolicy(
          state.siteHost,
          state.siteOrigin,
          action.javaScriptPolicy,
          DEFAULT_BROWSER_PROFILE_ID,
          this.activeEntry.boundary.dataScope,
          this.activeEntry.boundary.privacyMode
        );
        if (result.status === 'conflict' || result.status === 'invalid') {
          throw new Error('site JavaScript commit failed');
        }
      });
    }
    if (action.kind === 'reset_site') {
      return this.runDetailMutation(async (): Promise<void> => {
        await this.siteCoordinator.resetSiteCustomizations(
          state.siteHost,
          state.siteOrigin,
          DEFAULT_BROWSER_PROFILE_ID,
          this.activeEntry.boundary.dataScope,
          this.activeEntry.boundary.privacyMode
        );
      });
    }
    return new WebAppSettingsSessionActionResult();
  }

  private async runDetailMutation(task: () => Promise<void>): Promise<WebAppSettingsSessionActionResult> {
    const serial = this.requestSerial;
    const shortcutId = this.activeEntry.shortcutId;
    const boundary = this.activeEntry.boundary;
    this.operationBusy = true;
    this.publish();
    try {
      await task();
      const nextDetail = await this.queryDetailState(shortcutId, boundary);
      if (this.isCurrent(serial, 'web_app_detail')) {
        this.detailState = nextDetail.webAppState;
        this.siteState = nextDetail.siteState;
        this.operationBusy = false;
        this.currentStatus = 'ready';
        this.errorMessage = '';
        this.siteRenderVersion += 1;
        this.publish();
      }
      return new WebAppSettingsSessionActionResult(true);
    } catch (_error) {
      this.publishMutationFailure(serial, 'web_app_detail');
      return new WebAppSettingsSessionActionResult();
    }
  }

  private resolvePermissionNavigation(kind: SitePermissionKind): WebAppSettingsSessionActionResult {
    if (this.activeEntry.kind !== 'web_app_detail' || !this.detailState.canOpenSiteSettings) {
      return new WebAppSettingsSessionActionResult();
    }
    if (!this.serviceModeGate.canUseOptionalService()) {
      return new WebAppSettingsSessionActionResult(false, true);
    }
    return new WebAppSettingsSessionActionResult(
      false,
      false,
      'permission',
      this.detailState.siteHost,
      this.detailState.siteOrigin,
      kind
    );
  }

  private resolveDesktopSiteNavigation(): WebAppSettingsSessionActionResult {
    if (this.activeEntry.kind !== 'web_app_detail' || !this.detailState.canOpenSiteSettings) {
      return new WebAppSettingsSessionActionResult();
    }
    if (!this.serviceModeGate.canUseOptionalService()) {
      return new WebAppSettingsSessionActionResult(false, true);
    }
    return new WebAppSettingsSessionActionResult(
      false,
      false,
      'desktop_site',
      this.detailState.siteHost,
      this.detailState.siteOrigin
    );
  }

  private async applyPermissionRule(rule: SitePermissionRule): Promise<WebAppSettingsSessionActionResult> {
    if (this.activeEntry.kind !== 'site_permission') {
      return new WebAppSettingsSessionActionResult();
    }
    if (rule === this.permissionGroup.selectedRule) {
      return new WebAppSettingsSessionActionResult(false, true);
    }
    const serial = this.requestSerial;
    const entry = this.activeEntry;
    this.operationBusy = true;
    this.publish();
    try {
      await this.siteCoordinator.updatePermissionRule(
        entry.host,
        entry.origin,
        entry.permissionKind,
        rule,
        DEFAULT_BROWSER_PROFILE_ID,
        entry.boundary.dataScope,
        entry.boundary.privacyMode
      );
      if (this.isCurrent(serial, 'site_permission')) {
        const permission = this.buildPermissionSnapshot(entry);
        this.permissionTitle = permission.title;
        this.permissionGroup = permission.group;
        this.operationBusy = false;
        this.publish();
        return new WebAppSettingsSessionActionResult(true, true);
      }
      return new WebAppSettingsSessionActionResult(true);
    } catch (_error) {
      this.publishMutationFailure(serial, 'site_permission');
      return new WebAppSettingsSessionActionResult();
    }
  }

  private async applyDesktopSiteMode(
    mode: BrowserDesktopSiteMode
  ): Promise<WebAppSettingsSessionActionResult> {
    if (this.activeEntry.kind !== 'desktop_site') {
      return new WebAppSettingsSessionActionResult();
    }
    if (mode === this.desktopSiteMode) {
      return new WebAppSettingsSessionActionResult(false, true);
    }
    const serial = this.requestSerial;
    const entry = this.activeEntry;
    this.operationBusy = true;
    this.publish();
    try {
      const result = await this.siteCoordinator.setSiteUserAgentMode(
        entry.host,
        entry.origin,
        mode,
        DEFAULT_BROWSER_PROFILE_ID
      );
      if (result.status === 'conflict' || result.status === 'invalid') {
        throw new Error('site user-agent commit failed');
      }
      if (this.isCurrent(serial, 'desktop_site')) {
        this.desktopSiteMode = mode;
        this.operationBusy = false;
        this.publish();
        return new WebAppSettingsSessionActionResult(true, true);
      }
      return new WebAppSettingsSessionActionResult(true);
    } catch (_error) {
      this.publishMutationFailure(serial, 'desktop_site');
      return new WebAppSettingsSessionActionResult();
    }
  }

  private buildPermissionSnapshot(entry: WebAppSettingsSessionEntry): WebAppSettingsPermissionSnapshot {
    const siteState = this.siteViewModel.buildDetailState(
      this.siteCoordinator.buildDetailState(
        entry.host,
        entry.origin,
        DEFAULT_BROWSER_PROFILE_ID,
        entry.boundary.dataScope,
        entry.boundary.privacyMode
      )
    );
    const matchedGroup = siteState.permissionGroups.find((group: SiteCustomizationPermissionGroupState) => {
      return group.kind === entry.permissionKind;
    });
    const group = matchedGroup === undefined
      ? this.buildFallbackPermissionGroup(entry.permissionKind)
      : matchedGroup;
    return new WebAppSettingsPermissionSnapshot(`${group.title}权限`, group);
  }

  private resolveDesktopSiteMode(host: string, origin: string): BrowserDesktopSiteMode {
    return this.siteCoordinator.resolveSiteUserAgentMode(host, origin, DEFAULT_BROWSER_PROFILE_ID);
  }

  private buildDetailSnapshot(
    webAppState: WebAppSettingsDetailState,
    boundary: BrowserBoundaryRouteState
  ): WebAppSettingsSessionDetailSnapshot {
    const siteState = this.siteViewModel.buildDetailState(
      this.siteCoordinator.buildDetailState(
        webAppState.canOpenSiteSettings ? webAppState.siteHost : '',
        webAppState.canOpenSiteSettings ? webAppState.siteOrigin : '',
        DEFAULT_BROWSER_PROFILE_ID,
        boundary.dataScope,
        boundary.privacyMode
      )
    );
    return new WebAppSettingsSessionDetailSnapshot(webAppState, siteState);
  }

  private buildFallbackPermissionGroup(kind: SitePermissionKind): SiteCustomizationPermissionGroupState {
    return {
      kind: kind,
      title: this.capabilityCatalog.getPermissionTitle(kind),
      selectedRule: 'ask',
      options: this.capabilityCatalog.buildDefaultPermissionOptions()
    };
  }

  private buildEmptySiteState(): SiteCustomizationDetailViewState {
    return {
      host: '',
      origin: '',
      title: '',
      summary: '',
      externalNavigationPolicy: 'ask',
      hasExternalNavigationRule: false,
      desktopSiteSummary: '跟随全局',
      hasDesktopSiteRule: false,
      privateSiteEnabled: false,
      preserveCookiesOnClose: false,
      hasPrivateSiteRule: false,
      javaScriptPolicy: 'default',
      hasJavaScriptRule: false,
      javaScriptCanApply: true,
      permissionGroups: [],
      hasAnyRules: false,
      resetEnabled: false,
      hasUnreadableEntry: false
    };
  }

  private isValidEntry(entry: WebAppSettingsSessionEntry): boolean {
    if (entry.kind === 'web_apps_root') {
      return true;
    }
    if (entry.kind === 'web_app_detail') {
      return entry.shortcutId.length > 0;
    }
    if (entry.kind === 'site_permission' || entry.kind === 'desktop_site') {
      return entry.host.length > 0 && entry.origin.length > 0;
    }
    return false;
  }

  private isCurrent(serial: number, kind: WebAppSettingsSessionEntryKind): boolean {
    return serial === this.requestSerial && this.activeEntry.kind === kind;
  }

  private publishMutationFailure(serial: number, kind: WebAppSettingsSessionEntryKind): void {
    if (!this.isCurrent(serial, kind)) {
      return;
    }
    this.operationBusy = false;
    this.currentStatus = 'error';
    this.errorMessage = '保存网页应用设置失败，请重试';
    this.publish();
  }

  private buildSnapshot(): WebAppSettingsSessionSnapshot {
    return new WebAppSettingsSessionSnapshot(
      this.activeEntry.kind,
      this.currentStatus,
      this.errorMessage,
      this.listState,
      this.detailState,
      this.siteState,
      this.permissionTitle,
      this.permissionGroup,
      this.desktopSiteMode,
      this.operationBusy,
      this.siteRenderVersion
    );
  }

  private publish(): void {
    this.currentSnapshot = this.buildSnapshot();
    for (let index = 0; index < this.observers.length; index += 1) {
      const listener = this.observers[index].listener;
      if (listener !== undefined) {
        listener(this.currentSnapshot);
      }
    }
  }
}

class WebAppSettingsSessionDetailSnapshot {
  webAppState: WebAppSettingsDetailState;
  siteState: SiteCustomizationDetailViewState;

  constructor(webAppState: WebAppSettingsDetailState, siteState: SiteCustomizationDetailViewState) {
    this.webAppState = webAppState;
    this.siteState = siteState;
  }
}

class WebAppSettingsPermissionSnapshot {
  title: string;
  group: SiteCustomizationPermissionGroupState;

  constructor(title: string, group: SiteCustomizationPermissionGroupState) {
    this.title = title;
    this.group = group;
  }
}
