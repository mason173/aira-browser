import { SearchEngineEditScreen } from './SearchEngineEditScreen';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  SearchEngineEditorState,
  SearchEngineManagementViewModel
} from '../../../core/search/SearchEngineManagementViewModel';
import {
  sharedPreferencesRepository,
  sharedSearchEngineRepository,
  sharedSearchEngineSettingsCoordinator
} from '../../bootstrap/BrowserAppRuntime';
import { SearchEngineRecord } from '../../../common/models/BrowserModels';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import { SearchSettingsBoundary } from '../../../core/search/SearchEngineSettingsCoordinator';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';

/**
 * 搜索引擎编辑页的共享主体：手机端由 SearchEngineEditPage 全屏承载，大屏端由默认引擎面板
 * 就地承载。引擎 id 通过 @Prop 传入，保存/删除/返回统一走 onBack 回调。
 */
@Component
export struct SearchEngineEditHost {
  private viewModel: SearchEngineManagementViewModel = new SearchEngineManagementViewModel();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private themePreferencesListenerKey: string = '';
  private editingEngine?: SearchEngineRecord = undefined;
  @Prop engineId: string = '';
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  onBack?: () => void;
  @State private name: string = '';
  @State private searchUrlTemplate: string = '';
  @State private state: SearchEngineEditorState = this.viewModel.buildEditorState(undefined, '', '');
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshThemeState();
    this.editingEngine = this.engineId.length > 0 ? sharedSearchEngineRepository.findEngine(this.engineId) : undefined;
    this.name = this.editingEngine?.name ?? '';
    this.searchUrlTemplate = this.editingEngine?.searchUrlTemplate ?? '';
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  build() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: this.state.title,
          showBackButton: true,
          primaryTextColor: this.theme.textPrimary,
          iconColor: this.theme.accent,
          buttonBackgroundColor: this.theme.controlBackground,
          primaryActionText: '保存',
          primaryActionLabel: '保存搜索引擎',
          onBack: () => {
            this.onBack?.();
          },
          onPrimaryAction: () => {
            this.saveEngine();
          }
        })
      }

      SearchEngineEditScreen({
        state: this.state,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        pageBackground: this.theme.pageBackground,
        surfaceBackground: this.theme.surfaceBackground,
        controlBackground: this.theme.controlBackground,
        headerButtonBackground: this.theme.controlBackground,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        desktopPresentation: this.desktopPresentation,
        showBackButton: !this.desktopPresentation,
        showTitleBar: !this.desktopPresentation,
        useTopSafeInset: !this.embedded,
        onBack: () => {
          this.onBack?.();
        },
        onNameChange: (value: string) => {
          this.name = value;
          this.refreshState();
        },
        onTemplateChange: (value: string) => {
          this.searchUrlTemplate = value;
          this.refreshState();
        },
        onSave: () => {
          this.saveEngine();
        },
        onDelete: () => {
          this.confirmDeleteEngine();
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

  private refreshState(): void {
    this.state = this.viewModel.buildEditorState(this.editingEngine, this.name, this.searchUrlTemplate);
  }

  private saveEngine(): void {
    if (!this.state.saveEnabled) {
      const errorMessage = this.viewModel.buildEditorSubmitError(this.name, this.searchUrlTemplate);
      if (errorMessage.length > 0) {
        this.state = {
          title: this.state.title,
          name: this.state.name,
          searchUrlTemplate: this.state.searchUrlTemplate,
          errorMessage: errorMessage,
          saveEnabled: false,
          deleteEnabled: this.state.deleteEnabled
        };
        this.showToast(errorMessage);
      }
      return;
    }
    sharedSearchEngineSettingsCoordinator.saveCustomEngine(
      this.editingEngine?.id,
      this.name,
      this.searchUrlTemplate,
      this.buildSettingsBoundary()
    )
      .then(() => {
        this.onBack?.();
      })
      .catch((error: Error) => {
        this.state = {
          title: this.state.title,
          name: this.state.name,
          searchUrlTemplate: this.state.searchUrlTemplate,
          errorMessage: error.message,
          saveEnabled: false,
          deleteEnabled: this.state.deleteEnabled
        };
        this.showToast(error.message);
      });
  }

  private showToast(message: string): void {
    if (message.trim().length <= 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_error) {}
  }

  private deleteEngine(): void {
    if (this.editingEngine === undefined || !this.editingEngine.isEditable) {
      return;
    }
    sharedSearchEngineSettingsCoordinator.deleteCustomEngine(this.editingEngine.id, this.buildSettingsBoundary())
      .then(() => {
        this.onBack?.();
      })
      .catch((_error: Error) => {});
  }

  private confirmDeleteEngine(): void {
    if (this.editingEngine === undefined || !this.editingEngine.isEditable) {
      return;
    }
    showCenteredAlertDialog({
      title: '删除搜索引擎',
      message: this.viewModel.buildDeleteConfirmationMessage(this.editingEngine),
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.deleteEngine();
        }
      }
    });
  }

  private buildSettingsBoundary(): SearchSettingsBoundary {
    return new SearchSettingsBoundary(this.dataScope, this.privacyMode);
  }
}
