import { display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AiraSyncProviderKind } from '../../../common/models/AiraSyncModels';
import {
  SyncFirstActivationItemId,
  SyncFirstActivationItemsState
} from '../../../core/sync/SyncFirstActivationItemsCoordinator';
import { SyncExperienceGoalOption } from '../../../core/sync/SyncExperienceViewModel';
import {
  DESKTOP_DIALOG_EDGE_VP,
  DESKTOP_DIALOG_HEIGHT_CAP_VP
} from '../../../core/browser/BrowserDialogPresentationTokens';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { SyncFirstActivationFlowSheet } from './SyncFirstActivationFlowSheet';
import { SyncGoalSelectionSheet } from './SyncGoalSelectionSheet';
import { CENTERED_DIALOG_SYSTEM_HUG_DEFINITE_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

export type SyncExperienceSelectionKind = 'none' | 'setup' | 'goal';

class SyncSelectionDialogWindowHeightSource {
  private mainWindow?: window.Window = undefined;
  private densityPixels: number = 1;
  private bindGeneration: number = 0;
  onHeightVp: (heightVp: number) => void = (_heightVp: number): void => {};
  private readonly windowSizeChangeCallback: (size: window.Size) => void = (_size: window.Size): void => {
    this.publish();
  };

  bind(hostContext: common.UIAbilityContext): void {
    const generation = this.bindGeneration + 1;
    this.bindGeneration = generation;
    this.detachWindow();
    try {
      const densityPixels = display.getDefaultDisplaySync().densityPixels;
      if (Number.isFinite(densityPixels) && densityPixels > 0) {
        this.densityPixels = densityPixels;
      }
    } catch (_error) {
    }
    window.getLastWindow(hostContext)
      .then((mainWindow: window.Window) => {
        if (generation !== this.bindGeneration) {
          return;
        }
        this.mainWindow = mainWindow;
        this.publish();
        try {
          mainWindow.on('windowSizeChange', this.windowSizeChangeCallback);
        } catch (_error) {
        }
      })
      .catch(() => {
      });
  }

  unbind(): void {
    this.bindGeneration += 1;
    this.detachWindow();
  }

  private detachWindow(): void {
    if (this.mainWindow === undefined) {
      return;
    }
    try {
      this.mainWindow.off('windowSizeChange', this.windowSizeChangeCallback);
    } catch (_error) {
    }
    this.mainWindow = undefined;
  }

  private publish(): void {
    const mainWindow = this.mainWindow;
    if (mainWindow === undefined) {
      return;
    }
    const heightPx = mainWindow.getWindowProperties().windowRect.height;
    if (!Number.isFinite(heightPx) || heightPx <= 0 || this.densityPixels <= 0) {
      return;
    }
    this.onHeightVp(heightPx / this.densityPixels);
  }
}

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
  @State private windowHeightVp: number = 0;
  private readonly windowHeightSource: SyncSelectionDialogWindowHeightSource =
    new SyncSelectionDialogWindowHeightSource();

  aboutToAppear(): void {
    this.windowHeightSource.onHeightVp = (heightVp: number): void => {
      if (!Number.isFinite(heightVp) || heightVp <= 0 || Math.abs(heightVp - this.windowHeightVp) < 1) {
        return;
      }
      this.windowHeightVp = heightVp;
    };
    this.windowHeightSource.bind(getContext(this) as common.UIAbilityContext);
  }

  aboutToDisappear(): void {
    this.windowHeightSource.unbind();
  }

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
          maxHeightVp: this.resolveDialogMaxHeightVp(),
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
          maxHeightVp: this.resolveDialogMaxHeightVp(),
          onSelect: this.onSelectGoal,
          onOpenTutorial: this.onOpenTutorial,
          onConfigureWebdav: this.onConfigureWebdav,
          onClose: this.onClose
        })
      }
    }
    .width('100%')
    .attributeModifier(CENTERED_DIALOG_SYSTEM_HUG_DEFINITE_SURFACE_MODIFIER)
    .constraintSize({ maxHeight: this.resolveDialogMaxHeightVp() })
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      this.onClose();
    })
  }

  private resolveDialogMaxHeightVp(): number {
    const usableHeightVp = this.windowHeightVp - DESKTOP_DIALOG_EDGE_VP * 2;
    if (!Number.isFinite(usableHeightVp) || usableHeightVp <= 0) {
      return DESKTOP_DIALOG_HEIGHT_CAP_VP;
    }
    return Math.min(DESKTOP_DIALOG_HEIGHT_CAP_VP, usableHeightVp);
  }
}
