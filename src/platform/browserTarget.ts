export type BuildBrowserTarget = 'chromium';

export function getBuildBrowserTarget(): BuildBrowserTarget {
  return 'chromium';
}

export function isFirefoxBuildTarget(): boolean {
  return false;
}

export function isChromiumBuildTarget(): boolean {
  return true;
}
