import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  BrowserTrackingProtectionOptionState,
  BrowserTrackingProtectionSettingsCoordinator,
  BrowserTrackingProtectionSettingsState
} from '../../../core/settings/BrowserTrackingProtectionSettingsCoordinator';
import { BrowserTrackingProtectionMode } from '../../../services/privacy/BrowserFingerprintPrivacyPolicyService';
import {
  sharedBrowserFingerprintPrivacyPolicyService,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsOptionRow,
  SettingsRowPosition,
  SettingsStaticValueRow
} from './SettingsRows';
import {
  SettingsDesktopDivider,
  SettingsDesktopGroup,
  SettingsDesktopOptionRow,
  SettingsDesktopStaticValueRow
} from './SettingsDesktopRows';

const TRACKING_PROTECTION_RADIO_GROUP: string = 'browser-tracking-protection';

@Component
export struct BrowserTrackingProtectionSettingsContent {
  private readonly coordinator: BrowserTrackingProtectionSettingsCoordinator =
    new BrowserTrackingProtectionSettingsCoordinator(
      sharedPreferencesRepository,
      sharedBrowserFingerprintPrivacyPolicyService
    );
  @Prop surfaceBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop desktopPresentation: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @State private state: BrowserTrackingProtectionSettingsState = this.coordinator.buildState();
  @State private saving: boolean = false;
  onSettingsChanged?: () => void;

  aboutToAppear(): void {
    this.state = this.coordinator.buildState();
  }

  build() {
    Column({ space: 18 }) {
      SettingsSection({ title: '防跟踪防护', secondaryTextColor: this.secondaryTextColor }) {
        this.buildModeSurface()
        SettingsFooterText({ text: this.state.footerText, secondaryTextColor: this.secondaryTextColor })
      }

      SettingsSection({ title: '当前策略', secondaryTextColor: this.secondaryTextColor }) {
        this.buildPolicySurface()
        SettingsFooterText({ text: this.state.limitationText, secondaryTextColor: this.secondaryTextColor })
      }
    }
    .width('100%')
  }

  @Builder
  private buildModeSurface() {
    if (this.desktopPresentation) {
      SettingsDesktopGroup({ surfaceColor: this.surfaceBackground }) {
        this.buildModeRows()
      }
    } else {
      SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
        this.buildModeRows()
      }
    }
  }

  @Builder
  private buildModeRows() {
    ForEach(this.state.options, (
      option: BrowserTrackingProtectionOptionState,
      index: number
    ) => {
      if (this.desktopPresentation) {
        SettingsDesktopOptionRow({
          title: option.title,
          isSelected: option.mode === this.state.mode,
          isEnabled: !this.saving,
          radioGroup: TRACKING_PROTECTION_RADIO_GROUP,
          radioValue: option.mode,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          hoverBackgroundColor: this.pressedBackground,
          focusColor: this.accentColor,
          onAction: (): void => {
            this.selectMode(option.mode);
          }
        })
      } else {
        SettingsOptionRow({
          title: option.title,
          rowPosition: this.resolveRowPosition(index, this.state.options.length),
          isSelected: option.mode === this.state.mode,
          isEnabled: !this.saving,
          selectedIndicatorColor: this.accentColor,
          radioGroup: TRACKING_PROTECTION_RADIO_GROUP,
          radioValue: option.mode,
          onAction: (): void => {
            this.selectMode(option.mode);
          }
        })
      }
      if (index < this.state.options.length - 1) {
        if (this.desktopPresentation) {
          SettingsDesktopDivider({ dividerColor: this.dividerColor })
        } else {
          SettingsGroupDivider({ dividerColor: this.dividerColor })
        }
      }
    }, (option: BrowserTrackingProtectionOptionState): string =>
      `${option.mode}:${option.mode === this.state.mode ? 'selected' : 'idle'}:${this.saving ? 'saving' : 'ready'}`)
  }

  @Builder
  private buildPolicySurface() {
    if (this.desktopPresentation) {
      SettingsDesktopGroup({ surfaceColor: this.surfaceBackground }) {
        this.buildPolicyRows()
      }
    } else {
      SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
        this.buildPolicyRows()
      }
    }
  }

  @Builder
  private buildPolicyRows() {
    this.buildPolicyRow(
      '网页客户端提示',
      this.state.clientHintsRuntimeApplied ? (this.state.clientHintsEnabled ? '允许' : '已收紧') : '未完全生效',
      'first'
    )
    this.buildPolicyDivider()
    this.buildPolicyRow(
      '第三方 Cookie',
      this.state.cookiePolicyRuntimeApplied ? (this.state.thirdPartyCookiesAllowed ? '允许' : '已拦截') : '未完全生效',
      'middle'
    )
    this.buildPolicyDivider()
    this.buildPolicyRow(
      '网页标识',
      this.state.stableBrowserIdentityEnabled ? '保持一致' : '兼容模式',
      'last'
    )
  }

  @Builder
  private buildPolicyRow(title: ResourceStr, value: ResourceStr, rowPosition: SettingsRowPosition) {
    if (this.desktopPresentation) {
      SettingsDesktopStaticValueRow({
        title: title,
        value: value,
        primaryTextColor: this.primaryTextColor,
        secondaryTextColor: this.secondaryTextColor
      })
    } else {
      SettingsStaticValueRow({ title: title, value: value, rowPosition: rowPosition })
    }
  }

  @Builder
  private buildPolicyDivider() {
    if (this.desktopPresentation) {
      SettingsDesktopDivider({ dividerColor: this.dividerColor })
    } else {
      SettingsGroupDivider({ dividerColor: this.dividerColor })
    }
  }

  private selectMode(mode: BrowserTrackingProtectionMode): void {
    if (this.saving || mode === this.state.mode) {
      return;
    }
    if (mode === 'enhanced') {
      showCenteredAlertDialog({
        title: '开启增强反跟踪？',
        message: '将收紧网页客户端提示并拦截第三方 Cookie。少数登录、支付或嵌入内容可能受影响；现有网页重新加载后完整生效。',
        autoCancel: true,
        primaryButton: { value: '取消', action: (): void => {} },
        secondaryButton: { value: '开启', action: (): void => this.persistMode(mode) }
      });
      return;
    }
    this.persistMode(mode);
  }

  private persistMode(mode: BrowserTrackingProtectionMode): void {
    const previous = this.state;
    this.saving = true;
    this.coordinator.setMode(mode, this.buildBoundaryInput())
      .then((state: BrowserTrackingProtectionSettingsState): void => {
        this.saving = false;
        this.state = state;
        this.onSettingsChanged?.();
      })
      .catch((_error: Error): void => {
        this.saving = false;
        this.state = previous;
      });
  }

  private resolveRowPosition(index: number, count: number): SettingsRowPosition {
    if (count <= 1) {
      return 'single';
    }
    if (index <= 0) {
      return 'first';
    }
    return index >= count - 1 ? 'last' : 'middle';
  }

  private buildBoundaryInput(): BrowserDataBoundaryInput {
    return { dataScope: this.dataScope, privacyMode: this.privacyMode };
  }
}
