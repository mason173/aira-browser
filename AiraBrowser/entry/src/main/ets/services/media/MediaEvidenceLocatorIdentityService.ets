export interface MediaEvidenceLocatorIdentity {
  identity: string;
  safeLocator: string;
  hasQuery: boolean;
}

export class MediaEvidenceLocatorIdentityService {
  resolve(value: string | undefined): MediaEvidenceLocatorIdentity | undefined {
    const trimmed = (value ?? '').trim();
    if (trimmed.length <= 0) {
      return undefined;
    }
    const bounded = trimmed.length <= 4096 ? trimmed : trimmed.substring(0, 4096);
    const queryIndex = bounded.indexOf('?');
    const fragmentIndex = bounded.indexOf('#');
    let safeEnd = bounded.length;
    if (queryIndex >= 0) {
      safeEnd = Math.min(safeEnd, queryIndex);
    }
    if (fragmentIndex >= 0) {
      safeEnd = Math.min(safeEnd, fragmentIndex);
    }
    const identity: MediaEvidenceLocatorIdentity = {
      identity: 'locator:' + this.fingerprint(bounded),
      safeLocator: this.buildSafeLocator(bounded.substring(0, safeEnd)),
      hasQuery: queryIndex >= 0 && (fragmentIndex < 0 || queryIndex < fragmentIndex)
    };
    return identity;
  }

  private buildSafeLocator(locator: string): string {
    const lower = locator.toLowerCase();
    if (lower.indexOf('data:') === 0 || lower.indexOf('javascript:') === 0 ||
      lower.indexOf('blob:') === 0) {
      const separatorIndex = locator.indexOf(':');
      return locator.substring(0, separatorIndex + 1) + '<redacted>';
    }
    const schemeSeparatorIndex = locator.indexOf('://');
    if (schemeSeparatorIndex > 0) {
      const scheme = locator.substring(0, schemeSeparatorIndex).toLowerCase();
      const authorityStart = schemeSeparatorIndex + 3;
      const pathIndex = locator.indexOf('/', authorityStart);
      const authorityEnd = pathIndex >= 0 ? pathIndex : locator.length;
      let authority = locator.substring(authorityStart, authorityEnd);
      const userInfoIndex = authority.lastIndexOf('@');
      if (userInfoIndex >= 0) {
        authority = authority.substring(userInfoIndex + 1);
      }
      const safeAuthority = authority.length > 0 ? authority.toLowerCase() : '<redacted-host>';
      return scheme + '://' + safeAuthority + (pathIndex >= 0 ? '/<redacted-path>' : '');
    }
    const schemeIndex = locator.indexOf(':');
    if (schemeIndex > 0 && schemeIndex <= 24) {
      return locator.substring(0, schemeIndex + 1).toLowerCase() + '<redacted>';
    }
    return '<relative-locator>';
  }

  private fingerprint(locator: string): string {
    let hashA = 2166136261;
    let hashB = 5381;
    for (let i = 0; i < locator.length; i++) {
      const code = locator.charCodeAt(i);
      hashA = ((hashA << 5) - hashA + code) >>> 0;
      hashB = (((hashB << 5) + hashB) ^ code) >>> 0;
    }
    return hashA.toString(36) + ':' + hashB.toString(36) + ':' + locator.length.toString(36);
  }
}
