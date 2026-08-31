import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { SecureDnsSettingsRepository } from '../../data/preferences/SecureDnsSettingsRepository';
import {
  SecureDnsApplyResult,
  SecureDnsOption,
  SecureDnsService
} from '../../services/web/SecureDnsService';
import {
  SecureDnsCustomProfile,
  SecureDnsSelectionId,
  SecureDnsSettings,
  SecureDnsSettingsModel
} from './SecureDnsSettingsModel';
import { AppModeSwitchRestartService } from '../../services/settings/AppModeSwitchRestartService';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface SecureDnsSettingsOptionState {
  id: SecureDnsSelectionId;
  title: string;
}

export interface SecureDnsCustomProfileState {
  id: string;
  title: string;
  endpoint: string;
  isActive: boolean;
}

export interface SecureDnsSettingsState {
  settings: SecureDnsSettings;
  options: SecureDnsSettingsOptionState[];
  customProfiles: SecureDnsCustomProfileState[];
  summaryLabel: string;
  draftSelectionId: SecureDnsSelectionId;
  saving: boolean;
}

export interface SecureDnsCustomProfileDraft {
  id: string;
  name: string;
  endpoint: string;
  nameError: string;
  endpointError: string;
}

export interface SecureDnsCustomProfileMutationResult {
  success: boolean;
  draft: SecureDnsCustomProfileDraft;
  message: string;
}

export interface SecureDnsStartupResult {
  state: SecureDnsSettingsState;
  applyResult: SecureDnsApplyResult;
}

export type SecureDnsSettingsObserver = (state: SecureDnsSettingsState, persistedChange: boolean) => void;

export class SecureDnsSettingsCoordinator {
  private repository: SecureDnsSettingsRepository;
  private service: SecureDnsService;
  private settingsModel: SecureDnsSettingsModel;
  private restartService: AppModeSwitchRestartService;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private observer?: SecureDnsSettingsObserver;
  private state: SecureDnsSettingsState;

  constructor(
    repository: SecureDnsSettingsRepository,
    service: SecureDnsService,
    settingsModel: SecureDnsSettingsModel = new SecureDnsSettingsModel(),
    restartService: AppModeSwitchRestartService = new AppModeSwitchRestartService(),
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.service = service;
    this.settingsModel = settingsModel;
    this.restartService = restartService;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
    this.state = this.buildState(this.repository.getSettings());
  }

  async initializeAndApply(): Promise<SecureDnsStartupResult> {
    const settings = await this.repository.initialize();
    const resolution = await this.service.resolveStartupSettings(settings);
    const applyResult = this.service.applyToArkWeb(
      resolution.activeSettings,
      resolution.configuredSelectionId,
      resolution.probeElapsedMs
    );
    this.state = this.buildState(settings);
    return {
      state: this.copyState(this.state),
      applyResult: applyResult
    };
  }

  connect(observer: SecureDnsSettingsObserver): SecureDnsSettingsState {
    this.observer = observer;
    this.state = this.buildState(this.repository.getSettings());
    return this.copyState(this.state);
  }

  disconnect(): void {
    this.observer = undefined;
  }

  getState(): SecureDnsSettingsState {
    return this.copyState(this.state);
  }

  getSummaryLabel(): string {
    return this.resolveSummaryLabel(this.repository.getSettings());
  }

  handleOptionSelected(
    selectionId: SecureDnsSelectionId,
    boundaryInput: BrowserDataBoundaryInput
  ): void {
    if (this.state.saving) {
      return;
    }
    if (selectionId === 'custom') {
      return;
    }
    if (selectionId === this.state.settings.selectionId) {
      return;
    }
    const previousState = this.copyState(this.state);
    const mutation = this.settingsModel.apply(this.state.settings, {
      kind: 'select_provider',
      selectionId: selectionId
    });
    if (!mutation.success) {
      return;
    }
    const nextSettings = mutation.settings;
    if (!this.canWriteDevicePreference(boundaryInput)) {
      return;
    }
    const restartRequired = this.runtimeSettingsDiffer(nextSettings, this.state.settings);
    const savingState = this.copyState(this.state);
    savingState.saving = true;
    this.state = savingState;
    this.publish(false);
    this.repository.save(nextSettings)
      .then((settings: SecureDnsSettings): void => {
        this.handleSettingsPersisted(settings, restartRequired);
      })
      .catch((_error: Error): void => {
        this.state = previousState;
        this.publish(false);
      });
  }

  handleCustomProfileSelected(
    profileId: string,
    boundaryInput: BrowserDataBoundaryInput
  ): void {
    if (this.state.saving) {
      return;
    }
    const mutation = this.settingsModel.apply(this.state.settings, {
      kind: 'select_custom_profile',
      profileId: profileId
    });
    if (!mutation.success ||
      (this.state.settings.selectionId === 'custom' &&
        this.state.settings.activeCustomProfileId === profileId)) {
      return;
    }
    const nextSettings = mutation.settings;
    if (!this.canWriteDevicePreference(boundaryInput)) {
      return;
    }
    const previousState = this.copyState(this.state);
    const restartRequired = this.runtimeSettingsDiffer(nextSettings, this.state.settings);
    const savingState = this.copyState(this.state);
    savingState.saving = true;
    this.state = savingState;
    this.publish(false);
    this.repository.save(nextSettings)
      .then((settings: SecureDnsSettings): void => {
        this.handleSettingsPersisted(settings, restartRequired);
      })
      .catch((_error: Error): void => {
        this.state = previousState;
        this.publish(false);
      });
  }

  buildCustomProfileDraft(profileId: string = ''): SecureDnsCustomProfileDraft {
    const profile = this.settingsModel.findProfile(this.repository.getSettings(), profileId);
    if (profile === undefined) {
      return {
        id: '',
        name: '',
        endpoint: '',
        nameError: '',
        endpointError: ''
      };
    }
    return {
      id: profile.id,
      name: profile.name,
      endpoint: profile.endpoint,
      nameError: '',
      endpointError: ''
    };
  }

  async saveCustomProfileDraft(
    draft: SecureDnsCustomProfileDraft,
    boundaryInput: BrowserDataBoundaryInput,
    activate: boolean
  ): Promise<SecureDnsCustomProfileMutationResult> {
    const currentSettings = this.repository.getSettings();
    const mutation = this.settingsModel.apply(currentSettings, {
      kind: 'save_custom_profile',
      profileId: draft.id,
      name: draft.name,
      endpoint: draft.endpoint,
      activate: activate
    });
    if (!mutation.success) {
      return {
        success: false,
        draft: {
          id: draft.id,
          name: draft.name,
          endpoint: draft.endpoint,
          nameError: mutation.nameError,
          endpointError: mutation.endpointError
        },
        message: ''
      };
    }
    if (!this.canWriteDevicePreference(boundaryInput)) {
      return this.failedProfileMutation(draft, '当前模式下无法保存设备 DNS 设置。');
    }
    const restartRequired = this.runtimeSettingsDiffer(mutation.settings, currentSettings);
    try {
      const settings = await this.repository.save(mutation.settings);
      this.handleSettingsPersisted(settings, restartRequired);
      const savedProfileId = draft.id.length > 0 ? draft.id : settings.activeCustomProfileId;
      return {
        success: true,
        draft: this.buildCustomProfileDraft(savedProfileId),
        message: ''
      };
    } catch (_error) {
      return this.failedProfileMutation(draft, '保存失败，请稍后重试。');
    }
  }

  async deleteCustomProfileDraft(
    draft: SecureDnsCustomProfileDraft,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<SecureDnsCustomProfileMutationResult> {
    const currentSettings = this.repository.getSettings();
    if (draft.id.length === 0 || this.settingsModel.findProfile(currentSettings, draft.id) === undefined) {
      return this.failedProfileMutation(draft, '这个自定义 DNS 已不存在。');
    }
    if (!this.canWriteDevicePreference(boundaryInput)) {
      return this.failedProfileMutation(draft, '当前模式下无法删除设备 DNS 设置。');
    }
    const mutation = this.settingsModel.apply(currentSettings, {
      kind: 'delete_custom_profile',
      profileId: draft.id
    });
    if (!mutation.success) {
      return this.failedProfileMutation(draft, '这个自定义 DNS 已不存在。');
    }
    const restartRequired = this.runtimeSettingsDiffer(mutation.settings, currentSettings);
    try {
      const settings = await this.repository.save(mutation.settings);
      this.handleSettingsPersisted(settings, restartRequired);
      return {
        success: true,
        draft: this.copyCustomProfileDraft(draft),
        message: ''
      };
    } catch (_error) {
      return this.failedProfileMutation(draft, '删除失败，请稍后重试。');
    }
  }

  private buildState(settings: SecureDnsSettings): SecureDnsSettingsState {
    return {
      settings: settings,
      options: this.buildOptions(),
      customProfiles: this.buildCustomProfiles(settings),
      summaryLabel: this.resolveSummaryLabel(settings),
      draftSelectionId: settings.selectionId,
      saving: false
    };
  }

  private buildCustomProfiles(settings: SecureDnsSettings): SecureDnsCustomProfileState[] {
    return settings.customProfiles.map((profile: SecureDnsCustomProfile): SecureDnsCustomProfileState => {
      return {
        id: profile.id,
        title: profile.name,
        endpoint: profile.endpoint,
        isActive: settings.selectionId === 'custom' && settings.activeCustomProfileId === profile.id
      };
    });
  }

  private buildOptions(): SecureDnsSettingsOptionState[] {
    return this.service.getOptions().map((option: SecureDnsOption): SecureDnsSettingsOptionState => {
      return {
        id: option.id,
        title: this.resolveSelectionTitle(option.id)
      };
    });
  }

  private resolveSelectionTitle(selectionId: SecureDnsSelectionId): string {
    if (selectionId === 'auto') {
      return '自动优选';
    }
    if (selectionId === 'alidns') {
      return 'AliDNS';
    }
    if (selectionId === 'dnspod') {
      return 'DNSPod';
    }
    if (selectionId === 'cloudflare') {
      return 'Cloudflare';
    }
    if (selectionId === 'google') {
      return 'Google';
    }
    if (selectionId === 'custom') {
      return '自定义 DoH';
    }
    return '系统 DNS';
  }

  private resolveSummaryLabel(settings: SecureDnsSettings): string {
    if (settings.selectionId !== 'custom') {
      return this.resolveSelectionTitle(settings.selectionId);
    }
    return this.settingsModel.findProfile(settings, settings.activeCustomProfileId)?.name ?? '系统 DNS';
  }

  private copyState(source: SecureDnsSettingsState): SecureDnsSettingsState {
    return {
      settings: {
        selectionId: source.settings.selectionId,
        activeCustomProfileId: source.settings.activeCustomProfileId,
        customProfiles: source.settings.customProfiles.map(
          (profile: SecureDnsCustomProfile): SecureDnsCustomProfile => {
            return {
              id: profile.id,
              name: profile.name,
              endpoint: profile.endpoint
            };
          }
        )
      },
      options: source.options.map((option: SecureDnsSettingsOptionState): SecureDnsSettingsOptionState => {
        return {
          id: option.id,
          title: option.title
        };
      }),
      customProfiles: source.customProfiles.map(
        (profile: SecureDnsCustomProfileState): SecureDnsCustomProfileState => {
          return {
            id: profile.id,
            title: profile.title,
            endpoint: profile.endpoint,
            isActive: profile.isActive
          };
        }
      ),
      summaryLabel: source.summaryLabel,
      draftSelectionId: source.draftSelectionId,
      saving: source.saving
    };
  }

  private handleSettingsPersisted(settings: SecureDnsSettings, restartRequired: boolean): void {
    this.state = this.buildState(settings);
    this.publish(true);
    if (restartRequired) {
      this.restartService.scheduleRestart();
    }
  }

  private runtimeSettingsDiffer(left: SecureDnsSettings, right: SecureDnsSettings): boolean {
    return left.selectionId !== right.selectionId ||
      this.service.resolveEndpoint(left) !== this.service.resolveEndpoint(right);
  }

  private failedProfileMutation(
    draft: SecureDnsCustomProfileDraft,
    message: string
  ): SecureDnsCustomProfileMutationResult {
    return {
      success: false,
      draft: this.copyCustomProfileDraft(draft),
      message: message
    };
  }

  private copyCustomProfileDraft(draft: SecureDnsCustomProfileDraft): SecureDnsCustomProfileDraft {
    return {
      id: draft.id,
      name: draft.name,
      endpoint: draft.endpoint,
      nameError: draft.nameError,
      endpointError: draft.endpointError
    };
  }

  private publish(persistedChange: boolean): void {
    this.observer?.(this.copyState(this.state), persistedChange);
  }

  private canWriteDevicePreference(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }
}
