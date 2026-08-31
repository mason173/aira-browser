import { common } from '@kit.AbilityKit';
import { EntitlementDecision } from '../../common/models/MembershipModels';
import { EntitlementContext } from '../../services/membership/EntitlementService';
import { UserScriptLocalFileService } from '../../services/userscripts/UserScriptLocalFileService';
import {
  UserScriptSourceFetchResult,
  UserScriptSourceFetchService
} from '../../services/userscripts/UserScriptSourceFetchService';
import {
  resolveUserScriptPackageSource,
  UserScriptPackageSource
} from '../../features/userscripts/UserScriptMetadataModels';
import {
  UserScriptPackageDuplicateInfo,
  UserScriptPackageLifecycleCoordinator,
  UserScriptPackageMutationResult,
  UserScriptPackageCommitResult,
  UserScriptPackagePreviewResult,
  UserScriptPackageSourceInput
} from './UserScriptPackageLifecycleCoordinator';
import { formatUserScriptPackageCommitMessage } from './UserScriptFeatureCopy';
import { UserScriptManualSourceEditCompletionSignal } from './UserScriptManualSourceEditCompletionSignal';

export interface UserScriptInstallSessionStartInput {
  existingScriptId?: string;
  source?: string;
  sourceUrl?: string;
}

export interface UserScriptManualSourceEditOwner {
  windowId: string;
  surface: 'page' | 'native_tab';
  dataScope: string;
  privacyMode: string;
  boundarySource: string;
  hostSessionId: string;
}

interface UserScriptManualSourceEditSession {
  token: string;
  owner: UserScriptManualSourceEditOwner;
  source: string;
  completionPending: boolean;
}

export interface UserScriptInstallSessionState {
  source: string;
  sourceUrl: string;
  installSource: UserScriptPackageSource;
  existingScriptId: string;
  importBusy: boolean;
  commitBusy: boolean;
  helperMessage: string;
  revision: number;
  preview?: UserScriptPackagePreviewResult;
}

export type UserScriptInstallSessionObserver = (state: UserScriptInstallSessionState) => void;

export interface UserScriptInstallSessionReadyStartResult {
  status: 'ready';
  state: UserScriptInstallSessionState;
}

export interface UserScriptInstallSessionMissingScriptStartResult {
  status: 'missing-script';
  state: UserScriptInstallSessionState;
  scriptId: string;
}

export type UserScriptInstallSessionStartResult =
  UserScriptInstallSessionReadyStartResult |
  UserScriptInstallSessionMissingScriptStartResult;

export interface UserScriptInstallUrlSourceRequest {
  type: 'url';
  url: string;
}

export interface UserScriptInstallFileSourceRequest {
  type: 'file';
  context: common.UIAbilityContext;
}

export interface UserScriptInstallFileUriSourceRequest {
  type: 'file_uri';
  uri: string;
}

export type UserScriptInstallSourceRequest =
  UserScriptInstallUrlSourceRequest |
  UserScriptInstallFileSourceRequest |
  UserScriptInstallFileUriSourceRequest;

export interface UserScriptInstallSourceLoadedResult {
  status: 'loaded';
  state: UserScriptInstallSessionState;
}

export interface UserScriptInstallSourceDuplicateResult {
  status: 'duplicate';
  duplicate: UserScriptPackageDuplicateInfo;
}

export interface UserScriptInstallSourceCancelledResult {
  status: 'cancelled';
}

export interface UserScriptInstallSourceFailedResult {
  status: 'failed';
  errorMessage: string;
}

export type UserScriptInstallSourceResult =
  UserScriptInstallSourceLoadedResult |
  UserScriptInstallSourceDuplicateResult |
  UserScriptInstallSourceCancelledResult |
  UserScriptInstallSourceFailedResult;

export interface UserScriptConfirmedUrlInstallCompletedResult {
  status: 'completed';
  scriptId: string;
  message: string;
}

export interface UserScriptConfirmedUrlInstallDeniedResult {
  status: 'denied';
  entitlementDecision: EntitlementDecision;
}

export interface UserScriptConfirmedUrlInstallFailedResult {
  status: 'failed';
  errorMessage: string;
}

export type UserScriptConfirmedUrlInstallResult =
  UserScriptConfirmedUrlInstallCompletedResult |
  UserScriptConfirmedUrlInstallDeniedResult |
  UserScriptConfirmedUrlInstallFailedResult;

interface UserScriptInstallSessionDraft {
  source: string;
  sourceUrl: string;
  installSource: UserScriptPackageSource;
  existingScriptId: string;
  clearOriginOnSourceEdit: boolean;
  previewRequested: boolean;
  importBusy: boolean;
  commitBusy: boolean;
  helperMessage: string;
  revision: number;
}

export class UserScriptInstallSessionCoordinator {
  private packageLifecycle: UserScriptPackageLifecycleCoordinator;
  private sourceFetchService: UserScriptSourceFetchService;
  private localFileService: UserScriptLocalFileService;
  private draft: UserScriptInstallSessionDraft = {
    source: '',
    sourceUrl: '',
    installSource: 'paste',
    existingScriptId: '',
    clearOriginOnSourceEdit: true,
    previewRequested: false,
    importBusy: false,
    commitBusy: false,
    helperMessage: '',
    revision: 0
  };
  private observer?: UserScriptInstallSessionObserver;
  private installSurfaceObserverToken: string = '';
  private installSurfaceObserverTokenSerial: number = 0;
  private importOperationSerial: number = 0;
  private commitPromise?: Promise<UserScriptPackageMutationResult>;
  private manualSourceEditTokenSerial: number = 0;
  private manualSourceEditSession?: UserScriptManualSourceEditSession;
  private manualSourceInstallHostTokenSerial: number = 0;
  private activeManualSourceInstallHosts: UserScriptManualSourceEditOwner[] = [];
  private manualSourceInstallOwner?: UserScriptManualSourceEditOwner;
  private manualSourceInstallToken: string = '';
  private manualSourceInstallReleasePending: boolean = false;
  private manualSourceEditCompletionSignal: UserScriptManualSourceEditCompletionSignal;

  constructor(
    packageLifecycle: UserScriptPackageLifecycleCoordinator,
    sourceFetchService: UserScriptSourceFetchService = new UserScriptSourceFetchService(),
    localFileService: UserScriptLocalFileService = new UserScriptLocalFileService(),
    manualSourceEditCompletionSignal: UserScriptManualSourceEditCompletionSignal =
      new UserScriptManualSourceEditCompletionSignal()
  ) {
    this.packageLifecycle = packageLifecycle;
    this.sourceFetchService = sourceFetchService;
    this.localFileService = localFileService;
    this.manualSourceEditCompletionSignal = manualSourceEditCompletionSignal;
  }

  reset(): UserScriptInstallSessionState {
    if (this.draft.commitBusy || this.manualSourceInstallOwner !== undefined) {
      return this.getState();
    }
    this.invalidateImportOperation();
    return this.replaceDraft('', '', 'paste', '', true, false);
  }

  registerManualSourceInstallHost(owner: UserScriptManualSourceEditOwner): string {
    const normalizedOwner = this.normalizeManualSourceEditOwner(owner);
    if (normalizedOwner.windowId.length === 0) {
      return '';
    }
    this.manualSourceInstallHostTokenSerial += 1;
    const hostSessionId = `user-script-install-host-${this.manualSourceInstallHostTokenSerial}`;
    const registeredOwner: UserScriptManualSourceEditOwner = {
      windowId: normalizedOwner.windowId,
      surface: normalizedOwner.surface,
      dataScope: normalizedOwner.dataScope,
      privacyMode: normalizedOwner.privacyMode,
      boundarySource: normalizedOwner.boundarySource,
      hostSessionId: hostSessionId
    };
    this.activeManualSourceInstallHosts.push(registeredOwner);
    this.refreshManualSourceInstallReleasePendingForHostStack();
    return hostSessionId;
  }

  unregisterManualSourceInstallHost(owner: UserScriptManualSourceEditOwner): boolean {
    const normalizedOwner = this.normalizeManualSourceEditOwner(owner);
    const wasRegistered = this.activeManualSourceInstallHosts.some(
      (activeOwner: UserScriptManualSourceEditOwner): boolean =>
        this.isSameManualSourceEditOwner(activeOwner, normalizedOwner)
    );
    if (!wasRegistered) {
      return false;
    }
    this.activeManualSourceInstallHosts = this.activeManualSourceInstallHosts.filter(
      (activeOwner: UserScriptManualSourceEditOwner): boolean =>
        !this.isSameManualSourceEditOwner(activeOwner, normalizedOwner)
    );
    this.refreshManualSourceInstallReleasePendingForHostStack();
    return true;
  }

  hasManualSourceInstallClaim(): boolean {
    return this.manualSourceInstallOwner !== undefined;
  }

  hasManualSourceWorkForHost(owner: UserScriptManualSourceEditOwner): boolean {
    const normalizedOwner = this.normalizeManualSourceEditOwner(owner);
    return (this.manualSourceEditSession !== undefined &&
      this.isSameManualSourceEditOwner(this.manualSourceEditSession.owner, normalizedOwner)) ||
      (this.manualSourceInstallOwner !== undefined &&
        this.isSameManualSourceEditOwner(this.manualSourceInstallOwner, normalizedOwner));
  }

  beginManualSourceEdit(owner: UserScriptManualSourceEditOwner): string {
    const normalizedOwner = this.normalizeManualSourceEditOwner(owner);
    if (this.draft.commitBusy || this.manualSourceEditSession !== undefined ||
      this.manualSourceInstallOwner !== undefined ||
      !this.isActiveManualSourceInstallHost(normalizedOwner)) {
      return '';
    }
    this.reset();
    const token = this.nextManualSourceEditToken();
    this.manualSourceEditSession = {
      token: token,
      owner: normalizedOwner,
      source: '',
      completionPending: false
    };
    return token;
  }

  getStateForInstallSurface(
    owner?: UserScriptManualSourceEditOwner,
    manualSourceInstallToken: string = ''
  ): UserScriptInstallSessionState | undefined {
    return this.canAccessManualSourceInstall(owner, manualSourceInstallToken) ? this.getState() : undefined;
  }

  resetForInstallSurface(
    owner?: UserScriptManualSourceEditOwner,
    manualSourceInstallToken: string = ''
  ): UserScriptInstallSessionState | undefined {
    return this.canAccessManualSourceInstall(owner, manualSourceInstallToken) ? this.reset() : undefined;
  }

  observeInstallSurface(
    observer: UserScriptInstallSessionObserver,
    owner?: UserScriptManualSourceEditOwner,
    manualSourceInstallToken: string = ''
  ): string {
    if (!this.canAccessManualSourceInstall(owner, manualSourceInstallToken)) {
      return '';
    }
    this.installSurfaceObserverTokenSerial += 1;
    const token = `user-script-install-observer-${this.installSurfaceObserverTokenSerial}`;
    this.installSurfaceObserverToken = token;
    this.observer = observer;
    observer(this.getState());
    return token;
  }

  clearInstallSurfaceObserver(token: string): boolean {
    if (token.trim().length === 0 || token !== this.installSurfaceObserverToken) {
      return false;
    }
    this.installSurfaceObserverToken = '';
    this.observer = undefined;
    return true;
  }

  cancelImport(): void {
    const wasBusy = this.draft.importBusy;
    this.invalidateImportOperation();
    if (wasBusy) {
      this.updateImportState(false, '');
    }
  }

  begin(input: UserScriptInstallSessionStartInput = {}): UserScriptInstallSessionStartResult {
    if (this.draft.commitBusy) {
      return this.ready(this.getState());
    }
    const existingScriptId = String(input.existingScriptId ?? '').trim();
    if (existingScriptId.length > 0) {
      const existing = this.packageLifecycle.findInstalledScript(existingScriptId);
      if (existing !== undefined) {
        this.invalidateImportOperation();
        return this.ready(
          this.replaceDraft(
            existing.source,
            existing.sourceUrl,
            resolveUserScriptPackageSource(existing.installSource, existing.sourceUrl),
            existing.id,
            false,
            true
          )
        );
      }
      return {
        status: 'missing-script',
        state: this.reset(),
        scriptId: existingScriptId
      };
    }

    const source = String(input.source ?? '');
    if (source.trim().length > 0) {
      this.invalidateImportOperation();
      const sourceUrl = String(input.sourceUrl ?? '').trim();
      return this.ready(
        this.replaceDraft(
          source,
          sourceUrl,
          sourceUrl.length > 0 ? 'url' : 'paste',
          '',
          true,
          true
        )
      );
    }
    return this.ready(this.getState());
  }

  getState(): UserScriptInstallSessionState {
    return this.buildState();
  }

  editSource(source: string): void {
    if (this.draft.commitBusy) {
      return;
    }
    this.invalidateImportOperation();
    const clearOrigin = this.draft.clearOriginOnSourceEdit;
    this.draft = {
      source: source,
      sourceUrl: clearOrigin ? '' : this.draft.sourceUrl,
      installSource: clearOrigin ? 'paste' : this.draft.installSource,
      existingScriptId: this.draft.existingScriptId,
      clearOriginOnSourceEdit: clearOrigin,
      previewRequested: true,
      importBusy: false,
      commitBusy: false,
      helperMessage: '',
      revision: this.draft.revision + 1
    };
  }

  getManualSourceEditSource(token: string): string {
    return this.isCurrentManualSourceEditToken(token) ? this.manualSourceEditSession?.source ?? '' : '';
  }

  editManualSource(token: string, source: string): boolean {
    if (!this.isCurrentManualSourceEditToken(token) || this.manualSourceEditSession === undefined) {
      return false;
    }
    this.manualSourceEditSession.source = source;
    return true;
  }

  completeManualSourceEdit(token: string, source: string): boolean {
    if (this.draft.commitBusy || this.manualSourceInstallOwner !== undefined ||
      !this.editManualSource(token, source) || this.manualSourceEditSession === undefined) {
      return false;
    }
    this.manualSourceEditSession.completionPending = source.trim().length > 0;
    this.manualSourceEditCompletionSignal.bump();
    return true;
  }

  cancelManualSourceEdit(token: string): boolean {
    if (!this.isCurrentManualSourceEditToken(token)) {
      return false;
    }
    this.manualSourceEditSession = undefined;
    this.manualSourceEditCompletionSignal.bump();
    return true;
  }

  abandonManualSourceEdit(token: string): boolean {
    if (!this.isCurrentManualSourceEditToken(token) ||
      this.manualSourceEditSession?.completionPending === true) {
      return false;
    }
    this.manualSourceEditSession = undefined;
    this.manualSourceEditCompletionSignal.bump();
    return true;
  }

  consumeManualSourceEditCompletion(owner: UserScriptManualSourceEditOwner): string {
    const session = this.manualSourceEditSession;
    const normalizedOwner = this.normalizeManualSourceEditOwner(owner);
    if (this.draft.commitBusy || session === undefined || !session.completionPending ||
      !this.isSameManualSourceEditBoundary(session.owner, normalizedOwner) ||
      !this.isActiveManualSourceInstallHost(normalizedOwner)) {
      return '';
    }
    this.invalidateImportOperation();
    this.manualSourceEditSession = undefined;
    this.manualSourceInstallOwner = normalizedOwner;
    this.manualSourceInstallToken = session.token;
    this.observer = undefined;
    this.installSurfaceObserverToken = '';
    this.replaceDraft(session.source, '', 'paste', '', true, true);
    return session.token;
  }

  releaseManualSourceInstall(owner: UserScriptManualSourceEditOwner, manualSourceInstallToken: string): boolean {
    if (this.manualSourceInstallOwner === undefined ||
      !this.isSameManualSourceInstallAccess(owner, manualSourceInstallToken)) {
      return false;
    }
    if (this.draft.commitBusy) {
      this.manualSourceInstallReleasePending = true;
      return true;
    }
    this.clearManualSourceInstall();
    return true;
  }

  resumeManualSourceInstall(owner: UserScriptManualSourceEditOwner): string {
    const normalizedOwner = this.normalizeManualSourceEditOwner(owner);
    if (this.manualSourceInstallOwner === undefined ||
      !this.isSameManualSourceEditBoundary(this.manualSourceInstallOwner, normalizedOwner) ||
      !this.isActiveManualSourceInstallHost(normalizedOwner) ||
      this.draft.commitBusy || this.manualSourceInstallReleasePending ||
      this.draft.source.trim().length === 0) {
      return '';
    }
    if (!this.isSameManualSourceEditOwner(this.manualSourceInstallOwner, normalizedOwner)) {
      this.manualSourceInstallOwner = normalizedOwner;
      this.observer = undefined;
      this.installSurfaceObserverToken = '';
    }
    this.manualSourceInstallReleasePending = false;
    return this.manualSourceInstallToken;
  }

  async loadSource(request: UserScriptInstallSourceRequest): Promise<UserScriptInstallSourceResult> {
    if (this.manualSourceInstallOwner !== undefined) {
      return this.failed('另一个窗口正在安装脚本，请稍后重试。');
    }
    if (this.draft.commitBusy) {
      return this.failed('脚本正在安装，请稍后重试。');
    }
    const operationSerial = this.beginImportOperation();
    this.updateImportState(true, request.type === 'url' ? '正在下载脚本...' : '');
    try {
      let result: UserScriptInstallSourceResult;
      switch (request.type) {
        case 'url':
          result = await this.loadUrlSource(request.url, operationSerial);
          break;
        case 'file':
          result = await this.loadFileSource(request.context, operationSerial);
          break;
        case 'file_uri':
          result = await this.loadFileUriSource(request.uri, operationSerial);
          break;
      }
      if (!this.isCurrentImportOperation(operationSerial)) {
        return { status: 'cancelled' };
      }
      if (result.status === 'failed') {
        this.updateImportState(false, result.errorMessage);
      } else if (result.status !== 'loaded') {
        this.updateImportState(false, '');
      }
      return result;
    } catch (error) {
      if (!this.isCurrentImportOperation(operationSerial)) {
        return { status: 'cancelled' };
      }
      const fallback = request.type === 'url' ? '下载脚本失败。' : '读取脚本文件失败。';
      const message = error instanceof Error && error.message.length > 0 ? error.message : fallback;
      const result = this.failed(message);
      this.updateImportState(false, message);
      return result;
    }
  }

  async commit(
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    },
    manualSourceInstallOwner?: UserScriptManualSourceEditOwner,
    manualSourceInstallToken: string = ''
  ): Promise<UserScriptPackageMutationResult> {
    if (this.manualSourceEditSession?.completionPending) {
      return this.blockedCommit('脚本编辑正在返回安装页，请稍后重试。');
    }
    if (!this.canAccessManualSourceInstall(manualSourceInstallOwner, manualSourceInstallToken)) {
      return this.blockedCommit('另一个窗口正在安装脚本，请稍后重试。');
    }
    if (this.commitPromise !== undefined) {
      return this.commitPromise;
    }
    if (this.draft.importBusy) {
      return {
        status: 'failed',
        warnings: [],
        errorMessage: '脚本仍在导入，请稍后再保存。'
      };
    }
    const sourceInput = this.buildSourceInput();
    this.updateCommitState(true, false);
    const commitPromise = this.performCommit(sourceInput, entitlementContext);
    this.commitPromise = commitPromise;
    this.publish(this.buildState());
    return commitPromise;
  }

  async installConfirmedUrl(
    url: string,
    entitlementContext: EntitlementContext = {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: true
    }
  ): Promise<UserScriptConfirmedUrlInstallResult> {
    const result: UserScriptPackageCommitResult = await this.packageLifecycle.installFromUrl(url, entitlementContext);
    switch (result.status) {
      case 'denied':
        return {
          status: 'denied',
          entitlementDecision: result.entitlementDecision
        };
      case 'failed':
        return {
          status: 'failed',
          errorMessage: result.errorMessage
        };
      default:
        return {
          status: 'completed',
          scriptId: result.scriptId,
          message: formatUserScriptPackageCommitMessage(result)
        };
    }
  }

  private buildState(knownPreview?: UserScriptPackagePreviewResult): UserScriptInstallSessionState {
    const state: UserScriptInstallSessionState = {
      source: this.draft.source,
      sourceUrl: this.draft.sourceUrl,
      installSource: this.draft.installSource,
      existingScriptId: this.draft.existingScriptId,
      importBusy: this.draft.importBusy,
      commitBusy: this.draft.commitBusy,
      helperMessage: this.draft.helperMessage,
      revision: this.draft.revision
    };
    if (this.draft.previewRequested) {
      state.preview = knownPreview ?? this.packageLifecycle.previewSource(this.buildSourceInput());
    }
    return state;
  }

  private async loadUrlSource(url: string, operationSerial: number): Promise<UserScriptInstallSourceResult> {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length === 0) {
      return this.failed('请输入脚本 URL。');
    }
    const result: UserScriptSourceFetchResult = await this.sourceFetchService.fetchSource(normalizedUrl, true);
    if (!this.isCurrentImportOperation(operationSerial)) {
      return { status: 'cancelled' };
    }
    if (!result.ok) {
      return this.failed(result.errorMessage);
    }
    return this.applyLoadedSource(result.source, normalizedUrl, 'url');
  }

  private async loadFileSource(
    context: common.UIAbilityContext,
    operationSerial: number
  ): Promise<UserScriptInstallSourceResult> {
    const uri = await this.localFileService.pickScriptFileUri(context);
    if (!this.isCurrentImportOperation(operationSerial)) {
      return { status: 'cancelled' };
    }
    if (uri === undefined) {
      return { status: 'cancelled' };
    }
    return await this.loadFileUriSource(uri, operationSerial);
  }

  private async loadFileUriSource(
    uri: string,
    operationSerial: number
  ): Promise<UserScriptInstallSourceResult> {
    const normalizedUri = uri.trim();
    if (normalizedUri.length === 0) {
      return this.failed('未收到可读取的用户脚本文件。');
    }
    const source = await this.localFileService.readScriptFile(normalizedUri);
    if (!this.isCurrentImportOperation(operationSerial)) {
      return { status: 'cancelled' };
    }
    if (source.length === 0) {
      return this.failed('脚本文件为空。');
    }
    return this.applyLoadedSource(source, normalizedUri, 'file');
  }

  private applyLoadedSource(
    source: string,
    sourceUrl: string,
    installSource: UserScriptPackageSource
  ): UserScriptInstallSourceResult {
    const input: UserScriptPackageSourceInput = {
      source: source,
      sourceUrl: sourceUrl,
      installSource: installSource,
      existingScriptId: this.draft.existingScriptId
    };
    const preview = this.packageLifecycle.previewSource(input);
    if (preview.status === 'duplicate') {
      return {
        status: 'duplicate',
        duplicate: preview.duplicate
      };
    }
    return {
      status: 'loaded',
      state: this.replaceDraft(
        source,
        sourceUrl,
        installSource,
        this.draft.existingScriptId,
        this.draft.existingScriptId.length === 0,
        true,
        preview
      )
    };
  }

  private replaceDraft(
    source: string,
    sourceUrl: string,
    installSource: UserScriptPackageSource,
    existingScriptId: string,
    clearOriginOnSourceEdit: boolean,
    previewRequested: boolean,
    knownPreview?: UserScriptPackagePreviewResult
  ): UserScriptInstallSessionState {
    this.draft = {
      source: source,
      sourceUrl: sourceUrl,
      installSource: installSource,
      existingScriptId: existingScriptId,
      clearOriginOnSourceEdit: clearOriginOnSourceEdit,
      previewRequested: previewRequested,
      importBusy: false,
      commitBusy: false,
      helperMessage: '',
      revision: this.draft.revision + 1
    };
    const state = this.buildState(knownPreview);
    this.publish(state);
    return state;
  }

  private updateImportState(importBusy: boolean, helperMessage: string): void {
    this.draft = {
      source: this.draft.source,
      sourceUrl: this.draft.sourceUrl,
      installSource: this.draft.installSource,
      existingScriptId: this.draft.existingScriptId,
      clearOriginOnSourceEdit: this.draft.clearOriginOnSourceEdit,
      previewRequested: this.draft.previewRequested,
      importBusy: importBusy,
      commitBusy: this.draft.commitBusy,
      helperMessage: helperMessage,
      revision: this.draft.revision + 1
    };
    this.publish(this.buildState());
  }

  private updateCommitState(commitBusy: boolean, publish: boolean = true): void {
    this.draft = {
      source: this.draft.source,
      sourceUrl: this.draft.sourceUrl,
      installSource: this.draft.installSource,
      existingScriptId: this.draft.existingScriptId,
      clearOriginOnSourceEdit: this.draft.clearOriginOnSourceEdit,
      previewRequested: this.draft.previewRequested,
      importBusy: this.draft.importBusy,
      commitBusy: commitBusy,
      helperMessage: this.draft.helperMessage,
      revision: this.draft.revision + 1
    };
    if (publish) {
      this.publish(this.buildState());
    }
  }

  private async performCommit(
    sourceInput: UserScriptPackageSourceInput,
    entitlementContext: EntitlementContext
  ): Promise<UserScriptPackageMutationResult> {
    try {
      return await this.packageLifecycle.saveInteractiveSource(sourceInput, entitlementContext);
    } finally {
      const shouldReleaseManualInstall = this.manualSourceInstallReleasePending &&
        this.manualSourceInstallOwner !== undefined &&
        !this.isActiveManualSourceInstallHost(this.manualSourceInstallOwner);
      this.commitPromise = undefined;
      this.updateCommitState(false);
      if (shouldReleaseManualInstall) {
        this.clearManualSourceInstall();
      } else {
        this.manualSourceInstallReleasePending = false;
      }
    }
  }

  private clearManualSourceInstall(): void {
    this.manualSourceInstallOwner = undefined;
    this.manualSourceInstallToken = '';
    this.manualSourceInstallReleasePending = false;
    this.invalidateImportOperation();
    this.replaceDraft('', '', 'paste', '', true, false);
  }

  private beginImportOperation(): number {
    this.importOperationSerial += 1;
    return this.importOperationSerial;
  }

  private invalidateImportOperation(): void {
    this.importOperationSerial += 1;
  }

  private isCurrentImportOperation(operationSerial: number): boolean {
    return operationSerial === this.importOperationSerial;
  }

  private publish(state: UserScriptInstallSessionState): void {
    this.observer?.(state);
  }

  private buildSourceInput(): UserScriptPackageSourceInput {
    return {
      source: this.draft.source,
      sourceUrl: this.draft.sourceUrl,
      installSource: this.draft.installSource,
      existingScriptId: this.draft.existingScriptId
    };
  }

  private normalizeManualSourceEditOwner(owner: UserScriptManualSourceEditOwner): UserScriptManualSourceEditOwner {
    return {
      windowId: owner.windowId.trim(),
      surface: owner.surface,
      dataScope: owner.dataScope.trim(),
      privacyMode: owner.privacyMode.trim(),
      boundarySource: owner.boundarySource.trim(),
      hostSessionId: owner.hostSessionId.trim()
    };
  }

  private nextManualSourceEditToken(): string {
    this.manualSourceEditTokenSerial += 1;
    return `manual-source-edit-${this.manualSourceEditTokenSerial}`;
  }

  private isCurrentManualSourceEditToken(token: string): boolean {
    const normalizedToken = token.trim();
    return normalizedToken.length > 0 && this.manualSourceEditSession?.token === normalizedToken;
  }

  private isSameManualSourceEditBoundary(
    expected: UserScriptManualSourceEditOwner,
    actual: UserScriptManualSourceEditOwner
  ): boolean {
    const normalizedActual = this.normalizeManualSourceEditOwner(actual);
    return expected.windowId.length > 0 &&
      expected.windowId === normalizedActual.windowId &&
      expected.surface === normalizedActual.surface &&
      expected.dataScope === normalizedActual.dataScope &&
      expected.privacyMode === normalizedActual.privacyMode &&
      expected.boundarySource === normalizedActual.boundarySource;
  }

  private isSameManualSourceEditOwner(
    expected: UserScriptManualSourceEditOwner,
    actual: UserScriptManualSourceEditOwner
  ): boolean {
    const normalizedActual = this.normalizeManualSourceEditOwner(actual);
    return expected.hostSessionId.length > 0 &&
      expected.hostSessionId === normalizedActual.hostSessionId &&
      this.isSameManualSourceEditBoundary(expected, normalizedActual);
  }

  private isActiveManualSourceInstallHost(owner: UserScriptManualSourceEditOwner): boolean {
    let activeOwnerForBoundary: UserScriptManualSourceEditOwner | undefined = undefined;
    this.activeManualSourceInstallHosts.forEach(
      (activeOwner: UserScriptManualSourceEditOwner): void => {
        if (this.isSameManualSourceEditBoundary(activeOwner, owner)) {
          activeOwnerForBoundary = activeOwner;
        }
      }
    );
    return activeOwnerForBoundary !== undefined &&
      this.isSameManualSourceEditOwner(activeOwnerForBoundary, owner);
  }

  private refreshManualSourceInstallReleasePendingForHostStack(): void {
    if (!this.draft.commitBusy || this.manualSourceInstallOwner === undefined) {
      return;
    }
    this.manualSourceInstallReleasePending =
      !this.isActiveManualSourceInstallHost(this.manualSourceInstallOwner);
  }

  private isSameManualSourceInstallAccess(
    owner: UserScriptManualSourceEditOwner,
    manualSourceInstallToken: string
  ): boolean {
    const normalizedToken = manualSourceInstallToken.trim();
    return this.manualSourceInstallOwner !== undefined &&
      normalizedToken.length > 0 &&
      normalizedToken === this.manualSourceInstallToken &&
      this.isSameManualSourceEditOwner(this.manualSourceInstallOwner, owner) &&
      this.isActiveManualSourceInstallHost(owner);
  }

  private canAccessManualSourceInstall(
    owner?: UserScriptManualSourceEditOwner,
    manualSourceInstallToken: string = ''
  ): boolean {
    if (this.manualSourceInstallOwner === undefined) {
      return manualSourceInstallToken.trim().length === 0;
    }
    return owner !== undefined && this.isSameManualSourceInstallAccess(owner, manualSourceInstallToken);
  }

  private failed(errorMessage: string): UserScriptInstallSourceFailedResult {
    return {
      status: 'failed',
      errorMessage: errorMessage
    };
  }

  private blockedCommit(errorMessage: string): UserScriptPackageMutationResult {
    return {
      status: 'failed',
      warnings: [],
      errorMessage: errorMessage
    };
  }

  private ready(state: UserScriptInstallSessionState): UserScriptInstallSessionReadyStartResult {
    return {
      status: 'ready',
      state: state
    };
  }
}
