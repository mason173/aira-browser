import { BrowserExperimentSettings } from '../../../common/models/BrowserModels';
import { PreferencesRepository } from '../../../data/preferences/PreferencesRepository';
import { BrowserMediaDiscoveryRuntimeContext } from './BrowserMediaDiscoveryModels';

export interface BrowserMediaDiscoveryRuntimeContextBuildInput {
  fullAppServiceMode: boolean;
  cachedExperimentSettings: BrowserExperimentSettings;
  mediaResourcesPanelOpen: boolean;
}

export class BrowserMediaDiscoveryRuntimeContextFactory {
  private preferencesRepository: PreferencesRepository;
  private cachedBuildSignature: string = '';
  private cachedRuntimeContext?: BrowserMediaDiscoveryRuntimeContext;

  constructor(preferencesRepository: PreferencesRepository) {
    this.preferencesRepository = preferencesRepository;
  }

  invalidate(): void {
    this.cachedBuildSignature = '';
    this.cachedRuntimeContext = undefined;
  }

  build(input: BrowserMediaDiscoveryRuntimeContextBuildInput): BrowserMediaDiscoveryRuntimeContext {
    const cachedTakeoverEnabled = input.cachedExperimentSettings.webVideoTakeoverEnabled;
    const buildSignature =
      (input.fullAppServiceMode ? '1' : '0') + ':' +
        (cachedTakeoverEnabled ? '1' : '0') + ':' +
        (input.mediaResourcesPanelOpen ? '1' : '0');
    if (this.cachedRuntimeContext !== undefined && buildSignature === this.cachedBuildSignature) {
      return this.cachedRuntimeContext;
    }
    const preferences = this.preferencesRepository.getPreferences();
    const repositoryTakeoverEnabled = preferences.experiments.webVideoTakeoverEnabled;
    this.cachedBuildSignature = buildSignature;
    this.cachedRuntimeContext = {
      fullAppServiceMode: input.fullAppServiceMode,
      webVideoTakeoverEnabled: repositoryTakeoverEnabled,
      mediaResourcesPanelOpen: input.mediaResourcesPanelOpen
    };
    return this.cachedRuntimeContext;
  }
}
