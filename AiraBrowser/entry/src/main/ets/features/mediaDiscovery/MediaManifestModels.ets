export type MediaManifestKind = 'hls' | 'dash' | 'unknown';

export type MediaManifestPlaylistRole = 'master' | 'media' | 'dash' | 'unknown';

export interface MediaManifestRequestContext {
  url: string;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
}

export interface MediaManifestVariant {
  index: number;
  url: string;
  bandwidth: number;
  averageBandwidth: number;
  resolution: string;
  codecs: string;
  name: string;
  segmentCount: number;
  targetDuration: number;
  durationSeconds: number;
  encrypted: boolean;
  protectedContent?: boolean;
  sampleSegments?: string[];
  keyUrls?: string[];
  keyMethods?: string[];
  mapUrls?: string[];
}

export interface MediaManifestMediaRendition {
  type: string;
  groupId: string;
  name: string;
  language: string;
  url: string;
}

export interface MediaManifestSummary {
  kind: MediaManifestKind;
  role: MediaManifestPlaylistRole;
  url: string;
  sourceHost: string;
  fetchedAt: number;
  variantCount: number;
  segmentCount: number;
  keyCount: number;
  encrypted: boolean;
  targetDuration: number;
  durationSeconds: number;
  variants: MediaManifestVariant[];
  media: MediaManifestMediaRendition[];
  sampleSegments: string[];
  keyUrls: string[];
  keyMethods: string[];
  mapUrls: string[];
  protectedContent: boolean;
  warnings: string[];
}

export interface MediaManifestParseResult {
  ok: boolean;
  summary?: MediaManifestSummary;
  errorMessage: string;
}

export function emptyMediaManifestSummary(): MediaManifestSummary {
  return {
    kind: 'unknown',
    role: 'unknown',
    url: '',
    sourceHost: '',
    fetchedAt: 0,
    variantCount: 0,
    segmentCount: 0,
    keyCount: 0,
    encrypted: false,
    targetDuration: 0,
    durationSeconds: 0,
    variants: [],
    media: [],
    sampleSegments: [],
    keyUrls: [],
    keyMethods: [],
    mapUrls: [],
    protectedContent: false,
    warnings: []
  };
}
