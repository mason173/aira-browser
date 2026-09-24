import { Want } from '@kit.AbilityKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BROWSER_NEW_WINDOW_INSTANCE_ID_WANT_KEY,
  BROWSER_NEW_WINDOW_LAUNCH_SOURCE,
  BROWSER_NEW_WINDOW_OPEN_NEW_WANT_KEY,
  BROWSER_NEW_WINDOW_PROFILE_ID_WANT_KEY,
  BROWSER_NEW_WINDOW_SOURCE_WANT_KEY
} from '../../app/runtime/BrowserWindowRuntime';
import { APP_BUNDLE_NAME } from '../../common/constants/AppVersionInfo';

const ENTRY_MODULE_NAME: string = 'entry';
const ENTRY_ABILITY_NAME: string = 'EntryAbility';

/**
 * Opens a URL in a separate regular browser window.
 *
 * Mirrors BrowserPrivateWindowLaunchService: the new window instance claims the launch by
 * instance id, which is what keeps the payload from being delivered into the current window.
 */
export class BrowserNewWindowLaunchService {
  async openNewWindow(initialUrl: string = '', profileId: string = 'default'): Promise<void> {
    const instanceId = this.createInstanceId();
    const parameters: Record<string, Object> = {};
    parameters[BROWSER_NEW_WINDOW_SOURCE_WANT_KEY] = BROWSER_NEW_WINDOW_LAUNCH_SOURCE;
    parameters[BROWSER_NEW_WINDOW_INSTANCE_ID_WANT_KEY] = instanceId;
    parameters[BROWSER_NEW_WINDOW_OPEN_NEW_WANT_KEY] = true;
    parameters[BROWSER_NEW_WINDOW_PROFILE_ID_WANT_KEY] = profileId;
    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      moduleName: ENTRY_MODULE_NAME,
      abilityName: ENTRY_ABILITY_NAME,
      uri: initialUrl.trim(),
      parameters: parameters
    };
    await AppRuntimeContext.getUIAbilityContext().startAbility(want);
  }

  private createInstanceId(): string {
    const randomPart = Math.floor(Math.random() * 0xFFFFFF).toString(36);
    return `${Date.now().toString(36)}-${randomPart}`;
  }
}
