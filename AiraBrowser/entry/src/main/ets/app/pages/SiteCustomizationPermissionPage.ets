import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import {
  SiteCustomizationDetailViewState,
  SiteCustomizationManagementViewModel
} from '../../core/sitecustomization/SiteCustomizationManagementViewModel';
import {
  SiteCustomizationPermissionGroupState,
  SiteCustomizationPermissionOptionState,
  SiteCustomizationManagementCoordinator
} from '../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import {
  sharedBrowserSitePrivacyRuleRepository,
  sharedBrowserUserAgentSettingsRepository,
  sharedPreferencesRepository,
  sharedSitePolicyService,
  sharedSavedSiteSettingRepository
} from '../bootstrap/BrowserAppRuntime';
import { SettingsOptionRow } from '../components/settings/SettingsRows';
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
  DEFAULT_BROWSER_PROFILE_ID,
  SitePermissionKind,
  SitePermissionRule
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
import { SiteCapabilityCatalogService } from '../../services/web/SiteCapabilityCatalogService';

interface SiteCustomizationPermissionPageParams {
  host?: string;
  origin?: string;
  profileId?: string;
  kind?: string;
  dataScope?: string;
  privacyMode?: string;
  boundarySource?: string;
  subpage?: string;
}

@Entry
@Component
struct SiteCustomizationPermissionPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private viewModel: SiteCustomizationManagementViewModel = new SiteCustomizationManagementViewModel();
  private coordinator: SiteCustomizationManagementCoordinator = new SiteCustomizationManagementCoordinator(
    sharedPreferencesRepository,
    sharedBrowserUserAgentSettingsRepository,
    sharedBrowserSitePrivacyRuleRepository,
    sharedSitePolicyService,
    sharedSavedSiteSettingRepository
  );
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private refreshSignal: SiteCustomizationRefreshSignal = new SiteCustomizationRefreshSignal();
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();
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
  @State private kind: SitePermissionKind = 'camera';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private subpage: string = '';
  @State private state: SiteCustomizationDetailViewState = this.viewModel.buildDetailState(
    this.coordinator.buildDetailState('', '', DEFAULT_BROWSER_PROFILE_ID)
  );
  @State private isSelectingOption: boolean = false;
  @State private isLeaving: boolean = false;

  aboutToAppear(): void {
    this.isSelectingOption = false;
    this.isLeaving = false;
    this.refreshState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: this.resolveTitle(),
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
          this.buildOptionSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildOptionSection() {
    SettingsSection({
      title: '站点权限',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(this.resolveSelectedGroup().options, (option: SiteCustomizationPermissionOptionState, index: number) => {
          this.buildOptionRow(option, index, this.resolveSelectedGroup().options.length)
          if (index < this.resolveSelectedGroup().options.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: SiteCustomizationPermissionOptionState) => option.value)
      }
    }
  }

  @Builder
  private buildOptionRow(option: SiteCustomizationPermissionOptionState, index: number, total: number) {
    SettingsOptionRow({
      title: option.label,
      helperText: option.helperText,
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: option.value === this.resolveSelectedGroup().selectedRule,
      isEnabled: !this.isSelectingOption && !this.isLeaving,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      selectedIndicatorColor: this.storedAccentColor,
      radioGroup: `site-customization-${this.kind}`,
      radioValue: option.value,
      onAction: (): void => {
        this.requestSelectRule(option.value);
      }
    })
  }

  private refreshState(): void {
    const params = router.getParams() as SiteCustomizationPermissionPageParams | undefined;
    this.subpage = params?.subpage ?? this.subpage;
    if (!this.isSiteControlsMode() && !this.ensureOptionalServiceRoute()) {
      return;
    }
    this.host = params?.host ?? this.host;
    this.origin = params?.origin ?? this.origin;
    this.profileId = (params?.profileId as BrowserProfileId) ?? this.profileId;
    this.kind = this.resolveKind(params?.kind ?? this.kind);
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.state = this.viewModel.buildDetailState(
      this.coordinator.buildDetailState(this.host, this.origin, this.profileId, this.dataScope, this.privacyMode)
    );
  }

  private requestSelectRule(rule: SitePermissionRule): void {
    if (this.isSelectingOption || this.isLeaving) {
      return;
    }
    if (rule === this.resolveSelectedGroup().selectedRule) {
      this.handleBack();
      return;
    }
    this.isSelectingOption = true;
    this.coordinator.updatePermissionRule(
      this.host,
      this.origin,
      this.kind,
      rule,
      this.profileId,
      this.dataScope,
      this.privacyMode
    )
      .then(() => {
        this.refreshState();
        this.refreshSignal.bump('permission', this.origin, this.profileId);
        this.handleBack();
      })
      .catch((_error: Error) => {
        this.isSelectingOption = false;
      });
  }

  private resolveSelectedGroup(): SiteCustomizationPermissionGroupState {
    const matchedGroup = this.state.permissionGroups.find((group: SiteCustomizationPermissionGroupState) => {
      return group.kind === this.kind;
    });
    if (matchedGroup !== undefined) {
      return matchedGroup;
    }
    return {
      kind: this.kind,
      title: this.resolveKindTitle(this.kind),
      selectedRule: 'ask',
      options: this.capabilityCatalog.buildDefaultPermissionOptions()
    };
  }

  private resolveTitle(): string {
    return `${this.resolveSelectedGroup().title}权限`;
  }

  private resolveKind(value: string): SitePermissionKind {
    return this.capabilityCatalog.resolvePermissionKind(value);
  }

  private resolveKindTitle(kind: SitePermissionKind): string {
    return this.capabilityCatalog.getPermissionTitle(kind);
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

  private isSiteControlsMode(): boolean {
    return this.subpage === 'site_controls';
  }
}
