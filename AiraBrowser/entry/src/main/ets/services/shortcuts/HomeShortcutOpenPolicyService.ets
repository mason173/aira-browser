import {
  HomeSystemShortcutTarget,
  ShortcutRecord,
  TabLaunchContext
} from '../../common/models/BrowserModels';
import { normalizeUrl } from '../../common/utils/UrlUtils';
import { TabReusePolicyService } from '../tabs/TabReusePolicyService';
import {
  resolveHomeShortcutKind,
  resolveHomeSystemShortcutTarget
} from './HomeSystemShortcutCatalog';

export type HomeShortcutOpenIntent = 'current_tab' | 'new_tab' | 'background_tab';

export interface HomeShortcutWebOpenPlan {
  kind: 'web';
  url: string;
  title: string;
  intent: HomeShortcutOpenIntent;
  source: 'home_shortcut';
  openerTabId: string;
  launchContext: TabLaunchContext;
}

export interface HomeShortcutSystemOpenPlan {
  kind: 'system';
  target: HomeSystemShortcutTarget;
  title: string;
  source: 'home_shortcut';
}

export type HomeShortcutOpenPlan = HomeShortcutWebOpenPlan | HomeShortcutSystemOpenPlan;

export class HomeShortcutOpenPolicyService {
  private tabReusePolicyService: TabReusePolicyService = new TabReusePolicyService();

  buildOpenPlan(
    shortcut: ShortcutRecord,
    activeTabId: string,
    intent: HomeShortcutOpenIntent = 'current_tab'
  ): HomeShortcutOpenPlan {
    if (resolveHomeShortcutKind(shortcut.kind) === 'system') {
      const target = resolveHomeSystemShortcutTarget(shortcut.url);
      if (target === undefined) {
        throw new Error('这个系统快捷方式暂不可用。');
      }
      const systemPlan: HomeShortcutSystemOpenPlan = {
        kind: 'system',
        target: target,
        title: shortcut.title,
        source: 'home_shortcut'
      };
      return systemPlan;
    }
    const targetUrl = normalizeUrl(shortcut.url);
    const launchContext = this.tabReusePolicyService.buildHomeShortcutLaunchContext(shortcut.id, targetUrl);
    const normalizedIntent = this.normalizeIntent(intent);
    const webPlan: HomeShortcutWebOpenPlan = {
      kind: 'web',
      url: targetUrl,
      title: shortcut.title,
      intent: normalizedIntent,
      source: 'home_shortcut',
      openerTabId: activeTabId,
      launchContext: launchContext
    };
    return webPlan;
  }

  private normalizeIntent(intent: HomeShortcutOpenIntent): HomeShortcutOpenIntent {
    if (intent === 'new_tab' || intent === 'background_tab') {
      return intent;
    }
    return 'current_tab';
  }

}
