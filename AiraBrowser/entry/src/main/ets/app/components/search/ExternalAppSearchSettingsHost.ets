import {
  ExternalAppSearchPreferences,
  ExternalAppSearchTargetId
} from '../../../common/models/BrowserModels';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import { EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY } from '../../../common/constants/SearchPreferenceKeys';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import {
  ExternalAppSearchService,
  ExternalAppSearchTarget
} from '../../../services/search/ExternalAppSearchService';
import {
  sharedExternalAppSearchPreferencesRepository,
  sharedPreferencesRepository,
  sharedSearchEngineSettingsCoordinator
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { ExternalAppSearchSettingsScreen } from './ExternalAppSearchSettingsScreen';
import { SearchSettingsBoundary } from '../../../core/search/SearchEngineSettingsCoordinator';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';

@Component
export struct ExternalAppSearchSettingsHost {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private externalAppSearchService: ExternalAppSearchService = new ExternalAppSearchService();
  private themePreferencesListenerKey: string = '';
  onBack?: () => void;
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  @StorageLink(EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY) @Watch('refreshExternalAppSearchPreferences')
  private externalAppSearchPreferencesRevision: number = 0;
  @State private boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };
  @State private preferences: ExternalAppSearchPreferences =
    sharedExternalAppSearchPreferencesRepository.getSettings();
  @State private targets: ExternalAppSearchTarget[] =
    this.externalAppSearchService.listAllTargets(this.preferences.targetOrder);
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  onPageShow(): void {
    this.refreshState();
  }

  build() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '跨应用搜索',
          showBackButton: true,
          primaryTextColor: this.theme.textPrimary,
          iconColor: this.theme.accent,
          buttonBackgroundColor: this.theme.controlBackground,
          onBack: () => {
            this.onBack?.();
          }
        })
      }

      ExternalAppSearchSettingsScreen({
        featureEnabled: this.preferences.enabled,
        selectedTargetIds: this.preferences.selectedTargetIds,
        targets: this.targets,
        dataScope: this.boundary.dataScope,
        privacyMode: this.boundary.privacyMode,
        theme: this.theme,
        desktopPresentation: this.desktopPresentation,
        useTopSafeInset: !this.embedded,
        onBack: () => {
          if (this.onBack !== undefined) {
            this.onBack();
            return;
          }
          this.navigationCoordinator.back();
        },
        onFeatureEnabledChange: (enabled: boolean) => {
          this.updateFeatureEnabled(enabled);
        },
        onTargetEnabledChange: (targetId: ExternalAppSearchTargetId, enabled: boolean) => {
          this.updateTargetEnabled(targetId, enabled);
        },
        onTargetOrderChange: (targetOrder: ExternalAppSearchTargetId[]) => {
          this.updateTargetOrder(targetOrder);
        }
      })
        .width('100%')
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.theme.pageBackground)
  }

  private refreshState(): void {
    if (this.embedded) {
      this.boundary = {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      };
    } else {
      this.boundary = readBrowserBoundaryRouteState(this.boundary);
    }
    this.refreshThemeState();
    this.refreshExternalAppSearchPreferences();
  }

  private refreshExternalAppSearchPreferences(): void {
    void this.externalAppSearchPreferencesRevision;
    this.preferences = sharedExternalAppSearchPreferencesRepository.getSettings();
    this.targets = this.externalAppSearchService.listAllTargets(this.preferences.targetOrder);
  }

  private updateFeatureEnabled(enabled: boolean): void {
    if (this.preferences.enabled === enabled) {
      return;
    }
    const previousPreferences = this.preferences;
    const optimisticPreferences: ExternalAppSearchPreferences = {
      enabled: enabled,
      selectedTargetIds: previousPreferences.selectedTargetIds.slice(),
      targetOrder: previousPreferences.targetOrder.slice(),
      updatedAt: Date.now()
    };
    this.preferences = optimisticPreferences;
    sharedSearchEngineSettingsCoordinator.setExternalAppSearchEnabled(enabled, this.buildSettingsBoundary())
      .then((preferences: ExternalAppSearchPreferences) => {
        this.preferences = preferences;
        this.targets = this.externalAppSearchService.listAllTargets(preferences.targetOrder);
      })
      .catch((_error: Error) => {
        this.preferences = previousPreferences;
        this.targets = this.externalAppSearchService.listAllTargets(previousPreferences.targetOrder);
      });
  }

  private updateTargetEnabled(targetId: ExternalAppSearchTargetId, enabled: boolean): void {
    const currentlyEnabled = this.preferences.selectedTargetIds.indexOf(targetId) >= 0;
    if (currentlyEnabled === enabled) {
      return;
    }
    const previousPreferences = this.preferences;
    const nextTargetIds = previousPreferences.selectedTargetIds.filter((candidate: ExternalAppSearchTargetId): boolean => {
      return candidate !== targetId;
    });
    if (enabled) {
      nextTargetIds.push(targetId);
    }
    const optimisticPreferences: ExternalAppSearchPreferences = {
      enabled: previousPreferences.enabled,
      selectedTargetIds: nextTargetIds,
      targetOrder: previousPreferences.targetOrder.slice(),
      updatedAt: Date.now()
    };
    this.preferences = optimisticPreferences;
    sharedSearchEngineSettingsCoordinator.setExternalAppSearchTargetEnabled(
      targetId,
      enabled,
      this.buildSettingsBoundary()
    )
      .then((preferences: ExternalAppSearchPreferences) => {
        this.preferences = preferences;
        this.targets = this.externalAppSearchService.listAllTargets(preferences.targetOrder);
      })
      .catch((_error: Error) => {
        this.preferences = previousPreferences;
        this.targets = this.externalAppSearchService.listAllTargets(previousPreferences.targetOrder);
      });
  }

  private updateTargetOrder(targetOrder: ExternalAppSearchTargetId[]): void {
    const previousPreferences = this.preferences;
    const optimisticPreferences: ExternalAppSearchPreferences = {
      enabled: previousPreferences.enabled,
      selectedTargetIds: previousPreferences.selectedTargetIds.slice(),
      targetOrder: targetOrder.slice(),
      updatedAt: Date.now()
    };
    this.preferences = optimisticPreferences;
    this.targets = this.externalAppSearchService.listAllTargets(targetOrder);
    sharedSearchEngineSettingsCoordinator.setExternalAppSearchTargetOrder(targetOrder, this.buildSettingsBoundary())
      .then((preferences: ExternalAppSearchPreferences) => {
        this.preferences = preferences;
        this.targets = this.externalAppSearchService.listAllTargets(preferences.targetOrder);
      })
      .catch((_error: Error) => {
        this.preferences = previousPreferences;
        this.targets = this.externalAppSearchService.listAllTargets(previousPreferences.targetOrder);
      });
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private buildSettingsBoundary(): SearchSettingsBoundary {
    return new SearchSettingsBoundary(this.boundary.dataScope, this.boundary.privacyMode);
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((_preferences, scope) => {
      if (scope === 'theme_mode' || scope === 'appearance') {
        this.refreshThemeState();
      }
    });
  }

  private unbindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length <= 0) {
      return;
    }
    sharedPreferencesRepository.unsubscribe(this.themePreferencesListenerKey);
    this.themePreferencesListenerKey = '';
  }
}
