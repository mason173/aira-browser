import { MediaCandidateValidationSnapshot } from './MediaCandidateValidationModels';

export type MediaSignalSourceKind =
  | 'resource_network'
  | 'resource_dom'
  | 'video_network'
  | 'video_dom'
  | 'site_extractor'
  | 'arkweb_media_assistant'
  | 'video_adapter'
  | 'unknown';

export type MediaCandidateFamily =
  | 'video'
  | 'audio'
  | 'image'
  | 'file'
  | 'manifest'
  | 'segment'
  | 'unknown';

export type MediaCandidateKind =
  | 'hls'
  | 'dash'
  | 'mp4'
  | 'webm'
  | 'mov'
  | 'flv'
  | 'mkv'
  | 'avi'
  | 'mpeg'
  | 'wmv'
  | 'ogv'
  | 'audio'
  | 'image'
  | 'document'
  | 'archive'
  | 'package'
  | 'segment'
  | 'unknown';

export type MediaDetectionState = 'detected' | 'needs_processing' | 'stale';

export type MediaPlayabilityState =
  | 'unknown'
  | 'candidate'
  | 'playable'
  | 'playing_native'
  | 'needs_processing'
  | 'unsupported'
  | 'protected'
  | 'expired'
  | 'failed'
  | 'requires_po_token'
  | 'signature_failed'
  | 'format_unavailable';

export type MediaDownloadabilityState =
  | 'unknown'
  | 'downloadable'
  | 'manifest'
  | 'copy_only'
  | 'needs_headers'
  | 'unsupported'
  | 'expired';

export type MediaActionHint = 'download' | 'parse_manifest' | 'copy';

/**
 * The transport shape of a media acquisition. This describes how the current resource can be
 * consumed without naming the site, Profile, Recipe, or extractor that found it.
 */
export type MediaAcquisitionMode = 'progressive' | 'paired_adaptive';

/**
 * `combined` is a progressive resource carrying its own audio, while adaptive resources expose
 * separately acquired video and audio tracks.
 */
export type MediaAcquisitionTrackRole = 'combined' | 'video' | 'audio';

export interface MediaAcquisitionTrack {
  role: MediaAcquisitionTrackRole;
  url: string;
  mimeType?: string;
  codecs?: string;
  bitrate?: number;
  contentLength?: number;
  width?: number;
  height?: number;
  fps?: number;
  audioSampleRate?: number;
  audioChannels?: number;
  initializationRange?: string;
  indexRange?: string;
}

/**
 * Site-neutral resource and track facts for an acquired playable source. `pairedTrack` is present
 * only for a `paired_adaptive` acquisition and is always the separately acquired audio track.
 */
export interface MediaAcquisitionFacts {
  mode: MediaAcquisitionMode;
  primaryTrack: MediaAcquisitionTrack;
  pairedTrack?: MediaAcquisitionTrack;
}

export interface MediaEvidence {
  kind: string;
  value: string;
}

export interface MediaFrameContext {
  frameType?: string;
  frameUrl?: string;
  isMainFrame?: boolean;
}

export interface MediaAuthContext {
  pageUrl: string;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
  responseHeaders?: Record<string, string>;
}

export interface MediaManifestContext {
  manifestText?: string;
  manifestBaseUrl?: string;
  pairedAudioUrl?: string;
  pairedAudioMimeType?: string;
  codecs?: string;
  bandwidth?: number;
  contentLength?: number;
  fps?: number;
  initializationRange?: string;
  indexRange?: string;
  pairedAudioCodecs?: string;
  pairedAudioBandwidth?: number;
  pairedAudioContentLength?: number;
  pairedAudioSampleRate?: number;
  pairedAudioChannels?: number;
  pairedAudioInitializationRange?: string;
  pairedAudioIndexRange?: string;
}

export interface MediaPlaybackMetadata {
  displayName?: string;
  sourceHost?: string;
  extension?: string;
  mimeType?: string;
  contentDisposition?: string;
  totalBytes?: number;
  durationMs?: number;
  width?: number;
  height?: number;
  posterUrl?: string;
}

export interface NativeMediaIdentity {
  site: string;
  mediaId: string;
  title?: string;
  requiresMux?: boolean;
}

export interface MediaCandidate {
  id: string;
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  url: string;
  kind: MediaCandidateKind;
  family: MediaCandidateFamily;
  source: MediaSignalSourceKind;
  evidence: MediaEvidence[];
  confidence: number;
  detectionState: MediaDetectionState;
  playabilityState: MediaPlayabilityState;
  downloadabilityState: MediaDownloadabilityState;
  actionHints: MediaActionHint[];
  frameContext?: MediaFrameContext;
  authContext?: MediaAuthContext;
  manifestContext?: MediaManifestContext;
  playbackMetadata?: MediaPlaybackMetadata;
  nativeIdentity?: NativeMediaIdentity;
  acquisition?: MediaAcquisitionFacts;
  validation?: MediaCandidateValidationSnapshot;
  firstSeenAt: number;
  lastSeenAt: number;
}
