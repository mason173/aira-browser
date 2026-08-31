import router from '@ohos.router';
import {
  SearchEngineManagementViewModel,
  SearchEngineRowView
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
import {
  isPrivateBoundaryRoute,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsFooterText,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsOptionRow } from '../settings/SettingsRows';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';
import { SearchEngineIconResources } from './SearchEngineIconResources';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { SearchSettingsBoundary } from '../../../core/search/SearchEngineSettingsCoordinator';

/**
 * 备用搜索引擎选择页的共享主体：手机端由 SearchFallbackEnginePage 全屏承载，大屏端由
 * 搜索面板就地承载。选中后即返回上一层（onBack）。
 */
@Component
export struct SearchFallbackEngineHost {
  private viewModel: SearchEngineManagementViewModel = new SearchEngineManagementViewModel();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private themePreferencesListenerKey: string = '';
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  onBack?: () => void;
  @State private rows: SearchEngineRowView[] = this.viewModel.buildFallbackEngineRows(
    sharedSearchEngineRepository.getSettings(),
    sharedSearchEngineRepository.listEngines()
  );
  @State private isSelectingOption: boolean = false;
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.isSelectingOption = false;
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  build() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '备用搜索引擎',
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
        title: '备用搜索引擎',
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
        SettingsPresentationScrollBody({
          contentSpace: 18,
          desktopPresentation: this.desktopPresentation,
          topPadding: 16,
          bottomPadding: 32
        }) {
          this.buildEngineSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.theme.pageBackground)
  }

  @Builder
  private buildEngineSection() {
    SettingsSection({
      title: '主搜索引擎不可用时使用',
      secondaryTextColor: this.theme.textSecondary
    }) {
      SettingsGroupCard({
        surfaceColor: this.theme.surfaceBackground,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.rows, (engine: SearchEngineRowView, index: number) => {
          this.buildEngineRow(engine, index, this.rows.length)
          if (index < this.rows.length - 1) {
            SettingsGroupDivider({ dividerColor: this.theme.divider })
          }
        }, (engine: SearchEngineRowView) => this.resolveEngineRenderKey(engine))
      }
      SettingsFooterText({
        text: '这里不会改变默认搜索引擎，只决定自动回退时使用哪个搜索引擎。',
        secondaryTextColor: this.theme.textSecondary
      })
    }
  }

  @Builder
  private buildEngineRow(engine: SearchEngineRowView, index: number, total: number) {
    SettingsOptionRow({
      title: engine.title,
      desktopPresentation: this.desktopPresentation,
      leadingIcon: SearchEngineIconResources.builtInIcon(engine.id) === undefined ?
        $r('sys.symbol.magnifyingglass') :
        undefined,
      leadingImage: SearchEngineIconResources.builtInIcon(engine.id),
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: engine.isDefault,
      isEnabled: !this.isSelectingOption,
      radioGroup: 'fallback-search-engine',
      radioValue: engine.id,
      primaryTextColor: this.theme.textPrimary,
      secondaryTextColor: this.theme.textSecondary,
      pressedBackgroundColor: this.theme.pressedBackground,
      selectedIndicatorColor: this.theme.accent,
      onAction: (): void => {
        this.requestSelectEngine(engine.id);
      }
    })
  }

  private refreshState(): void {
    if (this.embedded) {
      // 大屏就地承载时边界由外部传入，不读路由参数。
    } else {
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
    this.rows = this.viewModel.buildFallbackEngineRows(
      sharedSearchEngineRepository.getSettings(),
      sharedSearchEngineRepository.listEngines()
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

  private requestSelectEngine(engineId: SearchEngineId): void {
    if (this.isSelectingOption) {
      return;
    }
    const selected = this.rows.find((row: SearchEngineRowView): boolean => row.id === engineId);
    if (selected?.isDefault === true) {
      this.handleBack();
      return;
    }
    this.isSelectingOption = true;
    sharedSearchEngineSettingsCoordinator.setFallbackEngine(
      engineId,
      new SearchSettingsBoundary(this.dataScope, this.privacyMode)
    )
      .then((_settings: SearchEngineSettings) => {
        this.handleBack();
      })
      .catch((_error: Error) => {
        this.isSelectingOption = false;
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

  private resolveEngineRenderKey(engine: SearchEngineRowView): string {
    return `${this.storedResolvedThemeMode}:${engine.id}:${engine.isDefault ? '1' : '0'}:${engine.title}`;
  }

  private handleBack(): void {
    if (this.onBack !== undefined) {
      this.onBack();
      return;
    }
    router.back();
  }
}
