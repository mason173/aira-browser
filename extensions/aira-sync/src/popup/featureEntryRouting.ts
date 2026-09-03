export type CloudFeatureEntryView = 'login' | 'sync-method' | 'personal-server';

export function resolveCloudFeatureEntryView(options: {
  hasAiraDesktopSession: boolean;
  airaCloudAvailable: boolean;
}): CloudFeatureEntryView {
  if (options.hasAiraDesktopSession) return 'sync-method';
  return options.airaCloudAvailable ? 'login' : 'personal-server';
}
