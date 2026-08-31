import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import tests from '../test/List.test';

const TEST_LOG_DOMAIN: number = 0x0000;
const TEST_LOG_TAG: string = 'AiraValueStateTest';
const UNEXPECTED_DESTROY_RESULT_CODE: number = -2;

export default class TestAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const argumentsSnapshot = abilityDelegatorRegistry.getArguments();
    hilog.info(TEST_LOG_DOMAIN, TEST_LOG_TAG, '%{public}s', 'Starting file adapter conformance tests.');
    Hypium.hypiumTest(delegator, argumentsSnapshot, tests);
  }

  onDestroy(): void {
    abilityDelegatorRegistry.getAbilityDelegator().finishTest(
      'TestAbility destroyed before Hypium completed.',
      UNEXPECTED_DESTROY_RESULT_CODE,
      (): void => {}
    );
  }
}
