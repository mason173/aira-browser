import { readExtensionStorageRecord, writeExtensionStorageRecord } from '@/platform/extensionStorage';

export const HISTORY_TAKEOVER_OPEN_MESSAGE = 'AIRA_HISTORY_TAKEOVER_OPEN';
const INSTALLED_BROWSER_STORAGE_KEY = 'airaInstalledBrowserKind';

export type HistoryBrowserKind = 'zen' | 'floorp' | 'librewolf' | 'waterfox' | 'firefox' | 'opera' | 'vivaldi' | 'edge' | 'brave' | 'chrome' | 'chromium';
export type HistoryPlatform = 'mac' | 'other';

export type HistoryBrowserSignals = {
  userAgent?: string;
  brands?: readonly string[];
  isBrave?: boolean;
  isVivaldi?: boolean;
};

export type HistoryShortcutEvent = {
  key?: string;
  code?: string;
  ctrlKey: boolean;
  metaKey: boolean;
  altKey: boolean;
  shiftKey: boolean;
};

export function detectHistoryBrowserKind(userAgent: string): HistoryBrowserKind {
  return resolveHistoryBrowserKind({ userAgent });
}

export function resolveHistoryBrowserKind(signals: HistoryBrowserSignals = {}): HistoryBrowserKind {
  const ua = signals.userAgent || '';
  const brands = (signals.brands || []).map((brand) => brand.toLowerCase());
  const hasBrand = (name: string) => brands.some((brand) => brand.includes(name));

  if (signals.isBrave === true || hasBrand('brave')) return 'brave';
  // These Gecko forks still contain Firefox/ in the user agent.
  if (/Zen\//i.test(ua)) return 'zen';
  if (/Waterfox\//i.test(ua)) return 'waterfox';
  if (/LibreWolf\//i.test(ua)) return 'librewolf';
  if (/Floorp\//i.test(ua)) return 'floorp';
  if (/Firefox\//i.test(ua)) return 'firefox';
  if (/OPR\/|Opera\//i.test(ua) || hasBrand('opera')) return 'opera';
  // Chrome and Edge are the common case. An inferred Vivaldi flag must not
  // override either of them; only an explicit Vivaldi token can.
  if (/Edg\/|Edge\//i.test(ua) || hasBrand('microsoft edge') || brands.some((brand) => brand === 'edge')) return 'edge';
  if (hasBrand('google chrome')) return 'chrome';
  if (/Vivaldi\//i.test(ua) || hasBrand('vivaldi')) return 'vivaldi';
  if (/Chrome\//i.test(ua)) return 'chrome';
  if (signals.isVivaldi === true) return 'vivaldi';
  return 'chromium';
}

export function historyBrowserLabel(kind: HistoryBrowserKind): string {
  switch (kind) {
    case 'zen': return 'Zen';
    case 'floorp': return 'Floorp';
    case 'librewolf': return 'LibreWolf';
    case 'waterfox': return 'Waterfox';
    case 'firefox': return 'Firefox';
    case 'opera': return 'Opera';
    case 'vivaldi': return 'Vivaldi';
    case 'edge': return 'Edge';
    case 'brave': return 'Brave';
    case 'chrome': return 'Chrome';
    default: return 'Chromium';
  }
}

type HistoryBrowserNavigator = {
  userAgent?: string;
  brave?: { isBrave?: () => Promise<boolean> };
  userAgentData?: { brands?: Array<{ brand?: string }>; platform?: string };
};

type GeckoBrowserInfo = {
  name?: string;
  vendor?: string;
  zen?: unknown;
  floorp?: unknown;
  librewolf?: unknown;
  waterfox?: unknown;
};

type GeckoBrowserRuntime = {
  getBrowserInfo?: () => Promise<GeckoBrowserInfo>;
};

export async function readInstalledHistoryBrowser(
  navigatorObject: HistoryBrowserNavigator | null = globalThis.navigator ?? null,
): Promise<HistoryBrowserKind> {
  // Zen reports name "Firefox" and keeps its identity in info.zen. A Chrome-like
  // user agent must not override that Gecko result.
  const geckoKind = await readGeckoBrowserKind();
  if (geckoKind) return rememberSpecificBrowser(geckoKind);
  let isBrave = false;
  try {
    if (typeof navigatorObject?.brave?.isBrave === 'function') {
      isBrave = await navigatorObject.brave.isBrave() === true;
    }
  } catch {
    isBrave = false;
  }
  const brands = navigatorObject?.userAgentData?.brands
    ?.map((item) => String(item?.brand || '').trim())
    .filter(Boolean) || [];
  const detected = resolveHistoryBrowserKind({
    userAgent: navigatorObject?.userAgent || '',
    brands,
    isBrave,
    isVivaldi: await detectInstalledVivaldi(navigatorObject, brands, isBrave),
  });
  return rememberSpecificBrowser(detected);
}

async function rememberSpecificBrowser(detected: HistoryBrowserKind): Promise<HistoryBrowserKind> {
  const remembered = await readRememberedBrowserKind();
  // Chrome and Edge must not inherit a name stored by another browser, or by an
  // earlier uncertain read. A remembered Edge must not appear on Chrome, or the reverse.
  if (detected === 'chrome' || detected === 'edge' || detected === 'chromium') {
    if (remembered && remembered !== detected) {
      await writeExtensionStorageRecord({ [INSTALLED_BROWSER_STORAGE_KEY]: '' }).catch(() => undefined);
    }
    return detected;
  }
  if (detected !== remembered) {
    await writeExtensionStorageRecord({ [INSTALLED_BROWSER_STORAGE_KEY]: detected }).catch(() => undefined);
  }
  return detected;
}

async function readRememberedBrowserKind(): Promise<HistoryBrowserKind | null> {
  try {
    const record = await readExtensionStorageRecord([INSTALLED_BROWSER_STORAGE_KEY]);
    const value = String(record[INSTALLED_BROWSER_STORAGE_KEY] || '').trim();
    return isHistoryBrowserKind(value) && value !== 'chrome' && value !== 'chromium' ? value : null;
  } catch {
    return null;
  }
}

function isHistoryBrowserKind(value: string): value is HistoryBrowserKind {
  return value === 'zen'
    || value === 'floorp'
    || value === 'librewolf'
    || value === 'waterfox'
    || value === 'firefox'
    || value === 'opera'
    || value === 'vivaldi'
    || value === 'edge'
    || value === 'brave'
    || value === 'chrome'
    || value === 'chromium';
}

type VivaldiTabProbe = {
  query?: (queryInfo: { currentWindow?: boolean }) => Promise<Array<Record<string, unknown>>>;
};

export function tabHasVivaldiMetadata(tab: object | null | undefined): boolean {
  return Boolean(tab && ('vivExtData' in tab || Object.prototype.hasOwnProperty.call(tab, 'vivExtData')));
}

export function vivaldiProbeRejectionMeansInstalled(message: string): boolean {
  const text = message.trim();
  // Only a rejected tab id means the browser accepted vivExtData. Any other
  // message, including an empty or localized one, is not evidence of Vivaldi.
  return /no tab with id|no such tab|invalid tab/i.test(text);
}

export function vivaldiFromExtensionClientHints(options: {
  protocol?: string;
  userAgent?: string;
  brands?: readonly string[];
  platform?: string;
}): boolean {
  const userAgent = options.userAgent || '';
  const brands = options.brands || [];
  // Missing client hints are not a Vivaldi signal. Chrome extension pages can
  // omit them too, and an uncertain read must stay Chrome.
  return /Vivaldi/i.test(userAgent) || brands.some((brand) => /vivaldi/i.test(brand));
}

async function detectInstalledVivaldi(
  navigatorObject: HistoryBrowserNavigator | null,
  brands: string[],
  isBrave: boolean,
): Promise<boolean> {
  const userAgent = navigatorObject?.userAgent || '';
  const normalizedBrands = brands.map((brand) => brand.toLowerCase());
  if (/Edg\/|Edge\//i.test(userAgent) || normalizedBrands.some((brand) => brand.includes('microsoft edge') || brand === 'edge')) {
    return false;
  }
  if (normalizedBrands.some((brand) => brand.includes('google chrome'))) return false;
  if (/Vivaldi/i.test(userAgent) || normalizedBrands.some((brand) => brand.includes('vivaldi'))) return true;
  if (isBrave || /OPR\/|Firefox\//i.test(userAgent)) return false;
  if (normalizedBrands.some((brand) => /brave|opera/.test(brand))) return false;
  // A Chrome user agent is Chrome. Do not probe vivExtData: Chrome can reject
  // that call with the same "no tab" message Vivaldi uses.
  if (/Chrome\//i.test(userAgent)) return false;
  if (await queryHasVivaldiTab()) return true;
  return vivaldiFromExtensionClientHints({
    protocol: globalThis.location?.protocol,
    userAgent,
    brands,
    platform: navigatorObject?.userAgentData?.platform,
  });
}

async function queryHasVivaldiTab(): Promise<boolean> {
  const chromeApi = globalThis.chrome as unknown as {
    tabs?: VivaldiTabProbe;
    windows?: { getAll?: () => Promise<Array<Record<string, unknown>>> };
  } | undefined;
  try {
    const tabs = chromeApi?.tabs?.query ? await chromeApi.tabs.query({}) : [];
    if (tabs.some((tab) => tabHasVivaldiMetadata(tab))) return true;
  } catch {
    // Tabs can be unavailable while the service worker is starting.
  }
  try {
    const windows = chromeApi?.windows?.getAll ? await chromeApi.windows.getAll() : [];
    return windows.some((item) => tabHasVivaldiMetadata(item));
  } catch {
    return false;
  }
}

function hasGeckoForkMarker(value: unknown): boolean {
  if (typeof value === 'string') return value.trim().length > 0;
  return Boolean(value) && typeof value === 'object';
}

export function kindFromGeckoBrowserInfo(info: GeckoBrowserInfo | null | undefined): HistoryBrowserKind | null {
  if (!info) return null;
  if (hasGeckoForkMarker(info.zen)) return 'zen';
  if (hasGeckoForkMarker(info.floorp)) return 'floorp';
  if (hasGeckoForkMarker(info.librewolf)) return 'librewolf';
  if (hasGeckoForkMarker(info.waterfox)) return 'waterfox';
  const named = kindFromGeckoBrowserName(`${info.name || ''} ${info.vendor || ''}`);
  if (named) return named;
  return /firefox/i.test(`${info.name || ''} ${info.vendor || ''}`) ? 'firefox' : null;
}

function kindFromGeckoBrowserName(name: string): HistoryBrowserKind | null {
  if (/zen/i.test(name)) return 'zen';
  if (/floorp/i.test(name)) return 'floorp';
  if (/librewolf/i.test(name)) return 'librewolf';
  if (/waterfox/i.test(name)) return 'waterfox';
  return null;
}

async function readGeckoBrowserKind(): Promise<HistoryBrowserKind | null> {
  const info = await readGeckoBrowserInfo();
  return kindFromGeckoBrowserInfo(info);
}

async function readGeckoBrowserInfo(): Promise<GeckoBrowserInfo | null> {
  const runtimeScopes = globalThis as typeof globalThis & {
    browser?: { runtime?: GeckoBrowserRuntime };
    chrome?: { runtime?: GeckoBrowserRuntime };
  };
  const scopes = [runtimeScopes.browser, runtimeScopes.chrome];
  for (const scope of scopes) {
    if (typeof scope?.runtime?.getBrowserInfo !== 'function') continue;
    try {
      return await scope.runtime.getBrowserInfo() || null;
    } catch {
      // Try the other namespace. Firefox exposes both, and one can throw.
    }
  }
  return null;
}

export function detectHistoryPlatform(platform: string, userAgent = ''): HistoryPlatform {
  return /Mac|iPhone|iPad|iPod/i.test(`${platform} ${userAgent}`) ? 'mac' : 'other';
}

export function isGeckoHistoryBrowser(browser: HistoryBrowserKind): boolean {
  return browser === 'firefox'
    || browser === 'zen'
    || browser === 'floorp'
    || browser === 'librewolf'
    || browser === 'waterfox';
}

// Firefox and Vivaldi keep their own history UI. The extension command is the
// shortcut that actually opens Aira, including when focus is not in a page.
export function usesExtensionHistoryCommand(browser: HistoryBrowserKind): boolean {
  return isGeckoHistoryBrowser(browser) || browser === 'vivaldi';
}

export function geckoHistoryCommandShortcut(platform: HistoryPlatform): string {
  return platform === 'mac' ? 'Command+Shift+Y' : 'Ctrl+Shift+Y';
}

export function extensionHistoryCommandShortcuts(platform: HistoryPlatform): string[] {
  const primary = geckoHistoryCommandShortcut(platform);
  return platform === 'mac' ? [primary, 'Ctrl+Shift+Y'] : [primary];
}

export function isExtensionHistoryCommandShortcut(
  platform: HistoryPlatform,
  event: {
    code?: string;
    ctrlKey?: boolean;
    metaKey?: boolean;
    altKey?: boolean;
    shiftKey?: boolean;
    repeat?: boolean;
  },
): boolean {
  if (event.repeat || event.altKey || event.code !== 'KeyY') return false;
  if (platform === 'mac') return Boolean(event.metaKey && event.shiftKey && !event.ctrlKey);
  return Boolean(event.ctrlKey && event.shiftKey && !event.metaKey);
}

export function shouldAssignExtensionHistoryShortcut(browser: HistoryBrowserKind, currentShortcut: string): boolean {
  if (!usesExtensionHistoryCommand(browser)) return false;
  const current = String(currentShortcut || '').trim();
  if (!current) return true;
  // Command+Y / Ctrl+Y is the browser's own history key. It does not open Aira.
  return /^(?:Command|Ctrl)\+Y$/i.test(current);
}

export function historyShortcutLabel(browser: HistoryBrowserKind, platform: HistoryPlatform): string {
  if (usesExtensionHistoryCommand(browser)) {
    return platform === 'mac' ? '⌘⇧Y' : 'Ctrl+Shift+Y';
  }
  if (browser === 'opera') {
    return platform === 'mac' ? '⌘⇧H' : 'Ctrl+H';
  }
  if (browser === 'edge' && platform !== 'mac') {
    return 'Ctrl+Y';
  }
  return platform === 'mac' ? '⌘Y' : 'Ctrl+H';
}

export function formatAssignedHistoryShortcut(shortcut: string, platform: HistoryPlatform): string {
  const parts = String(shortcut || '').split('+').map((part) => part.trim()).filter(Boolean);
  const key = parts.at(-1) || '';
  if (!key) return '';
  const modifiers = new Set(parts.slice(0, -1));
  const shift = modifiers.has('Shift');
  const alt = modifiers.has('Alt');
  const macControl = modifiers.has('MacCtrl');
  const command = modifiers.has('Command') || (platform === 'mac' && modifiers.has('Ctrl') && !macControl);
  const control = macControl || (platform !== 'mac' && modifiers.has('Ctrl'));
  if (platform === 'mac') {
    return `${command ? '⌘' : ''}${control ? '⌃' : ''}${alt ? '⌥' : ''}${shift ? '⇧' : ''}${key}`;
  }
  const labels = [
    control ? 'Ctrl' : '',
    alt ? 'Alt' : '',
    shift ? 'Shift' : '',
    key,
  ].filter(Boolean);
  return labels.join('+');
}

function matchesLetter(event: HistoryShortcutEvent, letter: string): boolean {
  const code = String(event.code || '');
  if (code) return code === `Key${letter.toUpperCase()}`;
  return String(event.key || '').toLowerCase() === letter.toLowerCase();
}

function hasPrimaryModifier(platform: HistoryPlatform, event: HistoryShortcutEvent): boolean {
  if (event.altKey) return false;
  if (platform === 'mac') return event.metaKey && !event.ctrlKey;
  return event.ctrlKey && !event.metaKey;
}

// Page override already owns the history command on Chromium browsers that honor
// chrome_url_overrides. Only intercept shortcuts the override cannot see.
export function isHistoryTakeoverShortcut(
  browser: HistoryBrowserKind,
  platform: HistoryPlatform,
  event: HistoryShortcutEvent,
): boolean {
  if (!hasPrimaryModifier(platform, event)) return false;

  // Edge on Windows/Linux: the requested history shortcut is Ctrl+Y. Ctrl+H is
  // already covered by the history page override, so stealing it would also
  // fight Redo on other Chromium browsers. Mac Edge uses Command+Y, which the
  // page override receives.
  if (browser === 'edge') {
    return platform !== 'mac' && matchesLetter(event, 'y') && !event.shiftKey;
  }

  if (browser === 'chromium' || browser === 'chrome' || browser === 'brave') return false;

  if (browser === 'opera') {
    if (!matchesLetter(event, 'h')) return false;
    return platform === 'mac' ? event.shiftKey : !event.shiftKey;
  }

  // These browsers own their history keys. The extension command opens Aira.
  if (usesExtensionHistoryCommand(browser)) return false;

  if (!matchesLetter(event, 'h') && !(platform === 'mac' && matchesLetter(event, 'y') && !event.shiftKey)) {
    return false;
  }
  return true;
}

export function isNativeHistoryPageUrl(url: string): boolean {
  const value = String(url || '').trim();
  if (!value) return false;
  return /^(?:chrome|edge|brave|opera|vivaldi|whale|yandex):\/\/history(?:\/|$|\?|#)/i.test(value)
    || /^about:history(?:$|\?|#)/i.test(value);
}
