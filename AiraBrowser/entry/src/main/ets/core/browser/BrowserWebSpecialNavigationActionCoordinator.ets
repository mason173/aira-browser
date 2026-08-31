import {
  BrowserWebComponentNavigationEventSource,
  BrowserWebComponentWebUrlDecision
} from '../web/BrowserWebComponentController';

export interface BrowserWebSpecialNavigationActionInput {
  tabId: string;
  targetUrl: string;
  source: BrowserWebComponentNavigationEventSource;
  isMainFrame: boolean;
}

export interface BrowserWebSpecialNavigationActionHost {
  handleUserScriptInstallNavigation: (url: string, source: string, tabId: string) => boolean;
  handleErrorDocumentActionUrl: (tabId: string, url: string) => boolean;
  isInternalDebugPageUrl: (url: string) => boolean;
}

export interface BrowserWebSpecialNavigationActionCoordinatorOptions {
  host: BrowserWebSpecialNavigationActionHost;
}

export class BrowserWebSpecialNavigationActionCoordinator {
  private readonly host: BrowserWebSpecialNavigationActionHost;

  constructor(options: BrowserWebSpecialNavigationActionCoordinatorOptions) {
    this.host = options.host;
  }

  handleNavigationAction(input: BrowserWebSpecialNavigationActionInput): BrowserWebComponentWebUrlDecision {
    const host = this.host;
    if ((input.source === 'override_url_loading' || input.isMainFrame) &&
      host.handleUserScriptInstallNavigation(input.targetUrl, input.source, input.tabId)) {
      return this.buildConsumeDecision(input.targetUrl, 'consume_extension_action', 'userscript_install_navigation');
    }
    if (input.source === 'override_url_loading' && host.handleErrorDocumentActionUrl(input.tabId, input.targetUrl)) {
      return this.buildConsumeDecision(input.targetUrl, 'consume_internal', 'error_document_action_url');
    }
    if (input.source === 'override_url_loading' && host.isInternalDebugPageUrl(input.targetUrl)) {
      return {
        action: 'rewrite_same_web_navigation',
        targetUrl: input.targetUrl,
        reason: 'internal_debug_page_url'
      };
    }
    return {
      action: 'allow_web',
      targetUrl: input.targetUrl,
      reason: 'no_special_navigation'
    };
  }

  private buildConsumeDecision(
    targetUrl: string,
    action: 'consume_internal' | 'consume_extension_action',
    reason: string
  ): BrowserWebComponentWebUrlDecision {
    return {
      action: action,
      targetUrl: targetUrl,
      reason: reason
    };
  }
}
