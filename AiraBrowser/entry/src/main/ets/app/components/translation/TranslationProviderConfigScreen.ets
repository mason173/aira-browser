import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  TranslationProviderEditFieldView,
  TranslationProviderEditState
} from '../../../core/translation/TranslationProviderEditViewModel';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import { SettingsTextField } from '../settings/SettingsRows';
import {
  SettingsGroupCard,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';

@Component
export struct TranslationProviderConfigScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: TranslationProviderEditState = {
    title: '配置服务商',
    displayName: '自定义接口',
    endpoint: '',
    apiKey: '',
    appId: '',
    secretKey: '',
    region: '',
    model: '',
    description: '',
    helperText: '',
    errorMessage: '',
    saveEnabled: false,
    fields: []
  };
  securityMessage: string = '';
  isSaving: boolean = false;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  onBack?: () => void;
  onFieldChange: (key: string, value: string) => void = (_key: string, _value: string) => {};
  onSave: () => void = () => {};

  build() {
    SettingsHdsScaffold({
      title: this.state.title,
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      contentKind: 'readable',
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      menuActionLabel: '保存',
      menuActionIcon: $r('sys.symbol.checkmark'),
      menuActionEnabled: this.state.saveEnabled && !this.isSaving,
      onBack: () => {
        if (this.onBack !== undefined) {
          this.onBack();
          return;
        }
        this.navigationCoordinator.back();
      },
      onMenuAction: () => {
        this.onSave();
      }
    }) {
      SettingsPresentationScrollBody({
        contentSpace: 16,
        desktopPresentation: this.desktopPresentation,
        topPadding: 16,
        bottomPadding: 32
      }) {
        this.buildSecurityCard()
        this.buildFormCard()
      }
    }
  }

  @Builder
  private buildFormCard() {
    SettingsSection({ title: '服务参数' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        Column({ space: 16 }) {
          Text(this.state.description)
            .width('100%')
            .fontSize(13)
            .lineHeight(18)
            .fontColor(this.storedSecondaryTextColor)
          if (this.state.fields.length > 0) {
            ForEach(this.state.fields, (field: TranslationProviderEditFieldView) => {
              this.buildInput(field, this.resolveFieldValue(field.key))
            }, (field: TranslationProviderEditFieldView) => field.key)
          }
          Text(this.state.helperText)
            .width('100%')
            .fontSize(13)
            .lineHeight(18)
            .fontColor(this.storedSecondaryTextColor)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      }
    }
  }

  @Builder
  private buildSecurityCard() {
    SettingsSection({ title: '安全' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        Row({ space: 12 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.lock_fill'))
              .fontSize(17)
              .fontColor([this.storedSecondaryTextColor])
          }
          .width(34)
          .height(34)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.storedControlBackgroundColor)
          .borderRadius(17)

          Column({ space: 4 }) {
            Text('安全存储')
              .width('100%')
              .fontSize(15)
              .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
              .fontColor(this.storedPrimaryTextColor)
            Text(this.securityMessage.length > 0
              ? this.securityMessage
              : 'API 密钥将通过系统安全存储加密保存在本机。')
              .width('100%')
              .fontSize(13)
              .lineHeight(18)
              .fontColor(this.storedSecondaryTextColor)
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      }
    }
  }

  @Builder
  private buildInput(
    field: TranslationProviderEditFieldView,
    value: string
  ) {
    SettingsTextField({
      desktopPresentation: this.desktopPresentation,
      label: field.label,
      text: value,
      placeholder: field.placeholder,
      secure: field.secure,
      controlBackgroundColor: this.storedControlBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      onChange: (nextValue: string) => {
        this.onFieldChange(field.key, nextValue);
      }
    })
  }

  private resolveFieldValue(key: string): string {
    if (key === 'displayName') {
      return this.state.displayName;
    }
    if (key === 'endpoint') {
      return this.state.endpoint;
    }
    if (key === 'apiKey') {
      return this.state.apiKey;
    }
    if (key === 'appId') {
      return this.state.appId;
    }
    if (key === 'secretKey') {
      return this.state.secretKey;
    }
    if (key === 'region') {
      return this.state.region;
    }
    if (key === 'model') {
      return this.state.model;
    }
    return '';
  }
}
