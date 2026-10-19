import { resolveAppResourceText } from '../resources/AppResourceText';
import { ShortcutRecord } from '../../common/models/BrowserModels';
import { BrowserAppUrlOpenCoordinator } from '../browser/BrowserAppUrlOpenCoordinator';
import { BrowserShellRouteCoordinator } from '../browser/BrowserShellRouteCoordinator';
import {
  HomeShortcutOpenIntent,
  HomeShortcutOpenPlan,
  HomeShortcutOpenPolicyService
} from '../../services/shortcuts/HomeShortcutOpenPolicyService';

export interface HomeShortcutOpenOutcome {
  failureMessage: string;
}

/**
 * How a shortcut that holds a store page reaches the store app.
 *
 * The hand-over is the platform's own store deep link, which only the shell can raise.
 * Aira opens no page for it and learns nothing back, so the port owns reporting a store
 * that cannot answer.
 */
export interface HomeShortcutStoreHandoffPort {
  openStoreDetailPage: (storeId: string) => void;
}

export class HomeShortcutOpenCoordinator {
  private policyService: HomeShortcutOpenPolicyService = new HomeShortcutOpenPolicyService();
  private appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  private routeCoordinator: BrowserShellRouteCoordinator;
  private storeHandoffPort: HomeShortcutStoreHandoffPort;

  constructor(
    appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator,
    routeCoordinator: BrowserShellRouteCoordinator,
    storeHandoffPort: HomeShortcutStoreHandoffPort
  ) {
    this.appUrlOpenCoordinator = appUrlOpenCoordinator;
    this.routeCoordinator = routeCoordinator;
    this.storeHandoffPort = storeHandoffPort;
  }

  openShortcut(
    shortcut: ShortcutRecord,
    activeTabId: string,
    intent: HomeShortcutOpenIntent = 'current_tab'
  ): HomeShortcutOpenOutcome {
    try {
      const plan = this.policyService.buildOpenPlan(shortcut, activeTabId, intent);
      return this.applyOpenPlan(plan);
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      return { failureMessage: message };
    }
  }

  private applyOpenPlan(plan: HomeShortcutOpenPlan): HomeShortcutOpenOutcome {
    if (plan.kind === 'store') {
      this.storeHandoffPort.openStoreDetailPage(plan.storeId);
      return { failureMessage: '' };
    }
    if (plan.kind === 'system') {
      if (!this.routeCoordinator.openHomeSystemEntry(plan.target)) {
        return { failureMessage: resolveAppResourceText($r('app.string.home_shortcut_open_unavailable')) };
      }
      return { failureMessage: '' };
    }
    this.appUrlOpenCoordinator.openHomeShortcut(plan);
    return { failureMessage: '' };
  }
}
