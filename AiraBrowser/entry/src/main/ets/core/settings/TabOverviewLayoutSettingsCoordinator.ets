import { BrowserDataBoundaryInput, BrowserTabsOverviewLayoutStyle } from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface TabOverviewLayoutOptionState {
  style: BrowserTabsOverviewLayoutStyle;
  title: string;
  isSelected: boolean;
}

export interface TabOverviewLayoutSettingsState {
  currentStyle: BrowserTabsOverviewLayoutStyle;
  draftStyle: BrowserTabsOverviewLayoutStyle;
  currentCloseButtonAlwaysVisible: boolean;
  draftCloseButtonAlwaysVisible: boolean;
  isSaving: boolean;
  errorMessage: string;
}

export interface TabOverviewLayoutApplyResult {
  state: TabOverviewLayoutSettingsState;
  succeeded: boolean;
}

export class TabOverviewLayoutSettingsCoordinator {
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

  buildInitialState(): TabOverviewLayoutSettingsState {
    const appearance = this.preferencesRepository.getPreferences().appearance;
    const style = this.normalizeStyle(appearance.tabsOverviewLayoutStyle);
    const closeButtonAlwaysVisible = appearance.tabsOverviewCloseButtonAlwaysVisible === true;
    return this.buildState(
      style,
      style,
      closeButtonAlwaysVisible,
      closeButtonAlwaysVisible,
      false,
      ''
    );
  }

  refreshDraft(): TabOverviewLayoutSettingsState {
    return this.buildInitialState();
  }

  selectDraft(
    state: TabOverviewLayoutSettingsState,
    style: BrowserTabsOverviewLayoutStyle
  ): TabOverviewLayoutSettingsState {
    if (state.isSaving) {
      return state;
    }
    return this.buildState(
      state.currentStyle,
      this.normalizeStyle(style),
      state.currentCloseButtonAlwaysVisible,
      state.draftCloseButtonAlwaysVisible,
      false,
      ''
    );
  }

  setCloseButtonAlwaysVisibleDraft(
    state: TabOverviewLayoutSettingsState,
    alwaysVisible: boolean
  ): TabOverviewLayoutSettingsState {
    if (state.isSaving) {
      return state;
    }
    return this.buildState(
      state.currentStyle,
      state.draftStyle,
      state.currentCloseButtonAlwaysVisible,
      alwaysVisible,
      false,
      ''
    );
  }

  cancelDraft(state: TabOverviewLayoutSettingsState): TabOverviewLayoutSettingsState {
    if (state.isSaving) {
      return state;
    }
    return this.buildState(
      state.currentStyle,
      state.currentStyle,
      state.currentCloseButtonAlwaysVisible,
      state.currentCloseButtonAlwaysVisible,
      false,
      ''
    );
  }

  beginApply(state: TabOverviewLayoutSettingsState): TabOverviewLayoutSettingsState {
    return this.buildState(
      state.currentStyle,
      state.draftStyle,
      state.currentCloseButtonAlwaysVisible,
      state.draftCloseButtonAlwaysVisible,
      true,
      ''
    );
  }

  apply(
    state: TabOverviewLayoutSettingsState,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<TabOverviewLayoutApplyResult> {
    const requestedStyle = this.normalizeStyle(state.draftStyle);
    const requestedCloseButtonAlwaysVisible = state.draftCloseButtonAlwaysVisible === true;
    if (requestedStyle === state.currentStyle &&
      requestedCloseButtonAlwaysVisible === state.currentCloseButtonAlwaysVisible) {
      return Promise.resolve(this.buildApplyResult(
        this.buildState(
          requestedStyle,
          requestedStyle,
          requestedCloseButtonAlwaysVisible,
          requestedCloseButtonAlwaysVisible,
          false,
          ''
        ),
        true
      ));
    }
    if (!this.canWriteDevicePreference(boundaryInput)) {
      return Promise.resolve(this.buildApplyResult(
        this.buildState(
          state.currentStyle,
          state.draftStyle,
          state.currentCloseButtonAlwaysVisible,
          state.draftCloseButtonAlwaysVisible,
          false,
          '标签页样式更新失败，请稍后重试。'
        ),
        false
      ));
    }
    return this.preferencesRepository.updateTabsOverviewPresentation(
      requestedStyle,
      requestedCloseButtonAlwaysVisible
    )
      .then((preferences) => {
        const savedStyle = this.normalizeStyle(preferences.appearance.tabsOverviewLayoutStyle);
        const savedCloseButtonAlwaysVisible =
          preferences.appearance.tabsOverviewCloseButtonAlwaysVisible === true;
        return this.buildApplyResult(this.buildState(
          savedStyle,
          savedStyle,
          savedCloseButtonAlwaysVisible,
          savedCloseButtonAlwaysVisible,
          false,
          ''
        ), true);
      })
      .catch((_error: Error) => {
        return this.buildApplyResult(
          this.buildState(
            state.currentStyle,
            state.draftStyle,
            state.currentCloseButtonAlwaysVisible,
            state.draftCloseButtonAlwaysVisible,
            false,
            '标签页样式更新失败，请稍后重试。'
          ),
          false
        );
      });
  }

  buildOptions(state: TabOverviewLayoutSettingsState): TabOverviewLayoutOptionState[] {
    return [
      {
        style: 'grid',
        title: '卡片平铺',
        isSelected: state.draftStyle === 'grid'
      },
      {
        style: 'horizontal_cards',
        title: '横向大卡片',
        isSelected: state.draftStyle === 'horizontal_cards'
      }
    ];
  }

  private normalizeStyle(
    style: BrowserTabsOverviewLayoutStyle | string | undefined
  ): BrowserTabsOverviewLayoutStyle {
    return style === 'horizontal_cards' ? 'horizontal_cards' : 'grid';
  }

  private buildState(
    currentStyle: BrowserTabsOverviewLayoutStyle,
    draftStyle: BrowserTabsOverviewLayoutStyle,
    currentCloseButtonAlwaysVisible: boolean,
    draftCloseButtonAlwaysVisible: boolean,
    isSaving: boolean,
    errorMessage: string
  ): TabOverviewLayoutSettingsState {
    return {
      currentStyle: currentStyle,
      draftStyle: draftStyle,
      currentCloseButtonAlwaysVisible: currentCloseButtonAlwaysVisible,
      draftCloseButtonAlwaysVisible: draftCloseButtonAlwaysVisible,
      isSaving: isSaving,
      errorMessage: errorMessage
    };
  }

  private buildApplyResult(
    state: TabOverviewLayoutSettingsState,
    succeeded: boolean
  ): TabOverviewLayoutApplyResult {
    return {
      state: state,
      succeeded: succeeded
    };
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
