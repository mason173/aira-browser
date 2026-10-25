import { MediaCandidate } from './MediaCandidateModels';

export interface MediaResourceName {
  displayName: string;
  fileName: string;
  usesTitle: boolean;
}

const MEDIA_NAME_EXTENSION: RegExp = /\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm|flv|hlv|f4v|mkv|avi|wmv|asf|mpeg|mpg|mpeg4|divx|ogv|ts|m4s)$/i;

// Page titles are evidence about the page, not every resource on it. Only use
// them for video/manifest names that carry no useful human-readable description.
export function resolveMediaResourceName(candidate: MediaCandidate, originalName: string): MediaResourceName {
  if (candidate.family !== 'video' && candidate.family !== 'manifest') {
    return { displayName: originalName, fileName: originalName, usesTitle: false };
  }
  const specificTitle = usableTitle(candidate.nativeIdentity?.title) || usableTitle(candidate.playbackMetadata?.mediaTitle);
  const title = specificTitle || (isOpaqueMediaName(originalName) ? usableTitle(candidate.pageTitle) : '');
  const displayName = title.length > 0 ? title : originalName;
  const extension = candidate.kind === 'hls' ? 'ts' : mediaExtension(candidate, originalName);
  let fileName = displayName;
  if (title.length > 0 || candidate.kind === 'hls') {
    const stem = displayName.replace(MEDIA_NAME_EXTENSION, '');
    fileName = (stem || 'video') + (extension.length > 0 ? '.' + extension : '');
  }
  return { displayName: displayName, fileName: fileName, usesTitle: title.length > 0 };
}

function isOpaqueMediaName(value: string): boolean {
  const base = value.trim().replace(/\.[A-Za-z0-9]{1,8}$/, '');
  if (base.length <= 0 || /^(?:index|master|playlist|mixed|video|movie|stream|media|play|player|download|file|videoplayback|chunklist|manifest)(?:[-_]\d+(?:p|k)?)?$/i.test(base)) {
    return true;
  }
  const compact = base.replace(/[-_]/g, '');
  if (/^\d{6,}$/.test(compact) || /^[a-f\d]{12,}$/i.test(compact)) {
    return true;
  }
  // Keep ordinary words, dates, episode names and non-Latin titles intact.
  // Conservatively recognize long CDN identifiers with a high digit density.
  const digits = compact.replace(/\D/g, '').length;
  return compact.length >= 20 && /^[a-z\d]+$/i.test(compact) && digits >= compact.length / 4;
}

function usableTitle(value: string | undefined): string {
  let title = (value ?? '').substring(0, 512)
    .replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, '')
    .replace(/[\\/:*?"<>|]/g, '_').replace(/\s+/g, ' ').trim().replace(/^[. ]+|[. ]+$/g, '');
  if (title.length <= 0 || /^(?:https?:|blob:)/i.test(value?.trim() ?? '') ||
    /^(?:video|video player|player|play|untitled|loading\.*|视频|视频播放器|播放器|播放|无标题|加载中\.*)$/i.test(title)) {
    return '';
  }
  // Leave room for the extension and collision suffix within common 255-byte
  // filesystem limits. Count UTF-8 bytes without splitting surrogate pairs.
  let bytes = 0;
  let end = 0;
  while (end < title.length) {
    const code = title.charCodeAt(end);
    const pair = code >= 0xd800 && code <= 0xdbff && end + 1 < title.length &&
      title.charCodeAt(end + 1) >= 0xdc00 && title.charCodeAt(end + 1) <= 0xdfff;
    const size = pair ? 4 : code < 0x80 ? 1 : code < 0x800 ? 2 : 3;
    if (bytes + size > 200) {
      break;
    }
    bytes += size;
    end += pair ? 2 : 1;
  }
  title = title.substring(0, end).replace(/[. ]+$/g, '');
  return title;
}

function mediaExtension(candidate: MediaCandidate, originalName: string): string {
  const mime = (candidate.playbackMetadata?.mimeType ?? '').split(';')[0].trim().toLowerCase();
  if (mime === 'video/mp4') return 'mp4';
  if (mime === 'video/webm') return 'webm';
  if (mime === 'video/quicktime') return 'mov';
  if (mime === 'video/x-matroska') return 'mkv';
  if (mime === 'video/x-flv') return 'flv';
  if (mime === 'video/mp2t') return 'ts';
  if (mime === 'video/mpeg') return 'mpeg';
  if (mime === 'video/ogg') return 'ogv';
  const hints: string[] = ['.' + (candidate.playbackMetadata?.extension ?? ''), originalName,
    candidate.url.split('?')[0].split('#')[0], '.' + candidate.kind];
  for (let i = 0; i < hints.length; i++) {
    const match = MEDIA_NAME_EXTENSION.exec(hints[i]);
    if (match !== null) {
      return match[0].substring(1).toLowerCase();
    }
  }
  return '';
}
