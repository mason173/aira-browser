import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { BrowserTabState } from '../tabs/TabManager';
import {
  OfflinePageManifest,
  OfflinePageFailureReason,
  OfflinePageRecord,
  OfflinePageMediaManifestItem,
  OfflinePageSaveEligibility,
  OfflinePageSaveResult,
  OfflinePageSnapshotResult,
  OfflinePageSelectedResource
} from '../../common/models/OfflinePageModels';
import { AIRA_FEATURE_OFFLINE_PAGE_SAVE } from '../../common/constants/MembershipFeatureKeys';
import { OfflinePageRepository } from '../../data/offline/OfflinePageRepository';
import { OfflinePageFileStore } from '../../data/offline/OfflinePageFileStore';
import { OfflinePageManifestCodec } from '../../data/offline/OfflinePageManifestCodec';
import { OfflinePageFailureClassifierService } from '../../services/offline/OfflinePageFailureClassifierService';
import { OfflinePageHtmlSanitizerService } from '../../services/offline/OfflinePageHtmlSanitizerService';
import { OfflinePagePreviewImageResult, OfflinePagePreviewImageService } from '../../services/offline/OfflinePagePreviewImageService';
import { OfflinePageResourceSelectionService } from '../../services/offline/OfflinePageResourceSelectionService';
import { OfflinePageSnapshotService } from '../../services/offline/OfflinePageSnapshotService';
import { OfflinePageStorageQuotaService } from '../../services/offline/OfflinePageStorageQuotaService';
import { OfflinePageWebArchiveService } from '../../services/offline/OfflinePageWebArchiveService';
import { ActivityTracker } from '../../services/activity/ActivityTracker';
import { OfflinePageSaveEligibilityInput, OfflinePageSaveViewModel } from './OfflinePageSaveViewModel';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { WebLoadErrorPresentation } from '../../services/web/WebLoadErrorPresentationService';
import { OfflineErrorDocumentSnapshotService } from '../../services/offline/OfflineErrorDocumentSnapshotService';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { FeatureGateCoordinator } from '../membership/FeatureGateCoordinator';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface OfflinePageSaveShellContext {
  targetTab?: BrowserTabState;
  targetControllerAttached: boolean;
  currentUrl: string;
  currentTitle: string;
  useErrorDocumentSnapshot: boolean;
  errorDocumentPresentation?: WebLoadErrorPresentation;
  errorDocumentTargetUrlCandidates: string[];
  promptFavicon?: image.PixelMap;
}

export interface OfflinePageSaveSessionSnapshot {
  visible: boolean;
  message: string;
  title: string;
  url: string;
  iconUri: string;
  favicon?: image.PixelMap;
}

export interface OfflinePageSaveCoordinatorShell {
  readContext: (targetTabId: string) => OfflinePageSaveShellContext;
  publishSessionSnapshot: (snapshot: OfflinePageSaveSessionSnapshot) => void;
  showToast: (message: string) => void;
  reportError: (message: string) => void;
}

export interface OfflinePageSaveCoordinatorOptions {
  membershipFeature: MembershipFeature;
  featureGateCoordinator: FeatureGateCoordinator;
  shell: OfflinePageSaveCoordinatorShell;
  repository?: OfflinePageRepository;
  fileStore?: OfflinePageFileStore;
  manifestCodec?: OfflinePageManifestCodec;
  snapshotService?: OfflinePageSnapshotService;
  sanitizerService?: OfflinePageHtmlSanitizerService;
  previewImageService?: OfflinePagePreviewImageService;
  resourceSelectionService?: OfflinePageResourceSelectionService;
  storageQuotaService?: OfflinePageStorageQuotaService;
  failureClassifier?: OfflinePageFailureClassifierService;
  webArchiveService?: OfflinePageWebArchiveService;
  errorDocumentSnapshotService?: OfflineErrorDocumentSnapshotService;
  activityTracker?: ActivityTracker;
  runtimeLifecyclePort?: BrowserRuntimeLifecyclePort;
  resolveHostedRuntimeSurfacePort?: () => BrowserHostedRuntimeSurfacePort;
  promptHideDelayMs?: number;
  privacyEffectPolicy?: BrowserPrivacyEffectPolicyService;
  profileBoundaryService?: BrowserProfileBoundaryService;
}

const OFFLINE_PAGE_SNAPSHOT_FILE_NAME: string = 'snapshot.html';
const OFFLINE_PAGE_MANIFEST_FILE_NAME: string = 'manifest.json';
const SAVE_SUCCESS_MESSAGE: string = '已保存到离线页面';
const SAVE_PARTIAL_SUCCESS_MESSAGE: string = '部分资源保存失败，已保存可阅读内容';
const SAVE_CONTENT_TOO_LARGE_MESSAGE: string = '网页内容过大，保存失败';
const SAVE_STORAGE_FULL_MESSAGE: string = '存储空间不足';
const SAVE_UNSUPPORTED_MESSAGE: string = '当前页面暂不支持保存';
const SAVE_FAILED_MESSAGE: string = '当前页面无法保存';
const DEFAULT_PROMPT_HIDE_DELAY_MS: number = 5200;
const HIDDEN_OFFLINE_PAGE_SAVE_SESSION_SNAPSHOT: OfflinePageSaveSessionSnapshot = {
  visible: false,
  message: '',
  title: '',
  url: '',
  iconUri: '',
  favicon: undefined
};

export class OfflinePageSaveCoordinator {
  private viewModel: OfflinePageSaveViewModel;
  private membershipFeature: MembershipFeature;
  private featureGateCoordinator: FeatureGateCoordinator;
  private shell: OfflinePageSaveCoordinatorShell;
  private repository?: OfflinePageRepository;
  private fileStore: OfflinePageFileStore;
  private manifestCodec: OfflinePageManifestCodec;
  private snapshotService: OfflinePageSnapshotService;
  private sanitizerService: OfflinePageHtmlSanitizerService;
  private previewImageService: OfflinePagePreviewImageService;
  private resourceSelectionService: OfflinePageResourceSelectionService;
  private storageQuotaService: OfflinePageStorageQuotaService;
  private failureClassifier: OfflinePageFailureClassifierService;
  private webArchiveService: OfflinePageWebArchiveService;
  private errorDocumentSnapshotService: OfflineErrorDocumentSnapshotService;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private activityTracker?: ActivityTracker;
  private runtimeLifecyclePort?: BrowserRuntimeLifecyclePort;
  private resolveHostedRuntimeSurfacePort?: () => BrowserHostedRuntimeSurfacePort;
  private promptHideDelayMs: number;
  private textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private pendingLinkSaveTabId: string = '';
  private pendingLinkSaveUrl: string = '';
  private sessionSnapshot: OfflinePageSaveSessionSnapshot = HIDDEN_OFFLINE_PAGE_SAVE_SESSION_SNAPSHOT;
  private actionPromptTimer: number = -1;
  private completionPresentationVersion: number = 0;

  constructor(
    options: OfflinePageSaveCoordinatorOptions,
    viewModel: OfflinePageSaveViewModel = new OfflinePageSaveViewModel()
  ) {
    this.viewModel = viewModel;
    this.membershipFeature = options.membershipFeature;
    this.featureGateCoordinator = options.featureGateCoordinator;
    this.shell = options.shell;
    this.repository = options.repository;
    this.fileStore = options.fileStore ?? new OfflinePageFileStore();
    this.manifestCodec = options.manifestCodec ?? new OfflinePageManifestCodec();
    this.snapshotService = options.snapshotService ?? new OfflinePageSnapshotService();
    this.sanitizerService = options.sanitizerService ?? new OfflinePageHtmlSanitizerService();
    this.previewImageService = options.previewImageService ?? new OfflinePagePreviewImageService();
    this.resourceSelectionService = options.resourceSelectionService ?? new OfflinePageResourceSelectionService();
    this.storageQuotaService = options.storageQuotaService ?? new OfflinePageStorageQuotaService(this.fileStore);
    this.failureClassifier = options.failureClassifier ?? new OfflinePageFailureClassifierService();
    this.webArchiveService = options.webArchiveService ?? new OfflinePageWebArchiveService();
    this.errorDocumentSnapshotService = options.errorDocumentSnapshotService ?? new OfflineErrorDocumentSnapshotService();
    this.privacyEffectPolicy = options.privacyEffectPolicy ?? new BrowserPrivacyEffectPolicyService();
    this.profileBoundaryService = options.profileBoundaryService ?? new BrowserProfileBoundaryService();
    this.activityTracker = options.activityTracker;
    this.runtimeLifecyclePort = options.runtimeLifecyclePort;
    this.resolveHostedRuntimeSurfacePort = options.resolveHostedRuntimeSurfacePort;
    this.promptHideDelayMs = options.promptHideDelayMs ?? DEFAULT_PROMPT_HIDE_DELAY_MS;
  }

  getSessionSnapshot(): OfflinePageSaveSessionSnapshot {
    return this.sessionSnapshot;
  }

  startActiveSave(): void {
    this.startSave('');
  }

  startPendingLinkSave(tabId: string): void {
    this.startSave(tabId.trim());
  }

  async ensureLinkSaveAccess(dataScope: string, privacyMode: string): Promise<boolean> {
    const currentUsage = this.repository === undefined ? 0 : (await this.repository.list()).length;
    return this.featureGateCoordinator.ensureAccess(AIRA_FEATURE_OFFLINE_PAGE_SAVE, {
      dataScope: dataScope,
      privacyMode: privacyMode,
      loggedIn: true,
      currentUsage: currentUsage
    });
  }

  private startSave(targetTabId: string): void {
    const presentationVersion = this.completionPresentationVersion;
    void this.runSave(targetTabId, presentationVersion);
  }

  dismissActionPrompt(): void {
    this.clearActionPromptTimer();
    const prompt = this.sessionSnapshot;
    if (!prompt.visible) {
      return;
    }
    this.publishActionPrompt(HIDDEN_OFFLINE_PAGE_SAVE_SESSION_SNAPSHOT);
  }

  handleShellDisappear(): void {
    this.completionPresentationVersion += 1;
    this.dismissActionPrompt();
  }

  clearPendingLinkSave(): void {
    this.pendingLinkSaveTabId = '';
    this.pendingLinkSaveUrl = '';
  }

  markPendingLinkSave(tabId: string, url: string): void {
    this.pendingLinkSaveTabId = tabId.trim();
    this.pendingLinkSaveUrl = url.trim();
  }

  consumePendingLinkSave(tabId: string): boolean {
    if (this.pendingLinkSaveTabId !== tabId.trim()) {
      return false;
    }
    const shouldSave = this.pendingLinkSaveUrl.length > 0;
    this.clearPendingLinkSave();
    return shouldSave;
  }

  private async runSave(targetTabId: string, presentationVersion: number): Promise<void> {
    const context = this.shell.readContext(targetTabId);
    try {
      const targetTab = context.targetTab;
      if (targetTab === undefined) {
        this.shell.reportError('当前页面状态不可用，请稍后重试。');
        return;
      }
      const currentUsage = this.repository === undefined ? 0 : (await this.repository.list()).length;
      const decision = await this.membershipFeature.canUse(AIRA_FEATURE_OFFLINE_PAGE_SAVE, {
        dataScope: targetTab.dataScope,
        privacyMode: targetTab.privacyMode,
        loggedIn: true,
        currentUsage: currentUsage
      });
      if (!decision.allowed) {
        if (presentationVersion === this.completionPresentationVersion) {
          this.featureGateCoordinator.presentDecision(decision);
        }
        return;
      }
      if (presentationVersion === this.completionPresentationVersion) {
        this.shell.showToast('正在保存网页...');
      }
      const result = await this.saveActivePage(context);
      if (result.ok) {
        void this.membershipFeature.recordUsage(AIRA_FEATURE_OFFLINE_PAGE_SAVE);
        if (presentationVersion === this.completionPresentationVersion) {
          this.presentActionPrompt(this.buildSaveActionPromptState(result, context));
        }
        return;
      }
      if (presentationVersion === this.completionPresentationVersion) {
        this.shell.showToast(result.message);
      }
    } catch (error) {
      this.shell.reportError(`保存离线网页失败：${JSON.stringify(error)}`);
      if (presentationVersion === this.completionPresentationVersion) {
        this.shell.showToast(SAVE_FAILED_MESSAGE);
      }
    }
  }

  private async saveActivePage(context: OfflinePageSaveShellContext): Promise<OfflinePageSaveResult> {
    const eligibility = this.resolveActiveEligibility(context);
    if (!eligibility.canSave) {
      return this.buildFailureResult(this.mapBlockedReason(eligibility), eligibility.message || SAVE_FAILED_MESSAGE);
    }
    const tab = context.targetTab;
    if (tab === undefined) {
      return this.buildFailureResult('controller_unavailable', SAVE_FAILED_MESSAGE);
    }
    const documentSnapshot = this.resolveDocumentSnapshot(context);
    const controller = this.resolveController(tab.id);
    if (controller === undefined && documentSnapshot === undefined) {
      return this.buildFailureResult('controller_unavailable', SAVE_FAILED_MESSAGE);
    }
    if (this.repository === undefined) {
      return this.buildFailureResult('database_write_failed', SAVE_FAILED_MESSAGE);
    }

    const saveJobId = this.createSaveJobId();
    try {
      const snapshot = documentSnapshot ?? await this.captureControllerSnapshot(controller);
      if (!snapshot.ok) {
        return this.buildFailureResult(snapshot.reason || 'snapshot_failed', this.resolveFailureMessage(snapshot.reason));
      }

      const metadata = snapshot.metadata;
      const originalUrl = eligibility.targetUrl;
      const normalizedUrl = this.normalizeUrl(originalUrl);
      const urlHash = this.hashUrl(normalizedUrl);
      const pageId = await this.resolvePageId(urlHash);
      const title = this.resolveTitle(metadata.title, eligibility.title, originalUrl);
      const siteName = this.resolveSiteName(metadata.siteName, metadata.host, originalUrl);
      const savedAt = Date.now();
      const selection = this.resourceSelectionService.select(metadata);
      const sanitized = this.sanitizerService.sanitize({
        html: snapshot.html,
        originalUrl: originalUrl,
        title: title,
        siteName: siteName,
        savedAt: savedAt
      });
      const htmlBytes = this.measureUtf8Bytes(sanitized.html);
      const quota = await this.storageQuotaService.check(
        this.storageQuotaService.buildInput(htmlBytes, this.resourceSelectionService.estimateResourceBudgetBytes(selection))
      );
      if (!quota.canWrite) {
        return this.buildFailureResult('storage_full', SAVE_STORAGE_FULL_MESSAGE);
      }
      if (!this.canPersistOfflinePage(tab)) {
        return this.buildFailureResult('privacy_policy_blocked', '当前隐私策略不允许保存离线页面');
      }

      await this.fileStore.prepareDraft(saveJobId);
      await this.fileStore.writeTextToDraft(saveJobId, {
        relativePath: OFFLINE_PAGE_SNAPSHOT_FILE_NAME,
        content: sanitized.html
      });
      const resourceItems = this.buildSkippedResourceItems(selection.resources);
      const previewImage = this.previewImageService.extractPreviewImage(sanitized.html);
      if (previewImage !== undefined) {
        await this.fileStore.writeBytesToDraft(saveJobId, {
          relativePath: previewImage.fileName,
          bytes: previewImage.bytes
        });
      }
      if (controller !== undefined) {
        await this.tryWriteNativeWebArchiveSidecar(saveJobId, controller);
      }
      const manifest: OfflinePageManifest = {
        id: pageId,
        originalUrl: originalUrl,
        title: title,
        siteName: siteName,
        savedAt: savedAt,
        snapshotFileName: OFFLINE_PAGE_SNAPSHOT_FILE_NAME,
        contentKind: 'html',
        previewFileName: previewImage?.fileName ?? '',
        faviconFileName: '',
        resources: resourceItems
      };
      await this.fileStore.writeTextToDraft(saveJobId, {
        relativePath: OFFLINE_PAGE_MANIFEST_FILE_NAME,
        content: this.manifestCodec.encode(manifest)
      });
      const commit = await this.fileStore.commitDraft(saveJobId, pageId);
      const failedResourceCount = this.countFailedResources(resourceItems);
      const record: OfflinePageRecord = {
        id: pageId,
        originalUrl: originalUrl,
        normalizedUrl: normalizedUrl,
        urlHash: urlHash,
        title: title,
        siteName: siteName,
        host: metadata.host.length > 0 ? metadata.host : this.resolveHost(originalUrl),
        savedAt: savedAt,
        updatedAt: savedAt,
        snapshotPath: commit.snapshotPath,
        manifestPath: commit.manifestPath,
        previewImageUri: this.resolveCommittedPreviewUri(commit.pageDir, previewImage),
        faviconUri: '',
        totalBytes: commit.totalBytes,
        resourceCount: resourceItems.length,
        failedResourceCount: failedResourceCount,
        saveStatus: failedResourceCount > 0 ? 'partial_saved' : 'saved',
        openStatus: 'available'
      };
      await this.repository.upsert(record);
      this.activityTracker?.recordFeatureAction(savedAt, 3);
      return {
        ok: true,
        status: record.saveStatus,
        reason: failedResourceCount > 0 ? 'resource_partial_failed' : '',
        message: failedResourceCount > 0 ? SAVE_PARTIAL_SUCCESS_MESSAGE : SAVE_SUCCESS_MESSAGE,
        record: record
      };
    } catch (error) {
      await this.fileStore.cleanupDraft(saveJobId);
      const reason = this.failureClassifier.classify(error);
      return this.buildFailureResult(reason, this.resolveFailureMessage(reason));
    }
  }

  private buildSaveActionPromptState(
    result: OfflinePageSaveResult,
    context: OfflinePageSaveShellContext
  ): OfflinePageSaveSessionSnapshot {
    const record = result.record;
    const title = record?.title.trim() ?? '';
    const url = record?.originalUrl.trim() ?? '';
    return {
      visible: true,
      message: result.message,
      title: title.length > 0 ? title : context.currentTitle,
      url: url.length > 0 ? url : context.currentUrl,
      iconUri: '',
      favicon: context.promptFavicon
    };
  }

  private presentActionPrompt(prompt: OfflinePageSaveSessionSnapshot): void {
    this.clearActionPromptTimer();
    this.publishActionPrompt(prompt);
    this.actionPromptTimer = setTimeout(() => {
      this.actionPromptTimer = -1;
      this.dismissActionPrompt();
    }, this.promptHideDelayMs);
  }

  private clearActionPromptTimer(): void {
    if (this.actionPromptTimer < 0) {
      return;
    }
    clearTimeout(this.actionPromptTimer);
    this.actionPromptTimer = -1;
  }

  private publishActionPrompt(prompt: OfflinePageSaveSessionSnapshot): void {
    this.sessionSnapshot = prompt;
    this.shell.publishSessionSnapshot(this.sessionSnapshot);
  }

  private resolveActiveEligibility(context: OfflinePageSaveShellContext): OfflinePageSaveEligibility {
    return this.viewModel.buildEligibility(this.buildEligibilityInput(context, context.targetTab));
  }

  private buildEligibilityInput(
    context: OfflinePageSaveShellContext,
    tab: BrowserTabState | undefined
  ): OfflinePageSaveEligibilityInput {
    if (tab === undefined) {
      return {
        hasAttachedController: false
      };
    }
    return {
      tab: tab,
      hasAttachedController: this.hasAttachedController(context, tab.id),
      hasDocumentSnapshot: this.hasDocumentSnapshot(context),
      currentUrl: context.currentUrl,
      currentTitle: context.currentTitle
    };
  }

  private hasAttachedController(context: OfflinePageSaveShellContext, tabId: string): boolean {
    const hostedRuntimeSurfacePort = this.resolveHostedRuntimeSurfacePort !== undefined
      ? this.resolveHostedRuntimeSurfacePort()
      : undefined;
    if (hostedRuntimeSurfacePort?.isHostedControllerAttached(tabId) === true) {
      return true;
    }
    if (tabId === context.targetTab?.id && context.targetControllerAttached) {
      return true;
    }
    return this.resolveController(tabId) !== undefined;
  }

  private resolveController(tabId: string): webview.WebviewController | undefined {
    return this.runtimeLifecyclePort?.resolveController(tabId);
  }

  private hasDocumentSnapshot(context: OfflinePageSaveShellContext): boolean {
    return context.useErrorDocumentSnapshot && context.errorDocumentPresentation !== undefined;
  }

  private resolveDocumentSnapshot(
    context: OfflinePageSaveShellContext
  ): OfflinePageSnapshotResult | undefined {
    if (!this.hasDocumentSnapshot(context) || context.errorDocumentPresentation === undefined) {
      return undefined;
    }
    return this.errorDocumentSnapshotService.buildFromCandidates(
      context.errorDocumentPresentation,
      context.errorDocumentTargetUrlCandidates
    );
  }

  private async captureControllerSnapshot(
    controller: webview.WebviewController | undefined
  ): Promise<OfflinePageSnapshotResult> {
    return await this.snapshotService.capture(controller);
  }

  private async resolvePageId(urlHash: string): Promise<string> {
    const existing = await this.repository?.findByUrlHash(urlHash);
    if (existing !== undefined) {
      return existing.id;
    }
    return `offline-page-${urlHash}`;
  }

  private buildSkippedResourceItems(resources: OfflinePageSelectedResource[]): OfflinePageMediaManifestItem[] {
    return resources.map((resource: OfflinePageSelectedResource): OfflinePageMediaManifestItem => {
      return {
        originalUrl: resource.originalUrl,
        localFileName: resource.localFileName,
        mimeType: '',
        bytes: 0,
        status: 'skipped'
      };
    });
  }

  private async tryWriteNativeWebArchiveSidecar(
    saveJobId: string,
    controller: webview.WebviewController
  ): Promise<void> {
    const archiveFileName = this.webArchiveService.getFileName();
    const draftArchivePath = this.fileStore.getDraftFilePath(saveJobId, archiveFileName);
    const archive = await this.webArchiveService.capture(controller, draftArchivePath);
    if (!archive.ok) {
      return;
    }
    if (archive.path !== draftArchivePath) {
      await this.fileStore.moveFileToDraft(saveJobId, archive.path, archiveFileName);
    }
  }

  private countFailedResources(resources: OfflinePageMediaManifestItem[]): number {
    let failedCount = 0;
    resources.forEach((resource: OfflinePageMediaManifestItem) => {
      if (resource.status === 'failed') {
        failedCount += 1;
      }
    });
    return failedCount;
  }

  private resolveCommittedPreviewUri(
    pageDir: string,
    previewImage: OfflinePagePreviewImageResult | undefined
  ): string {
    if (previewImage === undefined || previewImage.fileName.length === 0) {
      return '';
    }
    return this.fileStore.toFileUri(`${pageDir}/${previewImage.fileName}`);
  }

  private mapBlockedReason(eligibility: OfflinePageSaveEligibility): 'unsupported_page' | 'controller_unavailable' {
    if (eligibility.reason === 'controller_unavailable') {
      return 'controller_unavailable';
    }
    return 'unsupported_page';
  }

  private canPersistOfflinePage(tab: BrowserTabState): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'offline_page_save',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        profileId: tab.profileId,
        dataScope: tab.dataScope,
        privacyMode: tab.privacyMode,
        sessionId: tab.id
      }),
      targetScope: 'regular_profile_data',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private buildFailureResult(reason: OfflinePageFailureReason | '', message: string): OfflinePageSaveResult {
    return {
      ok: false,
      status: 'failed',
      reason: reason,
      message: message
    };
  }

  private resolveFailureMessage(reason: string): string {
    if (reason === 'content_too_large') {
      return SAVE_CONTENT_TOO_LARGE_MESSAGE;
    }
    if (reason === 'storage_full') {
      return SAVE_STORAGE_FULL_MESSAGE;
    }
    if (reason === 'unsupported_page' || reason === 'snapshot_failed') {
      return SAVE_UNSUPPORTED_MESSAGE;
    }
    return SAVE_FAILED_MESSAGE;
  }

  private resolveTitle(snapshotTitle: string, eligibilityTitle: string, url: string): string {
    const candidates: string[] = [snapshotTitle, eligibilityTitle, this.resolveHost(url), url];
    for (let index = 0; index < candidates.length; index += 1) {
      const value = candidates[index].trim();
      if (value.length > 0) {
        return value;
      }
    }
    return '离线网页';
  }

  private resolveSiteName(snapshotSiteName: string, snapshotHost: string, url: string): string {
    const candidates: string[] = [snapshotSiteName, snapshotHost, this.resolveHost(url)];
    for (let index = 0; index < candidates.length; index += 1) {
      const value = candidates[index].trim();
      if (value.length > 0) {
        return value;
      }
    }
    return '未知来源';
  }

  private resolveHost(url: string): string {
    const protocolMarker = url.indexOf('://');
    if (protocolMarker < 0) {
      return '';
    }
    const hostStart = protocolMarker + 3;
    const slashIndex = url.indexOf('/', hostStart);
    const hostWithPort = slashIndex < 0 ? url.substring(hostStart) : url.substring(hostStart, slashIndex);
    const queryIndex = hostWithPort.indexOf('?');
    const cleanHost = queryIndex < 0 ? hostWithPort : hostWithPort.substring(0, queryIndex);
    return cleanHost.trim();
  }

  private normalizeUrl(url: string): string {
    return url.trim();
  }

  private hashUrl(url: string): string {
    let hash = 2166136261;
    for (let index = 0; index < url.length; index += 1) {
      hash = (hash ^ url.charCodeAt(index)) * 16777619;
      hash = hash >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  }

  private measureUtf8Bytes(value: string): number {
    return this.textEncoder.encodeInto(value).byteLength;
  }

  private createSaveJobId(): string {
    return `offline-save-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
  }
}
