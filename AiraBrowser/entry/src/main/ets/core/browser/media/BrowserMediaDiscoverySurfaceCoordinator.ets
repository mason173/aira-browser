import {
  MediaResourceListProjection,
  MediaResourceTabCounts,
  emptyMediaResourceTabCounts
} from '../../../features/mediaDiscovery/MediaResourceProjectionModels';
import { MediaHlsManifestTarget } from '../../../features/mediaDiscovery/MediaHlsProjectionModels';
import { MediaDownloadCandidate } from '../../../features/mediaDiscovery/MediaDownloadProjectionModels';
import {
  MediaCandidateProjector
} from '../../../services/media/MediaCandidateProjector';
import { MediaDiscoveryTabSnapshot } from '../../../services/media/MediaDiscoveryStore';
import { BrowserMediaDiscoverySurfaceState } from './BrowserMediaDiscoveryModels';

export interface BrowserMediaDiscoverySurfaceBuildInput {
  fullAppServiceMode: boolean;
  tabId: string;
  videoTakeoverEnabled: boolean;
  resourcePanelOpen: boolean;
  resourceScanInProgress: boolean;
}

export interface BrowserMediaDiscoverySurfaceResolution {
  state: BrowserMediaDiscoverySurfaceState;
  clearDomScanState: boolean;
}

export interface BrowserMediaDiscoveryHlsManifestTargetResolution {
  state: BrowserMediaDiscoverySurfaceState;
  target?: MediaHlsManifestTarget;
  resourceTabCounts: MediaResourceTabCounts;
  clearDomScanState: boolean;
  summary: string;
}

export interface BrowserMediaDiscoveryDownloadActionCandidateResolution {
  state: BrowserMediaDiscoverySurfaceState;
  candidate?: MediaDownloadCandidate;
  resourceTabCounts: MediaResourceTabCounts;
  clearDomScanState: boolean;
  summary: string;
}

export class BrowserMediaDiscoverySurfaceCoordinator {
  private projector: MediaCandidateProjector;

  constructor(projector: MediaCandidateProjector = new MediaCandidateProjector()) {
    this.projector = projector;
  }

  build(
    input: BrowserMediaDiscoverySurfaceBuildInput,
    snapshot: MediaDiscoveryTabSnapshot
  ): BrowserMediaDiscoverySurfaceResolution {
    if (!this.shouldExposeSurface(input)) {
      return {
        state: this.buildEmptySurfaceState(),
        clearDomScanState: true
      };
    }
    const resourceListProjection = this.projector.projectResourceList(snapshot, input.videoTakeoverEnabled);
    return {
      state: this.buildSurfaceState(resourceListProjection, input.resourceScanInProgress),
      clearDomScanState: false
    };
  }

  buildHlsManifestTarget(
    input: BrowserMediaDiscoverySurfaceBuildInput,
    snapshot: MediaDiscoveryTabSnapshot,
    candidateId: string
  ): BrowserMediaDiscoveryHlsManifestTargetResolution {
    if (!this.shouldExposeSurface(input)) {
      const state = this.buildEmptySurfaceState();
      return {
        state,
        target: undefined,
        resourceTabCounts: state.resourceTabCounts,
        clearDomScanState: true,
        summary: 'empty'
      };
    }
    const resourceListProjection = this.projector.projectResourceList(snapshot, input.videoTakeoverEnabled);
    const state = this.buildSurfaceState(resourceListProjection, input.resourceScanInProgress);
    const target = this.projector.projectHlsManifestTargetById(snapshot, candidateId);
    return {
      state,
      target,
      resourceTabCounts: state.resourceTabCounts,
      clearDomScanState: false,
      summary: this.summarizeHlsManifestTarget(target)
    };
  }

  buildDownloadActionCandidate(
    input: BrowserMediaDiscoverySurfaceBuildInput,
    snapshot: MediaDiscoveryTabSnapshot,
    candidateId: string
  ): BrowserMediaDiscoveryDownloadActionCandidateResolution {
    if (!this.shouldExposeSurface(input)) {
      const state = this.buildEmptySurfaceState();
      return {
        state,
        candidate: undefined,
        resourceTabCounts: state.resourceTabCounts,
        clearDomScanState: true,
        summary: 'empty'
      };
    }
    const resourceListProjection = this.projector.projectResourceList(snapshot, input.videoTakeoverEnabled);
    const state = this.buildSurfaceState(resourceListProjection, input.resourceScanInProgress);
    const candidate = this.projector.projectDownloadCandidateById(snapshot, candidateId);
    return {
      state,
      candidate,
      resourceTabCounts: state.resourceTabCounts,
      clearDomScanState: false,
      summary: this.summarizeDownloadCandidate(candidate)
    };
  }

  private shouldExposeSurface(input: BrowserMediaDiscoverySurfaceBuildInput): boolean {
    return input.fullAppServiceMode && input.tabId.length > 0 &&
      (input.videoTakeoverEnabled || input.resourcePanelOpen);
  }

  private buildEmptySurfaceState(): BrowserMediaDiscoverySurfaceState {
    return {
      videoMediaCount: 0,
      resourceListItems: [],
      resourceTabCounts: emptyMediaResourceTabCounts(),
      resourceScanInProgress: false
    };
  }

  private buildSurfaceState(
    resourceListProjection: MediaResourceListProjection,
    resourceScanInProgress: boolean
  ): BrowserMediaDiscoverySurfaceState {
    return {
      videoMediaCount: Math.max(0, resourceListProjection.counts.video),
      resourceListItems: resourceListProjection.items,
      resourceTabCounts: resourceListProjection.counts,
      resourceScanInProgress
    };
  }

  private summarizeHlsManifestTarget(target: MediaHlsManifestTarget | undefined): string {
    if (target === undefined) {
      return 'missing';
    }
    return target.kind + '/' + target.family + '/' + target.sourceHost;
  }

  private summarizeDownloadCandidate(candidate: MediaDownloadCandidate | undefined): string {
    if (candidate === undefined) {
      return 'missing';
    }
    return candidate.kind + '/' + candidate.family + '/' + candidate.sourceHost;
  }
}
