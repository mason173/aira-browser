import { webview } from '@kit.ArkWeb';

export const BROWSER_WEB_LOCAL_SCROLL_NATIVE_BRIDGE_NAME: string = '__airaWebLocalScrollNativeBridge';

export interface BrowserWebLocalScrollSignal {
  sourceId: string;
  scrollTop: number;
  deltaY: number;
  timestamp: number;
}

interface BrowserWebLocalScrollRawSignal {
  sourceId?: string;
  scrollTop?: number;
  deltaY?: number;
  timestamp?: number;
}

const LOCAL_SCROLL_SOURCE_ID_MAX_LENGTH: number = 96;
const LOCAL_SCROLL_MAX_TOP_PX: number = 100000000;
const LOCAL_SCROLL_MAX_DELTA_PX: number = 4096;
const LOCAL_SCROLL_SOURCE_ID_PATTERN: RegExp = /^[A-Za-z0-9:_-]+$/;
const LOCAL_SCROLL_NATIVE_BRIDGE_NAME_LITERAL: string =
  JSON.stringify(BROWSER_WEB_LOCAL_SCROLL_NATIVE_BRIDGE_NAME);
const LOCAL_SCROLL_NATIVE_BRIDGE_METHODS: string[] = ['onScroll'];

const BROWSER_WEB_LOCAL_SCROLL_DOCUMENT_START_SCRIPT: string = `
(function () {
  if (window.__airaWebLocalScrollSignalInstalled === true) {
    return;
  }
  window.__airaWebLocalScrollSignalInstalled = true;

  var sourceIds = new WeakMap();
  var lastScrollTopBySource = new WeakMap();
  var knownLocalScrollSources = new WeakSet();
  var nextSourceId = 1;
  var pendingSignal = null;
  var pendingFrame = -1;
  var documentId = Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);

  function readScrollTop(source) {
    var value = Number(source && source.scrollTop || 0);
    return Number.isFinite(value) ? Math.max(0, value) : 0;
  }

  function isLocalVerticalScroller(source) {
    try {
      if (!source || source === document || source === document.documentElement ||
        source === document.body || source === document.scrollingElement || source.nodeType !== 1) {
        return false;
      }
      var scrollHeight = Number(source.scrollHeight || 0);
      var clientHeight = Number(source.clientHeight || 0);
      if (!Number.isFinite(scrollHeight) || !Number.isFinite(clientHeight) ||
        clientHeight <= 0 || scrollHeight <= clientHeight + 1) {
        return false;
      }
      var style = window.getComputedStyle(source);
      var overflowY = String(style && style.overflowY || '').toLowerCase();
      return overflowY === 'auto' || overflowY === 'scroll' || overflowY === 'overlay';
    } catch (_error) {
      return false;
    }
  }

  function resolveSourceId(source) {
    var existing = sourceIds.get(source);
    if (existing) {
      return existing;
    }
    var sourceId = documentId + ':' + String(nextSourceId++);
    sourceIds.set(source, sourceId);
    return sourceId;
  }

  function sendPendingSignal() {
    var signal = pendingSignal;
    pendingSignal = null;
    pendingFrame = -1;
    if (!signal || Math.abs(signal.deltaY) < 0.5) {
      return;
    }
    try {
      var bridge = window[${LOCAL_SCROLL_NATIVE_BRIDGE_NAME_LITERAL}];
      if (bridge && typeof bridge.onScroll === 'function') {
        bridge.onScroll(JSON.stringify({
          sourceId: signal.sourceId,
          scrollTop: signal.scrollTop,
          deltaY: signal.deltaY,
          timestamp: Date.now()
        }));
      }
    } catch (_error) {
    }
  }

  function scheduleSignal(sourceId, scrollTop, deltaY) {
    if (pendingSignal && pendingSignal.sourceId !== sourceId) {
      sendPendingSignal();
    }
    if (pendingSignal) {
      pendingSignal.scrollTop = scrollTop;
      pendingSignal.deltaY += deltaY;
    } else {
      pendingSignal = {
        sourceId: sourceId,
        scrollTop: scrollTop,
        deltaY: deltaY
      };
    }
    if (pendingFrame >= 0) {
      return;
    }
    if (typeof window.requestAnimationFrame === 'function') {
      pendingFrame = window.requestAnimationFrame(sendPendingSignal);
    } else {
      pendingFrame = window.setTimeout(sendPendingSignal, 16);
    }
  }

  function primeScrollSources(event) {
    try {
      var path = typeof event.composedPath === 'function' ? event.composedPath() : [];
      if (!path || path.length <= 0) {
        var current = event.target;
        path = [];
        while (current && path.length < 32) {
          path.push(current);
          current = current.parentNode || current.host || null;
        }
      }
      for (var index = 0; index < path.length && index < 32; index += 1) {
        var candidate = path[index];
        if (isLocalVerticalScroller(candidate)) {
          knownLocalScrollSources.add(candidate);
          lastScrollTopBySource.set(candidate, readScrollTop(candidate));
        }
      }
    } catch (_error) {
    }
  }

  function handleLocalScroll(event) {
    try {
      var source = event && event.target;
      if (!knownLocalScrollSources.has(source)) {
        if (!isLocalVerticalScroller(source)) {
          return;
        }
        knownLocalScrollSources.add(source);
      }
      var scrollTop = readScrollTop(source);
      var previousScrollTop = lastScrollTopBySource.get(source);
      lastScrollTopBySource.set(source, scrollTop);
      if (typeof previousScrollTop !== 'number' || !Number.isFinite(previousScrollTop)) {
        return;
      }
      var deltaY = scrollTop - previousScrollTop;
      if (!Number.isFinite(deltaY) || Math.abs(deltaY) < 0.5) {
        return;
      }
      scheduleSignal(resolveSourceId(source), scrollTop, deltaY);
    } catch (_error) {
    }
  }

  document.addEventListener('touchstart', primeScrollSources, { capture: true, passive: true });
  document.addEventListener('pointerdown', primeScrollSources, { capture: true, passive: true });
  document.addEventListener('scroll', handleLocalScroll, true);
})();
`;

export class BrowserWebLocalScrollSignalService {
  buildDocumentStartScriptItem(): ScriptItem {
    return {
      script: BROWSER_WEB_LOCAL_SCROLL_DOCUMENT_START_SCRIPT,
      scriptRules: ['*']
    };
  }

  registerBridge(
    controller: webview.WebviewController,
    signalHandler: (payloadJson: string) => void
  ): void {
    try {
      controller.deleteJavaScriptRegister(BROWSER_WEB_LOCAL_SCROLL_NATIVE_BRIDGE_NAME);
    } catch (_error) {
    }
    try {
      controller.registerJavaScriptProxy(
        new BrowserWebLocalScrollNativeBridge(signalHandler),
        BROWSER_WEB_LOCAL_SCROLL_NATIVE_BRIDGE_NAME,
        LOCAL_SCROLL_NATIVE_BRIDGE_METHODS
      );
    } catch (_error) {
    }
  }

  parseSignal(payloadJson: string): BrowserWebLocalScrollSignal | undefined {
    let raw: BrowserWebLocalScrollRawSignal;
    try {
      raw = JSON.parse(payloadJson) as BrowserWebLocalScrollRawSignal;
    } catch (_error) {
      return undefined;
    }
    if (raw === undefined || raw === null) {
      return undefined;
    }
    const sourceId = String(raw.sourceId ?? '').trim();
    if (sourceId.length <= 0 || sourceId.length > LOCAL_SCROLL_SOURCE_ID_MAX_LENGTH ||
      !LOCAL_SCROLL_SOURCE_ID_PATTERN.test(sourceId)) {
      return undefined;
    }
    if (typeof raw.scrollTop !== 'number' || !Number.isFinite(raw.scrollTop) ||
      typeof raw.deltaY !== 'number' || !Number.isFinite(raw.deltaY) || Math.abs(raw.deltaY) < 0.5) {
      return undefined;
    }
    const scrollTop = Math.min(LOCAL_SCROLL_MAX_TOP_PX, Math.max(0, raw.scrollTop));
    const deltaY = Math.min(LOCAL_SCROLL_MAX_DELTA_PX, Math.max(-LOCAL_SCROLL_MAX_DELTA_PX, raw.deltaY));
    const rawTimestamp = raw.timestamp;
    const timestamp = typeof rawTimestamp === 'number' && Number.isFinite(rawTimestamp) && rawTimestamp > 0 ?
      Math.floor(rawTimestamp) : Date.now();
    return {
      sourceId: sourceId,
      scrollTop: scrollTop,
      deltaY: deltaY,
      timestamp: timestamp
    };
  }
}

class BrowserWebLocalScrollNativeBridge {
  private readonly signalHandler: (payloadJson: string) => void;

  constructor(signalHandler: (payloadJson: string) => void) {
    this.signalHandler = signalHandler;
  }

  onScroll(payloadJson: string): void {
    this.signalHandler(payloadJson);
  }
}
