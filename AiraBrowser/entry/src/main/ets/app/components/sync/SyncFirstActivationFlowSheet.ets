import { AiraSyncProviderKind } from '../../../common/models/AiraSyncModels';
import {
  SyncFirstActivationItemId,
  SyncFirstActivationItemState,
  SyncFirstActivationItemsState
} from '../../../core/sync/SyncFirstActivationItemsCoordinator';
import { SyncExperienceGoalOption } from '../../../core/sync/SyncExperienceViewModel';
import { BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { SyncFirstActivationItemsSheet } from './SyncFirstActivationItemsSheet';
import { SyncGoalSelectionSheet } from './SyncGoalSelectionSheet';
import { SyncSetupStepLayoutMode } from './SyncSetupStepScaffold';

const SYNC_GOAL_DESTINATION_NAME: string = 'syncGoalSelection';

class SyncGoalDestinationParams {
}

@Component
export struct SyncFirstActivationFlowSheet {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.controlBackground;
  @Link itemsState: SyncFirstActivationItemsState;
  @Prop goalOptions: SyncExperienceGoalOption[] = [];
  @Prop isBusy: boolean = false;
  @Prop isPrivateSession: boolean = false;
  @Prop layoutMode: SyncSetupStepLayoutMode = 'phone';
  @Prop @Watch('resetNavigation') flowRevision: number = 0;
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  private navigationStack: NavPathStack = new NavPathStack();
  onToggle: (id: SyncFirstActivationItemId, enabled: boolean) => void =
    (_id: SyncFirstActivationItemId, _enabled: boolean) => {};
  onSelectGoal: (remoteKind: AiraSyncProviderKind) => void = (_remoteKind: AiraSyncProviderKind) => {};
  onOpenTutorial: () => void = () => {};
  onConfigureWebdav: () => void = () => {};
  onClose: () => void = () => {};

  aboutToAppear(): void {
    this.resetNavigation();
  }

  build() {
    Navigation(this.navigationStack) {
      SyncFirstActivationItemsSheet({
        state: $itemsState,
        isBusy: this.isBusy,
        canSubmit: this.hasSelectedItems(),
        layoutMode: this.layoutMode,
        submitLabel: '下一步',
        settingsIconBackgrounds: this.settingsIconBackgrounds,
        onToggle: (id: SyncFirstActivationItemId, enabled: boolean) => {
          this.onToggle(id, enabled);
        },
        onSubmit: () => {
          this.openGoalSelection();
        },
        onClose: this.onClose
      })
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideNavBar(false)
    .navDestination(this.buildDestination)
    .backgroundColor(this.layoutMode === 'large_screen' ? Color.Transparent : this.storedControlBackgroundColor)
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === SYNC_GOAL_DESTINATION_NAME) {
      NavDestination() {
        SyncGoalSelectionSheet({
          options: this.goalOptions,
          isBusy: this.isBusy,
          isPrivateSession: this.isPrivateSession,
          showBackButton: true,
          layoutMode: this.layoutMode,
          radioGroup: 'sync-first-activation-goal',
          onBack: () => {
            this.navigationStack.pop();
          },
          onSelect: (remoteKind: AiraSyncProviderKind) => {
            this.onSelectGoal(remoteKind);
          },
          onOpenTutorial: () => {
            this.onOpenTutorial();
          },
          onConfigureWebdav: () => {
            this.onConfigureWebdav();
          },
          onClose: this.onClose
        })
      }
      .hideTitleBar(true)
      .onBackPressed(() => {
        this.navigationStack.pop();
        return true;
      })
    }
  }

  private openGoalSelection(): void {
    if (this.isBusy || !this.hasSelectedItems()) {
      return;
    }
    this.navigationStack.pushPathByName(SYNC_GOAL_DESTINATION_NAME, new SyncGoalDestinationParams());
  }

  private resetNavigation(): void {
    while (this.navigationStack.pop(false) !== undefined) {
    }
  }

  private hasSelectedItems(): boolean {
    return this.itemsState.items.some((item: SyncFirstActivationItemState): boolean => item.enabled);
  }
}
