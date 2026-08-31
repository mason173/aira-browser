export const SITE_CUSTOMIZATION_REFRESH_REVISION_KEY: string = 'aira.siteCustomization.refreshRevision';
export const SITE_CUSTOMIZATION_REFRESH_REASON_KEY: string = 'aira.siteCustomization.refreshReason';
export const SITE_CUSTOMIZATION_REFRESH_TARGET_ORIGIN_KEY: string = 'aira.siteCustomization.refreshTargetOrigin';
export const SITE_CUSTOMIZATION_REFRESH_PROFILE_ID_KEY: string = 'aira.siteCustomization.refreshProfileId';

export type SiteCustomizationRefreshReason =
  'general' |
  'permission' |
  'desktop_site' |
  'privacy' |
  'cookie' |
  'javascript' |
  'web_security' |
  'reset';

export interface SiteCustomizationRefreshImpact {
  reason: SiteCustomizationRefreshReason;
  targetOrigin: string;
  profileId: string;
}

export class SiteCustomizationRefreshSignal {
  bump(reason: SiteCustomizationRefreshReason = 'general', targetOrigin: string = '', profileId: string = ''): number {
    AppStorage.setOrCreate(SITE_CUSTOMIZATION_REFRESH_REASON_KEY, reason);
    AppStorage.setOrCreate(SITE_CUSTOMIZATION_REFRESH_TARGET_ORIGIN_KEY, targetOrigin.trim().toLowerCase());
    AppStorage.setOrCreate(SITE_CUSTOMIZATION_REFRESH_PROFILE_ID_KEY, profileId.trim());
    const nextRevision = (AppStorage.get<number>(SITE_CUSTOMIZATION_REFRESH_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(SITE_CUSTOMIZATION_REFRESH_REVISION_KEY, nextRevision);
    return nextRevision;
  }

  getLatestReason(): SiteCustomizationRefreshReason {
    const reason = AppStorage.get<string>(SITE_CUSTOMIZATION_REFRESH_REASON_KEY) ?? 'general';
    if (reason === 'permission' || reason === 'desktop_site' || reason === 'privacy' ||
      reason === 'cookie' || reason === 'javascript' || reason === 'web_security' || reason === 'reset') {
      return reason;
    }
    return 'general';
  }

  getLatestImpact(): SiteCustomizationRefreshImpact {
    return {
      reason: this.getLatestReason(),
      targetOrigin: AppStorage.get<string>(SITE_CUSTOMIZATION_REFRESH_TARGET_ORIGIN_KEY) ?? '',
      profileId: AppStorage.get<string>(SITE_CUSTOMIZATION_REFRESH_PROFILE_ID_KEY) ?? ''
    };
  }
}
