import {
  TranslationProviderConfig,
  TranslationProviderTemplateId
} from '../../../common/models/BrowserModels';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  TranslationProviderEditDraft,
  TranslationProviderEditViewModel
} from '../../../core/translation/TranslationProviderEditViewModel';
import {
  TranslationSettingsBoundary,
  TranslationSettingsCoordinator,
  TranslationProviderConfigSaveResult,
  TranslationSettingsMutationResult
} from '../../../core/translation/TranslationSettingsCoordinator';
import {
  WebpageTranslationSettingsViewModel,
  WebpageTranslationSettingsViewState
} from '../../../core/translation/WebpageTranslationSettingsViewModel';
import {
  sharedTranslationSecretStore,
  sharedTranslationSettingsRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';
import { TranslationProviderEditScreen } from './TranslationProviderEditScreen';
import { TranslationProviderConfigScreen } from './TranslationProviderConfigScreen';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';

export type TranslationProviderWorkspaceStartMode = 'selection' | 'config';

@CustomDialog
struct TranslationProviderWorkspaceValidationDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;

  build() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(34)
        .height(34)
        .color(this.storedAccentColor)
      Text('正在测试翻译服务')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
      Text('正在联网校验 API 配置，请稍候。')
        .fontSize(14)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .fontColor(this.storedSecondaryTextColor)
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }
}

@Component
export struct TranslationProviderWorkspaceHost {
  private settingsViewModel: WebpageTranslationSettingsViewModel = new WebpageTranslationSettingsViewModel();
  private editViewModel: TranslationProviderEditViewModel = new TranslationProviderEditViewModel();
  private coordinator: TranslationSettingsCoordinator = new TranslationSettingsCoordinator(
    sharedTranslationSettingsRepository,
    sharedTranslationSecretStore
  );
  private providerId: string = '';
  private configReturnsToSelection: boolean = false;
  private validationDialogController: CustomDialogController = new CustomDialogController({
    builder: TranslationProviderWorkspaceValidationDialog(),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true
  });
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop startMode: TranslationProviderWorkspaceStartMode = 'selection';
  @Prop initialProviderId: string = '';
  @Prop initialTemplateId: TranslationProviderTemplateId = 'custom_http';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  onBack?: () => void;
  onSettingsChanged?: () => void;
  @State private activeView: TranslationProviderWorkspaceStartMode = 'selection';
  @State private settingsState: WebpageTranslationSettingsViewState =
    this.settingsViewModel.buildState(sharedTranslationSettingsRepository.getSettings());
  @State private draft: TranslationProviderEditDraft = this.editViewModel.buildInitialDraft('custom_http');
  @State private errorMessage: string = '';
  @State private isSaving: boolean = false;

  aboutToAppear(): void {
    this.activeView = this.startMode;
    this.refreshSettingsState();
    if (this.startMode === 'config') {
      this.openInitialConfig();
    }
  }

  build() {
    Column() {
      SettingsDesktopWorkspaceHeader({
        title: this.resolveHeaderTitle(),
        showBackButton: true,
        primaryTextColor: this.storedPrimaryTextColor,
        iconColor: this.storedSecondaryTextColor,
        buttonBackgroundColor: this.storedPressedBackgroundColor,
        primaryActionText: this.activeView === 'config' ? '保存' : '',
        primaryActionLabel: '保存翻译服务配置',
        primaryActionEnabled: this.activeView === 'config' &&
          this.editViewModel.buildState(this.draft, this.errorMessage).saveEnabled &&
          !this.isSaving,
        onBack: () => {
          this.handleBack();
        },
        onPrimaryAction: () => {
          this.saveProvider();
        }
      })

      if (this.activeView === 'selection') {
        TranslationProviderEditScreen({
          providers: this.settingsState.providers,
          showBackButton: false,
          showTitleBar: false,
          useTopSafeInset: false,
          desktopPresentation: true,
          onSelectProvider: (providerId: string) => {
            this.selectProvider(providerId);
          },
          onConfigureTemplate: (templateId: TranslationProviderTemplateId) => {
            this.openTemplateConfig(templateId, true);
          }
        })
          .width('100%')
          .layoutWeight(1)
      } else {
        TranslationProviderConfigScreen({
          state: this.editViewModel.buildState(this.draft, this.errorMessage),
          securityMessage: sharedTranslationSecretStore.getInfo().message,
          isSaving: this.isSaving,
          showBackButton: false,
          showTitleBar: false,
          useTopSafeInset: false,
          desktopPresentation: true,
          onFieldChange: (key: string, value: string) => {
            this.updateField(key, value);
          },
          onSave: () => {
            this.saveProvider();
          }
        })
          .width('100%')
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  private refreshSettingsState(): void {
    this.settingsState = this.settingsViewModel.buildState(sharedTranslationSettingsRepository.getSettings());
  }

  private openInitialConfig(): void {
    if (this.initialProviderId.length > 0) {
      this.openProviderConfig(this.initialProviderId, false);
      return;
    }
    this.openTemplateConfig(this.initialTemplateId, false);
  }

  private openTemplateConfig(templateId: TranslationProviderTemplateId, returnToSelection: boolean): void {
    this.providerId = '';
    this.configReturnsToSelection = returnToSelection;
    this.draft = this.editViewModel.buildDraftForTemplate(templateId);
    this.errorMessage = '';
    this.activeView = 'config';
  }

  private openProviderConfig(providerId: string, returnToSelection: boolean): void {
    this.providerId = providerId;
    this.configReturnsToSelection = returnToSelection;
    this.errorMessage = '';
    this.activeView = 'config';
    void this.loadProviderDraft(providerId);
  }

  private async loadProviderDraft(providerId: string): Promise<void> {
    const provider = sharedTranslationSettingsRepository.getSettings().providers.find(
      (item: TranslationProviderConfig): boolean => item.id === providerId
    );
    if (provider === undefined) {
      return;
    }
    const editableProvider = await this.coordinator.buildEditableProvider(provider, this.buildSettingsBoundary());
    if (this.providerId !== providerId) {
      return;
    }
    this.draft = this.editViewModel.buildDraftFromProvider(editableProvider);
    this.errorMessage = '';
  }

  private selectProvider(providerId: string): void {
    this.coordinator.selectProvider(providerId, this.buildSettingsBoundary())
      .then((result: TranslationSettingsMutationResult) => {
        if (!result.allowed) {
          return;
        }
        this.refreshSettingsState();
        this.onSettingsChanged?.();
        this.onBack?.();
      })
      .catch((_error: Error) => {});
  }

  private updateField(key: string, value: string): void {
    this.draft = this.editViewModel.updateDraft(
      this.draft,
      key as 'displayName' | 'endpoint' | 'apiKey' | 'appId' | 'secretKey' | 'region' | 'model',
      value
    );
    this.errorMessage = '';
  }

  private saveProvider(): void {
    if (this.isSaving) {
      return;
    }
    const state = this.editViewModel.buildState(this.draft, '');
    if (!state.saveEnabled) {
      this.errorMessage = state.errorMessage;
      this.showDialog('保存失败', state.errorMessage);
      return;
    }
    const provider = this.editViewModel.buildProvider(this.draft);
    showCenteredAlertDialog({
      title: '启用翻译服务？',
      message: this.coordinator.buildSaveConfirmationMessage(provider),
      autoCancel: true,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '保存并启用',
        action: () => {
          this.persistProvider();
        }
      }
    });
  }

  private persistProvider(): void {
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = '';
    this.validationDialogController.open();
    this.coordinator.saveConfiguredProvider(this.draft, this.buildSettingsBoundary())
      .then((result: TranslationProviderConfigSaveResult) => {
        this.isSaving = false;
        this.validationDialogController.close();
        if (!result.ok) {
          this.showToast('翻译服务验证失败。');
          this.showDialog('连接校验失败', result.message);
          return;
        }
        this.showToast('翻译服务验证成功。');
        this.refreshSettingsState();
        this.onSettingsChanged?.();
        this.finishConfig();
      })
      .catch((error: Error) => {
        this.isSaving = false;
        this.validationDialogController.close();
        this.showToast('翻译服务验证失败。');
        this.showDialog('连接校验失败', error.message);
      });
  }

  private finishConfig(): void {
    if (this.configReturnsToSelection) {
      this.activeView = 'selection';
      return;
    }
    this.onBack?.();
  }

  private handleBack(): void {
    if (this.activeView === 'config' && this.configReturnsToSelection) {
      this.activeView = 'selection';
      return;
    }
    this.onBack?.();
  }

  private resolveHeaderTitle(): string {
    if (this.activeView === 'selection') {
      return '选择翻译服务';
    }
    return this.editViewModel.buildState(this.draft, this.errorMessage).title;
  }

  private buildSettingsBoundary(): TranslationSettingsBoundary {
    return new TranslationSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (_error) {}
  }

  private showDialog(title: string, message: string): void {
    showCenteredAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      confirm: { value: '知道了', action: () => {} }
    });
  }
}
