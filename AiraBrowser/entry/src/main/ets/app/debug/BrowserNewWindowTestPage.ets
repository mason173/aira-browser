const BROWSER_NEW_WINDOW_TEST_URL = 'aira://release-disabled';

export function isBrowserNewWindowTestUrl(_url: string): boolean {
  return false;
}

export function getBrowserNewWindowTestUrl(): string {
  return BROWSER_NEW_WINDOW_TEST_URL;
}

export function getBrowserNewWindowTestTitle(): string {
  return 'Aira';
}

export function resolveBrowserNewWindowTestTitle(url: string, fallbackTitle: string): string {
  return isBrowserNewWindowTestUrl(url) ? getBrowserNewWindowTestTitle() : fallbackTitle;
}

export function buildBrowserNewWindowTestHtml(): string {
  return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8" /></head><body>Aira</body></html>';
}
