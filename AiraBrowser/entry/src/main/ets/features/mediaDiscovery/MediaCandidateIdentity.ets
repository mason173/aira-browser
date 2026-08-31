import { NativeMediaIdentity } from './MediaCandidateModels';

export interface MediaCandidateIdentityInput {
  tabId: string;
  url: string;
  source: string;
  nativeIdentity?: NativeMediaIdentity;
}

export interface MediaCandidateIdentityResolution {
  idKey: string;
  displayKey: string;
}

export class MediaCandidateIdentityService {
  resolve(input: MediaCandidateIdentityInput): MediaCandidateIdentityResolution {
    const nativeIdentity = input.nativeIdentity;
    if (nativeIdentity !== undefined) {
      const site = nativeIdentity.site.trim().toLowerCase();
      const mediaId = nativeIdentity.mediaId.trim();
      if (site.length > 0 && mediaId.length > 0) {
        const displayKey = `native:${site}:${mediaId}`;
        return {
          idKey: displayKey,
          displayKey: displayKey
        };
      }
    }
    const normalizedUrl = this.normalizeUrlKey(input.url);
    if (normalizedUrl.length > 0) {
      const displayKey = `url:${normalizedUrl}`;
      return {
        idKey: displayKey,
        displayKey: displayKey
      };
    }
    const fallbackKey = `source:${input.source}:${input.tabId}`;
    return {
      idKey: fallbackKey,
      displayKey: fallbackKey
    };
  }

  normalizeUrlKey(url: string): string {
    const value = url.trim();
    if (value.length <= 0) {
      return '';
    }
    const fragmentIndex = value.indexOf('#');
    const resourceUrl = fragmentIndex >= 0 ? value.substring(0, fragmentIndex) : value;
    const lower = resourceUrl.toLowerCase();
    if (lower.indexOf('http://') === 0) {
      return 'httpx://' + resourceUrl.substring('http://'.length);
    }
    if (lower.indexOf('https://') === 0) {
      return 'httpx://' + resourceUrl.substring('https://'.length);
    }
    return resourceUrl;
  }
}
