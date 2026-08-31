import { AppProxyProfileListItemState } from './AppProxySettingsViewModel';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import {
  AppProxySettingsCoordinator,
  AppProxySettingsCoordinatorState
} from './AppProxySettingsCoordinator';

export interface AppProxyQuickSheetState {
  globalEnabled: boolean;
  hasProfiles: boolean;
  profiles: AppProxyProfileListItemState[];
  switchingGlobalEnabled: boolean;
  switchingProfileId: string;
  toolbarActive: boolean;
}

export interface AppProxyQuickSheetAction {
  type: 'dismiss' | 'toggle_global' | 'select_profile' | 'open_settings';
  enabled?: boolean;
  profileId?: string;
}

export interface AppProxyQuickSheetShell {
  publishState: (state: AppProxyQuickSheetState) => void;
  setSurfaceVisible: (visible: boolean) => void;
  showMessage: (message: string) => void;
  openSettings: () => void;
  refreshConsumers?: () => void;
}

export class AppProxyQuickSheetCoordinator {
  private readonly appProxySettingsCoordinator: AppProxySettingsCoordinator;
  private readonly shell: AppProxyQuickSheetShell;
  private state: AppProxyQuickSheetState;
  private boundaryInput?: BrowserDataBoundaryInput;
  private surfaceGeneration: number = 0;
  private surfaceOpen: boolean = false;

  constructor(
    appProxySettingsCoordinator: AppProxySettingsCoordinator,
    shell: AppProxyQuickSheetShell
  ) {
    this.appProxySettingsCoordinator = appProxySettingsCoordinator;
    this.shell = shell;
    this.state = this.buildStateFromCoordinatorState(this.appProxySettingsCoordinator.buildState());
  }

  getSnapshot(): AppProxyQuickSheetState {
    return this.state;
  }

  refresh(): void {
    const coordinatorState = this.appProxySettingsCoordinator.buildState();
    const toolbarActive = this.state.switchingGlobalEnabled
      ? this.state.toolbarActive
      : coordinatorState.pageState.globalEnabled;
    this.publishState(this.buildStateFromCoordinatorState(
      coordinatorState,
      this.state.switchingGlobalEnabled,
      this.state.switchingProfileId,
      toolbarActive
    ));
  }

  open(boundaryInput: BrowserDataBoundaryInput): void {
    this.surfaceGeneration += 1;
    this.surfaceOpen = true;
    this.boundaryInput = boundaryInput;
    this.publishState(this.buildStateFromCoordinatorState(this.appProxySettingsCoordinator.buildState()));
    this.shell.setSurfaceVisible(true);
  }

  handleAction(action: AppProxyQuickSheetAction): void {
    if (action.type === 'dismiss') {
      this.dismiss();
      return;
    }
    if (action.type === 'toggle_global') {
      if (action.enabled !== undefined) {
        void this.setGlobalEnabled(action.enabled);
      }
      return;
    }
    if (action.type === 'select_profile') {
      if (action.profileId !== undefined) {
        void this.selectProfile(action.profileId);
      }
      return;
    }
    this.openSettings();
  }

  dismiss(): void {
    this.surfaceOpen = false;
    this.boundaryInput = undefined;
    this.surfaceGeneration += 1;
    this.publishState(this.copyBusyState(false, ''));
    this.shell.setSurfaceVisible(false);
  }

  handleSurfaceDismissed(): void {
    if (!this.surfaceOpen && !this.state.switchingGlobalEnabled && this.state.switchingProfileId.length <= 0) {
      return;
    }
    this.surfaceOpen = false;
    this.boundaryInput = undefined;
    this.surfaceGeneration += 1;
    this.publishState(this.copyBusyState(false, ''));
  }

  async setGlobalEnabled(enabled: boolean): Promise<void> {
    const boundaryInput = this.boundaryInput;
    if (this.state.switchingGlobalEnabled || boundaryInput === undefined) {
      return;
    }
    const runGeneration = this.surfaceGeneration;
    const fallbackToolbarActive = this.state.toolbarActive;
    this.publishState({
      globalEnabled: this.state.globalEnabled,
      hasProfiles: this.state.hasProfiles,
      profiles: this.state.profiles,
      switchingGlobalEnabled: true,
      switchingProfileId: this.state.switchingProfileId,
      toolbarActive: enabled
    });
    try {
      const result = await this.appProxySettingsCoordinator.setGlobalEnabled(enabled, boundaryInput);
      this.applyMutationResult(result.state, result.message, result.success, fallbackToolbarActive, runGeneration);
    } finally {
      if (runGeneration === this.surfaceGeneration) {
        this.publishState(this.copyBusyState(false, this.state.switchingProfileId));
      }
    }
  }

  async selectProfile(profileId: string): Promise<void> {
    const boundaryInput = this.boundaryInput;
    if (this.state.switchingProfileId.length > 0 || boundaryInput === undefined) {
      return;
    }
    const runGeneration = this.surfaceGeneration;
    const fallbackToolbarActive = this.state.toolbarActive;
    this.publishState(this.copyBusyState(this.state.switchingGlobalEnabled, profileId));
    try {
      const result = await this.appProxySettingsCoordinator.selectProfile(profileId, boundaryInput);
      this.applyMutationResult(result.state, result.message, result.success, fallbackToolbarActive, runGeneration);
    } finally {
      if (runGeneration === this.surfaceGeneration) {
        this.publishState(this.copyBusyState(this.state.switchingGlobalEnabled, ''));
      }
    }
  }

  openSettings(): void {
    this.dismiss();
    this.shell.openSettings();
  }

  private applyMutationResult(
    coordinatorState: AppProxySettingsCoordinatorState,
    message: string,
    success: boolean,
    fallbackToolbarActive: boolean,
    runGeneration: number
  ): void {
    if (runGeneration !== this.surfaceGeneration) {
      this.refresh();
      this.shell.refreshConsumers?.();
      if (message.length > 0) {
        this.shell.showMessage(message);
      }
      return;
    }
    const toolbarActive = success ? coordinatorState.pageState.globalEnabled : fallbackToolbarActive;
    this.publishState(this.buildStateFromCoordinatorState(
      coordinatorState,
      this.state.switchingGlobalEnabled,
      this.state.switchingProfileId,
      toolbarActive
    ));
    this.shell.refreshConsumers?.();
    if (message.length > 0) {
      this.shell.showMessage(message);
    }
  }

  private buildStateFromCoordinatorState(
    state: AppProxySettingsCoordinatorState,
    switchingGlobalEnabled: boolean = false,
    switchingProfileId: string = '',
    toolbarActive: boolean = state.pageState.globalEnabled
  ): AppProxyQuickSheetState {
    return {
      globalEnabled: state.pageState.globalEnabled,
      hasProfiles: state.pageState.hasProfiles,
      profiles: state.pageState.profileItems,
      switchingGlobalEnabled: switchingGlobalEnabled,
      switchingProfileId: switchingProfileId,
      toolbarActive: toolbarActive
    };
  }

  private copyBusyState(switchingGlobalEnabled: boolean, switchingProfileId: string): AppProxyQuickSheetState {
    return {
      globalEnabled: this.state.globalEnabled,
      hasProfiles: this.state.hasProfiles,
      profiles: this.state.profiles,
      switchingGlobalEnabled: switchingGlobalEnabled,
      switchingProfileId: switchingProfileId,
      toolbarActive: this.state.toolbarActive
    };
  }

  private publishState(state: AppProxyQuickSheetState): void {
    this.state = state;
    this.shell.publishState(state);
  }
}
