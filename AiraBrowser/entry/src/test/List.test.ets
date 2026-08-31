import userScriptValueStateStoreTest from './UserScriptValueStateStore.test';
import novelReadingSessionStateTest from './NovelReadingSessionState.test';
import readingDocumentTest from './ReadingDocument.test';
import mediaSessionResolutionServiceTest from './MediaSessionResolutionService.test';
import browserArkWebMediaTakeoverRecoveryCharacterizationTest from
  './BrowserArkWebMediaTakeoverRecoveryCharacterization.test';
import mediaSessionResolutionRuntimeServiceTest from './MediaSessionResolutionRuntimeService.test';
import mediaPageBehaviorEvidenceAdapterTest from './MediaPageBehaviorEvidenceAdapter.test';
import browserTabletInterfaceModePolicyTest from './BrowserTabletInterfaceModePolicy.test';
import browserTabletInterfaceModeTransitionOwnerTest from './BrowserTabletInterfaceModeTransitionOwner.test';
import browserPrivacyEffectPolicyTest from './BrowserPrivacyEffectPolicy.test';
import downloadPrivacyPolicyTest from './DownloadPrivacyPolicy.test';
import settingsDestinationNavigationOwnerTest from './SettingsDestinationNavigationOwner.test';
import airaBookmarkMergeServiceTest from './AiraBookmarkMergeService.test';
import siteSettingTargetAndUserAgentTest from './SiteSettingTargetAndUserAgent.test';
import videoCompatibilityProfileCatalogTest from './VideoCompatibilityProfileCatalog.test';
import videoCompatibilityBilibiliAcquisitionRecipeServiceTest from
  './VideoCompatibilityBilibiliAcquisitionRecipeService.test';
import videoCompatibilityProfileReleaseGateTest from './VideoCompatibilityProfileReleaseGate.test';
import browserHttpsFirstNavigationServiceTest from './BrowserHttpsFirstNavigationService.test';
import browserBrowsingIdentityPolicyCoordinatorTest from './BrowserBrowsingIdentityPolicyCoordinator.test';
import browserUserAgentRuntimeServiceTest from './BrowserUserAgentRuntimeService.test';
import browserUserAgentHostPolicyCatalogTest from './BrowserUserAgentHostPolicyCatalog.test';
import localBackupImportScenariosTest from './LocalBackupImportScenarios.test';

export default function tests(): void {
  userScriptValueStateStoreTest();
  novelReadingSessionStateTest();
  readingDocumentTest();
  mediaSessionResolutionServiceTest();
  browserArkWebMediaTakeoverRecoveryCharacterizationTest();
  mediaSessionResolutionRuntimeServiceTest();
  mediaPageBehaviorEvidenceAdapterTest();
  browserTabletInterfaceModePolicyTest();
  browserTabletInterfaceModeTransitionOwnerTest();
  browserPrivacyEffectPolicyTest();
  downloadPrivacyPolicyTest();
  settingsDestinationNavigationOwnerTest();
  airaBookmarkMergeServiceTest();
  siteSettingTargetAndUserAgentTest();
  videoCompatibilityProfileCatalogTest();
  videoCompatibilityBilibiliAcquisitionRecipeServiceTest();
  videoCompatibilityProfileReleaseGateTest();
  browserHttpsFirstNavigationServiceTest();
  browserBrowsingIdentityPolicyCoordinatorTest();
  browserUserAgentRuntimeServiceTest();
  browserUserAgentHostPolicyCatalogTest();
  localBackupImportScenariosTest();
}
