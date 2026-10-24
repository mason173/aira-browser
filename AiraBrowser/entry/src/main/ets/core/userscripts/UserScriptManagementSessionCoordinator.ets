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
import { resolveAppResourceText } from '../resources/AppResourceText';

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
    title: resolveAppResourceText($r('app.string.user_script_risk_title')),
    intro: resolveAppResourceText($r('app.string.user_script_risk_intro')),
    riskItems: [
      resolveAppResourceText($r('app.string.user_script_risk_item_source')),
      resolveAppResourceText($r('app.string.user_script_risk_item_data')),
      resolveAppResourceText($r('app.string.user_script_risk_item_network')),
      resolveAppResourceText($r('app.string.user_script_risk_item_experimental')),
      resolveAppResourceText($r('app.string.user_script_risk_item_disable'))
    ],
    confirmation: resolveAppResourceText($r('app.string.user_script_risk_confirmation')),
    primaryActionLabel: resolveAppResourceText($r('app.string.user_script_risk_accept')),
    secondaryActionLabel: resolveAppResourceText($r('app.string.user_script_risk_decline'))
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
  private activationSerial: number = 0;
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
    this.activationSerial += 1;
    const serial = this.activationSerial;
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
    this.publish();
    void this.initializeManagementState(serial);
  }

  private async initializeManagementState(serial: number): Promise<void> {
    // Disabled startup leaves installed packages and their GM state unloaded. Show the
    // package list as soon as metadata is ready; recovery/diagnostics must not hide it.
    const readiness: boolean[] = await Promise.all([
      this.packageLifecycle.initializeMetadata().then((): boolean => true).catch((): boolean => false),
      this.riskConsentRepository.initialize().then((): boolean => true).catch((): boolean => false)
    ]);
    if (!this.isCurrentActivation(serial)) {
      return;
    }
    if (!this.riskConsentRepository.hasAcceptedCurrentVersion()) {
      this.activeSheet = 'riskConsent';
    } else if (this.activeSheet === 'riskConsent') {
      this.activeSheet = 'none';
    }
    const metadataReady = readiness[0];
    this.publish(metadataReady && readiness[1] ? [] : [UserScriptManagementEffect.message(
      resolveAppResourceText($r('app.string.user_script_read_failed'))
    )]);
    if (!metadataReady) {
      return;
    }
    await Promise.all([
      this.valueStore.initialize().then((): void => {}).catch((): void => {}),
      this.runtimeStateRepository.initialize().then((): void => {}).catch((): void => {}),
      this.noticeRepository.initialize().then((): void => {}).catch((): void => {})
    ]);
    if (!this.isCurrentActivation(serial)) {
      return;
    }
    this.publish();
    if (readiness[1]) {
      void this.runAutomaticUpdateCheck();
    }
  }

  private isCurrentActivation(serial: number): boolean {
    return this.facts.visible && serial === this.activationSerial;
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
      this.publish([UserScriptManagementEffect.message(resolveAppResourceText($r('app.string.user_script_session_readonly')))]);
      return;
    }
    try {
      await this.riskConsentRepository.acceptCurrentVersion();
      this.activeSheet = 'none';
      this.publish([UserScriptManagementEffect.settingsChanged()]);
    } catch (_error) {
      this.publish([UserScriptManagementEffect.message(resolveAppResourceText($r('app.string.user_script_consent_save_failed')))]);
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
      this.publish([UserScriptManagementEffect.message(resolveAppResourceText($r('app.string.user_script_session_readonly')))]);
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
      this.publish([UserScriptManagementEffect.message(resolveAppResourceText($r('app.string.user_script_export_not_allowed')))]);
      return;
    }
    const script = this.packageLifecycle.findInstalledScript(scriptId);
    if (script === undefined) {
      this.publish([UserScriptManagementEffect.message(resolveAppResourceText($r('app.string.user_script_export_missing_script')))]);
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
      this.updateResults = [this.buildFailedUpdateCheckResult(scriptId, resolveAppResourceText($r('app.string.user_script_update_check_failed')))];
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
      this.updateResults = [this.buildFailedUpdateCheckResult('', resolveAppResourceText($r('app.string.user_script_update_check_failed')))];
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
        failedResults.push(this.buildFailedUpdateCheckResult(scriptIds[index], resolveAppResourceText($r('app.string.user_script_update_failed'))));
      }
    }
    this.updateBusy = false;
    this.updateInstalling = false;
    this.updateResults = failedResults;
    this.activeSheet = failedResults.length > 0 ? 'updateCheck' : 'none';
    const effects: UserScriptManagementEffect[] = [];
    if (updatedCount > 0) {
      effects.push(UserScriptManagementEffect.settingsChanged());
      effects.push(UserScriptManagementEffect.message(
        resolveAppResourceText($r('app.string.user_script_updated_count'), updatedCount)
      ));
    } else if (failedResults.length > 0) {
      effects.push(UserScriptManagementEffect.message(resolveAppResourceText($r('app.string.user_script_update_failed'))));
    }
    this.publish(effects);
  }

  private async setAutoUpdate(enabled: boolean): Promise<void> {
    if (!this.canWriteDevicePreference()) {
      this.publish([UserScriptManagementEffect.message(resolveAppResourceText($r('app.string.user_script_session_readonly')))]);
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
        this.publish([UserScriptManagementEffect.message(resolveAppResourceText($r('app.string.user_script_auto_update_save_failed')))]);
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
        this.publish([UserScriptManagementEffect.message(
          resolveAppResourceText($r('app.string.user_script_updates_found'), summary.availableCount)
        )]);
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
      scriptName: script?.name ?? resolveAppResourceText($r('app.string.user_script_update_check_title')),
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
