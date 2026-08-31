import { TabRuntimeState } from '../../common/models/BrowserModels';

export interface BrowserRuntimePersistedStateContext {
  runtimeState?: TabRuntimeState;
  isHome: boolean;
  isActive: boolean;
  webStatePath?: string;
}

export class BrowserRuntimeStateTransitionTable {
  private activeProtectedStates: TabRuntimeState[] = [
    'error',
    'crashed',
    'restoring',
    'loading',
    'suspended',
    'cold',
    'discarded'
  ];
  private backgroundProtectedStates: TabRuntimeState[] = [
    'error',
    'crashed',
    'restoring',
    'cold',
    'discarded',
    'loading'
  ];
  private restoreRequiredAttachStates: TabRuntimeState[] = [
    'cold',
    'discarded',
    'crashed',
    'loading',
    'restoring'
  ];

  resolveForegroundState(state: TabRuntimeState, isHome: boolean = false): TabRuntimeState {
    if (isHome) {
      return 'active';
    }
    if (this.containsState(this.activeProtectedStates, state)) {
      return state;
    }
    return 'active';
  }

  resolveBackgroundState(state: TabRuntimeState, isHome: boolean = false): TabRuntimeState {
    if (isHome) {
      return 'background';
    }
    if (this.containsState(this.backgroundProtectedStates, state)) {
      return state;
    }
    return 'background-hot';
  }

  normalizePersistedState(context: BrowserRuntimePersistedStateContext): TabRuntimeState {
    const webStatePath = context.webStatePath ?? '';
    if (context.runtimeState !== undefined) {
      if (context.isActive && !context.isHome && context.runtimeState !== 'error') {
        return webStatePath.length > 0 ? 'restoring' : 'loading';
      }
      if (!context.isActive && context.isHome && context.runtimeState === 'active') {
        return 'background';
      }
      if (!context.isActive && !context.isHome && this.shouldSuspendPersistedBackgroundState(context.runtimeState)) {
        return 'suspended';
      }
      return context.runtimeState;
    }
    if (context.isActive) {
      return context.isHome ? 'active' : (webStatePath.length > 0 ? 'restoring' : 'loading');
    }
    return context.isHome ? 'background' : 'suspended';
  }

  shouldRestoreAfterControllerAttach(state: TabRuntimeState): boolean {
    return this.containsState(this.restoreRequiredAttachStates, state);
  }

  private shouldSuspendPersistedBackgroundState(state: TabRuntimeState): boolean {
    return state === 'active' || state === 'loading' || state === 'restoring';
  }

  private containsState(states: TabRuntimeState[], state: TabRuntimeState): boolean {
    return states.indexOf(state) >= 0;
  }
}
