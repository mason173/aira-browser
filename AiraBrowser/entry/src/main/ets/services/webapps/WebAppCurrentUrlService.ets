import { BrowserTabState } from '../../core/tabs/TabManager';
import { WebAppActiveContext } from '../../core/webapps/WebAppSessionCoordinator';
import { DesktopWebEntryRecord } from '../../data/webapps/WebAppInstallModels';
import {
  WebAppInstallRepository,
  sharedWebAppInstallRepository
} from '../../data/webapps/WebAppInstallRepository';

export interface WebAppCurrentUrlUpdateInput {
  activeContext: WebAppActiveContext | undefined;
  tab: BrowserTabState | undefined;
  url: string;
}

export class WebAppCurrentUrlService {
  private installRepository: WebAppInstallRepository;

  constructor(installRepository: WebAppInstallRepository = sharedWebAppInstallRepository) {
    this.installRepository = installRepository;
  }

  async recordInstalledWebAppUrl(input: WebAppCurrentUrlUpdateInput): Promise<boolean> {
    const targetUrl = input.url.trim();
    if (!this.shouldRecord(input, targetUrl)) {
      return false;
    }
    const activeContext = input.activeContext;
    if (activeContext === undefined) {
      return false;
    }
    try {
      const record: DesktopWebEntryRecord | undefined =
        await this.installRepository.updateCurrentUrl(activeContext.shortcutId, targetUrl);
      return record !== undefined && record.currentUrl === targetUrl;
    } catch (_error) {
      return false;
    }
  }

  resolveCommittedExitUrl(input: WebAppCurrentUrlUpdateInput): string {
    if (!this.isMatchingWebAppTab(input)) {
      return '';
    }
    const candidates: string[] = [
      input.tab?.url ?? '',
      input.tab?.lastGoodUrl ?? '',
      input.tab?.lastRestorableUrl ?? '',
      input.url
    ];
    for (let index = 0; index < candidates.length; index += 1) {
      const candidate = candidates[index].trim();
      if (this.isWebUrl(candidate)) {
        return candidate;
      }
    }
    return '';
  }

  shouldRecord(input: WebAppCurrentUrlUpdateInput, targetUrl: string = input.url.trim()): boolean {
    const activeContext = input.activeContext;
    if (activeContext === undefined) {
      return false;
    }
    if (!this.isWebUrl(targetUrl)) {
      return false;
    }
    return this.isMatchingWebAppTab(input);
  }

  private isMatchingWebAppTab(input: WebAppCurrentUrlUpdateInput): boolean {
    const activeContext = input.activeContext;
    const tab = input.tab;
    if (activeContext === undefined || tab === undefined || tab.isHome) {
      return false;
    }
    return tab.launchContext.sourceType === 'desktop_web_entry' &&
      tab.launchContext.sourceId === activeContext.shortcutId;
  }

  private isWebUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }
}
