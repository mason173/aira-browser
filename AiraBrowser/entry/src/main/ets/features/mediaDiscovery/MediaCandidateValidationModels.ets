export type MediaValidationState =
  | 'unvalidated'
  | 'validating'
  | 'validated_playable'
  | 'validated_resource_only'
  | 'unsupported'
  | 'protected'
  | 'expired'
  | 'failed';

export type MediaValidationKind =
  | 'progressive_http'
  | 'hls_resource_graph'
  | 'dash_resource_graph'
  | 'site_native_identity'
  | 'captured_hls_virtual_graph'
  | 'web_only';

export type MediaValidationFailureCode =
  | 'none'
  | 'non_http_url'
  | 'html_response'
  | 'manifest_fetch_failed'
  | 'manifest_parse_failed'
  | 'child_playlist_failed'
  | 'child_resource_failed'
  | 'key_resource_failed'
  | 'map_resource_failed'
  | 'protected_drm'
  | 'missing_headers'
  | 'unsupported_codec'
  | 'unsupported_delivery'
  | 'expired_url'
  | 'range_probe_failed'
  | 'stale_navigation'
  | 'probe_timeout'
  | 'unknown';

export type MediaValidationProbeKind =
  | 'response_header'
  | 'first_bytes'
  | 'manifest_root'
  | 'manifest_variant'
  | 'hls_key'
  | 'hls_map'
  | 'hls_segment'
  | 'media_element'
  | 'site_native_identity';

export interface MediaValidationProbeEvidence {
  kind: MediaValidationProbeKind;
  url: string;
  ok: boolean;
  statusCode?: number;
  contentType?: string;
  contentLength?: number;
  byteLength?: number;
  message?: string;
}

export interface MediaValidationHlsVariantSummary {
  url: string;
  bandwidth?: number;
  averageBandwidth?: number;
  estimatedBitrate?: number;
  bitrateEstimateSource?: 'average_bandwidth' | 'declared_bandwidth' | 'url_hint';
  durationSeconds?: number;
  estimatedTotalBytes?: number;
}

export interface MediaValidationGraphSummary {
  role?: 'master' | 'media' | 'dash' | 'progressive';
  variantUrls?: string[];
  hlsVariants?: MediaValidationHlsVariantSummary[];
  variantCount?: number;
  probedVariantCount?: number;
  segmentCount?: number;
  durationSeconds?: number;
  sampleSegmentUrl?: string;
  mapUrl?: string;
  keyUrl?: string;
  encrypted?: boolean;
  protectedContent?: boolean;
  live?: boolean;
}

export interface MediaCandidateValidationSnapshot {
  state: MediaValidationState;
  kind: MediaValidationKind;
  fingerprint: string;
  validatedAt: number;
  expiresAt?: number;
  playableUrl?: string;
  manifestBaseUrl?: string;
  failureCode?: MediaValidationFailureCode;
  failureMessage?: string;
  graph?: MediaValidationGraphSummary;
  evidence: MediaValidationProbeEvidence[];
}

export interface MediaCandidateValidationResult {
  candidateId: string;
  tabId: string;
  fingerprint: string;
  snapshot: MediaCandidateValidationSnapshot;
}
