import { AbilityStage, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  resolveBrowserLaunchPayloadFromWant,
  resolveBrowserLaunchWindowId
} from '../runtime/BrowserWindowRuntime';

const DOMAIN = 0x0000;
const TAG = 'AiraAbilityStage';
const DEFAULT_ABILITY_INSTANCE_KEY = 'window-main';

export default class AiraAbilityStage extends AbilityStage {
  onCreate(): void {
    hilog.info(DOMAIN, TAG, 'AbilityStage onCreate');
  }

  onAcceptWant(want: Want): string {
    const launchPayload = resolveBrowserLaunchPayloadFromWant(want, 'onAcceptWant');
    if (launchPayload !== undefined) {
      const instanceKey = resolveBrowserLaunchWindowId(launchPayload);
      hilog.info(DOMAIN, TAG, 'AbilityStage onAcceptWant instance=%{public}s', instanceKey);
      return instanceKey;
    }
    const instanceKey = DEFAULT_ABILITY_INSTANCE_KEY;
    hilog.info(DOMAIN, TAG, 'AbilityStage onAcceptWant instance=%{public}s', instanceKey);
    return instanceKey;
  }
}
