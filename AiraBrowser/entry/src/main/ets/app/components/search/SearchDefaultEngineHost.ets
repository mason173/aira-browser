import router from '@ohos.router';
import {
  SearchEngineManagementState,
  SearchEngineManagementViewModel,
  SearchEngineRowView
} from '../../../core/search/SearchEngineManagementViewModel';
import {
  sharedPreferencesRepository,
  sharedSearchEngineRepository,
  sharedSearchEngineSettingsCoordinator
} from '../../bootstrap/BrowserAppRuntime';
import { SearchEngineId, SearchEngineSettings } from '../../../common/models/BrowserModels';
import {
  BrowserBoundaryRouteState,
  isPrivateBoundaryRoute,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsOptionRow
} from '../settings/SettingsRows';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { SearchDefaultEngineBuiltInList } from './SearchDefaultEngineBuiltInList';
import { SearchEngineEditHost } from './SearchEngineEditHost';
import { SearchBuiltInEnginesHost } from './SearchBuiltInEnginesHost';
import { SearchSettingsBoundary } from '../../../core/search/SearchEngineSettingsCoordinator';

/**
 * 默认搜索引擎页的共享主体：手机端由 SearchDefaultEnginePage 全屏承载，大屏端由搜索面板
 * 就地承载。选中引擎后即返回上一层（onBack）。编辑引擎/管理内置引擎目前仍走全屏路由，
 * 后续子步会改成就地。
 */
@Component
export struct SearchDefaultEngineHost {
  private viewModel: SearchEngineManagementViewModel = new SearchEngineManagementViewModel();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private themePreferencesListenerKey: string = '';
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  onBack?: () => void;
  @State private state: SearchEngineManagementState =
    this.viewModel.buildState(sharedSearchEngineRepository.getSettings(), sharedSearchEngineRepository.listEngines());
  @State private isSelectingOption: boolean = false;
  @State private isLeaving: boolean = false;
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @State private deepView: string = 'main';
  @State private editingEngineId: string = '';

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.isSelectingOption = false;
    this.isLeaving = false;
    this.syncBoundaryRouteState();
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  build() {
    if (this.embedded && this.deepView === 'edit') {
      SearchEngineEditHost({
        embedded: true,
        desktopPresentation: this.desktopPresentation,
        engineId: this.editingEngineId,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        onBack: () => {
          this.deepView = 'main';
          this.refreshState();
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.embedded && this.deepView === 'built_in') {
      SearchBuiltInEnginesHost({
        embedded: true,
        desktopPresentation: this.desktopPresentation,
        showDesktopHeader: this.desktopPresentation,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        onBack: () => {
          this.deepView = 'main';
          this.refreshState();
        }
      })
        .width('100%')
        .height('100%')
    } else {
      this.buildDefaultEngineContent()
    }
  }

  @Builder
  private buildDefaultEngineContent() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '默认搜索引擎',
          showBackButton: true,
          primaryTextColor: this.theme.textPrimary,
          iconColor: this.theme.accent,
          buttonBackgroundColor: this.theme.controlBackground,
          onBack: () => {
            this.handleBack();
          }
        })
      }

      SettingsHdsScaffold({
        title: '默认搜索引擎',
        backIconKind: 'back',
        pageBackground: this.theme.pageBackground,
        headerButtonBackground: this.theme.controlBackground,
        primaryTextColor: this.theme.textPrimary,
        dividerColor: this.theme.divider,
        showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
        showBackButton: !this.desktopPresentation,
        showTitleBar: !this.desktopPresentation,
        useTopSafeInset: !this.embedded,
        desktopPresentation: this.desktopPresentation,
        onBack: () => {
          this.handleBack();
        }
      }) {
        this.buildOptionSubpage()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.theme.pageBackground)
  }

  private syncBoundaryRouteState(): void {
    if (this.embedded) {
      this.refreshThemeState();
      return;
    }
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.refreshThemeState();
  }

  @Builder
  private buildOptionSubpage() {
    SettingsPresentationScrollBody({
      contentSpace: 18,
      desktopPresentation: this.desktopPresentation,
      topPadding: 16,
      bottomPadding: 32
    }) {
      this.buildOptionContent()
    }
  }

  @Builder
  private buildOptionContent() {
    Column({ space: 18 }) {
      this.buildBuiltInSection()
      this.buildBuiltInManagerSection()
      this.buildCustomSection()
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private buildBuiltInSection() {
    SearchDefaultEngineBuiltInList({
      engines: this.state.builtInEngines,
      isEnabled: !this.isSelectingOption && !this.isLeaving,
      theme: this.theme,
      desktopPresentation: this.desktopPresentation,
      onSelectEngine: (engineId: SearchEngineId) => {
        this.requestSelectEngine(engineId);
      },
      onReorderEngines: (engineIds: SearchEngineId[]) => {
        this.persistBuiltInOrder(engineIds);
      }
    })
  }

  @Builder
  private buildBuiltInManagerSection() {
    SettingsGroupCard({
      surfaceColor: this.theme.surfaceBackground,
      desktopPresentation: this.desktopPresentation
    }) {
      SettingsNavigationRow({
        title: '管理更多搜索引擎',
        desktopPresentation: this.desktopPresentation,
        value: `${this.state.builtInEngines.length} 个常用`,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        pressedBackgroundColor: this.theme.pressedBackground,
        rowPosition: 'single',
        onAction: () => {
          this.openBuiltInEngineManager();
        }
      })
    }
  }

  @Builder
  private buildCustomSection() {
    SettingsSection({
      title: '自定义搜索引擎',
      secondaryTextColor: this.theme.textSecondary
    }) {
      if (this.state.customEngines.length > 0) {
        SettingsGroupCard({
          surfaceColor: this.theme.surfaceBackground,
          desktopPresentation: this.desktopPresentation
        }) {
          ForEach(this.state.customEngines, (engine: SearchEngineRowView, index: number) => {
            this.buildCustomOptionRow(engine, index, this.state.customEngines.length)
            if (index < this.state.customEngines.length - 1) {
              SettingsGroupDivider({ dividerColor: this.theme.divider })
            }
          }, (engine: SearchEngineRowView) => this.resolveEngineRenderKey(engine))
        }
      }
      SettingsActionButton({
        title: '添加搜索引擎',
        accentColor: this.theme.accent,
        pressedBackgroundColor: this.theme.pressedBackground,
        onAction: () => {
          this.openEditor('');
        }
      })
    }
  }

  @Builder
  private buildCustomOptionRow(engine: SearchEngineRowView, index: number, total: number) {
    SettingsOptionRow({
      title: engine.title,
      desktopPresentation: this.desktopPresentation,
      helperText: engine.subtitle,
      leadingIcon: $r('sys.symbol.magnifyingglass'),
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: engine.isDefault,
      isEnabled: !this.isSelectingOption && !this.isLeaving,
      primaryTextColor: this.theme.textPrimary,
      secondaryTextColor: this.theme.textSecondary,
      pressedBackgroundColor: this.theme.pressedBackground,
      selectedIndicatorColor: this.theme.accent,
      trailingActionIcon: $r('sys.symbol.gearshape_fill'),
      onAction: (): void => {
        this.requestSelectEngine(engine.id);
      },
      onTrailingAction: (): void => {
        this.openEditor(engine.id);
      }
    })
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private resolveEngineRenderKey(engine: SearchEngineRowView): string {
    return `${this.resolveThemeRenderKey()}:${engine.id}:${engine.isDefault ? '1' : '0'}:${engine.subtitle}`;
  }

  private resolveThemeRenderKey(): string {
    return `${this.storedResolvedThemeMode}:${this.theme.pageBackground}:${this.theme.surfaceBackground}:` +
      `${this.theme.controlBackground}:${this.theme.accent}:${this.theme.pressedBackground}:` +
      `${this.theme.textPrimary}:${this.theme.textSecondary}:${this.theme.divider}`;
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

  private refreshState(): void {
    this.state = this.viewModel.buildState(
      sharedSearchEngineRepository.getSettings(),
      sharedSearchEngineRepository.listEngines()
    );
  }

  private persistBuiltInOrder(engineIds: SearchEngineId[]): void {
    sharedSearchEngineSettingsCoordinator.reorderBuiltInEngines(engineIds, this.buildSettingsBoundary())
      .then((_settings: SearchEngineSettings) => {
        this.refreshState();
      })
      .catch((_error: Error) => {
        this.refreshState();
      });
  }

  private resolveRowPosition(index: number, total: number): 'single' | 'first' | 'middle' | 'last' {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === total - 1) {
      return 'last';
    }
    return 'middle';
  }

  private requestSelectEngine(engineId: string): void {
    if (this.isSelectingOption || this.isLeaving) {
      return;
    }
    if (this.findEngineRow(engineId)?.isDefault === true) {
      this.handleBack();
      return;
    }
    this.isSelectingOption = true;
    sharedSearchEngineSettingsCoordinator.setDefaultEngine(engineId, this.buildSettingsBoundary())
      .then((_settings: SearchEngineSettings) => {
        this.refreshState();
      })
      .then(() => {
        this.handleBack();
      })
      .catch((_error: Error) => {
        this.isSelectingOption = false;
      });
  }

  private findEngineRow(engineId: string): SearchEngineRowView | undefined {
    const builtInEngine = this.state.builtInEngines.find((engine: SearchEngineRowView) => engine.id === engineId);
    if (builtInEngine !== undefined) {
      return builtInEngine;
    }
    return this.state.customEngines.find((engine: SearchEngineRowView) => engine.id === engineId);
  }

  private openEditor(engineId: string): void {
    if (this.isLeaving) {
      return;
    }
    if (this.embedded) {
      this.editingEngineId = engineId;
      this.deepView = 'edit';
      return;
    }
    this.navigationCoordinator.openSearchEngineEditor(engineId, this.buildForwardRouteParams());
  }

  private openBuiltInEngineManager(): void {
    if (this.isLeaving) {
      return;
    }
    if (this.embedded) {
      this.deepView = 'built_in';
      return;
    }
    this.navigationCoordinator.openSearchBuiltInEngines(this.buildForwardRouteParams());
  }

  private buildForwardRouteParams(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private buildSettingsBoundary(): SearchSettingsBoundary {
    return new SearchSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private handleBack(): boolean {
    if (this.isLeaving) {
      return true;
    }
    this.isLeaving = true;
    if (this.onBack !== undefined) {
      this.onBack();
      return true;
    }
    router.back();
    return true;
  }
}
