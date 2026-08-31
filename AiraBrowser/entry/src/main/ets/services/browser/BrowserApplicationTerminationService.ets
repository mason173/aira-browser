import { common } from '@kit.AbilityKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

/**
 * Platform executor for terminating the browser's current Stage UIAbility.
 * Browser policy and cleanup remain with the app/window and tab owners.
 */
export class BrowserApplicationTerminationService {
  private readonly abilityContext: common.UIAbilityContext;
  private pendingTermination?: Promise<void>;

  constructor() {
    this.abilityContext = AppRuntimeContext.getUIAbilityContext();
  }

  terminateCurrentApplication(): Promise<void> {
    if (this.pendingTermination !== undefined) {
      return this.pendingTermination;
    }
    const request = this.abilityContext.terminateSelf();
    const pendingTermination = request
      .then((): void => {
        this.pendingTermination = undefined;
      })
      .catch((error: Error): never => {
        this.pendingTermination = undefined;
        throw error;
      });
    this.pendingTermination = pendingTermination;
    return pendingTermination;
  }
}
