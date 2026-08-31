import { util } from '@kit.ArkTS';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserResolvedThemeMode,
  BrowserSessionPrivacyMode,
  BrowserThemeMode,
  BrowserThemePaletteId,
  SearchEngineRecord,
  SearchEngineSelectionScope,
  ShortcutKind,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import {
  AIRA_ICON_FONT_RAWFILE_PATH,
  GeneratedAiraIconCatalog
} from '../../core/resources/GeneratedAiraIconCatalog';
import {
  resolveHomeSystemShortcutDefinitionByUrl
} from '../shortcuts/HomeSystemShortcutCatalog';
import {
  CustomHomepageEnvironmentService,
  CustomHomepageNativeEnvironmentState
} from './CustomHomepageEnvironmentService';

interface CustomHomepageShortcutItem {
  id: string;
  kind: ShortcutKind;
  iconId: string;
  title: string;
  url: string;
  position: number;
  icon: string;
  iconRendering: string;
  iconColor: string;
}

export interface CustomHomepageShortcutIconItem {
  id: string;
  path: string;
  backgroundColor: string;
}

export interface CustomHomepageThemeState {
  mode: BrowserThemeMode;
  effectiveMode: BrowserResolvedThemeMode;
  palette: CustomHomepageThemePaletteState;
}

export interface CustomHomepageThemePaletteState {
  id: BrowserThemePaletteId;
  title: string;
  colors: CustomHomepageThemePaletteColors;
}

export interface CustomHomepageThemePaletteColors {
  accent: string;
  onAccent: string;
  pageBackground: string;
  surfaceBackground: string;
  controlBackground: string;
  textPrimary: string;
  textSecondary: string;
  divider: string;
  outline: string;
}

export interface CustomHomepagePrivacyState {
  privacyMode: BrowserSessionPrivacyMode;
  isPrivate: boolean;
}

export type CustomHomepageHoldingHandStatus = 0 | 1 | 2 | 3 | 16;

export interface CustomHomepageMotionState {
  allowed: boolean;
  holdingHandStatus: CustomHomepageHoldingHandStatus;
}

interface CustomHomepageDocumentStartState {
  theme?: CustomHomepageThemeState;
  privacy?: CustomHomepagePrivacyState;
  environment?: CustomHomepageNativeEnvironmentState;
  motion?: CustomHomepageMotionState;
}

interface CustomHomepageSearchEngineItem {
  id: string;
  name: string;
  kind: string;
  icon: string;
}

export interface CustomHomepageSearchEngineState {
  selectedEngineId: string;
  selectionScope: SearchEngineSelectionScope;
  engines: CustomHomepageSearchEngineItem[];
}

export interface CustomHomepageSearchEngineRequest {
  requestId: string;
  engineId: string;
}

export interface CustomHomepageSearchEngineRequestResult {
  requestId: string;
  ok: boolean;
  state: CustomHomepageSearchEngineState;
  code: string;
  message: string;
}

export interface CustomHomepageSearchRequest {
  query: string;
  engineId: string;
}

export type CustomHomepageStorageOperation = 'get' | 'set' | 'remove' | 'clear';

export interface CustomHomepageStorageRequest {
  requestId: string;
  key: string;
  valueJson: string;
}

export interface CustomHomepageStorageRequestResult {
  requestId: string;
  ok: boolean;
  found: boolean;
  valueJson: string;
  code: string;
  message: string;
}

interface CustomHomepageAiraUrlRequest {
  action: string;
  value: string;
}

export class CustomHomepageBridgeService {
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  private environmentService: CustomHomepageEnvironmentService;
  private searchEngineIconCache: Map<string, string> = new Map<string, string>();
  private operationalIconFontBase64: string = '';
  private operationalIconFontResolved: boolean = false;

  constructor(environmentService: CustomHomepageEnvironmentService = new CustomHomepageEnvironmentService()) {
    this.environmentService = environmentService;
  }

  buildDocumentStartScriptItem(state: CustomHomepageDocumentStartState = {}): ScriptItem {
    return {
      script: this.buildDocumentStartScript(state),
      scriptRules: ['.*']
    };
  }

  async buildShortcutsJson(
    shortcuts: ShortcutRecord[],
    icons: CustomHomepageShortcutIconItem[] = [],
    _effectiveMode: BrowserResolvedThemeMode = 'light'
  ): Promise<string> {
    const items: CustomHomepageShortcutItem[] = [];
    const ordered = shortcuts.slice().sort((left: ShortcutRecord, right: ShortcutRecord): number => {
      return left.position - right.position;
    });
    for (const shortcut of ordered) {
      const item = await this.buildShortcutItem(shortcut, icons);
      if (item !== undefined) {
        items.push(item);
      }
    }
    return JSON.stringify(items);
  }

  async buildShortcutsUpdateScript(
    shortcuts: ShortcutRecord[],
    icons: CustomHomepageShortcutIconItem[] = [],
    effectiveMode: BrowserResolvedThemeMode = 'light'
  ): Promise<string> {
    const shortcutsJson = await this.buildShortcutsJson(shortcuts, icons, effectiveMode);
    return `
${this.buildDocumentStartScript()}
window.__airaHomeSetShortcuts(${shortcutsJson});
`;
  }

  buildShortcutIconItemsSnapshot(
    shortcuts: ShortcutRecord[],
    currentIcons: CustomHomepageShortcutIconItem[],
    rememberedIcons: CustomHomepageShortcutIconItem[]
  ): CustomHomepageShortcutIconItem[] {
    const activeShortcutIds = shortcuts.map((shortcut: ShortcutRecord): string => shortcut.id);
    const rememberedItems = rememberedIcons.filter((item: CustomHomepageShortcutIconItem): boolean => {
      return activeShortcutIds.indexOf(item.id) >= 0 &&
        currentIcons.find((current: CustomHomepageShortcutIconItem): boolean => current.id === item.id) === undefined;
    });
    return rememberedItems.concat(currentIcons).map((item: CustomHomepageShortcutIconItem): CustomHomepageShortcutIconItem => {
      return {
        id: item.id,
        path: item.path,
        backgroundColor: item.backgroundColor
      };
    });
  }

  async buildSearchEngineState(
    selectedEngineId: string,
    selectionScope: SearchEngineSelectionScope,
    engines: SearchEngineRecord[]
  ): Promise<CustomHomepageSearchEngineState> {
    const items: CustomHomepageSearchEngineItem[] = [];
    const ordered = engines.slice().sort((left: SearchEngineRecord, right: SearchEngineRecord): number => {
      return left.position - right.position;
    });
    for (const engine of ordered) {
      const icon = await this.resolveSearchEngineIcon(engine);
      items.push({
        id: engine.id,
        name: engine.name,
        kind: engine.kind,
        icon: icon
      });
    }
    return {
      selectedEngineId: selectedEngineId,
      selectionScope: selectionScope,
      engines: items
    };
  }

  buildSearchEngineUpdateScript(state: CustomHomepageSearchEngineState): string {
    return `
${this.buildDocumentStartScript()}
window.__airaHomeSetSearchEngines(${JSON.stringify(state)});
`;
  }

  buildSearchEngineRequestResultScript(result: CustomHomepageSearchEngineRequestResult): string {
    return `
${this.buildDocumentStartScript()}
window.__airaHomeResolveSearchEngineRequest(${JSON.stringify(result)});
`;
  }

  buildStorageRequestResultScript(result: CustomHomepageStorageRequestResult): string {
    return `
${this.buildDocumentStartScript()}
window.__airaHomeResolveStorageRequest(${JSON.stringify(result)});
`;
  }

  parseSearchEngineRequest(value: string): CustomHomepageSearchEngineRequest | undefined {
    try {
      const parsed = JSON.parse(value) as CustomHomepageSearchEngineRequest;
      const requestId = `${parsed.requestId ?? ''}`.trim();
      const engineId = `${parsed.engineId ?? ''}`.trim();
      if (requestId.length === 0 || requestId.length > 128 || engineId.length === 0 || engineId.length > 256) {
        return undefined;
      }
      return {
        requestId: requestId,
        engineId: engineId
      };
    } catch (_error) {
      return undefined;
    }
  }

  parseStorageRequest(
    value: string,
    operation: CustomHomepageStorageOperation
  ): CustomHomepageStorageRequest | undefined {
    try {
      const parsed = JSON.parse(value) as CustomHomepageStorageRequest;
      const requestId = `${parsed.requestId ?? ''}`.trim();
      const key = `${parsed.key ?? ''}`.trim();
      const valueJson = `${parsed.valueJson ?? ''}`;
      if (requestId.length === 0 || requestId.length > 128) {
        return undefined;
      }
      if (operation !== 'clear' && (key.length === 0 || key.length > 256)) {
        return undefined;
      }
      if (operation === 'set' && valueJson.length === 0) {
        return undefined;
      }
      return {
        requestId: requestId,
        key: operation === 'clear' ? '' : key,
        valueJson: operation === 'set' ? valueJson : ''
      };
    } catch (_error) {
      return undefined;
    }
  }

  parseSearchRequest(value: string): CustomHomepageSearchRequest | undefined {
    try {
      const parsed = JSON.parse(value) as CustomHomepageSearchRequest;
      const query = `${parsed.query ?? ''}`.trim();
      const engineId = `${parsed.engineId ?? ''}`.trim();
      if (query.length > 8192 || engineId.length > 256) {
        return undefined;
      }
      return {
        query: query,
        engineId: engineId
      };
    } catch (_error) {
      return undefined;
    }
  }

  parseShortcutReorderRequest(value: string): string[] | undefined {
    try {
      const parsed = JSON.parse(value) as string[];
      if (!Array.isArray(parsed) || parsed.length > 256) {
        return undefined;
      }
      const ids: string[] = [];
      for (const item of parsed) {
        const id = `${item ?? ''}`.trim();
        if (id.length === 0 || id.length > 256) {
          return undefined;
        }
        ids.push(id);
      }
      return ids;
    } catch (_error) {
      return undefined;
    }
  }

  parseAiraUrl(url: string): CustomHomepageAiraUrlRequest | undefined {
    const normalized = url.trim();
    if (!normalized.toLowerCase().startsWith('aira:')) {
      return undefined;
    }
    const withoutScheme = normalized.substring(5).replace(/^\/\//, '');
    const cleanAction = withoutScheme.split('?')[0].split('#')[0];
    const segments = cleanAction.split('/').filter((segment: string): boolean => segment.trim().length > 0);
    if (segments.length === 0) {
      return undefined;
    }
    return {
      action: segments[0].trim().toLowerCase(),
      value: this.extractAiraUrlValue(normalized)
    };
  }

  buildThemeUpdateScript(theme: CustomHomepageThemeState): string {
    return `
${this.buildDocumentStartScript()}
window.__airaHomeSetTheme(${JSON.stringify(theme)});
`;
  }

  buildPrivacyUpdateScript(privacy: CustomHomepagePrivacyState): string {
    return `
${this.buildDocumentStartScript()}
window.__airaHomeSetPrivacy(${JSON.stringify(privacy)});
`;
  }

  buildHoldingHandUpdateScript(status: CustomHomepageHoldingHandStatus): string {
    return `
// Preserve the previous status while rebuilding the bridge. The setter below
// must see the old value so it can dispatch holdingHandChanged.
(function () {
  var previous = window.__airaHomeMotionState || {};
  window.__airaHomeMotionState = {
    allowed: true,
    holdingHandStatus: previous.holdingHandStatus === undefined ? 16 : previous.holdingHandStatus
  };
})();
${this.buildDocumentStartScript()}
window.__airaHomeSetHoldingHandStatus(${status});
`;
  }

  buildBackRequestScript(): string {
    return `
(function () {
  try {
    window.dispatchEvent(new CustomEvent('aira-home-back-requested'));
  } catch (_error) {
  }
})();
`;
  }

  buildDocumentStartScript(state: CustomHomepageDocumentStartState = {}): string {
    const themeBootstrapLine = state.theme === undefined ?
      "window.__airaHomeTheme = window.__airaHomeTheme || { mode: 'system', effectiveMode: 'light', palette: {} };" :
      `window.__airaHomeTheme = ${JSON.stringify(this.normalizeThemeState(state.theme))};`;
    const privacyBootstrapLine = state.privacy === undefined ?
      "window.__airaHomePrivacy = window.__airaHomePrivacy || { privacyMode: 'regular', isPrivate: false };" :
      `window.__airaHomePrivacy = ${JSON.stringify(this.normalizePrivacyState(state.privacy))};`;
    const motionBootstrapLine = state.motion === undefined ?
      'window.__airaHomeMotionState = window.__airaHomeMotionState || { allowed: false, holdingHandStatus: 16 };' :
      `window.__airaHomeMotionState = ${JSON.stringify(state.motion)};`;
    const nativeEnvironment = state.environment ?? this.environmentService.resolveNativeState();
    const environmentBootstrapLine =
      `window.__airaHomeNativeEnvironment = ${JSON.stringify(nativeEnvironment)};`;
    return `
(function () {
  window.__airaHomeShortcuts = Array.isArray(window.__airaHomeShortcuts) ? window.__airaHomeShortcuts : [];
  ${themeBootstrapLine}
  window.__airaHomeSearchEngineState = window.__airaHomeSearchEngineState || null;
  window.__airaHomeSearchEngineWaiters = Array.isArray(window.__airaHomeSearchEngineWaiters) ?
    window.__airaHomeSearchEngineWaiters : [];
  window.__airaHomeSearchEngineRequests = window.__airaHomeSearchEngineRequests || {};
  window.__airaHomeStorageRequests = window.__airaHomeStorageRequests || {};
  ${privacyBootstrapLine}
  ${motionBootstrapLine}
  window.__airaHomeHoldingHandCallbacks = Array.isArray(window.__airaHomeHoldingHandCallbacks) ?
    window.__airaHomeHoldingHandCallbacks : [];
  ${environmentBootstrapLine}
  window.__airaHomeApiInstalled = true;
  function clone(value) {
    try {
      return JSON.parse(JSON.stringify(value || []));
    } catch (_error) {
      return [];
    }
  }
  function getShortcuts() {
    return Array.isArray(window.__airaHomeShortcuts) ? window.__airaHomeShortcuts : [];
  }
  function normalizeThemeColors(colors) {
    var incoming = colors || {};
    return {
      accent: String(incoming.accent || '').trim(),
      onAccent: String(incoming.onAccent || '').trim(),
      pageBackground: String(incoming.pageBackground || '').trim(),
      surfaceBackground: String(incoming.surfaceBackground || '').trim(),
      controlBackground: String(incoming.controlBackground || '').trim(),
      textPrimary: String(incoming.textPrimary || '').trim(),
      textSecondary: String(incoming.textSecondary || '').trim(),
      divider: String(incoming.divider || '').trim(),
      outline: String(incoming.outline || '').trim()
    };
  }
  function normalizeThemePalette(palette) {
    var incoming = palette || {};
    return {
      id: String(incoming.id || '').trim(),
      title: String(incoming.title || '').trim(),
      colors: normalizeThemeColors(incoming.colors)
    };
  }
  function getTheme() {
    var theme = window.__airaHomeTheme || {};
    var mode = theme.mode === 'light' || theme.mode === 'dark' || theme.mode === 'system' ? theme.mode : 'system';
    var effectiveMode = theme.effectiveMode === 'dark' ? 'dark' : 'light';
    return {
      mode: mode,
      effectiveMode: effectiveMode,
      palette: normalizeThemePalette(theme.palette)
    };
  }
  function getPrivacy() {
    var privacy = window.__airaHomePrivacy || {};
    var privacyMode = privacy.privacyMode === 'private' ? 'private' : 'regular';
    return { privacyMode: privacyMode, isPrivate: privacyMode === 'private' };
  }
  function normalizeHoldingHandStatus(status) {
    var value = Number(status);
    return value === 0 || value === 1 || value === 2 || value === 3 || value === 16 ? value : 16;
  }
  function getHoldingHandStatus() {
    var state = window.__airaHomeMotionState || {};
    return normalizeHoldingHandStatus(state.holdingHandStatus);
  }
  function assertHoldingHandEventType(type) {
    if (type !== 'holdingHandChanged') {
      throw new TypeError("type 必须为 'holdingHandChanged'");
    }
  }
  function addHoldingHandCallback(type, callback) {
    assertHoldingHandEventType(type);
    if (typeof callback !== 'function') {
      throw new TypeError('callback 必须为函数');
    }
    if (window.__airaHomeHoldingHandCallbacks.indexOf(callback) < 0) {
      window.__airaHomeHoldingHandCallbacks.push(callback);
    }
  }
  function removeHoldingHandCallback(type, callback) {
    assertHoldingHandEventType(type);
    if (callback === undefined) {
      window.__airaHomeHoldingHandCallbacks.splice(0);
      return;
    }
    if (typeof callback !== 'function') {
      throw new TypeError('callback 必须为函数或省略');
    }
    var index = window.__airaHomeHoldingHandCallbacks.indexOf(callback);
    if (index >= 0) {
      window.__airaHomeHoldingHandCallbacks.splice(index, 1);
    }
  }
  function normalizeNativeEnvironment(environment) {
    var incoming = environment || {};
    var formFactor = String(incoming.formFactor || '').trim();
    if (formFactor !== 'phone' && formFactor !== 'tablet' && formFactor !== 'two_in_one' &&
      formFactor !== 'pc' && formFactor !== 'unknown') {
      formFactor = 'unknown';
    }
    var shellFamily = incoming.shellFamily === 'large_screen' ? 'large_screen' : 'phone';
    return { formFactor: formFactor, shellFamily: shellFamily };
  }
  function resolveViewportDimension(primaryValue, fallbackValue) {
    var value = Number(primaryValue || fallbackValue || 0);
    return Number.isFinite(value) && value > 0 ? Math.round(value) : 0;
  }
  function getEnvironment() {
    var nativeEnvironment = normalizeNativeEnvironment(window.__airaHomeNativeEnvironment);
    var root = document.documentElement || {};
    var width = resolveViewportDimension(window.innerWidth, root.clientWidth);
    var height = resolveViewportDimension(window.innerHeight, root.clientHeight);
    var orientation = width > height ? 'landscape' : (height > width ? 'portrait' : 'square');
    return {
      formFactor: nativeEnvironment.formFactor,
      shellFamily: nativeEnvironment.shellFamily,
      viewport: {
        width: width,
        height: height,
        orientation: orientation
      }
    };
  }
  function buildEnvironmentSignature(environment) {
    var state = environment || getEnvironment();
    var viewport = state.viewport || {};
    return [state.formFactor, state.shellFamily, viewport.width, viewport.height, viewport.orientation].join('|');
  }
  function emitEnvironmentChanged() {
    var environment = getEnvironment();
    var signature = buildEnvironmentSignature(environment);
    if (signature === window.__airaHomeEnvironmentSignature) {
      return;
    }
    window.__airaHomeEnvironmentSignature = signature;
    try {
      window.dispatchEvent(new CustomEvent('aira-home-environment-changed', {
        detail: environment
      }));
    } catch (_error) {
    }
  }
  window.__airaHomeEnvironmentSignature = buildEnvironmentSignature(getEnvironment());
  if (window.__airaHomeEnvironmentListenerInstalled !== true) {
    window.__airaHomeEnvironmentListenerInstalled = true;
    window.addEventListener('resize', function () {
      if (window.__airaHomeEnvironmentFramePending === true) {
        return;
      }
      window.__airaHomeEnvironmentFramePending = true;
      var schedule = typeof window.requestAnimationFrame === 'function' ? window.requestAnimationFrame : function (task) {
        return setTimeout(task, 16);
      };
      schedule(function () {
        window.__airaHomeEnvironmentFramePending = false;
        emitEnvironmentChanged();
      });
    });
  }
  function ensureIconFont() {
    if (window.__airaHomeIconFontReady === true) {
      return Promise.resolve(true);
    }
    if (window.__airaHomeIconFontPromise) {
      return window.__airaHomeIconFontPromise;
    }
    var retryAfter = Number(window.__airaHomeIconFontRetryAfter || 0);
    if (retryAfter > Date.now()) {
      return Promise.resolve(false);
    }
    var encoded = String(window.__airaHomeIconFontBase64 || '');
    if (!encoded) {
      encoded = request('iconFont', '');
      if (encoded) {
        window.__airaHomeIconFontBase64 = encoded;
      }
    }
    if (typeof document === 'undefined') {
      return Promise.resolve(false);
    }
    try {
      var style = document.getElementById('aira-home-icon-font-style');
      if (!style) {
        if (!encoded) {
          return Promise.resolve(false);
        }
        var parent = document.head || document.documentElement;
        if (!parent) {
          return Promise.resolve(false);
        }
        style = document.createElement('style');
        style.id = 'aira-home-icon-font-style';
        style.textContent = "@font-face{font-family:'AiraHomeIcons';" +
          'src:url("data:font/ttf;base64,' + encoded + '") format("truetype");' +
          'font-style:normal;font-weight:400;font-display:block;}';
        parent.appendChild(style);
        window.__airaHomeIconFontBase64 = '';
      }
      window.__airaHomeIconFontInstalled = true;
      if (!document.fonts || typeof document.fonts.load !== 'function') {
        window.__airaHomeIconFontRetryAfter = 0;
        window.__airaHomeIconFontReady = true;
        try {
          window.dispatchEvent(new CustomEvent('aira-home-icon-font-ready'));
        } catch (_error) {
        }
        return Promise.resolve(true);
      }
      window.__airaHomeIconFontPromise = document.fonts.load("16px 'AiraHomeIcons'").then(function () {
        window.__airaHomeIconFontRetryAfter = 0;
        window.__airaHomeIconFontReady = true;
        try {
          window.dispatchEvent(new CustomEvent('aira-home-icon-font-ready'));
        } catch (_error) {
        }
        return true;
      }).catch(function () {
        window.__airaHomeIconFontPromise = null;
        window.__airaHomeIconFontRetryAfter = Date.now() + 30000;
        return false;
      });
      return window.__airaHomeIconFontPromise;
    } catch (_error) {
      window.__airaHomeIconFontPromise = null;
      window.__airaHomeIconFontRetryAfter = Date.now() + 30000;
      return Promise.resolve(false);
    }
  }
  if (typeof window.__airaHomeEnsureIconFont !== 'function') {
    window.__airaHomeEnsureIconFont = ensureIconFont;
  }
  function clearShortcutIconElement(element) {
    while (element.firstChild) {
      element.removeChild(element.firstChild);
    }
    element.classList.remove(
      'aira-home-shortcut-icon-font',
      'aira-home-shortcut-icon-image',
      'aira-home-shortcut-icon-fallback'
    );
    element.style.removeProperty('font-family');
    element.style.removeProperty('font-style');
    element.style.removeProperty('font-weight');
    element.style.removeProperty('line-height');
    element.style.removeProperty('background-color');
    element.removeAttribute('aria-hidden');
  }
  function renderShortcutFallback(element, shortcut) {
    clearShortcutIconElement(element);
    var fallback = String((shortcut && (shortcut.title || shortcut.url)) || '?').trim().slice(0, 1) || '?';
    element.textContent = fallback.toUpperCase();
    element.classList.add('aira-home-shortcut-icon-fallback');
    var fallbackColor = String((shortcut && shortcut.iconColor) || '').trim();
    if (fallbackColor) {
      element.style.backgroundColor = fallbackColor;
    }
    return false;
  }
  function renderShortcutIcon(element, shortcut) {
    if (!element || typeof element.appendChild !== 'function') {
      return false;
    }
    clearShortcutIconElement(element);
    var item = shortcut || {};
    var icon = String(item.icon || '');
    var rendering = String(item.iconRendering || '').toLowerCase();
    var renderKey = String(item.id || '') + ':' + rendering + ':' + icon;
    element.setAttribute('data-aira-icon-key', renderKey);
    if (rendering === 'font' && icon.length > 0) {
      element.textContent = icon;
      element.classList.add('aira-home-shortcut-icon-font');
      element.style.fontFamily = 'AiraHomeIcons';
      element.style.fontStyle = 'normal';
      element.style.fontWeight = 'normal';
      element.style.lineHeight = '1';
      element.setAttribute('aria-hidden', 'true');
      window.__airaHomeEnsureIconFont().then(function (ready) {
        if (ready !== true && window.__airaHomeIconFontInstalled !== true &&
          element.getAttribute('data-aira-icon-key') === renderKey) {
          renderShortcutFallback(element, item);
        }
      });
      return true;
    }
    if (rendering === 'image' && icon.length > 0) {
      var image = document.createElement('img');
      image.alt = '';
      image.draggable = false;
      image.src = icon;
      image.className = 'aira-home-shortcut-icon-image';
      image.addEventListener('error', function () {
        if (element.getAttribute('data-aira-icon-key') === renderKey) {
          renderShortcutFallback(element, item);
        }
      });
      element.classList.add('aira-home-shortcut-icon-image');
      element.setAttribute('aria-hidden', 'true');
      element.appendChild(image);
      return true;
    }
    return renderShortcutFallback(element, item);
  }
  function normalizeSearchEngineState(state) {
    var incoming = state || {};
    var engines = Array.isArray(incoming.engines) ? clone(incoming.engines) : [];
    return {
      selectedEngineId: String(incoming.selectedEngineId || ''),
      selectionScope: incoming.selectionScope === 'session' ? 'session' : 'persistent',
      engines: engines
    };
  }
  function getSearchEngineState() {
    if (!window.__airaHomeSearchEngineState) {
      return null;
    }
    return normalizeSearchEngineState(window.__airaHomeSearchEngineState);
  }
  function requestSearchEngineState() {
    request('searchEngines', '');
  }
  function waitForSearchEngineState() {
    var current = getSearchEngineState();
    if (current) {
      return Promise.resolve(clone(current));
    }
    return new Promise(function (resolve) {
      window.__airaHomeSearchEngineWaiters.push(resolve);
      requestSearchEngineState();
    });
  }
  function buildSearchEngineRequestId() {
    return 'search-engine-' + Date.now() + '-' + Math.random().toString(36).slice(2);
  }
  function buildStorageRequestId() {
    return 'storage-' + Date.now() + '-' + Math.random().toString(36).slice(2);
  }
  function emitShortcutsChanged() {
    try {
      window.dispatchEvent(new CustomEvent('aira-home-shortcuts-changed', {
        detail: clone(getShortcuts())
      }));
    } catch (_error) {
    }
  }
  function request(action, value) {
    var bridge = window.__airaHomeNativeBridge;
    if (!bridge || typeof bridge.request !== 'function') {
      return '';
    }
    try {
      return String(bridge.request(String(action || ''), String(value || '')) || '');
    } catch (_error) {
      return '';
    }
  }
  function openAiraAction(action, value) {
    try {
      var target = 'aira://' + encodeURIComponent(String(action || ''));
      if (String(value || '').length > 0) {
        target += '?url=' + encodeURIComponent(String(value || ''));
      }
      window.location.href = target;
    } catch (_error) {
    }
  }
  function openSystemEntry(entry) {
    openAiraAction('systemEntry', entry);
  }
  window.__airaHomeSetShortcuts = function (items) {
    window.__airaHomeShortcuts = Array.isArray(items) ? clone(items) : [];
    emitShortcutsChanged();
  };
  window.__airaHomeSetTheme = function (theme) {
    var incoming = theme || {};
    var mode = incoming.mode === 'light' || incoming.mode === 'dark' || incoming.mode === 'system' ? incoming.mode : 'system';
    var effectiveMode = incoming.effectiveMode === 'dark' ? 'dark' : 'light';
    window.__airaHomeTheme = {
      mode: mode,
      effectiveMode: effectiveMode,
      palette: normalizeThemePalette(incoming.palette)
    };
    try {
      window.dispatchEvent(new CustomEvent('aira-home-theme-changed', {
        detail: getTheme()
      }));
    } catch (_error) {
    }
  };
  window.__airaHomeSetPrivacy = function (privacy) {
    var incoming = privacy || {};
    var privacyMode = incoming.privacyMode === 'private' || incoming.isPrivate === true ? 'private' : 'regular';
    window.__airaHomePrivacy = { privacyMode: privacyMode, isPrivate: privacyMode === 'private' };
    try {
      window.dispatchEvent(new CustomEvent('aira-home-privacy-mode-changed', {
        detail: getPrivacy()
      }));
    } catch (_error) {
    }
  };
  window.__airaHomeSetHoldingHandStatus = function (status) {
    var motionState = window.__airaHomeMotionState || {};
    if (motionState.allowed !== true) {
      return;
    }
    var previous = getHoldingHandStatus();
    var next = normalizeHoldingHandStatus(status);
    window.__airaHomeMotionState = { allowed: true, holdingHandStatus: next };
    if (previous === next) {
      return;
    }
    window.__airaHomeHoldingHandCallbacks.slice().forEach(function (callback) {
      try {
        callback(next);
      } catch (_error) {
      }
    });
  };
  window.__airaHomeSetSearchEngines = function (state) {
    window.__airaHomeSearchEngineState = normalizeSearchEngineState(state);
    var waiters = window.__airaHomeSearchEngineWaiters.splice(0);
    waiters.forEach(function (resolve) {
      try {
        resolve(clone(window.__airaHomeSearchEngineState));
      } catch (_error) {
      }
    });
    try {
      window.dispatchEvent(new CustomEvent('aira-home-search-engines-changed', {
        detail: clone(window.__airaHomeSearchEngineState)
      }));
    } catch (_error) {
    }
  };
  window.__airaHomeResolveSearchEngineRequest = function (result) {
    var incoming = result || {};
    var requestId = String(incoming.requestId || '');
    var pending = window.__airaHomeSearchEngineRequests[requestId];
    if (!pending) {
      if (incoming.state) {
        window.__airaHomeSetSearchEngines(incoming.state);
      }
      return;
    }
    delete window.__airaHomeSearchEngineRequests[requestId];
    if (pending.timer) {
      clearTimeout(pending.timer);
    }
    if (incoming.state) {
      window.__airaHomeSetSearchEngines(incoming.state);
    }
    if (incoming.ok === true) {
      pending.resolve(clone(getSearchEngineState()));
      return;
    }
    var error = new Error(String(incoming.message || '搜索引擎切换失败'));
    error.code = String(incoming.code || 'SEARCH_ENGINE_UPDATE_FAILED');
    pending.reject(error);
  };
  window.__airaHomeResolveStorageRequest = function (result) {
    var incoming = result || {};
    var requestId = String(incoming.requestId || '');
    var pending = window.__airaHomeStorageRequests[requestId];
    if (!pending) {
      return;
    }
    delete window.__airaHomeStorageRequests[requestId];
    if (pending.timer) {
      clearTimeout(pending.timer);
    }
    if (incoming.ok === true) {
      pending.resolve(incoming);
      return;
    }
    var error = new Error(String(incoming.message || '主页配置存储失败'));
    error.code = String(incoming.code || 'STORAGE_FAILED');
    pending.reject(error);
  };
  function requestStorage(action, payload) {
    var requestId = buildStorageRequestId();
    return new Promise(function (resolve, reject) {
      var timer = setTimeout(function () {
        delete window.__airaHomeStorageRequests[requestId];
        var timeoutError = new Error('主页配置存储请求超时');
        timeoutError.code = 'STORAGE_TIMEOUT';
        reject(timeoutError);
      }, 12000);
      window.__airaHomeStorageRequests[requestId] = {
        resolve: resolve,
        reject: reject,
        timer: timer
      };
      payload.requestId = requestId;
      var response = request(action, JSON.stringify(payload));
      if (response !== 'accepted') {
        clearTimeout(timer);
        delete window.__airaHomeStorageRequests[requestId];
        var requestError = new Error(response === 'invalid_request' ? '主页配置存储请求无效' : '主页配置存储不可用');
        requestError.code = response === 'invalid_request' ? 'INVALID_STORAGE_REQUEST' : 'STORAGE_UNAVAILABLE';
        reject(requestError);
      }
    });
  }
  var holdingHandStatus = Object.freeze({
    NOT_HELD: 0,
    LEFT_HAND_HELD: 1,
    RIGHT_HAND_HELD: 2,
    BOTH_HANDS_HELD: 3,
    UNKNOWN_STATUS: 16
  });
  var airaMotion = window.__airaHomeMotionState.allowed === true ? Object.freeze({
    HoldingHandStatus: holdingHandStatus,
    on: addHoldingHandCallback,
    off: removeHoldingHandCallback
  }) : undefined;
  window.AiraHome = {
    motion: airaMotion,
    prepareIconFont: function () {
      return window.__airaHomeEnsureIconFont();
    },
    renderShortcutIcon: function (element, shortcut) {
      return renderShortcutIcon(element, shortcut);
    },
    getSearchEngineState: function () {
      return waitForSearchEngineState();
    },
    setSearchEngine: function (engineId) {
      var normalizedEngineId = String(engineId || '').trim();
      if (!normalizedEngineId) {
        var emptyError = new Error('搜索引擎 ID 不能为空');
        emptyError.code = 'ENGINE_NOT_AVAILABLE';
        return Promise.reject(emptyError);
      }
      var requestId = buildSearchEngineRequestId();
      return new Promise(function (resolve, reject) {
        var timer = setTimeout(function () {
          delete window.__airaHomeSearchEngineRequests[requestId];
          var timeoutError = new Error('搜索引擎切换超时');
          timeoutError.code = 'SEARCH_ENGINE_UPDATE_TIMEOUT';
          reject(timeoutError);
        }, 12000);
        window.__airaHomeSearchEngineRequests[requestId] = {
          resolve: resolve,
          reject: reject,
          timer: timer
        };
        var response = request('setSearchEngine', JSON.stringify({
          requestId: requestId,
          engineId: normalizedEngineId
        }));
        if (response !== 'accepted') {
          clearTimeout(timer);
          delete window.__airaHomeSearchEngineRequests[requestId];
          var requestError = new Error(response === 'invalid_request' ? '搜索引擎请求无效' : '搜索引擎切换不可用');
          requestError.code = response === 'invalid_request' ? 'INVALID_REQUEST' : 'SEARCH_ENGINE_UPDATE_UNAVAILABLE';
          reject(requestError);
        }
      });
    },
    storage: {
      get: function (key, defaultValue) {
        return requestStorage('storageGet', {
          key: String(key || '')
        }).then(function (result) {
          if (!result || result.found !== true) {
            return defaultValue;
          }
          return JSON.parse(String(result.valueJson || 'null'));
        });
      },
      set: function (key, value) {
        var valueJson;
        try {
          valueJson = JSON.stringify(value);
        } catch (error) {
          return Promise.reject(error);
        }
        if (valueJson === undefined) {
          return Promise.reject(new Error('主页配置值必须可以转换为 JSON'));
        }
        return requestStorage('storageSet', {
          key: String(key || ''),
          valueJson: valueJson
        }).then(function () {});
      },
      remove: function (key) {
        return requestStorage('storageRemove', {
          key: String(key || '')
        }).then(function () {});
      },
      clear: function () {
        return requestStorage('storageClear', {}).then(function () {});
      }
    },
    getShortcuts: function () {
      return Promise.resolve(clone(getShortcuts()));
    },
    openShortcutPicker: function () {
      openAiraAction('openShortcutPicker', '');
    },
    refreshShortcuts: function () {
      request('shortcuts', '');
      openAiraAction('shortcuts', '');
      return Promise.resolve(clone(getShortcuts()));
    },
    removeShortcut: function (id) {
      openAiraAction('removeShortcut', id);
      return Promise.resolve();
    },
    deleteShortcut: function (id) {
      openAiraAction('removeShortcut', id);
      return Promise.resolve();
    },
    openShortcut: function (id) {
      openAiraAction('openShortcut', id);
    },
    copyShortcutUrl: function (id) {
      openAiraAction('copyShortcutUrl', id);
    },
    editShortcut: function (id) {
      openAiraAction('editShortcut', id);
    },
    moveShortcutUp: function (id) {
      openAiraAction('moveShortcutUp', id);
      return Promise.resolve();
    },
    moveShortcutDown: function (id) {
      openAiraAction('moveShortcutDown', id);
      return Promise.resolve();
    },
    moveShortcutToTop: function (id) {
      openAiraAction('moveShortcutToTop', id);
      return Promise.resolve();
    },
    moveShortcutToBottom: function (id) {
      openAiraAction('moveShortcutToBottom', id);
      return Promise.resolve();
    },
    reorderShortcuts: function (ids) {
      if (!Array.isArray(ids)) {
        var invalidOrderError = new Error('快捷方式排序列表无效');
        invalidOrderError.code = 'INVALID_SHORTCUT_ORDER';
        return Promise.reject(invalidOrderError);
      }
      var normalizedIds = ids.map(function (id) {
        return String(id || '').trim();
      });
      var response = request('reorderShortcuts', JSON.stringify(normalizedIds));
      if (response === 'accepted' || response === 'unchanged') {
        return Promise.resolve();
      }
      var reorderError = new Error(response === 'not_allowed'
        ? '当前模式不允许保存快捷方式排序'
        : response === 'invalid_request'
          ? '快捷方式排序列表无效'
          : '快捷方式排序不可用');
      reorderError.code = response === 'not_allowed'
        ? 'SHORTCUT_REORDER_NOT_ALLOWED'
        : response === 'invalid_request'
          ? 'INVALID_SHORTCUT_ORDER'
          : 'SHORTCUT_REORDER_UNAVAILABLE';
      return Promise.reject(reorderError);
    },
    confirmDeleteShortcut: function (id) {
      openAiraAction('confirmDeleteShortcut', id);
    },
    getTheme: function () {
      return Promise.resolve(getTheme());
    },
    getEnvironment: function () {
      return Promise.resolve(getEnvironment());
    },
    getThemePalette: function () {
      return Promise.resolve(getTheme().palette);
    },
    refreshTheme: function () {
      request('theme', '');
      openAiraAction('theme', '');
      return Promise.resolve(getTheme());
    },
    getPrivacyMode: function () {
      return Promise.resolve(getPrivacy());
    },
    isPrivateMode: function () {
      return Promise.resolve(getPrivacy().isPrivate);
    },
    refreshPrivacyMode: function () {
      request('privacy', '');
      openAiraAction('privacy', '');
      return Promise.resolve(getPrivacy());
    },
    openSettings: function () {
      openAiraAction('settings', '');
    },
    openBookmarks: function () {
      openAiraAction('bookmarks', '');
    },
    openHistory: function () {
      openAiraAction('history', '');
    },
    openTabs: function () {
      openAiraAction('tabs', '');
    },
    openDownloads: function () {
      openAiraAction('downloads', '');
    },
    openSavedPages: function () {
      openSystemEntry('savedPages');
    },
    openOfflinePages: function () {
      openSystemEntry('savedPages');
    },
    openSync: function () {
      openSystemEntry('sync');
    },
    openAiraPro: function () {
      openSystemEntry('airaPro');
    },
    openMembership: function () {
      openSystemEntry('airaPro');
    },
    openSearchSettings: function () {
      openSystemEntry('searchSettings');
    },
    openAdBlockSettings: function () {
      openSystemEntry('adBlockSettings');
    },
    openSiteSettings: function () {
      openSystemEntry('siteSettings');
    },
    openWebpageTranslationSettings: function () {
      openSystemEntry('webpageTranslationSettings');
    },
    openPasswordSettings: function () {
      openSystemEntry('passwordSettings');
    },
    openUserScripts: function () {
      openSystemEntry('userScripts');
    },
    openUserAgentSettings: function () {
      openSystemEntry('userAgentSettings');
    },
    openDownloadSettings: function () {
      openSystemEntry('downloadSettings');
    },
    openCustomHomepageSettings: function () {
      openSystemEntry('customHomepageSettings');
    },
    openGeneralSettings: function () {
      openSystemEntry('generalSettings');
    },
    openAppearanceSettings: function () {
      openSystemEntry('appearanceSettings');
    },
    openPrivacySecuritySettings: function () {
      openSystemEntry('privacySecuritySettings');
    },
    openExperimentsSettings: function () {
      openSystemEntry('experimentsSettings');
    },
    openAboutSettings: function () {
      openSystemEntry('aboutSettings');
    },
    openStartupSettings: function () {
      openSystemEntry('startupSettings');
    },
    openPrivateTabsSettings: function () {
      openSystemEntry('privateTabsSettings');
    },
    openHistoryRetentionSettings: function () {
      openSystemEntry('historyRetentionSettings');
    },
    openThemePaletteSettings: function () {
      openSystemEntry('themePaletteSettings');
    },
    openKeyboardShortcutsSettings: function () {
      openSystemEntry('keyboardShortcutsSettings');
    },
    openAppProxySettings: function () {
      openSystemEntry('appProxySettings');
    },
    openSystemEntry: function (entry) {
      openSystemEntry(entry);
    },
    openSearch: function () {
      openAiraAction('openSearch', '');
    },
    openToolbar: function () {
      openAiraAction('openToolbar', '');
    },
    openNovelBookshelf: function () {
      openAiraAction('openNovelBookshelf', '');
    },
    togglePrivateMode: function () {
      openAiraAction('togglePrivateMode', '');
    },
    scanQr: function () {
      openAiraAction('scanQr', '');
    },
    search: function (query, options) {
      var engineId = '';
      if (options && typeof options === 'object') {
        engineId = String(options.engineId || '').trim();
      }
      openAiraAction('search', JSON.stringify({
        query: String(query || ''),
        engineId: engineId
      }));
    },
    openUrl: function (url) {
      openAiraAction('open', url);
    },
    setBackHandlerActive: function (active) {
      request('backHandler', active === true ? '1' : '0');
    }
  };
  try {
    window.dispatchEvent(new CustomEvent('aira-home-ready', {
      detail: { apiVersion: 'v1' }
    }));
  } catch (_error) {
  }
})();
`;
  }

  private normalizePrivacyState(privacy: CustomHomepagePrivacyState | undefined): CustomHomepagePrivacyState {
    const privacyMode = privacy?.privacyMode === 'private' || privacy?.isPrivate === true ? 'private' : 'regular';
    return {
      privacyMode: privacyMode,
      isPrivate: privacyMode === 'private'
    };
  }

  private normalizeThemeState(theme: CustomHomepageThemeState): CustomHomepageThemeState {
    const mode = theme.mode === 'light' || theme.mode === 'dark' ? theme.mode : 'system';
    return {
      mode: mode,
      effectiveMode: theme.effectiveMode === 'dark' ? 'dark' : 'light',
      palette: {
        id: theme.palette.id,
        title: theme.palette.title,
        colors: {
          accent: theme.palette.colors.accent,
          onAccent: theme.palette.colors.onAccent,
          pageBackground: theme.palette.colors.pageBackground,
          surfaceBackground: theme.palette.colors.surfaceBackground,
          controlBackground: theme.palette.colors.controlBackground,
          textPrimary: theme.palette.colors.textPrimary,
          textSecondary: theme.palette.colors.textSecondary,
          divider: theme.palette.colors.divider,
          outline: theme.palette.colors.outline
        }
      }
    };
  }

  private extractAiraUrlValue(url: string): string {
    const queryIndex = url.indexOf('?');
    if (queryIndex < 0) {
      return '';
    }
    const query = url.substring(queryIndex + 1).split('#')[0];
    const pairs = query.split('&');
    for (const pair of pairs) {
      const separatorIndex = pair.indexOf('=');
      const key = separatorIndex >= 0 ? pair.substring(0, separatorIndex) : pair;
      if (key === 'q' || key === 'query' || key === 'url') {
        const encoded = separatorIndex >= 0 ? pair.substring(separatorIndex + 1) : '';
        return this.safeDecodeUrlComponent(encoded);
      }
    }
    return '';
  }

  private safeDecodeUrlComponent(value: string): string {
    try {
      return decodeURIComponent(value.replace(/\+/g, ' ')).trim();
    } catch (_error) {
      return value.trim();
    }
  }

  private async resolveSearchEngineIcon(engine: SearchEngineRecord): Promise<string> {
    if (engine.kind === 'custom') {
      return engine.iconUrl?.trim() ?? '';
    }
    const cached = this.searchEngineIconCache.get(engine.id);
    if (cached !== undefined) {
      return cached;
    }
    if (!AppRuntimeContext.hasApplicationContext()) {
      return '';
    }
    try {
      const iconBytes = await AppRuntimeContext.getApplicationContext().resourceManager
        .getMediaByName(`search_engine_${engine.id}`);
      const icon = `data:image/svg+xml;base64,${this.base64Helper.encodeToStringSync(iconBytes)}`;
      this.searchEngineIconCache.set(engine.id, icon);
      return icon;
    } catch (_error) {
      this.searchEngineIconCache.set(engine.id, '');
      return '';
    }
  }

  private async buildShortcutItem(
    shortcut: ShortcutRecord,
    icons: CustomHomepageShortcutIconItem[]
  ): Promise<CustomHomepageShortcutItem | undefined> {
    if (shortcut.kind === 'system') {
      const definition = resolveHomeSystemShortcutDefinitionByUrl(shortcut.url);
      if (definition === undefined) {
        return undefined;
      }
      const icon = GeneratedAiraIconCatalog.resolveFontGlyph(definition.iconId);
      return {
        id: shortcut.id,
        kind: 'system',
        iconId: definition.iconId,
        title: definition.title,
        url: '',
        position: shortcut.position,
        icon: icon,
        iconRendering: icon.length > 0 ? 'font' : '',
        iconColor: ''
      };
    }
    const icon = icons.find((item: CustomHomepageShortcutIconItem): boolean => item.id === shortcut.id);
    return {
      id: shortcut.id,
      kind: 'web',
      iconId: '',
      title: shortcut.title,
      url: shortcut.url,
      position: shortcut.position,
      icon: icon?.path ?? shortcut.icon ?? '',
      iconRendering: icon?.path.length ? 'image' : shortcut.iconRendering ?? '',
      iconColor: icon?.backgroundColor ?? shortcut.iconColor ?? ''
    };
  }

  resolveOperationalIconFontBase64(): string {
    if (this.operationalIconFontResolved) {
      return this.operationalIconFontBase64;
    }
    if (!AppRuntimeContext.hasApplicationContext()) {
      return '';
    }
    try {
      const fontBytes = AppRuntimeContext.getApplicationContext().resourceManager
        .getRawFileContentSync(AIRA_ICON_FONT_RAWFILE_PATH);
      this.operationalIconFontBase64 = this.base64Helper.encodeToStringSync(fontBytes);
      this.operationalIconFontResolved = true;
      return this.operationalIconFontBase64;
    } catch (_error) {
      return '';
    }
  }
}
