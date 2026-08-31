import {
  SettingsDestinationNavigationRouter,
  SettingsRoutedDestination
} from '../../core/settings/SettingsDestinationNavigationOwner';
import { BrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from './SettingsNavigationCoordinator';

export class SettingsDestinationNavigationRouterAdapter implements SettingsDestinationNavigationRouter {
  private navigationCoordinator: SettingsNavigationCoordinator;

  constructor(navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator()) {
    this.navigationCoordinator = navigationCoordinator;
  }

  openRoutedDestination(
    target: SettingsRoutedDestination,
    boundary: BrowserBoundaryRouteState
  ): Promise<boolean> {
    return this.navigationCoordinator.openRoutedDestinationCommitted(target, boundary)
      .catch((_error: Error): boolean => false);
  }

  exitSettings(): Promise<boolean> {
    try {
      this.navigationCoordinator.back();
      return Promise.resolve(true);
    } catch (_error) {
      return Promise.resolve(false);
    }
  }
}
