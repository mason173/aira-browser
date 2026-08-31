import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { SearchEngineEditorState } from '../../../core/search/SearchEngineManagementViewModel';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import {
  SettingsActionButton,
  SettingsTextField
} from '../settings/SettingsRows';
import {
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';

@Component
export struct SearchEngineEditScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  state: SearchEngineEditorState = {
    title: '添加搜索引擎',
    name: '',
    searchUrlTemplate: '',
    errorMessage: '',
    saveEnabled: false,
    deleteEnabled: false
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop pageBackground: ResourceColor | undefined = undefined;
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop controlBackground: ResourceColor | undefined = undefined;
  @Prop headerButtonBackground: ResourceColor | undefined = undefined;
  @Prop primaryTextColor: ResourceColor = this.storedPrimaryTextColor;
  @Prop secondaryTextColor: ResourceColor = this.storedSecondaryTextColor;
  @Prop useTopSafeInset: boolean = true;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop desktopPresentation: boolean = false;
  onBack?: () => void;
  onNameChange: (value: string) => void = (_value: string) => {};
  onTemplateChange: (value: string) => void = (_value: string) => {};
  onSave: () => void = () => {};
  onDelete: () => void = () => {};

  build() {
    SettingsHdsScaffold({
      title: this.state.title,
      backIconKind: 'back',
      pageBackground: this.resolvePageBackground(),
      headerButtonBackground: this.resolveHeaderButtonBackground(),
      primaryTextColor: this.resolvePrimaryTextColor(),
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      contentKind: 'readable',
      menuActionLabel: '保存',
      menuActionIcon: $r('sys.symbol.checkmark'),
      menuActionEnabled: true,
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
        contentSpace: 18,
        desktopPresentation: this.desktopPresentation,
        topPadding: 16,
        bottomPadding: 32
      }) {
        this.buildFormCard()
        if (this.state.deleteEnabled) {
          this.buildDeleteButton()
        }
      }
    }
  }

  @Builder
  private buildFormCard() {
    SettingsSection({ title: '搜索引擎' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        Column({ space: 16 }) {
          SettingsTextField({
            desktopPresentation: this.desktopPresentation,
            label: '名称（可选）',
            text: this.state.name,
            placeholder: '留空时自动使用搜索站点域名',
            controlBackgroundColor: this.resolveControlBackground(),
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            onChange: (value: string) => {
              this.onNameChange(value);
            }
          })
          SettingsTextField({
            desktopPresentation: this.desktopPresentation,
            label: '搜索 URL',
            text: this.state.searchUrlTemplate,
            placeholder: 'https://example.com/search?q={searchTerms}',
            helperText: this.state.errorMessage.length > 0
              ? ''
              : '使用 {searchTerms} 作为搜索词占位符；导入的 %s 会自动兼容。',
            errorText: this.state.errorMessage,
            controlBackgroundColor: this.resolveControlBackground(),
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            onChange: (value: string) => {
              this.onTemplateChange(value);
            }
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 12 })
      }
    }
  }

  @Builder
  private buildDeleteButton() {
    SettingsSection({ title: '管理' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsActionButton({
          title: '删除搜索引擎',
          emphasis: 'danger',
          pressedBackgroundColor: this.resolveControlBackground(),
          onAction: () => {
            this.onDelete();
          }
        })
      }
    }
  }

  private resolvePageBackground(): ResourceColor {
    return this.pageBackground === undefined ? this.storedPageBackgroundColor : this.pageBackground;
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolveControlBackground(): ResourceColor {
    return this.controlBackground === undefined ? this.storedPressedBackgroundColor : this.controlBackground;
  }

  private resolveHeaderButtonBackground(): ResourceColor {
    return this.headerButtonBackground === undefined ? this.storedPressedBackgroundColor : this.headerButtonBackground;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }
}
