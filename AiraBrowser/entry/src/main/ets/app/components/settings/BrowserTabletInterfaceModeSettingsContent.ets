import { BrowserTabletInterfaceMode } from '../../../common/models/BrowserDevicePresentationModels';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import {
  BrowserTabletInterfaceModeOptionState,
  BrowserTabletInterfaceModeSettingsCoordinator,
  BrowserTabletInterfaceModeSettingsState
} from '../../../core/settings/BrowserTabletInterfaceModeSettingsCoordinator';
import { BrowserTabletInterfaceModeTransitionConsumer } from '../../../core/settings/BrowserTabletInterfaceModeTransitionOwner';
import { sharedBrowserTabletInterfaceModeRepository } from '../../bootstrap/BrowserAppRuntime';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsSection
} from './SettingsLayout';
import { SettingsOptionRow, SettingsRowPosition } from './SettingsRows';
import { DesktopInterfaceModeConfirmationDialog } from './DesktopInterfaceModeConfirmationDialog';
import { createCenteredDialogMaterial } from '../common/CenteredDialogSurface';

const TABLET_INTERFACE_MODE_RADIO_GROUP: string = 'tablet-interface-mode';

@Component
export struct BrowserTabletInterfaceModeSettingsContent {
  private readonly coordinator: BrowserTabletInterfaceModeSettingsCoordinator =
    new BrowserTabletInterfaceModeSettingsCoordinator(sharedBrowserTabletInterfaceModeRepository);
  @Prop surfaceBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop desktopPresentation: boolean = false;
  @Prop transitionConsumer: BrowserTabletInterfaceModeTransitionConsumer = 'phone_native_settings_handoff';
  onSettingsChanged?: () => void;
  @State private state: BrowserTabletInterfaceModeSettingsState = this.coordinator.buildState();
  @State private saving: boolean = false;
  @State private desktopModeConfirmationAccepted: boolean = false;
  private desktopModeConfirmationDialogController: CustomDialogController = new CustomDialogController({
    builder: DesktopInterfaceModeConfirmationDialog({
      accepted: $desktopModeConfirmationAccepted,
      onCancel: (): void => {
        this.desktopModeConfirmationAccepted = false;
      },
      onConfirm: (): void => {
        this.desktopModeConfirmationAccepted = false;
        this.persistMode('desktop');
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
  });

  aboutToAppear(): void {
    this.state = this.coordinator.buildState();
  }

  build() {
    SettingsSection({
      title: '界面模式',
      secondaryTextColor: this.secondaryTextColor
    }) {
      SettingsGroupCard({
        surfaceColor: this.surfaceBackground,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.state.options, (
          option: BrowserTabletInterfaceModeOptionState,
          index: number
        ) => {
          SettingsOptionRow({
            title: option.title,
            desktopPresentation: this.desktopPresentation,
            rowPosition: this.resolveRowPosition(index, this.state.options.length),
            isSelected: option.mode === this.state.selectedMode,
            isEnabled: !this.saving,
            selectedIndicatorColor: this.accentColor,
            radioGroup: TABLET_INTERFACE_MODE_RADIO_GROUP,
            radioValue: option.mode,
            onAction: (): void => {
              this.updateMode(option.mode);
            }
          })
          if (index < this.state.options.length - 1) {
            SettingsGroupDivider({ dividerColor: this.dividerColor })
          }
        }, (option: BrowserTabletInterfaceModeOptionState): string => option.mode)
      }
      SettingsFooterText({
        text: this.state.footerText,
        secondaryTextColor: this.secondaryTextColor
      })
    }
  }

  private updateMode(mode: BrowserTabletInterfaceMode): void {
    if (this.saving || mode === this.state.selectedMode) {
      return;
    }
    if (this.coordinator.requiresDesktopModeConfirmation(mode)) {
      this.confirmPhoneDesktopMode(mode);
      return;
    }
    this.persistMode(mode);
  }

  private confirmPhoneDesktopMode(mode: BrowserTabletInterfaceMode): void {
    if (mode !== 'desktop') {
      return;
    }
    this.desktopModeConfirmationAccepted = false;
    this.desktopModeConfirmationDialogController.open();
  }

  private persistMode(mode: BrowserTabletInterfaceMode): void {
    const previousState = this.state;
    this.state = this.coordinator.buildStateForMode(mode);
    this.saving = true;
    this.coordinator.setMode(mode, this.buildBoundaryInput(), this.transitionConsumer)
      .then((state: BrowserTabletInterfaceModeSettingsState): void => {
        this.saving = false;
        this.state = state;
        this.onSettingsChanged?.();
      })
      .catch((_error: Error): void => {
        this.saving = false;
        this.state = previousState;
      });
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
