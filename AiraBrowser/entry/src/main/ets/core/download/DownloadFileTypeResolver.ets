export type DownloadFileType =
  | 'archive'
  | 'video'
  | 'audio'
  | 'image'
  | 'pdf'
  | 'document'
  | 'spreadsheet'
  | 'presentation'
  | 'web'
  | 'json'
  | 'text'
  | 'apk'
  | 'hap'
  | 'unknown';

const ARCHIVE_EXTENSIONS: string[] = ['.zip', '.rar', '.7z', '.gz', '.tar'];
const VIDEO_EXTENSIONS: string[] = ['.mp4', '.m4v', '.webm', '.mov', '.mkv'];
const AUDIO_EXTENSIONS: string[] = ['.mp3', '.m4a', '.wav', '.flac'];
const IMAGE_EXTENSIONS: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.svg'];
const DOCUMENT_EXTENSIONS: string[] = ['.doc', '.docx'];
const SPREADSHEET_EXTENSIONS: string[] = ['.xls', '.xlsx'];
const PRESENTATION_EXTENSIONS: string[] = ['.ppt', '.pptx'];
const WEB_EXTENSIONS: string[] = ['.html', '.htm', '.xhtml', '.css', '.js', '.mjs', '.ts', '.jsx', '.tsx', '.xml'];
const JSON_EXTENSIONS: string[] = ['.json', '.jsonl'];
const TEXT_EXTENSIONS: string[] = ['.txt', '.md', '.markdown', '.csv', '.log', '.rtf'];
const APK_EXTENSIONS: string[] = ['.apk'];
const HAP_EXTENSIONS: string[] = ['.hap'];

export function resolveDownloadFileType(fileName: string, mimeType?: string): DownloadFileType {
  const extension = resolveFileExtension(fileName);
  const byExtension = resolveFileTypeByExtension(extension);
  if (byExtension !== 'unknown') {
    return byExtension;
  }
  return resolveFileTypeByMimeType(mimeType);
}

function resolveFileExtension(fileName: string): string {
  const normalized = fileName.trim().toLowerCase();
  const dotIndex = normalized.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex >= normalized.length - 1) {
    return '';
  }
  return normalized.substring(dotIndex);
}

function resolveFileTypeByExtension(extension: string): DownloadFileType {
  if (ARCHIVE_EXTENSIONS.indexOf(extension) >= 0) return 'archive';
  if (VIDEO_EXTENSIONS.indexOf(extension) >= 0) return 'video';
  if (AUDIO_EXTENSIONS.indexOf(extension) >= 0) return 'audio';
  if (IMAGE_EXTENSIONS.indexOf(extension) >= 0) return 'image';
  if (extension === '.pdf') return 'pdf';
  if (DOCUMENT_EXTENSIONS.indexOf(extension) >= 0) return 'document';
  if (SPREADSHEET_EXTENSIONS.indexOf(extension) >= 0) return 'spreadsheet';
  if (PRESENTATION_EXTENSIONS.indexOf(extension) >= 0) return 'presentation';
  if (WEB_EXTENSIONS.indexOf(extension) >= 0) return 'web';
  if (JSON_EXTENSIONS.indexOf(extension) >= 0) return 'json';
  if (TEXT_EXTENSIONS.indexOf(extension) >= 0) return 'text';
  if (APK_EXTENSIONS.indexOf(extension) >= 0) return 'apk';
  if (HAP_EXTENSIONS.indexOf(extension) >= 0) return 'hap';
  return 'unknown';
}

function resolveFileTypeByMimeType(mimeType?: string): DownloadFileType {
  const normalized = mimeType?.trim().toLowerCase() ?? '';
  if (normalized === 'application/pdf') return 'pdf';
  if (normalized === 'application/zip' || normalized === 'application/vnd.rar' ||
    normalized === 'application/x-7z-compressed' || normalized === 'application/gzip' ||
    normalized === 'application/x-tar') return 'archive';
  if (normalized.indexOf('video/') === 0) return 'video';
  if (normalized.indexOf('audio/') === 0) return 'audio';
  if (normalized.indexOf('image/') === 0) return 'image';
  if (normalized === 'application/json' || normalized === 'application/ld+json' ||
    normalized === 'application/manifest+json') return 'json';
  if (normalized === 'text/html' || normalized === 'application/xhtml+xml' ||
    normalized === 'text/css' || normalized === 'text/javascript' ||
    normalized === 'application/javascript' || normalized === 'application/xml' ||
    normalized === 'text/xml') return 'web';
  if (normalized.indexOf('text/') === 0) return 'text';
  if (normalized.indexOf('word') >= 0 || normalized === 'application/msword') return 'document';
  if (normalized.indexOf('spreadsheet') >= 0 || normalized.indexOf('excel') >= 0) return 'spreadsheet';
  if (normalized.indexOf('presentation') >= 0 || normalized.indexOf('powerpoint') >= 0) return 'presentation';
  if (normalized === 'application/vnd.android.package-archive') return 'apk';
  if (normalized === 'application/x-hap' || normalized === 'application/vnd.huawei.hap') return 'hap';
  return 'unknown';
}
