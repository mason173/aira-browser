import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import {
  SiteCustomizationManagementCoordinator,
  SiteCustomizationUserAgentState
} from '../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import {
  sharedBrowserSitePrivacyRuleRepository,
  sharedBrowserUserAgentSettingsRepository,
  sharedPreferencesRepository,
  sharedSavedSiteSettingRepository
} from '../bootstrap/BrowserAppRuntime';
import { SettingsActionButton, SettingsOptionRow } from '../components/settings/SettingsRows';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../components/settings/SettingsLayout';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../common/models/BrowserModels';
import {
  isPrivateBoundaryRoute,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { SiteCustomizationRefreshSignal } from '../../core/sitecustomization/SiteCustomizationRefreshSignal';
import {
  BrowserUserAgentIdentity,
  FOLLOW_GLOBAL_BROWSER_IDENTITY_ID
} from '../../services/web/BrowserUserAgentService';

interface SiteCustomizationDesktopSitePageParams {
  host?: string;
  origin?: string;
  profileId?: string;
  dataScope?: string;
  privacyMode?: string;
  boundarySource?: string;
}

@Entry
@Component
struct SiteCustomizationDesktopSitePage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private coordinator: SiteCustomizationManagementCoordinator = new SiteCustomizationManagementCoordinator(
    sharedPreferencesRepository,
    sharedBrowserUserAgentSettingsRepository,
    sharedBrowserSitePrivacyRuleRepository,
    undefined,
    sharedSavedSiteSettingRepository
  );
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private refreshSignal: SiteCustomizationRefreshSignal = new SiteCustomizationRefreshSignal();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private host: string = '';
  @State private origin: string = '';
  @State private profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private identities: BrowserUserAgentIdentity[] = [];
  @State private selectedIdentityId: string = FOLLOW_GLOBAL_BROWSER_IDENTITY_ID;
  @State private savedIdentityId: string = FOLLOW_GLOBAL_BROWSER_IDENTITY_ID;
  @State private expectedRevision: number = 0;
  @State private canApply: boolean = false;
  @State private isSaving: boolean = false;
  @State private isLeaving: boolean = false;

  aboutToAppear(): void {
    this.isSaving = false;
    this.isLeaving = false;
    this.refreshState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '网页标识',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
        onBack: () => {
          this.handleBack();
        }
      }) {
        SettingsScrollBody({ topPadding: 16, bottomPadding: 22 }) {
          this.buildIdentitySection()
          SettingsActionButton({
            title: this.isSaving ? '应用中' : '应用并重新加载',
            variant: 'filled',
            isEnabled: this.canApply && !this.isSaving && !this.isLeaving &&
              this.selectedIdentityId !== this.savedIdentityId,
            onAction: (): void => {
              this.applySelection();
            }
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildIdentitySection() {
    SettingsSection({ title: '当前站点' }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(this.identities, (identity: BrowserUserAgentIdentity, index: number) => {
          this.buildIdentityRow(identity, index, this.identities.length)
          if (index < this.identities.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (identity: BrowserUserAgentIdentity) => identity.id)
      }
    }
  }

  @Builder
  private buildIdentityRow(identity: BrowserUserAgentIdentity, index: number, total: number) {
    SettingsOptionRow({
      title: identity.title,
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: this.selectedIdentityId === identity.id,
      isEnabled: !this.isSaving && !this.isLeaving,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      selectedIndicatorColor: this.storedAccentColor,
      radioGroup: 'site-user-agent-identity',
      radioValue: identity.id,
      onAction: (): void => {
        this.selectedIdentityId = identity.id;
      }
    })
  }

  private refreshState(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    const params = router.getParams() as SiteCustomizationDesktopSitePageParams | undefined;
    this.host = params?.host ?? this.host;
    this.origin = params?.origin ?? this.origin;
    this.profileId = (params?.profileId as BrowserProfileId) ?? this.profileId;
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: params?.dataScope ?? this.dataScope,
      privacyMode: params?.privacyMode ?? this.privacyMode,
      boundarySource: params?.boundarySource ?? this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    const state: SiteCustomizationUserAgentState =
      this.coordinator.buildUserAgentState(
        this.host,
        this.origin,
        this.profileId,
        this.dataScope,
        this.privacyMode
      );
    this.selectedIdentityId = state.selectedIdentityId;
    this.savedIdentityId = state.selectedIdentityId;
    this.expectedRevision = state.revision;
    this.canApply = state.canApply;
    this.identities = state.identities;
  }

  private applySelection(): void {
    if (!this.canApply || this.isSaving || this.isLeaving || this.selectedIdentityId === this.savedIdentityId) {
      return;
    }
    this.isSaving = true;
    this.coordinator.commitUserAgentIdentity(
      this.host,
      this.origin,
      this.selectedIdentityId,
      this.expectedRevision,
      this.profileId,
      this.dataScope,
      this.privacyMode
    )
      .then((result) => {
        if (result.status === 'conflict' || result.status === 'invalid') {
          this.isSaving = false;
          this.refreshState();
          return;
        }
        this.refreshSignal.bump('desktop_site', this.origin, this.profileId);
        this.handleBack();
      })
      .catch((_error: Error) => {
        this.isSaving = false;
      });
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

  private handleBack(): boolean {
    if (this.isLeaving) {
      return true;
    }
    this.isLeaving = true;
    this.navigationCoordinator.back();
    return true;
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}
