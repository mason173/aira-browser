import {
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID,
  ExternalNavigationAppOpenPolicy,
  SitePermissionRule
} from '../../common/models/BrowserModels';
import {
  SiteCustomizationDetailState,
  SiteCustomizationListState,
  SiteCustomizationManagementCoordinator,
  SiteCustomizationPermissionGroupState,
  SiteJavaScriptPolicy
} from './SiteCustomizationManagementCoordinator';

export interface SiteCustomizationManagementState {
  query: string;
  list: SiteCustomizationListState;
}

export interface SiteCustomizationDetailViewState {
  host: string;
  origin: string;
  title: string;
  summary: string;
  externalNavigationPolicy: ExternalNavigationAppOpenPolicy;
  hasExternalNavigationRule: boolean;
  desktopSiteSummary: string;
  hasDesktopSiteRule: boolean;
  javaScriptPolicy: SiteJavaScriptPolicy;
  hasJavaScriptRule: boolean;
  javaScriptCanApply: boolean;
  privateSiteEnabled: boolean;
  preserveCookiesOnClose: boolean;
  hasPrivateSiteRule: boolean;
  permissionGroups: SiteCustomizationPermissionGroupState[];
  hasAnyRules: boolean;
  resetEnabled: boolean;
  hasUnreadableEntry: boolean;
}

export class SiteCustomizationManagementViewModel {
  buildListState(
    coordinator: SiteCustomizationManagementCoordinator,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    query: string = ''
  ): SiteCustomizationManagementState {
    return {
      query: query,
      list: coordinator.buildListState(profileId, query)
    };
  }

  buildDetailState(detail: SiteCustomizationDetailState): SiteCustomizationDetailViewState {
    return {
      host: detail.host,
      origin: detail.origin,
      title: detail.title,
      summary: detail.summary,
      externalNavigationPolicy: detail.externalNavigationPolicy,
      hasExternalNavigationRule: detail.hasExternalNavigationRule,
      desktopSiteSummary: detail.desktopSiteSummary,
      hasDesktopSiteRule: detail.hasDesktopSiteRule,
      javaScriptPolicy: detail.javaScriptPolicy,
      hasJavaScriptRule: detail.hasJavaScriptRule,
      javaScriptCanApply: detail.javaScriptCanApply,
      privateSiteEnabled: detail.privateSiteEnabled,
      preserveCookiesOnClose: detail.preserveCookiesOnClose,
      hasPrivateSiteRule: detail.hasPrivateSiteRule,
      permissionGroups: detail.permissionGroups,
      hasAnyRules: detail.hasAnyRules,
      resetEnabled: detail.resetEnabled,
      hasUnreadableEntry: detail.hasUnreadableEntry
    };
  }

  updatePermissionRule(
    currentRule: SitePermissionRule,
    nextRule: SitePermissionRule
  ): SitePermissionRule {
    if (currentRule === nextRule) {
      return currentRule;
    }
    return nextRule;
  }
}
