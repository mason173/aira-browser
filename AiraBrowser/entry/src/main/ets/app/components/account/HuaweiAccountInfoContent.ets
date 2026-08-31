import {
  HuaweiAccountInfoRowState,
  HuaweiAccountInfoViewState
} from '../../../core/settings/HuaweiAccountInfoViewModel';
import { BrowserThemeViewState } from '../../../core/theme/BrowserThemeViewState';
import {
  SettingsAccountRecognitionBadge,
  SettingsActionButton,
  SettingsInfoTooltipButton,
  SettingsNavigationRow,
  SettingsStaticValueRow
} from '../settings/SettingsRows';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsSection
} from '../settings/SettingsLayout';
import { ActivityHeatmapCard } from './ActivityHeatmapCard';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../../common/config/AiraDistributionCapabilityOwner';

export type HuaweiAccountInfoContentMode = 'page' | 'embedded_popup';

@Component
export struct HuaweiAccountInfoContent {
  @Prop state: HuaweiAccountInfoViewState;
  @Prop theme: BrowserThemeViewState;
  @Prop iconForegroundColor: ResourceColor = '';
  @Prop isBusy: boolean = false;
  @Prop contentMode: HuaweiAccountInfoContentMode = 'page';
  @Prop showAiraProEntry: boolean = false;
  onCopyAccountId: () => void = () => {};
  onRequestSignOut: () => void = () => {};
  onOpenAiraPro: () => void = () => {};

  build() {
    Column({ space: 14 }) {
      this.buildAccountHeader()
      if (this.showAiraProEntry && AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
        this.buildAiraProSection()
      }
      this.buildActivitySection()
      this.buildInfoSection()
      this.buildSignOutSection()
    }
    .width('100%')
  }

  @Builder
  private buildAiraProSection() {
    SettingsSection({ title: '会员', secondaryTextColor: this.theme.textSecondary }) {
      SettingsGroupCard({ surfaceColor: this.theme.surfaceBackground }) {
        SettingsNavigationRow({
          title: 'Aira Pro',
          value: this.resolveMembershipValue(),
          airaIconId: 'settings.membership',
          iconBackgroundColor: this.theme.accent,
          iconColor: this.iconForegroundColor,
          rowPosition: 'single',
          primaryTextColor: this.theme.textPrimary,
          secondaryTextColor: this.theme.textSecondary,
          pressedBackgroundColor: this.theme.pressedBackground,
          onAction: this.onOpenAiraPro
        })
      }
    }
  }

  @Builder
  private buildAccountHeader() {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.state.avatarUri.trim().length > 0) {
          Image(this.state.avatarUri)
            .width(82)
            .height(82)
            .borderRadius(41)
            .clip(true)
            .objectFit(ImageFit.Cover)
        } else {
          SymbolGlyph($r('sys.symbol.person_fill'))
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.iconForegroundColor])
        }
      }
      .width(82)
      .height(82)
      .borderRadius(41)
      .backgroundColor(this.theme.accent)
      .clip(true)

      Row({ space: 8 }) {
        Text(this.state.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '72%' })

        SettingsAccountRecognitionBadge({
          kind: this.state.recognitionBadge,
          badgeBackgroundColor: this.theme.accent,
          badgeTextColor: this.iconForegroundColor
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Row({ space: 2 }) {
        Text(this.state.subtitle)
          .fontSize(13)
          .fontColor(this.theme.textSecondary)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: this.state.recognitionInfoText.length > 0 ? '82%' : '100%' })

        if (this.state.recognitionInfoText.length > 0 && this.contentMode === 'page') {
          SettingsInfoTooltipButton({
            tooltipMessage: this.state.recognitionInfoText,
            tooltipAccessibilityLabel: '查看 Insider 身份说明',
            tooltipIconColor: this.theme.textSecondary,
            tooltipBackgroundColor: this.theme.surfaceBackground,
            tooltipTextColor: this.theme.textSecondary
          })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      if (this.state.recognitionInfoText.length > 0 && this.contentMode === 'embedded_popup') {
        Text(this.state.recognitionInfoText)
          .width('100%')
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.theme.textSecondary)
          .textAlign(TextAlign.Center)
          .maxLines(3)
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildActivitySection() {
    Column({ space: 10 }) {
      Row() {
        Text('活跃')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme.textSecondary)
          .padding({ left: 6 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ActivityHeatmapCard({
        state: this.state.activity,
        surfaceColor: this.theme.surfaceBackground,
        tooltipTextColor: this.theme.textPrimary,
        heatmapColors: this.theme.activityHeatmap,
        tooltipPresentation: this.contentMode === 'embedded_popup' ? 'none' : 'popup'
      })
    }
    .width('100%')
  }

  @Builder
  private buildInfoSection() {
    SettingsSection({ title: '个人信息', secondaryTextColor: this.theme.textSecondary }) {
      SettingsGroupCard({ surfaceColor: this.theme.surfaceBackground }) {
        ForEach(this.state.rows, (row: HuaweiAccountInfoRowState, index: number) => {
          SettingsStaticValueRow({
            title: row.title,
            value: row.value,
            valueMaxLines: row.id === 'uid' ? 4 : 1,
            valueClickable: row.id === 'uid' && this.state.canSignOut,
            pressedBackgroundColor: this.theme.pressedBackground,
            rowPosition: this.resolveRowPosition(index, this.state.rows.length),
            primaryTextColor: this.theme.textPrimary,
            secondaryTextColor: this.theme.textSecondary,
            onValueAction: () => {
              if (row.id === 'uid') {
                this.onCopyAccountId();
              }
            }
          })
          if (index < this.state.rows.length - 1) {
            SettingsGroupDivider({ dividerColor: this.theme.divider })
          }
        }, (row: HuaweiAccountInfoRowState) => this.resolveInfoRowRenderKey(row))
      }
    }
  }

  @Builder
  private buildSignOutSection() {
    SettingsActionButton({
      title: '退出华为账号',
      emphasis: 'danger',
      isEnabled: this.state.canSignOut && !this.isBusy,
      pressedBackgroundColor: this.theme.pressedBackground,
      onAction: () => {
        this.onRequestSignOut();
      }
    })
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }

  private resolveInfoRowRenderKey(row: HuaweiAccountInfoRowState): string {
    return `${row.id}:${this.theme.resolvedMode}:${this.theme.surfaceBackground}:${this.theme.textPrimary}:` +
      `${this.theme.textSecondary}:${this.theme.divider}`;
  }

  private resolveMembershipValue(): string {
    return this.state.rows.find((row: HuaweiAccountInfoRowState): boolean => row.id === 'membership')?.value ?? '';
  }
}
