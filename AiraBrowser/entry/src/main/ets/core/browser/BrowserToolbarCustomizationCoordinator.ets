import vibrator from '@ohos.vibrator';
import {
  BrowserBottomToolbarScrollBehavior,
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  BrowserToolbarLayoutSettings
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserBottomAddressPanelActionId } from './BrowserBottomAddressPanelViewModel';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';
import { BrowserToolbarCustomizationViewModel } from './BrowserToolbarCustomizationViewModel';

const TOOLBAR_REORDER_HAPTIC_DURATION_MS: number = 18;
const TOOLBAR_REORDER_HAPTIC_MIN_INTERVAL_MS: number = 45;

export class BrowserToolbarCustomizationBoundary {
  dataScope: BrowserDataScope | string;
  privacyMode: BrowserSessionPrivacyMode | string;

  constructor(dataScope: BrowserDataScope | string = '', privacyMode: BrowserSessionPrivacyMode | string = '') {
    this.dataScope = dataScope;
    this.privacyMode = privacyMode;
  }
}

export class BrowserToolbarCustomizationCoordinator {
  private viewModel: BrowserToolbarCustomizationViewModel = new BrowserToolbarCustomizationViewModel();
  private lastReorderFeedbackAt: number = 0;
  private preferencesRepository: PreferencesRepository;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    preferencesRepository: PreferencesRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.preferencesRepository = preferencesRepository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  buildPrimaryMove(
    settings: BrowserToolbarLayoutSettings,
    actionId: BrowserBottomAddressPanelActionId,
    targetIndex: number
  ): BrowserToolbarLayoutSettings {
    return this.viewModel.movePrimaryToIndex(settings, actionId, targetIndex);
  }

  persistPrimaryMove(
    actionId: BrowserBottomAddressPanelActionId,
    targetIndex: number,
    boundary: BrowserToolbarCustomizationBoundary
  ): Promise<BrowserToolbarLayoutSettings> {
    const settings = this.preferencesRepository.getPreferences().toolbarLayout;
    return this.persistSettings(this.buildPrimaryMove(settings, actionId, targetIndex), boundary);
  }

  persistSettings(
    settings: BrowserToolbarLayoutSettings,
    boundary: BrowserToolbarCustomizationBoundary
  ): Promise<BrowserToolbarLayoutSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    const normalizedSettings = this.viewModel.normalizeSettings(settings);
    return this.preferencesRepository.updateToolbarLayoutSettings(normalizedSettings)
      .then((preferences) => preferences.toolbarLayout);
  }

  persistScrollBehavior(
    behavior: BrowserBottomToolbarScrollBehavior,
    boundary: BrowserToolbarCustomizationBoundary
  ): Promise<BrowserBottomToolbarScrollBehavior> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.preferencesRepository.updateBottomToolbarScrollBehavior(behavior)
      .then((preferences) => preferences.appearance.bottomToolbarScrollBehavior);
  }

  performReorderFeedback(): void {
    const now = Date.now();
    if (now - this.lastReorderFeedbackAt < TOOLBAR_REORDER_HAPTIC_MIN_INTERVAL_MS) {
      return;
    }
    this.lastReorderFeedbackAt = now;
    vibrator.startVibration({
      type: 'time',
      duration: TOOLBAR_REORDER_HAPTIC_DURATION_MS
    }, {
      usage: 'touch'
    }).catch((_error: Error) => {
    });
  }

  private ensureDevicePreferenceWriteAllowed(boundary: BrowserToolbarCustomizationBoundary): void {
    const decision = this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: boundary.dataScope,
        privacyMode: boundary.privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      throw new Error('Toolbar device preference write privacy effect was not allowed.');
    }
  }
}
