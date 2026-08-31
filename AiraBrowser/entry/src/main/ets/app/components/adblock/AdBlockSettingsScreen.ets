import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  AdBlockExceptionRowView,
  AdBlockSettingsViewState
} from '../../../core/adblock/AdBlockSettingsViewModel';
import {
  SettingsNavigationRow,
  SettingsActionButton,
  SettingsStaticValueRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  SettingsTargetRevealController,
  SettingsTargetRevealRegion
} from '../settings/SettingsTargetReveal';

@Component
export struct AdBlockSettingsScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsScroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: AdBlockSettingsViewState = {
    enabled: false,
    updateOnForeground: true,
    hasProtectionStats: false,
    customRuleSources: [],
    hasCustomRuleSources: false,
    exceptions: [],
    hasExceptions: false
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop pageBackground: ResourceColor | undefined = undefined;
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop controlBackground: ResourceColor | undefined = undefined;
  @Prop pressedBackground: ResourceColor | undefined = undefined;
  @Prop accentColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = this.storedPrimaryTextColor;
  @Prop secondaryTextColor: ResourceColor = this.storedSecondaryTextColor;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop controlsEnabled: boolean = true;
  @Prop revealTargetId: string = '';
  @Prop revealRevision: number = 0;
  onEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onOpenCustomRules: () => void = () => {};
  onOpenManualElementHideSettings: () => void = () => {};
  onClearStats: () => void = () => {};
  onRemoveException: (host: string) => void = (_host: string) => {};

  build() {
    SettingsHdsScaffold({
      title: '网页内容过滤',
      backIconKind: 'back',
      pageBackground: this.resolvePageBackground(),
      headerButtonBackground: this.resolveControlBackground(),
      primaryTextColor: this.resolvePrimaryTextColor(),
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      scrollers: [this.settingsScroller],
      onBack: () => {
        this.navigationCoordinator.back();
      }
    }) {
      Column() {
        SettingsScrollBody({
          contentSpace: 18,
          topPadding: 16,
          bottomPadding: 32,
          scroller: this.settingsScroller
        }) {
          AdBlockSettingsContent({
            state: this.state,
            surfaceBackground: this.resolveSurfaceBackground(),
            pressedBackground: this.resolvePressedBackground(),
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            accentColor: this.resolveAccentColor(),
            controlsEnabled: this.controlsEnabled,
            revealTargetId: this.revealTargetId,
            revealRevision: this.revealRevision,
            scroller: this.settingsScroller,
            onEnabledChange: (enabled: boolean) => {
              this.onEnabledChange(enabled);
            },
            onOpenCustomRules: () => {
              this.onOpenCustomRules();
            },
            onOpenManualElementHideSettings: () => {
              this.onOpenManualElementHideSettings();
            },
            onClearStats: () => {
              this.onClearStats();
            },
            onRemoveException: (host: string) => {
              this.onRemoveException(host);
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolvePageBackground())
    }
  }

  private resolveAccentColor(): ResourceColor {
    return `${this.accentColor}`.length > 0 ? this.accentColor : this.storedAccentColor;
  }

  private resolvePageBackground(): ResourceColor {
    return this.pageBackground === undefined ? this.storedPageBackgroundColor : this.pageBackground;
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolveControlBackground(): ResourceColor {
    return this.controlBackground === undefined ? this.storedPressedBackgroundColor : this.controlBackground;
  }

  private resolvePressedBackground(): ResourceColor {
    return this.pressedBackground === undefined ? this.storedPressedBackgroundColor : this.pressedBackground;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }
}

@Component
export struct AdBlockSettingsContent {
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: AdBlockSettingsViewState = {
    enabled: false,
    updateOnForeground: true,
    hasProtectionStats: false,
    customRuleSources: [],
    hasCustomRuleSources: false,
    exceptions: [],
    hasExceptions: false
  };
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop pressedBackground: ResourceColor | undefined = undefined;
  @Prop primaryTextColor: ResourceColor = this.storedPrimaryTextColor;
  @Prop secondaryTextColor: ResourceColor = this.storedSecondaryTextColor;
  @Prop accentColor: ResourceColor = '';
  @Prop controlsEnabled: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleRevealRequest') revealTargetId: string = '';
  @Prop @Watch('handleRevealRequest') revealRevision: number = 0;
  scroller?: Scroller;
  @State private highlightedTargetId: string = '';
  private revealController: SettingsTargetRevealController = new SettingsTargetRevealController(
    (targetId: string): void => {
      this.highlightedTargetId = targetId;
    }
  );
  onEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onOpenCustomRules: () => void = () => {};
  onOpenManualElementHideSettings: () => void = () => {};
  onClearStats: () => void = () => {};
  onRemoveException: (host: string) => void = (_host: string) => {};

  aboutToAppear(): void {
    this.revealController.bindScroller(this.scroller);
    this.handleRevealRequest();
  }

  aboutToDisappear(): void {
    this.revealController.dispose();
  }

  build() {
    Column({ space: 18 }) {
      this.buildStatusSection()
      this.buildCustomRuleSection()
      this.buildManualHideSection()
      this.buildClearStatsSection()
      this.buildExceptionsSection()
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.revealController.rememberContentArea(newArea);
    })
  }

  @Builder
  private buildStatusSection() {
    SettingsSection({
      title: '保护',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsSwitchRow({
          title: '网页内容过滤',
          desktopPresentation: this.desktopPresentation,
          description: '按你启用的规则过滤网页内容',
          checked: this.state.enabled,
          isEnabled: this.controlsEnabled,
          primaryTextColor: this.resolvePrimaryTextColor(),
          secondaryTextColor: this.resolveSecondaryTextColor(),
          pressedBackgroundColor: this.resolvePressedBackground(),
          rowPosition: 'single',
          onChange: (enabled: boolean) => {
            this.onEnabledChange(enabled);
          }
        })
      }
    }
  }

  @Builder
  private buildCustomRuleSection() {
    SettingsSection({
      title: '过滤规则',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'adblock_rules',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsNavigationRow({
            title: '过滤规则',
            desktopPresentation: this.desktopPresentation,
            value: `${this.state.customRuleSources.length}`,
            description: '管理第三方和自定义过滤规则',
            isEnabled: this.controlsEnabled && this.state.enabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'single',
            onAction: () => {
              this.onOpenCustomRules();
            }
          })
        }
      }
    }
  }

  @Builder
  private buildManualHideSection() {
    SettingsSection({
      title: '页面元素清理',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'adblock_hidden_elements',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsNavigationRow({
            title: '已清理页面元素',
            desktopPresentation: this.desktopPresentation,
            value: '管理',
            description: '查看和恢复你手动隐藏的网页元素',
            isEnabled: this.controlsEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'single',
            onAction: () => {
              this.onOpenManualElementHideSettings();
            }
          })
        }
      }
    }
  }

  @Builder
  private buildClearStatsSection() {
    SettingsTargetRevealRegion({
      targetId: 'clear_adblock_stats',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsActionButton({
        title: '清空统计',
        emphasis: 'danger',
        isEnabled: this.controlsEnabled && this.state.enabled && this.state.hasProtectionStats,
        pressedBackgroundColor: this.resolvePressedBackground(),
        onAction: () => {
          this.onClearStats();
        }
      })
    }
  }

  @Builder
  private buildExceptionsSection() {
    SettingsSection({
      title: '站点例外',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        if (this.state.hasExceptions) {
          ForEach(this.state.exceptions, (item: AdBlockExceptionRowView, index: number) => {
            this.buildExceptionRow(item)
            if (index < this.state.exceptions.length - 1) {
              SettingsGroupDivider()
            }
          }, (item: AdBlockExceptionRowView) => item.host)
        } else {
          SettingsStaticValueRow({
            title: '暂无站点例外',
            desktopPresentation: this.desktopPresentation,
            value: '',
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            rowPosition: 'single'
          })
        }
      }
    }
  }

  @Builder
  private buildExceptionRow(item: AdBlockExceptionRowView) {
    Row({ space: 12 }) {
      Column() {
        Text(item.host)
          .width('100%')
          .fontSize(this.desktopPresentation ? 15 : 16)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.state.enabled ? this.resolvePrimaryTextColor() : this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('移除')
        .height(34)
        .type(ButtonType.Normal)
        .buttonStyle(ButtonStyleMode.NORMAL)
        .enabled(this.controlsEnabled && this.state.enabled)
        .padding({ left: 12, right: 12 })
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.permission_blocked'))
        .backgroundColor(this.resolvePressedBackground())
        .borderRadius(17)
        .stateEffect(true)
        .onClick(() => {
          this.onRemoveException(item.host);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.controlsEnabled && this.state.enabled ? 1 : 0.48)
  }

  private handleRevealRequest(): void {
    this.revealController.request(this.revealTargetId, this.revealRevision);
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolvePressedBackground(): ResourceColor {
    return this.pressedBackground === undefined ? this.storedPressedBackgroundColor : this.pressedBackground;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }
}
