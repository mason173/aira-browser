import { BuilderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  buildWebAppearanceDocumentStartScriptItem,
  resolveWebAppearancePolicy,
  WebAppearancePolicy
} from './WebAppearancePolicy';
import { BrowserHistoryApiBridgeScriptService } from './BrowserHistoryApiBridge';
import { BrowserWebAttributeModifier } from './WebDefaultContextMenuModifier';
import { WebBackForwardCacheCoordinator } from './WebBackForwardCacheCoordinator';
import { BrowserWebRuntimeSecurityPolicy } from '../../common/models/BrowserWebSecurityModels';
import { USER_SCRIPT_NATIVE_BRIDGE_NAME } from '../../features/userscripts/UserScriptNativeBridgeModels';
import {
  sharedBrowserSafeBrowsingThreatPresentationService
} from '../../services/web/BrowserSafeBrowsingThreatPresentationService';
import {
  WEB_VIDEO_FULLSCREEN_REQUEST_RESULT_EVENT,
  WEB_VIDEO_RUNTIME_ID_PROPERTY
} from '../../services/video/WebVideoRuntimeProtocol';

const HOSTED_WEB_NODE_LOG_DOMAIN: number = 0x0000;
const HOSTED_WEB_NODE_LOG_TAG: string = 'HostedWebNode';
const HOSTED_WEB_DOCUMENT_SCRIPT_KEY_VERSION: string = 'hosted-web-document-start-v3';
const HOSTED_WEB_VIDEO_RUNTIME_ID_PROPERTY_LITERAL: string = JSON.stringify(WEB_VIDEO_RUNTIME_ID_PROPERTY);
const HOSTED_WEB_VIDEO_FULLSCREEN_REQUEST_RESULT_EVENT_LITERAL: string =
  JSON.stringify(WEB_VIDEO_FULLSCREEN_REQUEST_RESULT_EVENT);

export interface HostedWebNodeCallbacks {
  onControllerAttached: (tabId: string) => void;
  onBeforeWebBuild?: (tabId: string) => void;
  onPageVisible: (tabId: string, event: OnPageVisibleEvent) => void;
  onPageBegin: (tabId: string, event: OnPageBeginEvent) => void;
  onPageEnd: (tabId: string, event: OnPageEndEvent) => void;
  onNativeMediaPlayerObserved?: (tabId: string, mediaInfo: webview.MediaInfo) => void;
  onAudioStateChanged?: (tabId: string, playing: boolean) => void;
  onLoadFinished: (tabId: string) => void;
  onProgressChange: (tabId: string, event: OnProgressChangeEvent) => void;
  onScroll: (tabId: string, event: OnScrollEvent) => void;
  onTouch: (tabId: string, event: TouchEvent) => void;
  onNavigationEntryCommitted: (tabId: string, details: LoadCommittedDetails) => void;
  onTitleReceive: (tabId: string, event: OnTitleReceiveEvent) => void;
  onFaviconReceived: (tabId: string, event: OnFaviconReceivedEvent) => void;
  onSearchResultReceive: (tabId: string, event: OnSearchResultReceiveEvent) => void;
  onErrorReceive: (tabId: string, event: OnErrorReceiveEvent) => void;
  onPermissionRequest: (tabId: string, request: PermissionRequest) => void;
  onGeolocationShow: (tabId: string, event: OnGeolocationShowEvent) => void;
  onWindowNew: (tabId: string, event: OnWindowNewEvent) => void;
  onWindowExit: (tabId: string) => void;
  onActivateContent: (tabId: string) => void;
  onShowFileSelector: (tabId: string, event: OnShowFileSelectorEvent) => boolean;
  onPrompt: (tabId: string, event: OnPromptEvent) => boolean;
  onConfirm: (tabId: string, event: OnConfirmEvent) => boolean;
  onAlert: (tabId: string, event: OnAlertEvent) => boolean;
  onHttpAuthRequest: (tabId: string, event: OnHttpAuthRequestEvent) => boolean;
  onSslErrorEvent: (tabId: string, event: SslErrorEvent) => void;
  onLoadIntercept: (tabId: string, event: OnLoadInterceptEvent) => boolean;
  onInterceptRequest: (tabId: string, event: OnInterceptRequestEvent) => WebResourceResponse | null;
  onOverrideUrlLoading: (tabId: string, request: WebResourceRequest) => boolean;
  onDownloadStart: (tabId: string, event: OnDownloadStartEvent) => void;
  onUserScriptInstallRequest: (tabId: string, url: string) => void;
  onHistoryApiUrlChange: (tabId: string, payloadJson: string) => void;
  onPageChromeThemeSignal: (tabId: string, payloadJson: string) => void;
  onPageBehaviorSignal: (tabId: string, payloadJson: string) => void;
  onAdBlockCosmeticHidden: (tabId: string, payloadJson: string) => void;
  onAdBlockManualHidden: (tabId: string, payloadJson: string) => void;
  onContextMenuShow: (tabId: string, event: OnContextMenuShowEvent, controller: webview.WebviewController) => boolean;
  onContextMenuHide: (tabId: string) => void;
  onFullScreenEnter: (tabId: string, event: FullScreenEnterEvent) => void;
  onFullScreenExit: (tabId: string) => void;
}

export interface HostedWebVideoControllerBridge {
  enterFullscreen(tabId: string, payloadJson: string): void;
  exitFullscreen(tabId: string): void;
  cast(tabId: string, payloadJson: string): void;
  readSystemControl(tabId: string, kind: string): string;
  setSystemControl(tabId: string, payloadJson: string): string;
  close(tabId: string): void;
}

export interface HostedWebNodeConfig {
  tabId: string;
  componentSnapshotId: string;
  webComponentSnapshotId?: string;
  controller: webview.WebviewController;
  uiContext: UIContext;
  pageUrl: string;
  pageTitle: string;
  initialSrc?: string;
  incognitoMode?: boolean;
  appearancePolicy?: WebAppearancePolicy;
  runtimeSecurityPolicy?: BrowserWebRuntimeSecurityPolicy;
  documentStartScripts?: ScriptItem[];
  documentStartScriptKey?: string;
  documentEndScripts?: ScriptItem[];
  documentEndScriptKey?: string;
  userScriptNativeBridge?: Object;
  hostedNativeBridge?: Object;
  webVideoControllerBridge?: HostedWebVideoControllerBridge;
  forceEnableWebZoom?: boolean;
  textZoomRatio?: number;
  pullRefreshNestedScrollEnabled?: boolean;
  callbacks: HostedWebNodeCallbacks;
}

const HOSTED_WEB_NODE_IDEAL_WIDTH: number = 390;
const HOSTED_WEB_NODE_IDEAL_HEIGHT: number = 844;
const HOSTED_WEB_BFCACHE_COORDINATOR: WebBackForwardCacheCoordinator = new WebBackForwardCacheCoordinator();
const HOSTED_WEB_NATIVE_BRIDGE_NAME: string = USER_SCRIPT_NATIVE_BRIDGE_NAME;
const PAGE_BEHAVIOR_NATIVE_BRIDGE_NAME: string = '__airaPageBehaviorNativeBridge';
const PAGE_BEHAVIOR_NATIVE_BRIDGE_METHODS: string[] = ['onSignal'];
const HOSTED_WEB_NATIVE_BRIDGE_METHODS: string[] = [
  'request',
  'readValue',
  'openInTab',
  'abort',
  'installUserScript',
  'historyApiUrlChange',
  'pageChromeThemeSignal',
  'adBlockCosmeticHidden',
  'adBlockManualHidden',
  'webVideoEnterFullscreen',
  'webVideoExitFullscreen',
  'webVideoCast',
  'webVideoReadSystemControl',
  'webVideoSetSystemControl',
  'webVideoClose'
];
const HOSTED_WEB_NATIVE_BRIDGE_ALIAS_SCRIPT: string = `
;(function airaInstallHostedWebNativeBridgeAliases() {
  var remainingAttempts = 60;
  function installAliases() {
    var bridge = window.__airaUserScriptNativeBridge;
    if (!bridge) {
      if (remainingAttempts > 0) {
        remainingAttempts -= 1;
        setTimeout(installAliases, 100);
      }
      return;
    }
    window.__airaHistoryApiNativeBridge = {
      onUrlChange: function (payloadJson) { return bridge.historyApiUrlChange(payloadJson); }
    };
    window.__airaPageChromeThemeNativeBridge = {
      onSignal: function (payloadJson) { return bridge.pageChromeThemeSignal(payloadJson); }
    };
    window.__airaAdBlockNativeBridge = {
      onCosmeticHidden: function (payloadJson) { return bridge.adBlockCosmeticHidden(payloadJson); },
      onManualHidden: function (payloadJson) { return bridge.adBlockManualHidden(payloadJson); }
    };
    window.__airaWebVideoControllerBridge = {
      enterFullscreen: function (payloadJson) { return bridge.webVideoEnterFullscreen(payloadJson); },
      exitFullscreen: function () { return bridge.webVideoExitFullscreen(); },
      cast: function (payloadJson) { return bridge.webVideoCast(payloadJson); },
      readSystemControl: function (kind) { return bridge.webVideoReadSystemControl(kind); },
      setSystemControl: function (payloadJson) { return bridge.webVideoSetSystemControl(payloadJson); },
      close: function () { return bridge.webVideoClose(); }
    };
  }
  installAliases();
})();
//# sourceURL=aira-hosted-web-native-bridge-aliases.js
`;
const HOSTED_WEB_NATIVE_BRIDGE_ALIAS_SCRIPTS: ScriptItem[] = [{
  script: HOSTED_WEB_NATIVE_BRIDGE_ALIAS_SCRIPT,
  scriptRules: ['.*']
}];
const WEB_LINK_DRAG_SUPPRESSION_SCRIPT: string = `
(function () {
  if (window.__airaLinkDragSuppressed === true) {
    return;
  }
  window.__airaLinkDragSuppressed = true;
  document.addEventListener('dragstart', function (event) {
    var target = event.target;
    while (target && target !== document) {
      if (target.tagName === 'A' && target.href) {
        event.preventDefault();
        event.stopPropagation();
        return false;
      }
      target = target.parentNode;
    }
    return true;
  }, true);
})();
`;
const USER_SCRIPT_INSTALL_LINK_CAPTURE_SCRIPT: string = `
(function () {
  if (window.__airaUserScriptInstallCapture === true) {
    return;
  }
  window.__airaUserScriptInstallCapture = true;
  var installUrlPattern = /\\.user\\.js(?:[?#]|$)/i;
  function isGreasyForkHost() {
    var host = String(location.hostname || '').toLowerCase();
    return host === 'greasyfork.org' || host.endsWith('.greasyfork.org') ||
      host === 'sleazyfork.org' || host.endsWith('.sleazyfork.org');
  }
  function isUserScriptInstallUrl(value) {
    return installUrlPattern.test(String(value || ''));
  }
  function resolveHref(anchor) {
    if (!anchor) {
      return '';
    }
    return String(anchor.href || anchor.getAttribute('href') || '');
  }
  function findInstallLink(target) {
    while (target && target !== document) {
      if (target.tagName === 'A' && target.href) {
        var href = resolveHref(target);
        if (isUserScriptInstallUrl(href)) {
          return href;
        }
      }
      target = target.parentNode;
    }
    return '';
  }
  function openInstallUrl(href) {
    if (!href) {
      return false;
    }
    try {
      var bridge = window.__airaUserScriptNativeBridge;
      if (bridge && typeof bridge.installUserScript === 'function') {
        bridge.installUserScript(String(href));
        return true;
      }
    } catch (_error) {
    }
    window.location.href = href;
    return true;
  }
  function buildAiraManagerBridge() {
    return {
      isInstalled: function (_name, _namespace, callback) {
        if (typeof callback === 'function') {
          callback({ installed: false, version: null });
        }
      }
    };
  }
  function installGreasyForkManagerBridge() {
    if (!isGreasyForkHost()) {
      return;
    }
    try {
      var external = window.external || {};
      if (typeof external.Tampermonkey !== 'function') {
        external.Tampermonkey = function () {
          return buildAiraManagerBridge();
        };
      }
      window.external = external;
      return;
    } catch (_error) {
    }
    try {
      Object.defineProperty(window, 'external', {
        configurable: true,
        value: {
          Tampermonkey: function () {
            return buildAiraManagerBridge();
          }
        }
      });
    } catch (_error) {
    }
  }
  installGreasyForkManagerBridge();
  document.addEventListener('click', function (event) {
    var href = findInstallLink(event.target);
    if (!href) {
      return;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    openInstallUrl(href);
  }, true);
  document.addEventListener('submit', function (event) {
    var action = String(event.target && event.target.action || '');
    if (!isUserScriptInstallUrl(action)) {
      return;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
    openInstallUrl(action);
  }, true);
  var originalOpen = window.open;
  window.open = function (url, target, features) {
    if (isUserScriptInstallUrl(url) && openInstallUrl(String(url))) {
      return null;
    }
    return originalOpen ? originalOpen.apply(window, arguments) : null;
  };
  function patchLocationMethod(name) {
    try {
      var original = window.location[name];
      if (typeof original !== 'function') {
        return;
      }
      window.location[name] = function (url) {
        if (isUserScriptInstallUrl(url) && openInstallUrl(String(url))) {
          return;
        }
        return original.apply(window.location, arguments);
      };
    } catch (_error) {
    }
  }
  patchLocationMethod('assign');
  patchLocationMethod('replace');
})();
`;
const WEB_FILE_SAVE_PICKER_COMPAT_SCRIPT: string = `
(function () {
  function hideShowSaveFilePicker() {
    try {
      Object.defineProperty(window, 'showSaveFilePicker', {
        configurable: true,
        set: function (_value) {
        },
        get: function () {
          return undefined;
        }
      });
      return;
    } catch (_error) {
    }
    try {
      window.showSaveFilePicker = undefined;
    } catch (_error) {
    }
  }
  function applyCompat() {
    hideShowSaveFilePicker();
  }
  applyCompat();
  if (window.__airaWebFileSavePickerCompatTimerInstalled === true) {
    return;
  }
  window.__airaWebFileSavePickerCompatTimerInstalled = true;
  var attempts = 0;
  var timer = setInterval(function () {
    attempts += 1;
    applyCompat();
    if (attempts >= 80) {
      clearInterval(timer);
    }
  }, 250);
})();
`;
const PAGE_CHROME_THEME_SIGNAL_SCRIPT: string = `
(function () {
  if (window.__airaPageChromeThemeSignalInstalled === true) {
    return;
  }
  window.__airaPageChromeThemeSignalInstalled = true;
  var lastSignature = '';
  var signalTimer = -1;
  var trailingSignalTimer = -1;
  var bridgeRetryTimer = -1;
  var bridgeRetryCount = 0;
  var followupTimers = [];

  function toHex(value, minimumAlpha) {
    var normalized = String(value || '').trim();
    var alphaFloor = typeof minimumAlpha === 'number' ? minimumAlpha : 0.96;
    if (!normalized) {
      return '';
    }
    var probe = document.createElement('span');
    probe.style.color = '';
    probe.style.color = normalized;
    if (!probe.style.color) {
      return '';
    }
    (document.body || document.documentElement).appendChild(probe);
    var resolved = window.getComputedStyle(probe).color || '';
    probe.remove();
    var match = resolved.match(/rgba?\\(([^)]+)\\)/i);
    if (!match) {
      return '';
    }
    var parts = match[1].split(',').map(function (part) {
      return part.trim();
    });
    var red = Number.parseInt(parts[0], 10);
    var green = Number.parseInt(parts[1], 10);
    var blue = Number.parseInt(parts[2], 10);
    var alpha = parts.length > 3 ? Number.parseFloat(parts[3]) : 1;
    if ([red, green, blue].some(function (item) {
      return Number.isNaN(item);
    }) || Number.isNaN(alpha) || alpha < alphaFloor) {
      return '';
    }
    var channelToHex = function (channel) {
      return Math.max(0, Math.min(255, channel)).toString(16).padStart(2, '0');
    };
    return '#' + channelToHex(red) + channelToHex(green) + channelToHex(blue);
  }

  function readAttribute(node, name) {
    try {
      return node ? String(node.getAttribute(name) || '') : '';
    } catch (_error) {
      return '';
    }
  }

  function readMetaThemeColor() {
    try {
      var metaNodes = Array.from(document.querySelectorAll('meta[name="theme-color"]'));
      var fallback = '';
      for (var index = metaNodes.length - 1; index >= 0; index -= 1) {
        var node = metaNodes[index];
        var content = String(node.getAttribute('content') || '').trim();
        if (!content) {
          continue;
        }
        var media = String(node.getAttribute('media') || '').trim();
        if (!media) {
          if (!fallback) {
            fallback = content;
          }
          continue;
        }
        try {
          if (window.matchMedia(media).matches) {
            return content;
          }
        } catch (_error) {
        }
      }
      return fallback;
    } catch (_error) {
      return '';
    }
  }

  function hasDarkToken(value) {
    return String(value || '').toLowerCase().split(/\\s+/).indexOf('dark') >= 0;
  }

  function resolveSupportsDarkAppearance() {
    try {
      var meta = document.querySelector('meta[name="color-scheme"]');
      if (meta && hasDarkToken(meta.getAttribute('content') || '')) {
        return true;
      }
      var rootScheme = window.getComputedStyle(document.documentElement).colorScheme || '';
      if (hasDarkToken(rootScheme)) {
        return true;
      }
      if (document.body) {
        var bodyScheme = window.getComputedStyle(document.body).colorScheme || '';
        if (hasDarkToken(bodyScheme)) {
          return true;
        }
      }
    } catch (_error) {
    }
    return false;
  }

  function resolveNodeBackgroundColor(node) {
    var current = node;
    while (current && current !== document) {
      var backgroundColor = window.getComputedStyle(current).backgroundColor || '';
      var hex = toHex(backgroundColor, 0.8);
      if (hex) {
        return hex;
      }
      current = current.parentElement;
    }
    return '';
  }

  function resolveDeclaredPageBackgroundColor() {
    var nodes = [document.documentElement, document.body];
    for (var index = 0; index < nodes.length; index += 1) {
      var node = nodes[index];
      if (!node) {
        continue;
      }
      var backgroundColor = window.getComputedStyle(node).backgroundColor || '';
      var hex = toHex(backgroundColor, 0.8);
      if (hex) {
        return hex;
      }
    }
    return '';
  }

  function resolveViewportBackgroundColor() {
    var width = Math.max(1, window.innerWidth || document.documentElement.clientWidth || 1);
    var height = Math.max(1, window.innerHeight || document.documentElement.clientHeight || 1);
    var sampleXFactors = [0.2, 0.5, 0.8];
    var sampleYFactors = [0.08, 0.24, 0.48];
    var counts = {};
    var bestColor = '';
    var bestCount = 0;
    for (var yIndex = 0; yIndex < sampleYFactors.length; yIndex += 1) {
      var sampleY = Math.max(1, Math.min(height - 1, Math.floor(height * sampleYFactors[yIndex])));
      for (var xIndex = 0; xIndex < sampleXFactors.length; xIndex += 1) {
        var sampleX = Math.max(0, Math.min(width - 1, Math.floor(width * sampleXFactors[xIndex])));
        var color = resolveNodeBackgroundColor(document.elementFromPoint(sampleX, sampleY));
        if (!color) {
          continue;
        }
        counts[color] = (counts[color] || 0) + 1;
        if (counts[color] > bestCount) {
          bestCount = counts[color];
          bestColor = color;
        }
      }
    }
    return bestCount >= 2 ? bestColor : '';
  }

  function resolvePageBackgroundColor() {
    return resolveViewportBackgroundColor() || resolveDeclaredPageBackgroundColor();
  }

  function buildSnapshot() {
    return {
      themeColor: toHex(readMetaThemeColor()),
      pageBackgroundColor: resolvePageBackgroundColor(),
      prefersDarkScheme: !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches),
      supportsDarkAppearance: resolveSupportsDarkAppearance()
    };
  }

  function readMetaSignature() {
    try {
      return Array.from(document.querySelectorAll('meta[name="theme-color"], meta[name="color-scheme"]'))
        .map(function (node) {
          return [
            readAttribute(node, 'name'),
            readAttribute(node, 'media'),
            readAttribute(node, 'content')
          ].join('=');
        })
        .join('|');
    } catch (_error) {
      return '';
    }
  }

  function buildSignature(snapshot) {
    var root = document.documentElement;
    var body = document.body;
    return [
      readAttribute(root, 'class'),
      readAttribute(root, 'style'),
      readAttribute(root, 'data-theme'),
      readAttribute(root, 'data-color-mode'),
      readAttribute(root, 'data-color-scheme'),
      readAttribute(body, 'class'),
      readAttribute(body, 'style'),
      readAttribute(body, 'data-theme'),
      readAttribute(body, 'data-color-mode'),
      readAttribute(body, 'data-color-scheme'),
      readMetaSignature(),
      snapshot.themeColor,
      snapshot.pageBackgroundColor,
      snapshot.prefersDarkScheme ? 'prefersDark' : 'prefersLight',
      snapshot.supportsDarkAppearance ? 'supportsDark' : 'noDark'
    ].join('\\n');
  }

  function notify(reason) {
    try {
      var snapshot = buildSnapshot();
      var signature = buildSignature(snapshot);
      if (signature === lastSignature) {
        return;
      }
      var bridge = window.__airaPageChromeThemeNativeBridge;
      if (bridge && typeof bridge.onSignal === 'function') {
        bridge.onSignal(JSON.stringify({
          reason: String(reason || ''),
          timestamp: Date.now(),
          themeColor: snapshot.themeColor,
          pageBackgroundColor: snapshot.pageBackgroundColor,
          prefersDarkScheme: snapshot.prefersDarkScheme,
          supportsDarkAppearance: snapshot.supportsDarkAppearance
        }));
        lastSignature = signature;
        bridgeRetryCount = 0;
        if (bridgeRetryTimer >= 0) {
          clearTimeout(bridgeRetryTimer);
          bridgeRetryTimer = -1;
        }
        return;
      }
      if (bridgeRetryTimer < 0 && bridgeRetryCount < 12) {
        bridgeRetryCount += 1;
        bridgeRetryTimer = setTimeout(function () {
          bridgeRetryTimer = -1;
          notify(reason);
        }, 160);
      }
    } catch (_error) {
    }
  }

  function sampleAfterFrame(reason) {
    try {
      window.requestAnimationFrame(function () {
        notify(reason);
      });
    } catch (_error) {
      notify(reason);
    }
  }

  function schedule(reason, delayMs) {
    var delay = typeof delayMs === 'number' ? delayMs : 80;
    if (delay <= 0) {
      sampleAfterFrame(reason);
      return;
    }
    if (signalTimer < 0) {
      signalTimer = setTimeout(function () {
        signalTimer = -1;
        sampleAfterFrame(reason);
      }, delay);
      return;
    }
    if (trailingSignalTimer >= 0) {
      clearTimeout(trailingSignalTimer);
    }
    trailingSignalTimer = setTimeout(function () {
      trailingSignalTimer = -1;
      sampleAfterFrame(reason);
    }, Math.min(160, delay));
  }

  function scheduleFollowups(reason) {
    followupTimers.forEach(function (timer) {
      clearTimeout(timer);
    });
    followupTimers = [80, 240, 720, 1500].map(function (delay) {
      return setTimeout(function () {
        notify(reason);
      }, delay);
    });
  }

  function observeAttributes(node, reason) {
    try {
      if (!node || typeof MutationObserver !== 'function') {
        return;
      }
      var observer = new MutationObserver(function () {
        schedule(reason);
      });
      observer.observe(node, {
        attributes: true,
        attributeFilter: ['class', 'style', 'data-theme', 'data-color-mode', 'data-color-scheme']
      });
    } catch (_error) {
    }
  }

  function observeHead() {
    try {
      if (!document.head || typeof MutationObserver !== 'function') {
        return;
      }
      var observer = new MutationObserver(function () {
        schedule('meta');
      });
      observer.observe(document.head, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['name', 'content', 'media']
      });
    } catch (_error) {
    }
  }

  function observeBodyWhenReady() {
    if (document.body) {
      observeAttributes(document.body, 'body');
      schedule('body-ready');
      return;
    }
    document.addEventListener('DOMContentLoaded', function () {
      observeAttributes(document.body, 'body');
      schedule('body-ready');
    }, { once: true });
  }

  observeAttributes(document.documentElement, 'root');
  observeBodyWhenReady();
  observeHead();
  schedule('install', 180);
  scheduleFollowups('install');
  document.addEventListener('DOMContentLoaded', function () {
    schedule('dom-ready');
    scheduleFollowups('dom-ready');
  }, { once: true });
  window.addEventListener('load', function () {
    schedule('load');
    scheduleFollowups('load');
  }, { once: true });
  window.addEventListener('pageshow', function () {
    schedule('pageshow');
    scheduleFollowups('pageshow');
  }, true);
  try {
    if (window.matchMedia) {
      var query = window.matchMedia('(prefers-color-scheme: dark)');
      if (query && typeof query.addEventListener === 'function') {
        query.addEventListener('change', function () {
          schedule('color-scheme');
          scheduleFollowups('color-scheme');
        });
      }
    }
  } catch (_error) {
  }
})();
`;
const PAGE_BEHAVIOR_SIGNAL_SCRIPT: string = `
(function () {
  if (window.__airaPageBehaviorSignalInstalled === true) {
    try {
      if (typeof window.__airaPageBehaviorSignalForceSample === 'function') {
        window.__airaPageBehaviorSignalForceSample('reinjected');
      }
    } catch (_error) {
    }
    return;
  }
  window.__airaPageBehaviorSignalInstalled = true;
  var lastSignature = '';
  var notifyTimer = -1;
  var heartbeatTimer = -1;
  var bridgeRetryTimer = -1;
  var bridgeRetryCount = 0;
  var screenCaptureTrackCount = 0;
  var userEdited = false;
  var mediaPlaybackHintActive = false;
  var mediaPlaybackHintExpiresAt = 0;
  var trackedMediaElements = [];
  var trackedAudioContexts = [];
  var pendingMediaRoots = [];
  var pendingMediaRootIndex = 0;
  var pendingMediaRootTimer = -1;
  var pendingMediaFallbackDocuments = [];
  var videoGeometryTimer = -1;
  var videoDocumentEpoch = Date.now().toString(36);
  var nextVideoRuntimeSequence = 1;
  var videoRuntimeIdProperty = ${HOSTED_WEB_VIDEO_RUNTIME_ID_PROPERTY_LITERAL};
  var videoFullscreenRequestResultEvent = ${HOSTED_WEB_VIDEO_FULLSCREEN_REQUEST_RESULT_EVENT_LITERAL};
  var videoTimeUpdateSentAt = typeof WeakMap === 'function' ? new WeakMap() : null;
  var nativeAudioContextConstructor = null;
  var nativeWebkitAudioContextConstructor = null;

  // Child media probes may initialize before ArkWeb exposes the registered proxy in that frame.
  // Keep the channel handshake and signal relay in the host document, where the proxy is owned.
  window.addEventListener('message', function (event) {
    var payload = event && event.data;
    if (!payload || payload.protocol !== 'aira.media_frame_probe.v1' || !event.source) {
      return;
    }
    if (payload.kind === 'channel_request') {
      try {
        var videoBridge = window.__airaWebVideoControllerBridge;
        var raw = videoBridge && typeof videoBridge.readSystemControl === 'function' ?
          videoBridge.readSystemControl('aira_media_frame_probe_v1') : '{}';
        var snapshot = JSON.parse(String(raw || '{}'));
        event.source.postMessage({
          protocol: 'aira.media_frame_probe.v1',
          kind: 'channel_response',
          frameRuntimeId: String(payload.frameRuntimeId || ''),
          channelId: typeof snapshot.channelId === 'string' ? snapshot.channelId : ''
        }, '*');
      } catch (_channelRelayError) {
      }
      return;
    }
    if (payload.kind === 'signal_relay' && typeof payload.payloadJson === 'string') {
      try {
        var pageBridge = window.__airaPageBehaviorNativeBridge;
        if (pageBridge && typeof pageBridge.onSignal === 'function') {
          pageBridge.onSignal(payload.payloadJson);
        }
      } catch (_signalRelayError) {
      }
    }
  }, false);

  function isEditableElement(node) {
    if (!node || node === document || !node.tagName) {
      return false;
    }
    var tagName = String(node.tagName || '').toLowerCase();
    if (tagName === 'textarea') {
      return true;
    }
    if (tagName === 'input') {
      var type = String(node.type || '').toLowerCase();
      return ['button', 'checkbox', 'color', 'file', 'hidden', 'image', 'radio', 'range', 'reset', 'submit'].indexOf(type) < 0;
    }
    if (node.isContentEditable === true) {
      return true;
    }
    try {
      if (typeof node.getAttribute === 'function') {
        var role = String(node.getAttribute('role') || '').toLowerCase();
        if (role === 'textbox' || role === 'searchbox') {
          return true;
        }
        if (String(node.getAttribute('aria-multiline') || '').toLowerCase() === 'true') {
          return true;
        }
      }
    } catch (_error) {
    }
    return false;
  }

  function findEditableElement(node) {
    var current = node;
    var depth = 0;
    while (current && current !== document && depth < 12) {
      if (isEditableElement(current)) {
        return current;
      }
      if (current.parentElement) {
        current = current.parentElement;
      } else if (current.parentNode && current.parentNode !== current) {
        current = current.parentNode;
      } else {
        var root = typeof current.getRootNode === 'function' ? current.getRootNode() : null;
        current = root && root.host ? root.host : null;
      }
      depth += 1;
    }
    return null;
  }

  function readEditableText(node) {
    try {
      if (!node) {
        return '';
      }
      if (typeof node.value === 'string') {
        return node.value;
      }
      if (typeof node.innerText === 'string') {
        return node.innerText;
      }
      return String(node.textContent || '');
    } catch (_error) {
      return '';
    }
  }

  function hasFocusedEditableContent() {
    var active = findEditableElement(document.activeElement);
    return isEditableElement(active) && readEditableText(active).trim().length > 0;
  }

  function hasEditedContent() {
    try {
      var nodes = document.querySelectorAll('input, textarea, [contenteditable="true"], [contenteditable=""], [role="textbox"], [role="searchbox"], [aria-multiline="true"]');
      var limit = Math.min(nodes.length, 80);
      for (var index = 0; index < limit; index += 1) {
        var node = nodes[index];
        if (isEditableElement(node) && readEditableText(node).trim().length > 0) {
          return true;
        }
      }
    } catch (_error) {
    }
    return false;
  }

  function resolveVideoRuntimeId(node) {
    try {
      if (!node || String(node.tagName || '').toLowerCase() !== 'video') {
        return '';
      }
      var existing = String(node[videoRuntimeIdProperty] || '');
      if (existing.length > 0) {
        return existing;
      }
      var runtimeId = videoDocumentEpoch + ':' + String(nextVideoRuntimeSequence++);
      node[videoRuntimeIdProperty] = runtimeId;
      return runtimeId;
    } catch (_error) {
      return '';
    }
  }

  function resolveVideoFullscreenCapability(node) {
    try {
      if (!node || String(node.tagName || '').toLowerCase() !== 'video') {
        return 'none';
      }
      if (typeof node.requestFullscreen === 'function' ||
          typeof node.webkitRequestFullscreen === 'function' ||
          typeof node.mozRequestFullScreen === 'function' ||
          typeof node.msRequestFullscreen === 'function') {
        return 'standard';
      }
      if (typeof node.webkitEnterFullscreen === 'function' ||
          typeof node.webkitEnterFullScreen === 'function') {
        return 'webkit';
      }
    } catch (_error) {
    }
    return 'none';
  }

  function isVideoFullscreenActive(node) {
    try {
      if (!node || String(node.tagName || '').toLowerCase() !== 'video') {
        return false;
      }
      var ownerDocument = node.ownerDocument || document;
      var fullscreenElement = ownerDocument.fullscreenElement || ownerDocument.webkitFullscreenElement || null;
      return fullscreenElement === node || node.webkitDisplayingFullscreen === true;
    } catch (_error) {
      return false;
    }
  }

  function rememberMediaElement(node) {
    if (!node) {
      return;
    }
    try {
      resolveVideoRuntimeId(node);
      if (trackedMediaElements.indexOf(node) < 0) {
        trackedMediaElements.push(node);
      }
    } catch (_error) {
    }
  }

  function isMediaElementPlaying(node) {
    try {
      return !!node && node.paused === false && node.ended !== true && Number(node.readyState || 0) > 0;
    } catch (_error) {
      return false;
    }
  }

  function collectDocumentMediaElements(doc, depth) {
    try {
      if (!doc || depth > 2) {
        return;
      }
      var nodes = doc.querySelectorAll('audio, video');
      var limit = Math.min(nodes.length, 120);
      for (var index = 0; index < limit; index += 1) {
        rememberMediaElement(nodes[index]);
      }
      var frames = doc.querySelectorAll('iframe, frame');
      var frameLimit = Math.min(frames.length, 40);
      for (var frameIndex = 0; frameIndex < frameLimit; frameIndex += 1) {
        var frame = frames[frameIndex];
        collectDocumentMediaElements(frame.contentDocument, depth + 1);
      }
    } catch (_error) {
    }
  }

  function hasTrackedMediaElementPlaying() {
    var retained = [];
    var playing = false;
    try {
      trackedMediaElements.forEach(function (node) {
        if (!node) {
          return;
        }
        var connected = true;
        try {
          connected = node.isConnected !== false;
        } catch (_error) {
        }
        if (connected || isMediaElementPlaying(node)) {
          retained.push(node);
        }
        if (isMediaElementPlaying(node)) {
          playing = true;
        }
      });
    } catch (_error) {
    }
    trackedMediaElements = retained.slice(0, 120);
    return playing;
  }

  function hasTrackedVideoElementPlaying() {
    try {
      for (var index = 0; index < trackedMediaElements.length; index += 1) {
        var node = trackedMediaElements[index];
        if (String(node && node.tagName || '').toLowerCase() === 'video' && isMediaElementPlaying(node)) {
          return true;
        }
      }
    } catch (_error) {
    }
    return false;
  }

  function hasRunningAudioContext() {
    var retained = [];
    var playing = false;
    try {
      trackedAudioContexts.forEach(function (context) {
        if (!context) {
          return;
        }
        var state = String(context.state || '').toLowerCase();
        if (state !== 'closed') {
          retained.push(context);
        }
        if (state === 'running') {
          playing = true;
        }
      });
    } catch (_error) {
    }
    trackedAudioContexts = retained.slice(0, 40);
    return playing;
  }

  function hasRecentMediaPlaybackHint() {
    return mediaPlaybackHintActive && Date.now() < mediaPlaybackHintExpiresAt;
  }

  function refreshMediaPlaybackHint(active, reason) {
    mediaPlaybackHintActive = active === true;
    mediaPlaybackHintExpiresAt = mediaPlaybackHintActive ? Date.now() + 15000 : 0;
    schedule(reason || 'media_hint', 40);
  }

  function hasPlayingMedia() {
    try {
      return hasTrackedMediaElementPlaying() || hasRunningAudioContext() || hasRecentMediaPlaybackHint();
    } catch (_error) {
    }
    return false;
  }

  function buildSnapshot(reason) {
    var editing = hasFocusedEditableContent() || (userEdited && hasEditedContent());
    if (!editing && userEdited) {
      userEdited = false;
    }
    return {
      source: String(reason || 'sample'),
      timestamp: Date.now(),
      isScreenCapture: screenCaptureTrackCount > 0,
      isMediaPlaying: hasPlayingMedia(),
      isVideoPlaying: hasTrackedVideoElementPlaying(),
      isUserEditing: editing
    };
  }

  function buildVideoPlaybackEvent(node, eventName, sourceEvent) {
    try {
      if (String(node && node.tagName || '').toLowerCase() !== 'video') {
        return null;
      }
      var rect = readVideoViewportRect(node);
      var requestDetail = sourceEvent && sourceEvent.detail && typeof sourceEvent.detail === 'object' ?
        sourceEvent.detail : null;
      return {
        eventName: String(eventName || ''),
        runtimeId: resolveVideoRuntimeId(node),
        elementId: String(node.id || ''),
        source: String(node.currentSrc || node.src || ''),
        fullscreenCapability: resolveVideoFullscreenCapability(node),
        fullscreenActive: isVideoFullscreenActive(node),
        fullscreenAttemptId: requestDetail && Number.isFinite(Number(requestDetail.attemptId)) ?
          Number(requestDetail.attemptId) : 0,
        fullscreenRequestStatus: requestDetail ? String(requestDetail.status || '') : '',
        muted: node.muted === true || Number(node.volume || 0) <= 0,
        paused: node.paused !== false,
        ended: node.ended === true,
        seeking: node.seeking === true,
        readyState: Number.isFinite(Number(node.readyState)) ? Math.max(0, Number(node.readyState)) : 0,
        networkState: Number.isFinite(Number(node.networkState)) ? Math.max(0, Number(node.networkState)) : 0,
        visible: isVideoVisible(node, rect),
        rect: rect,
        viewportWidth: Math.max(1, Number(window.innerWidth || document.documentElement.clientWidth || 1)),
        viewportHeight: Math.max(1, Number(window.innerHeight || document.documentElement.clientHeight || 1)),
        videoWidth: Number.isFinite(Number(node.videoWidth)) ? Math.max(0, Number(node.videoWidth)) : 0,
        videoHeight: Number.isFinite(Number(node.videoHeight)) ? Math.max(0, Number(node.videoHeight)) : 0,
        currentTime: Number.isFinite(Number(node.currentTime)) ? Number(node.currentTime) : 0,
        duration: Number.isFinite(Number(node.duration)) ? Number(node.duration) : 0
      };
    } catch (_error) {
      return null;
    }
  }

  function readVideoViewportRect(node) {
    try {
      var sourceRect = node.getBoundingClientRect();
      var left = Number(sourceRect.left || 0);
      var top = Number(sourceRect.top || 0);
      var width = Math.max(0, Number(sourceRect.width || 0));
      var height = Math.max(0, Number(sourceRect.height || 0));
      var ownerView = node.ownerDocument && node.ownerDocument.defaultView;
      var depth = 0;
      while (ownerView && ownerView !== window && depth < 4) {
        var frame = ownerView.frameElement;
        if (!frame || typeof frame.getBoundingClientRect !== 'function') {
          break;
        }
        var frameRect = frame.getBoundingClientRect();
        if (Number(frameRect.width || 0) < 2 || Number(frameRect.height || 0) < 2) {
          return { x: 0, y: 0, width: 0, height: 0 };
        }
        var layoutWidth = Math.max(1, Number(frame.offsetWidth || frame.clientWidth || frameRect.width || 1));
        var layoutHeight = Math.max(1, Number(frame.offsetHeight || frame.clientHeight || frameRect.height || 1));
        var frameScaleX = Math.max(0.01, Number(frameRect.width || 0) / layoutWidth);
        var frameScaleY = Math.max(0.01, Number(frameRect.height || 0) / layoutHeight);
        left = Number(frameRect.left || 0) + Number(frame.clientLeft || 0) * frameScaleX + left * frameScaleX;
        top = Number(frameRect.top || 0) + Number(frame.clientTop || 0) * frameScaleY + top * frameScaleY;
        width *= frameScaleX;
        height *= frameScaleY;
        ownerView = frame.ownerDocument && frame.ownerDocument.defaultView;
        depth += 1;
      }
      return {
        x: Number.isFinite(left) ? left : 0,
        y: Number.isFinite(top) ? top : 0,
        width: Number.isFinite(width) ? width : 0,
        height: Number.isFinite(height) ? height : 0
      };
    } catch (_error) {
      return { x: 0, y: 0, width: 0, height: 0 };
    }
  }

  function isVideoVisible(node, rect) {
    try {
      if (!rect || rect.width < 2 || rect.height < 2) {
        return false;
      }
      var viewportWidth = Math.max(1, Number(window.innerWidth || document.documentElement.clientWidth || 1));
      var viewportHeight = Math.max(1, Number(window.innerHeight || document.documentElement.clientHeight || 1));
      if (rect.x + rect.width <= 0 || rect.y + rect.height <= 0 ||
          rect.x >= viewportWidth || rect.y >= viewportHeight) {
        return false;
      }
      var ownerView = node.ownerDocument && node.ownerDocument.defaultView;
      var style = ownerView && typeof ownerView.getComputedStyle === 'function' ? ownerView.getComputedStyle(node) : null;
      if (style && (style.display === 'none' || style.visibility === 'hidden' ||
          Number.parseFloat(style.opacity || '1') <= 0.02)) {
        return false;
      }
      return true;
    } catch (_error) {
      return false;
    }
  }

  function sendVideoPlaybackEvent(node, eventName, sourceEvent) {
    try {
      var videoEvent = buildVideoPlaybackEvent(node, eventName, sourceEvent);
      if (!videoEvent) {
        return;
      }
      var snapshot = buildSnapshot('video_' + String(eventName || 'event'));
      snapshot.videoEvent = videoEvent;
      sendSnapshot(snapshot, true);
    } catch (_error) {
    }
  }

  function sendVideoTimeUpdateIfDue(node) {
    try {
      if (!isMediaElementPlaying(node)) {
        return;
      }
      var now = Date.now();
      var lastSentAt = videoTimeUpdateSentAt ? Number(videoTimeUpdateSentAt.get(node) || 0) : 0;
      if (now - lastSentAt < 500) {
        return;
      }
      if (videoTimeUpdateSentAt) {
        videoTimeUpdateSentAt.set(node, now);
      }
      sendVideoPlaybackEvent(node, 'timeupdate');
    } catch (_error) {
    }
  }

  function sendPlayingVideoGeometry(reason) {
    var sent = 0;
    try {
      trackedMediaElements.forEach(function (node) {
        if (sent >= 8 || String(node && node.tagName || '').toLowerCase() !== 'video' ||
            !isMediaElementPlaying(node)) {
          return;
        }
        sendVideoPlaybackEvent(node, reason || 'geometry');
        sent += 1;
      });
    } catch (_error) {
    }
  }

  function scheduleVideoGeometryRefresh(reason) {
    if (videoGeometryTimer >= 0) {
      clearTimeout(videoGeometryTimer);
    }
    videoGeometryTimer = setTimeout(function () {
      videoGeometryTimer = -1;
      try {
        window.requestAnimationFrame(function () {
          sendPlayingVideoGeometry(reason);
        });
      } catch (_error) {
        sendPlayingVideoGeometry(reason);
      }
    }, 80);
  }

  function installVideoGeometryListeners(doc) {
    if (!doc) {
      return;
    }
    try {
      if (doc.__airaPageBehaviorVideoGeometryTracked === true) {
        return;
      }
      doc.__airaPageBehaviorVideoGeometryTracked = true;
      doc.addEventListener('scroll', function () {
        scheduleVideoGeometryRefresh('geometry_scroll');
      }, true);
      ['fullscreenchange', 'webkitfullscreenchange'].forEach(function (eventName) {
        doc.addEventListener(eventName, function () {
          try {
            var fullscreenElement = doc.fullscreenElement || doc.webkitFullscreenElement || null;
            if (String(fullscreenElement && fullscreenElement.tagName || '').toLowerCase() === 'video') {
              sendVideoPlaybackEvent(fullscreenElement, eventName);
            }
          } catch (_fullscreenError) {
          }
        }, true);
      });
      var view = doc.defaultView;
      if (!view || typeof view.addEventListener !== 'function') {
        return;
      }
      view.addEventListener('resize', function () {
        scheduleVideoGeometryRefresh('geometry_resize');
      }, true);
      view.addEventListener('orientationchange', function () {
        scheduleVideoGeometryRefresh('geometry_orientation');
      }, true);
    } catch (_error) {
    }
  }

  function buildSignature(snapshot) {
    return [
      snapshot.isScreenCapture ? 'screen' : 'noScreen',
      snapshot.isMediaPlaying ? 'media' : 'noMedia',
      snapshot.isVideoPlaying ? 'video' : 'noVideo',
      snapshot.isUserEditing ? 'editing' : 'noEditing'
    ].join('|');
  }

  function sendSnapshot(snapshot, force) {
    try {
      var signature = buildSignature(snapshot);
      if (force !== true && signature === lastSignature) {
        syncHeartbeat(snapshot);
        return;
      }
      var bridge = window.__airaPageBehaviorNativeBridge;
      if (bridge && typeof bridge.onSignal === 'function') {
        bridge.onSignal(JSON.stringify(snapshot));
        lastSignature = signature;
        bridgeRetryCount = 0;
        if (bridgeRetryTimer >= 0) {
          clearTimeout(bridgeRetryTimer);
          bridgeRetryTimer = -1;
        }
        syncHeartbeat(snapshot);
        return;
      }
      if (bridgeRetryTimer < 0 && bridgeRetryCount < 12) {
        bridgeRetryCount += 1;
        bridgeRetryTimer = setTimeout(function () {
          bridgeRetryTimer = -1;
          sendSnapshot(snapshot, force);
        }, 160);
      }
    } catch (_error) {
    }
  }

  function shouldRecoverPlayingVideoIdentity(reason) {
    var source = String(reason || '');
    return source === 'heartbeat' || source === 'reinjected' || source === 'install' ||
      source === 'media_probe_install' || source === 'media_added_playing' || source === 'pageshow' ||
      source === 'visibility' || source === 'dom_ready';
  }

  function notify(reason, force) {
    var snapshot = buildSnapshot(reason);
    if (snapshot.isVideoPlaying && shouldRecoverPlayingVideoIdentity(reason)) {
      sendPlayingVideoGeometry('playing');
    }
    sendSnapshot(snapshot, force === true);
  }

  window.__airaPageBehaviorSignalForceSample = function (reason) {
    notify(String(reason || 'external'), true);
  };

  function schedule(reason, delayMs) {
    var delay = typeof delayMs === 'number' ? delayMs : 80;
    if (notifyTimer >= 0) {
      clearTimeout(notifyTimer);
    }
    notifyTimer = setTimeout(function () {
      notifyTimer = -1;
      notify(reason, false);
    }, delay);
  }

  function syncHeartbeat(snapshot) {
    var active = snapshot.isScreenCapture || snapshot.isMediaPlaying || snapshot.isUserEditing;
    if (!active) {
      if (heartbeatTimer >= 0) {
        clearTimeout(heartbeatTimer);
        heartbeatTimer = -1;
      }
      return;
    }
    if (heartbeatTimer >= 0) {
      return;
    }
    heartbeatTimer = setTimeout(function () {
      heartbeatTimer = -1;
      notify('heartbeat', true);
    }, 5000);
  }

  function markEditing(reason) {
    userEdited = true;
    schedule(reason || 'editing', 40);
  }

  function clearEditingIfEmpty(reason) {
    if (!hasEditedContent() && !hasFocusedEditableContent()) {
      userEdited = false;
    }
    schedule(reason || 'editing_check', 80);
  }

  function trackScreenCaptureStream(stream) {
    try {
      if (!stream || typeof stream.getTracks !== 'function') {
        return;
      }
      var tracks = stream.getTracks();
      if (!tracks || tracks.length <= 0) {
        return;
      }
      screenCaptureTrackCount += tracks.length;
      notify('screen_capture_start', true);
      tracks.forEach(function (track) {
        var ended = false;
        var finish = function () {
          if (ended) {
            return;
          }
          ended = true;
          screenCaptureTrackCount = Math.max(0, screenCaptureTrackCount - 1);
          notify('screen_capture_end', true);
        };
        try {
          track.addEventListener('ended', finish, { once: true });
        } catch (_error) {
        }
      });
    } catch (_error) {
    }
  }

  function installScreenCaptureProbe() {
    try {
      var devices = navigator.mediaDevices;
      if (!devices || typeof devices.getDisplayMedia !== 'function' || devices.getDisplayMedia.__airaWrapped === true) {
        return;
      }
      var originalGetDisplayMedia = devices.getDisplayMedia.bind(devices);
      var wrappedGetDisplayMedia = function () {
        var result = originalGetDisplayMedia.apply(devices, arguments);
        if (result && typeof result.then === 'function') {
          return result.then(function (stream) {
            trackScreenCaptureStream(stream);
            return stream;
          });
        }
        trackScreenCaptureStream(result);
        return result;
      };
      wrappedGetDisplayMedia.__airaWrapped = true;
      devices.getDisplayMedia = wrappedGetDisplayMedia;
    } catch (_error) {
    }
  }

  function attachMediaElementListeners(node) {
    try {
      if (!node || node.__airaPageBehaviorMediaTracked === true) {
        return;
      }
      node.__airaPageBehaviorMediaTracked = true;
      rememberMediaElement(node);
      ['loadstart', 'loadedmetadata', 'canplay', 'canplaythrough', 'playing', 'play', 'timeupdate',
        'waiting', 'stalled', 'seeking', 'seeked', 'pause', 'ended', 'emptied', 'abort', 'error', 'volumechange',
        'fullscreenerror', 'webkitfullscreenerror', videoFullscreenRequestResultEvent,
        'webkitbeginfullscreen', 'webkitendfullscreen'].forEach(function (eventName) {
        node.addEventListener(eventName, function (event) {
          if (eventName === 'timeupdate') {
            sendVideoTimeUpdateIfDue(node);
          } else {
            sendVideoPlaybackEvent(node, eventName, event);
          }
          if (eventName === 'pause' || eventName === 'ended' || eventName === 'emptied' || eventName === 'abort' ||
            eventName === 'error') {
            refreshMediaPlaybackHint(hasTrackedMediaElementPlaying() || hasRunningAudioContext(), 'media_' + eventName);
            return;
          }
          if (eventName === 'loadstart' || eventName === 'loadedmetadata' || eventName === 'canplay' ||
            eventName === 'canplaythrough' || eventName === 'waiting' || eventName === 'stalled' ||
            eventName === 'seeking' || eventName === 'seeked') {
            return;
          }
          refreshMediaPlaybackHint(true, 'media_' + eventName);
        }, true);
      });
    } catch (_error) {
    }
  }

  function attachKnownMediaElements() {
    try {
      collectDocumentMediaElements(document, 0);
      trackedMediaElements.forEach(function (node) {
        attachMediaElementListeners(node);
      });
      var frames = document.querySelectorAll('iframe, frame');
      var frameLimit = Math.min(frames.length, 40);
      for (var frameIndex = 0; frameIndex < frameLimit; frameIndex += 1) {
        attachFrameMediaElements(frames[frameIndex], 0);
      }
    } catch (_error) {
    }
  }

  function attachFrameMediaElements(frame, depth) {
    if (!frame || depth > 2) {
      return false;
    }
    try {
      if (frame.__airaPageBehaviorFrameTracked !== true) {
        frame.__airaPageBehaviorFrameTracked = true;
        frame.addEventListener('load', function () {
          try {
            var frameDocument = frame.contentDocument;
            observeMediaDocument(frameDocument, depth + 1);
            enqueueMediaRoot(frameDocument, depth + 1, frameDocument);
          } catch (_error) {
          }
        }, true);
      }
      var frameDocument = frame.contentDocument;
      observeMediaDocument(frameDocument, depth + 1);
      enqueueMediaRoot(frameDocument, depth + 1, frameDocument);
      return false;
    } catch (_error) {
      return false;
    }
  }

  function inspectMediaElementNode(node, depth) {
    if (!node || depth > 2) {
      return false;
    }
    var found = false;
    try {
      var tagName = String(node.tagName || '').toLowerCase();
      if (tagName === 'audio' || tagName === 'video') {
        attachMediaElementListeners(node);
        found = true;
      } else if (tagName === 'iframe' || tagName === 'frame') {
        found = attachFrameMediaElements(node, depth) || found;
      }
    } catch (_error) {
    }
    return found;
  }

  function createMediaTreeWalker(root) {
    try {
      var doc = root && root.nodeType === 9 ? root : (root ? root.ownerDocument : null);
      if (!doc || typeof doc.createTreeWalker !== 'function') {
        return null;
      }
      return doc.createTreeWalker(root, 1, null);
    } catch (_error) {
      return null;
    }
  }

  function schedulePendingMediaRoots() {
    if (pendingMediaRootTimer < 0 && pendingMediaRootIndex < pendingMediaRoots.length) {
      pendingMediaRootTimer = setTimeout(processPendingMediaRoots, 40);
    }
  }

  function queueMediaFallbackDocument(doc, depth) {
    if (!doc || depth > 2) {
      return;
    }
    try {
      if (doc.__airaPageBehaviorMediaFallbackQueued === true) {
        return;
      }
      doc.__airaPageBehaviorMediaFallbackQueued = true;
    } catch (_error) {
    }
    pendingMediaFallbackDocuments.push({
      node: doc,
      depth: depth
    });
  }

  function enqueueMediaRoot(node, depth, fallbackDocument) {
    if (!node || depth > 2) {
      return true;
    }
    try {
      if (node.__airaPageBehaviorMediaRootQueued === true) {
        return true;
      }
    } catch (_error) {
    }
    if (pendingMediaRoots.length - pendingMediaRootIndex >= 512) {
      queueMediaFallbackDocument(fallbackDocument || node.ownerDocument || document, depth);
      return false;
    }
    try {
      node.__airaPageBehaviorMediaRootQueued = true;
    } catch (_error) {
    }
    pendingMediaRoots.push({
      node: node,
      depth: depth,
      inspected: false,
      walker: null
    });
    schedulePendingMediaRoots();
    return true;
  }

  function processPendingMediaRoots() {
    pendingMediaRootTimer = -1;
    var found = false;
    try {
      var remainingElementBudget = 48;
      while (pendingMediaRootIndex < pendingMediaRoots.length && remainingElementBudget > 0) {
        var entry = pendingMediaRoots[pendingMediaRootIndex];
        if (entry.inspected !== true) {
          found = inspectMediaElementNode(entry.node, entry.depth) || found;
          entry.inspected = true;
          entry.walker = createMediaTreeWalker(entry.node);
          remainingElementBudget -= 1;
        }
        if (remainingElementBudget <= 0) {
          break;
        }
        var nextNode = entry.walker && typeof entry.walker.nextNode === 'function' ? entry.walker.nextNode() : null;
        if (nextNode) {
          found = inspectMediaElementNode(nextNode, entry.depth) || found;
          remainingElementBudget -= 1;
          continue;
        }
        try {
          entry.node.__airaPageBehaviorMediaRootQueued = false;
        } catch (_error) {
        }
        pendingMediaRootIndex += 1;
      }
      if (found && hasTrackedMediaElementPlaying()) {
        refreshMediaPlaybackHint(true, 'media_added_playing');
      }
    } catch (_error) {
    }
    if (pendingMediaRootIndex < pendingMediaRoots.length) {
      if (pendingMediaRootIndex >= 256) {
        pendingMediaRoots = pendingMediaRoots.slice(pendingMediaRootIndex);
        pendingMediaRootIndex = 0;
      }
      pendingMediaRootTimer = setTimeout(processPendingMediaRoots, 40);
      return;
    }
    pendingMediaRoots = [];
    pendingMediaRootIndex = 0;
    if (pendingMediaFallbackDocuments.length > 0) {
      var fallbackDocuments = pendingMediaFallbackDocuments;
      pendingMediaFallbackDocuments = [];
      for (var fallbackIndex = 0; fallbackIndex < fallbackDocuments.length; fallbackIndex += 1) {
        var fallback = fallbackDocuments[fallbackIndex];
        try {
          fallback.node.__airaPageBehaviorMediaFallbackQueued = false;
        } catch (_error) {
        }
        enqueueMediaRoot(fallback.node, fallback.depth, fallback.node);
      }
    }
  }

  function enqueueAddedMediaElements(mutations, depth, observedDocument) {
    if (depth > 2) {
      return;
    }
    try {
      var mutationCount = mutations ? mutations.length : 0;
      for (var mutationIndex = 0; mutationIndex < mutationCount; mutationIndex += 1) {
        var addedNodes = mutations[mutationIndex].addedNodes;
        var addedCount = addedNodes ? addedNodes.length : 0;
        for (var nodeIndex = 0; nodeIndex < addedCount; nodeIndex += 1) {
          var node = addedNodes[nodeIndex];
          if (!enqueueMediaRoot(node, depth, observedDocument)) {
            return;
          }
        }
      }
    } catch (_error) {
    }
  }

  function observeMediaDocument(doc, depth) {
    if (!doc || depth > 2) {
      return;
    }
    installVideoGeometryListeners(doc);
    if (typeof MutationObserver !== 'function') {
      return;
    }
    try {
      if (doc.__airaPageBehaviorMediaDocumentObserved === true) {
        return;
      }
      doc.__airaPageBehaviorMediaDocumentObserved = true;
      var observer = new MutationObserver(function (mutations) {
        enqueueAddedMediaElements(mutations, depth, doc);
      });
      observer.observe(doc.documentElement || doc, {
        childList: true,
        subtree: true
      });
      doc.__airaPageBehaviorMediaObserver = observer;
    } catch (_error) {
    }
  }

  function trackAudioContext(context, reason) {
    try {
      if (!context) {
        return context;
      }
      if (trackedAudioContexts.indexOf(context) < 0) {
        trackedAudioContexts.push(context);
      }
      if (context.__airaPageBehaviorAudioContextTracked !== true) {
        context.__airaPageBehaviorAudioContextTracked = true;
        if (typeof context.addEventListener === 'function') {
          context.addEventListener('statechange', function () {
            refreshMediaPlaybackHint(hasRunningAudioContext() || hasTrackedMediaElementPlaying(), 'web_audio_statechange');
          });
        }
      }
      refreshMediaPlaybackHint(hasRunningAudioContext() || hasTrackedMediaElementPlaying(), reason || 'web_audio_context');
    } catch (_error) {
    }
    return context;
  }

  function wrapAudioContextConstructor(name) {
    try {
      var OriginalConstructor = window[name];
      if (typeof OriginalConstructor !== 'function' || OriginalConstructor.__airaWrapped === true) {
        return;
      }
      var WrappedConstructor = function () {
        var context = new (Function.prototype.bind.apply(OriginalConstructor, [null].concat(Array.prototype.slice.call(arguments))))();
        return trackAudioContext(context, 'web_audio_context_created');
      };
      WrappedConstructor.prototype = OriginalConstructor.prototype;
      Object.keys(OriginalConstructor).forEach(function (key) {
        try {
          WrappedConstructor[key] = OriginalConstructor[key];
        } catch (_error) {
        }
      });
      WrappedConstructor.__airaWrapped = true;
      window[name] = WrappedConstructor;
      if (name === 'AudioContext') {
        nativeAudioContextConstructor = OriginalConstructor;
      } else if (name === 'webkitAudioContext') {
        nativeWebkitAudioContextConstructor = OriginalConstructor;
      }
    } catch (_error) {
    }
  }

  function wrapAudioContextPrototype(Constructor) {
    try {
      if (!Constructor || !Constructor.prototype || Constructor.prototype.__airaPageBehaviorWrapped === true) {
        return;
      }
      Constructor.prototype.__airaPageBehaviorWrapped = true;
      ['resume', 'suspend', 'close'].forEach(function (methodName) {
        var original = Constructor.prototype[methodName];
        if (typeof original !== 'function') {
          return;
        }
        Constructor.prototype[methodName] = function () {
          var context = this;
          var result = original.apply(context, arguments);
          var report = function () {
            trackAudioContext(context, 'web_audio_' + methodName);
          };
          if (result && typeof result.then === 'function') {
            result.then(report, report);
          } else {
            report();
          }
          return result;
        };
      });
    } catch (_error) {
    }
  }

  function wrapMediaElementPlay() {
    try {
      var prototype = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
      if (!prototype || prototype.__airaPageBehaviorPlayWrapped === true) {
        return;
      }
      prototype.__airaPageBehaviorPlayWrapped = true;
      var originalPlay = prototype.play;
      var originalPause = prototype.pause;
      if (typeof originalPlay === 'function') {
        prototype.play = function () {
          attachMediaElementListeners(this);
          refreshMediaPlaybackHint(true, 'media_play_method');
          var result = originalPlay.apply(this, arguments);
          if (result && typeof result.then === 'function') {
            result.then(function () {
              refreshMediaPlaybackHint(true, 'media_play_resolved');
            }, function () {
              refreshMediaPlaybackHint(hasTrackedMediaElementPlaying() || hasRunningAudioContext(), 'media_play_rejected');
            });
          }
          return result;
        };
      }
      if (typeof originalPause === 'function') {
        prototype.pause = function () {
          var result = originalPause.apply(this, arguments);
          refreshMediaPlaybackHint(hasTrackedMediaElementPlaying() || hasRunningAudioContext(), 'media_pause_method');
          return result;
        };
      }
    } catch (_error) {
    }
  }

  function installMediaPlaybackProbe() {
    attachKnownMediaElements();
    wrapMediaElementPlay();
    wrapAudioContextConstructor('AudioContext');
    wrapAudioContextConstructor('webkitAudioContext');
    wrapAudioContextPrototype(nativeAudioContextConstructor || window.AudioContext);
    wrapAudioContextPrototype(nativeWebkitAudioContextConstructor || window.webkitAudioContext);
    schedule('media_probe_install', 120);
  }

  function notifyPageHide() {
    screenCaptureTrackCount = 0;
    userEdited = false;
    if (pendingMediaRootTimer >= 0) {
      clearTimeout(pendingMediaRootTimer);
      pendingMediaRootTimer = -1;
    }
    if (videoGeometryTimer >= 0) {
      clearTimeout(videoGeometryTimer);
      videoGeometryTimer = -1;
    }
    for (var pendingIndex = pendingMediaRootIndex; pendingIndex < pendingMediaRoots.length; pendingIndex += 1) {
      try {
        pendingMediaRoots[pendingIndex].node.__airaPageBehaviorMediaRootQueued = false;
      } catch (_error) {
      }
    }
    for (var fallbackIndex = 0; fallbackIndex < pendingMediaFallbackDocuments.length; fallbackIndex += 1) {
      try {
        pendingMediaFallbackDocuments[fallbackIndex].node.__airaPageBehaviorMediaFallbackQueued = false;
      } catch (_error) {
      }
    }
    pendingMediaRoots = [];
    pendingMediaRootIndex = 0;
    pendingMediaFallbackDocuments = [];
    sendSnapshot({
      source: 'pagehide',
      timestamp: Date.now(),
      isScreenCapture: false,
      isMediaPlaying: false,
      isVideoPlaying: false,
      isUserEditing: false
    }, true);
  }

  ['loadstart', 'loadedmetadata', 'canplay', 'canplaythrough', 'playing', 'play', 'waiting', 'stalled',
    'seeking', 'seeked', 'pause', 'ended', 'emptied', 'abort', 'error', 'volumechange'].forEach(function (eventName) {
    document.addEventListener(eventName, function (event) {
      attachMediaElementListeners(event.target);
      if (eventName === 'playing' || eventName === 'play') {
        refreshMediaPlaybackHint(true, 'media_' + eventName);
        return;
      }
      if (eventName === 'pause' || eventName === 'ended' || eventName === 'emptied' || eventName === 'abort' ||
        eventName === 'error') {
        refreshMediaPlaybackHint(hasTrackedMediaElementPlaying() || hasRunningAudioContext(), 'media_' + eventName);
        return;
      }
      schedule('media_' + eventName, 40);
    }, true);
  });
  ['input', 'beforeinput', 'change', 'compositionend', 'paste', 'cut', 'keyup'].forEach(function (eventName) {
    document.addEventListener(eventName, function (event) {
      if (findEditableElement(event.target) || hasFocusedEditableContent() || hasEditedContent()) {
        markEditing('editing_' + eventName);
      }
    }, true);
  });
  document.addEventListener('focusin', function (event) {
    if (findEditableElement(event.target)) {
      clearEditingIfEmpty('editing_focus');
    }
  }, true);
  document.addEventListener('focusout', function () {
    clearEditingIfEmpty('editing_blur');
  }, true);
  document.addEventListener('reset', function () {
    userEdited = false;
    schedule('editing_reset', 40);
  }, true);
  document.addEventListener('visibilitychange', function () {
    schedule('visibility', 80);
  }, true);
  window.addEventListener('pageshow', function (event) {
    if (event && event.persisted === true) {
      attachKnownMediaElements();
    }
    schedule('pageshow', 80);
  }, true);
  window.addEventListener('pagehide', notifyPageHide, true);
  observeMediaDocument(document, 0);
  installMediaPlaybackProbe();
  installScreenCaptureProbe();
  schedule('install', 160);
  document.addEventListener('DOMContentLoaded', function () {
    schedule('dom_ready', 80);
  }, { once: true });
})();
`;
const WEB_LINK_DRAG_SUPPRESSION_SCRIPTS: ScriptItem[] = [{
  script: WEB_LINK_DRAG_SUPPRESSION_SCRIPT,
  scriptRules: ['.*']
}, {
  script: USER_SCRIPT_INSTALL_LINK_CAPTURE_SCRIPT,
  scriptRules: ['.*']
}, {
  script: WEB_FILE_SAVE_PICKER_COMPAT_SCRIPT,
  scriptRules: ['.*']
}];

class HostedWebNodeNoopUserScriptBridge {
  request(_payloadJson: string): void {
  }

  readValue(_payloadJson: string): string {
    return '{"success":false,"error":"userscript-bridge-unavailable"}';
  }

  openInTab(_payloadJson: string): void {
  }

  abort(_requestId: string): void {
  }

  installUserScript(_url: string): void {
  }
}

const HOSTED_WEB_NODE_NOOP_USER_SCRIPT_BRIDGE: HostedWebNodeNoopUserScriptBridge =
  new HostedWebNodeNoopUserScriptBridge();

class HostedWebNodePageBehaviorBridge {
  private signalHandler: ((payloadJson: string) => void) | undefined;

  bind(signalHandler: (payloadJson: string) => void): void {
    this.signalHandler = signalHandler;
  }

  unbind(): void {
    this.signalHandler = undefined;
  }

  onSignal(payloadJson: string): void {
    this.signalHandler?.(payloadJson);
  }
}

class HostedWebNodeNativeBridge {
  private tabId: string = '';
  private userScriptRuntimeBridge: Object = HOSTED_WEB_NODE_NOOP_USER_SCRIPT_BRIDGE;
  private callbacks: HostedWebNodeCallbacks | undefined;
  private webVideoRuntimeBridge: HostedWebVideoControllerBridge | undefined;

  bind(config: HostedWebNodeConfig): void {
    this.tabId = config.tabId;
    this.userScriptRuntimeBridge = config.userScriptNativeBridge ?? HOSTED_WEB_NODE_NOOP_USER_SCRIPT_BRIDGE;
    this.callbacks = config.callbacks;
    this.webVideoRuntimeBridge = config.webVideoControllerBridge;
  }

  unbind(): void {
    this.tabId = '';
    this.userScriptRuntimeBridge = HOSTED_WEB_NODE_NOOP_USER_SCRIPT_BRIDGE;
    this.callbacks = undefined;
    this.webVideoRuntimeBridge = undefined;
  }

  request(payloadJson: string): void {
    const bridge = this.userScriptRuntimeBridge as HostedWebNodeNoopUserScriptBridge;
    bridge.request(payloadJson);
  }

  readValue(payloadJson: string): string {
    const bridge = this.userScriptRuntimeBridge as HostedWebNodeNoopUserScriptBridge;
    return bridge.readValue(payloadJson);
  }

  openInTab(payloadJson: string): void {
    const bridge = this.userScriptRuntimeBridge as HostedWebNodeNoopUserScriptBridge;
    bridge.openInTab(payloadJson);
  }

  abort(payloadJson: string): void {
    const bridge = this.userScriptRuntimeBridge as HostedWebNodeNoopUserScriptBridge;
    bridge.abort(payloadJson);
  }

  installUserScript(url: string): void {
    this.callbacks?.onUserScriptInstallRequest(this.tabId, url);
  }

  historyApiUrlChange(payloadJson: string): void {
    this.callbacks?.onHistoryApiUrlChange(this.tabId, payloadJson);
  }

  pageChromeThemeSignal(payloadJson: string): void {
    this.callbacks?.onPageChromeThemeSignal(this.tabId, payloadJson);
  }

  adBlockCosmeticHidden(payloadJson: string): void {
    this.callbacks?.onAdBlockCosmeticHidden(this.tabId, payloadJson);
  }

  adBlockManualHidden(payloadJson: string): void {
    this.callbacks?.onAdBlockManualHidden(this.tabId, payloadJson);
  }

  webVideoEnterFullscreen(payloadJson: string = '{}'): void {
    hilog.info(
      HOSTED_WEB_NODE_LOG_DOMAIN,
      HOSTED_WEB_NODE_LOG_TAG,
      'web_video_fullscreen_bridge tab=%{public}s payloadLength=%{public}d',
      this.tabId,
      payloadJson.length
    );
    this.webVideoRuntimeBridge?.enterFullscreen(this.tabId, payloadJson);
  }

  webVideoExitFullscreen(): void {
    this.webVideoRuntimeBridge?.exitFullscreen(this.tabId);
  }

  webVideoCast(payloadJson: string): void {
    hilog.info(
      HOSTED_WEB_NODE_LOG_DOMAIN,
      HOSTED_WEB_NODE_LOG_TAG,
      'web_video_cast_bridge tab=%{public}s payloadLength=%{public}d',
      this.tabId,
      payloadJson.length
    );
    this.webVideoRuntimeBridge?.cast(this.tabId, payloadJson);
  }

  webVideoReadSystemControl(kind: string): string {
    return this.webVideoRuntimeBridge?.readSystemControl(this.tabId, kind) ?? '{}';
  }

  webVideoSetSystemControl(payloadJson: string): string {
    return this.webVideoRuntimeBridge?.setSystemControl(this.tabId, payloadJson) ?? '{}';
  }

  webVideoClose(): void {
    this.webVideoRuntimeBridge?.close(this.tabId);
  }
}

const HOSTED_WEB_NODE_NOOP_NATIVE_BRIDGE: HostedWebNodeNativeBridge = new HostedWebNodeNativeBridge();

function enableWholeWebPageDrawingForPreviews(): void {
  try {
    webview.WebviewController.enableWholeWebPageDrawing();
  } catch (_error) {
  }
}

enableWholeWebPageDrawingForPreviews();

function resolveHostedWebAppearancePolicy(config: HostedWebNodeConfig): WebAppearancePolicy {
  return resolveWebAppearancePolicy(config.appearancePolicy);
}

function buildHostedWebDocumentStartScripts(config: HostedWebNodeConfig): ScriptItem[] {
  const appearancePolicy = resolveHostedWebAppearancePolicy(config);
  const historyApiBridgeScript = new BrowserHistoryApiBridgeScriptService().buildDocumentStartScriptItem();
  const scripts = HOSTED_WEB_NATIVE_BRIDGE_ALIAS_SCRIPTS
    .concat(WEB_LINK_DRAG_SUPPRESSION_SCRIPTS)
    .concat([buildWebAppearanceDocumentStartScriptItem(appearancePolicy)])
    .concat([historyApiBridgeScript])
    .concat([{
      script: PAGE_BEHAVIOR_SIGNAL_SCRIPT,
      scriptRules: ['*']
    }])
    .concat([{
      script: PAGE_CHROME_THEME_SIGNAL_SCRIPT,
      scriptRules: ['.*']
    }]);
  return scripts.concat(config.documentStartScripts ?? []);
}

function buildHostedWebDocumentEndScripts(config: HostedWebNodeConfig): ScriptItem[] {
  return config.documentEndScripts ?? [];
}

function buildHostedWebDocumentScriptSignature(config: HostedWebNodeConfig): string {
  const startSignature = buildHostedWebDocumentStartScripts(config)
    .map((item: ScriptItem): string => {
      const rules = (item.scriptRules ?? []).join('|');
      const script = String(item.script ?? '')
        .replace(/var __airaNativeBridgeToken = "(?:\\.|[^"\\])*";/g, 'var __airaNativeBridgeToken = "";');
      return `${rules}\n${script}`;
    })
    .join('\n---aira-document-start-item---\n');
  const endSignature = buildHostedWebDocumentEndScripts(config)
    .map((item: ScriptItem): string => {
      const rules = (item.scriptRules ?? []).join('|');
      const script = String(item.script ?? '')
        .replace(/var __airaNativeBridgeToken = "(?:\\.|[^"\\])*";/g, 'var __airaNativeBridgeToken = "";');
      return `${rules}\n${script}`;
    })
    .join('\n---aira-document-end-item---\n');
  return `${startSignature}\n---aira-document-lifecycle---\n${endSignature}`;
}

function buildHostedWebDocumentScriptKey(config: HostedWebNodeConfig): string | undefined {
  if (config.documentStartScriptKey === undefined || config.documentEndScriptKey === undefined) {
    return undefined;
  }
  return [
    HOSTED_WEB_DOCUMENT_SCRIPT_KEY_VERSION,
    buildHostedWebAppearancePolicySignature(config),
    config.documentStartScriptKey,
    config.documentEndScriptKey
  ].join('|');
}

function injectWebFileSavePickerCompat(config: HostedWebNodeConfig): void {
  void config.controller.runJavaScript(WEB_FILE_SAVE_PICKER_COMPAT_SCRIPT)
    .catch((_error: Error) => {
    });
}

function injectPageBehaviorSignal(config: HostedWebNodeConfig): void {
  void config.controller.runJavaScript(PAGE_BEHAVIOR_SIGNAL_SCRIPT)
    .catch((_error: Error) => {
    });
}

function registerHostedWebNativeMediaObservation(config: HostedWebNodeConfig): void {
  const observationHandler = config.callbacks.onNativeMediaPlayerObserved;
  if (observationHandler === undefined) {
    return;
  }
  try {
    config.controller.onCreateNativeMediaPlayer((
      _handler: webview.NativeMediaPlayerHandler,
      mediaInfo: webview.MediaInfo
    ) => {
      observationHandler(config.tabId, mediaInfo);
      // Huawei's official example returns null when the app only observes the media
      // and ArkWeb should continue using its own player. The SDK declaration is non-null,
      // so keep the explicit cast until the declaration matches the documented contract.
      return null;
    });
  } catch (error) {
    hilog.warn(
      HOSTED_WEB_NODE_LOG_DOMAIN,
      HOSTED_WEB_NODE_LOG_TAG,
      'ArkWeb native media observation registration failed tab=%{public}s error=%{public}s',
      config.tabId,
      `${error}`
    );
  }
}

function configureHostedWebBackForwardCache(
  tabId: string,
  controller: webview.WebviewController,
  source: string,
  force: boolean = false
): void {
  const result = HOSTED_WEB_BFCACHE_COORDINATOR.applyControllerOptionsForTab(tabId, controller, source, force);
  hilog.info(
    HOSTED_WEB_NODE_LOG_DOMAIN,
    HOSTED_WEB_NODE_LOG_TAG,
    'ArkWeb BFCache %{public}s: %{public}s',
    result.configured ? 'configured' : 'skipped',
    result.message
  );
}

function applyHostedWebSafeBrowsing(config: HostedWebNodeConfig): void {
  try {
    config.controller.enableSafeBrowsing(config.runtimeSecurityPolicy?.safeBrowsingEnabled !== false);
  } catch (error) {
    hilog.warn(
      HOSTED_WEB_NODE_LOG_DOMAIN,
      HOSTED_WEB_NODE_LOG_TAG,
      'ArkWeb safe browsing configuration failed tab=%{public}s error=%{public}s',
      config.tabId,
      `${error}`
    );
  }
}

@Builder
function HostedWebNodeBuilder(config: HostedWebNodeConfig) {
  Stack() {
    Web({
      src: config.initialSrc ?? '',
      controller: config.controller,
      incognitoMode: config.incognitoMode === true
    })
      .id(config.webComponentSnapshotId ?? `${config.componentSnapshotId}-web`)
      .width('100%')
      .height('100%')
      .backgroundColor(resolveHostedWebAppearancePolicy(config).backgroundColor)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .darkMode(resolveHostedWebAppearancePolicy(config).darkMode)
      .forceDarkAccess(resolveHostedWebAppearancePolicy(config).forceDarkAccess)
      .zoomAccess(true)
      .textZoomRatio(config.textZoomRatio ?? 100)
      .attributeModifier(new BrowserWebAttributeModifier({
        forceEnableWebZoom: config.forceEnableWebZoom
      }))
      .overScrollMode(OverScrollMode.NEVER)
      .nestedScroll(resolveHostedWebNestedScrollOptions(config.pullRefreshNestedScrollEnabled === true))
      .databaseAccess(true)
      .domStorageAccess(true)
      .javaScriptAccess(config.runtimeSecurityPolicy?.javaScriptEnabled !== false)
      .enableNativeMediaPlayer({
        enable: config.callbacks.onNativeMediaPlayerObserved !== undefined,
        shouldOverlay: true
      })
      .javaScriptProxy({
        object: config.hostedNativeBridge ?? HOSTED_WEB_NODE_NOOP_NATIVE_BRIDGE,
        name: HOSTED_WEB_NATIVE_BRIDGE_NAME,
        methodList: HOSTED_WEB_NATIVE_BRIDGE_METHODS,
        controller: config.controller
      })
      .runJavaScriptOnDocumentStart(buildHostedWebDocumentStartScripts(config))
      .runJavaScriptOnDocumentEnd(buildHostedWebDocumentEndScripts(config))
      .multiWindowAccess(true)
      .allowWindowOpenMethod(true)
      .geolocationAccess(true)
      .onSafeBrowsingCheckResult((threatType: ThreatType) => {
        sharedBrowserSafeBrowsingThreatPresentationService.presentIfNeeded(
          config.uiContext,
          config.tabId,
          threatType
        );
      })
      .onControllerAttached(() => {
        applyHostedWebSafeBrowsing(config);
        configureHostedWebBackForwardCache(config.tabId, config.controller, 'hosted_web_controller_attached', true);
        config.callbacks.onControllerAttached(config.tabId);
      })
      .onPageVisible((event: OnPageVisibleEvent) => {
        configureHostedWebBackForwardCache(config.tabId, config.controller, 'hosted_web_page_visible');
        config.callbacks.onPageVisible(config.tabId, event);
      })
      .onPageBegin((event: OnPageBeginEvent) => {
        registerHostedWebNativeMediaObservation(config);
        config.callbacks.onPageBegin(config.tabId, event);
      })
      .onPageEnd((event: OnPageEndEvent) => {
        hilog.info(
          HOSTED_WEB_NODE_LOG_DOMAIN,
          HOSTED_WEB_NODE_LOG_TAG,
          '[DEBUG-desktop-zoom-20260726] scale-probe page-end tab=%{public}s',
          config.tabId
        );
        injectWebFileSavePickerCompat(config);
        injectPageBehaviorSignal(config);
        config.callbacks.onPageEnd(config.tabId, event);
      })
      .onLoadFinished(() => {
        injectWebFileSavePickerCompat(config);
        injectPageBehaviorSignal(config);
        config.callbacks.onLoadFinished(config.tabId);
      })
      .onProgressChange((event: OnProgressChangeEvent) => {
        config.callbacks.onProgressChange(config.tabId, event);
      })
      .onAudioStateChanged((event: OnAudioStateChangedEvent) => {
        config.callbacks.onAudioStateChanged?.(config.tabId, event.playing);
      })
      .onScaleChange((event: OnScaleChangeEvent) => {
        hilog.info(
          HOSTED_WEB_NODE_LOG_DOMAIN,
          HOSTED_WEB_NODE_LOG_TAG,
          '[DEBUG-desktop-zoom-20260726] scale-probe change tab=%{public}s old=%{public}s new=%{public}s',
          config.tabId,
          event.oldScale.toString(),
          event.newScale.toString()
        );
      })
      .onScroll((event: OnScrollEvent) => {
        config.callbacks.onScroll(config.tabId, event);
      })
      .onTouch((event: TouchEvent) => {
        config.callbacks.onTouch(config.tabId, event);
      })
      .onNavigationEntryCommitted((details: LoadCommittedDetails) => {
        config.callbacks.onNavigationEntryCommitted(config.tabId, details);
      })
      .onTitleReceive((event: OnTitleReceiveEvent) => {
        config.callbacks.onTitleReceive(config.tabId, event);
      })
      .onFaviconReceived((event: OnFaviconReceivedEvent) => {
        config.callbacks.onFaviconReceived(config.tabId, event);
      })
      .onSearchResultReceive((event: OnSearchResultReceiveEvent) => {
        config.callbacks.onSearchResultReceive(config.tabId, event);
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        config.callbacks.onErrorReceive(config.tabId, event);
      })
      .onPermissionRequest((event: OnPermissionRequestEvent) => {
        config.callbacks.onPermissionRequest(config.tabId, event.request);
      })
      .onGeolocationShow((event: OnGeolocationShowEvent) => {
        config.callbacks.onGeolocationShow(config.tabId, event);
      })
      .onWindowNew((event: OnWindowNewEvent) => {
        config.callbacks.onWindowNew(config.tabId, event);
      })
      .onWindowExit(() => {
        config.callbacks.onWindowExit(config.tabId);
      })
      .onActivateContent(() => {
        config.callbacks.onActivateContent(config.tabId);
      })
      .onShowFileSelector((event: OnShowFileSelectorEvent) => {
        return config.callbacks.onShowFileSelector(config.tabId, event);
      })
      .onPrompt((event: OnPromptEvent) => {
        return config.callbacks.onPrompt(config.tabId, event);
      })
      .onConfirm((event: OnConfirmEvent) => {
        return config.callbacks.onConfirm(config.tabId, event);
      })
      .onAlert((event: OnAlertEvent) => {
        return config.callbacks.onAlert(config.tabId, event);
      })
      .onHttpAuthRequest((event: OnHttpAuthRequestEvent) => {
        return config.callbacks.onHttpAuthRequest(config.tabId, event);
      })
      .onSslErrorEvent((event: SslErrorEvent) => {
        config.callbacks.onSslErrorEvent(config.tabId, event);
      })
      .onLoadIntercept((event: OnLoadInterceptEvent) => {
        return config.callbacks.onLoadIntercept(config.tabId, event);
      })
      .onInterceptRequest((event: OnInterceptRequestEvent) => {
        return config.callbacks.onInterceptRequest(config.tabId, event);
      })
      .onOverrideUrlLoading((request: WebResourceRequest) => {
        return config.callbacks.onOverrideUrlLoading(config.tabId, request);
      })
      .onDownloadStart((event: OnDownloadStartEvent) => {
        config.callbacks.onDownloadStart(config.tabId, event);
      })
      .onContextMenuShow((event: OnContextMenuShowEvent) => {
        return config.callbacks.onContextMenuShow(config.tabId, event, config.controller);
      })
      .onContextMenuHide(() => {
        config.callbacks.onContextMenuHide(config.tabId);
      })
      .onFullScreenEnter((event: FullScreenEnterEvent) => {
        config.callbacks.onFullScreenEnter(config.tabId, event);
      })
      .onFullScreenExit(() => {
        config.callbacks.onFullScreenExit(config.tabId);
      })
  }
    .id(config.componentSnapshotId)
    .width('100%')
    .height('100%')
    .backgroundColor(resolveHostedWebAppearancePolicy(config).backgroundColor)
}

export class HostedWebNodeController extends NodeController {
  private readonly tabId: string;
  private readonly hostedNativeBridge: HostedWebNodeNativeBridge = new HostedWebNodeNativeBridge();
  private readonly pageBehaviorNativeBridge: HostedWebNodePageBehaviorBridge =
    new HostedWebNodePageBehaviorBridge();
  private builderNode: BuilderNode<[HostedWebNodeConfig]> | undefined;
  private rootNode: FrameNode | null = null;
  private webControllerAttached: boolean = false;
  private webController: webview.WebviewController | undefined;
  private pageBehaviorBridgeController: webview.WebviewController | undefined;
  private documentScriptSignature: string = '';
  private documentScriptIdentityUsesKey: boolean = false;
  private appearancePolicySignature: string = '';
  private runtimeSecurityPolicySignature: string = '';

  constructor(tabId: string, builderNode: BuilderNode<[HostedWebNodeConfig]> | undefined) {
    super();
    this.tabId = tabId;
    this.builderNode = builderNode;
  }

  makeNode(_uiContext: UIContext): FrameNode | null {
    return this.rootNode;
  }

  attachWeb(): boolean {
    if (this.builderNode === undefined) {
      return false;
    }
    const frameNode = this.builderNode.getFrameNode();
    if (frameNode === null || frameNode === undefined) {
      return false;
    }
    if (frameNode.getParent() !== null) {
      return false;
    }
    this.rootNode = frameNode;
    return true;
  }

  isAttached(): boolean {
    return this.rootNode !== null;
  }

  isWebControllerAttached(): boolean {
    return this.webControllerAttached;
  }

  markWebControllerAttached(): void {
    this.webControllerAttached = true;
  }

  rememberWebController(controller: webview.WebviewController): void {
    if (this.webController === controller) {
      return;
    }
    this.releasePageBehaviorBridge();
    this.webController = controller;
    this.webControllerAttached = false;
  }

  bindHostedNativeBridge(config: HostedWebNodeConfig): HostedWebNodeNativeBridge {
    this.hostedNativeBridge.bind(config);
    this.pageBehaviorNativeBridge.bind((payloadJson: string): void => {
      config.callbacks.onPageBehaviorSignal(config.tabId, payloadJson);
    });
    return this.hostedNativeBridge;
  }

  registerPageBehaviorBridge(controller: webview.WebviewController): void {
    if (this.pageBehaviorBridgeController === controller) {
      return;
    }
    this.releasePageBehaviorBridge();
    try {
      controller.deleteJavaScriptRegister(PAGE_BEHAVIOR_NATIVE_BRIDGE_NAME);
    } catch (_error) {
    }
    try {
      controller.registerJavaScriptProxy(
        this.pageBehaviorNativeBridge,
        PAGE_BEHAVIOR_NATIVE_BRIDGE_NAME,
        PAGE_BEHAVIOR_NATIVE_BRIDGE_METHODS
      );
      this.pageBehaviorBridgeController = controller;
    } catch (error) {
      hilog.warn(
        HOSTED_WEB_NODE_LOG_DOMAIN,
        HOSTED_WEB_NODE_LOG_TAG,
        'register page behavior native bridge failed tab=%{public}s message=%{public}s',
        this.tabId,
        String((error as Error)?.message ?? error ?? '')
      );
    }
  }

  private releasePageBehaviorBridge(): void {
    const controller = this.pageBehaviorBridgeController;
    this.pageBehaviorBridgeController = undefined;
    if (controller === undefined) {
      return;
    }
    try {
      controller.deleteJavaScriptRegister(PAGE_BEHAVIOR_NATIVE_BRIDGE_NAME);
    } catch (_error) {
    }
  }

  detachWeb(): void {
    this.rootNode = null;
  }

  setBuilderNode(builderNode: BuilderNode<[HostedWebNodeConfig]> | undefined): void {
    this.builderNode = builderNode;
    this.webControllerAttached = false;
  }

  needsDocumentStartScriptRebuild(config: HostedWebNodeConfig): boolean {
    const nextKey = buildHostedWebDocumentScriptKey(config);
    if (nextKey !== undefined) {
      return this.documentScriptSignature.length > 0 &&
        (!this.documentScriptIdentityUsesKey || this.documentScriptSignature !== nextKey);
    }
    if (this.documentScriptIdentityUsesKey) {
      return this.documentScriptSignature.length > 0;
    }
    const nextSignature = buildHostedWebDocumentScriptSignature(config);
    return this.documentScriptSignature.length > 0 && this.documentScriptSignature !== nextSignature;
  }

  rememberDocumentScripts(config: HostedWebNodeConfig): void {
    const nextKey = buildHostedWebDocumentScriptKey(config);
    this.documentScriptIdentityUsesKey = nextKey !== undefined;
    this.documentScriptSignature = nextKey ?? buildHostedWebDocumentScriptSignature(config);
  }

  rememberAppearancePolicy(config: HostedWebNodeConfig): void {
    this.appearancePolicySignature = buildHostedWebAppearancePolicySignature(config);
  }

  rememberRuntimeSecurityPolicy(config: HostedWebNodeConfig): void {
    this.runtimeSecurityPolicySignature = buildHostedWebRuntimeSecurityPolicySignature(config);
  }

  needsAppearancePolicyRebuild(config: HostedWebNodeConfig): boolean {
    const nextSignature = buildHostedWebAppearancePolicySignature(config);
    return this.appearancePolicySignature.length > 0 && this.appearancePolicySignature !== nextSignature;
  }

  needsRuntimeSecurityPolicyRebuild(config: HostedWebNodeConfig): boolean {
    const nextSignature = buildHostedWebRuntimeSecurityPolicySignature(config);
    return this.runtimeSecurityPolicySignature.length > 0 && this.runtimeSecurityPolicySignature !== nextSignature;
  }

  update(config: HostedWebNodeConfig): void {
    try {
      this.rememberWebController(config.controller);
      const shouldRebuild = this.needsAppearancePolicyRebuild(config) ||
        this.needsRuntimeSecurityPolicyRebuild(config);
      applyHostedWebSafeBrowsing(config);
      this.builderNode?.update(buildTrackedHostedWebNodeConfig(config, this));
      if (shouldRebuild) {
        this.rebuild();
      }
    } catch (_error) {
    }
  }

  dispose(): void {
    HOSTED_WEB_BFCACHE_COORDINATOR.removeTabId(this.tabId, this.webController);
    this.releasePageBehaviorBridge();
    this.pageBehaviorNativeBridge.unbind();
    this.hostedNativeBridge.unbind();
    this.rootNode = null;
    this.webControllerAttached = false;
    this.webController = undefined;
    this.documentScriptSignature = '';
    this.documentScriptIdentityUsesKey = false;
    this.appearancePolicySignature = '';
    this.runtimeSecurityPolicySignature = '';
    this.builderNode?.dispose();
    this.builderNode = undefined;
  }
}

function buildHostedWebAppearancePolicySignature(config: HostedWebNodeConfig): string {
  const policy = resolveHostedWebAppearancePolicy(config);
  return [
    String(policy.darkMode),
    policy.forceDarkAccess ? 'forceDark' : 'noForceDark',
    policy.backgroundColor,
    policy.prefersDarkColorScheme ? 'prefersDark' : 'prefersLight'
  ].join('|');
}

function buildHostedWebRuntimeSecurityPolicySignature(config: HostedWebNodeConfig): string {
  const policy = config.runtimeSecurityPolicy;
  return policy?.javaScriptEnabled !== false ? 'javaScript' : 'noJavaScript';
}

function buildTrackedHostedWebNodeConfig(
  config: HostedWebNodeConfig,
  hostedController: HostedWebNodeController
): HostedWebNodeConfig {
  hostedController.rememberWebController(config.controller);
  hostedController.rememberDocumentScripts(config);
  hostedController.rememberAppearancePolicy(config);
  hostedController.rememberRuntimeSecurityPolicy(config);
  const hostedNativeBridge = hostedController.bindHostedNativeBridge(config);
  return {
    tabId: config.tabId,
    componentSnapshotId: config.componentSnapshotId,
    webComponentSnapshotId: config.webComponentSnapshotId,
    controller: config.controller,
    uiContext: config.uiContext,
    pageUrl: config.pageUrl,
    pageTitle: config.pageTitle,
    initialSrc: config.initialSrc,
    incognitoMode: config.incognitoMode === true,
    appearancePolicy: config.appearancePolicy,
    runtimeSecurityPolicy: config.runtimeSecurityPolicy,
    documentStartScripts: config.documentStartScripts,
    documentStartScriptKey: config.documentStartScriptKey,
    documentEndScripts: config.documentEndScripts,
    documentEndScriptKey: config.documentEndScriptKey,
    userScriptNativeBridge: config.userScriptNativeBridge,
    hostedNativeBridge: hostedNativeBridge,
    webVideoControllerBridge: config.webVideoControllerBridge,
    forceEnableWebZoom: config.forceEnableWebZoom,
    textZoomRatio: config.textZoomRatio,
    pullRefreshNestedScrollEnabled: config.pullRefreshNestedScrollEnabled === true,
    callbacks: {
      onControllerAttached: (tabId: string): void => {
        hostedController.markWebControllerAttached();
        hostedController.registerPageBehaviorBridge(config.controller);
        config.callbacks.onControllerAttached(tabId);
      },
      onPageVisible: config.callbacks.onPageVisible,
      onPageBegin: config.callbacks.onPageBegin,
      onPageEnd: config.callbacks.onPageEnd,
      onNativeMediaPlayerObserved: config.callbacks.onNativeMediaPlayerObserved,
      onLoadFinished: config.callbacks.onLoadFinished,
      onProgressChange: config.callbacks.onProgressChange,
      onScroll: config.callbacks.onScroll,
      onTouch: config.callbacks.onTouch,
      onNavigationEntryCommitted: config.callbacks.onNavigationEntryCommitted,
      onTitleReceive: config.callbacks.onTitleReceive,
      onFaviconReceived: config.callbacks.onFaviconReceived,
      onSearchResultReceive: config.callbacks.onSearchResultReceive,
      onErrorReceive: config.callbacks.onErrorReceive,
      onPermissionRequest: config.callbacks.onPermissionRequest,
      onGeolocationShow: config.callbacks.onGeolocationShow,
      onWindowNew: config.callbacks.onWindowNew,
      onWindowExit: config.callbacks.onWindowExit,
      onActivateContent: config.callbacks.onActivateContent,
      onShowFileSelector: config.callbacks.onShowFileSelector,
      onPrompt: config.callbacks.onPrompt,
      onConfirm: config.callbacks.onConfirm,
      onAlert: config.callbacks.onAlert,
      onHttpAuthRequest: config.callbacks.onHttpAuthRequest,
      onSslErrorEvent: config.callbacks.onSslErrorEvent,
      onLoadIntercept: config.callbacks.onLoadIntercept,
      onInterceptRequest: config.callbacks.onInterceptRequest,
      onOverrideUrlLoading: config.callbacks.onOverrideUrlLoading,
      onDownloadStart: config.callbacks.onDownloadStart,
      onUserScriptInstallRequest: config.callbacks.onUserScriptInstallRequest,
      onHistoryApiUrlChange: config.callbacks.onHistoryApiUrlChange,
      onPageChromeThemeSignal: config.callbacks.onPageChromeThemeSignal,
      onPageBehaviorSignal: config.callbacks.onPageBehaviorSignal,
      onAdBlockCosmeticHidden: config.callbacks.onAdBlockCosmeticHidden,
      onAdBlockManualHidden: config.callbacks.onAdBlockManualHidden,
      onContextMenuShow: config.callbacks.onContextMenuShow,
      onContextMenuHide: config.callbacks.onContextMenuHide,
      onFullScreenEnter: config.callbacks.onFullScreenEnter,
      onFullScreenExit: config.callbacks.onFullScreenExit
    }
  };
}

function resolveHostedWebNestedScrollOptions(enabled: boolean): NestedScrollOptionsExt {
  if (!enabled) {
    return {
      scrollUp: NestedScrollMode.SELF_ONLY,
      scrollDown: NestedScrollMode.SELF_ONLY,
      scrollLeft: NestedScrollMode.SELF_ONLY,
      scrollRight: NestedScrollMode.SELF_ONLY
    };
  }
  return {
    scrollUp: NestedScrollMode.SELF_FIRST,
    scrollDown: NestedScrollMode.SELF_FIRST,
    scrollLeft: NestedScrollMode.SELF_ONLY,
    scrollRight: NestedScrollMode.SELF_ONLY
  };
}

export function createHostedWebNodeController(
  uiContext: UIContext,
  config: HostedWebNodeConfig
): HostedWebNodeController {
  enableWholeWebPageDrawingForPreviews();
  config.callbacks.onBeforeWebBuild?.(config.tabId);
  const hostedController = new HostedWebNodeController(config.tabId, undefined);
  const builderNode: BuilderNode<[HostedWebNodeConfig]> = new BuilderNode(uiContext, {
    selfIdealSize: {
      width: HOSTED_WEB_NODE_IDEAL_WIDTH,
      height: HOSTED_WEB_NODE_IDEAL_HEIGHT
    }
  });
  const trackedConfig = buildTrackedHostedWebNodeConfig(config, hostedController);
  builderNode.build(wrapBuilder<[HostedWebNodeConfig]>(HostedWebNodeBuilder), trackedConfig);
  hostedController.setBuilderNode(builderNode);
  return hostedController;
}
