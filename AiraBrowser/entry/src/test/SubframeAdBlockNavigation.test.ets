import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserWebComponentController,
  BrowserWebComponentControllerHost,
  BrowserWebComponentWebUrlDecision
} from '../main/ets/core/web/BrowserWebComponentController';
import { BrowserUnifiedLinkResult } from '../main/ets/services/web/BrowserUnifiedLinkLogic';

// A fake frame request. Only the accessors the controller reads for a subframe navigation matter.
class FakeFrameRequest {
  private readonly url: string;

  constructor(url: string) {
    this.url = url;
  }

  getRequestUrl(): string {
    return this.url;
  }

  isMainFrame(): boolean {
    return false;
  }

  isRequestGesture(): boolean {
    return false;
  }
}

class FakeOnLoadInterceptEvent {
  readonly data: FakeFrameRequest;

  constructor(url: string) {
    this.data = new FakeFrameRequest(url);
  }
}

class FakeControllerHost implements BrowserWebComponentControllerHost {
  subframeBlockedCalls: number = 0;
  lastPolicyReason: string = '';
  private readonly blockSubframe: boolean;

  constructor(blockSubframe: boolean) {
    this.blockSubframe = blockSubframe;
  }

  resolveWebController(): undefined {
    return undefined;
  }

  isWebControllerAttached(): boolean {
    return true;
  }

  handleWebDialogBack(): boolean {
    return false;
  }

  recordRuntimeEvent(_type: string, message: string, _tabId: string): void {
    // The controller reports its navigation decision here; keep the reason for the assertion.
    const marker = 'reason=';
    const index = message.indexOf(marker);
    if (index >= 0) {
      this.lastPolicyReason = message.substring(index + marker.length).split(' ')[0];
    }
  }

  handleSpecialNavigationAction(): BrowserWebComponentWebUrlDecision {
    return { action: 'allow_web', targetUrl: '', reason: 'test_no_special' };
  }

  canLoadUrlInWebView(): boolean {
    return true;
  }

  shouldBlockSubframeNavigation(_tabId: string, _url: string): boolean {
    this.subframeBlockedCalls += 1;
    return this.blockSubframe;
  }

  handleWebAppScopeOutNavigation(): boolean {
    return false;
  }

  resolveMainFrameWebUrlDecision(): BrowserWebComponentWebUrlDecision {
    return { action: 'allow_web', targetUrl: '', reason: 'test_allow' };
  }

  executeSameWebNavigationRewrite(): boolean {
    return true;
  }

  prepareMainFrameWebNavigation(): boolean {
    return true;
  }

  observeMainFrameWebRequest(): void {}

  evaluateUnifiedLinkNavigation(): BrowserUnifiedLinkResult {
    return {
      handled: false,
      shouldConsumeWebLoad: false,
      action: 'allow_web',
      tabId: '',
      url: '',
      fallbackUrl: '',
      appName: '',
      message: '',
      isUserTriggered: false,
      key: '',
      reason: 'test_noop'
    };
  }

  applyUnifiedLinkNavigationResult(): void {}
}

export default function subframeAdBlockNavigationTest(): void {
  describe('Ad-block subframe navigation', () => {
    // A blocked ad iframe (cool18.com -> ad.parkvv.com/html/iframe.php) must be denied at
    // onLoadIntercept and never fetched. Answering it with a synthesized onInterceptRequest response
    // made ArkWeb classify the frame URL as a download and pop the download-confirm sheet.
    it('denies a blocked subframe navigation before it is fetched', 0, () => {
      const controller = new BrowserWebComponentController('window-main-tab-test');
      const host = new FakeControllerHost(true);
      const consumed = controller.onLoadIntercept(new FakeOnLoadInterceptEvent(
        'https://ad.parkvv.com/html/iframe.php?id=c336280'
      ) as ESObject as never, host as ESObject as never);
      expect(consumed).assertTrue();
      expect(host.subframeBlockedCalls).assertEqual(1);
      expect(host.lastPolicyReason).assertEqual('subframe_adblock_blocked');
    });

    it('allows an ordinary subframe navigation', 0, () => {
      const controller = new BrowserWebComponentController('window-main-tab-test');
      const host = new FakeControllerHost(false);
      const consumed = controller.onLoadIntercept(new FakeOnLoadInterceptEvent(
        'https://example.com/embed'
      ) as ESObject as never, host as ESObject as never);
      expect(consumed).assertFalse();
      expect(host.subframeBlockedCalls).assertEqual(1);
      expect(host.lastPolicyReason).assertEqual('webview_supported_subframe');
    });
  });
}
