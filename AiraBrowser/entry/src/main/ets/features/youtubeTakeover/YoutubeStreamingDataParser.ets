import {
  YoutubeFormat,
  YoutubeFormatTrackKind,
  YoutubePlaybackPlan,
  YoutubePlanStatus
} from './YoutubeModels';

interface PlayerResponseFormat {
  itag?: number;
  url?: string;
  signatureCipher?: string;
  cipher?: string;
  mimeType?: string;
  bitrate?: number;
  averageBitrate?: number;
  width?: number;
  height?: number;
  fps?: number;
  qualityLabel?: string;
  audioSampleRate?: string | number;
  audioChannels?: number;
  contentLength?: string | number;
  initRange?: PlayerResponseRange;
  indexRange?: PlayerResponseRange;
  approxDurationMs?: string | number;
}

interface PlayerResponseRange {
  start?: string | number;
  end?: string | number;
}

interface PlayerResponsePlayabilityStatus {
  status?: string;
  reason?: string;
}

interface PlayerResponseVideoDetails {
  title?: string;
  videoId?: string;
  lengthSeconds?: string | number;
  thumbnail?: PlayerResponseThumbnailList;
}

interface PlayerResponseThumbnail {
  url?: string;
  width?: number;
  height?: number;
}

interface PlayerResponseThumbnailList {
  thumbnails?: PlayerResponseThumbnail[];
}

interface PlayerResponseStreamingData {
  expiresInSeconds?: string | number;
  formats?: PlayerResponseFormat[];
  adaptiveFormats?: PlayerResponseFormat[];
  hlsManifestUrl?: string;
  dashManifestUrl?: string;
}

interface PlayerResponseShape {
  playabilityStatus?: PlayerResponsePlayabilityStatus;
  videoDetails?: PlayerResponseVideoDetails;
  streamingData?: PlayerResponseStreamingData;
}

function asNumber(value: string | number | undefined): number | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'number') {
    return isNaN(value) ? undefined : value;
  }
  const parsed = parseFloat(value);
  return isNaN(parsed) ? undefined : parsed;
}

function extractCodecs(mimeType: string | undefined): string | undefined {
  if (mimeType === undefined) {
    return undefined;
  }
  const idx = mimeType.indexOf('codecs=');
  if (idx < 0) {
    return undefined;
  }
  let tail = mimeType.substring(idx + 7).trim();
  if (tail.startsWith('"')) {
    tail = tail.substring(1);
  }
  const endQuote = tail.indexOf('"');
  if (endQuote >= 0) {
    tail = tail.substring(0, endQuote);
  }
  return tail.length > 0 ? tail : undefined;
}

function extractContainer(mimeType: string | undefined): string | undefined {
  if (mimeType === undefined) {
    return undefined;
  }
  const semi = mimeType.indexOf(';');
  const base = (semi >= 0 ? mimeType.substring(0, semi) : mimeType).trim().toLowerCase();
  if (base.startsWith('video/')) {
    return base.substring(6);
  }
  if (base.startsWith('audio/')) {
    return base.substring(6);
  }
  return base;
}

function formatByteRange(range: PlayerResponseRange | undefined): string | undefined {
  const start = asNumber(range?.start);
  const end = asNumber(range?.end);
  if (start === undefined || end === undefined || start < 0 || end < start) {
    return undefined;
  }
  return `${Math.floor(start)}-${Math.floor(end)}`;
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (_error) {
    return value;
  }
}

function hasQueryParameter(url: string, name: string): boolean {
  const queryIndex = url.indexOf('?');
  if (queryIndex < 0) {
    return false;
  }
  const fragmentIndex = url.indexOf('#', queryIndex + 1);
  const query = fragmentIndex >= 0 ? url.substring(queryIndex + 1, fragmentIndex) : url.substring(queryIndex + 1);
  const parts = query.split('&');
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (part.length <= 0) {
      continue;
    }
    const eqIndex = part.indexOf('=');
    const rawName = eqIndex >= 0 ? part.substring(0, eqIndex) : part;
    if (safeDecode(rawName) === name) {
      return true;
    }
  }
  return false;
}

function trackKindFor(mimeType: string | undefined, hasBothVideoAndAudio: boolean): YoutubeFormatTrackKind {
  const base = (mimeType ?? '').toLowerCase();
  if (base.indexOf('video/') === 0) {
    return hasBothVideoAndAudio ? 'progressive' : 'video';
  }
  if (base.indexOf('audio/') === 0) {
    return 'audio';
  }
  return 'progressive';
}

export class YoutubeStreamingDataParser {
  parse(playerResponseJson: string, pageUrl: string, fallbackVideoId: string): YoutubePlaybackPlan {
    const emptyPlan: YoutubePlaybackPlan = {
      status: 'no_streaming_data',
      videoId: fallbackVideoId,
      pageUrl: pageUrl,
      title: '',
      progressiveFormats: [],
      videoOnlyFormats: [],
      audioOnlyFormats: []
    };
    if (playerResponseJson.length === 0) {
      return emptyPlan;
    }
    let parsed: PlayerResponseShape | undefined;
    try {
      parsed = JSON.parse(playerResponseJson) as PlayerResponseShape;
    } catch (_error) {
      return emptyPlan;
    }
    if (parsed === undefined) {
      return emptyPlan;
    }
    const playability = parsed.playabilityStatus;
    const videoDetails = parsed.videoDetails;
    const streamingData = parsed.streamingData;
    const videoId = videoDetails?.videoId ?? fallbackVideoId;
    const title = videoDetails?.title ?? '';
    const thumbnails = videoDetails?.thumbnail?.thumbnails ?? [];
    const posterUrl = thumbnails.length > 0 ? thumbnails[thumbnails.length - 1].url : undefined;
    const lengthSec = asNumber(videoDetails?.lengthSeconds);
    const durationMs = lengthSec !== undefined ? Math.round(lengthSec * 1000) : undefined;

    if (playability !== undefined) {
      const ps = (playability.status ?? '').toUpperCase();
      if (ps === 'UNPLAYABLE' || ps === 'LOGIN_REQUIRED' || ps === 'AGE_VERIFICATION_REQUIRED') {
        const status: YoutubePlanStatus =
          ps === 'LOGIN_REQUIRED' || ps === 'AGE_VERIFICATION_REQUIRED' ? 'requires_po_token' : 'drm_protected';
        return {
          status: status,
          videoId: videoId,
          pageUrl: pageUrl,
          title: title,
          durationMs: durationMs,
          posterUrl: posterUrl,
          progressiveFormats: [],
          videoOnlyFormats: [],
          audioOnlyFormats: [],
          reason: playability.reason
        };
      }
    }

    if (streamingData === undefined) {
      return {
        status: 'no_streaming_data',
        videoId: videoId,
        pageUrl: pageUrl,
        title: title,
        durationMs: durationMs,
        posterUrl: posterUrl,
        progressiveFormats: [],
        videoOnlyFormats: [],
        audioOnlyFormats: [],
        reason: 'streaming_data_missing'
      };
    }

    const expiresInSec = asNumber(streamingData.expiresInSeconds);
    const expiresAtMs = expiresInSec !== undefined ? Date.now() + expiresInSec * 1000 : undefined;
    const progressive: YoutubeFormat[] = [];
    const videoOnly: YoutubeFormat[] = [];
    const audioOnly: YoutubeFormat[] = [];
    const hlsManifestUrl = streamingData.hlsManifestUrl?.trim() ?? '';

    const formatsList = streamingData.formats ?? [];
    for (let i = 0; i < formatsList.length; i++) {
      const fmt = this.buildFormat(formatsList[i], true, expiresAtMs);
      if (fmt !== undefined) {
        progressive.push(fmt);
      }
    }
    const adaptiveList = streamingData.adaptiveFormats ?? [];
    for (let i = 0; i < adaptiveList.length; i++) {
      const fmt = this.buildFormat(adaptiveList[i], false, expiresAtMs);
      if (fmt === undefined) {
        continue;
      }
      if (fmt.trackKind === 'audio') {
        audioOnly.push(fmt);
      } else {
        videoOnly.push(fmt);
      }
    }

    let allHaveCipher = progressive.length > 0;
    for (let i = 0; i < progressive.length; i++) {
      if (progressive[i].url.length > 0) {
        allHaveCipher = false;
        break;
      }
    }
    if (progressive.length === 0 && videoOnly.length === 0 && audioOnly.length === 0) {
      if (hlsManifestUrl.length > 0) {
        return {
          status: 'ok',
          videoId: videoId,
          pageUrl: pageUrl,
          title: title,
          durationMs: durationMs,
          posterUrl: posterUrl,
          progressiveFormats: [],
          videoOnlyFormats: [],
          audioOnlyFormats: [],
          hlsManifestUrl: streamingData.hlsManifestUrl,
          dashManifestUrl: streamingData.dashManifestUrl,
          expiresAtMs: expiresAtMs
        };
      }
      return {
        status: 'no_streaming_data',
        videoId: videoId,
        pageUrl: pageUrl,
        title: title,
        durationMs: durationMs,
        posterUrl: posterUrl,
        progressiveFormats: [],
        videoOnlyFormats: [],
        audioOnlyFormats: [],
        hlsManifestUrl: streamingData.hlsManifestUrl,
        dashManifestUrl: streamingData.dashManifestUrl,
        expiresAtMs: expiresAtMs,
        reason: 'no_formats'
      };
    }
    const hasAnyDirect = this.hasDirectUrl(progressive) || this.hasDirectUrl(videoOnly) || this.hasDirectUrl(audioOnly);
    const status: YoutubePlanStatus = hasAnyDirect || hlsManifestUrl.length > 0 ? 'ok' : 'signature_failed';
    return {
      status: status,
      videoId: videoId,
      pageUrl: pageUrl,
      title: title,
      durationMs: durationMs,
      posterUrl: posterUrl,
      progressiveFormats: progressive,
      videoOnlyFormats: videoOnly,
      audioOnlyFormats: audioOnly,
      hlsManifestUrl: streamingData.hlsManifestUrl,
      dashManifestUrl: streamingData.dashManifestUrl,
      expiresAtMs: expiresAtMs,
      reason: status === 'signature_failed' ? 'all_formats_require_cipher' : undefined
    };
  }

  private hasDirectUrl(list: YoutubeFormat[]): boolean {
    for (let i = 0; i < list.length; i++) {
      if (list[i].url.length > 0) {
        return true;
      }
    }
    return false;
  }

  private buildFormat(raw: PlayerResponseFormat, fromProgressive: boolean, expiresAtMs: number | undefined): YoutubeFormat | undefined {
    if (raw === undefined || raw === null) {
      return undefined;
    }
    const itag = raw.itag;
    if (itag === undefined) {
      return undefined;
    }
    const mimeType = raw.mimeType ?? '';
    const trackKind = trackKindFor(mimeType, fromProgressive);
    const url = raw.url ?? '';
    const signatureCipher = raw.signatureCipher ?? raw.cipher;
    const codecs = extractCodecs(mimeType);
    const container = extractContainer(mimeType);
    const contentLength = asNumber(raw.contentLength);
    const initializationRange = formatByteRange(raw.initRange);
    const indexRange = formatByteRange(raw.indexRange);
    const durationMs = asNumber(raw.approxDurationMs);
    const audioSampleRate = asNumber(raw.audioSampleRate);
    const hasPoToken = hasQueryParameter(url, 'pot') || url.indexOf('/pot/') >= 0;
    const requiresNChallenge = hasQueryParameter(url, 'n');
    return {
      itag: itag,
      url: url,
      signatureCipher: signatureCipher,
      mimeType: mimeType,
      codecs: codecs,
      container: container,
      bitrate: raw.bitrate ?? raw.averageBitrate,
      width: raw.width,
      height: raw.height,
      fps: raw.fps,
      audioSampleRate: audioSampleRate,
      audioChannels: raw.audioChannels,
      contentLength: contentLength,
      initializationRange: initializationRange,
      indexRange: indexRange,
      durationMs: durationMs,
      qualityLabel: raw.qualityLabel,
      trackKind: trackKind,
      requiresPoToken: false,
      hasPoToken: hasPoToken,
      requiresNChallenge: requiresNChallenge,
      expiresAtMs: expiresAtMs
    };
  }
}
