import { AiraSyncProviderKind } from '../../../common/models/AiraSyncModels';
import {
  SyncFirstActivationItemId,
  SyncFirstActivationItemsState
} from '../../../core/sync/SyncFirstActivationItemsCoordinator';
import { SyncExperienceGoalOption } from '../../../core/sync/SyncExperienceViewModel';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { SyncFirstActivationFlowSheet } from './SyncFirstActivationFlowSheet';
import { SyncGoalSelectionSheet } from './SyncGoalSelectionSheet';
import { CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

export type SyncExperienceSelectionKind = 'none' | 'setup' | 'goal';

@CustomDialog
export struct SyncExperienceSelectionDialog {
  controller?: CustomDialogController;
  @Link activeKind: SyncExperienceSelectionKind;
  @Link itemsState: SyncFirstActivationItemsState;
  @Prop goalOptions: SyncExperienceGoalOption[] = [];
  @Prop isBusy: boolean = false;
  @Prop isPrivateSession: boolean = false;
  @Prop flowRevision: number = 0;
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  onToggle: (id: SyncFirstActivationItemId, enabled: boolean) => void =
    (_id: SyncFirstActivationItemId, _enabled: boolean) => {};
  onSelectGoal: (remoteKind: AiraSyncProviderKind) => void = (_remoteKind: AiraSyncProviderKind) => {};
  onOpenTutorial: () => void = () => {};
  onConfigureWebdav: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      if (this.activeKind === 'setup') {
        SyncFirstActivationFlowSheet({
          itemsState: $itemsState,
          goalOptions: this.goalOptions,
          isBusy: this.isBusy,
          isPrivateSession: this.isPrivateSession,
          layoutMode: 'large_screen',
          flowRevision: this.flowRevision,
          settingsIconBackgrounds: this.settingsIconBackgrounds,
          onToggle: this.onToggle,
          onSelectGoal: this.onSelectGoal,
          onOpenTutorial: this.onOpenTutorial,
          onConfigureWebdav: this.onConfigureWebdav,
          onClose: this.onClose
        })
      } else if (this.activeKind === 'goal') {
        SyncGoalSelectionSheet({
          options: this.goalOptions,
          isBusy: this.isBusy,
          isPrivateSession: this.isPrivateSession,
          layoutMode: 'large_screen',
          radioGroup: 'sync-active-goal',
          onSelect: this.onSelectGoal,
          onOpenTutorial: this.onOpenTutorial,
          onConfigureWebdav: this.onConfigureWebdav,
          onClose: this.onClose
        })
      }
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER)
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      this.onClose();
    })
  }
}
