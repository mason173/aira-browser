import {
  ExternalNavigationAppOpenPolicy,
  SitePermissionKind,
  SitePermissionRule
} from '../../../common/models/BrowserModels';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  BrowserBoundaryRouteState,
  isPrivateBoundaryRoute
} from '../../../common/utils/RouteParamUtils';
import {
  SettingsNavigationDetailKind
} from '../../../core/settings/SettingsDestinationNavigationOwner';
import {
  SiteCustomizationManagementCoordinator,
  SiteCustomizationPermissionOptionState,
  SiteJavaScriptPolicy
} from '../../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import { WebAppPinnedShortcutCoordinator } from '../../../core/webapps/WebAppPinnedShortcutCoordinator';
import {
  WebAppSettingsSessionAction,
  WebAppSettingsSessionActionResult,
  WebAppSettingsSessionCoordinator,
  WebAppSettingsSessionEntry,
  WebAppSettingsSessionEntryKind,
  WebAppSettingsSessionSnapshot
} from '../../../core/webapps/WebAppSettingsSessionCoordinator';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import { BrowserDesktopSiteMode } from '../../../services/web/BrowserUserAgentService';
import {
  sharedBrowserSitePrivacyRuleRepository,
  sharedBrowserUserAgentSettingsRepository,
  sharedPreferencesRepository,
  sharedSitePolicyService,
  sharedSavedSiteSettingRepository
} from '../../bootstrap/BrowserAppRuntime';
import { sharedWebAppInstallRepository } from '../../../data/webapps/WebAppInstallRepository';
import { WebAppDetailSettingsScreen } from './WebAppDetailSettingsScreen';
import { WebAppSettingsScreen } from './WebAppSettingsScreen';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from './SettingsLayout';
import { SettingsOptionRow } from './SettingsRows';

export type SettingsWebAppsPanelMode = 'compact' | 'twoPane';

@Component
export struct SettingsWebAppsDetailPanel {
  private sessionCoordinator: WebAppSettingsSessionCoordinator = new WebAppSettingsSessionCoordinator(
    sharedWebAppInstallRepository,
    new WebAppPinnedShortcutCoordinator(),
    new SiteCustomizationManagementCoordinator(
      sharedPreferencesRepository,
      sharedBrowserUserAgentSettingsRepository,
      sharedBrowserSitePrivacyRuleRepository,
      sharedSitePolicyService,
      sharedSavedSiteSettingRepository
    ),
    new AppServiceModeGateService(sharedPreferencesRepository)
  );
  private observerKey: string = '';
  @Prop panelMode: SettingsWebAppsPanelMode = 'twoPane';
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('activateEntry') refreshRevision: number = 0;
  @Prop @Watch('activateEntry') detailKind: SettingsNavigationDetailKind = 'web_apps_root';
  @Prop @Watch('activateEntry') shortcutId: string = '';
  @Prop @Watch('activateEntry') host: string = '';
  @Prop @Watch('activateEntry') origin: string = '';
  @Prop @Watch('activateEntry') permissionKind: SitePermissionKind = 'camera';
  @Prop @Watch('activateEntry') dataScope: string = '';
  @Prop @Watch('activateEntry') privacyMode: string = '';
  @Prop @Watch('activateEntry') boundarySource: string = '';
  @Prop pageBackground: ResourceColor = '';
  @Prop surfaceBackground: ResourceColor = '';
  @Prop headerButtonBackground: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  onBack?: () => void;
  onOpenWebAppDetail?: (shortcutId: string) => void;
  onOpenPermission?: (host: string, origin: string, kind: SitePermissionKind) => void;
  onOpenDesktopSite?: (host: string, origin: string) => void;
  onSettingsChanged?: () => void;
  @State private sessionSnapshot: WebAppSettingsSessionSnapshot = this.sessionCoordinator.snapshot();
  @State private sessionReady: boolean = false;

  aboutToAppear(): void {
    this.bindSession();
    this.activateEntry();
  }

  aboutToDisappear(): void {
    this.unbindSession();
  }

  build() {
    Column() {
      if (this.sessionReady) {
        this.buildEntryPage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBackground)
    .clip(true)
  }

  @Builder
  private buildEntryPage() {
    Column() {
      if (this.sessionSnapshot.status === 'error' || this.sessionSnapshot.entryKind === 'invalid') {
        this.buildErrorPanel()
      } else if (this.sessionSnapshot.entryKind === 'web_apps_root') {
        this.buildWebAppsRoot()
      } else if (this.sessionSnapshot.entryKind === 'web_app_detail') {
        this.buildWebAppDetail()
      } else if (this.sessionSnapshot.entryKind === 'site_permission') {
        this.buildPermissionPanel()
      } else if (this.sessionSnapshot.entryKind === 'desktop_site') {
        this.buildDesktopSitePanel()
      } else {
        this.buildErrorPanel()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildWebAppsRoot() {
    WebAppSettingsScreen({
      state: this.sessionSnapshot.listState,
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      presentationMode: this.panelMode === 'compact' ? 'standalone' : 'embedded',
      desktopPresentation: this.desktopPresentation,
      onBack: () => {
        this.onBack?.();
      },
      onOpenItem: (shortcutId: string) => {
        this.onOpenWebAppDetail?.(shortcutId);
      }
    })
  }

  @Builder
  private buildWebAppDetail() {
    WebAppDetailSettingsScreen({
      state: this.sessionSnapshot.detailState,
      siteState: this.sessionSnapshot.siteState,
      siteRenderVersion: this.sessionSnapshot.siteRenderVersion,
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      presentationMode: this.panelMode === 'compact' ? 'standalone' : 'embedded',
      desktopPresentation: this.desktopPresentation,
      onBack: () => {
        this.onBack?.();
      },
      onDefaultFullscreenChange: (enabled: boolean) => {
        this.runEnabledAction('set_default_fullscreen', enabled);
      },
      onTogglePrivateSite: (enabled: boolean) => {
        this.runEnabledAction('set_private_site', enabled);
      },
      onTogglePrivateSitePreserveCookies: (enabled: boolean) => {
        this.runEnabledAction('set_preserve_cookies', enabled);
      },
      onOpenPermission: (kind: string) => {
        const action = new WebAppSettingsSessionAction('open_permission');
        action.permissionKind = kind as SitePermissionKind;
        this.runAction(action);
      },
      onOpenDesktopSite: () => {
        this.runAction(new WebAppSettingsSessionAction('open_desktop_site'));
      },
      onSelectJavaScriptPolicy: (policy: SiteJavaScriptPolicy) => {
        const action = new WebAppSettingsSessionAction('set_javascript');
        action.javaScriptPolicy = policy;
        this.runAction(action);
      },
      onToggleExternalNavigation: (policy: string, followDefault: boolean) => {
        const action = new WebAppSettingsSessionAction('set_external_navigation');
        action.externalNavigationPolicy = policy as ExternalNavigationAppOpenPolicy;
        action.followDefault = followDefault;
        this.runAction(action);
      },
      onResetSite: () => {
        this.confirmResetSite();
      }
    })
  }

  @Builder
  private buildPermissionPanel() {
    Column() {
      if (!this.desktopPresentation) {
        this.buildEmbeddedBackHeader(this.sessionSnapshot.permissionTitle)
      }
      this.buildPermissionContent()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildPermissionContent() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      topPadding: 0,
      bottomPadding: 22
    }) {
      SettingsSection({ title: '站点权限', secondaryTextColor: this.secondaryTextColor }) {
        SettingsGroupCard({
          surfaceColor: this.surfaceBackground,
          desktopPresentation: this.desktopPresentation
        }) {
          ForEach(
            this.sessionSnapshot.permissionGroup.options,
            (option: SiteCustomizationPermissionOptionState, index: number) => {
              SettingsOptionRow({
                title: option.label,
                desktopPresentation: this.desktopPresentation,
                rowPosition: this.resolveRowPosition(index, this.sessionSnapshot.permissionGroup.options.length),
                isSelected: option.value === this.sessionSnapshot.permissionGroup.selectedRule,
                isEnabled: !this.sessionSnapshot.operationBusy,
                primaryTextColor: this.primaryTextColor,
                secondaryTextColor: this.secondaryTextColor,
                pressedBackgroundColor: this.pressedBackground,
                selectedIndicatorColor: this.accentColor,
                radioGroup: `settings-web-app-${this.permissionKind}`,
                radioValue: option.value,
                onAction: (): void => {
                  this.selectPermissionRule(option.value);
                }
              })
              if (index < this.sessionSnapshot.permissionGroup.options.length - 1) {
                SettingsGroupDivider({ dividerColor: this.dividerColor })
              }
            },
            (option: SiteCustomizationPermissionOptionState) => option.value
          )
        }
      }
    }
  }

  @Builder
  private buildDesktopSitePanel() {
    Column() {
      if (!this.desktopPresentation) {
        this.buildEmbeddedBackHeader('网页标识')
      }
      this.buildDesktopSiteContent()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildDesktopSiteContent() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      topPadding: 0,
      bottomPadding: 22
    }) {
      SettingsSection({ title: '当前站点', secondaryTextColor: this.secondaryTextColor }) {
        SettingsGroupCard({
          surfaceColor: this.surfaceBackground,
          desktopPresentation: this.desktopPresentation
        }) {
          this.buildDesktopModeRow('跟随全局', 'default', 'first')
          SettingsGroupDivider({ dividerColor: this.dividerColor })
          this.buildDesktopModeRow('移动版', 'mobile', 'middle')
          SettingsGroupDivider({ dividerColor: this.dividerColor })
          this.buildDesktopModeRow('桌面版', 'desktop', 'last')
        }
      }
    }
  }

  @Builder
  private buildDesktopModeRow(
    title: string,
    mode: BrowserDesktopSiteMode,
    rowPosition: 'single' | 'first' | 'middle' | 'last'
  ) {
    SettingsOptionRow({
      title: title,
      desktopPresentation: this.desktopPresentation,
      rowPosition: rowPosition,
      isSelected: this.sessionSnapshot.desktopSiteMode === mode,
      isEnabled: !this.sessionSnapshot.operationBusy,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      pressedBackgroundColor: this.pressedBackground,
      selectedIndicatorColor: this.accentColor,
      radioGroup: 'settings-web-app-desktop-mode',
      radioValue: mode,
      onAction: (): void => {
        const action = new WebAppSettingsSessionAction('select_desktop_site');
        action.desktopSiteMode = mode;
        this.runAction(action);
      }
    })
  }

  @Builder
  private buildErrorPanel() {
    if (this.panelMode === 'compact') {
      SettingsHdsScaffold({
        title: '网页应用',
        backIconKind: 'back',
        pageBackground: this.pageBackground,
        headerButtonBackground: this.headerButtonBackground,
        primaryTextColor: this.primaryTextColor,
        dividerColor: this.dividerColor,
        showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
        onBack: () => {
          this.onBack?.();
        }
      }) {
        this.buildErrorContent()
      }
    } else if (this.desktopPresentation) {
      this.buildErrorContent()
    } else {
      Column() {
        this.buildEmbeddedBackHeader('网页应用')
        this.buildErrorContent()
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private buildErrorContent() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(30)
        .fontColor([this.secondaryTextColor])
      Text(this.resolveErrorMessage())
        .fontSize(15)
        .fontColor(this.primaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 24, right: 24 })
  }

  @Builder
  private buildEmbeddedBackHeader(title: string) {
    Row({ space: 10 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.secondaryTextColor])
      }
      .width(36)
      .height(36)
      .type(ButtonType.Circle)
      .backgroundColor(this.headerButtonBackground)
      .stateEffect(true)
      .onClick(() => {
        this.onBack?.();
      })

      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  private bindSession(): void {
    if (this.observerKey.length > 0) {
      return;
    }
    this.observerKey = this.sessionCoordinator.observe((snapshot: WebAppSettingsSessionSnapshot): void => {
      this.sessionSnapshot = snapshot;
    });
    this.sessionSnapshot = this.sessionCoordinator.snapshot();
  }

  private unbindSession(): void {
    if (this.observerKey.length <= 0) {
      return;
    }
    this.sessionCoordinator.unobserve(this.observerKey);
    this.observerKey = '';
  }

  private activateEntry(): void {
    this.sessionCoordinator.activate(new WebAppSettingsSessionEntry(
      this.resolveEntryKind(),
      this.shortcutId,
      this.host,
      this.origin,
      this.permissionKind,
      this.buildBoundaryState()
    ));
    this.sessionReady = true;
  }

  private resolveEntryKind(): WebAppSettingsSessionEntryKind {
    if (this.detailKind === 'web_apps_root' || this.detailKind === 'web_app_detail' ||
      this.detailKind === 'site_permission' || this.detailKind === 'desktop_site') {
      return this.detailKind;
    }
    return 'invalid';
  }

  private runEnabledAction(
    kind: 'set_default_fullscreen' |
      'set_private_site' | 'set_preserve_cookies',
    enabled: boolean
  ): void {
    const action = new WebAppSettingsSessionAction(kind);
    action.enabled = enabled;
    this.runAction(action);
  }

  private selectPermissionRule(rule: SitePermissionRule): void {
    const action = new WebAppSettingsSessionAction('select_permission');
    action.permissionRule = rule;
    this.runAction(action);
  }

  private runAction(action: WebAppSettingsSessionAction): void {
    this.sessionCoordinator.action(action)
      .then((result: WebAppSettingsSessionActionResult): void => {
        this.handleActionResult(result);
      })
      .catch((_error: Error): void => {
      });
  }

  private handleActionResult(result: WebAppSettingsSessionActionResult): void {
    if (result.changed) {
      this.onSettingsChanged?.();
    }
    if (result.navigationKind === 'permission') {
      this.onOpenPermission?.(result.host, result.origin, result.permissionKind);
      return;
    }
    if (result.navigationKind === 'desktop_site') {
      this.onOpenDesktopSite?.(result.host, result.origin);
      return;
    }
    if (result.shouldNavigateBack) {
      this.onBack?.();
    }
  }

  private confirmResetSite(): void {
    if (this.sessionSnapshot.operationBusy || !this.sessionSnapshot.detailState.canOpenSiteSettings) {
      return;
    }
    showCenteredAlertDialog({
      title: '重置站点设置',
      message: '将清除这个网页应用对应站点的网页标识、关闭后清除、打开应用和权限自定义规则。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '重置',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.runAction(new WebAppSettingsSessionAction('reset_site'));
        }
      }
    });
  }

  private resolveErrorMessage(): string {
    return this.sessionSnapshot.errorMessage.length > 0
      ? this.sessionSnapshot.errorMessage
      : '这个设置页面暂时无法打开';
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
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
