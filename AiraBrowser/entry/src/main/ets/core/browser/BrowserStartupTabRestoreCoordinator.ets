import {
  BrowserPrivateTabRestorePolicy,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  BrowserTabAutoClosePolicy,
  TabRecord
} from '../../common/models/BrowserModels';
import {
  BrowserCreateTabOptions,
  BrowserTabRestoreResult,
  BrowserTabState,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import { WebRecoveryManager } from '../web/WebRecoveryManager';
import { DocumentViewerService } from '../../services/viewer/DocumentViewerService';
import {
  sharedPreferencesRepository,
  sharedAdBlockRepository,
  sharedSiteClearOnClosePendingRepository,
  sharedTabSessionRepository
} from '../../app/bootstrap/BrowserAppRuntime';
import { BrowserAdBlockCoordinator } from './BrowserAdBlockCoordinator';
import { BrowserDownloadNavigationStateCoordinator } from './BrowserDownloadNavigationStateCoordinator';
import {
  BrowserColdRestoreResolution,
  BrowserRestoreCoordinator,
  BrowserRestoreTrace
} from './BrowserRestoreCoordinator';
import {
  BrowserPrivateProfileLifecycleCoordinator
} from './BrowserPrivateProfileLifecycleCoordinator';
import {
  BrowserPrivateSessionCleanupCoordinator
} from './BrowserPrivateSessionCleanupCoordinator';
import { BrowserRecentlyClosedApplicationCoordinator } from './BrowserRecentlyClosedApplicationCoordinator';
import {
  SiteClearOnCloseCoordinator,
  SiteClearOnCloseCoordinatorHost
} from './SiteClearOnCloseCoordinator';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import {
  BrowserDocumentViewerSessionFilterResult,
  BrowserTabSessionRecordFilterCoordinator
} from './BrowserTabSessionRecordFilterCoordinator';
import {
  BrowserTabSessionRestorePreparation,
  BrowserTabSessionRestoreService
} from './BrowserTabSessionRestoreService';
import { BrowserMaterializationPolicy } from './BrowserMaterializationPolicy';
import {
  BrowserShellStateCoordinator,
  BrowserShellVisualState
} from './BrowserShellStateCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserWindowContextPort } from './BrowserWindowContextCoordinator';
import {
  BrowserTabBackgroundSessionSyncCoordinator
} from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserTabPreviewAssetBoundaryCoordinator } from './BrowserTabPreviewAssetBoundaryCoordinator';
import { BrowserTabPreviewCoordinator } from './BrowserTabPreviewCoordinator';
import {
  BrowserNativeNavigationConsumeCoordinator
} from '../navigation/BrowserNativeNavigationConsumeCoordinator';
import { RestoredTabSiteIconPrewarmCoordinator } from '../siteicons/RestoredTabSiteIconPrewarmCoordinator';

interface BrowserStartupTabRestoreRuntimeEvent {
  type: string;
  message: string;
  tabId: string;
}

interface BrowserStartupTabRestoreRequest {
  records: TabRecord[];
  tabSessionBoundaryOptions: BrowserCreateTabOptions;
  profileId: BrowserProfileId;
  currentActiveTabId: string;
  openHomeSurface: boolean;
  tabAutoClosePolicy?: BrowserTabAutoClosePolicy;
  privateTabRestorePolicy?: BrowserPrivateTabRestorePolicy | string;
  tabManager: BrowserTabManagerPort;
  documentViewerService: DocumentViewerService;
  webRecoveryManager: WebRecoveryManager;
}

interface BrowserStartupTabRestoreApplicationResult {
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
  startupBoundaryOptions: BrowserCreateTabOptions;
  hadStoredRecords: boolean;
  openHomeSurface: boolean;
  runtimeDegradedMessage: string;
  traces: BrowserRestoreTrace[];
  runtimeEvents: BrowserStartupTabRestoreRuntimeEvent[];
}

export interface BrowserStartupTabRestoreRunRequest {
  tabSessionBoundaryOptions: BrowserCreateTabOptions;
  profileId: BrowserProfileId;
  windowId: string;
}

export interface BrowserStartupTabRestoreFacts {
  activeTabId: string;
  tabSequence: number;
  runtimeDegradedMessage: string;
  tabs: BrowserTabState[];
  currentWindowId: string;
}

export interface BrowserStartupTabRestoreTabSnapshot {
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
}

export interface BrowserStartupTabRestoreStateApplication {
  tabSnapshot?: BrowserStartupTabRestoreTabSnapshot;
  restoreCompleted?: boolean;
  restoreTrace?: BrowserRestoreTrace;
  runtimeDegradedMessage?: string;
  resetHomeNavigationState?: boolean;
  previewRenderRevisionIncrement?: boolean;
}

export interface BrowserStartupTabRestoreHost {
  resolveFacts: () => BrowserStartupTabRestoreFacts;
  applyState: (application: BrowserStartupTabRestoreStateApplication) => void;
  setStartupHomeSurfacePending: (pending: boolean) => void;
  resetHomeTransientUiState: () => void;
  applyShellVisualState: (state: BrowserShellVisualState) => void;
  connectSearchInvocationSurfaceIfReady: () => void;
}

export interface BrowserStartupTabRestoreDependencies {
  restoreCoordinator: BrowserRestoreCoordinator;
  downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;
  recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator;
  siteClearOnCloseCoordinator: SiteClearOnCloseCoordinator;
  siteClearOnCloseHost: SiteClearOnCloseCoordinatorHost;
  privateSessionCleanupCoordinator: BrowserPrivateSessionCleanupCoordinator;
  privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator;
  tabSessionPersistenceCoordinator: BrowserTabSessionPersistenceCoordinator;
  tabManager: BrowserTabManagerPort;
  documentViewerService: DocumentViewerService;
  webRecoveryManager: WebRecoveryManager;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  resolveTabHomeCoordinator: () => BrowserTabHomeCoordinator;
  backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  shellStateCoordinator: BrowserShellStateCoordinator;
  tabPreviewAssetBoundaryCoordinator: BrowserTabPreviewAssetBoundaryCoordinator;
  tabPreviewCoordinator: BrowserTabPreviewCoordinator;
  nativeNavigationConsumeCoordinator: BrowserNativeNavigationConsumeCoordinator;
  previewHydrateBatchSize: number;
  previewHydrateBatchDelayMs: number;
  resolveWindowContextCoordinator: () => BrowserWindowContextPort;
}

export class BrowserStartupTabRestoreCoordinator {
  private readonly dependencies: BrowserStartupTabRestoreDependencies;
  private readonly host: BrowserStartupTabRestoreHost;
  private startupRestoreGeneration: number = 0;
  private sessionRestoreService: BrowserTabSessionRestoreService = new BrowserTabSessionRestoreService();
  private sessionRecordFilterCoordinator: BrowserTabSessionRecordFilterCoordinator =
    new BrowserTabSessionRecordFilterCoordinator();
  private restoredTabSiteIconPrewarmCoordinator: RestoredTabSiteIconPrewarmCoordinator =
    new RestoredTabSiteIconPrewarmCoordinator();

  constructor(dependencies: BrowserStartupTabRestoreDependencies, host: BrowserStartupTabRestoreHost) {
    this.dependencies = dependencies;
    this.host = host;
  }

  runStartupRestore(request: BrowserStartupTabRestoreRunRequest): void {
    const restoreGeneration = this.startupRestoreGeneration + 1;
    this.startupRestoreGeneration = restoreGeneration;
    const adBlockRuntimeReadiness = BrowserAdBlockCoordinator.prepareRuntimeBootStateForRepository(
      sharedAdBlockRepository
    );
    this.dependencies.downloadNavigationStateCoordinator
      .loadNonRestorableNavigationGuards()
      .then(() => this.dependencies.recentlyClosedApplicationCoordinator.loadForStartup(request.profileId))
      .then(() => sharedSiteClearOnClosePendingRepository.consumeRecords(request.windowId, request.profileId))
      .then((pendingRecords: TabRecord[]) => {
        this.cleanupSiteClearOnCloseRecords(pendingRecords);
      })
      .then(() => sharedTabSessionRepository.refresh(request.windowId, request.profileId))
      .then((records: TabRecord[]) => {
        return adBlockRuntimeReadiness.then(() => {
          if (!this.isStartupRestoreCurrent(restoreGeneration)) {
            return;
          }
          const currentActiveTabId = this.host.resolveFacts().activeTabId;
          void this.cleanupPrivateStartupResidualState(records, request.profileId);
          this.cleanupSiteClearOnCloseRecords(records);
          const generalSettings = sharedPreferencesRepository.getPreferences().general;
          const resolvedBoundaryOptions = this.resolveStartupTabSessionBoundaryOptions(
            request.tabSessionBoundaryOptions,
            generalSettings.alwaysUsePrivateMode === true
          );
          const restoreResult = this.buildRestoreApplicationResult({
            records: records,
            tabSessionBoundaryOptions: resolvedBoundaryOptions,
            profileId: request.profileId,
            currentActiveTabId: currentActiveTabId,
            openHomeSurface: generalSettings.startupRestorePolicy === 'open_home',
            tabAutoClosePolicy: generalSettings.tabAutoClosePolicy,
            privateTabRestorePolicy: generalSettings.privateTabRestorePolicy,
            tabManager: this.dependencies.tabManager,
            documentViewerService: this.dependencies.documentViewerService,
            webRecoveryManager: this.dependencies.webRecoveryManager
          });
          this.applyRestoreResult(restoreResult, restoreGeneration);
        });
      })
      .catch((_error: Error) => {
        if (!this.isStartupRestoreCurrent(restoreGeneration)) {
          return;
        }
        this.applyRestoreFailure(this.host.resolveFacts().activeTabId, restoreGeneration);
      });
  }

  cancelStartupRestore(): void {
    this.startupRestoreGeneration += 1;
  }

  private isStartupRestoreCurrent(generation: number): boolean {
    return generation === this.startupRestoreGeneration;
  }

  private cleanupSiteClearOnCloseRecords(records: TabRecord[]): void {
    this.dependencies.siteClearOnCloseCoordinator.cleanupRecordsForStartup(
      records,
      this.dependencies.siteClearOnCloseHost
    );
  }

  private cleanupPrivateStartupResidualState(records: TabRecord[], profileId: BrowserProfileId): Promise<void> {
    return this.dependencies.privateSessionCleanupCoordinator.runStartupResidualCleanup(
      this.dependencies.privateProfileLifecycleCoordinator.buildStartupResidualCleanupRequest(
        records,
        profileId,
        sharedPreferencesRepository.getPreferences().general.privateModePreserveCookiesOnClose
      )
    );
  }

  private resolveStartupTabSessionBoundaryOptions(
    current: BrowserCreateTabOptions,
    alwaysUsePrivateMode: boolean
  ): BrowserCreateTabOptions {
    if (!alwaysUsePrivateMode) {
      return current;
    }
    const privacyMode: BrowserSessionPrivacyMode = 'private';
    return {
      profileId: current.profileId,
      privacyMode: privacyMode,
      dataScope: 'session_ephemeral',
      launchContext: current.launchContext,
      openerTabId: current.openerTabId,
      openSource: current.openSource,
      openedByNewWindow: current.openedByNewWindow,
      insertAfterTabId: current.insertAfterTabId
    };
  }

  private buildRestoreApplicationResult(request: BrowserStartupTabRestoreRequest): BrowserStartupTabRestoreApplicationResult {
    const hadStoredRecords = request.records.length > 0;
    const runtimeEvents: BrowserStartupTabRestoreRuntimeEvent[] = [];
    const restoreRecords = this.filterDocumentViewerRecords(request, runtimeEvents);
    const preparation = this.sessionRestoreService.prepareRecordsForColdRestore(
      restoreRecords,
      this.sessionRestoreService.buildOptions(
        request.tabAutoClosePolicy,
        request.privateTabRestorePolicy
      )
    );
    const resolution = this.dependencies.restoreCoordinator.buildColdRestoreResolution(
      request.webRecoveryManager,
      preparation.records
    );
    const restored = request.tabManager.restoreTabs(resolution.records, request.tabSessionBoundaryOptions);
    request.webRecoveryManager.pruneTabs(restored.tabs.map((tab: BrowserTabState) => tab.id));
    this.appendColdRestoreTraceEvents(runtimeEvents, resolution);
    this.appendDroppedRecordDiagnostics(runtimeEvents, preparation, restored);
    return {
      tabs: restored.tabs,
      activeTabId: restored.activeTabId,
      tabSequence: restored.tabSequence,
      startupBoundaryOptions: request.tabSessionBoundaryOptions,
      hadStoredRecords: hadStoredRecords,
      openHomeSurface: request.openHomeSurface,
      runtimeDegradedMessage: this.buildSkippedRecordMessage(resolution.skippedCount),
      traces: resolution.traces,
      runtimeEvents: runtimeEvents
    };
  }

  private filterDocumentViewerRecords(
    request: BrowserStartupTabRestoreRequest,
    runtimeEvents: BrowserStartupTabRestoreRuntimeEvent[]
  ): TabRecord[] {
    const result: BrowserDocumentViewerSessionFilterResult =
      this.sessionRecordFilterCoordinator.filterDocumentViewerRecords(
        request.records,
        request.documentViewerService,
        request.tabManager,
        request.tabSessionBoundaryOptions
      );
    if (result.removedCount > 0) {
      runtimeEvents.push({
        type: 'document_viewer_session_filtered',
        message: `reason=persist_tabs removed=${result.removedCount}`,
        tabId: request.currentActiveTabId
      });
    }
    return result.records;
  }

  private appendColdRestoreTraceEvents(
    runtimeEvents: BrowserStartupTabRestoreRuntimeEvent[],
    resolution: BrowserColdRestoreResolution
  ): void {
    resolution.traces.forEach((trace: BrowserRestoreTrace) => {
      runtimeEvents.push({
        type: 'cold_restore_plan',
        message: `trace=${trace.id} type=${trace.restoreType} source=${trace.source} target=${trace.targetUrl} ` +
          `snapshot=${trace.snapshotPath.length > 0 ? trace.snapshotPath : 'none'}`,
        tabId: trace.tabId
      });
    });
  }

  private appendDroppedRecordDiagnostics(
    runtimeEvents: BrowserStartupTabRestoreRuntimeEvent[],
    preparation: BrowserTabSessionRestorePreparation,
    restored: BrowserTabRestoreResult
  ): void {
    this.sessionRestoreService
      .buildDroppedRecordDiagnostics(preparation)
      .forEach((diagnostic) => {
        runtimeEvents.push({
          type: diagnostic.eventName,
          message: diagnostic.message,
          tabId: restored.activeTabId
        });
      });
  }

  private buildSkippedRecordMessage(skippedCount: number): string {
    if (skippedCount <= 0) {
      return '';
    }
    return `已跳过 ${skippedCount} 个损坏标签页，避免冷启动恢复卡死。`;
  }

  private applyRestoreResult(
    result: BrowserStartupTabRestoreApplicationResult,
    restoreGeneration: number
  ): void {
    if (!this.isStartupRestoreCurrent(restoreGeneration)) {
      return;
    }
    const startupMaterializationPolicy: BrowserMaterializationPolicy = 'active_only';
    const currentFacts = this.host.resolveFacts();
    // Keep the startup surface on Home while restored web state is being
    // materialized. Other runtime callbacks can arrive between the tab
    // snapshot and the final open_home application; they must not expose the
    // restored active tab in that window.
    this.host.setStartupHomeSurfacePending(result.openHomeSurface);
    this.host.applyState({
      tabSnapshot: {
        tabs: result.tabs,
        activeTabId: result.activeTabId,
        tabSequence: Math.max(currentFacts.tabSequence, result.tabSequence)
      }
    });
    // Warm the restored tabs' cached favicons while the web surface is still
    // materializing. The tabs overview resolves card icons from the memory
    // cache at paint time, so doing this here keeps the first cold-start grid
    // from rendering letter badges for tabs whose icons are already on disk.
    this.restoredTabSiteIconPrewarmCoordinator.prewarmRestoredTabs(result.tabs);
    if (result.startupBoundaryOptions.privacyMode === 'private') {
      const activeTab = result.tabs.find((tab: BrowserTabState) => tab.id === result.activeTabId);
      if (activeTab !== undefined) {
        this.dependencies.resolveTabHomeCoordinator().applyBoundary(
          activeTab.profileId,
          activeTab.privacyMode,
          activeTab.dataScope
        );
      }
    }
    this.host.applyState({ restoreCompleted: true });
    const pendingLaunchSource = result.openHomeSurface ? 'restore-tabs-home' : 'restore-tabs';
    const pendingWebSceneLaunchConsumed = this.dependencies.resolveWindowContextCoordinator()
      .consumePendingWebSceneLaunch(pendingLaunchSource);
    if (pendingWebSceneLaunchConsumed) {
      this.host.setStartupHomeSurfacePending(false);
    }
    if (!pendingWebSceneLaunchConsumed) {
      if (result.openHomeSurface) {
        this.applyOpenHomeSurface(startupMaterializationPolicy);
        this.host.setStartupHomeSurfacePending(false);
      } else {
        this.dependencies.tabSwitchCoordinator.synchronizeActiveTab(startupMaterializationPolicy);
      }
    }
    this.restorePersistedTabPreviews();
    result.traces.forEach((trace: BrowserRestoreTrace) => {
      this.host.applyState({ restoreTrace: trace });
    });
    if (result.runtimeDegradedMessage.length > 0) {
      this.host.applyState({ runtimeDegradedMessage: result.runtimeDegradedMessage });
    }
    if (result.hadStoredRecords) {
      this.dependencies.tabSessionPersistenceCoordinator.persist();
    }
    this.completePendingLaunch(pendingLaunchSource, pendingWebSceneLaunchConsumed);
  }

  private applyOpenHomeSurface(materializationPolicy: BrowserMaterializationPolicy): void {
    this.host.resetHomeTransientUiState();
    this.host.applyShellVisualState(
      this.dependencies.shellStateCoordinator.buildHomeState(this.host.resolveFacts().runtimeDegradedMessage)
    );
    this.host.applyState({ resetHomeNavigationState: true });
    this.dependencies.backgroundSessionSyncCoordinator.sync('session_sync', {
      materializationPolicy: materializationPolicy
    });
  }

  private applyRestoreFailure(_activeTabId: string, restoreGeneration: number): void {
    if (!this.isStartupRestoreCurrent(restoreGeneration)) {
      return;
    }
    this.host.setStartupHomeSurfacePending(false);
    this.host.applyState({ restoreCompleted: true });
    const pendingLaunchSource = 'restore-tabs-fallback';
    const pendingWebSceneLaunchConsumed = this.dependencies.resolveWindowContextCoordinator()
      .consumePendingWebSceneLaunch(pendingLaunchSource);
    if (!pendingWebSceneLaunchConsumed) {
      this.dependencies.tabSwitchCoordinator.synchronizeActiveTab('active_only');
    }
    this.completePendingLaunch(pendingLaunchSource, pendingWebSceneLaunchConsumed);
  }

  private restorePersistedTabPreviews(): void {
    const facts = this.host.resolveFacts();
    void this.dependencies.tabPreviewAssetBoundaryCoordinator.hydratePersistedPreviewMetadata({
      previewCoordinator: this.dependencies.tabPreviewCoordinator,
      tabs: facts.tabs,
      suspendedWindowTabsByWindowId: this.dependencies.resolveWindowContextCoordinator()
        .getSuspendedWindowTabsByWindowId(),
      currentWindowId: facts.currentWindowId,
      options: {
        batchSize: this.dependencies.previewHydrateBatchSize,
        batchDelayMs: this.dependencies.previewHydrateBatchDelayMs
      },
      notifyChanged: (): void => this.host.applyState({ previewRenderRevisionIncrement: true })
    });
  }

  private completePendingLaunch(source: string, webSceneLaunchAlreadyConsumed: boolean = false): void {
    if (!webSceneLaunchAlreadyConsumed) {
      this.dependencies.nativeNavigationConsumeCoordinator.consume();
    }
    this.host.connectSearchInvocationSurfaceIfReady();
    const windowContextCoordinator = this.dependencies.resolveWindowContextCoordinator();
    if (!webSceneLaunchAlreadyConsumed) {
      windowContextCoordinator.consumePendingLaunch(source);
    }
    windowContextCoordinator.schedulePendingLaunchPolling();
  }
}
