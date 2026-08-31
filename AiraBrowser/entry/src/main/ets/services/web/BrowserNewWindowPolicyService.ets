import { WebRuntimeBridge } from '../../core/web/WebRuntimeBridge';
import {
  BrowserDeviceFormFactorProfile,
  BrowserWindowOpenSurface
} from '../../core/browser/BrowserDeviceFormFactorCoordinator';

export type BrowserNewWindowPolicyDecisionType =
  'ignore' |
  'download' |
  'new_tab' |
  'attached_window_tab' |
  'blocked_popup';

export interface BrowserNewWindowPolicyRequest {
  targetUrl: string;
  isAlert: boolean;
  isUserTriggered: boolean;
  deviceFormFactorProfile: BrowserDeviceFormFactorProfile;
}

export interface BrowserNewWindowPolicyDecision {
  type: BrowserNewWindowPolicyDecisionType;
  targetUrl: string;
  helperMessage: string;
  title: string;
  openedByNewWindow: boolean;
  isUserTriggered: boolean;
  deviceFormFactorProfile: BrowserDeviceFormFactorProfile;
  windowOpenSurface: BrowserWindowOpenSurface;
}

export class BrowserNewWindowPolicyService {
  buildDecision(
    request: BrowserNewWindowPolicyRequest,
    webRuntimeBridge: WebRuntimeBridge
  ): BrowserNewWindowPolicyDecision {
    if (!request.isUserTriggered) {
      return {
        type: 'blocked_popup',
        targetUrl: request.targetUrl.trim(),
        helperMessage: '已拦截弹窗',
        title: '',
        openedByNewWindow: false,
        isUserTriggered: false,
        deviceFormFactorProfile: request.deviceFormFactorProfile,
        windowOpenSurface: this.resolveWindowOpenSurface(request)
      };
    }

    const action = webRuntimeBridge.buildWindowOpenAction(request.targetUrl, request.isAlert);
    if (action.type === 'ignore') {
      return {
        type: 'ignore',
        targetUrl: action.targetUrl,
        helperMessage: action.helperMessage,
        title: action.title,
        openedByNewWindow: false,
        isUserTriggered: true,
        deviceFormFactorProfile: request.deviceFormFactorProfile,
        windowOpenSurface: this.resolveWindowOpenSurface(request)
      };
    }
    if (action.type === 'download' || action.type === 'external') {
      return {
        type: 'download',
        targetUrl: action.targetUrl,
        helperMessage: action.helperMessage,
        title: action.title,
        openedByNewWindow: false,
        isUserTriggered: true,
        deviceFormFactorProfile: request.deviceFormFactorProfile,
        windowOpenSurface: this.resolveWindowOpenSurface(request)
      };
    }
    return {
      type: this.shouldUseArkWebChildWindow(action.targetUrl) ? 'attached_window_tab' : 'new_tab',
      targetUrl: action.targetUrl,
      helperMessage: action.helperMessage,
      title: action.title,
      openedByNewWindow: true,
      isUserTriggered: true,
      deviceFormFactorProfile: request.deviceFormFactorProfile,
      windowOpenSurface: this.resolveWindowOpenSurface(request)
    };
  }

  private resolveWindowOpenSurface(request: BrowserNewWindowPolicyRequest): BrowserWindowOpenSurface {
    if (request.isAlert) {
      return request.deviceFormFactorProfile.alertWindowOpenSurface;
    }
    return request.deviceFormFactorProfile.defaultWindowOpenSurface;
  }

  private shouldUseArkWebChildWindow(targetUrl: string): boolean {
    const normalizedUrl = targetUrl.trim().toLowerCase();
    if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
      return true;
    }
    return false;
  }

  isPopupAuthNavigationTarget(targetUrl: string): boolean {
    return this.isPopupAuthNavigation(targetUrl.trim().toLowerCase());
  }

  private isPopupAuthNavigation(normalizedUrl: string): boolean {
    if (this.isGoogleAccountAuthNavigation(normalizedUrl)) {
      return true;
    }
    return normalizedUrl.indexOf('display=popup') >= 0 ||
      normalizedUrl.indexOf('ux_mode=popup') >= 0 ||
      normalizedUrl.indexOf('response_mode=form_post') >= 0 ||
      (normalizedUrl.indexOf('response_type=') >= 0 && normalizedUrl.indexOf('openid') >= 0);
  }

  private isGoogleAccountAuthNavigation(normalizedUrl: string): boolean {
    return normalizedUrl.indexOf('https://accounts.google.com/gsi/') === 0 ||
      normalizedUrl.indexOf('https://accounts.google.com/o/oauth2/') === 0 ||
      normalizedUrl.indexOf('https://accounts.google.com/o/oauth2/v2/') === 0 ||
      normalizedUrl.indexOf('https://accounts.google.com/signin/oauth/') === 0 ||
      normalizedUrl.indexOf('https://accounts.google.com/v3/signin/') === 0;
  }
}
