import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  SiteCustomizationDetailViewState
} from '../../../core/sitecustomization/SiteCustomizationManagementViewModel';
import {
  SiteCustomizationPermissionGroupState,
  SiteJavaScriptPolicy
} from '../../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import {
  SettingsActionButton,
  SettingsStaticValueRow,
  SettingsOptionRow,
  SettingsNavigationRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsFooterText,
  SettingsScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  ExternalNavigationPolicyOption,
  SiteCapabilityCatalogService
} from '../../../services/web/SiteCapabilityCatalogService';
import { SiteCustomizationFocusCapability } from '../../../core/sitecontrols/SiteControlsNavigationDecision';

const SITE_JAVASCRIPT_RADIO_GROUP: string = 'site-javascript-policy';

interface SiteJavaScriptPolicyOption {
  value: SiteJavaScriptPolicy;
  title: string;
}

@Component
export struct SiteCustomizationDetailScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: SiteCustomizationDetailViewState = {
    host: '',
    origin: '',
    title: '',
    summary: '',
    externalNavigationPolicy: 'ask',
    hasExternalNavigationRule: false,
    desktopSiteSummary: '跟随全局',
    hasDesktopSiteRule: false,
    javaScriptPolicy: 'default',
    hasJavaScriptRule: false,
    javaScriptCanApply: true,
    privateSiteEnabled: false,
    preserveCookiesOnClose: false,
    hasPrivateSiteRule: false,
    permissionGroups: [],
    hasAnyRules: false,
    resetEnabled: false,
    hasUnreadableEntry: false
  };
  onTogglePrivateSite?: (enabled: boolean) => void;
  onTogglePrivateSitePreserveCookies?: (enabled: boolean) => void;
  onOpenPermission?: (kind: string) => void;
  onOpenDesktopSite?: () => void;
  onSelectJavaScriptPolicy?: (policy: SiteJavaScriptPolicy) => void;
  onToggleExternalNavigation?: (policy: string, followDefault: boolean) => void;
  onReset?: () => void;
  @Prop renderVersion: number = 0;
  @Prop focusCapability: SiteCustomizationFocusCapability | '' = '';

  build() {
    SettingsHdsScaffold({
      title: this.state.title.length > 0 ? this.state.title : '当前站点设置',
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      onBack: () => {
        this.navigationCoordinator.back();
      }
    }) {
      Column() {
        SettingsScrollBody({
          contentSpace: 18,
          topPadding: 16,
          bottomPadding: 28
        }) {
          SiteCustomizationDetailSections({
            state: this.state,
            renderVersion: this.renderVersion,
            focusCapability: this.focusCapability,
            onTogglePrivateSite: (enabled: boolean) => {
              this.onTogglePrivateSite?.(enabled);
            },
            onTogglePrivateSitePreserveCookies: (enabled: boolean) => {
              this.onTogglePrivateSitePreserveCookies?.(enabled);
            },
            onOpenPermission: (kind: string) => {
              this.onOpenPermission?.(kind);
            },
            onOpenDesktopSite: () => {
              this.onOpenDesktopSite?.();
            },
            onSelectJavaScriptPolicy: (policy: SiteJavaScriptPolicy) => {
              this.onSelectJavaScriptPolicy?.(policy);
            },
            onToggleExternalNavigation: (policy: string, followDefault: boolean) => {
              this.onToggleExternalNavigation?.(policy, followDefault);
            },
            onReset: () => {
              this.onReset?.();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.storedPageBackgroundColor)
    }
  }
}

@Component
export struct SiteCustomizationDetailSections {
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @Prop state: SiteCustomizationDetailViewState = {
    host: '',
    origin: '',
    title: '',
    summary: '',
    externalNavigationPolicy: 'ask',
    hasExternalNavigationRule: false,
    desktopSiteSummary: '跟随全局',
    hasDesktopSiteRule: false,
    javaScriptPolicy: 'default',
    hasJavaScriptRule: false,
    javaScriptCanApply: true,
    privateSiteEnabled: false,
    preserveCookiesOnClose: false,
    hasPrivateSiteRule: false,
    permissionGroups: [],
    hasAnyRules: false,
    resetEnabled: false,
    hasUnreadableEntry: false
  };
  onTogglePrivateSite?: (enabled: boolean) => void;
  onTogglePrivateSitePreserveCookies?: (enabled: boolean) => void;
  onOpenPermission?: (kind: string) => void;
  onOpenDesktopSite?: () => void;
  onSelectJavaScriptPolicy?: (policy: SiteJavaScriptPolicy) => void;
  onToggleExternalNavigation?: (policy: string, followDefault: boolean) => void;
  onReset?: () => void;
  @Prop renderVersion: number = 0;
  @Prop focusCapability: SiteCustomizationFocusCapability | '' = '';
  @Prop desktopPresentation: boolean = false;

  build() {
    Column({ space: 18 }) {
      if (this.state.hasUnreadableEntry) {
        this.buildUnreadableSection()
        this.buildResetSection()
      } else if (this.focusCapability.length > 0) {
        this.buildFocusedCapabilitySection()
      } else {
        this.buildDisplaySection()
        this.buildJavaScriptSection()
        this.buildPrivacySection()
        this.buildPermissionSection()
        this.buildExternalActionSection()
        this.buildResetSection()
      }
    }
    .width('100%')
  }

  @Builder
  private buildUnreadableSection() {
    SettingsSection({ title: '站点设置' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsStaticValueRow({
          title: '数据状态',
          desktopPresentation: this.desktopPresentation,
          value: '无法读取',
          rowPosition: 'single'
        })
      }
      SettingsFooterText({
        text: '此记录已损坏或来自不支持的版本。重置后可重新设置当前站点。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildPrivacySection() {
    SettingsSection({ title: '隐私' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsSwitchRow({
          title: '关闭后清除',
          desktopPresentation: this.desktopPresentation,
          checked: this.state.privateSiteEnabled,
          rowPosition: this.state.privateSiteEnabled ? 'first' : 'single',
          onChange: (enabled: boolean) => {
            this.onTogglePrivateSite?.(enabled);
          }
        })
        if (this.state.privateSiteEnabled) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          SettingsSwitchRow({
            title: '保留 Cookie',
            desktopPresentation: this.desktopPresentation,
            checked: this.state.preserveCookiesOnClose,
            rowPosition: 'last',
            onChange: (enabled: boolean) => {
              this.onTogglePrivateSitePreserveCookies?.(enabled);
            }
          })
        }
      }
      SettingsFooterText({
        text: this.state.preserveCookiesOnClose
          ? '关闭此站点后仍会清除站点存储、缓存、历史和最近关闭记录，但保留 Cookie 登录状态。'
          : '关闭此站点后会清除站点存储、Cookie、缓存、历史和最近关闭记录。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildDisplaySection() {
    SettingsSection({ title: '显示与兼容' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        if (this.focusCapability !== 'desktop_site') {
          SettingsStaticValueRow({
            title: '字体大小',
            desktopPresentation: this.desktopPresentation,
            value: '跟随默认',
            rowPosition: 'first'
          })
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
        SettingsNavigationRow({
          title: '网页标识',
          desktopPresentation: this.desktopPresentation,
          value: this.state.desktopSiteSummary,
          rowPosition: this.focusCapability === 'desktop_site' ? 'single' : 'last',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onOpenDesktopSite?.();
          }
        })
      }
    }
  }

  @Builder
  private buildFocusedCapabilitySection() {
    if (this.focusCapability === 'external_actions') {
      this.buildExternalActionSection()
    } else if (this.focusCapability === 'desktop_site') {
      this.buildDisplaySection()
    } else if (this.focusCapability === 'private_site') {
      this.buildPrivacySection()
    } else if (this.focusCapability === 'javascript') {
      this.buildJavaScriptSection()
    } else {
      Blank().height(0)
    }
  }

  @Builder
  private buildJavaScriptSection() {
    SettingsSection({ title: 'JavaScript' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.buildJavaScriptPolicyOptions(), (option: SiteJavaScriptPolicyOption, index: number) => {
          SettingsOptionRow({
            title: option.title,
            desktopPresentation: this.desktopPresentation,
            rowPosition: this.resolveRowPosition(index, 3),
            isSelected: option.value === this.state.javaScriptPolicy,
            isEnabled: this.state.javaScriptCanApply,
            radioGroup: SITE_JAVASCRIPT_RADIO_GROUP,
            radioValue: option.value,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onAction: (): void => {
              this.onSelectJavaScriptPolicy?.(option.value);
            }
          })
          if (index < 2) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: SiteJavaScriptPolicyOption): string => option.value)
      }
      SettingsFooterText({
        text: '更改后重新加载此网站生效。阻止 JavaScript 可能导致网页无法正常使用。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildPermissionSection() {
    SettingsSection({ title: '站点权限' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.state.permissionGroups, (group: SiteCustomizationPermissionGroupState, index: number) => {
          this.buildPermissionRow(group, this.resolveRowPosition(index, this.state.permissionGroups.length))
          if (index < this.state.permissionGroups.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (group: SiteCustomizationPermissionGroupState) => this.resolvePermissionRowKey(group))
      }
    }
  }

  @Builder
  private buildPermissionRow(group: SiteCustomizationPermissionGroupState, rowPosition: 'single' | 'first' | 'middle' | 'last') {
    Column() {
      SettingsNavigationRow({
        title: group.title,
        desktopPresentation: this.desktopPresentation,
        value: this.resolveRuleLabel(group.selectedRule),
        rowPosition: rowPosition,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          this.onOpenPermission?.(group.kind);
        }
      })
    }
  }

  @Builder
  private buildExternalActionSection() {
    SettingsSection({ title: '外部动作' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.buildExternalNavigationOptions(), (option: ExternalNavigationPolicyOption, index: number) => {
          SettingsOptionRow({
            title: option.label,
            desktopPresentation: this.desktopPresentation,
            helperText: option.helperText,
            rowPosition: this.resolveRowPosition(index, 3),
            isSelected: this.isExternalNavigationOptionSelected(option.value),
            onAction: () => {
              this.onToggleExternalNavigation?.(option.value, option.value === 'ask' && !this.state.hasExternalNavigationRule);
            }
          })
          if (index < 2) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: ExternalNavigationPolicyOption) => option.value)
      }
    }
  }

  @Builder
  private buildResetSection() {
    SettingsSection({ title: '管理' }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsActionButton({
          title: '重置当前站点',
          isEnabled: this.state.resetEnabled,
          emphasis: 'danger',
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onReset?.();
          }
        })
      }
    }
  }

  private buildExternalNavigationOptions(): ExternalNavigationPolicyOption[] {
    return this.capabilityCatalog.buildExternalNavigationOptions();
  }

  private buildJavaScriptPolicyOptions(): SiteJavaScriptPolicyOption[] {
    return [
      { value: 'default', title: '跟随默认设置' },
      { value: 'allow', title: '允许' },
      { value: 'block', title: '阻止' }
    ];
  }

  private isExternalNavigationOptionSelected(value: string): boolean {
    if (!this.state.hasExternalNavigationRule) {
      return value === 'ask';
    }
    return value === this.state.externalNavigationPolicy;
  }

  private resolvePermissionRowKey(group: SiteCustomizationPermissionGroupState): string {
    return `${this.renderVersion}_${group.kind}_${group.selectedRule}`;
  }

  private resolveRuleLabel(rule: string): string {
    if (rule === 'allow') {
      return '允许';
    }
    if (rule === 'block') {
      return '阻止';
    }
    return '询问';
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
}
