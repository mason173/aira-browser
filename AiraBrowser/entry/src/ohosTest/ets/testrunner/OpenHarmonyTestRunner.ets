import { UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';

const TEST_LOG_DOMAIN: number = 0x0000;
const TEST_LOG_TAG: string = 'AiraValueStateTest';

async function onAbilityCreate(_ability: UIAbility): Promise<void> {
  hilog.info(TEST_LOG_DOMAIN, TEST_LOG_TAG, '%{public}s', 'TestAbility created.');
}

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {
    hilog.info(TEST_LOG_DOMAIN, TEST_LOG_TAG, '%{public}s', 'Test runner prepared.');
  }

  onRun(): void {
    const argumentsSnapshot = abilityDelegatorRegistry.getArguments();
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const moduleName = String(argumentsSnapshot.parameters['-m'] ?? 'entry_test');
    const monitor: abilityDelegatorRegistry.AbilityMonitor = {
      abilityName: 'TestAbility',
      moduleName: moduleName,
      onAbilityCreate: onAbilityCreate
    };
    delegator.addAbilityMonitor(monitor, (error: BusinessError): void => {
      if (error.code !== 0) {
        hilog.error(TEST_LOG_DOMAIN, TEST_LOG_TAG, 'Ability monitor failed code=%{public}d.', error.code);
      }
    });
    const want: Want = {
      bundleName: argumentsSnapshot.bundleName,
      moduleName: moduleName,
      abilityName: 'TestAbility'
    };
    delegator.startAbility(want, (error: BusinessError): void => {
      if (error.code !== 0) {
        hilog.error(TEST_LOG_DOMAIN, TEST_LOG_TAG, 'TestAbility start failed code=%{public}d.', error.code);
      }
    });
  }
}
