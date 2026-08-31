import { TabRecord } from '../../common/models/BrowserModels';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AiraMembershipState } from '../../common/models/MembershipModels';
import { AIRA_FEATURE_CROSS_DEVICE_TABS } from '../../common/constants/MembershipFeatureKeys';
import {
  sharedCrossDeviceTabPresencePreferencesRepository,
  CrossDeviceTabPresencePreferencesRepository
} from '../../data/deviceTabs/CrossDeviceTabPresencePreferencesRepository';
import {
  CrossDeviceTabPresenceApiError,
  CrossDeviceTabPresenceApiService
} from '../../services/deviceTabs/CrossDeviceTabPresenceApiService';
import {
  HuaweiAccountSyncAuthService,
  HuaweiAccountSyncIdentity
} from '../../services/sync/HuaweiAccountSyncAuthService';
import {
  BrowserWindowSessionLifetimeListener,
  sharedBrowserWindowSessionLifetimeSignal
} from '../browser/BrowserWindowSessionLifetimeSignal';
import { FeatureGateCoordinator } from '../membership/FeatureGateCoordinator';
import {
  CrossDeviceTabPresenceDevice,
  CrossDeviceTabPresenceLocalDevice,
  CrossDeviceTabPresencePanelAccessDecision,
  CrossDeviceTabPresencePanelState,
  CrossDeviceTabPresencePanelStatus,
  CrossDeviceTabPresenceTab
} from './CrossDeviceTabPresenceModels';

const PUBLISH_DEBOUNCE_MS: number = 750;
const HEARTBEAT_INTERVAL_MS: number = 60000;
const MAX_PUBLISHED_TABS: number = 100;

export class CrossDeviceTabPresenceEntryHost {
  private readonly openTabsSheetAction: () => void;
  private readonly openProAction: () => void;
  private readonly showUnavailableAction: (title: string, message: string) => void;

  constructor(
    openTabsSheetAction: () => void,
    openProAction: () => void,
    showUnavailableAction: (title: string, message: string) => void
  ) {
    this.openTabsSheetAction = openTabsSheetAction;
    this.openProAction = openProAction;
    this.showUnavailableAction = showUnavailableAction;
  }

  openTabsSheet(): void {
    this.openTabsSheetAction();
  }

  openPro(): void {
    this.openProAction();
  }

  showUnavailable(title: string, message: string): void {
    this.showUnavailableAction(title, message);
  }
}

export class CrossDeviceTabPresenceCoordinator {
  private readonly preferencesRepository: CrossDeviceTabPresencePreferencesRepository;
  private readonly apiService: CrossDeviceTabPresenceApiService;
  private readonly authService: HuaweiAccountSyncAuthService;
  private readonly tabsByWindowId: Record<string, CrossDeviceTabPresenceTab[] | undefined> = {};
  private readonly foregroundByWindowId: Record<string, boolean | undefined> = {};
  private readonly lifetimeListeners: Record<string, BrowserWindowSessionLifetimeListener | undefined> = {};
  private readonly windowOrder: string[] = [];
  private publishTimer: number = -1;
  private heartbeatTimer: number = -1;
  private publishPromise?: Promise<void>;
  private entitlementBlocked: boolean = false;
  private panelOpening: boolean = false;

  constructor(
    preferencesRepository?: CrossDeviceTabPresencePreferencesRepository,
    apiService?: CrossDeviceTabPresenceApiService,
    authService?: HuaweiAccountSyncAuthService
  ) {
    this.preferencesRepository = preferencesRepository ?? sharedCrossDeviceTabPresencePreferencesRepository;
    this.apiService = apiService ?? new CrossDeviceTabPresenceApiService();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  reconcileWindowRecords(windowId: string, records: TabRecord[]): void {
    const normalizedWindowId = windowId.trim();
    if (normalizedWindowId.length === 0) {
      return;
    }
    if (!this.windowOrder.includes(normalizedWindowId)) {
      this.windowOrder.push(normalizedWindowId);
    }
    this.tabsByWindowId[normalizedWindowId] = this.projectRecords(records);
    this.ensureWindowLifetimeSubscription(normalizedWindowId);
    if (this.hasForegroundWindow()) {
      this.schedulePublish();
    }
  }

  async loadPanelState(): Promise<CrossDeviceTabPresencePanelState> {
    const device = await this.preferencesRepository.readLocalDevice();
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return this.buildPanelState(
        'disabled',
        false,
        device.deviceName,
        [],
        AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud')
      );
    }
    const identity = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      return this.buildPanelState('signed_out', false, device.deviceName, [], '请先使用华为账号登录。');
    }
    const enabled = await this.preferencesRepository.isEnabled(identity.uid);
    if (!enabled) {
      return this.buildPanelState('disabled', false, device.deviceName, [], '');
    }
    try {
      const result = await this.apiService.list(identity.uid, device.deviceId);
      return {
        status: 'ready',
        enabled: true,
        deviceName: device.deviceName,
        devices: result.devices,
        message: '',
        serverTime: result.serverTime,
        onlineWindowMs: result.onlineWindowMs
      };
    } catch (error) {
      return this.buildPanelState('error', true, device.deviceName, [], this.resolveErrorMessage(error));
    }
  }

  async requestPanelAccess(
    featureGateCoordinator: FeatureGateCoordinator
  ): Promise<CrossDeviceTabPresencePanelAccessDecision> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return {
        allowed: false,
        title: '当前发行版不支持跨设备标签页',
        message: AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud'),
        openPro: false
      };
    }
    const decision = await featureGateCoordinator.evaluateAccess(
      AIRA_FEATURE_CROSS_DEVICE_TABS,
      {
        dataScope: 'profile_persistent',
        privacyMode: 'regular',
        loggedIn: true
      }
    );
    if (!decision.allowed) {
      const proRequired = decision.reason === 'pro_required';
      return {
        allowed: false,
        title: proRequired ? '跨设备标签页需要 Aira Pro' : decision.title,
        message: proRequired
          ? '查看其他在线电脑当前打开的普通网页，并可在手机上一键打开。升级 Aira Pro 后即可使用。'
          : decision.message,
        openPro: true
      };
    }
    await this.enableCurrentAccountByDefault();
    return {
      allowed: true,
      title: '',
      message: '',
      openPro: false
    };
  }

  requestOpenPanel(
    featureGateCoordinator: FeatureGateCoordinator,
    host: CrossDeviceTabPresenceEntryHost
  ): void {
    if (this.panelOpening) {
      return;
    }
    this.panelOpening = true;
    void this.openPanel(featureGateCoordinator, host);
  }

  async reconcileMembershipState(state: AiraMembershipState): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      this.entitlementBlocked = true;
      this.clearPublishTimer();
      this.stopHeartbeat();
      return;
    }
    const identity = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      this.entitlementBlocked = true;
      this.clearPublishTimer();
      this.stopHeartbeat();
      return;
    }
    const uid = identity.uid.trim();
    const enabledPreference = await this.preferencesRepository.readEnabledPreference(uid);
    if (!this.isActiveProState(state, uid)) {
      this.entitlementBlocked = true;
      this.clearPublishTimer();
      this.stopHeartbeat();
      if (enabledPreference === true) {
        const device = await this.preferencesRepository.readLocalDevice();
        await this.apiService.clear(uid, device.deviceId).catch((_error: Error): void => {
        });
      }
      return;
    }
    this.entitlementBlocked = false;
    if (enabledPreference !== true) {
      await this.preferencesRepository.setEnabled(uid, true);
    }
    if (this.hasForegroundWindow()) {
      this.startHeartbeat();
      this.schedulePublish();
    }
  }

  async clearCurrentAccountSnapshot(): Promise<void> {
    this.clearPublishTimer();
    this.stopHeartbeat();
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return;
    }
    const identity = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      return;
    }
    const device = await this.preferencesRepository.readLocalDevice();
    await this.apiService.clear(identity.uid, device.deviceId);
  }

  private async openPanel(
    featureGateCoordinator: FeatureGateCoordinator,
    host: CrossDeviceTabPresenceEntryHost
  ): Promise<void> {
    try {
      const decision = await this.requestPanelAccess(featureGateCoordinator);
      if (decision.allowed) {
        host.openTabsSheet();
        return;
      }
      if (decision.openPro) {
        host.openPro();
        return;
      }
      host.showUnavailable(decision.title, decision.message);
    } catch (_error) {
      host.showUnavailable(
        '暂时无法打开电脑标签页',
        '跨设备标签页暂时不可用，请稍后重试。'
      );
    } finally {
      this.panelOpening = false;
    }
  }

  private ensureWindowLifetimeSubscription(windowId: string): void {
    let listener = this.lifetimeListeners[windowId];
    if (listener === undefined) {
      listener = (foreground: boolean): void => {
        this.handleWindowLifetimeChanged(windowId, foreground);
      };
      this.lifetimeListeners[windowId] = listener;
    }
    sharedBrowserWindowSessionLifetimeSignal.subscribe(windowId, listener);
  }

  private handleWindowLifetimeChanged(windowId: string, foreground: boolean): void {
    this.foregroundByWindowId[windowId] = foreground;
    if (!this.hasForegroundWindow()) {
      this.clearPublishTimer();
      this.stopHeartbeat();
      return;
    }
    this.startHeartbeat();
    this.schedulePublish();
  }

  private hasForegroundWindow(): boolean {
    return Object.keys(this.foregroundByWindowId).some((windowId: string): boolean => {
      return this.foregroundByWindowId[windowId] === true;
    });
  }

  private schedulePublish(): void {
    if (this.entitlementBlocked) {
      return;
    }
    this.clearPublishTimer();
    this.publishTimer = setTimeout((): void => {
      this.publishTimer = -1;
      void this.publishNow().catch((_error: Error): void => {
      });
    }, PUBLISH_DEBOUNCE_MS);
  }

  private clearPublishTimer(): void {
    if (this.publishTimer < 0) {
      return;
    }
    clearTimeout(this.publishTimer);
    this.publishTimer = -1;
  }

  private startHeartbeat(): void {
    if (this.heartbeatTimer >= 0 || !this.hasForegroundWindow() || this.entitlementBlocked) {
      return;
    }
    this.heartbeatTimer = setInterval((): void => {
      void this.publishNow().catch((_error: Error): void => {
      });
    }, HEARTBEAT_INTERVAL_MS);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer < 0) {
      return;
    }
    clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = -1;
  }

  private async publishNow(): Promise<void> {
    if (this.publishPromise !== undefined) {
      return this.publishPromise;
    }
    this.publishPromise = this.publishCurrentSnapshot();
    try {
      await this.publishPromise;
    } finally {
      this.publishPromise = undefined;
    }
  }

  private async publishCurrentSnapshot(): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') ||
      !this.hasForegroundWindow() || this.entitlementBlocked) {
      return;
    }
    const identity: HuaweiAccountSyncIdentity | undefined = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      this.stopHeartbeat();
      return;
    }
    if (!await this.preferencesRepository.isEnabled(identity.uid)) {
      this.stopHeartbeat();
      return;
    }
    const device: CrossDeviceTabPresenceLocalDevice = await this.preferencesRepository.readLocalDevice();
    try {
      await this.apiService.publish(identity.uid, device, this.collectPublishedTabs());
    } catch (error) {
      const detail = error as Error;
      if (this.isProRequired(detail)) {
        this.entitlementBlocked = true;
        this.stopHeartbeat();
      }
      throw detail;
    }
  }

  private collectPublishedTabs(): CrossDeviceTabPresenceTab[] {
    const result: CrossDeviceTabPresenceTab[] = [];
    this.windowOrder.forEach((windowId: string, windowOrder: number): void => {
      const tabs = this.tabsByWindowId[windowId] ?? [];
      tabs.forEach((tab: CrossDeviceTabPresenceTab): void => {
        if (result.length >= MAX_PUBLISHED_TABS) {
          return;
        }
        result.push({
          title: tab.title,
          url: tab.url,
          active: tab.active,
          lastActiveAt: tab.lastActiveAt,
          windowOrder: windowOrder,
          tabOrder: tab.tabOrder
        });
      });
    });
    return result;
  }

  private projectRecords(records: TabRecord[]): CrossDeviceTabPresenceTab[] {
    const result: CrossDeviceTabPresenceTab[] = [];
    records.forEach((record: TabRecord, index: number): void => {
      if (result.length >= MAX_PUBLISHED_TABS || record.isHome === true || record.privacyMode === 'private' ||
        record.dataScope === 'session_ephemeral' || record.runtimeState === 'error') {
        return;
      }
      const url = this.normalizeHttpUrl(record.url);
      if (url.length === 0) {
        return;
      }
      result.push({
        title: record.title.trim().slice(0, 512),
        url: url,
        active: record.isActive === true,
        lastActiveAt: this.normalizeTimestamp(record.lastActiveAt),
        windowOrder: 0,
        tabOrder: this.normalizeOrder(record.tabOrder, index)
      });
    });
    return result;
  }

  private normalizeHttpUrl(value: string): string {
    const url = value.trim();
    const lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return '';
    }
    const authorityStart = url.indexOf('://') + 3;
    let authorityEnd = url.length;
    const separators: string[] = ['/', '?', '#'];
    separators.forEach((separator: string): void => {
      const index = url.indexOf(separator, authorityStart);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    });
    const authority = url.slice(authorityStart, authorityEnd);
    return authority.length > 0 && !authority.includes('@') ? url : '';
  }

  private normalizeTimestamp(value: number): number {
    return Number.isSafeInteger(value) && value > 0 ? value : 0;
  }

  private normalizeOrder(value: number | undefined, fallback: number): number {
    return value !== undefined && Number.isSafeInteger(value) && value >= 0 ? value : fallback;
  }

  private buildPanelState(
    status: CrossDeviceTabPresencePanelStatus,
    enabled: boolean,
    deviceName: string,
    devices: CrossDeviceTabPresenceDevice[],
    message: string
  ): CrossDeviceTabPresencePanelState {
    return {
      status: status,
      enabled: enabled,
      deviceName: deviceName,
      devices: devices,
      message: message,
      serverTime: Date.now(),
      onlineWindowMs: 120000
    };
  }

  private resolveErrorMessage(error: Object): string {
    const detail = error as Error;
    const message = detail.message?.trim() ?? '';
    return message.length > 0 ? message : '跨设备标签页暂时不可用。';
  }

  private isProRequired(error: Object): boolean {
    const detail = error as CrossDeviceTabPresenceApiError;
    return detail.code === 'pro_required';
  }

  private async enableCurrentAccountByDefault(): Promise<void> {
    const identity = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      return;
    }
    const uid = identity.uid.trim();
    const enabledPreference = await this.preferencesRepository.readEnabledPreference(uid);
    if (enabledPreference !== true) {
      await this.preferencesRepository.setEnabled(uid, true);
    }
    this.entitlementBlocked = false;
    if (this.hasForegroundWindow()) {
      this.startHeartbeat();
      this.schedulePublish();
    }
  }

  private isActiveProState(state: AiraMembershipState, uid: string): boolean {
    return state.userId.trim() === uid && state.plan === 'pro' &&
      (state.planExpiresAt === 0 || state.planExpiresAt > Date.now());
  }
}

export const sharedCrossDeviceTabPresenceCoordinator: CrossDeviceTabPresenceCoordinator =
  new CrossDeviceTabPresenceCoordinator();
