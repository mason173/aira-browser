export type SiteIconCandidateSource =
  'arkweb' |
  'override' |
  'manifest' |
  'appleTouch' |
  'documentIcon' |
  'rootAppleTouch' |
  'rootIcon' |
  'remoteFallback';

export type SiteIconCacheState =
  'memory' |
  'disk' |
  'network';

export type SiteIconNetworkPolicy =
  'cacheOnly' |
  'remoteAllowed';

export type SiteIconListResolutionPolicy =
  'memoryOnly' |
  'cacheOnly' |
  'remoteAllowed';

export interface SiteIconCandidate {
  url: string;
  source: SiteIconCandidateSource;
  size: number;
  scalable: boolean;
  purpose: string;
}

export interface SiteIconDocumentDiscovery {
  iconCandidates: SiteIconCandidate[];
  manifestUrls: string[];
}

export interface SiteIconResult {
  uri: string;
  domain: string;
  source: SiteIconCandidateSource;
  iconUrl?: string;
  cacheState: SiteIconCacheState;
  qualityScore: number;
  width: number;
  height: number;
}

export interface SiteIconCacheMetadata {
  source: SiteIconCandidateSource;
  iconUrl: string;
  extension: string;
  qualityScore: number;
  width?: number;
  height?: number;
  updatedAt: number;
  lastAccessedAt?: number;
}

export interface SiteIconMetadataRecord {
  domain: string;
  iconUrl: string;
  source: SiteIconCandidateSource;
  extension: string;
  fileUri: string;
  qualityScore: number;
  width: number;
  height: number;
  lastAccessedAt: number;
  updatedAt: number;
}

export interface SiteIconResolveOptions {
  networkPolicy?: SiteIconNetworkPolicy;
  allowRemoteFallback?: boolean;
  allowRootIconFallback?: boolean;
  maxManifestUrls?: number;
  maxIconCandidates?: number;
  privateMode?: boolean;
}

export interface SiteIconCachedFile {
  path: string;
  uri: string;
  cacheState: SiteIconCacheState;
  source?: SiteIconCandidateSource;
  iconUrl?: string;
  extension?: string;
  qualityScore?: number;
  width?: number;
  height?: number;
  updatedAt?: number;
  lastAccessedAt?: number;
}

export interface SiteIconUriCacheEntry {
  url: string;
  uri: string;
}

export interface SiteIconDomainUriCacheEntry {
  domain: string;
  uri: string;
}

export interface SiteIconCachePruneOptions {
  maxFiles: number;
  maxBytes: number;
}

export interface SiteIconCachePruneResult {
  scannedFiles: number;
  retainedFiles: number;
  removedFiles: number;
  scannedBytes: number;
  retainedBytes: number;
  removedBytes: number;
}
