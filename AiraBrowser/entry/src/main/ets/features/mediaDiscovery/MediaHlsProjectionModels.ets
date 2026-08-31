import {
  MediaAcquisitionFacts,
  MediaCandidateFamily,
  MediaCandidateKind
} from './MediaCandidateModels';
import { MediaResourceFrameType } from './MediaResourceProjectionModels';

export type MediaHlsManifestEvidence =
  | 'mime'
  | 'explicit_extension'
  | 'media_element'
  | 'image_element'
  | 'streaming_url_hint'
  | 'generic_url_hint'
  | 'weak_text_match'
  | 'negative';

export interface MediaHlsManifestTarget {
  candidateId: string;
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  frameUrl?: string;
  frameType?: MediaResourceFrameType;
  url: string;
  kind: MediaCandidateKind;
  family: MediaCandidateFamily;
  acquisition?: MediaAcquisitionFacts;
  displayName: string;
  sourceHost: string;
  extension?: string;
  mimeType?: string;
  evidence?: MediaHlsManifestEvidence;
  score: number;
  manifestText?: string;
  manifestBaseUrl?: string;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
}
