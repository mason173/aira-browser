import {
  ExternalAppSearchTargetId
} from '../../../common/models/BrowserModels';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { BrowserThemeViewState } from '../../../core/theme/BrowserThemeViewState';
import {
  ExternalAppSearchTarget
} from '../../../services/search/ExternalAppSearchService';
import { ExternalAppSearchTargetList } from './ExternalAppSearchTargetList';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsFooterText,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsSwitchRow } from '../settings/SettingsRows';

@Component
export struct ExternalAppSearchSettingsScreen {
  @Prop featureEnabled: boolean = true;
  @Prop selectedTargetIds: ExternalAppSearchTargetId[] = [];
  @Prop targets: ExternalAppSearchTarget[] = [];
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop theme: BrowserThemeViewState;
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  onBack: () => void = () => {};
  onFeatureEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onTargetEnabledChange: (targetId: ExternalAppSearchTargetId, enabled: boolean) => void =
    (_targetId: ExternalAppSearchTargetId, _enabled: boolean) => {};
  onTargetOrderChange: (targetOrder: ExternalAppSearchTargetId[]) => void =
    (_targetOrder: ExternalAppSearchTargetId[]) => {};

  build() {
    SettingsHdsScaffold({
      title: '跨应用搜索',
      backIconKind: 'back',
      pageBackground: this.theme.pageBackground,
      headerButtonBackground: this.theme.controlBackground,
      primaryTextColor: this.theme.textPrimary,
      dividerColor: this.theme.divider,
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: !this.desktopPresentation,
      showTitleBar: !this.desktopPresentation,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      onBack: () => {
        this.onBack();
      }
    }) {
      SettingsPresentationScrollBody({
        contentSpace: 18,
        desktopPresentation: this.desktopPresentation,
        topPadding: 16,
        bottomPadding: 32
      }) {
        this.buildMasterSection()
        this.buildTargetSection()
      }
    }
  }

  @Builder
  private buildMasterSection() {
    SettingsSection({
      title: '功能',
      secondaryTextColor: this.theme.textSecondary
    }) {
      SettingsGroupCard({
        surfaceColor: this.theme.surfaceBackground,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsSwitchRow({
          title: '显示应用入口',
          desktopPresentation: this.desktopPresentation,
          checked: this.featureEnabled,
          primaryTextColor: this.theme.textPrimary,
          secondaryTextColor: this.theme.textSecondary,
          pressedBackgroundColor: this.theme.pressedBackground,
          rowPosition: 'single',
          onChange: (enabled: boolean) => {
            this.onFeatureEnabledChange(enabled);
          }
        })
      }
      SettingsFooterText({
        text: '开启后，搜索框展开时会显示下方选择的应用入口。关闭后会保留当前选择。',
        secondaryTextColor: this.theme.textSecondary
      })
    }
  }

  @Builder
  private buildTargetSection() {
    SettingsSection({
      title: '显示的应用',
      secondaryTextColor: this.theme.textSecondary
    }) {
      ExternalAppSearchTargetList({
        featureEnabled: this.featureEnabled,
        selectedTargetIds: this.selectedTargetIds,
        targets: this.targets,
        theme: this.theme,
        desktopPresentation: this.desktopPresentation,
        onTargetEnabledChange: (targetId: ExternalAppSearchTargetId, enabled: boolean) => {
          this.onTargetEnabledChange(targetId, enabled);
        },
        onTargetOrderChange: (targetOrder: ExternalAppSearchTargetId[]) => {
          this.onTargetOrderChange(targetOrder);
        }
      })
      SettingsFooterText({
        text: '拖动开关左侧的手柄可以调整应用入口顺序。',
        secondaryTextColor: this.theme.textSecondary
      })
    }
  }
}
