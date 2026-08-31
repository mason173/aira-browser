import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../components/common/CenteredDialogSurface';
import router from '@ohos.router';
import {
  TranslationProviderConfig,
  TranslationProviderTemplateId
} from '../../common/models/BrowserModels';
import {
  TranslationProviderEditDraft,
  TranslationProviderEditViewModel
} from '../../core/translation/TranslationProviderEditViewModel';
import {
  TranslationSettingsBoundary,
  TranslationSettingsCoordinator,
  TranslationProviderConfigSaveResult
} from '../../core/translation/TranslationSettingsCoordinator';
import {
  sharedPreferencesRepository,
  sharedTranslationSecretStore,
  sharedTranslationSettingsRepository
} from '../bootstrap/BrowserAppRuntime';
import { TranslationProviderConfigScreen } from '../components/translation/TranslationProviderConfigScreen';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../components/common/CenteredDialogSurface';

@CustomDialog
struct TranslationProviderValidationDialog {
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

@Entry
@Component
struct TranslationProviderConfigPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private editViewModel: TranslationProviderEditViewModel = new TranslationProviderEditViewModel();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private coordinator: TranslationSettingsCoordinator = new TranslationSettingsCoordinator(
    sharedTranslationSettingsRepository,
    sharedTranslationSecretStore
  );
  private providerId: string = '';
  private validationDialogController: CustomDialogController = new CustomDialogController({
    builder: TranslationProviderValidationDialog(),
    autoCancel: false,
    alignment: DialogAlignment.Center,
    customStyle: true
  });
  @State private draft: TranslationProviderEditDraft = this.editViewModel.buildInitialDraft('custom_http');
  @State private errorMessage: string = '';
  @State private isSaving: boolean = false;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.refreshBoundaryState();
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    this.providerId = params?.providerId ?? '';
    const templateId = this.normalizeTemplateId(params?.templateId);
    if (this.providerId.length > 0) {
      void this.loadProviderDraft(this.providerId);
      return;
    }
    this.draft = this.editViewModel.buildDraftForTemplate(templateId);
    this.errorMessage = '';
  }

  build() {
    Column() {
      TranslationProviderConfigScreen({
        state: this.editViewModel.buildState(this.draft, this.errorMessage),
        securityMessage: sharedTranslationSecretStore.getInfo().message,
        isSaving: this.isSaving,
        onFieldChange: (key: string, value: string) => {
          this.updateField(key, value);
        },
        onSave: () => {
          this.saveProvider();
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private async loadProviderDraft(providerId: string): Promise<void> {
    const provider = sharedTranslationSettingsRepository.getSettings().providers.find((item: TranslationProviderConfig) => {
      return item.id === providerId;
    });
    if (provider !== undefined) {
      const editableProvider = await this.coordinator.buildEditableProvider(provider, this.buildSettingsBoundary());
      this.draft = this.editViewModel.buildDraftFromProvider(editableProvider);
      this.errorMessage = '';
    }
  }

  private updateField(key: string, value: string): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.draft = this.editViewModel.updateDraft(
      this.draft,
      key as 'displayName' | 'endpoint' | 'apiKey' | 'appId' | 'secretKey' | 'region' | 'model',
      value
    );
    this.errorMessage = '';
  }

  private saveProvider(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (this.isSaving) {
      return;
    }
    const state = this.editViewModel.buildState(this.draft, '');
    if (!state.saveEnabled) {
      this.errorMessage = state.errorMessage;
      this.showDialog('保存失败', state.errorMessage);
      return;
    }
    this.showSaveConfirmation();
  }

  private showSaveConfirmation(): void {
    const provider = this.editViewModel.buildProvider(this.draft);
    showCenteredAlertDialog({
      title: '启用翻译服务？',
      message: this.coordinator.buildSaveConfirmationMessage(provider),
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '保存并启用',
        action: () => {
          this.persistProvider();
        }
      }
    });
  }

  private persistProvider(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = '';
    this.validationDialogController.open();
    this.refreshBoundaryState();
    this.coordinator.saveConfiguredProvider(this.draft, this.buildSettingsBoundary())
      .then((result: TranslationProviderConfigSaveResult) => {
        this.isSaving = false;
        this.validationDialogController.close();
        if (result.ok) {
          this.showToast('翻译服务验证成功。');
          this.navigationCoordinator.back();
          return;
        }
        this.showToast('翻译服务验证失败。');
        this.showDialog('连接校验失败', result.message);
      })
      .catch((error: Error) => {
        this.isSaving = false;
        this.validationDialogController.close();
        this.showToast('翻译服务验证失败。');
        this.showDialog('连接校验失败', error.message);
      });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }

  private showDialog(title: string, message: string): void {
    showCenteredAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      confirm: {
        value: '知道了',
        action: () => {
        }
      }
    });
  }

  private normalizeTemplateId(value: string | undefined): TranslationProviderTemplateId {
    const candidate = `${value ?? ''}`.trim();
    if (candidate === 'deepl' ||
      candidate === 'aira_system' ||
      candidate === 'google_cloud' ||
      candidate === 'tencent_cloud' ||
      candidate === 'baidu' ||
      candidate === 'microsoft' ||
      candidate === 'alibaba_cloud' ||
      candidate === 'volcano' ||
      candidate === 'youdao') {
      return candidate as TranslationProviderTemplateId;
    }
    return 'custom_http';
  }

  private refreshBoundaryState(): void {
    const boundary = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundary.dataScope;
    this.privacyMode = boundary.privacyMode;
    this.boundarySource = boundary.boundarySource;
  }

  private buildSettingsBoundary(): TranslationSettingsBoundary {
    return new TranslationSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}
