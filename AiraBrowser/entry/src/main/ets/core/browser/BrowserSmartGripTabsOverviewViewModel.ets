import { BrowserSmartGripState } from './BrowserSmartGripCoordinator';

export class BrowserSmartGripTabsOverviewViewModel {
  shouldMirrorSideActionsForSmartGrip(state: BrowserSmartGripState): boolean {
    return state.enabled && state.hand === 'left';
  }
}
