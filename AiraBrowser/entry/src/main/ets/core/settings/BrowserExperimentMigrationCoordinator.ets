import { BrowserExperimentSettings } from '../../common/models/BrowserModels';
import { BrowserMigrationRepository } from '../../data/preferences/BrowserMigrationRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';

const WEB_VIDEO_TAKEOVER_DEFAULT_MIGRATION_ID: string = 'web_video_takeover_default_enabled_v1';

export interface BrowserExperimentMigrationResult {
  applied: boolean;
  reason: string;
}

export class BrowserExperimentMigrationCoordinator {
  private preferencesRepository: PreferencesRepository;
  private migrationRepository: BrowserMigrationRepository;

  constructor(
    preferencesRepository: PreferencesRepository,
    migrationRepository: BrowserMigrationRepository
  ) {
    this.preferencesRepository = preferencesRepository;
    this.migrationRepository = migrationRepository;
  }

  async enableDefaultWebVideoTakeoverIfNeeded(): Promise<BrowserExperimentMigrationResult> {
    await this.migrationRepository.initialize();
    if (this.migrationRepository.hasCompleted(WEB_VIDEO_TAKEOVER_DEFAULT_MIGRATION_ID)) {
      return {
        applied: false,
        reason: 'already_completed'
      };
    }

    const preferences = this.preferencesRepository.getPreferences();
    if (preferences.appServiceMode !== 'full') {
      return {
        applied: false,
        reason: 'not_full_mode'
      };
    }

    if (preferences.experiments.webVideoTakeoverEnabled) {
      await this.migrationRepository.markCompleted(WEB_VIDEO_TAKEOVER_DEFAULT_MIGRATION_ID);
      return {
        applied: false,
        reason: 'already_enabled'
      };
    }

    const nextExperiments: BrowserExperimentSettings = {
      pauseWebAnimationsDuringScroll: preferences.experiments.pauseWebAnimationsDuringScroll,
      reduceMediaMotionDuringScroll: preferences.experiments.reduceMediaMotionDuringScroll,
      strengthenAdBlockingForSmoothScroll: preferences.experiments.strengthenAdBlockingForSmoothScroll,
      pullRefreshEnabled: preferences.experiments.pullRefreshEnabled,
      forceEnableWebZoom: preferences.experiments.forceEnableWebZoom,
      smartGripTabsActionsEnabled: preferences.experiments.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: true,
      novelModeEnabled: preferences.experiments.novelModeEnabled,
      novelAutoTakeoverEnabled: preferences.experiments.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: preferences.experiments.appProxyActiveProfileId,
      appProxyProfiles: preferences.experiments.appProxyProfiles,
      appProxyEnabled: preferences.experiments.appProxyEnabled,
      appProxy: preferences.experiments.appProxy
    };
    await this.preferencesRepository.updateExperimentSettings(nextExperiments);
    await this.migrationRepository.markCompleted(WEB_VIDEO_TAKEOVER_DEFAULT_MIGRATION_ID);
    return {
      applied: true,
      reason: 'enabled_default'
    };
  }
}
