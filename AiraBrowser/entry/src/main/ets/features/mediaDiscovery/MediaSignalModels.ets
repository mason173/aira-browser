import {
  MediaActionHint,
  MediaAcquisitionFacts,
  MediaAuthContext,
  MediaCandidateFamily,
  MediaCandidateKind,
  MediaDetectionState,
  MediaDownloadabilityState,
  MediaEvidence,
  MediaFrameContext,
  MediaManifestContext,
  MediaPlaybackMetadata,
  MediaPlayabilityState,
  MediaSignalSourceKind,
  NativeMediaIdentity
} from './MediaCandidateModels';

export type MediaSignalKind =
  | 'network_request'
  | 'dom_probe'
  | 'deep_probe'
  | 'site_extractor'
  | 'userscript_request'
  | 'arkweb_media_assistant';

export type MediaSignalCost = 'cheap' | 'normal' | 'expensive';

export interface MediaSignal {
  candidateId?: string;
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  source: MediaSignalSourceKind;
  signalKind: MediaSignalKind;
  url: string;
  family: MediaCandidateFamily;
  kind: MediaCandidateKind;
  evidence: MediaEvidence[];
  confidence: number;
  detectionState?: MediaDetectionState;
  playabilityState?: MediaPlayabilityState;
  downloadabilityState?: MediaDownloadabilityState;
  actionHints?: MediaActionHint[];
  frameContext?: MediaFrameContext;
  authContext?: MediaAuthContext;
  manifestContext?: MediaManifestContext;
  playbackMetadata?: MediaPlaybackMetadata;
  nativeIdentity?: NativeMediaIdentity;
  acquisition?: MediaAcquisitionFacts;
  cost: MediaSignalCost;
  observedAt: number;
}

export interface MediaSignalBatch {
  tabId: string;
  signals: MediaSignal[];
}
