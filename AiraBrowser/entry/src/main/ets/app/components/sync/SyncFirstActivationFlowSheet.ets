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
  @Prop maxHeightVp: number = 0;
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  @State private contentHeightVp: number = 0;
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
    if (this.layoutMode === 'large_screen') {
      this.buildLargeScreenNavigation()
    } else {
      this.buildPhoneNavigation()
    }
  }

  @Builder
  private buildLargeScreenNavigation() {
    Navigation(this.navigationStack) {
      this.buildItemsSheet()
    }
    .width('100%')
    .height(this.resolveLargeScreenNavigationHeightVp())
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideNavBar(false)
    .navDestination(this.buildDestination)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private buildPhoneNavigation() {
    Navigation(this.navigationStack) {
      this.buildItemsSheet()
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideNavBar(false)
    .navDestination(this.buildDestination)
    .backgroundColor(this.storedControlBackgroundColor)
  }

  @Builder
  private buildItemsSheet() {
    SyncFirstActivationItemsSheet({
      state: $itemsState,
      isBusy: this.isBusy,
      canSubmit: this.hasSelectedItems(),
      layoutMode: this.layoutMode,
      submitLabel: '下一步',
      settingsIconBackgrounds: this.settingsIconBackgrounds,
      maxHeightVp: this.maxHeightVp,
      onToggle: (id: SyncFirstActivationItemId, enabled: boolean) => {
        this.onToggle(id, enabled);
      },
      onSubmit: () => {
        this.openGoalSelection();
      },
      onClose: this.onClose,
      onContentHeight: (heightVp: number): void => {
        this.publishContentHeight(heightVp, false);
      }
    })
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
          maxHeightVp: this.maxHeightVp,
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
          onClose: this.onClose,
          onContentHeight: (heightVp: number): void => {
            this.publishContentHeight(heightVp, true);
          }
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

  private publishContentHeight(heightVp: number, fromDestination: boolean): void {
    if (this.layoutMode !== 'large_screen' || fromDestination !== this.isShowingDestination()) {
      return;
    }
    if (!Number.isFinite(heightVp) || heightVp <= 0 || Math.abs(heightVp - this.contentHeightVp) < 1) {
      return;
    }
    this.contentHeightVp = heightVp;
  }

  private isShowingDestination(): boolean {
    return this.navigationStack.size() > 0;
  }

  private resolveLargeScreenNavigationHeightVp(): number {
    const capVp = this.maxHeightVp > 0 ? this.maxHeightVp : 4000;
    if (this.contentHeightVp <= 0) {
      return capVp;
    }
    return Math.min(this.contentHeightVp, capVp);
  }
}
