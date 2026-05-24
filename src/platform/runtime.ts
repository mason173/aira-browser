type ChromeApi = typeof chrome;

export function getChromeApi(): ChromeApi | undefined {
  return (globalThis as { chrome?: ChromeApi }).chrome;
}

export function getExtensionRuntime(): ChromeApi['runtime'] | undefined {
  return getChromeApi()?.runtime;
}

export function getExtensionManifest(): chrome.runtime.Manifest | undefined {
  return getExtensionRuntime()?.getManifest?.();
}

export function isExtensionRuntime(): boolean {
  return Boolean(getExtensionRuntime()?.id);
}

export function getPermissionsApi(): ChromeApi['permissions'] | undefined {
  return getChromeApi()?.permissions;
}

export function getTabsApi(): ChromeApi['tabs'] | undefined {
  return getChromeApi()?.tabs;
}

export function getWindowsApi(): ChromeApi['windows'] | undefined {
  return getChromeApi()?.windows;
}

export function getSearchApi(): ChromeApi['search'] | undefined {
  return getChromeApi()?.search;
}

export function getBookmarksApi(): ChromeApi['bookmarks'] | undefined {
  return getChromeApi()?.bookmarks;
}

export function getHistoryApi(): ChromeApi['history'] | undefined {
  return getChromeApi()?.history;
}
