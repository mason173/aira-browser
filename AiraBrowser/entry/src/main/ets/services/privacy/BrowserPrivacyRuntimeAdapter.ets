import { webview } from '@kit.ArkWeb';
import deviceInfo from '@ohos.deviceInfo';

const USER_AGENT_CLIENT_HINTS_MIN_API_VERSION: number = 24;

export class BrowserPrivacyRuntimeAdapter {
  applyClientHintsEnabled(enabled: boolean): boolean {
    if (deviceInfo.sdkApiVersion < USER_AGENT_CLIENT_HINTS_MIN_API_VERSION) {
      return false;
    }
    try {
      webview.WebviewController.setUserAgentClientHintsEnabled(enabled);
      return true;
    } catch (_error) {
      return false;
    }
  }

  applyCookiePolicy(acceptCookies: boolean, acceptThirdPartyCookies: boolean): boolean {
    try {
      webview.WebCookieManager.putAcceptCookieEnabled(acceptCookies);
      webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(acceptThirdPartyCookies);
      webview.WebCookieManager.saveCookieSync();
      return true;
    } catch (_error) {
      return false;
    }
  }
}
