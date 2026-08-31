import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { TranslationProviderTemplateId } from '../../../common/models/BrowserModels';
import { TranslationProviderLogoViewModel } from '../../../core/translation/TranslationProviderLogoViewModel';
import { TranslationProviderRowView } from '../../../core/translation/WebpageTranslationSettingsViewModel';
import {
  SettingsOptionRow,
  SettingsRowPosition
} from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';

@Component
export struct TranslationProviderEditScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop providers: TranslationProviderRowView[] = [];
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  private logoViewModel: TranslationProviderLogoViewModel = new TranslationProviderLogoViewModel();
  onBack?: () => void;
  onSelectProvider: (providerId: string) => void = (_providerId: string) => {};
  onConfigureTemplate: (templateId: TranslationProviderTemplateId) => void = (_templateId: TranslationProviderTemplateId) => {};

  build() {
    SettingsHdsScaffold({
      title: '选择翻译服务',
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      onBack: () => {
        if (this.onBack !== undefined) {
          this.onBack();
          return;
        }
        this.navigationCoordinator.back();
      }
    }) {
      SettingsPresentationScrollBody({
        contentSpace: 16,
        desktopPresentation: this.desktopPresentation,
        topPadding: 16,
        bottomPadding: 32
      }) {
        SettingsSection({
          title: '选择翻译服务',
          secondaryTextColor: this.storedSecondaryTextColor
        }) {
          this.buildTemplateCard()
        }
      }
    }
  }

  @Builder
  private buildTemplateCard() {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      desktopPresentation: this.desktopPresentation
    }) {
      ForEach(this.providers, (provider: TranslationProviderRowView, index: number) => {
        SettingsOptionRow({
          title: provider.title,
          desktopPresentation: this.desktopPresentation,
          helperText: provider.subtitle,
          leadingImage: this.logoViewModel.resolveLogo(provider.templateId),
          rowPosition: this.resolveRowPosition(index),
          isSelected: provider.isActive,
          membershipBadge: 'none',
          onAction: () => {
            if (provider.isConfigured) {
              this.onSelectProvider(provider.id);
            } else {
              this.onConfigureTemplate(provider.templateId);
            }
          }
        })
        if (index < this.providers.length - 1) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
      }, (provider: TranslationProviderRowView) => provider.id)
    }
  }

  private resolveRowPosition(index: number): SettingsRowPosition {
    if (this.providers.length <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === this.providers.length - 1) {
      return 'last';
    }
    return 'middle';
  }
}
