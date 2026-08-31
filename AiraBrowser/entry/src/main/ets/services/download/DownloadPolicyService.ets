import {
  BrowserDownloadLocation,
  BrowserPrivateDownloadFilePolicy,
  BrowserPrivateDownloadRecordPolicy,
  BrowserDownloadSettings,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { PreferencesRepository, DEFAULT_BROWSER_DOWNLOAD_SETTINGS } from '../../data/preferences/PreferencesRepository';
import { DownloadTaskBoundary } from '../../domain/download/DownloadTypes';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService,
  BrowserPrivacyEffectTargetScope
} from '../privacy/BrowserPrivacyEffectPolicyService';

export type DownloadSaveDestinationMode = 'default_location' | 'user_selected_location';
export type DownloadSavePolicyReason =
  'default_location' |
  'ask_before_download' |
  'private_prompt_for_location' |
  'private_session_temp_only';

export interface DownloadSavePolicy {
  defaultLocation: BrowserDownloadLocation;
  settings: BrowserDownloadSettings;
  destinationMode: DownloadSaveDestinationMode;
  reason: DownloadSavePolicyReason;
  requiresConfirmation: boolean;
  isPrivateSession: boolean;
  privateFilePolicy?: BrowserPrivateDownloadFilePolicy;
  privateRecordPolicy?: BrowserPrivateDownloadRecordPolicy;
}

export interface DownloadSessionCleanupPolicy {
  isPrivateSession: boolean;
  shouldClearSessionRecordsOnWindowClose: boolean;
  shouldDeleteSessionTempFilesOnWindowClose: boolean;
  privateRecordPolicy?: BrowserPrivateDownloadRecordPolicy;
}

export class DownloadPolicyService {
  private preferencesRepository?: PreferencesRepository;
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;

  constructor(
    preferencesRepository?: PreferencesRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService()
  ) {
    this.preferencesRepository = preferencesRepository;
    this.privacyEffectPolicy = privacyEffectPolicy;
  }

  private readSettingsUnchecked(): BrowserDownloadSettings {
    return this.preferencesRepository?.getPreferences().downloads ?? DEFAULT_BROWSER_DOWNLOAD_SETTINGS;
  }

  readSettings(boundary: DownloadTaskBoundary): BrowserDownloadSettings {
    if (!this.isEffectAllowed('download_settings_read', boundary, 'device_preferences')) {
      throw new Error('Download Settings privacy effect was not allowed.');
    }
    return this.readSettingsUnchecked();
  }

  async updateSettings(
    boundary: DownloadTaskBoundary,
    settings: BrowserDownloadSettings
  ): Promise<BrowserDownloadSettings> {
    if (!this.isEffectAllowed('download_settings_write', boundary, 'device_preferences')) {
      throw new Error('Download Settings privacy effect was not allowed.');
    }
    if (this.preferencesRepository === undefined) {
      throw new Error('Download Settings persistence is unavailable.');
    }
    const preferences = await this.preferencesRepository.updateDownloadSettings(settings);
    return preferences.downloads;
  }

  canReadSessionTasks(boundary: DownloadTaskBoundary): boolean {
    if (!this.isSessionEphemeralBoundary(boundary)) {
      return true;
    }
    return this.isEffectAllowed('download_session_task_read', boundary, 'private_session_state');
  }

  canWriteSessionTasks(boundary: DownloadTaskBoundary): boolean {
    if (!this.isSessionEphemeralBoundary(boundary)) {
      return true;
    }
    return this.isEffectAllowed('download_session_task_write', boundary, 'private_session_state');
  }

  canExportFile(boundary: DownloadTaskBoundary, targetIsClear: boolean): boolean {
    return this.isEffectAllowed(
      'download_file_export',
      boundary,
      'user_selected_external_location',
      targetIsClear
    );
  }

  canCleanupSession(boundary: DownloadTaskBoundary): boolean {
    if (!this.isSessionEphemeralBoundary(boundary)) {
      return true;
    }
    return this.isEffectAllowed('download_session_cleanup', boundary, 'private_session_state');
  }

  resolveSavePolicy(boundary: DownloadTaskBoundary): DownloadSavePolicy {
    const settings = this.readSettingsUnchecked();
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    const dataScope = normalizeBrowserDataScope(boundary.dataScope, privacyMode);
    if (this.profileBoundaryService.isSessionEphemeral({ privacyMode: privacyMode, dataScope: dataScope })) {
      const privateFilePolicy = settings.privateFilePolicy;
      return {
        defaultLocation: settings.defaultLocation,
        settings: settings,
        destinationMode: privateFilePolicy === 'session_temp_only' ? 'default_location' : 'user_selected_location',
        reason: privateFilePolicy === 'session_temp_only' ? 'private_session_temp_only' : 'private_prompt_for_location',
        requiresConfirmation: privateFilePolicy !== 'session_temp_only',
        isPrivateSession: true,
        privateFilePolicy: privateFilePolicy,
        privateRecordPolicy: settings.privateRecordPolicy
      };
    }
    if (settings.askBeforeDownload) {
      return {
        defaultLocation: settings.defaultLocation,
        settings: settings,
        destinationMode: 'default_location',
        reason: 'ask_before_download',
        requiresConfirmation: true,
        isPrivateSession: false
      };
    }
    return {
      defaultLocation: settings.defaultLocation,
      settings: settings,
      destinationMode: 'default_location',
      reason: 'default_location',
      requiresConfirmation: false,
      isPrivateSession: false
    };
  }

  resolveSessionCleanupPolicy(boundary: DownloadTaskBoundary): DownloadSessionCleanupPolicy {
    const settings = this.readSettingsUnchecked();
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    const dataScope = normalizeBrowserDataScope(boundary.dataScope, privacyMode);
    const isPrivateSession = this.profileBoundaryService.isSessionEphemeral({
      privacyMode: privacyMode,
      dataScope: dataScope
    });
    if (!isPrivateSession) {
      return {
        isPrivateSession: false,
        shouldClearSessionRecordsOnWindowClose: false,
        shouldDeleteSessionTempFilesOnWindowClose: false
      };
    }
    return {
      isPrivateSession: true,
      shouldClearSessionRecordsOnWindowClose: true,
      shouldDeleteSessionTempFilesOnWindowClose: true,
      privateRecordPolicy: settings.privateRecordPolicy
    };
  }

  private isEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    boundary: DownloadTaskBoundary,
    targetScope: BrowserPrivacyEffectTargetScope,
    targetIsClear: boolean = true
  ): boolean {
    const requestingBoundary = this.profileBoundaryService.buildBoundary({
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope,
      sessionId: boundary.windowId
    });
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: requestingBoundary,
      targetScope: targetScope,
      targetIsClear: targetIsClear
    }).outcome === 'allow';
  }

  private isSessionEphemeralBoundary(boundary: DownloadTaskBoundary): boolean {
    return this.profileBoundaryService.isSessionEphemeral(this.profileBoundaryService.buildBoundary({
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope,
      sessionId: boundary.windowId
    }));
  }
}
