import {
  MediaManifestParseResult,
  MediaManifestRequestContext
} from '../../features/mediaDiscovery/MediaManifestModels';
import { MediaHlsManifestTarget } from '../../features/mediaDiscovery/MediaHlsProjectionModels';
import {
  MediaResourceAction,
  MediaResourceListItem,
  MediaResourceTabCounts,
  emptyMediaResourceTabCounts
} from '../../features/mediaDiscovery/MediaResourceProjectionModels';
import { DownloadRuntimeService } from '../../services/download/DownloadRuntimeService';
import { MediaManifestProcessingService } from '../../services/media/MediaManifestProcessingService';
import { BrowserHlsTakeoverViewModel } from './BrowserHlsTakeoverViewModel';
import { BrowserDownloadConfirmOverlayCoordinator } from './BrowserDownloadConfirmOverlayCoordinator';
import { BrowserMediaDiscoveryCoordinator } from './media/BrowserMediaDiscoveryCoordinator';
import {
  BrowserMediaDiscoveryHost,
  BrowserMediaDiscoverySurfaceState
} from './media/BrowserMediaDiscoveryModels';
import {
  BrowserTransientSurfaceCoordinator,
  BrowserTransientSurfaceUpdate
} from './BrowserTransientSurfaceCoordinator';

export interface BrowserMediaResourceSessionSnapshot {
  resourceListItems: MediaResourceListItem[];
  resourceTabCounts: MediaResourceTabCounts;
  resourceScanInProgress: boolean;
  resourceManifestParsingCandidateId: string;
  resourceManifestParseResult?: MediaManifestParseResult;
  hlsTakeoverMounted: boolean;
  hlsTakeoverVisible: boolean;
  hlsTakeoverTarget?: MediaHlsManifestTarget;
  hlsTakeoverParsingCandidateId: string;
  hlsTakeoverParseResult?: MediaManifestParseResult;
}

export interface BrowserMediaResourcesOverlayAction {
  type: 'close' | 'resource';
  candidateId?: string;
  resourceAction?: MediaResourceAction;
}

export type BrowserHlsTakeoverAction =
  'close' |
  'refresh' |
  'copy_url' |
  'copy_context' |
  'open_resources';

export interface BrowserMediaResourceSessionShell {
  publishSnapshot: (snapshot: BrowserMediaResourceSessionSnapshot) => void;
  copyText: (value: string, emptyMessage: string, successMessage: string) => void;
  endDormantHlsPresentation: () => void;
}

interface BrowserMediaResourceSessionConfig {
  resourceRevealDelayMs: number;
  resourceDismissDurationMs: number;
  hlsDismissDurationMs: number;
}

type BrowserMediaManifestSessionKind = 'resource' | 'hls';

interface BrowserMediaResourceSessionStatePatch {
  resourceListItems?: MediaResourceListItem[];
  resourceTabCounts?: MediaResourceTabCounts;
  resourceScanInProgress?: boolean;
  resourceManifestParsingCandidateId?: string;
  resourceManifestParseResult?: MediaManifestParseResult;
  clearResourceManifestParseResult?: boolean;
  hlsTakeoverMounted?: boolean;
  hlsTakeoverVisible?: boolean;
  hlsTakeoverTarget?: MediaHlsManifestTarget;
  clearHlsTakeoverTarget?: boolean;
  hlsTakeoverParsingCandidateId?: string;
  hlsTakeoverParseResult?: MediaManifestParseResult;
  clearHlsTakeoverParseResult?: boolean;
}

export function createBrowserMediaResourceSessionSnapshot(): BrowserMediaResourceSessionSnapshot {
  return {
    resourceListItems: [],
    resourceTabCounts: emptyMediaResourceTabCounts(),
    resourceScanInProgress: false,
    resourceManifestParsingCandidateId: '',
    resourceManifestParseResult: undefined,
    hlsTakeoverMounted: false,
    hlsTakeoverVisible: false,
    hlsTakeoverTarget: undefined,
    hlsTakeoverParsingCandidateId: '',
    hlsTakeoverParseResult: undefined
  };
}

export class BrowserMediaResourceSessionCoordinator {
  private readonly mediaDiscoveryCoordinator: BrowserMediaDiscoveryCoordinator;
  private readonly mediaDiscoveryHost: BrowserMediaDiscoveryHost;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly downloadService: DownloadRuntimeService;
  private readonly downloadConfirmOverlayCoordinator: BrowserDownloadConfirmOverlayCoordinator;
  private readonly shell: BrowserMediaResourceSessionShell;
  private readonly config: BrowserMediaResourceSessionConfig;
  private readonly mediaManifestProcessingService: MediaManifestProcessingService;
  private readonly hlsTakeoverViewModel: BrowserHlsTakeoverViewModel = new BrowserHlsTakeoverViewModel();
  private snapshot: BrowserMediaResourceSessionSnapshot = createBrowserMediaResourceSessionSnapshot();
  private activePlaybackDownloadInFlight: boolean = false;

  constructor(
    mediaDiscoveryCoordinator: BrowserMediaDiscoveryCoordinator,
    mediaDiscoveryHost: BrowserMediaDiscoveryHost,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    downloadService: DownloadRuntimeService,
    downloadConfirmOverlayCoordinator: BrowserDownloadConfirmOverlayCoordinator,
    shell: BrowserMediaResourceSessionShell,
    config: BrowserMediaResourceSessionConfig,
    mediaManifestProcessingService: MediaManifestProcessingService = new MediaManifestProcessingService()
  ) {
    this.mediaDiscoveryCoordinator = mediaDiscoveryCoordinator;
    this.mediaDiscoveryHost = mediaDiscoveryHost;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.downloadService = downloadService;
    this.downloadConfirmOverlayCoordinator = downloadConfirmOverlayCoordinator;
    this.shell = shell;
    this.config = config;
    this.mediaManifestProcessingService = mediaManifestProcessingService;
  }

  applyDiscoverySurfaceState(state: BrowserMediaDiscoverySurfaceState): void {
    this.applyStatePatch({
      resourceListItems: state.resourceListItems,
      resourceTabCounts: state.resourceTabCounts,
      resourceScanInProgress: state.resourceScanInProgress
    });
  }

  handleTransientSurfaceUpdate(update: BrowserTransientSurfaceUpdate): void {
    if (update.lane !== 'custom_bottom' || update.surfaceId !== 'resource_candidates') {
      return;
    }
    if (update.reason === 'dismissed' || update.reason === 'reset') {
      this.applyManifestParseState('resource', '', undefined);
    }
  }

  openResources(): void {
    const runtime = this.mediaDiscoveryHost.buildRuntimeContext();
    if (!runtime.fullAppServiceMode) {
      this.mediaDiscoveryCoordinator.refreshActiveMediaDiscoverySurface(this.mediaDiscoveryHost);
      this.mediaDiscoveryHost.showToast('页面资源嗅探需切换到全量模式后使用。');
      return;
    }
    this.mediaDiscoveryCoordinator.refreshActiveMediaDiscoverySurface(this.mediaDiscoveryHost);
    void this.mediaDiscoveryCoordinator.runManualResourceScanForActiveTab(this.mediaDiscoveryHost);
    this.applyManifestParseState('resource', '', undefined);
    this.transientSurfaceCoordinator.present({
      id: 'resource_candidates',
      revealDelayMs: this.config.resourceRevealDelayMs,
      dismissDurationMs: this.config.resourceDismissDurationMs
    });
  }

  handleResourcesOverlayAction(action: BrowserMediaResourcesOverlayAction): void {
    if (action.type === 'close') {
      this.closeResources();
      return;
    }
    if (action.candidateId !== undefined && action.resourceAction !== undefined) {
      this.handleResourceAction(action.candidateId, action.resourceAction);
    }
  }

  private closeResources(): void {
    this.applyManifestParseState('resource', '', undefined);
    this.transientSurfaceCoordinator.dismiss('resource_candidates');
  }

  private closeResourcesIfMounted(): void {
    if (this.isResourceSurfaceMounted()) {
      this.closeResources();
    }
  }

  handleTakeoverStarted(): void {
    this.closeResourcesIfMounted();
    this.closeHlsTakeoverIfMounted();
  }

  async requestActivePlaybackDownload(tabId: string, playbackTargetId: string): Promise<void> {
    if (this.activePlaybackDownloadInFlight) {
      this.mediaDiscoveryHost.showToast('正在识别当前视频资源。');
      return;
    }
    this.activePlaybackDownloadInFlight = true;
    try {
      await this.mediaDiscoveryCoordinator.runTakeoverLaunchProbeForTab(tabId, this.mediaDiscoveryHost);
      if (this.mediaDiscoveryHost.resolveActiveTabId() !== tabId) {
        this.mediaDiscoveryHost.showToast('当前网页视频会话已经失效。');
        return;
      }
      const resolution = this.mediaDiscoveryCoordinator.resolveActivePlaybackDownload({
        tabId: tabId,
        runtime: this.mediaDiscoveryHost.buildRuntimeContext(),
        resourcePanelOpen: this.isResourceSurfaceMounted() || this.snapshot.hlsTakeoverMounted
      }, playbackTargetId);
      if (resolution.state !== undefined) {
        this.applyDiscoverySurfaceState(resolution.state);
      }
      if (resolution.downloadRequest === undefined) {
        this.mediaDiscoveryHost.showToast(resolution.message);
        return;
      }
      await this.downloadConfirmOverlayCoordinator.presentAndWaitForDecision(
        this.downloadService.requestManualDownloadPrompt(resolution.downloadRequest)
      );
    } finally {
      this.activePlaybackDownloadInFlight = false;
    }
  }

  handleHlsTakeoverAction(action: BrowserHlsTakeoverAction): void {
    switch (action) {
      case 'close':
        this.closeHlsTakeover();
        return;
      case 'refresh':
        this.parseHlsTakeoverTarget();
        return;
      case 'copy_url':
        this.copyHlsTakeoverUrl();
        return;
      case 'copy_context':
        this.copyHlsTakeoverContext();
        return;
      case 'open_resources':
        this.openResourcesFromHlsTakeover();
        return;
    }
  }

  private closeHlsTakeover(): void {
    this.applyStatePatch({
      hlsTakeoverVisible: false,
      hlsTakeoverParsingCandidateId: ''
    });
    setTimeout(() => {
      if (this.snapshot.hlsTakeoverVisible) {
        return;
      }
      this.applyStatePatch({
        hlsTakeoverMounted: false,
        hlsTakeoverVisible: false,
        clearHlsTakeoverTarget: true,
        hlsTakeoverParsingCandidateId: '',
        clearHlsTakeoverParseResult: true
      });
      this.shell.endDormantHlsPresentation();
    }, this.config.hlsDismissDurationMs);
  }

  private closeHlsTakeoverIfMounted(): void {
    if (this.snapshot.hlsTakeoverMounted) {
      this.closeHlsTakeover();
    }
  }

  private parseHlsTakeoverTarget(): void {
    const candidateId = this.snapshot.hlsTakeoverTarget?.candidateId ?? '';
    const tabId = this.snapshot.hlsTakeoverTarget?.tabId ?? this.mediaDiscoveryHost.resolveActiveTabId();
    const resolution = this.mediaDiscoveryCoordinator.resolveHlsManifestTarget({
      tabId: tabId,
      runtime: this.mediaDiscoveryHost.buildRuntimeContext(),
      resourcePanelOpen: this.isResourceSurfaceMounted() || this.snapshot.hlsTakeoverMounted
    }, candidateId);
    this.applyDiscoverySurfaceState(resolution.state);
    if (resolution.target !== undefined) {
      this.applyStatePatch({ hlsTakeoverTarget: resolution.target });
    }
    void this.runManifestParse('hls', resolution.target);
  }

  private copyHlsTakeoverUrl(): void {
    this.shell.copyText(
      this.snapshot.hlsTakeoverTarget?.url ?? '',
      '当前没有可复制的 m3u8 链接。',
      'm3u8 链接已复制。'
    );
  }

  private copyHlsTakeoverContext(): void {
    this.shell.copyText(
      this.hlsTakeoverViewModel.buildCopyableRequestContext(this.snapshot.hlsTakeoverTarget),
      '当前没有可复制的请求上下文。',
      '请求上下文已复制。'
    );
  }

  private openResourcesFromHlsTakeover(): void {
    this.closeHlsTakeover();
    setTimeout(() => {
      this.openResources();
    }, this.config.hlsDismissDurationMs);
  }

  private handleResourceAction(candidateId: string, action: MediaResourceAction): void {
    const resolution = this.mediaDiscoveryCoordinator.resolveMediaResourceAction({
      tabId: this.mediaDiscoveryHost.resolveActiveTabId(),
      runtime: this.mediaDiscoveryHost.buildRuntimeContext(),
      resourcePanelOpen: true
    }, candidateId, action);
    if (resolution.state !== undefined) {
      this.applyDiscoverySurfaceState(resolution.state);
    }
    switch (resolution.kind) {
      case 'parse_manifest':
        void this.runManifestParse('resource', resolution.hlsTarget);
        return;
      case 'download':
        if (resolution.downloadRequest === undefined) {
          return;
        }
        this.closeResources();
        this.downloadConfirmOverlayCoordinator.present(
          this.downloadService.requestManualDownloadPrompt(resolution.downloadRequest)
        );
        return;
      case 'copy':
        this.shell.copyText(
          resolution.copyUrl ?? '',
          '当前没有可复制的资源链接。',
          '资源链接已复制。'
        );
        return;
      default:
        return;
    }
  }

  private async runManifestParse(
    kind: BrowserMediaManifestSessionKind,
    target: MediaHlsManifestTarget | undefined
  ): Promise<void> {
    if (target === undefined || target.url.trim().length <= 0) {
      const currentParsingCandidateId = kind === 'hls' ?
        this.snapshot.hlsTakeoverParsingCandidateId :
        this.snapshot.resourceManifestParsingCandidateId;
      this.applyManifestParseState(kind, currentParsingCandidateId, undefined);
      this.mediaDiscoveryHost.showToast(
        kind === 'hls' ? '当前没有可解析的 m3u8 链接。' : '当前没有可解析的清单链接。'
      );
      return;
    }
    this.applyManifestParseState(kind, target.candidateId, undefined);
    const result = await this.parseManifest(
      target,
      kind === 'hls' ? 'HLS 清单解析失败。' : '清单解析失败。'
    );
    const currentParsingCandidateId = kind === 'hls' ?
      this.snapshot.hlsTakeoverParsingCandidateId :
      this.snapshot.resourceManifestParsingCandidateId;
    if (currentParsingCandidateId !== target.candidateId) {
      return;
    }
    this.applyManifestParseState(kind, '', result);
    this.mediaDiscoveryHost.showToast(
      result.ok ? (kind === 'hls' ? 'HLS 清单解析完成。' : '清单解析完成。') : result.errorMessage
    );
  }

  private async parseManifest(
    target: MediaHlsManifestTarget,
    fallbackErrorMessage: string
  ): Promise<MediaManifestParseResult> {
    try {
      return await this.mediaManifestProcessingService.parse(this.buildManifestRequestContext(target));
    } catch (_error) {
      return {
        ok: false,
        errorMessage: fallbackErrorMessage
      };
    }
  }

  private buildManifestRequestContext(target: MediaHlsManifestTarget): MediaManifestRequestContext {
    return {
      url: target.url,
      referer: target.referer ?? target.pageUrl,
      userAgent: target.userAgent,
      originUrl: target.originUrl,
      requestHeaders: target.requestHeaders
    };
  }

  private applyManifestParseState(
    kind: BrowserMediaManifestSessionKind,
    parsingCandidateId: string,
    parseResult: MediaManifestParseResult | undefined
  ): void {
    if (kind === 'resource') {
      this.applyStatePatch({
        resourceManifestParsingCandidateId: parsingCandidateId,
        resourceManifestParseResult: parseResult,
        clearResourceManifestParseResult: parseResult === undefined
      });
      return;
    }
    this.applyStatePatch({
      hlsTakeoverParsingCandidateId: parsingCandidateId,
      hlsTakeoverParseResult: parseResult,
      clearHlsTakeoverParseResult: parseResult === undefined
    });
  }

  private isResourceSurfaceMounted(): boolean {
    const surfaces = this.transientSurfaceCoordinator.snapshot().surfaces;
    for (let index = 0; index < surfaces.length; index += 1) {
      if (surfaces[index].id === 'resource_candidates') {
        return surfaces[index].mounted;
      }
    }
    return false;
  }

  private applyStatePatch(patch: BrowserMediaResourceSessionStatePatch): void {
    this.snapshot = {
      resourceListItems: patch.resourceListItems ?? this.snapshot.resourceListItems,
      resourceTabCounts: patch.resourceTabCounts ?? this.snapshot.resourceTabCounts,
      resourceScanInProgress: patch.resourceScanInProgress ?? this.snapshot.resourceScanInProgress,
      resourceManifestParsingCandidateId:
        patch.resourceManifestParsingCandidateId ?? this.snapshot.resourceManifestParsingCandidateId,
      resourceManifestParseResult: patch.clearResourceManifestParseResult === true ?
        undefined : (patch.resourceManifestParseResult ?? this.snapshot.resourceManifestParseResult),
      hlsTakeoverMounted: patch.hlsTakeoverMounted ?? this.snapshot.hlsTakeoverMounted,
      hlsTakeoverVisible: patch.hlsTakeoverVisible ?? this.snapshot.hlsTakeoverVisible,
      hlsTakeoverTarget: patch.clearHlsTakeoverTarget === true ?
        undefined : (patch.hlsTakeoverTarget ?? this.snapshot.hlsTakeoverTarget),
      hlsTakeoverParsingCandidateId:
        patch.hlsTakeoverParsingCandidateId ?? this.snapshot.hlsTakeoverParsingCandidateId,
      hlsTakeoverParseResult: patch.clearHlsTakeoverParseResult === true ?
        undefined : (patch.hlsTakeoverParseResult ?? this.snapshot.hlsTakeoverParseResult)
    };
    this.publishSnapshot();
  }

  private publishSnapshot(): void {
    this.shell.publishSnapshot(this.snapshot);
  }
}
