import {
  WEB_DAV_PROVIDER_ENDPOINT_KEY,
  WEB_DAV_PROVIDER_SELECTION_REVISION_KEY,
  WEB_DAV_PROVIDER_SELECTION_KEY,
  WebdavProviderCatalog,
  WebdavProviderTemplate
} from '../../core/sync/WebdavProviderCatalog';
import { SettingsOptionRow } from '../components/settings/SettingsRows';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody
} from '../components/settings/SettingsLayout';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { sharedPreferencesRepository } from '../bootstrap/BrowserAppRuntime';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';

@Entry
@Component
struct SyncWebdavProviderPage {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F6F8FB';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  private providerCatalog: WebdavProviderCatalog = new WebdavProviderCatalog();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  @State private selectedProviderId: string = 'custom';
  @State private isLeaving: boolean = false;

  aboutToAppear(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.selectedProviderId = AppStorage.get<string>(WEB_DAV_PROVIDER_SELECTION_KEY) ?? 'custom';
    this.isLeaving = false;
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: 'WebDAV 服务商',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        onBack: () => {
          this.handleBack();
        }
      }) {
        SettingsScrollBody({
          topPadding: 8,
          bottomPadding: 28
        }) {
          SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            ForEach(this.providerCatalog.listProviders(), (provider: WebdavProviderTemplate, index: number) => {
              SettingsOptionRow({
                title: provider.name,
                helperText: '',
                leadingIcon: provider.icon,
                leadingImage: provider.logo,
                rowPosition: this.resolveRowPosition(index, this.providerCatalog.listProviders().length),
                isSelected: provider.id === this.selectedProviderId,
                isEnabled: !this.isLeaving,
                onAction: () => {
                  this.selectProvider(provider.id);
                }
              })
              if (index < this.providerCatalog.listProviders().length - 1) {
                SettingsGroupDivider({ dividerColor: this.storedDividerColor })
              }
            }, (provider: WebdavProviderTemplate) => provider.id)
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private selectProvider(providerId: string): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (this.isLeaving) {
      return;
    }
    const provider = this.providerCatalog.resolveProvider(providerId);
    this.selectedProviderId = providerId;
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_SELECTION_KEY, providerId);
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_ENDPOINT_KEY, provider.endpoint);
    const revision = AppStorage.get<number>(WEB_DAV_PROVIDER_SELECTION_REVISION_KEY) ?? 0;
    AppStorage.setOrCreate(WEB_DAV_PROVIDER_SELECTION_REVISION_KEY, revision + 1);
    this.handleBack();
  }

  private handleBack(): void {
    if (this.isLeaving) {
      return;
    }
    this.isLeaving = true;
    this.navigationCoordinator.back();
  }

  private resolveRowPosition(index: number, total: number): 'single' | 'first' | 'middle' | 'last' {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === total - 1) {
      return 'last';
    }
    return 'middle';
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}
