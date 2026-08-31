import {
  SecureDnsCustomProfileState,
  SecureDnsSettingsObserver,
  SecureDnsSettingsOptionState,
  SecureDnsSettingsState
} from '../../../core/settings/SecureDnsSettingsCoordinator';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import { sharedSecureDnsSettingsCoordinator } from '../../bootstrap/BrowserAppRuntime';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsOptionRow,
  SettingsRowPosition
} from './SettingsRows';

const SECURE_DNS_RADIO_GROUP: string = 'secure-dns-provider';

@Component
export struct SecureDnsSettingsContent {
  @Prop surfaceBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop desktopPresentation: boolean = false;
  onSettingsChanged?: () => void;
  onEditCustomProfile?: (profileId: string) => void;
  @State private state: SecureDnsSettingsState = sharedSecureDnsSettingsCoordinator.getState();

  aboutToAppear(): void {
    const observer: SecureDnsSettingsObserver = (
      state: SecureDnsSettingsState,
      persistedChange: boolean
    ): void => {
      this.state = state;
      if (persistedChange) {
        this.onSettingsChanged?.();
      }
    };
    this.state = sharedSecureDnsSettingsCoordinator.connect(observer);
  }

  aboutToDisappear(): void {
    sharedSecureDnsSettingsCoordinator.disconnect();
  }

  build() {
    Column({ space: 16 }) {
      SettingsSection({
        title: 'DNS 服务',
        secondaryTextColor: this.secondaryTextColor
      }) {
        SettingsGroupCard({
          surfaceColor: this.surfaceBackground,
          desktopPresentation: this.desktopPresentation
        }) {
          ForEach(this.state.options, (option: SecureDnsSettingsOptionState, index: number) => {
            SettingsOptionRow({
              title: option.title,
              desktopPresentation: this.desktopPresentation,
              rowPosition: this.resolveRowPosition(index, this.state.options.length),
              isSelected: option.id === this.state.draftSelectionId,
              isEnabled: !this.state.saving,
              selectedIndicatorColor: this.accentColor,
              radioGroup: SECURE_DNS_RADIO_GROUP,
              radioValue: option.id,
              primaryTextColor: this.primaryTextColor,
              secondaryTextColor: this.secondaryTextColor,
              pressedBackgroundColor: this.pressedBackground,
              onAction: (): void => {
                sharedSecureDnsSettingsCoordinator.handleOptionSelected(option.id, this.buildBoundaryInput());
              }
            })
            if (index < this.state.options.length - 1) {
              SettingsGroupDivider({ dividerColor: this.dividerColor })
            }
          }, (option: SecureDnsSettingsOptionState): string => option.id)
        }

      }

      SettingsSection({
        title: '自定义 DNS',
        secondaryTextColor: this.secondaryTextColor
      }) {
        if (this.state.customProfiles.length > 0) {
          SettingsGroupCard({
            surfaceColor: this.surfaceBackground,
            desktopPresentation: this.desktopPresentation
          }) {
            ForEach(this.state.customProfiles, (profile: SecureDnsCustomProfileState, index: number) => {
              SettingsOptionRow({
                title: profile.title,
                desktopPresentation: this.desktopPresentation,
                rowPosition: this.resolveRowPosition(index, this.state.customProfiles.length),
                isSelected: profile.isActive,
                isEnabled: !this.state.saving,
                selectedIndicatorColor: this.accentColor,
                radioGroup: SECURE_DNS_RADIO_GROUP,
                radioValue: 'custom:' + profile.id,
                primaryTextColor: this.primaryTextColor,
                secondaryTextColor: this.secondaryTextColor,
                pressedBackgroundColor: this.pressedBackground,
                trailingActionIcon: $r('sys.symbol.chevron_right'),
                isTrailingActionEnabled: !this.state.saving,
                onAction: (): void => {
                  sharedSecureDnsSettingsCoordinator.handleCustomProfileSelected(
                    profile.id,
                    this.buildBoundaryInput()
                  );
                },
                onTrailingAction: (): void => {
                  this.onEditCustomProfile?.(profile.id);
                }
              })
              if (index < this.state.customProfiles.length - 1) {
                SettingsGroupDivider({ dividerColor: this.dividerColor })
              }
            }, (profile: SecureDnsCustomProfileState): string => profile.id)
          }
        } else {
          SettingsFooterText({
            text: '暂无自定义 DNS。',
            secondaryTextColor: this.secondaryTextColor
          })
        }
      }

    }
    .width('100%')
  }

  private resolveRowPosition(index: number, count: number): SettingsRowPosition {
    if (count <= 1) {
      return 'single';
    }
    if (index <= 0) {
      return 'first';
    }
    if (index >= count - 1) {
      return 'last';
    }
    return 'middle';
  }

  private buildBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

}
