import { Want } from '@kit.AbilityKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BROWSER_PRIVATE_WINDOW_DATA_SCOPE_WANT_KEY,
  BROWSER_PRIVATE_WINDOW_INSTANCE_ID_WANT_KEY,
  BROWSER_PRIVATE_WINDOW_LAUNCH_SOURCE,
  BROWSER_PRIVATE_WINDOW_OPEN_NEW_WANT_KEY,
  BROWSER_PRIVATE_WINDOW_PRIVACY_MODE_WANT_KEY,
  BROWSER_PRIVATE_WINDOW_PROFILE_ID_WANT_KEY,
  BROWSER_PRIVATE_WINDOW_SOURCE_WANT_KEY
} from '../../app/runtime/BrowserWindowRuntime';
import { APP_BUNDLE_NAME } from '../../common/constants/AppVersionInfo';

const ENTRY_MODULE_NAME: string = 'entry';
const ENTRY_ABILITY_NAME: string = 'EntryAbility';

export class BrowserPrivateWindowLaunchService {
  async openNewPrivateWindow(initialUrl: string = ''): Promise<void> {
    const instanceId = this.createInstanceId();
    const targetUrl = initialUrl.trim();
    const parameters: Record<string, Object> = {};
    parameters[BROWSER_PRIVATE_WINDOW_SOURCE_WANT_KEY] = BROWSER_PRIVATE_WINDOW_LAUNCH_SOURCE;
    parameters[BROWSER_PRIVATE_WINDOW_INSTANCE_ID_WANT_KEY] = instanceId;
    parameters[BROWSER_PRIVATE_WINDOW_OPEN_NEW_WANT_KEY] = true;
    parameters[BROWSER_PRIVATE_WINDOW_PROFILE_ID_WANT_KEY] = 'default';
    parameters[BROWSER_PRIVATE_WINDOW_PRIVACY_MODE_WANT_KEY] = 'private';
    parameters[BROWSER_PRIVATE_WINDOW_DATA_SCOPE_WANT_KEY] = 'session_ephemeral';
    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      moduleName: ENTRY_MODULE_NAME,
      abilityName: ENTRY_ABILITY_NAME,
      uri: targetUrl,
      parameters: parameters
    };
    await AppRuntimeContext.getUIAbilityContext().startAbility(want);
  }

  private createInstanceId(): string {
    const randomPart = Math.floor(Math.random() * 0xFFFFFF).toString(36);
    return `${Date.now().toString(36)}-${randomPart}`;
  }
}
