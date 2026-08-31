import { UIContext } from '@kit.ArkUI';

export class BrowserSafeBrowsingThreatPresentationService {
  private presentingByTabId: Record<string, boolean | undefined> = {};

  presentIfNeeded(uiContext: UIContext, tabId: string, threatType: ThreatType): void {
    if (threatType !== ThreatType.THREAT_WARNING || this.presentingByTabId[tabId] === true) {
      return;
    }
    this.presentingByTabId[tabId] = true;
    void uiContext.getPromptAction().showDialog({
      title: '此网站可能存在安全风险',
      message: '请谨慎输入密码、验证码或付款信息。确认网站可信后再继续访问。',
      buttons: [{
        text: '知道了',
        color: $r('sys.color.ohos_id_color_text_primary')
      }]
    }).then((): void => {
      this.presentingByTabId[tabId] = undefined;
    }).catch((_error: Error): void => {
      this.presentingByTabId[tabId] = undefined;
    });
  }
}

export const sharedBrowserSafeBrowsingThreatPresentationService: BrowserSafeBrowsingThreatPresentationService =
  new BrowserSafeBrowsingThreatPresentationService();
