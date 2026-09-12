import { hilog } from '@kit.PerformanceAnalysisKit';
import { SiteIconUriCacheEntry } from '../../common/models/SiteIconModels';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserTabsOverviewSectionPolicy } from '../browser/tabsOverview/BrowserTabsOverviewSectionPolicy';
import { SiteIconService } from '../../services/siteicons/SiteIconService';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'SiteIconPrewarm';

/**
 * Loads the restored tabs' cached favicons into the process-wide site-icon
 * memory cache during startup.
 *
 * The tabs overview builds its card grid and resolves each card's identity icon
 * from the memory cache as it paints. On a cold start that cache is empty, so
 * the first grid build carries no favicon and the disk read only lands after the
 * cards are already on screen. Home shortcuts avoid that race by warming their
 * icons with `resolveCachedUris`; restored tabs had no equivalent, which is why
 * the home favourites kept their icons while the tab cards fell back to their
 * letter badge until the app had been used for a while.
 */
export class RestoredTabSiteIconPrewarmCoordinator {
  private siteIconService: SiteIconService;
  private sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();
  private lastWarmedUrls: string = '';

  constructor(siteIconService: SiteIconService = new SiteIconService()) {
    this.siteIconService = siteIconService;
  }

  prewarmRestoredTabs(tabs: BrowserTabState[]): void {
    const urls = this.collectRestorableUrls(tabs);
    if (urls.length <= 0) {
      return;
    }
    const warmedKey = urls.join('|');
    if (warmedKey === this.lastWarmedUrls) {
      return;
    }
    this.lastWarmedUrls = warmedKey;
    this.siteIconService.resolveCachedUris(urls)
      .then((entries: SiteIconUriCacheEntry[]): void => {
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'restored tab icons warmed tabs=%{public}d resolved=%{public}d',
          urls.length, entries.length);
      })
      .catch((_error: Error) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'restored tab icon warmup failed tabs=%{public}d', urls.length);
      });
  }

  private collectRestorableUrls(tabs: BrowserTabState[]): string[] {
    const urls: string[] = [];
    for (let index = 0; index < tabs.length; index += 1) {
      const tab = tabs[index];
      if (tab.isHome || this.sectionPolicy.isPrivateTab(tab)) {
        continue;
      }
      const url = this.resolveTabUrl(tab);
      if (url.length > 0 && urls.indexOf(url) < 0) {
        urls.push(url);
      }
    }
    return urls;
  }

  private resolveTabUrl(tab: BrowserTabState): string {
    const candidates: string[] = [tab.url, tab.pendingUrl, tab.lastRestorableUrl, tab.lastGoodUrl];
    for (let index = 0; index < candidates.length; index += 1) {
      const normalized = candidates[index].trim();
      if (normalized.length > 0) {
        return normalized;
      }
    }
    return '';
  }
}
