import promptAction from '@ohos.promptAction';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import {
  SecureDnsCustomProfileDraft,
  SecureDnsCustomProfileMutationResult
} from '../../../core/settings/SecureDnsSettingsCoordinator';
import { sharedSecureDnsSettingsCoordinator } from '../../bootstrap/BrowserAppRuntime';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import {
  SettingsPresentationScrollBody,
  SettingsScrollBody,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsActionButton,
  SettingsTextField
} from './SettingsRows';
import { SettingsDesktopWorkspaceHeader } from './SettingsDesktopWorkspaceHeader';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';

export type SecureDnsProfileEditPresentationMode = 'page' | 'dialog' | 'workspace';

@CustomDialog
export struct SecureDnsProfileEditDialog {
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  controller?: CustomDialogController;

  build() {
    CenteredDialogSurface() {
      SecureDnsProfileEditHost({
        presentationMode: 'dialog',
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        onBack: (): void => {
          this.controller?.close();
        }
      })
        .width('100%')
    }
  }
}

@Component
export struct SecureDnsProfileEditHost {
  @Prop profileId: string = '';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop presentationMode: SecureDnsProfileEditPresentationMode = 'page';
  @Prop desktopPresentation: boolean = false;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private draft: SecureDnsCustomProfileDraft = {
    id: '',
    name: '',
    endpoint: '',
    nameError: '',
    endpointError: ''
  };
  @State private saving: boolean = false;
  @State private deleting: boolean = false;
  onBack?: () => void;

  aboutToAppear(): void {
    this.draft = sharedSecureDnsSettingsCoordinator.buildCustomProfileDraft(this.profileId);
    if (this.profileId.length > 0 && this.draft.id.length === 0) {
      promptAction.showToast({ message: '这个自定义 DNS 已不存在。', duration: 1800 });
      this.onBack?.();
    }
  }

  build() {
    if (this.presentationMode === 'dialog') {
      this.buildDialogContent()
    } else if (this.presentationMode === 'workspace') {
      this.buildWorkspaceContent()
    } else {
      this.buildPageContent()
    }
  }

  @Builder
  private buildWorkspaceContent() {
    Column() {
      SettingsDesktopWorkspaceHeader({
        title: this.draft.id.length > 0 ? '编辑自定义 DNS' : '添加自定义 DNS',
        showBackButton: true,
        primaryTextColor: this.storedPrimaryTextColor,
        iconColor: this.storedSecondaryTextColor,
        buttonBackgroundColor: this.storedPressedBackgroundColor,
        onBack: () => {
          this.onBack?.();
        }
      })
      SettingsPresentationScrollBody({
        desktopPresentation: true,
        topPadding: 16,
        bottomPadding: 28
      }) {
        Column({ space: 16 }) {
          this.buildFieldsSection()
          this.buildActionsSection()
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildPageContent() {
    Column() {
      SettingsHdsScaffold({
        title: this.draft.id.length > 0 ? '编辑自定义 DNS' : '添加自定义 DNS',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
        onBack: (): void => {
          this.onBack?.();
        }
      }) {
        SettingsScrollBody({ topPadding: 16, bottomPadding: 28 }) {
          Column({ space: 16 }) {
            this.buildFieldsSection()
            this.buildActionsSection()
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildDialogContent() {
    Column({ space: 16 }) {
      Text('添加自定义 DNS')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      this.buildFieldsSection()

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          actionEnabled: !this.saving && !this.deleting,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.onBack?.();
          }
        })

        BrowserSheetActionButton({
          label: this.saving ? '保存中...' : '保存并使用',
          emphasis: 'primary',
          actionEnabled: !this.saving && !this.deleting,
          accentColor: this.storedAccentColor,
          textColor: this.storedOnPrimaryColor,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            void this.saveProfile();
          }
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildFieldsSection() {
    SettingsSection({
      title: '',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 16 }) {
        SettingsTextField({
          desktopPresentation: this.desktopPresentation,
          label: '名称',
          text: this.draft.name,
          placeholder: '例如：家庭 DNS / 公司 DNS',
          errorText: this.draft.nameError,
          isEnabled: !this.saving && !this.deleting,
          maxLength: 80,
          controlBackgroundColor: this.resolveFieldBackgroundColor(),
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onChange: (value: string): void => {
            this.draft = this.copyDraft(value, this.draft.endpoint, '', this.draft.endpointError);
          }
        })

        SettingsTextField({
          desktopPresentation: this.desktopPresentation,
          label: 'DoH 地址',
          text: this.draft.endpoint,
          placeholder: 'https://example.com/dns-query',
          errorText: this.draft.endpointError,
          isEnabled: !this.saving && !this.deleting,
          inputType: InputType.URL,
          maxLength: 2048,
          controlBackgroundColor: this.resolveFieldBackgroundColor(),
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onChange: (value: string): void => {
            this.draft = this.copyDraft(this.draft.name, value, this.draft.nameError, '');
          }
        })
      }
      .width('100%')
    }
  }

  @Builder
  private buildActionsSection() {
    SettingsSection({
      title: '',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 10 }) {
        SettingsActionButton({
          title: this.resolveSaveButtonTitle(),
          variant: 'filled',
          isEnabled: !this.saving && !this.deleting,
          accentColor: this.storedAccentColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: (): void => {
            void this.saveProfile();
          }
        })

        if (this.draft.id.length > 0) {
          SettingsActionButton({
            title: this.deleting ? '删除中...' : '删除 DNS',
            emphasis: 'danger',
            isEnabled: !this.saving && !this.deleting,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onAction: (): void => {
              this.confirmDeleteProfile();
            }
          })
        }
      }
      .width('100%')
    }
  }

  private async saveProfile(): Promise<void> {
    if (this.saving || this.deleting) {
      return;
    }
    this.saving = true;
    const activate = this.draft.id.length === 0;
    const result = await sharedSecureDnsSettingsCoordinator.saveCustomProfileDraft(
      this.draft,
      this.buildBoundaryInput(),
      activate
    );
    this.saving = false;
    this.draft = result.draft;
    if (!result.success) {
      this.showMessage(result.message);
      return;
    }
    this.onBack?.();
  }

  private async deleteProfile(): Promise<void> {
    if (this.saving || this.deleting || this.draft.id.length === 0) {
      return;
    }
    this.deleting = true;
    const result: SecureDnsCustomProfileMutationResult =
      await sharedSecureDnsSettingsCoordinator.deleteCustomProfileDraft(
        this.draft,
        this.buildBoundaryInput()
      );
    this.deleting = false;
    this.draft = result.draft;
    if (!result.success) {
      this.showMessage(result.message);
      return;
    }
    this.onBack?.();
  }

  private confirmDeleteProfile(): void {
    const profileName = this.draft.name.trim().length > 0 ? this.draft.name.trim() : '这个 DNS';
    showCenteredAlertDialog({
      title: '删除自定义 DNS',
      message: `确定删除“${profileName}”吗？如果它正在使用，将回退到系统 DNS。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: (): void => {
          void this.deleteProfile();
        }
      }
    });
  }

  private resolveSaveButtonTitle(): string {
    if (this.saving) {
      return '保存中...';
    }
    return this.draft.id.length > 0 ? '保存' : '保存并使用';
  }

  private resolveFieldBackgroundColor(): ResourceColor {
    return this.presentationMode === 'dialog'
      ? this.storedControlBackgroundColor
      : this.storedSurfaceBackgroundColor;
  }

  private copyDraft(
    name: string,
    endpoint: string,
    nameError: string,
    endpointError: string
  ): SecureDnsCustomProfileDraft {
    return {
      id: this.draft.id,
      name: name,
      endpoint: endpoint,
      nameError: nameError,
      endpointError: endpointError
    };
  }

  private buildBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private showMessage(message: string): void {
    if (message.length > 0) {
      promptAction.showToast({ message: message, duration: 1800 });
    }
  }
}
