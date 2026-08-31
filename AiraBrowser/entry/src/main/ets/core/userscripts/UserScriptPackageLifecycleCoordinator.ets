import { AIRA_FEATURE_USERSCRIPT_INSTALL } from '../../common/constants/MembershipFeatureKeys';
import { EntitlementDecision } from '../../common/models/MembershipModels';
import { UserScriptRepository } from '../../data/userscripts/UserScriptRepository';
import { UserScriptRuntimeStateRepository } from '../../data/userscripts/UserScriptRuntimeStateRepository';
import { UserScriptValueStateStore } from '../../data/userscripts/UserScriptValueStateStore';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import {
  cloneUserScriptPackageCandidate,
  createInstalledUserScriptState,
  InstalledUserScriptState,
  markInstalledUserScriptChecked,
  replaceInstalledUserScriptPackage,
  resolveUserScriptPackageSource,
  setInstalledUserScriptEnabled,
  UserScriptInstallSource,
  UserScriptMaterializedDependencies,
  UserScriptPackageSource,
  UserScriptMetadataParseResult,
  UserScriptPackageCandidate
} from '../../features/userscripts/UserScriptMetadataModels';
import { EntitlementContext } from '../../services/membership/EntitlementService';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import {
  UserScriptBackupDependencyValidationResult,
  UserScriptDependencyFetchResult,
  UserScriptDependencyFetchService
} from '../../services/userscripts/UserScriptDependencyFetchService';
import { UserScriptIdentityService } from '../../services/userscripts/UserScriptIdentityService';
import { UserScriptMetadataParserService } from '../../services/userscripts/UserScriptMetadataParserService';
import {
  UserScriptSourceFetchResult,
  UserScriptSourceFetchService
} from '../../services/userscripts/UserScriptSourceFetchService';
import {
  UserScriptUpdatePackageResult,
  UserScriptUpdateResult,
  UserScriptUpdateService
} from '../../services/userscripts/UserScriptUpdateService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface UserScriptPackageSourceInput {
  source: string;
  installSource: UserScriptPackageSource;
  sourceUrl: string;
  existingScriptId: string;
}

export interface UserScriptBackupRestoreState {
  source: string;
  sourceUrl: string;
  installSource: UserScriptInstallSource;
  enabled: boolean;
  dependencies: UserScriptMaterializedDependencies;
}

export interface UserScriptPackageDuplicateInfo {
  scriptId: string;
  scriptName: string;
}

export interface UserScriptPackageReadyPreviewResult {
  status: 'ready';
  candidate: UserScriptPackageCandidate;
  warnings: string[];
}

export interface UserScriptPackageDuplicatePreviewResult {
  status: 'duplicate';
  candidate: UserScriptPackageCandidate;
  warnings: string[];
  duplicate: UserScriptPackageDuplicateInfo;
}

export interface UserScriptPackageFailedPreviewResult {
  status: 'failed';
  warnings: string[];
  errorMessage: string;
}

export type UserScriptPackagePreviewResult =
  UserScriptPackageReadyPreviewResult |
  UserScriptPackageDuplicatePreviewResult |
  UserScriptPackageFailedPreviewResult;

export interface UserScriptPackageSuccessResult {
  status: 'installed' | 'updated';
  scriptId: string;
  scriptName: string;
  warnings: string[];
}

export interface UserScriptPackageDuplicateResult {
  status: 'duplicate';
  warnings: string[];
  duplicate: UserScriptPackageDuplicateInfo;
}

export interface UserScriptPackageDeniedResult {
  status: 'denied';
  scriptId: string;
  scriptName: string;
  warnings: string[];
  errorMessage: string;
  entitlementDecision: EntitlementDecision;
}

export interface UserScriptPackageFailureResult {
  status: 'failed';
  warnings: string[];
  errorMessage: string;
}

export type UserScriptPackageCommitResult =
  UserScriptPackageSuccessResult |
  UserScriptPackageDeniedResult |
  UserScriptPackageFailureResult;

export type UserScriptPackageMutationResult =
  UserScriptPackageCommitResult |
  UserScriptPackageDuplicateResult;

export class UserScriptPackageLifecycleCoordinator {
  private repository: UserScriptRepository;
  private valueStore: UserScriptValueStateStore;
  private runtimeStateRepository?: UserScriptRuntimeStateRepository;
  private membershipFeature: MembershipFeature;
  private sourceFetchService: UserScriptSourceFetchService;
  private parser: UserScriptMetadataParserService;
  private dependencyFetchService: UserScriptDependencyFetchService;
  private identityService: UserScriptIdentityService;
  private updateService: UserScriptUpdateService;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    repository: UserScriptRepository,
    valueStore: UserScriptValueStateStore,
    runtimeStateRepository: UserScriptRuntimeStateRepository | undefined,
    membershipFeature: MembershipFeature,
    sourceFetchService: UserScriptSourceFetchService = new UserScriptSourceFetchService(),
    parser: UserScriptMetadataParserService = new UserScriptMetadataParserService(),
    dependencyFetchService: UserScriptDependencyFetchService = new UserScriptDependencyFetchService(sourceFetchService),
    identityService: UserScriptIdentityService = new UserScriptIdentityService(),
    updateService: UserScriptUpdateService = new UserScriptUpdateService(
      sourceFetchService,
      parser
    ),
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.valueStore = valueStore;
    this.runtimeStateRepository = runtimeStateRepository;
    this.membershipFeature = membershipFeature;
    this.sourceFetchService = sourceFetchService;
    this.parser = parser;
    this.dependencyFetchService = dependencyFetchService;
    this.identityService = identityService;
    this.updateService = updateService;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  findInstalledScript(scriptId: string): InstalledUserScriptState | undefined {
    return this.repository.findScript(scriptId.trim());
  }

  async restoreBackupState(
    state: UserScriptBackupRestoreState,
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ): Promise<UserScriptPackageCommitResult> {
    this.ensureCanWriteDevicePreference(entitlementContext);
    const installSource = resolveUserScriptPackageSource(state.installSource, state.sourceUrl);
    const parsed = this.parser.parse(state.source, installSource, state.sourceUrl);
    if (!parsed.valid || parsed.candidate === undefined) {
      return this.fail(this.resolveParseError(parsed, '备份中的脚本格式不正确。'), parsed.warnings);
    }
    const candidate = parsed.candidate;
    const existing = this.identityService.findDuplicateScript(candidate, this.repository.listScripts());
    if (existing === undefined) {
      const decision = await this.membershipFeature.canUse(
        AIRA_FEATURE_USERSCRIPT_INSTALL,
        this.buildEntitlementContext(entitlementContext)
      );
      if (!decision.allowed) {
        return this.denied(decision, candidate, parsed.warnings);
      }
    }
    const dependencies: UserScriptMaterializedDependencies = {
      requireSources: Array.isArray(state.dependencies.requireSources)
        ? state.dependencies.requireSources.slice()
        : [],
      resources: Array.isArray(state.dependencies.resources) ? state.dependencies.resources.slice() : []
    };
    const dependencyValidation: UserScriptBackupDependencyValidationResult =
      this.dependencyFetchService.validateBackupDependencies(candidate, dependencies);
    if (!dependencyValidation.valid) {
      return this.fail(dependencyValidation.errorMessage, parsed.warnings);
    }
    const restoredAt = Date.now();
    let nextState = existing === undefined
      ? this.createUniqueBackupInstalledState(candidate, dependencyValidation.dependencies, restoredAt)
      : replaceInstalledUserScriptPackage(
        candidate,
        dependencyValidation.dependencies,
        existing,
        existing.lastCheckedAt,
        restoredAt
      );
    const shouldEnable = state.enabled === true;
    nextState = setInstalledUserScriptEnabled(nextState, shouldEnable, restoredAt);
    await this.repository.saveInstalledState(nextState);
    await this.runtimeStateRepository?.deleteScriptState(nextState.id);
    if (existing === undefined) {
      await this.membershipFeature.recordUsage(AIRA_FEATURE_USERSCRIPT_INSTALL);
    }
    return {
      status: existing === undefined ? 'installed' : 'updated',
      scriptId: nextState.id,
      scriptName: nextState.name,
      warnings: parsed.warnings.slice()
    };
  }

  previewSource(input: UserScriptPackageSourceInput): UserScriptPackagePreviewResult {
    const parsed = this.parser.parse(
      input.source,
      input.installSource,
      input.sourceUrl
    );
    if (!parsed.valid || parsed.candidate === undefined) {
      return this.buildPreviewFailure(parsed);
    }
    const duplicate = this.findInteractiveDuplicate(parsed.candidate, input.existingScriptId);
    return this.buildPreviewSuccess(parsed, duplicate);
  }

  async saveInteractiveSource(
    input: UserScriptPackageSourceInput,
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ): Promise<UserScriptPackageMutationResult> {
    const preview = this.previewSource(input);
    switch (preview.status) {
      case 'failed':
        return this.fail(preview.errorMessage, preview.warnings);
      case 'duplicate':
        return this.duplicate(preview);
      case 'ready': {
        const existingScriptId = input.existingScriptId.trim();
        const existing = existingScriptId.length > 0 ? this.repository.findScript(existingScriptId) : undefined;
        if (existingScriptId.length > 0 && existing === undefined) {
          return this.fail('脚本不存在，无法保存。', preview.warnings);
        }
        return this.commitCandidate(preview.candidate, existing, entitlementContext, preview.warnings, 0);
      }
    }
  }

  async installFromUrl(
    url: string,
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ): Promise<UserScriptPackageCommitResult> {
    const normalizedUrl = url.trim();
    const fetchResult: UserScriptSourceFetchResult = await this.sourceFetchService.fetchSource(normalizedUrl);
    if (!fetchResult.ok) {
      return this.fail(fetchResult.errorMessage);
    }
    const parsed = this.parser.parse(fetchResult.source, 'url', normalizedUrl);
    if (!parsed.valid || parsed.candidate === undefined) {
      return this.fail(this.resolveParseError(parsed, '脚本格式不正确。'), parsed.warnings);
    }
    const existing = this.findDirectInstallReplacement(parsed.candidate);
    return this.commitCandidate(parsed.candidate, existing, entitlementContext, parsed.warnings, 0);
  }

  canCheckUpdates(scriptId: string): boolean {
    const script = this.repository.findScript(scriptId.trim());
    return script !== undefined && this.updateService.canCheckUpdates(script);
  }

  async checkScriptUpdate(
    scriptId: string,
    checkedAt: number = Date.now(),
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ): Promise<UserScriptUpdateResult> {
    if (!this.canWriteDevicePreference(entitlementContext)) {
      return this.buildPolicyDeniedUpdateResult(scriptId, checkedAt);
    }
    const script = this.repository.findScript(scriptId.trim());
    if (script === undefined) {
      return this.buildMissingUpdateResult(scriptId, checkedAt);
    }
    const result = await this.updateService.checkScript(script, checkedAt);
    if (result.status !== 'unsupported') {
      await this.markScriptChecked(script, result.checkedAt);
    }
    return result;
  }

  async updateScript(
    scriptId: string,
    checkedAt: number = Date.now(),
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ): Promise<UserScriptUpdateResult> {
    if (!this.canWriteDevicePreference(entitlementContext)) {
      return this.buildPolicyDeniedUpdateResult(scriptId, checkedAt);
    }
    const script = this.repository.findScript(scriptId.trim());
    if (script === undefined) {
      return this.buildMissingUpdateResult(scriptId, checkedAt);
    }
    const result: UserScriptUpdatePackageResult = await this.updateService.updateScript(script, checkedAt);
    if (result.candidate !== undefined) {
      const candidate = this.preserveRemoteUpdateUrls(result.candidate, script);
      const materialized: UserScriptDependencyFetchResult = await this.dependencyFetchService.materialize(candidate);
      const updatedState = replaceInstalledUserScriptPackage(
        candidate,
        materialized.dependencies,
        script,
        result.checkedAt,
        Date.now()
      );
      await this.repository.saveInstalledState(updatedState);
      await this.runtimeStateRepository?.deleteScriptState(updatedState.id);
      return this.withUpdatedState(result, updatedState, materialized.warnings);
    }
    if (result.status !== 'unsupported') {
      await this.markScriptChecked(script, result.checkedAt);
    }
    return result;
  }

  async setScriptEnabled(
    scriptId: string,
    enabled: boolean,
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ): Promise<void> {
    this.ensureCanWriteDevicePreference(entitlementContext);
    const state = this.repository.findScript(scriptId.trim());
    if (state === undefined) {
      return;
    }
    await this.repository.saveInstalledState(setInstalledUserScriptEnabled(state, enabled, Date.now()));
    if (enabled && !state.enabled) {
      await this.runtimeStateRepository?.deleteScriptState(state.id);
    }
  }

  async deleteScript(
    scriptId: string,
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ): Promise<void> {
    this.ensureCanWriteDevicePreference(entitlementContext);
    const normalizedId = scriptId.trim();
    await this.valueStore.deletePackageValues(normalizedId);
    await this.runtimeStateRepository?.deleteScriptState(normalizedId);
    await this.repository.deleteScript(normalizedId);
  }

  private createUniqueBackupInstalledState(
    candidate: UserScriptPackageCandidate,
    dependencies: UserScriptMaterializedDependencies,
    restoredAt: number
  ): InstalledUserScriptState {
    let uniqueTimestamp = restoredAt;
    let state = createInstalledUserScriptState(candidate, dependencies, uniqueTimestamp);
    while (this.repository.findScript(state.id) !== undefined) {
      uniqueTimestamp += 1;
      state = createInstalledUserScriptState(candidate, dependencies, uniqueTimestamp);
    }
    return state;
  }

  private findInteractiveDuplicate(
    candidate: UserScriptPackageCandidate,
    existingScriptId: string
  ): InstalledUserScriptState | undefined {
    const normalizedExistingId = existingScriptId.trim();
    return this.identityService.findDuplicateScript(
      candidate,
      this.repository.listScripts(),
      normalizedExistingId
    );
  }

  private findDirectInstallReplacement(candidate: UserScriptPackageCandidate): InstalledUserScriptState | undefined {
    const targetName = candidate.name.trim();
    const targetNamespace = candidate.namespace.trim();
    return this.repository.listScripts().find((installed: InstalledUserScriptState): boolean => {
      if (installed.name.trim() !== targetName) {
        return false;
      }
      if (targetNamespace.length > 0 || installed.namespace.trim().length > 0) {
        return installed.namespace.trim() === targetNamespace;
      }
      return true;
    });
  }

  private async commitCandidate(
    candidate: UserScriptPackageCandidate,
    existing: InstalledUserScriptState | undefined,
    entitlementContext: EntitlementContext,
    warnings: string[],
    checkedAt: number
  ): Promise<UserScriptPackageCommitResult> {
    if (!this.canWriteDevicePreference(entitlementContext)) {
      return this.fail('当前会话不可修改用户脚本配置。', warnings);
    }
    if (existing === undefined) {
      const decision = await this.membershipFeature.canUse(
        AIRA_FEATURE_USERSCRIPT_INSTALL,
        this.buildEntitlementContext(entitlementContext)
      );
      if (!decision.allowed) {
        return this.denied(decision, candidate, warnings);
      }
    }
    const materialized: UserScriptDependencyFetchResult = await this.dependencyFetchService.materialize(candidate);
    const committedAt = Date.now();
    const nextState = existing === undefined ?
      createInstalledUserScriptState(candidate, materialized.dependencies, committedAt) :
      replaceInstalledUserScriptPackage(
        candidate,
        materialized.dependencies,
        existing,
        checkedAt > 0 ? checkedAt : existing.lastCheckedAt,
        committedAt
      );
    await this.repository.saveInstalledState(nextState);
    if (existing !== undefined) {
      await this.runtimeStateRepository?.deleteScriptState(nextState.id);
    }
    if (existing === undefined) {
      await this.membershipFeature.recordUsage(AIRA_FEATURE_USERSCRIPT_INSTALL);
    }
    const status: 'installed' | 'updated' = existing === undefined ? 'installed' : 'updated';
    const combinedWarnings = warnings.concat(materialized.warnings);
    return {
      status: status,
      scriptId: nextState.id,
      scriptName: nextState.name,
      warnings: combinedWarnings
    };
  }

  private preserveRemoteUpdateUrls(
    candidate: UserScriptPackageCandidate,
    installed: InstalledUserScriptState
  ): UserScriptPackageCandidate {
    const resolvedCandidate = cloneUserScriptPackageCandidate(candidate);
    if (resolvedCandidate.updateUrl.length === 0) {
      resolvedCandidate.updateUrl = installed.updateUrl;
    }
    if (resolvedCandidate.downloadUrl.length === 0) {
      resolvedCandidate.downloadUrl = installed.downloadUrl;
    }
    return resolvedCandidate;
  }

  private buildEntitlementContext(context: EntitlementContext): EntitlementContext {
    return {
      dataScope: context.dataScope,
      privacyMode: context.privacyMode,
      loggedIn: context.loggedIn,
      currentUsage: this.repository.listScripts().length
    };
  }

  private ensureCanWriteDevicePreference(context: EntitlementContext): void {
    if (!this.canWriteDevicePreference(context)) {
      throw new Error('当前会话不可修改用户脚本配置。');
    }
  }

  private canWriteDevicePreference(context: EntitlementContext): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: context.dataScope,
        privacyMode: context.privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private buildPolicyDeniedUpdateResult(scriptId: string, checkedAt: number): UserScriptUpdateResult {
    const script = this.repository.findScript(scriptId.trim());
    return {
      scriptId: script?.id ?? scriptId.trim(),
      scriptName: script?.name ?? '用户脚本',
      status: 'failed',
      previousVersion: script?.version ?? '',
      nextVersion: '',
      checkedAt: checkedAt,
      message: '当前会话不可修改用户脚本配置。',
      warnings: []
    };
  }

  private buildPreviewSuccess(
    parsed: UserScriptMetadataParseResult,
    duplicate: InstalledUserScriptState | undefined
  ): UserScriptPackagePreviewResult {
    if (parsed.candidate === undefined) {
      return this.buildPreviewFailure(parsed);
    }
    if (duplicate !== undefined) {
      return {
        status: 'duplicate',
        candidate: parsed.candidate,
        warnings: parsed.warnings,
        duplicate: this.buildDuplicateInfo(duplicate)
      };
    }
    return {
      status: 'ready',
      candidate: parsed.candidate,
      warnings: parsed.warnings
    };
  }

  private buildPreviewFailure(parsed: UserScriptMetadataParseResult): UserScriptPackageFailedPreviewResult {
    return {
      status: 'failed',
      warnings: parsed.warnings,
      errorMessage: this.resolveParseError(parsed, '脚本格式不正确。')
    };
  }

  private duplicate(preview: UserScriptPackageDuplicatePreviewResult): UserScriptPackageDuplicateResult {
    return {
      status: 'duplicate',
      warnings: preview.warnings,
      duplicate: preview.duplicate
    };
  }

  private buildDuplicateInfo(record: InstalledUserScriptState): UserScriptPackageDuplicateInfo {
    return {
      scriptId: record.id,
      scriptName: record.name
    };
  }

  private denied(
    decision: EntitlementDecision,
    candidate: UserScriptPackageCandidate,
    warnings: string[]
  ): UserScriptPackageDeniedResult {
    return {
      status: 'denied',
      scriptId: '',
      scriptName: candidate.name,
      warnings: warnings,
      errorMessage: decision.message,
      entitlementDecision: decision
    };
  }

  private fail(message: string, warnings: string[] = []): UserScriptPackageFailureResult {
    return {
      status: 'failed',
      warnings: warnings,
      errorMessage: message
    };
  }

  private resolveParseError(parsed: UserScriptMetadataParseResult, fallback: string): string {
    return parsed.errorMessage.length > 0 ? parsed.errorMessage : fallback;
  }

  private buildMissingUpdateResult(scriptId: string, checkedAt: number): UserScriptUpdateResult {
    return {
      scriptId: scriptId,
      scriptName: '',
      status: 'failed',
      previousVersion: '',
      nextVersion: '',
      checkedAt: checkedAt,
      message: '脚本不存在。',
      warnings: []
    };
  }

  private withUpdatedState(
    result: UserScriptUpdatePackageResult,
    state: InstalledUserScriptState,
    materializationWarnings: string[]
  ): UserScriptUpdateResult {
    return {
      scriptId: result.scriptId,
      scriptName: state.name,
      status: result.status,
      previousVersion: result.previousVersion,
      nextVersion: state.version,
      checkedAt: result.checkedAt,
      message: result.message,
      warnings: result.warnings.concat(materializationWarnings)
    };
  }

  private async markScriptChecked(state: InstalledUserScriptState, checkedAt: number): Promise<void> {
    await this.repository.saveInstalledState(markInstalledUserScriptChecked(state, checkedAt));
  }
}
