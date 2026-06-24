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

export function getBookmarksApi(): ChromeApi['bookmarks'] | undefined {
  return getChromeApi()?.bookmarks;
}
