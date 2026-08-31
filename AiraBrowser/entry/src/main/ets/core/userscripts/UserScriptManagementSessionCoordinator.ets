import { SettingsNoticeDismissalRepository, SETTINGS_NOTICE_USER_SCRIPTS } from '../../data/preferences/SettingsNoticeDismissalRepository';
import { UserScriptRepository } from '../../data/userscripts/UserScriptRepository';
import { UserScriptRiskConsentRepository } from '../../data/userscripts/UserScriptRiskConsentRepository';
import { UserScriptRuntimeStateRepository } from '../../data/userscripts/UserScriptRuntimeStateRepository';
import { UserScriptValueStateStore } from '../../data/userscripts/UserScriptValueStateStore';
import {
  InstalledUserScriptState,
  UserScriptExportPayload
} from '../../features/userscripts/UserScriptMetadataModels';
import { EntitlementContext } from '../../services/membership/EntitlementService';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { UserScriptUpdateResult } from '../../services/userscripts/UserScriptUpdateService';
import { UserScriptPackageLifecycleCoordinator } from './UserScriptPackageLifecycleCoordinator';
import { UserScriptDetailState, UserScriptDetailViewModel } from './UserScriptDetailViewModel';
import {
  UserScriptValueRecoveryViewState,
  UserScriptsSettingsState,
  UserScriptsSettingsViewModel
} from './UserScriptsSettingsViewModel';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

const USER_SCRIPT_AUTO_UPDATE_INTERVAL_MS: number = 24 * 60 * 60 * 1000;

export interface UserScriptRiskConsentSheetState {
  title: string;
  intro: string;
  riskItems: string[];
  confirmation: string;
  primaryActionLabel: string;
  secondaryActionLabel: string;
}

function buildUserScriptRiskConsentState(): UserScriptRiskConsentSheetState {
  return {
    title: '使用用户脚本前，请先了解风险',
    intro: '用户脚本会在匹配的网站中运行，可以读取和修改网页内容，也可能向第三方服务发送网络请求。它们能增强网页，也可能带来隐私、安全和稳定性风险。',
    riskItems: [
      '只安装来自可信作者和可信来源的脚本，安装前尽量查看脚本说明、权限和源码。',
      '脚本可能读取页面中的账号信息、表单内容、网页文本或站点数据，并可能改变网页行为。',
      '脚本发起的网络请求、依赖资源和第三方服务由脚本作者或服务方控制，Aira 无法保证其安全性、可用性或处理结果。',
      'Aira 的用户脚本能力仍处于实验阶段，目前主要兼容常见用户脚本接口，不保证所有脚本、油猴 API、网站环境或桌面浏览器扩展能力都完整可用。',
      '如果脚本导致网页异常、性能下降、登录状态变化、翻译或其他网页服务不可用，请停用或删除相关脚本。'
    ],
    confirmation: '继续使用表示你理解上述风险，并愿意自行判断脚本来源和使用后果。',
    primaryActionLabel: '我已了解并继续',
    secondaryActionLabel: '暂不使用'
  };
}

export type UserScriptManagementSheet = 'none' | 'riskConsent' | 'updateCheck';
export type UserScriptManagementActionKind =
  'accept_risk_consent' |
  'decline_risk_consent' |
  'sheet_dismissed' |
  'dismiss_notice' |
  'toggle_script' |
  'request_delete_script' |
  'delete_script' |
  'request_export_script' |
  'check_script_update' |
  'check_all_updates' |
  'install_available_updates' |
  'set_auto_update';
export type UserScriptManagementEffectKind =
  'exit' |
  'message' |
  'confirm_delete_script' |
  'export_script' |
  'script_deleted' |
  'settings_changed';

export class UserScriptManagementSurfaceFacts {
  visible: boolean;
  entitlementContext: EntitlementContext;

  constructor(
    visible: boolean,
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ) {
    this.visible = visible;
    this.entitlementContext = {
      dataScope: entitlementContext.dataScope,
      privacyMode: entitlementContext.privacyMode,
      loggedIn: entitlementContext.loggedIn,
      currentUsage: entitlementContext.currentUsage
    };
  }
}

export class UserScriptManagementAction {
  readonly kind: UserScriptManagementActionKind;
  readonly scriptId: string;
  readonly enabled: boolean;
  readonly sheet: UserScriptManagementSheet;
  private readonly actionToken: boolean = true;

  private constructor(
    kind: UserScriptManagementActionKind,
    scriptId: string = '',
    enabled: boolean = false,
    sheet: UserScriptManagementSheet = 'none'
  ) {
    this.kind = kind;
    this.scriptId = scriptId.trim();
    this.enabled = enabled;
    this.sheet = sheet;
  }

  static acceptRiskConsent(): UserScriptManagementAction {
    return new UserScriptManagementAction('accept_risk_consent');
  }

  static declineRiskConsent(): UserScriptManagementAction {
    return new UserScriptManagementAction('decline_risk_consent');
  }

  static sheetDismissed(sheet: UserScriptManagementSheet): UserScriptManagementAction {
    return new UserScriptManagementAction('sheet_dismissed', '', false, sheet);
  }

  static dismissNotice(): UserScriptManagementAction {
    return new UserScriptManagementAction('dismiss_notice');
  }

  static toggleScript(scriptId: string, enabled: boolean): UserScriptManagementAction {
    return new UserScriptManagementAction('toggle_script', scriptId, enabled);
  }

  static requestDeleteScript(scriptId: string): UserScriptManagementAction {
    return new UserScriptManagementAction('request_delete_script', scriptId);
  }

  static deleteScript(scriptId: string): UserScriptManagementAction {
    return new UserScriptManagementAction('delete_script', scriptId);
  }

  static requestExportScript(scriptId: string): UserScriptManagementAction {
    return new UserScriptManagementAction('request_export_script', scriptId);
  }

  static checkScriptUpdate(scriptId: string): UserScriptManagementAction {
    return new UserScriptManagementAction('check_script_update', scriptId);
  }

  static checkAllUpdates(): UserScriptManagementAction {
    return new UserScriptManagementAction('check_all_updates');
  }

  static installAvailableUpdates(): UserScriptManagementAction {
    return new UserScriptManagementAction('install_available_updates');
  }

  static setAutoUpdate(enabled: boolean): UserScriptManagementAction {
    return new UserScriptManagementAction('set_auto_update', '', enabled);
  }
}

export class UserScriptManagementEffect {
  readonly kind: UserScriptManagementEffectKind;
  readonly message: string;
  readonly scriptId: string;
  readonly scriptName: string;
  readonly script?: UserScriptExportPayload;
  private readonly effectToken: boolean = true;

  private constructor(
    kind: UserScriptManagementEffectKind,
    message: string = '',
    scriptId: string = '',
    scriptName: string = '',
    script?: UserScriptExportPayload
  ) {
    this.kind = kind;
    this.message = message;
    this.scriptId = scriptId;
    this.scriptName = scriptName;
    this.script = script;
  }

  static exit(): UserScriptManagementEffect {
    return new UserScriptManagementEffect('exit');
  }

  static message(message: string): UserScriptManagementEffect {
    return new UserScriptManagementEffect('message', message);
  }

  static confirmDeleteScript(scriptId: string, scriptName: string): UserScriptManagementEffect {
    return new UserScriptManagementEffect('confirm_delete_script', '', scriptId, scriptName);
  }

  static exportScript(script: InstalledUserScriptState): UserScriptManagementEffect {
    return new UserScriptManagementEffect('export_script', '', '', '', {
      name: script.name,
      source: script.source
    });
  }

  static scriptDeleted(scriptId: string): UserScriptManagementEffect {
    return new UserScriptManagementEffect('script_deleted', '', scriptId);
  }

  static settingsChanged(): UserScriptManagementEffect {
    return new UserScriptManagementEffect('settings_changed');
  }
}

export class UserScriptManagementSnapshot {
  settings: UserScriptsSettingsState;
  riskConsent: UserScriptRiskConsentSheetState;
  activeSheet: UserScriptManagementSheet;
  updateChecking: boolean;
  updateInstalling: boolean;
  updateResults: UserScriptUpdateResult[];
  showNotice: boolean;
  valueRecovery: UserScriptValueRecoveryViewState;

  constructor(
    settings: UserScriptsSettingsState,
    riskConsent: UserScriptRiskConsentSheetState,
    activeSheet: UserScriptManagementSheet,
    updateChecking: boolean,
    updateInstalling: boolean,
    updateResults: UserScriptUpdateResult[],
    showNotice: boolean,
    valueRecovery: UserScriptValueRecoveryViewState
  ) {
    this.settings = settings;
    this.riskConsent = riskConsent;
    this.activeSheet = activeSheet;
    this.updateChecking = updateChecking;
    this.updateInstalling = updateInstalling;
    this.updateResults = updateResults.slice();
    this.showNotice = showNotice;
    this.valueRecovery = valueRecovery;
  }
}

export class UserScriptManagementTransition {
  snapshot: UserScriptManagementSnapshot;
  effects: UserScriptManagementEffect[];

  constructor(snapshot: UserScriptManagementSnapshot, effects: UserScriptManagementEffect[] = []) {
    this.snapshot = snapshot;
    this.effects = effects.slice();
  }
}

export type UserScriptManagementObserver = (transition: UserScriptManagementTransition) => void;

interface UserScriptBatchUpdateCheckSummary {
  checkedCount: number;
  availableCount: number;
  results: UserScriptUpdateResult[];
}

export class UserScriptManagementSessionCoordinator {
  private repository: UserScriptRepository;
  private runtimeStateRepository: UserScriptRuntimeStateRepository;
  private valueStore: UserScriptValueStateStore;
  private riskConsentRepository: UserScriptRiskConsentRepository;
  private noticeRepository: SettingsNoticeDismissalRepository;
  private packageLifecycle: UserScriptPackageLifecycleCoordinator;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private settingsViewModel: UserScriptsSettingsViewModel = new UserScriptsSettingsViewModel();
  private detailViewModel: UserScriptDetailViewModel = new UserScriptDetailViewModel();
  private facts: UserScriptManagementSurfaceFacts = new UserScriptManagementSurfaceFacts(false);
  private observer?: UserScriptManagementObserver;
  private activeSheet: UserScriptManagementSheet = 'none';
  private riskConsentExitHandled: boolean = false;
  private updateBusy: boolean = false;
  private updateChecking: boolean = false;
  private updateInstalling: boolean = false;
  private updateResults: UserScriptUpdateResult[] = [];
  private automaticCheckBusy: boolean = false;
  private autoUpdatePreferenceSerial: number = 0;
  private currentSnapshot: UserScriptManagementSnapshot;

  constructor(
    repository: UserScriptRepository,
    runtimeStateRepository: UserScriptRuntimeStateRepository,
    valueStore: UserScriptValueStateStore,
    riskConsentRepository: UserScriptRiskConsentRepository,
    noticeRepository: SettingsNoticeDismissalRepository,
    packageLifecycle: UserScriptPackageLifecycleCoordinator,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.runtimeStateRepository = runtimeStateRepository;
    this.valueStore = valueStore;
    this.riskConsentRepository = riskConsentRepository;
    this.noticeRepository = noticeRepository;
    this.packageLifecycle = packageLifecycle;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
    this.currentSnapshot = this.buildSnapshot();
  }

  snapshot(): UserScriptManagementSnapshot {
    return this.currentSnapshot;
  }

  detailSnapshot(scriptId: string): UserScriptDetailState {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length === 0) {
      return this.detailViewModel.buildState(undefined, undefined, []);
    }
    return this.detailViewModel.buildState(
      this.packageLifecycle.findInstalledScript(normalizedScriptId),
      this.runtimeStateRepository.findRecord(normalizedScriptId),
      this.valueStore.readScriptManagementProjection(normalizedScriptId).records
    );
  }

  setObserver(observer?: UserScriptManagementObserver): void {
    this.observer = observer;
    if (observer !== undefined) {
      observer(new UserScriptManagementTransition(this.currentSnapshot));
    }
  }

  activate(facts: UserScriptManagementSurfaceFacts): void {
    this.facts = new UserScriptManagementSurfaceFacts(
      facts.visible,
      facts.entitlementContext
    );
    this.riskConsentExitHandled = false;
    if (!this.facts.visible) {
      if (this.activeSheet === 'riskConsent' || this.activeSheet === 'updateCheck') {
        this.activeSheet = 'none';
      }
      this.publish();
      return;
    }
    if (!this.riskConsentRepository.hasAcceptedCurrentVersion()) {
      this.activeSheet = 'riskConsent';
      this.publish();
      return;
    }
    if (this.activeSheet === 'riskConsent') {
      this.activeSheet = 'none';
    }
    this.publish();
    void this.runAutomaticUpdateCheck();
  }

  action(action: UserScriptManagementAction): void {
    switch (action.kind) {
      case 'accept_risk_consent':
        void this.acceptRiskConsent();
        return;
      case 'decline_risk_consent':
        this.declineRiskConsent();
        return;
      case 'sheet_dismissed':
        this.handleSheetDismissed(action.sheet);
        return;
      case 'dismiss_notice':
        void this.dismissNotice();
        return;
      case 'toggle_script':
        void this.toggleScript(action.scriptId, action.enabled);
        return;
      case 'request_delete_script':
        this.requestDeleteScript(action.scriptId);
        return;
      case 'delete_script':
        void this.deleteScript(action.scriptId);
        return;
      case 'request_export_script':
        this.requestExportScript(action.scriptId);
        return;
      case 'check_script_update':
        this.checkScriptUpdate(action.scriptId);
        return;
      case 'check_all_updates':
        this.checkAllUpdates();
        return;
      case 'install_available_updates':
        this.installAvailableUpdates();
        return;
      case 'set_auto_update':
        void this.setAutoUpdate(action.enabled);
        return;
    }
  }

  private async acceptRiskConsent(): Promise<void> {
    if (!this.canWriteDevicePreference()) {
      this.publish([UserScriptManagementEffect.message('当前会话不可修改用户脚本配置。')]);
      return;
    }
    try {
      await this.riskConsentRepository.acceptCurrentVersion();
      this.activeSheet = 'none';
      this.publish([UserScriptManagementEffect.settingsChanged()]);
    } catch (_error) {
      this.publish([UserScriptManagementEffect.message('暂时无法保存确认，请稍后再试。')]);
    }
  }

  private declineRiskConsent(): void {
    this.riskConsentExitHandled = true;
    this.activeSheet = 'none';
    this.publish([UserScriptManagementEffect.exit()]);
  }

  private handleSheetDismissed(sheet: UserScriptManagementSheet): void {
    if (sheet === 'none' || this.activeSheet !== sheet) {
      return;
    }
    this.activeSheet = 'none';
    if (sheet === 'riskConsent' &&
      !this.riskConsentRepository.hasAcceptedCurrentVersion() &&
      !this.riskConsentExitHandled) {
      this.riskConsentExitHandled = true;
      this.publish([UserScriptManagementEffect.exit()]);
      return;
    }
    this.publish();
  }

  private async dismissNotice(): Promise<void> {
    if (!this.canWriteDevicePreference()) {
      this.publish([UserScriptManagementEffect.message('当前会话不可修改用户脚本配置。')]);
      return;
    }
    try {
      await this.noticeRepository.dismiss(SETTINGS_NOTICE_USER_SCRIPTS);
      this.publish([UserScriptManagementEffect.settingsChanged()]);
    } catch (_error) {
      this.publish();
    }
  }

  private async toggleScript(scriptId: string, enabled: boolean): Promise<void> {
    if (scriptId.length === 0) {
      return;
    }
    try {
      await this.packageLifecycle.setScriptEnabled(scriptId, enabled, this.facts.entitlementContext);
      this.publish([UserScriptManagementEffect.settingsChanged()]);
    } catch (_error) {
      this.publish();
    }
  }

  private requestDeleteScript(scriptId: string): void {
    const script = this.packageLifecycle.findInstalledScript(scriptId);
    if (script === undefined) {
      return;
    }
    this.publish([UserScriptManagementEffect.confirmDeleteScript(script.id, script.name)]);
  }

  private async deleteScript(scriptId: string): Promise<void> {
    if (scriptId.length === 0) {
      return;
    }
    try {
      await this.packageLifecycle.deleteScript(scriptId, this.facts.entitlementContext);
      this.publish([
        UserScriptManagementEffect.settingsChanged(),
        UserScriptManagementEffect.scriptDeleted(scriptId)
      ]);
    } catch (_error) {
      this.publish();
    }
  }

  private requestExportScript(scriptId: string): void {
    if (!this.canExportScript()) {
      this.publish([UserScriptManagementEffect.message('当前会话不可导出用户脚本。')]);
      return;
    }
    const script = this.packageLifecycle.findInstalledScript(scriptId);
    if (script === undefined) {
      this.publish([UserScriptManagementEffect.message('脚本不存在，无法导出。')]);
      return;
    }
    this.publish([UserScriptManagementEffect.exportScript(script)]);
  }

  private checkScriptUpdate(scriptId: string): void {
    if (this.updateBusy) {
      this.activeSheet = 'updateCheck';
      this.publish();
      return;
    }
    this.updateBusy = true;
    this.updateChecking = true;
    this.updateInstalling = false;
    this.updateResults = [];
    this.activeSheet = 'updateCheck';
    this.publish();
    void this.runScriptUpdateCheck(scriptId);
  }

  private async runScriptUpdateCheck(scriptId: string): Promise<void> {
    try {
      const result = await this.packageLifecycle.checkScriptUpdate(
        scriptId,
        Date.now(),
        this.facts.entitlementContext
      );
      this.updateResults = [result];
    } catch (_error) {
      this.updateResults = [this.buildFailedUpdateCheckResult(scriptId, '脚本更新检查失败。')];
    }
    this.updateBusy = false;
    this.updateChecking = false;
    this.publish();
  }

  private checkAllUpdates(): void {
    if (this.updateBusy) {
      this.activeSheet = 'updateCheck';
      this.publish();
      return;
    }
    this.updateBusy = true;
    this.updateChecking = true;
    this.updateInstalling = false;
    this.updateResults = [];
    this.activeSheet = 'updateCheck';
    this.publish();
    void this.runAllUpdateChecks();
  }

  private async runAllUpdateChecks(): Promise<void> {
    try {
      const summary = await this.checkAllScriptUpdates(false);
      this.updateResults = summary.results;
    } catch (_error) {
      this.updateResults = [this.buildFailedUpdateCheckResult('', '脚本更新检查失败。')];
    }
    this.updateBusy = false;
    this.updateChecking = false;
    this.publish();
  }

  private installAvailableUpdates(): void {
    if (this.updateBusy || this.updateChecking || this.updateInstalling) {
      return;
    }
    const scriptIds = this.updateResults
      .filter((result: UserScriptUpdateResult): boolean => result.status === 'available')
      .map((result: UserScriptUpdateResult): string => result.scriptId);
    if (scriptIds.length <= 0) {
      return;
    }
    this.updateBusy = true;
    this.updateInstalling = true;
    this.publish();
    void this.runAvailableUpdates(scriptIds);
  }

  private async runAvailableUpdates(scriptIds: string[]): Promise<void> {
    let updatedCount = 0;
    const failedResults: UserScriptUpdateResult[] = this.updateResults.filter(
      (result: UserScriptUpdateResult): boolean => result.status === 'failed'
    );
    for (let index = 0; index < scriptIds.length; index += 1) {
      try {
        const result: UserScriptUpdateResult = await this.packageLifecycle.updateScript(
          scriptIds[index],
          Date.now(),
          this.facts.entitlementContext
        );
        if (result.status === 'updated') {
          updatedCount += 1;
        } else if (result.status === 'failed') {
          failedResults.push(result);
        }
      } catch (_error) {
        failedResults.push(this.buildFailedUpdateCheckResult(scriptIds[index], '脚本更新失败。'));
      }
    }
    this.updateBusy = false;
    this.updateInstalling = false;
    this.updateResults = failedResults;
    this.activeSheet = failedResults.length > 0 ? 'updateCheck' : 'none';
    const effects: UserScriptManagementEffect[] = [];
    if (updatedCount > 0) {
      effects.push(UserScriptManagementEffect.settingsChanged());
      effects.push(UserScriptManagementEffect.message(`已更新 ${updatedCount} 个脚本。`));
    } else if (failedResults.length > 0) {
      effects.push(UserScriptManagementEffect.message('脚本更新失败。'));
    }
    this.publish(effects);
  }

  private async setAutoUpdate(enabled: boolean): Promise<void> {
    if (!this.canWriteDevicePreference()) {
      this.publish([UserScriptManagementEffect.message('当前会话不可修改用户脚本配置。')]);
      return;
    }
    this.autoUpdatePreferenceSerial += 1;
    const serial = this.autoUpdatePreferenceSerial;
    try {
      await this.repository.setAutoUpdateEnabled(enabled);
      if (serial !== this.autoUpdatePreferenceSerial) {
        return;
      }
      this.publish([UserScriptManagementEffect.settingsChanged()]);
      if (enabled) {
        void this.runAutomaticUpdateCheck();
      }
    } catch (_error) {
      if (serial === this.autoUpdatePreferenceSerial) {
        this.publish([UserScriptManagementEffect.message('自动更新设置保存失败。')]);
      }
    }
  }

  private async runAutomaticUpdateCheck(): Promise<void> {
    if (this.automaticCheckBusy || !this.canRunAutomaticUpdateCheck()) {
      return;
    }
    this.automaticCheckBusy = true;
    try {
      if (!this.canRunAutomaticUpdateCheck()) {
        return;
      }
      const summary = await this.checkAllScriptUpdates(true);
      if (!this.facts.visible || summary.checkedCount <= 0) {
        return;
      }
      if (summary.availableCount > 0) {
        this.publish([UserScriptManagementEffect.message(`发现 ${summary.availableCount} 个脚本有更新。`)]);
      } else {
        this.publish();
      }
    } catch (_error) {
    } finally {
      this.automaticCheckBusy = false;
    }
  }

  private canRunAutomaticUpdateCheck(): boolean {
    return this.facts.visible &&
      this.riskConsentRepository.hasAcceptedCurrentVersion() &&
      this.repository.getSettings().autoUpdateEnabled;
  }

  private async checkAllScriptUpdates(respectAutoInterval: boolean): Promise<UserScriptBatchUpdateCheckSummary> {
    const now = Date.now();
    const scripts = this.repository.listScripts();
    const summary: UserScriptBatchUpdateCheckSummary = {
      checkedCount: 0,
      availableCount: 0,
      results: []
    };
    for (let index = 0; index < scripts.length; index += 1) {
      const script = scripts[index];
      if (!this.shouldCheck(script, now, respectAutoInterval)) {
        continue;
      }
      const result = await this.packageLifecycle.checkScriptUpdate(
        script.id,
        now,
        this.facts.entitlementContext
      );
      summary.checkedCount += 1;
      summary.results.push(result);
      if (result.status === 'available') {
        summary.availableCount += 1;
      }
    }
    return summary;
  }

  private shouldCheck(script: InstalledUserScriptState, now: number, respectAutoInterval: boolean): boolean {
    if (!this.packageLifecycle.canCheckUpdates(script.id)) {
      return false;
    }
    if (!respectAutoInterval) {
      return true;
    }
    return script.lastCheckedAt <= 0 || now - script.lastCheckedAt >= USER_SCRIPT_AUTO_UPDATE_INTERVAL_MS;
  }

  private buildFailedUpdateCheckResult(scriptId: string, message: string): UserScriptUpdateResult {
    const script = scriptId.length > 0 ? this.packageLifecycle.findInstalledScript(scriptId) : undefined;
    return {
      scriptId: scriptId.length > 0 ? scriptId : `failed-${Date.now()}`,
      scriptName: script?.name ?? '脚本更新检查',
      status: 'failed',
      previousVersion: script?.version ?? '',
      nextVersion: '',
      checkedAt: Date.now(),
      message: message,
      warnings: []
    };
  }

  private canWriteDevicePreference(): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: this.facts.entitlementContext.dataScope,
        privacyMode: this.facts.entitlementContext.privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private canExportScript(): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'user_script_export',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: this.facts.entitlementContext.dataScope,
        privacyMode: this.facts.entitlementContext.privacyMode
      }),
      targetScope: 'user_selected_external_location',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private buildSnapshot(): UserScriptManagementSnapshot {
    return new UserScriptManagementSnapshot(
      this.settingsViewModel.buildState(
        this.repository.listScripts(),
        this.repository.getSettings().autoUpdateEnabled
      ),
      buildUserScriptRiskConsentState(),
      this.activeSheet,
      this.updateChecking,
      this.updateInstalling,
      this.updateResults,
      !this.noticeRepository.hasDismissed(SETTINGS_NOTICE_USER_SCRIPTS),
      this.settingsViewModel.buildValueRecoveryState(this.valueStore.readManagementProjection())
    );
  }

  private publish(effects: UserScriptManagementEffect[] = []): void {
    this.currentSnapshot = this.buildSnapshot();
    this.observer?.(new UserScriptManagementTransition(this.currentSnapshot, effects));
  }
}
