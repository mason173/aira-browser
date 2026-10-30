import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import {
  HomeSystemShortcutTarget,
  ShortcutRecord,
  TabLaunchContext
} from '../../common/models/BrowserModels';
import { normalizeUrl } from '../../common/utils/UrlUtils';
import { TabReusePolicyService } from '../tabs/TabReusePolicyService';
import { resolveShortcutStoreHandoffId } from './ShortcutStoreHandoffCatalog';
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

/**
 * The shortcut's page belongs to an app, so opening the tile hands that app over to the
 * store instead of loading the page. It carries the app, not a URL: the store service
 * owns the deep link that reaches the store app.
 */
export interface HomeShortcutStoreOpenPlan {
  kind: 'store';
  storeId: string;
  title: string;
  source: 'home_shortcut';
}

export type HomeShortcutOpenPlan =
  HomeShortcutWebOpenPlan |
  HomeShortcutSystemOpenPlan |
  HomeShortcutStoreOpenPlan;

export class HomeShortcutOpenPolicyService {
  private tabReusePolicyService: TabReusePolicyService = new TabReusePolicyService();

  buildOpenPlan(
    shortcut: ShortcutRecord,
    activeTabId: string,
    intent: HomeShortcutOpenIntent = 'current_tab'
  ): HomeShortcutOpenPlan {
    if (shortcut.kind === 'folder') {
      throw new Error(resolveAppResourceText($r('app.string.home_shortcut_open_unavailable')));
    }
    if (resolveHomeShortcutKind(shortcut.kind) === 'system') {
      const target = resolveHomeSystemShortcutTarget(shortcut.url);
      if (target === undefined) {
        throw new Error(resolveAppResourceText($r('app.string.home_shortcut_open_unavailable')));
      }
      const systemPlan: HomeShortcutSystemOpenPlan = {
        kind: 'system',
        target: target,
        title: shortcut.title,
        source: 'home_shortcut'
      };
      return systemPlan;
    }
    const normalizedIntent = this.normalizeIntent(intent);
    // Opening the tile itself is the one action that hands an app over to the store. A
    // menu entry that names a tab still opens the page it names, because that is what
    // the user asked for there, and a store app cannot open in the background.
    if (normalizedIntent === 'current_tab') {
      const storeId = resolveShortcutStoreHandoffId(shortcut.url);
      if (storeId !== undefined) {
        const storePlan: HomeShortcutStoreOpenPlan = {
          kind: 'store',
          storeId: storeId,
          title: shortcut.title,
          source: 'home_shortcut'
        };
        return storePlan;
      }
    }
    const targetUrl = normalizeUrl(shortcut.url);
    const launchContext = this.tabReusePolicyService.buildHomeShortcutLaunchContext(shortcut.id, targetUrl);
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
