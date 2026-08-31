export type WebSslErrorPolicyAction = 'prompt_user' | 'cancel_request';

export interface WebSslErrorPolicyInput {
  tabId: string;
  activeTabId: string;
  requestUrl: string;
  originalUrl: string;
  referrer: string;
  isMainFrame: boolean;
  isFatalError: boolean;
}

export interface WebSslErrorPolicyDecision {
  action: WebSslErrorPolicyAction;
  abortLoading: boolean;
  diagnosticMessage: string;
}

export class WebSslErrorPolicyService {
  decide(input: WebSslErrorPolicyInput): WebSslErrorPolicyDecision {
    if (input.tabId !== input.activeTabId) {
      return this.buildCancelDecision(input, 'background_tab');
    }
    if (!input.isMainFrame) {
      return this.buildCancelDecision(input, 'subresource');
    }
    return {
      action: 'prompt_user',
      abortLoading: true,
      diagnosticMessage: this.buildDiagnosticMessage(input, 'main_frame_prompt')
    };
  }

  private buildCancelDecision(input: WebSslErrorPolicyInput, reason: string): WebSslErrorPolicyDecision {
    return {
      action: 'cancel_request',
      abortLoading: true,
      diagnosticMessage: this.buildDiagnosticMessage(input, reason)
    };
  }

  private buildDiagnosticMessage(input: WebSslErrorPolicyInput, reason: string): string {
    const url = input.requestUrl.trim().length > 0 ? input.requestUrl.trim() : 'unknown';
    const originalUrl = input.originalUrl.trim().length > 0 ? input.originalUrl.trim() : 'unknown';
    const referrer = input.referrer.trim().length > 0 ? input.referrer.trim() : 'unknown';
    return `sslErrorDecision reason=${reason} tab=${input.tabId} mainFrame=${input.isMainFrame} fatal=${input.isFatalError} url=${url} originalUrl=${originalUrl} referrer=${referrer}`;
  }
}
