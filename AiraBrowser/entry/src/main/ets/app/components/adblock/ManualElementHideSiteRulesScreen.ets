import {
  ManualElementHideRuleRowViewState,
  ManualElementHideSiteRulesViewState
} from '../../../core/adblock/ManualElementHideSettingsViewModel';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { AiraIcon } from '../common/AiraIcon';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsActionButton,
  SettingsSwitchRow
} from '../settings/SettingsRows';

@Component
export struct ManualElementHideSiteRulesScreen {
  private settingsScroller: Scroller = new Scroller();
  @Prop state: ManualElementHideSiteRulesViewState = {
    host: '',
    enabled: false,
    rules: [],
    ruleCountText: '没有清理规则',
    hasRules: false
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop pageBackground: ResourceColor = '';
  @Prop surfaceBackground: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  onSiteEnabledChange: (host: string, enabled: boolean) => void = (_host: string, _enabled: boolean) => {};
  onDeleteRule: (host: string, ruleId: string, selector: string) => void =
    (_host: string, _ruleId: string, _selector: string) => {};
  onClearSite: (host: string) => void = (_host: string) => {};
  onBack: () => void = () => {};

  build() {
    SettingsHdsScaffold({
      title: this.state.host,
      backIconKind: 'back',
      pageBackground: this.pageBackground,
      headerButtonBackground: this.pressedBackground,
      primaryTextColor: this.primaryTextColor,
      dividerColor: this.dividerColor,
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: !this.desktopPresentation,
      showTitleBar: !this.desktopPresentation,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      scrollers: [this.settingsScroller],
      onBack: () => {
        this.onBack();
      }
    }) {
      Column() {
        SettingsPresentationScrollBody({
          contentSpace: 18,
          desktopPresentation: this.desktopPresentation,
          topPadding: 16,
          bottomPadding: 32,
          scroller: this.settingsScroller,
          clipContent: true
        }) {
          this.buildSiteSettingsSection()
          this.buildRuleSection()
          this.buildClearAllAction()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageBackground)
    }
  }

  @Builder
  private buildSiteSettingsSection() {
    SettingsSection({
      title: '网站设置',
      secondaryTextColor: this.secondaryTextColor
    }) {
      Column({ space: 10 }) {
        SettingsGroupCard({
          surfaceColor: this.surfaceBackground,
          desktopPresentation: this.desktopPresentation
        }) {
          SettingsSwitchRow({
            title: '自动隐藏已清理元素',
            desktopPresentation: this.desktopPresentation,
            checked: this.state.enabled,
            rowPosition: 'single',
            primaryTextColor: this.primaryTextColor,
            secondaryTextColor: this.secondaryTextColor,
            pressedBackgroundColor: this.pressedBackground,
            onChange: (enabled: boolean) => {
              this.onSiteEnabledChange(this.state.host, enabled);
            }
          })
        }
        SettingsFooterText({
          text: this.state.enabled
            ? '刷新或再次打开这个网站时，会继续应用下面的清理规则。'
            : '已暂停；刷新或再次打开这个网站时，不会应用下面的清理规则。',
          secondaryTextColor: this.secondaryTextColor
        })
      }
      .width('100%')
    }
  }

  @Builder
  private buildRuleSection() {
    SettingsSection({
      title: this.state.ruleCountText,
      secondaryTextColor: this.secondaryTextColor
    }) {
      SettingsGroupCard({
        surfaceColor: this.surfaceBackground,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.state.rules, (item: ManualElementHideRuleRowViewState, index: number) => {
          this.buildRuleRow(item)
          if (index < this.state.rules.length - 1) {
            SettingsGroupDivider({ dividerColor: this.dividerColor })
          }
        }, (item: ManualElementHideRuleRowViewState) => item.id)
      }
    }
  }

  @Builder
  private buildRuleRow(item: ManualElementHideRuleRowViewState) {
    Row({ space: 12 }) {
      Text(item.selector)
        .layoutWeight(1)
        .fontSize(15)
        .lineHeight(20)
        .fontColor(this.primaryTextColor)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button() {
        AiraIcon({
          airaIconId: 'site.setting.clearOnClose',
          iconSize: 18,
          iconColor: $r('app.color.permission_blocked')
        })
      }
      .width(40)
      .height(40)
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.TEXTUAL)
      .stateEffect(true)
      .accessibilityText(`删除规则 ${item.selector}`)
      .onClick(() => {
        this.onDeleteRule(this.state.host, item.id, item.selector);
      })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildClearAllAction() {
    SettingsActionButton({
      title: '清除这个网站的全部规则',
      emphasis: 'danger',
      variant: 'tonal',
      pressedBackgroundColor: this.pressedBackground,
      onAction: () => {
        this.onClearSite(this.state.host);
      }
    })
  }
}
