import { pasteboard } from '@kit.BasicServicesKit';
import { sharedMembershipFeature } from '../../bootstrap/BrowserAppRuntime';
import { AIRA_MEMBER_ID_STORAGE_KEY, AiraMemberIdState } from '../../../features/membership/MembershipFeature';
import {
  HuaweiAccountInfoRowState,
  HuaweiAccountInfoViewState
} from '../../../core/settings/HuaweiAccountInfoViewModel';
import { BrowserThemeViewState } from '../../../core/theme/BrowserThemeViewState';
import {
  SettingsAccountRecognitionBadge,
  SettingsActionButton,
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
import { AiraIcon } from '../common/AiraIcon';

export type HuaweiAccountInfoContentMode = 'page' | 'embedded_popup';

@Component
export struct HuaweiAccountInfoContent {
  @Prop @Watch('refreshMemberId') state: HuaweiAccountInfoViewState;
  @Prop theme: BrowserThemeViewState;
  @Prop iconForegroundColor: ResourceColor = '';
  @Prop isBusy: boolean = false;
  @Prop contentMode: HuaweiAccountInfoContentMode = 'page';
  @Prop showAiraProEntry: boolean = false;
  @StorageProp(AIRA_MEMBER_ID_STORAGE_KEY) private memberIdentity: AiraMemberIdState = new AiraMemberIdState();
  @State private recognitionInfoVisible: boolean = false;
  onCopyAccountId: () => void = () => {};
  onRequestSignOut: () => void = () => {};
  onOpenAiraPro: () => void = () => {};

  aboutToAppear(): void {
    this.refreshMemberId();
  }

  private refreshMemberId(): void {
    sharedMembershipFeature.ensureMemberId(this.state.uid ?? '').catch((): void => {});
  }

  private memberId(): string {
    return this.state.uid === this.memberIdentity.uid ? this.memberIdentity.id : '';
  }

  private copyMemberId(): void {
    const id = this.memberId();
    if (!id) { return; }
    try {
      pasteboard.getSystemPasteboard().setDataSync(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, id));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_account_member_id_copied') });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_account_copy_failed') });
    }
  }

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
    SettingsSection({ title: $r('app.string.settings_account_membership'), secondaryTextColor: this.theme.textSecondary }) {
      SettingsGroupCard({ surfaceColor: this.theme.surfaceBackground }) {
        SettingsNavigationRow({
          title: 'Aira Pro',
          value: this.resolveMembershipValue(),
          airaIconId: 'settings.membership',
          iconBackgroundColor: this.theme.settingsIconBackgrounds.syncMethod,
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
          AiraIcon({
            airaIconId: 'browser.toolbar.account',
            iconSize: 40,
            iconColor: this.iconForegroundColor
          })
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
          .constraintSize({ maxWidth: this.state.showRecognitionInfo ? '82%' : '100%' })

        if (this.state.showRecognitionInfo && this.contentMode === 'page') {
          this.buildRecognitionInfoButton()
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      if (this.state.showRecognitionInfo && this.contentMode === 'embedded_popup') {
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
        Text($r('app.string.settings_account_activity'))
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
    SettingsSection({ title: $r('app.string.settings_account_profile'), secondaryTextColor: this.theme.textSecondary }) {
      SettingsGroupCard({ surfaceColor: this.theme.surfaceBackground }) {
        if (this.memberId().length > 0) {
          SettingsStaticValueRow({
            title: $r('app.string.settings_account_member_id'),
            value: this.memberId(),
            valueClickable: true,
            pressedBackgroundColor: this.theme.pressedBackground,
            rowPosition: this.resolveRowPosition(0, this.state.rows.length + 1),
            primaryTextColor: this.theme.textPrimary,
            secondaryTextColor: this.theme.textSecondary,
            onValueAction: () => { this.copyMemberId(); }
          })
          SettingsGroupDivider({ dividerColor: this.theme.divider })
        }
        ForEach(this.state.rows, (row: HuaweiAccountInfoRowState, index: number) => {
          SettingsStaticValueRow({
            title: row.title,
            value: row.value,
            valueMaxLines: row.id === 'uid' ? 4 : 1,
            valueClickable: row.id === 'uid' && this.state.canSignOut,
            pressedBackgroundColor: this.theme.pressedBackground,
            rowPosition: this.memberId().length > 0
              ? this.resolveRowPosition(index + 1, this.state.rows.length + 1)
              : this.resolveRowPosition(index, this.state.rows.length),
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
      title: $r('app.string.settings_account_sign_out_action'),
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

  private resolveMembershipValue(): ResourceStr {
    const row = this.state.rows.find((item: HuaweiAccountInfoRowState): boolean => item.id === 'membership');
    return row !== undefined ? row.value : '';
  }

  @Builder
  private buildRecognitionInfoButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(17)
        .fontColor([this.theme.textSecondary])
    }
    .width(28)
    .height(28)
    .type(ButtonType.Circle)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(true)
    .accessibilityText($r('app.string.settings_account_insider_a11y'))
    .onClick(() => {
      if (this.state.showRecognitionInfo) {
        this.recognitionInfoVisible = !this.recognitionInfoVisible;
      }
    })
    .bindPopup(this.recognitionInfoVisible, {
      builder: this.buildRecognitionInfoPopup,
      placement: Placement.Top,
      enableArrow: true,
      autoCancel: true,
      mask: false,
      targetSpace: 8,
      popupColor: this.theme.surfaceBackground,
      radius: 14,
      width: 246,
      onStateChange: (event: PopupStateChangeParam) => {
        if (!event.isVisible) {
          this.recognitionInfoVisible = false;
        }
      }
    })
  }

  @Builder
  private buildRecognitionInfoPopup() {
    Text(this.state.recognitionInfoText)
      .fontSize(13)
      .fontColor(this.theme.textSecondary)
      .padding(12)
  }
}
