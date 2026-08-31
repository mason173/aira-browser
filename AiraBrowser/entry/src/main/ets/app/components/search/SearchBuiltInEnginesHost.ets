import router from '@ohos.router';
import {
  BuiltInSearchEngineVisibilityRowView,
  SearchEngineManagementViewModel
} from '../../../core/search/SearchEngineManagementViewModel';
import {
  SearchEngineId,
  SearchEngineSettings
} from '../../../common/models/BrowserModels';
import {
  sharedPreferencesRepository,
  sharedSearchEngineRepository,
  sharedSearchEngineSettingsCoordinator
} from '../../bootstrap/BrowserAppRuntime';
import { readBrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import { SearchBuiltInEngineVisibilityScreen } from './SearchBuiltInEngineVisibilityScreen';
import { SearchSettingsBoundary } from '../../../core/search/SearchEngineSettingsCoordinator';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';

/**
 * 内置搜索引擎显隐页的共享主体：手机端由 SearchBuiltInEnginesPage 全屏承载，大屏端由默认
 * 引擎面板就地承载。返回通过 onBack 回调。
 */
@Component
export struct SearchBuiltInEnginesHost {
  private viewModel: SearchEngineManagementViewModel = new SearchEngineManagementViewModel();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private themePreferencesListenerKey: string = '';
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop showDesktopHeader: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  @Prop revealTargetId: string = '';
  @Prop revealRevision: number = 0;
  onBack?: () => void;
  @State private rows: BuiltInSearchEngineVisibilityRowView[] =
    this.viewModel.buildBuiltInVisibilityRows(
      sharedSearchEngineRepository.getSettings(),
      sharedSearchEngineRepository.listBuiltInEngineCandidates()
    );
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  build() {
    Column() {
      if (this.desktopPresentation && this.showDesktopHeader) {
        SettingsDesktopWorkspaceHeader({
          title: '更多搜索引擎',
          showBackButton: true,
          primaryTextColor: this.theme.textPrimary,
          iconColor: this.theme.accent,
          buttonBackgroundColor: this.theme.controlBackground,
          onBack: () => {
            this.handleBack();
          }
        })
      }

      SearchBuiltInEngineVisibilityScreen({
        rows: this.rows,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        theme: this.theme,
        useTopSafeInset: !this.embedded,
        desktopPresentation: this.desktopPresentation,
        revealTargetId: this.revealTargetId,
        revealRevision: this.revealRevision,
        onBack: () => {
          this.handleBack();
        },
        onToggleEngine: (engineId: SearchEngineId, enabled: boolean) => {
          this.toggleEngine(engineId, enabled);
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
    if (!this.embedded) {
      const boundaryState = readBrowserBoundaryRouteState({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      });
      this.dataScope = boundaryState.dataScope;
      this.privacyMode = boundaryState.privacyMode;
      this.boundarySource = boundaryState.boundarySource;
    }
    this.refreshThemeState();
    this.rows = this.viewModel.buildBuiltInVisibilityRows(
      sharedSearchEngineRepository.getSettings(),
      sharedSearchEngineRepository.listBuiltInEngineCandidates()
    );
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

  private toggleEngine(engineId: SearchEngineId, enabled: boolean): void {
    sharedSearchEngineSettingsCoordinator.setBuiltInEngineEnabled(
      engineId,
      enabled,
      new SearchSettingsBoundary(this.dataScope, this.privacyMode)
    )
      .then((settings: SearchEngineSettings) => {
        this.rows = this.viewModel.buildBuiltInVisibilityRows(
          settings,
          sharedSearchEngineRepository.listBuiltInEngineCandidates()
        );
      })
      .catch((_error: Error) => {
        this.refreshState();
      });
  }

  private handleBack(): void {
    if (this.onBack !== undefined) {
      this.onBack();
      return;
    }
    router.back();
  }
}
