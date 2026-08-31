import {
  MediaActionHint,
  MediaAcquisitionFacts,
  MediaCandidateFamily,
  MediaCandidateKind
} from './MediaCandidateModels';

export type MediaResourceAction = MediaActionHint;

export type MediaResourceSource = 'network' | 'dom' | 'video_adapter' | 'unknown';

export type MediaResourceFrameType =
  | 'main_frame'
  | 'sub_frame'
  | 'dom_frame'
  | 'dom_document'
  | 'unknown';

export type MediaResourceStatus =
  | 'detected'
  | 'playable'
  | 'playing_native'
  | 'downloadable'
  | 'unsupported'
  | 'protected'
  | 'expired'
  | 'needs_processing'
  | 'failed';

export type MediaResourceTab = 'all' | 'video' | 'manifest' | 'audio' | 'image' | 'file';

export interface MediaResourceTabCounts {
  all: number;
  video: number;
  manifest: number;
  audio: number;
  image: number;
  file: number;
}

export interface MediaResourceListItem {
  id: string;
  tabId: string;
  pageTitle: string;
  url: string;
  source: MediaResourceSource;
  frameType?: MediaResourceFrameType;
  family: MediaCandidateFamily;
  kind: MediaCandidateKind;
  status: MediaResourceStatus;
  displayName: string;
  sourceHost: string;
  extension?: string;
  durationMs?: number;
  width?: number;
  height?: number;
  totalBytes?: number;
  estimatedTotalBytes?: number;
  posterUrl?: string;
  acquisition?: MediaAcquisitionFacts;
  failureReason?: string;
  actions: MediaResourceAction[];
}

export interface MediaResourceListProjection {
  items: MediaResourceListItem[];
  counts: MediaResourceTabCounts;
}

export function emptyMediaResourceTabCounts(): MediaResourceTabCounts {
  return {
    all: 0,
    video: 0,
    manifest: 0,
    audio: 0,
    image: 0,
    file: 0
  };
}
