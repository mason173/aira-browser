import userScriptValueFileAdapterConformanceTest from './UserScriptValueFileAdapterConformance.test';
import videoCompatibilityProfileCatalogTest from '../../../test/VideoCompatibilityProfileCatalog.test';
import videoCompatibilityBilibiliAcquisitionRecipeServiceTest from
  '../../../test/VideoCompatibilityBilibiliAcquisitionRecipeService.test';
import videoCompatibilityProfileReleaseGateTest from '../../../test/VideoCompatibilityProfileReleaseGate.test';
import mediaSessionResolutionServiceTest from '../../../test/MediaSessionResolutionService.test';
import mediaSessionResolutionRuntimeServiceTest from '../../../test/MediaSessionResolutionRuntimeService.test';
import browserArkWebMediaTakeoverRecoveryCharacterizationTest from
  '../../../test/BrowserArkWebMediaTakeoverRecoveryCharacterization.test';

export default function tests(): void {
  userScriptValueFileAdapterConformanceTest();
  videoCompatibilityProfileCatalogTest();
  videoCompatibilityBilibiliAcquisitionRecipeServiceTest();
  videoCompatibilityProfileReleaseGateTest();
  mediaSessionResolutionServiceTest();
  mediaSessionResolutionRuntimeServiceTest();
  browserArkWebMediaTakeoverRecoveryCharacterizationTest();
}
