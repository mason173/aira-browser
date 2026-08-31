import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  SitePermissionKind,
  SitePermissionRule
} from '../../../common/models/BrowserModels';
import { curves } from '@kit.ArkUI';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton
} from './BrowserModalBottomSheet';
import {
  SettingsNavigationRow,
  SettingsOptionRow,
  SettingsRowPosition,
  SettingsStaticValueRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';
import {
  SiteCapabilityCatalogService,
  SitePermissionRuleOption
} from '../../../services/web/SiteCapabilityCatalogService';
import {
  BrowserSiteControlsApplicationSnapshot,
  BrowserSiteControlsUserAction,
  DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT
} from '../../../core/browser/BrowserSiteControlsRuntimeCoordinator';
const SITE_INFO_SHEET_MAX_WIDTH: number = 560;
const SITE_SECURITY_METRIC_VALUE_FONT_SIZE: number = 34;
const SITE_SECURITY_METRIC_UNIT_FONT_SIZE: number = 12;
const SITE_INFO_PAGE_TRANSITION_RESPONSE: number = 0.34;
const SITE_INFO_PAGE_TRANSITION_DAMPING: number = 0.84;
const SITE_INFO_PERMISSION_RADIO_GROUP: string = 'site-info-permission-rule';
const SITE_INFO_CONTENT_TOP_PADDING: number = BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET;
const SITE_INFO_CONTENT_BOTTOM_PADDING: number = 84;

@Component
export struct BrowserSiteInfoSheet {
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop snapshot: BrowserSiteControlsApplicationSnapshot = DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT;
  onAction: (
    action: BrowserSiteControlsUserAction,
    permissionKind?: SitePermissionKind,
    permissionRule?: SitePermissionRule
  ) => void = (_action: BrowserSiteControlsUserAction) => {};

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      maxWidth: SITE_INFO_SHEET_MAX_WIDTH,
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      Column() {
        this.buildPageHost()
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private buildPageHost() {
    Stack({ alignContent: Alignment.Top }) {
      ForEach([this.resolvePageKey()], (pageKey: string) => {
        this.buildPage(this.resolvePageTransition())
      }, (pageKey: string) => pageKey)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  private buildPage(pageTransition: TransitionEffect) {
    Stack() {
      BrowserImmersiveSheetLayout({
        footerVisible: this.shouldShowPageFooter(),
        scrollContent: () => {
          this.buildActivePageContent()
        },
        header: () => {
          this.buildFeatureHeader(this.resolveFeatureHeaderTitle(), this.isFeaturePageNested())
        },
        footer: () => {
          this.buildActivePageFooter()
        }
      })
    }
    .width('100%')
    .height('100%')
    .transition(pageTransition)
  }

  @Builder
  private buildActivePageContent() {
    if (this.snapshot.session.mode === 'security') {
      this.buildSecurityReportContent()
    } else if (this.snapshot.session.mode === 'certificate') {
      this.buildCertificateDetailList()
    } else if (this.snapshot.session.mode === 'adblock_log') {
      this.buildAdBlockLogContent()
    } else if (this.isPermissionPageMode(this.snapshot.session.mode)) {
      this.buildPermissionOptionList(this.resolvePermissionKindFromMode(this.snapshot.session.mode))
    } else {
      this.buildOverviewList()
    }
  }

  @Builder
  private buildActivePageFooter() {
    if (this.snapshot.session.mode === 'security') {
      this.buildSecurityReportActions()
    } else if (this.snapshot.session.mode === 'certificate') {
      this.buildSinglePrimaryAction('完成')
    }
  }

  private resolvePageKey(): string {
    return this.snapshot.session.mode.length > 0 ? this.snapshot.session.mode : 'overview';
  }

  private resolvePageTransition(): TransitionEffect {
    if (this.snapshot.session.navigationDirection === 'backward') {
      return TransitionEffect.move(TransitionEdge.START)
        .animation({ curve: curves.springMotion(SITE_INFO_PAGE_TRANSITION_RESPONSE, SITE_INFO_PAGE_TRANSITION_DAMPING) });
    }
    if (this.snapshot.session.navigationDirection === 'forward') {
      return TransitionEffect.move(TransitionEdge.END)
        .animation({ curve: curves.springMotion(SITE_INFO_PAGE_TRANSITION_RESPONSE, SITE_INFO_PAGE_TRANSITION_DAMPING) });
    }
    return TransitionEffect.OPACITY.animation({ duration: 1 });
  }

  @Builder
  private buildFeatureHeader(title: string, nested: boolean) {
    BrowserFeatureSheetHeader({
      title: title,
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: nested ? '返回站点信息' : '关闭站点信息',
      onLeadingAction: () => {
        this.onAction(nested ? 'navigate_back' : 'close');
      }
    })
  }

  @Builder
  private buildSecurityReportContent() {
    List({ space: 12 }) {
      ListItem() {
        this.buildSecurityMetricRow()
      }

      ListItem() {
        Text('这里只统计 Aira 实际执行的网页保护动作，不包含 Cookie 或指纹策略的推测次数。')
          .width('100%')
          .padding({ left: 4, right: 4 })
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.storedSecondaryTextColor)
      }

      ListItem() {
        this.buildSecurityNavigationGroup()
      }

      ListItem() {
        this.buildSecurityProtectionSwitchGroup()
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 16,
      right: 16
    })
    .contentStartOffset(SITE_INFO_CONTENT_TOP_PADDING)
    .contentEndOffset(this.resolveContentBottomOffset())
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildSecurityNavigationGroup() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      SettingsNavigationRow({
        title: '连接',
        value: this.snapshot.connectionTitle.length > 0 ? this.snapshot.connectionTitle : '站点信息',
        icon: this.snapshot.isSecureSite ? $r('sys.symbol.lock_fill') : $r('sys.symbol.exclamationmark_triangle_fill'),
        iconBackgroundColor: this.storedControlBackgroundColor,
        iconColor: this.snapshot.isSecureSite ? this.storedAccentColor : this.storedSecondaryTextColor,
        rowPosition: 'first',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          this.onAction('open_certificate');
        }
      })
      SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      SettingsNavigationRow({
        title: '网页内容过滤',
        value: this.getProtectionSummaryText(),
        icon: $r('sys.symbol.shield_checkered'),
        iconBackgroundColor: this.storedControlBackgroundColor,
        iconColor: this.storedAccentColor,
        rowPosition: 'middle',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          this.onAction('open_protection_log');
        }
      })
      SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      SettingsNavigationRow({
        title: '防跟踪防护',
        value: this.snapshot.trackingProtectionSummary,
        airaIconId: 'settings.privacySecurity',
        iconBackgroundColor: this.storedControlBackgroundColor,
        iconColor: this.snapshot.trackingProtectionEnhanced ? this.storedAccentColor : this.storedSecondaryTextColor,
        rowPosition: 'middle',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          this.onAction('open_tracking_protection_settings');
        }
      })
      SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      SettingsNavigationRow({
        title: '站点设置',
        value: '',
        icon: $r('sys.symbol.person_shield_fill'),
        iconBackgroundColor: this.storedControlBackgroundColor,
        iconColor: this.storedAccentColor,
        rowPosition: 'last',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          this.onAction('open_site_customization');
        }
      })
    }
  }

  @Builder
  private buildSecurityProtectionSwitchGroup() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      SettingsSwitchRow({
        title: '本站网页内容过滤',
        checked: this.snapshot.session.protection.siteEnabled,
        isEnabled: this.snapshot.session.protection.siteToggleEnabled,
        rowPosition: 'single',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onChange: (_checked: boolean) => {
          this.onAction('toggle_protection');
        }
      })
    }
  }

  @Builder
  private buildSecurityMetricRow() {
    Row({ space: 8 }) {
      this.buildSecurityMetricCard(this.formatMetricCount(this.resolveSecurityBlockedCount()), '', '本页保护')
      this.buildSecurityMetricCard(this.formatMetricCount(this.snapshot.todayProtectionActionCount), '', '今日保护')
      this.buildSecurityMetricCard(this.formatMetricCount(this.snapshot.sevenDayProtectionActionCount), '', '近 7 天')
    }
    .width('100%')
  }

  @Builder
  private buildSecurityMetricCard(value: string, unit: string, label: string) {
    Column({ space: 4 }) {
      Row({ space: 2 }) {
        Text(value)
          .fontSize(SITE_SECURITY_METRIC_VALUE_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)

        if (unit.length > 0) {
          Text(unit)
            .fontSize(SITE_SECURITY_METRIC_UNIT_FONT_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Bottom)

      Text(label)
        .width('100%')
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .height(82)
    .padding({ top: 12, bottom: 10, left: 4, right: 4 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(16)
  }

  @Builder
  private buildSecurityReportActions() {
    Row({ space: 12 }) {
      BrowserSheetActionButton({
        label: '拦截日志',
        onAction: () => {
          this.onAction('open_protection_log');
        }
      })

      BrowserSheetActionButton({
        label: '站点信息',
        emphasis: 'primary',
        accentColor: this.storedAccentColor,
        onAction: () => {
          this.onAction('open_overview');
        }
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildOverviewList() {
    List({ space: 14 }) {
      if (this.snapshot.isPrivateMode) {
        ListItem() {
          this.buildPrivateSessionGroup()
        }
      }

      ListItem() {
        this.buildProtectionActionMetric()
      }

      ListItem() {
        this.buildProtectionCategoryGroup()
      }

      ListItem() {
        this.buildOverviewNavigationGroup()
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 16,
      right: 16
    })
    .contentStartOffset(SITE_INFO_CONTENT_TOP_PADDING)
    .contentEndOffset(this.resolveContentBottomOffset())
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildPrivateSessionGroup() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      SettingsStaticValueRow({
        title: '仅本次私密会话',
        value: '',
        rowPosition: 'single',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildProtectionActionMetric() {
    Column({ space: 5 }) {
      Text(`${this.snapshot.session.protection.blockedCount}`)
        .width('100%')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Text(this.getProtectionActionMetricLabel())
        .width('100%')
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(18)
  }

  @Builder
  private buildProtectionCategoryGroup() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      SettingsStaticValueRow({
        title: '请求拦截',
        value: `${this.snapshot.session.protection.requestBlockingCount}`,
        rowPosition: 'first',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor
      })
      SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      SettingsStaticValueRow({
        title: '链接清理',
        value: `${this.snapshot.session.protection.linkCleaningCount}`,
        rowPosition: 'middle',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor
      })
      SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      SettingsStaticValueRow({
        title: '元素隐藏',
        value: `${this.snapshot.session.protection.elementHidingCount}`,
        rowPosition: 'last',
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildPermissionGroup() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      ForEach(this.listPermissionKinds(), (kind: SitePermissionKind, index: number) => {
        this.buildPermissionRow(kind, this.getPermissionKindLabel(kind), index, this.listPermissionKinds().length)
        if (index < this.listPermissionKinds().length - 1) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
      }, (kind: SitePermissionKind) => kind)
    }
  }

  @Builder
  private buildPermissionRow(kind: SitePermissionKind, title: string, index: number, total: number) {
    SettingsNavigationRow({
      title: title,
      value: this.getPermissionRuleLabel(kind),
      description: this.getPermissionRuleDescription(kind),
      rowPosition: this.resolveRowPosition(index, total),
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      onAction: () => {
        this.onAction('open_permission', kind);
      }
    })
  }

  @Builder
  private buildPermissionOptionList(kind: SitePermissionKind) {
    Scroll() {
      Column({ space: 12 }) {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          ForEach(this.getPermissionOptions(kind), (option: SitePermissionRuleOption, index: number) => {
            this.buildPermissionOptionRow(kind, option, index, 3)
            if (index < 2) {
              SettingsGroupDivider({ dividerColor: this.storedDividerColor })
            }
          }, (option: SitePermissionRuleOption) => `${kind}:${option.value}:${this.getPermissionRule(kind) === option.value ? 'selected' : 'idle'}`)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: SITE_INFO_CONTENT_TOP_PADDING,
        bottom: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildPermissionOptionRow(kind: SitePermissionKind, option: SitePermissionRuleOption, index: number, total: number) {
    SettingsOptionRow({
      title: option.label,
      helperText: option.helperText,
      rowPosition: this.resolveRowPosition(index, total),
      isSelected: this.getPermissionRule(kind) === option.value,
      isEnabled: true,
      radioGroup: `${SITE_INFO_PERMISSION_RADIO_GROUP}-${kind}`,
      radioValue: option.value,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.storedPressedBackgroundColor,
      selectedIndicatorColor: this.storedAccentColor,
      onAction: (): void => {
        this.selectPermissionRule(kind, option.value);
      }
    })
  }

  @Builder
  private buildSiteDataGroup() {
    Column({ space: 8 }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsStaticValueRow({
          title: '站点数据',
          value: this.snapshot.siteDataSummary.length > 0 ? this.snapshot.siteDataSummary : '暂无',
          rowPosition: 'first',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsNavigationRow({
          title: this.snapshot.isPrivateMode ? '管理本次私密数据' : '管理全部浏览数据',
          value: '',
          rowPosition: 'last',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onAction('open_browsing_data_settings');
          }
        })
      }

      Text(this.snapshot.isPrivateMode
        ? '系统当前不支持按站点清除私密存储，请使用上方入口清除本次私密数据。'
        : '只清除该网站保存的本地数据；Cookie 和网页缓存会保留，登录状态可能继续保留。')
        .width('100%')
        .padding({ left: 4, right: 4 })
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)

      Row() {
        BrowserSheetActionButton({
          label: '清除当前站点存储',
          emphasis: 'primary',
          actionEnabled: this.snapshot.canClearCurrentSiteStorage,
          accentColor: $r('app.color.permission_blocked'),
          onAction: () => {
            this.onAction('clear_site_data');
          }
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildOverviewNavigationGroup() {
    Column({ space: 8 }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsNavigationRow({
          title: '隐私保护',
          value: this.getPrivacyCoverageValue(),
          rowPosition: 'first',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onAction('open_protection_settings');
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: this.snapshot.isPrivateMode ? '本站网页保护（仅本次私密会话）' : '本站网页保护',
          checked: this.snapshot.session.protection.siteEnabled,
          isEnabled: this.snapshot.session.protection.siteToggleEnabled,
          rowPosition: 'middle',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (_checked: boolean) => {
            this.onAction('toggle_protection');
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      SettingsNavigationRow({
          title: '保护活动摘要',
          value: `${this.snapshot.session.protection.blockedCount} 项`,
          rowPosition: 'middle',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onAction('open_protection_log');
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsNavigationRow({
          title: '连接与证书',
          value: this.snapshot.connectionTitle.length > 0 ? this.snapshot.connectionTitle : '站点信息',
          rowPosition: 'middle',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onAction('open_certificate');
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsNavigationRow({
          title: '站点设置',
          value: '权限、数据、脚本',
          rowPosition: 'last',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onAction('open_site_customization');
          }
        })
      }

      Text(this.snapshot.session.protection.privacyCoverageSummary)
        .width('100%')
        .padding({ left: 4, right: 4 })
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
    }
    .width('100%')
  }

  @Builder
  private buildAdBlockLogContent() {
    Scroll() {
      Column({ space: 8 }) {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          this.buildAdBlockLogSummaryRow()
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          SettingsStaticValueRow({
            title: '请求拦截',
            value: `${this.snapshot.session.protection.requestBlockingCount}`,
            rowPosition: 'middle',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor
          })
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          SettingsStaticValueRow({
            title: '链接清理',
            value: `${this.snapshot.session.protection.linkCleaningCount}`,
            rowPosition: 'middle',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor
          })
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          SettingsStaticValueRow({
            title: '元素隐藏',
            value: `${this.snapshot.session.protection.elementHidingCount}`,
            rowPosition: 'last',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor
          })
        }

        Text('保护活动仅对当前网页汇总，不展示资源地址、规则或选择器。')
          .width('100%')
          .padding({ left: 4, right: 4 })
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: SITE_INFO_CONTENT_TOP_PADDING,
        bottom: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildAdBlockLogSummaryRow() {
    SettingsStaticValueRow({
      title: '本页保护动作',
      value: `${this.snapshot.session.protection.blockedCount}`,
      rowPosition: 'first',
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor
    })
  }

  private getProtectionHeaderTitle(): string {
    const state = this.snapshot.session.protection.availabilityState;
    if (state === 'active_with_actions') {
      return this.snapshot.isPrivateMode ? '网页保护 · 仅本次私密会话' : '网页保护 · 本页已生效';
    }
    if (state === 'active_without_actions') {
      return '网页保护 · 已开启';
    }
    if (state === 'site_disabled') {
      return '网页保护 · 本站已关闭';
    }
    if (state === 'global_disabled_or_unconfigured') {
      return '网页保护 · 未配置';
    }
    return '网页保护 · 暂不可用';
  }

  private getProtectionActionMetricLabel(): string {
    const state = this.snapshot.session.protection.availabilityState;
    if (state === 'active_with_actions') {
      return '本页保护动作';
    }
    if (state === 'active_without_actions') {
      return '网页保护已开启，本页暂无触发';
    }
    if (state === 'site_disabled') {
      return '本站网页保护已关闭';
    }
    if (state === 'global_disabled_or_unconfigured') {
      return '网页保护未配置';
    }
    return '网页保护暂不可用';
  }

  private getPrivacyCoverageValue(): string {
    if (this.snapshot.session.protection.privacyCoverageState === 'enabled') {
      return '已开启';
    }
    if (this.snapshot.session.protection.privacyCoverageState === 'preparing') {
      return '准备中';
    }
    if (this.snapshot.session.protection.privacyCoverageState === 'failed') {
      return '需要处理';
    }
    if (this.snapshot.session.protection.privacyCoverageState === 'site_disabled') {
      return '本站已关闭';
    }
    if (this.snapshot.session.protection.privacyCoverageState === 'unavailable') {
      return '不可用';
    }
    return '未开启';
  }


  @Builder
  private buildCertificateDetailList() {
    Scroll() {
      Column() {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          this.buildCertificateDetailRow('连接状态', this.snapshot.session.certificate.detailStatus, 0, 9)
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildCertificateDetailRow('网站', this.getSiteHostText(), 1, 9)
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildCertificateDetailRow('颁发给', this.snapshot.session.certificate.subject, 2, 9)
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildCertificateDetailRow('签发者', this.snapshot.session.certificate.issuer, 3, 9)
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildCertificateDetailRow('有效期开始', this.snapshot.session.certificate.validFrom, 4, 9)
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildCertificateDetailRow('有效期结束', this.snapshot.session.certificate.validTo, 5, 9)
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildCertificateDetailRow('证书链', this.snapshot.certificateChainText, 6, 9)
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildCertificateDetailRow('签名算法', this.snapshot.session.certificate.signatureAlgorithm, 7, 9)
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildCertificateDetailRow('序列号', this.snapshot.session.certificate.serialNumber, 8, 9)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: SITE_INFO_CONTENT_TOP_PADDING,
        bottom: SITE_INFO_CONTENT_BOTTOM_PADDING
      })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildCertificateDetailRow(label: string, value: string, index: number, total: number) {
    SettingsStaticValueRow({
      title: label,
      value: value.length > 0 ? value : '暂无',
      valueMaxLines: 2,
      rowPosition: this.resolveRowPosition(index, total),
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor
    })
  }

  @Builder
  private buildSinglePrimaryAction(label: string) {
    Row() {
      BrowserSheetActionButton({
        label: label,
        emphasis: 'primary',
        accentColor: this.storedAccentColor,
        onAction: () => {
          this.onAction('close');
        }
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private resolveFeatureHeaderTitle(): string {
    if (this.snapshot.session.mode === 'security') {
      return this.snapshot.isSecureSite ? '访问安全' : '连接未验证';
    }
    if (this.snapshot.session.mode === 'certificate') {
      return '证书详情';
    }
    if (this.snapshot.session.mode === 'adblock_log') {
      return '保护活动';
    }
    if (this.isPermissionPageMode(this.snapshot.session.mode)) {
      return `${this.getPermissionKindLabel(this.resolvePermissionKindFromMode(this.snapshot.session.mode))}权限`;
    }
    return this.getProtectionHeaderTitle();
  }

  private isFeaturePageNested(): boolean {
    return this.snapshot.session.mode === 'certificate' || this.snapshot.session.mode === 'adblock_log' ||
      this.isPermissionPageMode(this.snapshot.session.mode);
  }

  private shouldShowPageFooter(): boolean {
    return this.snapshot.session.mode === 'security' || this.snapshot.session.mode === 'certificate';
  }

  private resolveContentBottomOffset(): number {
    return this.shouldShowPageFooter() ? SITE_INFO_CONTENT_BOTTOM_PADDING : BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING;
  }

  private getSiteHostText(): string {
    return this.snapshot.siteHost.length > 0 ? this.snapshot.siteHost : '当前页面';
  }

  private getProtectionSummaryText(): string {
    const blockedCount = this.resolveSecurityBlockedCount();
    if (blockedCount > 0) {
      return `已拦截 ${blockedCount} 项`;
    }
    return this.snapshot.session.protection.summary;
  }

  private resolveSecurityBlockedCount(): number {
    return Math.max(0, Math.round(this.snapshot.session.protection.blockedCount));
  }

  private resolveGuardianDays(): number {
    return Math.max(0, Math.round(this.snapshot.siteGuardianDays));
  }

  private formatMetricCount(value: number): string {
    const normalized = Math.max(0, Math.floor(value));
    if (normalized >= 100000000) {
      return `${Math.floor(normalized / 100000000)}亿`;
    }
    if (normalized >= 10000) {
      const whole = Math.floor(normalized / 10000);
      const decimal = Math.floor((normalized % 10000) / 1000);
      return decimal > 0 ? `${whole}.${decimal}万` : `${whole}万`;
    }
    return `${normalized}`;
  }

  private getPermissionRule(kind: SitePermissionKind): SitePermissionRule {
    if (kind === 'camera') {
      return this.snapshot.session.permissionDraft.camera;
    }
    if (kind === 'microphone') {
      return this.snapshot.session.permissionDraft.microphone;
    }
    if (kind === 'location') {
      return this.snapshot.session.permissionDraft.location;
    }
    if (kind === 'sensor') {
      return this.snapshot.session.permissionDraft.sensor;
    }
    return this.snapshot.session.permissionDraft.clipboard;
  }

  private selectPermissionRule(kind: SitePermissionKind, rule: SitePermissionRule): void {
    if (this.getPermissionRule(kind) === rule) {
      return;
    }
    this.onAction('change_permission', kind, rule);
  }

  private listPermissionKinds(): SitePermissionKind[] {
    return this.capabilityCatalog.listDevicePermissionKinds();
  }

  private getPermissionRuleLabel(kind: SitePermissionKind): string {
    return this.capabilityCatalog.getPermissionRuleLabel(this.getPermissionRule(kind));
  }

  private getPermissionRuleDescription(kind: SitePermissionKind): string {
    return this.capabilityCatalog.getPermissionRuleDescription(kind, this.getPermissionRule(kind));
  }

  private getPermissionKindLabel(kind: SitePermissionKind): string {
    return this.capabilityCatalog.getPermissionTitle(kind);
  }

  private getPermissionOptions(kind: SitePermissionKind): SitePermissionRuleOption[] {
    return this.capabilityCatalog.buildSitePermissionOptions(kind);
  }

  private isPermissionPageMode(mode: string): boolean {
    return mode === 'permission_camera' || mode === 'permission_microphone' ||
      mode === 'permission_location' || mode === 'permission_sensor' || mode === 'permission_clipboard';
  }

  private resolvePermissionKindFromMode(mode: string): SitePermissionKind {
    return this.capabilityCatalog.resolvePermissionKind(mode.replace('permission_', ''));
  }

  private resolveRowPosition(index: number, total: number): SettingsRowPosition {
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
