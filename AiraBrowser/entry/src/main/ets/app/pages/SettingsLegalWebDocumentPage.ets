import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import {
  AiraLegalDocumentLink,
  resolveAiraLegalDocumentLink
} from '../../services/legal/AiraLegalDocuments';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { AiraLegalWebDocumentContent } from '../components/legal/AiraLegalWebDocumentContent';

interface SettingsLegalWebDocumentPageParams {
  kind?: string;
}

@Entry
@Component
struct SettingsLegalWebDocumentPage {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @State private documentLink: AiraLegalDocumentLink = resolveAiraLegalDocumentLink('user_service_agreement');

  aboutToAppear(): void {
    this.documentLink = this.resolveRouteDocument();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: this.documentLink.title,
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
          documentUrl: this.documentLink.url,
          styleId: 'aira-settings-legal-style'
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private resolveRouteDocument(): AiraLegalDocumentLink {
    const params = router.getParams() as SettingsLegalWebDocumentPageParams | undefined;
    return resolveAiraLegalDocumentLink(params?.kind ?? 'user_service_agreement');
  }

}
