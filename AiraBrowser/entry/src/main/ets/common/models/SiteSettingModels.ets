import { BrowserProfileId } from './BrowserModels';

/** A single exact HTTP/HTTPS origin used by persisted site settings. */
export interface SiteSettingTarget {
  scheme: 'http' | 'https';
  host: string;
  effectivePort: number;
  canonicalOrigin: string;
  displayOrigin: string;
  displayHost: string;
}

/** Host-only rules such as content-filter exceptions keep their own target type. */
export interface HostRuleTarget {
  host: string;
}

export interface SavedSiteSettingOverrides {
  userAgentIdentityId?: string;
  javaScriptEnabled?: boolean;
  clearOnClose?: boolean;
  preserveCookiesOnClose?: boolean;
  externalNavigationPolicy?: string;
  camera?: string;
  microphone?: string;
  location?: string;
  sensor?: string;
  clipboard?: string;
}

export const SAVED_SITE_SETTING_OVERRIDES_SCHEMA_VERSION: number = 1;

export interface SavedSiteSettingOverridesDocument {
  schemaVersion: number;
  overrides: SavedSiteSettingOverrides;
}

export interface SavedSiteSettingEntry {
  profileId: BrowserProfileId;
  target: SiteSettingTarget;
  revision: number;
  overrides: SavedSiteSettingOverrides;
  updatedAt: number;
}
