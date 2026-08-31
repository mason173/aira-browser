import { WebAppActiveContext } from '../../core/webapps/WebAppSessionCoordinator';
import { WebAppScopeService } from '../../core/webapps/WebAppScopeService';

export interface WebAppScopeGuardDecision {
  intercept: boolean;
  reason: string;
  targetUrl: string;
}

/**
 * Keeps scope metadata visible to the browser layer without automatically
 * handing desktop WebApp navigation to the normal browser.
 */
export class WebAppScopeGuardService {
  private scopeService: WebAppScopeService;

  constructor(scopeService: WebAppScopeService = new WebAppScopeService()) {
    this.scopeService = scopeService;
  }

  evaluate(
    activeContext: WebAppActiveContext | undefined,
    targetUrl: string,
    isMainFrame: boolean
  ): WebAppScopeGuardDecision {
    const normalized = targetUrl.trim();
    if (activeContext === undefined) {
      return { intercept: false, reason: 'no_active_web_app', targetUrl: normalized };
    }
    if (!isMainFrame) {
      return { intercept: false, reason: 'subframe', targetUrl: normalized };
    }
    if (activeContext.scope.length === 0 && activeContext.origin.length === 0) {
      return { intercept: false, reason: 'no_scope_declared', targetUrl: normalized };
    }
    if (normalized.length === 0) {
      return { intercept: false, reason: 'empty_url', targetUrl: normalized };
    }
    if (normalized.toLowerCase().startsWith('about:') || normalized.toLowerCase().startsWith('javascript:') ||
      normalized.toLowerCase().startsWith('data:')) {
      return { intercept: false, reason: 'inert_scheme', targetUrl: normalized };
    }
    const match = this.scopeService.isInScope(normalized, activeContext.scope, activeContext.origin);
    if (match.inScope) {
      return { intercept: false, reason: `in_scope:${match.reason}`, targetUrl: normalized };
    }
    return { intercept: false, reason: `scope_not_enforced:${match.reason}`, targetUrl: normalized };
  }
}
