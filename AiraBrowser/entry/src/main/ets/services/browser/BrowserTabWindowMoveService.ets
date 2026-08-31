import { Want } from '@kit.AbilityKit';
import {
  BROWSER_TAB_WINDOW_MOVE_DATA_SCOPE_WANT_KEY,
  BROWSER_TAB_WINDOW_MOVE_INSTANCE_ID_WANT_KEY,
  BROWSER_TAB_WINDOW_MOVE_LAUNCH_SOURCE,
  BROWSER_TAB_WINDOW_MOVE_PRIVACY_MODE_WANT_KEY,
  BROWSER_TAB_WINDOW_MOVE_PROFILE_ID_WANT_KEY,
  BROWSER_TAB_WINDOW_MOVE_REQUEST_ID_WANT_KEY,
  BROWSER_TAB_WINDOW_MOVE_SOURCE_WANT_KEY,
  BrowserTabWindowMoveAcknowledgement,
  BrowserTabWindowMoveRequest,
  BrowserWindowRuntime
} from '../../app/runtime/BrowserWindowRuntime';
import { APP_BUNDLE_NAME } from '../../common/constants/AppVersionInfo';
import { BrowserTabState } from '../../core/tabs/TabManager';

const ENTRY_MODULE_NAME: string = 'entry';
const ENTRY_ABILITY_NAME: string = 'EntryAbility';

export class BrowserTabWindowMoveService {
  async moveToNewWindow(
    sourceWindowId: string,
    tab: BrowserTabState
  ): Promise<BrowserTabWindowMoveAcknowledgement> {
    const request = BrowserWindowRuntime.stageTabWindowMove(sourceWindowId, tab);
    const sourceContext = BrowserWindowRuntime.resolveWindowAbilityContext(request.sourceWindowId);
    if (sourceContext === undefined) {
      BrowserWindowRuntime.finishTabWindowMove(request.requestId);
      return this.buildRejectedAcknowledgement(request, '当前窗口还没有可用的启动上下文。');
    }
    try {
      await sourceContext.startAbility(this.buildWant(request));
      const acknowledgement = await BrowserWindowRuntime.waitForTabWindowMoveAcknowledgement(request.requestId);
      BrowserWindowRuntime.finishTabWindowMove(request.requestId);
      return acknowledgement;
    } catch (_error) {
      BrowserWindowRuntime.finishTabWindowMove(request.requestId);
      return this.buildRejectedAcknowledgement(request, '无法打开新的浏览器窗口。');
    }
  }

  private buildWant(request: BrowserTabWindowMoveRequest): Want {
    const parameters: Record<string, Object> = {};
    parameters[BROWSER_TAB_WINDOW_MOVE_SOURCE_WANT_KEY] = BROWSER_TAB_WINDOW_MOVE_LAUNCH_SOURCE;
    parameters[BROWSER_TAB_WINDOW_MOVE_INSTANCE_ID_WANT_KEY] = request.targetWindowInstanceId;
    parameters[BROWSER_TAB_WINDOW_MOVE_REQUEST_ID_WANT_KEY] = request.requestId;
    parameters[BROWSER_TAB_WINDOW_MOVE_PROFILE_ID_WANT_KEY] = request.tab.profileId;
    parameters[BROWSER_TAB_WINDOW_MOVE_PRIVACY_MODE_WANT_KEY] = request.tab.privacyMode;
    parameters[BROWSER_TAB_WINDOW_MOVE_DATA_SCOPE_WANT_KEY] = request.tab.dataScope;
    return {
      bundleName: APP_BUNDLE_NAME,
      moduleName: ENTRY_MODULE_NAME,
      abilityName: ENTRY_ABILITY_NAME,
      uri: this.resolveTargetUrl(request.tab),
      parameters: parameters
    };
  }

  private resolveTargetUrl(tab: BrowserTabState): string {
    const historyUrl = tab.navigationIndex >= 0 ? tab.navigationHistory[tab.navigationIndex] ?? '' : '';
    const candidates = [historyUrl, tab.pendingUrl, tab.url, tab.lastGoodUrl, tab.lastRestorableUrl];
    return candidates.find((candidate: string): boolean => candidate.trim().length > 0)?.trim() ?? 'aira://home';
  }

  private buildRejectedAcknowledgement(
    request: BrowserTabWindowMoveRequest,
    message: string
  ): BrowserTabWindowMoveAcknowledgement {
    return {
      requestId: request.requestId,
      accepted: false,
      targetWindowId: '',
      targetTabId: '',
      message: message
    };
  }
}
