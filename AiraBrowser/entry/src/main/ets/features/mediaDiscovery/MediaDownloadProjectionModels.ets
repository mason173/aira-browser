import {
  MediaActionHint,
  MediaAcquisitionFacts,
  MediaCandidateFamily,
  MediaCandidateKind
} from './MediaCandidateModels';

export interface MediaDownloadCandidate {
  candidateId: string;
  tabId: string;
  pageUrl: string;
  url: string;
  family: MediaCandidateFamily;
  kind: MediaCandidateKind;
  acquisition?: MediaAcquisitionFacts;
  actions: MediaActionHint[];
  score: number;
  displayName: string;
  sourceHost: string;
  totalBytes?: number;
  estimatedTotalBytes?: number;
  durationMs?: number;
  mimeType?: string;
  contentDisposition?: string;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
}
