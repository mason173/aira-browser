import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { AIRA_PRIVACY_STATEMENT_URL } from '../../services/legal/AiraLegalDocuments';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { AiraLegalWebDocumentContent } from '../components/legal/AiraLegalWebDocumentContent';

@Entry
@Component
struct SettingsPrivacyStatementPage {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '隐私声明',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'readable',
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        AiraLegalWebDocumentContent({
          documentUrl: AIRA_PRIVACY_STATEMENT_URL,
          styleId: 'aira-settings-privacy-style'
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

}
