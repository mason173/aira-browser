import { BrowserPageReloadReason } from '../browser/BrowserRuntimeActionReason';
import { SiteCustomizationRefreshReason } from './SiteCustomizationRefreshSignal';
import { SiteIdentityService } from '../../services/web/SiteIdentityService';

export interface SiteCustomizationRuntimeRefreshRequest {
  reason: SiteCustomizationRefreshReason;
  pageUrl: string;
  webPageVisible: boolean;
  controllerAttached: boolean;
  hasActiveController: boolean;
  targetOrigin?: string;
  targetProfileId?: string;
  currentProfileId?: string;
}

export interface SiteCustomizationRuntimeRefreshPlan {
  shouldRefreshCurrentSitePermissions: boolean;
  shouldApplyUserAgent: boolean;
  shouldReloadActivePage: boolean;
  reloadReason: BrowserPageReloadReason;
}

export class SiteCustomizationRuntimeRefreshCoordinator {
  private readonly siteIdentityService: SiteIdentityService = new SiteIdentityService();

  buildRefreshPlan(request: SiteCustomizationRuntimeRefreshRequest): SiteCustomizationRuntimeRefreshPlan {
    const targetMatches = this.matchesTarget(request);
    const hasPage = request.pageUrl.trim().length > 0 && request.webPageVisible && targetMatches;
    const hasController = request.controllerAttached && request.hasActiveController;
    const shouldReload = this.shouldReloadActivePage(request.reason, hasPage, hasController);
    const shouldApplyUserAgent = this.shouldApplyUserAgent(request.reason, hasPage, hasController);
    const shouldRefreshCurrentSitePermissions = targetMatches && (request.reason === 'permission' ||
      request.reason === 'reset' ||
      request.reason === 'general');
    return {
      shouldRefreshCurrentSitePermissions: shouldRefreshCurrentSitePermissions,
      shouldApplyUserAgent: shouldApplyUserAgent,
      shouldReloadActivePage: shouldReload,
      reloadReason: this.resolveReloadReason(request.reason)
    };
  }

  private matchesTarget(request: SiteCustomizationRuntimeRefreshRequest): boolean {
    const targetOrigin = request.targetOrigin?.trim() ?? '';
    const targetProfileId = request.targetProfileId?.trim() ?? '';
    const currentProfileId = request.currentProfileId?.trim() ?? '';
    if (targetProfileId.length > 0 && currentProfileId.length > 0 && targetProfileId !== currentProfileId) {
      return false;
    }
    if (targetOrigin.length <= 0) {
      return true;
    }
    const target = this.siteIdentityService.resolveSiteSettingTarget(targetOrigin);
    return target !== undefined && this.siteIdentityService.matchesSiteSettingTarget(request.pageUrl, target);
  }

  private shouldApplyUserAgent(
    reason: SiteCustomizationRefreshReason,
    hasPage: boolean,
    hasController: boolean
  ): boolean {
    if (!hasPage || !hasController) {
      return false;
    }
    return reason === 'desktop_site' || reason === 'reset' || reason === 'general';
  }

  private shouldReloadActivePage(
    reason: SiteCustomizationRefreshReason,
    hasPage: boolean,
    hasController: boolean
  ): boolean {
    if (!hasPage || !hasController) {
      return false;
    }
    return reason === 'desktop_site' || reason === 'javascript' || reason === 'reset' || reason === 'general';
  }

  private resolveReloadReason(reason: SiteCustomizationRefreshReason): BrowserPageReloadReason {
    if (reason === 'permission') {
      return 'site_permission_apply';
    }
    return 'user_manual_reload';
  }

}
