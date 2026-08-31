export interface BrowserWebSecuritySettings {
  httpsFirstEnabled: boolean;
  safeBrowsingEnabled: boolean;
  javaScriptEnabled: boolean;
}

export interface BrowserWebRuntimeSecurityPolicy extends BrowserWebSecuritySettings {
  javaScriptUsesSiteOverride: boolean;
}

export const DEFAULT_BROWSER_WEB_SECURITY_SETTINGS: BrowserWebSecuritySettings = {
  httpsFirstEnabled: true,
  safeBrowsingEnabled: false,
  javaScriptEnabled: true
};

export function copyBrowserWebSecuritySettings(
  settings: BrowserWebSecuritySettings
): BrowserWebSecuritySettings {
  return {
    httpsFirstEnabled: settings.httpsFirstEnabled,
    safeBrowsingEnabled: settings.safeBrowsingEnabled,
    javaScriptEnabled: settings.javaScriptEnabled
  };
}

export function normalizeBrowserWebSecuritySettings(
  settings: BrowserWebSecuritySettings | undefined
): BrowserWebSecuritySettings {
  return {
    httpsFirstEnabled: typeof settings?.httpsFirstEnabled === 'boolean'
      ? settings.httpsFirstEnabled
      : DEFAULT_BROWSER_WEB_SECURITY_SETTINGS.httpsFirstEnabled,
    safeBrowsingEnabled: typeof settings?.safeBrowsingEnabled === 'boolean'
      ? settings.safeBrowsingEnabled
      : DEFAULT_BROWSER_WEB_SECURITY_SETTINGS.safeBrowsingEnabled,
    javaScriptEnabled: typeof settings?.javaScriptEnabled === 'boolean'
      ? settings.javaScriptEnabled
      : DEFAULT_BROWSER_WEB_SECURITY_SETTINGS.javaScriptEnabled
  };
}
