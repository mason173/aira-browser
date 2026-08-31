import router from '@ohos.router';
import { showCenteredAlertDialog } from '../components/common/CenteredDialogSurface';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';
import { SettingsActionButton } from '../components/settings/SettingsRows';
import { SyncFormField } from '../components/sync/SyncFormFields';
import {
  sharedAiraSyncConfigStore,
  sharedSyncExperienceCoordinator
} from '../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import {
  AiraPersonalServerConfig,
  AiraSyncSettings,
  resolveAiraPersonalServerConfig
} from '../../common/models/AiraSyncModels';
import {
  AIRA_PERSONAL_SERVER_INSTANCE_SERVICE,
  AiraPersonalServerPairingResult
} from '../../services/sync/AiraPersonalServerInstanceService';
import { SyncExperienceActionOutcome } from '../../core/sync/SyncExperienceCoordinator';
import { SyncSettingsRefreshSignal } from '../../core/sync/SyncSettingsRefreshSignal';

@Entry
@Component
struct SyncPersonalServerConfigPage {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F6F8FB';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private refreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal();
  private activateExperienceAfterPair: boolean = false;
  @State private baseUrl: string = '';
  @State private pairingCode: string = '';
  @State private deviceName: string = 'Aira HarmonyOS';
  @State private instanceId: string = '';
  @State private isBusy: boolean = false;
  @State private isConfigured: boolean = false;
  @State private statusText: string = '尚未连接';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    this.activateExperienceAfterPair = params?.syncActivateExperience === 'true';
    void sharedAiraSyncConfigStore.initialize()
      .then((settings: AiraSyncSettings): void => {
        this.applyConfig(resolveAiraPersonalServerConfig(settings));
      })
      .catch((error: Error): void => {
        this.statusText = this.stringifyError(error);
      });
  }

  onBackPress(): boolean {
    return this.isBusy;
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '个人服务器',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
        onBack: () => {
          if (!this.isBusy) {
            this.navigationCoordinator.back();
          }
        }
      }) {
        SettingsScrollBody({ contentSpace: 18, topPadding: 8, bottomPadding: 28 }) {
          SyncFormField({
            label: '服务器地址',
            placeholder: 'https://sync.example.com',
            text: $baseUrl,
            inputType: InputType.URL,
            isEnabled: !this.isBusy,
            onChange: (_value: string) => {}
          })

          SyncFormField({
            label: '一次性配对码',
            placeholder: '输入服务器生成的配对码',
            text: $pairingCode,
            secure: true,
            isEnabled: !this.isBusy,
            onChange: (_value: string) => {}
          })

          SyncFormField({
            label: '设备名称',
            placeholder: 'Aira HarmonyOS',
            text: $deviceName,
            isEnabled: !this.isBusy,
            onChange: (_value: string) => {}
          })

          Text('配对码只使用一次。设备凭据会保存在本机，不会发送华为账号令牌、会员信息或付款数据。公开访问服务器时请使用 HTTPS。')
            .width('100%')
            .fontSize(13)
            .lineHeight(19)
            .fontColor(this.storedSecondaryTextColor)
            .padding({ left: 6, right: 6 })

          if (this.isConfigured) {
            Text(`${this.statusText}\n实例：${this.instanceId}`)
              .width('100%')
              .fontSize(13)
              .lineHeight(19)
              .fontColor(this.storedSecondaryTextColor)
              .padding({ left: 6, right: 6 })
          }

          Button(this.isBusy ? '正在连接…' : (this.isConfigured ? '重新配对' : '连接并配对'))
            .width('100%')
            .height(48)
            .type(ButtonType.Normal)
            .enabled(this.canPair())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedOnPrimaryColor)
            .backgroundColor(this.storedAccentColor)
            .borderRadius(24)
            .stateEffect(true)
            .onClick(() => {
              this.pair();
            })

          if (this.isConfigured) {
            SettingsActionButton({
              title: '断开本机连接',
              emphasis: 'danger',
              isEnabled: !this.isBusy,
              pressedBackgroundColor: this.storedPressedBackgroundColor,
              onAction: () => {
                this.confirmDisconnect();
              }
            })
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private canPair(): boolean {
    return !this.isBusy && this.baseUrl.trim().length > 0 && this.pairingCode.trim().length > 0 &&
      this.deviceName.trim().length > 0;
  }

  private pair(): void {
    if (!this.canPair()) {
      return;
    }
    this.isBusy = true;
    this.statusText = '正在发现服务器并交换设备凭据';
    void this.pairAndPersist().finally((): void => {
      this.isBusy = false;
    });
  }

  private async pairAndPersist(): Promise<void> {
    try {
      const settings = await sharedAiraSyncConfigStore.initialize();
      const result: AiraPersonalServerPairingResult = await AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.pair(
        this.baseUrl,
        this.pairingCode,
        settings.sourceId,
        this.deviceName
      );
      await sharedAiraSyncConfigStore.savePersonalServerConfig(
        result.config.baseUrl,
        result.config.instanceId,
        result.config.protocolVersion,
        result.config.credentialId,
        result.config.deviceToken,
        result.config.deviceName
      );
      if (this.activateExperienceAfterPair) {
        const outcome: SyncExperienceActionOutcome =
          await sharedSyncExperienceCoordinator.completeConfiguredGoal('self_hosted');
        if (outcome.type !== 'completed') {
          throw new Error(outcome.message);
        }
      }
      this.pairingCode = '';
      this.applyConfig(result.config);
      this.statusText = this.activateExperienceAfterPair ? '已连接并开启同步' : '已连接';
      this.refreshSignal.bump();
      showCenteredAlertDialog({
        title: '个人服务器已连接',
        message: this.activateExperienceAfterPair ? '所选内容会通过这台个人服务器保持同步。' : '设备凭据已保存在本机。',
        autoCancel: true,
        secondaryButton: { value: '完成', action: () => { this.navigationCoordinator.back(); } }
      });
    } catch (error) {
      this.statusText = this.stringifyError(error as Error);
      showCenteredAlertDialog({
        title: '连接失败',
        message: this.statusText,
        autoCancel: true,
        secondaryButton: { value: '知道了', action: () => {} }
      });
    }
  }

  private applyConfig(config: AiraPersonalServerConfig): void {
    this.baseUrl = config.baseUrl;
    this.deviceName = config.deviceName.trim().length > 0 ? config.deviceName : 'Aira HarmonyOS';
    this.instanceId = config.instanceId;
    this.isConfigured = config.instanceId.trim().length > 0 && config.deviceToken.trim().length > 0;
    this.statusText = this.isConfigured ? '已连接' : '尚未连接';
  }

  private confirmDisconnect(): void {
    showCenteredAlertDialog({
      title: '断开本机连接？',
      message: '本机将删除个人服务器设备凭据并停止使用该实例同步。本机已有数据不会删除。',
      autoCancel: true,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '断开', action: () => { this.disconnect(); } }
    });
  }

  private disconnect(): void {
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    void sharedAiraSyncConfigStore.clearPersonalServerConfig()
      .then((): void => {
        this.applyConfig(AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.clearConfig());
        this.refreshSignal.bump();
      })
      .catch((error: Error): void => {
        showCenteredAlertDialog({
          title: '未能断开',
          message: this.stringifyError(error),
          autoCancel: true,
          secondaryButton: { value: '知道了', action: () => {} }
        });
      })
      .finally((): void => {
        this.isBusy = false;
      });
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }
}
