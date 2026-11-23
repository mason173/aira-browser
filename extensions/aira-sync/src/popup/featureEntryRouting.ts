export type CloudFeatureEntryView = 'login' | 'sync-method' | 'personal-server';

export function shouldOfferCloudSyncChoice(options: {
  airaCloudAvailable: boolean;
  loggedIn: boolean;
  selectedSource: string | null;
  loginJustCompleted: boolean;
}): boolean {
  if (!options.airaCloudAvailable || !options.loggedIn) return false;
  if (options.loginJustCompleted) return true;
  return !options.selectedSource;
}

export function resolveCloudFeatureEntryView(options: {
  hasAiraDesktopSession: boolean;
  airaCloudAvailable: boolean;
}): CloudFeatureEntryView {
  if (options.hasAiraDesktopSession) return 'sync-method';
  return options.airaCloudAvailable ? 'login' : 'personal-server';
}

export function resolveOfficialPopupOpenView(options: {
  airaCloudAvailable: boolean;
  loggedIn: boolean;
  selectedSource: string | null;
}): 'home' | 'login' {
  if (!options.airaCloudAvailable || options.loggedIn) return 'home';
  if (options.selectedSource === 'personal-server' || options.selectedSource === 'webdav') return 'home';
  return 'login';
}
