import { MediaCandidate } from '../../features/mediaDiscovery/MediaCandidateModels';

export class MediaCandidateValidationFingerprintService {
  build(candidate: MediaCandidate): string {
    const parts: string[] = [];
    this.append(parts, 'kind', candidate.kind);
    this.append(parts, 'family', candidate.family);
    this.append(parts, 'url', this.normalizeUrl(candidate.url));
    this.append(parts, 'mime', candidate.playbackMetadata?.mimeType ?? '');
    this.append(parts, 'extension', candidate.playbackMetadata?.extension ?? '');
    this.append(parts, 'manifestBase', candidate.manifestContext?.manifestBaseUrl ?? '');
    this.append(parts, 'manifestText', this.manifestTextSignature(candidate.manifestContext?.manifestText));
    this.append(parts, 'referer', candidate.authContext?.referer ?? '');
    this.append(parts, 'userAgent', candidate.authContext?.userAgent ?? '');
    this.append(parts, 'originUrl', candidate.authContext?.originUrl ?? '');
    this.appendHeaders(parts, candidate.authContext?.requestHeaders);
    return this.hash(parts.join('\n'));
  }

  private append(parts: string[], name: string, value: string): void {
    parts.push(name + '=' + value.trim());
  }

  private appendHeaders(parts: string[], headers: Record<string, string> | undefined): void {
    if (headers === undefined) {
      return;
    }
    const allowed = ['authorization', 'cookie', 'origin', 'range', 'referer', 'user-agent'];
    const keys = Object.keys(headers).sort();
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim();
      const lower = key.toLowerCase();
      if (allowed.indexOf(lower) < 0) {
        continue;
      }
      const value = headers[keys[i]]?.trim() ?? '';
      if (value.length > 0) {
        parts.push('header:' + lower + '=' + value);
      }
    }
  }

  private normalizeUrl(url: string): string {
    const trimmed = url.trim();
    const fragmentIndex = trimmed.indexOf('#');
    return fragmentIndex >= 0 ? trimmed.substring(0, fragmentIndex) : trimmed;
  }

  private manifestTextSignature(text: string | undefined): string {
    if (text === undefined || text.length <= 0) {
      return '';
    }
    const prefix = text.substring(0, Math.min(text.length, 4096));
    return text.length.toString() + ':' + this.hash(prefix);
  }

  private hash(value: string): string {
    let hash = 2166136261;
    for (let i = 0; i < value.length; i++) {
      hash ^= value.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }
}
