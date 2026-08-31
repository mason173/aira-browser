import { SyncSettingsProviderCardViewState } from '../../../core/sync/SyncSettingsCenterViewModel';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsSwitchRow } from '../settings/SettingsRows';

@Component
export struct SyncSettingsBackupSourceSection {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string =
    DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop providerCards: SyncSettingsProviderCardViewState[] = [];
  @Prop isBusy: boolean = false;
  @Prop isPrivateSession: boolean = false;
  @Prop renderVersion: number = 0;
  @Prop sectionTitle: string = '额外备份';
  @Prop desktopPresentation: boolean = false;
  onProviderChange?: (card: SyncSettingsProviderCardViewState, enabled: boolean) => void;

  build() {
    if (this.providerCards.length > 0) {
      SettingsSection({ title: this.sectionTitle, secondaryTextColor: this.storedSecondaryTextColor }) {
        SettingsGroupCard({
          surfaceColor: this.storedSurfaceBackgroundColor,
          desktopPresentation: this.desktopPresentation
        }) {
          ForEach(this.providerCards, (card: SyncSettingsProviderCardViewState, index: number) => {
            SettingsSwitchRow({
              title: card.title,
              desktopPresentation: this.desktopPresentation,
              checked: card.role === 'additional_backup',
              icon: card.icon,
              imageIcon: card.imageIcon,
              iconBackgroundColor: card.iconBackgroundColor,
              rowPosition: this.resolveRowPosition(index, this.providerCards.length),
              isEnabled: !this.isPrivateSession && !this.isBusy,
              membershipBadge: card.requiresPro ? 'pro' : 'none',
              primaryTextColor: this.storedPrimaryTextColor,
              secondaryTextColor: this.storedSecondaryTextColor,
              pressedBackgroundColor: this.storedPressedBackgroundColor,
              onChange: (enabled: boolean) => {
                this.onProviderChange?.(card, enabled);
              }
            })
            if (index < this.providerCards.length - 1) {
              SettingsGroupDivider({ dividerColor: this.storedDividerColor })
            }
          }, (card: SyncSettingsProviderCardViewState) => this.buildProviderCardRenderKey(card))
        }
      }
    }
  }

  private buildProviderCardRenderKey(card: SyncSettingsProviderCardViewState): string {
    return `${this.renderVersion}|${card.id}|${card.role}|${card.isConfigured ? 'configured' : 'unconfigured'}`;
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }
}
