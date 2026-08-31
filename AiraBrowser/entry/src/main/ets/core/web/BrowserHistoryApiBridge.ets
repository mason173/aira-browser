export type BrowserHistoryApiChangeKind = 'pushState' | 'replaceState' | 'popstate' | 'hashchange' | 'init';

export interface BrowserHistoryApiChangeEvent {
  kind: BrowserHistoryApiChangeKind;
  oldUrl: string;
  newUrl: string;
  timestamp: number;
}

export interface BrowserHistoryApiBridgeDecision {
  accepted: boolean;
  event?: BrowserHistoryApiChangeEvent;
  reason: string;
}

interface BrowserHistoryApiRawEvent {
  kind?: string;
  oldUrl?: string;
  newUrl?: string;
  timestamp?: number;
}

const BROWSER_HISTORY_API_ALLOWED_KINDS: string[] = [
  'pushState',
  'replaceState',
  'popstate',
  'hashchange',
  'init'
];

const BROWSER_HISTORY_API_DOCUMENT_START_SCRIPT: string = `
(function () {
  if (window.__airaHistoryApiBridgeInstalled === true) {
    return;
  }
  window.__airaHistoryApiBridgeInstalled = true;
  window.__airaHistoryApiBridgeLastUrl = String(window.location && window.location.href || '');

  function notify(kind, oldUrl, newUrl) {
    try {
      var normalizedOldUrl = String(oldUrl || '');
      var normalizedNewUrl = String(newUrl || '');
      if (!normalizedNewUrl || normalizedOldUrl === normalizedNewUrl) {
        return;
      }
      if (window.__airaHistoryApiNativeBridge &&
        typeof window.__airaHistoryApiNativeBridge.onUrlChange === 'function') {
        window.__airaHistoryApiNativeBridge.onUrlChange(JSON.stringify({
          kind: String(kind || ''),
          oldUrl: normalizedOldUrl,
          newUrl: normalizedNewUrl,
          timestamp: Date.now()
        }));
      }
      window.__airaHistoryApiBridgeLastUrl = normalizedNewUrl;
    } catch (_error) {
    }
  }

  function installHistoryHook(methodName) {
    try {
      var original = window.history && window.history[methodName];
      if (typeof original !== 'function' || original.__airaHistoryApiBridgeWrapped === true) {
        return;
      }
      var wrapped = function () {
        var oldUrl = String(window.location && window.location.href || '');
        var result = original.apply(this, arguments);
        var newUrl = String(window.location && window.location.href || '');
        notify(methodName, oldUrl, newUrl);
        return result;
      };
      wrapped.__airaHistoryApiBridgeWrapped = true;
      wrapped.__airaHistoryApiBridgeOriginal = original;
      window.history[methodName] = wrapped;
    } catch (_error) {
    }
  }

  installHistoryHook('pushState');
  installHistoryHook('replaceState');

  window.addEventListener('hashchange', function (event) {
    notify('hashchange', String(event.oldURL || window.__airaHistoryApiBridgeLastUrl || ''), String(event.newURL || location.href || ''));
  }, true);

  window.addEventListener('popstate', function () {
    notify('popstate', String(window.__airaHistoryApiBridgeLastUrl || ''), String(window.location && window.location.href || ''));
  }, true);

  notify('init', '', String(window.location && window.location.href || ''));
})();
`;

export class BrowserHistoryApiBridgeScriptService {
  buildDocumentStartScriptItem(): ScriptItem {
    return {
      script: BROWSER_HISTORY_API_DOCUMENT_START_SCRIPT,
      scriptRules: ['.*']
    };
  }
}

export class BrowserHistoryApiBridgePolicy {
  resolveChange(payloadJson: string, previousUrl: string): BrowserHistoryApiBridgeDecision {
    const raw = this.parsePayload(payloadJson);
    if (raw === undefined) {
      return {
        accepted: false,
        reason: 'invalid_payload'
      };
    }
    const kind = this.normalizeKind(raw.kind ?? '');
    if (kind.length <= 0) {
      return {
        accepted: false,
        reason: 'unsupported_kind'
      };
    }
    const newUrl = this.normalizeUrl(raw.newUrl ?? '');
    if (!this.isWebUrl(newUrl)) {
      return {
        accepted: false,
        reason: 'unsupported_url'
      };
    }
    const normalizedPreviousUrl = this.normalizeUrl(previousUrl);
    if (normalizedPreviousUrl.length > 0 && this.normalizeComparableUrl(normalizedPreviousUrl) ===
      this.normalizeComparableUrl(newUrl)) {
      return {
        accepted: false,
        reason: 'same_url'
      };
    }
    return {
      accepted: true,
      event: {
        kind: kind as BrowserHistoryApiChangeKind,
        oldUrl: this.normalizeUrl(raw.oldUrl ?? previousUrl),
        newUrl: newUrl,
        timestamp: this.normalizeTimestamp(raw.timestamp)
      },
      reason: 'accepted'
    };
  }

  private parsePayload(payloadJson: string): BrowserHistoryApiRawEvent | undefined {
    try {
      return JSON.parse(payloadJson) as BrowserHistoryApiRawEvent;
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeKind(kind: string): string {
    const normalized = String(kind ?? '').trim();
    return BROWSER_HISTORY_API_ALLOWED_KINDS.includes(normalized) ? normalized : '';
  }

  private normalizeUrl(url: string): string {
    return String(url ?? '').trim();
  }

  private normalizeComparableUrl(url: string): string {
    return this.normalizeUrl(url);
  }

  private normalizeTimestamp(timestamp: number | undefined): number {
    if (typeof timestamp === 'number' && Number.isFinite(timestamp) && timestamp > 0) {
      return Math.floor(timestamp);
    }
    return Date.now();
  }

  private isWebUrl(url: string): boolean {
    const lower = url.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}

