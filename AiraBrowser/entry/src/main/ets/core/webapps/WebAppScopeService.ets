export interface WebAppScopeMatchResult {
  inScope: boolean;
  reason: string;
}

export class WebAppScopeService {
  isInScope(targetUrl: string, scope: string, origin: string): WebAppScopeMatchResult {
    const url = targetUrl.trim();
    if (url.length === 0) {
      return { inScope: false, reason: 'empty_target' };
    }
    const normalizedOrigin = this.extractOrigin(origin.length > 0 ? origin : scope);
    const targetOrigin = this.extractOrigin(url);
    if (normalizedOrigin.length === 0 || targetOrigin.length === 0) {
      return { inScope: false, reason: 'origin_missing' };
    }
    if (normalizedOrigin !== targetOrigin) {
      return { inScope: false, reason: 'cross_origin' };
    }
    const normalizedScope = scope.trim();
    if (normalizedScope.length === 0) {
      return { inScope: true, reason: 'origin_match' };
    }
    if (!this.startsWithIgnoringTrailingSlash(url, normalizedScope)) {
      return { inScope: false, reason: 'outside_scope_prefix' };
    }
    return { inScope: true, reason: 'scope_prefix_match' };
  }

  extractOrigin(url: string): string {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const match = /^([a-z]+:\/\/[^/?#]+)/i.exec(trimmed);
    if (match === null) {
      return '';
    }
    return match[1];
  }

  private startsWithIgnoringTrailingSlash(targetUrl: string, scope: string): boolean {
    if (targetUrl.startsWith(scope)) {
      return true;
    }
    if (scope.endsWith('/') && targetUrl === scope.substring(0, scope.length - 1)) {
      return true;
    }
    return false;
  }
}
