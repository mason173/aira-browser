import { SearchSettingsScreen } from './SearchSettingsScreen';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { SearchFallbackEngineHost } from './SearchFallbackEngineHost';
import { ExternalAppSearchSettingsHost } from './ExternalAppSearchSettingsHost';
import { SearchDefaultEngineHost } from './SearchDefaultEngineHost';
import {
  SearchEngineManagementState,
  SearchEngineManagementViewModel
} from '../../../core/search/SearchEngineManagementViewModel';
import {
  sharedExternalAppSearchPreferencesRepository,
  sharedPreferencesRepository,
  sharedQuickSearchSwitchPreferencesRepository,
  sharedSearchEngineRepository,
  sharedSearchEngineSettingsCoordinator,
  sharedSearchQueryHistoryService
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  ExternalAppSearchPreferences,
  SearchEngineSettings,
  SearchSuggestionPreferences
} from '../../../common/models/BrowserModels';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import { SearchQueryHistoryClearResult } from '../../../services/search/SearchQueryHistoryService';
import {
  SearchSettingsBoundary
} from '../../../core/search/SearchEngineSettingsCoordinator';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import {
  EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY,
  QUICK_SEARCH_SWITCHING_PREFERENCES_REVISION_KEY,
  SEARCH_ENGINE_SETTINGS_REVISION_KEY
} from '../../../common/constants/SearchPreferenceKeys';

@Component
export struct SearchSettingsHost {
  private viewModel: SearchEngineManagementViewModel = new SearchEngineManagementViewModel();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private themePreferencesListenerKey: string = '';
  @StorageLink(SEARCH_ENGINE_SETTINGS_REVISION_KEY) @Watch('refreshState')
  private searchEngineSettingsRevision: number = 0;
  @StorageLink(EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY) @Watch('refreshExternalAppSearchPreferences')
  private externalAppSearchPreferencesRevision: number = 0;
  @StorageLink(QUICK_SEARCH_SWITCHING_PREFERENCES_REVISION_KEY) @Watch('refreshQuickSearchSwitchingPreference')
  private quickSearchSwitchingPreferencesRevision: number = 0;
  @Prop @Watch('refreshState') dataScope: string = '';
  @Prop @Watch('refreshState') privacyMode: string = '';
  @Prop @Watch('refreshState') boundarySource: string = '';
  @Prop @Watch('refreshState') refreshRevision: number = 0;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop contentKind: SettingsContentKind = 'standard';
  @Prop largeScreenInline: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop revealTargetId: string = '';
  @Prop revealRevision: number = 0;
  @State private searchDeepView: string = 'main';
  onSettingsChanged?: () => void;
  @State private boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };
  @State private state: SearchEngineManagementState =
    this.viewModel.buildState(sharedSearchEngineRepository.getSettings(), sharedSearchEngineRepository.listEngines());
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @State private externalAppSearchPreferences: ExternalAppSearchPreferences =
    sharedExternalAppSearchPreferencesRepository.getSettings();
  @State private quickSearchSwitchingEnabled: boolean =
    sharedQuickSearchSwitchPreferencesRepository.isEnabled();
  @State private clearingSearchHistory: boolean = false;

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
    if (this.largeScreenInline && this.searchDeepView === 'fallback_engine') {
      SearchFallbackEngineHost({
        embedded: true,
        desktopPresentation: this.desktopPresentation,
        dataScope: this.boundary.dataScope,
        privacyMode: this.boundary.privacyMode,
        boundarySource: this.boundary.boundarySource,
        onBack: () => {
          this.searchDeepView = 'main';
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.largeScreenInline && this.searchDeepView === 'external_app') {
      ExternalAppSearchSettingsHost({
        embedded: true,
        desktopPresentation: this.desktopPresentation,
        dataScope: this.boundary.dataScope,
        privacyMode: this.boundary.privacyMode,
        boundarySource: this.boundary.boundarySource,
        onBack: () => {
          this.searchDeepView = 'main';
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.largeScreenInline && this.searchDeepView === 'default_engine') {
      SearchDefaultEngineHost({
        embedded: true,
        desktopPresentation: this.desktopPresentation,
        dataScope: this.boundary.dataScope,
        privacyMode: this.boundary.privacyMode,
        boundarySource: this.boundary.boundarySource,
        onBack: () => {
          this.searchDeepView = 'main';
        }
      })
        .width('100%')
        .height('100%')
    } else {
      this.buildMainContent()
    }
  }

  @Builder
  private buildMainContent() {
    Column() {
      SearchSettingsScreen({
        state: this.state,
        dataScope: this.boundary.dataScope,
        privacyMode: this.boundary.privacyMode,
        pageBackground: this.theme.pageBackground,
        surfaceBackground: this.theme.surfaceBackground,
        controlBackground: this.theme.controlBackground,
        pressedBackground: this.theme.pressedBackground,
        accentColor: this.theme.accent,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        showBackButton: this.showBackButton,
        showTitleBar: this.showTitleBar,
        useTopSafeInset: this.useTopSafeInset,
        contentKind: this.contentKind,
        desktopPresentation: this.desktopPresentation,
        revealTargetId: this.revealTargetId,
        revealRevision: this.revealRevision,
        externalAppSearchSummary: this.resolveExternalAppSearchSummary(),
        quickSearchSwitchingEnabled: this.quickSearchSwitchingEnabled,
        onOpenDefaultEngine: () => {
          this.openDefaultEnginePicker();
        },
        onQuickSearchSwitchingChange: (enabled: boolean) => {
          this.updateQuickSearchSwitchingEnabled(enabled);
        },
        onFallbackEnabledChange: (enabled: boolean) => {
          this.updateSearchFallbackEnabled(enabled);
        },
        onOpenFallbackEngine: () => {
          this.openFallbackEnginePicker();
        },
        onFallbackNoticeEnabledChange: (enabled: boolean) => {
          this.updateSearchFallbackNoticeEnabled(enabled);
        },
        onHistorySuggestionsChange: (enabled: boolean) => {
          this.updateSearchHistorySuggestions(enabled);
        },
        onRemoteSuggestionsChange: (enabled: boolean) => {
          this.updateRemoteSearchSuggestions(enabled);
        },
        onOpenExternalAppSearchSettings: () => {
          this.openExternalAppSearchSettings();
        },
        onClearSearchHistory: () => {
          this.confirmClearSearchHistory();
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
  }

  private refreshState(): void {
    void this.searchEngineSettingsRevision;
    void this.refreshRevision;
    this.boundary = readBrowserBoundaryRouteState({
      dataScope: this.dataScope.length > 0 ? this.dataScope : this.boundary.dataScope,
      privacyMode: this.privacyMode.length > 0 ? this.privacyMode : this.boundary.privacyMode,
      boundarySource: this.boundarySource.length > 0 ? this.boundarySource : this.boundary.boundarySource
    });
    this.refreshThemeState();
    this.state = this.viewModel.buildState(
      sharedSearchEngineRepository.getSettings(),
      sharedSearchEngineRepository.listEngines()
    );
    this.refreshExternalAppSearchPreferences();
    this.refreshQuickSearchSwitchingPreference();
  }

  private refreshExternalAppSearchPreferences(): void {
    void this.externalAppSearchPreferencesRevision;
    this.externalAppSearchPreferences = sharedExternalAppSearchPreferencesRepository.getSettings();
  }

  private refreshQuickSearchSwitchingPreference(): void {
    void this.quickSearchSwitchingPreferencesRevision;
    this.quickSearchSwitchingEnabled = sharedQuickSearchSwitchPreferencesRepository.isEnabled();
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
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

  private openDefaultEnginePicker(): void {
    if (this.largeScreenInline) {
      this.searchDeepView = 'default_engine';
      return;
    }
    this.navigationCoordinator.openSearchDefaultEngine(this.buildForwardRouteParams());
  }

  private updateQuickSearchSwitchingEnabled(enabled: boolean): void {
    sharedSearchEngineSettingsCoordinator.setQuickSearchSwitchingEnabled(enabled, this.buildSettingsBoundary())
      .then((nextEnabled: boolean) => {
        this.quickSearchSwitchingEnabled = nextEnabled;
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.refreshQuickSearchSwitchingPreference();
      });
  }

  private openFallbackEnginePicker(): void {
    if (this.largeScreenInline) {
      this.searchDeepView = 'fallback_engine';
      return;
    }
    this.navigationCoordinator.openSearchFallbackEngine(this.buildForwardRouteParams());
  }

  private openExternalAppSearchSettings(): void {
    if (this.largeScreenInline) {
      this.searchDeepView = 'external_app';
      return;
    }
    this.navigationCoordinator.openExternalAppSearchSettings(this.buildForwardRouteParams());
  }

  private updateSearchFallbackEnabled(enabled: boolean): void {
    sharedSearchEngineSettingsCoordinator.setFallbackEnabled(enabled, this.buildSettingsBoundary())
      .then((settings: SearchEngineSettings) => {
        this.state = this.viewModel.buildState(settings, sharedSearchEngineRepository.listEngines());
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.refreshState();
      });
  }

  private updateSearchFallbackNoticeEnabled(enabled: boolean): void {
    sharedSearchEngineSettingsCoordinator.setFallbackNoticeEnabled(enabled, this.buildSettingsBoundary())
      .then((settings: SearchEngineSettings) => {
        this.state = this.viewModel.buildState(settings, sharedSearchEngineRepository.listEngines());
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.refreshState();
      });
  }

  private updateSearchHistorySuggestions(enabled: boolean): void {
    const nextPreferences: SearchSuggestionPreferences =
      this.viewModel.buildSearchSuggestionPreferences(enabled, this.state.remoteSuggestionsEnabled);
    this.updateSearchSuggestionPreferences(nextPreferences);
  }

  private updateRemoteSearchSuggestions(enabled: boolean): void {
    const nextPreferences: SearchSuggestionPreferences =
      this.viewModel.buildSearchSuggestionPreferences(this.state.historySuggestionsEnabled, enabled);
    this.updateSearchSuggestionPreferences(nextPreferences);
  }

  private updateSearchSuggestionPreferences(nextPreferences: SearchSuggestionPreferences): void {
    sharedSearchEngineSettingsCoordinator.updateSuggestionPreferences(nextPreferences, this.buildSettingsBoundary())
      .then((settings: SearchEngineSettings) => {
        this.state = this.viewModel.buildState(settings, sharedSearchEngineRepository.listEngines());
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {});
  }

  private confirmClearSearchHistory(): void {
    if (this.clearingSearchHistory) {
      return;
    }
    showCenteredAlertDialog({
      title: '清除搜索历史',
      message: '会清除地址栏保存的搜索词，不影响网页浏览历史。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.clearSearchHistory();
        }
      }
    });
  }

  private clearSearchHistory(): void {
    if (this.clearingSearchHistory) {
      return;
    }
    this.clearingSearchHistory = true;
    sharedSearchQueryHistoryService.clearRegularProfileSearchHistory({
      dataScope: this.boundary.dataScope,
      privacyMode: this.boundary.privacyMode
    })
      .then((result: SearchQueryHistoryClearResult) => {
        this.showToast(result.removedCount > 0 ? '搜索历史已清除。' : '当前没有搜索历史。');
      })
      .catch((_error: Error) => {
        this.showToast('清除搜索历史失败，请稍后再试。');
      })
      .finally(() => {
        this.clearingSearchHistory = false;
      });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_error) {
    }
  }

  private buildForwardRouteParams(): BrowserBoundaryRouteState {
    return {
      dataScope: this.boundary.dataScope,
      privacyMode: this.boundary.privacyMode,
      boundarySource: this.boundary.boundarySource
    };
  }

  private buildSettingsBoundary(): SearchSettingsBoundary {
    return new SearchSettingsBoundary(this.boundary.dataScope, this.boundary.privacyMode);
  }

  private resolveExternalAppSearchSummary(): string {
    if (!this.externalAppSearchPreferences.enabled) {
      return '已关闭';
    }
    return `已开启 ${this.externalAppSearchPreferences.selectedTargetIds.length} 个`;
  }
}
