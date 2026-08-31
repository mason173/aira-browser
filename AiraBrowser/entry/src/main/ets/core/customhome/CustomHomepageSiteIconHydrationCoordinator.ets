import { SiteIconService } from '../../services/siteicons/SiteIconService';
import { CustomHomepageChoiceViewState } from './CustomHomepageSettingsViewModel';

export interface CustomHomepageSiteIconHydrationResult {
  choiceId: string;
  siteIconUri: string;
}

interface CustomHomepageSiteIconHydrationOptions {
  cacheLimit: number;
  networkPrefetchLimit: number;
  shouldContinue?: () => boolean;
  onResolved?: (result: CustomHomepageSiteIconHydrationResult) => void;
}

export class CustomHomepageSiteIconHydrationCoordinator {
  private readonly siteIconService: SiteIconService;

  constructor(siteIconService: SiteIconService = new SiteIconService()) {
    this.siteIconService = siteIconService;
  }

  async hydrateChoices(
    choices: CustomHomepageChoiceViewState[],
    options: CustomHomepageSiteIconHydrationOptions
  ): Promise<void> {
    const targets = choices
      .filter((choice: CustomHomepageChoiceViewState): boolean => choice.isRemoteUrl)
      .slice(0, Math.max(0, options.cacheLimit));
    const networkPrefetchLimit = Math.max(0, options.networkPrefetchLimit);
    for (let index = 0; index < targets.length; index += 1) {
      if (options.shouldContinue !== undefined && !options.shouldContinue()) {
        return;
      }
      const result = await this.resolveChoice(targets[index], index < networkPrefetchLimit);
      if (result !== undefined) {
        options.onResolved?.(result);
      }
    }
  }

  async resolveChoice(
    choice: CustomHomepageChoiceViewState,
    allowNetwork: boolean
  ): Promise<CustomHomepageSiteIconHydrationResult | undefined> {
    if (!choice.isRemoteUrl || choice.url.trim().length <= 0) {
      return undefined;
    }
    try {
      const cachedIconPath = this.siteIconService.peekUri(choice.url);
      if (cachedIconPath.length > 0) {
        return this.buildResult(choice.id, cachedIconPath);
      }
      const iconPath = await this.siteIconService.readCachedUri(choice.url);
      if (iconPath.length > 0) {
        return this.buildResult(choice.id, iconPath);
      }
      if (!allowNetwork) {
        return undefined;
      }
      const remoteIcon = await this.siteIconService.resolve(choice.url, {
        networkPolicy: 'remoteAllowed',
        allowRemoteFallback: true
      });
      const remoteIconPath = remoteIcon?.uri ?? '';
      return remoteIconPath.length > 0 ? this.buildResult(choice.id, remoteIconPath) : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private buildResult(choiceId: string, siteIconUri: string): CustomHomepageSiteIconHydrationResult | undefined {
    const normalizedSiteIconUri = siteIconUri.trim();
    if (choiceId.length <= 0 || normalizedSiteIconUri.length <= 0) {
      return undefined;
    }
    return {
      choiceId: choiceId,
      siteIconUri: normalizedSiteIconUri
    };
  }
}
