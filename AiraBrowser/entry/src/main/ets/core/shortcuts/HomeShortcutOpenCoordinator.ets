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

export class HomeShortcutOpenCoordinator {
  private policyService: HomeShortcutOpenPolicyService = new HomeShortcutOpenPolicyService();
  private appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  private routeCoordinator: BrowserShellRouteCoordinator;

  constructor(
    appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator,
    routeCoordinator: BrowserShellRouteCoordinator
  ) {
    this.appUrlOpenCoordinator = appUrlOpenCoordinator;
    this.routeCoordinator = routeCoordinator;
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
    if (plan.kind === 'system') {
      if (!this.routeCoordinator.openHomeSystemEntry(plan.target)) {
        return { failureMessage: '这个系统快捷方式暂不可用。' };
      }
      return { failureMessage: '' };
    }
    this.appUrlOpenCoordinator.openHomeShortcut(plan);
    return { failureMessage: '' };
  }
}
