import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { SitePermissionKind, SitePermissionRule } from '../../common/models/BrowserModels';
import {
  SettingsSitePermissionDefaultOption,
  SettingsSitePermissionDefaultPageState,
  SettingsSitePermissionsCoordinator
} from '../../core/settings/SettingsSitePermissionsCoordinator';
import { sharedPreferencesRepository, sharedSitePolicyService } from '../bootstrap/BrowserAppRuntime';
import { SettingsOptionRow } from '../components/settings/SettingsRows';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsFooterText
} from '../components/settings/SettingsLayout';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  isPrivateBoundaryRoute,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SiteCapabilityCatalogService } from '../../services/web/SiteCapabilityCatalogService';

interface SettingsSitePermissionDefaultPageParams {
  kind?: string;
}

@Entry
@Component
struct SettingsSitePermissionDefaultPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private coordinator: SettingsSitePermissionsCoordinator =
    new SettingsSitePermissionsCoordinator(sharedPreferencesRepository, sharedSitePolicyService);
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();
  @State private kind: SitePermissionKind = 'camera';
  @State private state: SettingsSitePermissionDefaultPageState = this.coordinator.buildDefaultPageState('camera');
  @State private isSelectingOption: boolean = false;
  @State private isLeaving: boolean = false;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.isSelectingOption = false;
    this.isLeaving = false;
    this.syncBoundaryRouteState();
    const params = router.getParams() as SettingsSitePermissionDefaultPageParams | undefined;
    this.kind = this.resolveKind(params?.kind ?? '');
    this.refreshState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: this.state.title,
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
        this.buildOptionSubpage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private syncBoundaryRouteState(): void {
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
  }

  @Builder
  private buildOptionSubpage() {
    SettingsScrollBody({ bottomPadding: 22 }) {
      this.buildOptionContent()
    }
  }

  @Builder
  private buildOptionContent() {
    Column({ space: 8 }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(this.state.options, (option: SettingsSitePermissionDefaultOption, index: number) => {
          this.buildOptionRow(option, index, this.state.options.length)
          if (index < this.state.options.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: SettingsSitePermissionDefaultOption) => this.resolveOptionRenderKey(option))
      }

      SettingsFooterText({
        text: this.buildFooterText(),
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
    .width('100%')
  }

  @Builder
  private buildOptionRow(option: SettingsSitePermissionDefaultOption, index: number, total: number) {
    SettingsOptionRow({
      title: option.label,
      helperText: '',
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: option.value === this.state.selectedRule,
      isEnabled: !this.isSelectingOption && !this.isLeaving,
      onAction: (): void => {
        this.requestSelectRule(option.value);
      }
    })
  }

  private refreshState(): void {
    this.state = this.coordinator.buildDefaultPageState(this.kind);
  }

  private buildFooterText(): string {
    return `${this.capabilityCatalog.getPermissionObjectLabel(this.kind)}默认设置会在站点没有单独规则时使用。`;
  }

  private resolveOptionRenderKey(option: SettingsSitePermissionDefaultOption): string {
    return `${this.resolveThemeRenderKey()}:${option.value}:${option.value === this.state.selectedRule ? '1' : '0'}`;
  }

  private resolveThemeRenderKey(): string {
    return `${this.storedResolvedThemeMode}:${this.storedPageBackgroundColor}:${this.storedSurfaceBackgroundColor}:` +
      `${this.storedPressedBackgroundColor}:${this.storedPrimaryTextColor}:${this.storedSecondaryTextColor}:` +
      `${this.storedDividerColor}`;
  }

  private requestSelectRule(rule: SitePermissionRule): void {
    if (this.isSelectingOption || this.isLeaving) {
      return;
    }
    if (rule === this.state.selectedRule) {
      this.handleBack();
      return;
    }
    this.isSelectingOption = true;
    this.coordinator.updateDefaultRule(this.kind, rule, {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    })
      .then(() => {
        this.refreshState();
        this.handleBack();
      })
      .catch((_error: Error) => {
        this.isSelectingOption = false;
      });
  }

  private resolveKind(value: string): SitePermissionKind {
    return this.capabilityCatalog.resolvePermissionKind(value);
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
}
