export type YoutubeFormatTrackKind = 'progressive' | 'video' | 'audio';

export interface YoutubeFormat {
  itag: number;
  url: string;
  signatureCipher?: string;
  mimeType: string;
  codecs?: string;
  container?: string;
  bitrate?: number;
  width?: number;
  height?: number;
  fps?: number;
  audioSampleRate?: number;
  audioChannels?: number;
  contentLength?: number;
  initializationRange?: string;
  indexRange?: string;
  durationMs?: number;
  qualityLabel?: string;
  trackKind: YoutubeFormatTrackKind;
  requiresPoToken: boolean;
  hasPoToken: boolean;
  requiresNChallenge: boolean;
  sourceClient?: string;
  expiresAtMs?: number;
}

export type YoutubePlanStatus =
  | 'ok'
  | 'requires_po_token'
  | 'signature_failed'
  | 'drm_protected'
  | 'expired'
  | 'format_unavailable'
  | 'no_streaming_data';

export interface YoutubePlaybackPlan {
  status: YoutubePlanStatus;
  videoId: string;
  pageUrl: string;
  title: string;
  durationMs?: number;
  posterUrl?: string;
  progressiveFormats: YoutubeFormat[];
  videoOnlyFormats: YoutubeFormat[];
  audioOnlyFormats: YoutubeFormat[];
  hlsManifestUrl?: string;
  dashManifestUrl?: string;
  expiresAtMs?: number;
  sourceClient?: string;
  reason?: string;
  userAgent?: string;
}

export interface YoutubePageProbeResult {
  ok: boolean;
  videoId?: string;
  pageUrl: string;
  title?: string;
  playerResponseJson?: string;
  innertubeApiKey?: string;
  innertubeClientName?: string;
  innertubeClientVersion?: string;
  playerJsUrl?: string;
  visitorData?: string;
  userAgent?: string;
  error?: string;
}

export interface YoutubeVideoplaybackHint {
  url: string;
  itag?: number;
  mime?: string;
  contentLength?: number;
  durationMs?: number;
  expireSeconds?: number;
}
