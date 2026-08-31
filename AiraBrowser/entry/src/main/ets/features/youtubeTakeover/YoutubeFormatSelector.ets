import { YoutubeFormat, YoutubePlaybackPlan } from './YoutubeModels';

export interface YoutubeFormatSelection {
  progressive?: YoutubeFormat;
  video?: YoutubeFormat;
  audio?: YoutubeFormat;
}

function pixelArea(format: YoutubeFormat): number {
  const w = format.width ?? 0;
  const h = format.height ?? 0;
  return w * h;
}

function effectiveBitrate(format: YoutubeFormat): number {
  return format.bitrate ?? 0;
}

function normalizedMime(format: YoutubeFormat): string {
  const semi = format.mimeType.indexOf(';');
  return (semi >= 0 ? format.mimeType.substring(0, semi) : format.mimeType).trim().toLowerCase();
}

function normalizedCodecs(format: YoutubeFormat): string {
  return (format.codecs ?? '').toLowerCase();
}

function hasVideoCodec(codecs: string): boolean {
  return codecs.indexOf('avc1') >= 0 || codecs.indexOf('h264') >= 0 ||
    codecs.indexOf('hev1') >= 0 || codecs.indexOf('hvc1') >= 0 ||
    codecs.indexOf('vp9') >= 0 || codecs.indexOf('vp09') >= 0 ||
    codecs.indexOf('av01') >= 0;
}

function hasAudioCodec(codecs: string): boolean {
  return codecs.indexOf('mp4a') >= 0 || codecs.indexOf('opus') >= 0 ||
    codecs.indexOf('vorbis') >= 0 || codecs.indexOf('aac') >= 0;
}

function hasPlayableContainer(format: YoutubeFormat): boolean {
  const mime = normalizedMime(format);
  return mime === 'video/mp4';
}

function isExpired(format: YoutubeFormat): boolean {
  const expiresAtMs = format.expiresAtMs ?? 0;
  return expiresAtMs > 0 && expiresAtMs <= Date.now() + 60000;
}

function isDurationDamaged(format: YoutubeFormat, planDurationMs: number | undefined): boolean {
  if (planDurationMs === undefined || !isFinite(planDurationMs) || planDurationMs <= 0) {
    return false;
  }
  const formatDurationMs = format.durationMs;
  if (formatDurationMs === undefined || !isFinite(formatDurationMs) || formatDurationMs <= 0) {
    return false;
  }
  if (formatDurationMs >= planDurationMs * 0.75) {
    return false;
  }
  return planDurationMs - formatDurationMs > 30000;
}

function compareDesc(a: number, b: number): number {
  if (a === b) {
    return 0;
  }
  return a < b ? 1 : -1;
}

export class YoutubeFormatSelector {
  selectDefault(plan: YoutubePlaybackPlan): YoutubeFormatSelection {
    const selection: YoutubeFormatSelection = {};
    selection.progressive = this.pickBestProgressive(plan.progressiveFormats, plan.durationMs);
    selection.video = this.pickBestVideoOnly(plan.videoOnlyFormats, plan.durationMs);
    selection.audio = this.pickBestAudio(plan.audioOnlyFormats, plan.durationMs);
    return selection;
  }

  pickBestProgressive(formats: YoutubeFormat[], planDurationMs: number | undefined = undefined): YoutubeFormat | undefined {
    const playable = this.filterSafeProgressive(formats, planDurationMs);
    if (playable.length === 0) {
      return undefined;
    }
    playable.sort((a: YoutubeFormat, b: YoutubeFormat): number => {
      const areaCmp = compareDesc(pixelArea(a), pixelArea(b));
      if (areaCmp !== 0) {
        return areaCmp;
      }
      return compareDesc(effectiveBitrate(a), effectiveBitrate(b));
    });
    return playable[0];
  }

  pickBestVideoOnly(formats: YoutubeFormat[], planDurationMs: number | undefined = undefined): YoutubeFormat | undefined {
    const playable = this.preferNativeDashVideo(this.filterDirectFormats(formats, planDurationMs));
    if (playable.length === 0) {
      return undefined;
    }
    playable.sort((a: YoutubeFormat, b: YoutubeFormat): number => {
      const areaCmp = compareDesc(pixelArea(a), pixelArea(b));
      if (areaCmp !== 0) {
        return areaCmp;
      }
      return compareDesc(effectiveBitrate(a), effectiveBitrate(b));
    });
    return playable[0];
  }

  pickBestAudio(formats: YoutubeFormat[], planDurationMs: number | undefined = undefined): YoutubeFormat | undefined {
    const playable = this.preferNativeDashAudio(this.filterDirectFormats(formats, planDurationMs));
    if (playable.length === 0) {
      return undefined;
    }
    playable.sort((a: YoutubeFormat, b: YoutubeFormat): number => {
      return compareDesc(effectiveBitrate(a), effectiveBitrate(b));
    });
    return playable[0];
  }

  isSafeProgressiveDirectFormat(format: YoutubeFormat | undefined): boolean {
    if (format === undefined) {
      return false;
    }
    if (format.trackKind !== 'progressive' || format.url.length <= 0) {
      return false;
    }
    if (format.signatureCipher !== undefined && format.signatureCipher.length > 0) {
      return false;
    }
    if (format.requiresPoToken || format.requiresNChallenge || isExpired(format) || !hasPlayableContainer(format)) {
      return false;
    }
    const codecs = normalizedCodecs(format);
    return hasVideoCodec(codecs) && hasAudioCodec(codecs);
  }

  private filterSafeProgressive(formats: YoutubeFormat[], planDurationMs: number | undefined): YoutubeFormat[] {
    const out: YoutubeFormat[] = [];
    for (let i = 0; i < formats.length; i++) {
      const fmt = formats[i];
      if (this.isSafeProgressiveDirectFormat(fmt) && !isDurationDamaged(fmt, planDurationMs)) {
        out.push(fmt);
      }
    }
    return out;
  }

  private filterDirectFormats(formats: YoutubeFormat[], planDurationMs: number | undefined): YoutubeFormat[] {
    const out: YoutubeFormat[] = [];
    for (let i = 0; i < formats.length; i++) {
      const fmt = formats[i];
      if (fmt.url.length > 0 && (fmt.signatureCipher === undefined || fmt.signatureCipher.length <= 0) &&
        !fmt.requiresPoToken && !fmt.requiresNChallenge && !isExpired(fmt) && !isDurationDamaged(fmt, planDurationMs)) {
        out.push(fmt);
      }
    }
    return out;
  }

  private preferNativeDashVideo(formats: YoutubeFormat[]): YoutubeFormat[] {
    const nativeFormats: YoutubeFormat[] = [];
    for (let i = 0; i < formats.length; i++) {
      const fmt = formats[i];
      const mime = normalizedMime(fmt);
      const codecs = normalizedCodecs(fmt);
      if (fmt.trackKind === 'video' && mime === 'video/mp4' &&
        (codecs.indexOf('avc1') >= 0 || codecs.indexOf('h264') >= 0)) {
        nativeFormats.push(fmt);
      }
    }
    return nativeFormats.length > 0 ? nativeFormats : formats;
  }

  private preferNativeDashAudio(formats: YoutubeFormat[]): YoutubeFormat[] {
    const nativeFormats: YoutubeFormat[] = [];
    for (let i = 0; i < formats.length; i++) {
      const fmt = formats[i];
      const mime = normalizedMime(fmt);
      const codecs = normalizedCodecs(fmt);
      if (fmt.trackKind === 'audio' && mime === 'audio/mp4' &&
        (codecs.indexOf('mp4a') >= 0 || codecs.indexOf('aac') >= 0)) {
        nativeFormats.push(fmt);
      }
    }
    return nativeFormats.length > 0 ? nativeFormats : formats;
  }
}
