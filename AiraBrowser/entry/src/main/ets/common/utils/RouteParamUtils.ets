import router from '@ohos.router';

export interface BrowserBoundaryRouteState {
  dataScope: string;
  privacyMode: string;
  boundarySource: string;
  subpage?: string;
}

export interface SettingsTargetRouteState {
  settingsTargetId: string;
  settingsRevealTargetId: string;
}

export function readBrowserBoundaryRouteState(previous?: BrowserBoundaryRouteState): BrowserBoundaryRouteState {
  const params = router.getParams() as Record<string, string | undefined> | undefined;
  return {
    dataScope: params?.dataScope ?? previous?.dataScope ?? '',
    privacyMode: params?.privacyMode ?? previous?.privacyMode ?? '',
    boundarySource: params?.boundarySource ?? previous?.boundarySource ?? '',
    subpage: params?.subpage ?? previous?.subpage
  };
}

export function readSettingsTargetRouteState(previous?: SettingsTargetRouteState): SettingsTargetRouteState {
  const params = router.getParams() as Record<string, string | undefined> | undefined;
  return {
    settingsTargetId: params?.settingsTargetId ?? previous?.settingsTargetId ?? '',
    settingsRevealTargetId: params?.settingsRevealTargetId ?? previous?.settingsRevealTargetId ?? ''
  };
}

export function isPrivateBoundaryRoute(dataScope: string, privacyMode: string): boolean {
  return dataScope === 'session_ephemeral' || privacyMode === 'private';
}
