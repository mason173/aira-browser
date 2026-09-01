import { TabRecord } from '../../common/models/BrowserModels';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AiraMembershipState } from '../../common/models/MembershipModels';
import {
  AiraPersonalServerConfig,
  AiraSyncSettings
} from '../../common/models/AiraSyncModels';
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
import { AIRA_PERSONAL_SERVER_INSTANCE_SERVICE } from '../../services/sync/AiraPersonalServerInstanceService';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
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

interface CrossDeviceTabPresenceProviderContext {
  kind: 'aira_cloud' | 'self_hosted';
  preferenceScope: string;
  device: CrossDeviceTabPresenceLocalDevice;
  uid: string;
  personalServer?: AiraPersonalServerConfig;
}

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
  private syncConfigStore?: AiraSyncConfigStore;
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

  configureSyncConfigStore(syncConfigStore: AiraSyncConfigStore): void {
    this.syncConfigStore = syncConfigStore;
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
    try {
      const settings = await this.requireSyncConfigStore().initialize();
      const localDevice = await this.preferencesRepository.readLocalDevice();
      if (!this.isSupportedProvider(settings)) {
        return this.buildPanelState(
          'disabled',
          false,
          localDevice.deviceName,
          [],
          this.resolveUnsupportedProviderMessage()
        );
      }
      if (settings.remoteKind === 'aira_cloud' &&
        !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
        return this.buildPanelState(
          'disabled',
          false,
          localDevice.deviceName,
          [],
          AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud')
        );
      }
      const context = await this.resolveProviderContext(settings, localDevice);
      if (context === undefined) {
        return this.buildPanelState('signed_out', false, localDevice.deviceName, [], '请先使用华为账号登录。');
      }
      const enabled = await this.preferencesRepository.isEnabled(context.preferenceScope);
      if (!enabled) {
        return this.buildPanelState('disabled', false, context.device.deviceName, [], '');
      }
      const result = context.kind === 'self_hosted' && context.personalServer !== undefined
        ? await this.apiService.listPersonalServer(
          context.personalServer.baseUrl,
          context.personalServer.deviceToken
        )
        : await this.apiService.list(context.uid, context.device.deviceId);
      return {
        status: 'ready',
        enabled: true,
        deviceName: context.device.deviceName,
        devices: result.devices,
        message: '',
        serverTime: result.serverTime,
        onlineWindowMs: result.onlineWindowMs
      };
    } catch (error) {
      const device = await this.preferencesRepository.readLocalDevice();
      return this.buildPanelState('error', true, device.deviceName, [], this.resolveErrorMessage(error));
    }
  }

  async requestPanelAccess(
    featureGateCoordinator: FeatureGateCoordinator
  ): Promise<CrossDeviceTabPresencePanelAccessDecision> {
    const settings = await this.requireSyncConfigStore().initialize();
    if (settings.remoteKind === 'self_hosted') {
      const localDevice = await this.preferencesRepository.readLocalDevice();
      const context = await this.resolveProviderContext(settings, localDevice);
      if (context === undefined) {
        return {
          allowed: false,
          title: '请先连接个人服务器',
          message: '跨设备标签页需要有效的个人服务器设备凭据。',
          openPro: false
        };
      }
      await this.enableProviderByDefault(context);
      return {
        allowed: true,
        title: '',
        message: '',
        openPro: false
      };
    }
    if (settings.remoteKind !== 'aira_cloud') {
      return {
        allowed: false,
        title: '当前同步服务不支持跨设备标签页',
        message: this.resolveUnsupportedProviderMessage(),
        openPro: false
      };
    }
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
        title: proRequired ? 'Aira 云跨设备标签页需要 Pro' : decision.title,
        message: proRequired
          ? 'Aira 官方托管的跨设备标签页需要 Pro；连接个人服务器后可免费使用。'
          : decision.message,
        openPro: true
      };
    }
    const localDevice = await this.preferencesRepository.readLocalDevice();
    const context = await this.resolveProviderContext(settings, localDevice);
    if (context === undefined) {
      return {
        allowed: false,
        title: '请先登录华为账号',
        message: 'Aira 云同步的跨设备标签页需要华为账号登录。',
        openPro: false
      };
    }
    await this.enableProviderByDefault(context);
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
    const settings = await this.requireSyncConfigStore().initialize();
    if (settings.remoteKind === 'self_hosted') {
      try {
        const localDevice = await this.preferencesRepository.readLocalDevice();
        const context = await this.resolveProviderContext(settings, localDevice);
        if (context === undefined) {
          throw new Error('个人服务器尚未连接。');
        }
        await this.enableProviderByDefault(context);
      } catch (_error) {
        this.entitlementBlocked = true;
        this.clearPublishTimer();
        this.stopHeartbeat();
      }
      return;
    }
    if (settings.remoteKind !== 'aira_cloud' ||
      !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
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
    const settings = await this.requireSyncConfigStore().initialize();
    if (settings.remoteKind !== 'aira_cloud' ||
      !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return;
    }
    this.clearPublishTimer();
    this.stopHeartbeat();
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
    if (!this.hasForegroundWindow()) {
      return;
    }
    const settings = await this.requireSyncConfigStore().initialize();
    if (!this.isSupportedProvider(settings) ||
      (settings.remoteKind === 'aira_cloud' &&
        !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud'))) {
      this.stopHeartbeat();
      return;
    }
    const localDevice = await this.preferencesRepository.readLocalDevice();
    const context = await this.resolveProviderContext(settings, localDevice);
    if (context === undefined) {
      this.stopHeartbeat();
      return;
    }
    if (context.kind === 'aira_cloud' && this.entitlementBlocked) {
      return;
    }
    if (context.kind === 'self_hosted' && this.entitlementBlocked) {
      this.entitlementBlocked = false;
      this.startHeartbeat();
    }
    if (!await this.preferencesRepository.isEnabled(context.preferenceScope)) {
      this.stopHeartbeat();
      return;
    }
    try {
      if (context.kind === 'self_hosted' && context.personalServer !== undefined) {
        await this.apiService.publishPersonalServer(
          context.personalServer.baseUrl,
          context.personalServer.deviceToken,
          context.device,
          this.collectPublishedTabs()
        );
      } else {
        await this.apiService.publish(context.uid, context.device, this.collectPublishedTabs());
      }
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

  private async enableProviderByDefault(context: CrossDeviceTabPresenceProviderContext): Promise<void> {
    const enabledPreference = await this.preferencesRepository.readEnabledPreference(context.preferenceScope);
    if (enabledPreference !== true) {
      await this.preferencesRepository.setEnabled(context.preferenceScope, true);
    }
    this.entitlementBlocked = false;
    if (this.hasForegroundWindow()) {
      this.startHeartbeat();
      this.schedulePublish();
    }
  }

  private requireSyncConfigStore(): AiraSyncConfigStore {
    if (this.syncConfigStore === undefined) {
      throw new Error('同步配置尚未初始化。');
    }
    return this.syncConfigStore;
  }

  private isSupportedProvider(settings: AiraSyncSettings): boolean {
    return settings.remoteKind === 'aira_cloud' || settings.remoteKind === 'self_hosted';
  }

  private async resolveProviderContext(
    settings: AiraSyncSettings,
    localDevice: CrossDeviceTabPresenceLocalDevice
  ): Promise<CrossDeviceTabPresenceProviderContext | undefined> {
    if (settings.remoteKind === 'self_hosted') {
      const config = AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.requireConfigured(settings);
      const pairedDeviceId = settings.sourceId.trim();
      if (pairedDeviceId.length === 0) {
        throw new Error('个人服务器设备标识不可用，请重新连接。');
      }
      return {
        kind: 'self_hosted',
        preferenceScope: `personal-server:${config.instanceId}`,
        device: {
          deviceId: pairedDeviceId,
          deviceName: config.deviceName.trim().length > 0 ? config.deviceName : localDevice.deviceName,
          platform: localDevice.platform,
          model: localDevice.model,
          browserName: localDevice.browserName,
          browserVersion: localDevice.browserVersion
        },
        uid: '',
        personalServer: config
      };
    }
    if (settings.remoteKind !== 'aira_cloud') {
      return undefined;
    }
    const identity: HuaweiAccountSyncIdentity | undefined = await this.authService.getCurrentIdentity();
    if (identity === undefined || identity.uid.trim().length === 0) {
      return undefined;
    }
    const uid = identity.uid.trim();
    return {
      kind: 'aira_cloud',
      preferenceScope: uid,
      device: localDevice,
      uid: uid
    };
  }

  private resolveUnsupportedProviderMessage(): string {
    return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')
      ? '请选择个人服务器或 Aira 云同步后再使用跨设备标签页。'
      : '请选择个人服务器后再使用跨设备标签页。';
  }

  private isActiveProState(state: AiraMembershipState, uid: string): boolean {
    return state.userId.trim() === uid && state.plan === 'pro' &&
      (state.planExpiresAt === 0 || state.planExpiresAt > Date.now());
  }
}

export const sharedCrossDeviceTabPresenceCoordinator: CrossDeviceTabPresenceCoordinator =
  new CrossDeviceTabPresenceCoordinator();
