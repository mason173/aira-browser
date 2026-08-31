export class AdBlockPingRuntimeScriptService {
  buildDocumentStartScriptItem(): ScriptItem {
    return {
      script: this.buildRuntimeScript(),
      scriptRules: ['*']
    };
  }

  private buildRuntimeScript(): string {
    return `
;(function airaAdBlockPingRuntime() {
  if (window.__airaAdBlockPingRuntimeInstalled === true) {
    return;
  }
  window.__airaAdBlockPingRuntimeInstalled = true;
  var mark = function(rawUrl) {
    try {
      var url = new URL(String(rawUrl), document.baseURI || location.href);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') {
        return;
      }
      var bridge = window.__airaAdBlockPingNativeBridge;
      if (bridge && typeof bridge.mark === 'function') {
        bridge.mark(url.href);
      }
    } catch (_error) {}
  };
  try {
    var prototype = typeof Navigator === 'function' && Navigator.prototype
      ? Navigator.prototype
      : Object.getPrototypeOf(navigator);
    if (prototype && typeof prototype.sendBeacon === 'function') {
      var original = prototype.sendBeacon;
      var wrapped = function(url, data) {
        mark(url);
        return original.call(this, url, data);
      };
      Object.defineProperty(prototype, 'sendBeacon', {
        configurable: true,
        writable: true,
        value: wrapped
      });
    }
  } catch (_error) {}
  var markAnchorPings = function(event) {
    try {
      var path = typeof event.composedPath === 'function' ? event.composedPath() : [];
      var anchor = null;
      for (var index = 0; index < path.length; index += 1) {
        var candidate = path[index];
        if (candidate && String(candidate.localName || '').toLowerCase() === 'a' && candidate.hasAttribute('ping')) {
          anchor = candidate;
          break;
        }
      }
      if (!anchor) {
        return;
      }
      String(anchor.getAttribute('ping') || '').trim().split(/\\s+/).forEach(mark);
    } catch (_error) {}
  };
  try {
    document.addEventListener('click', markAnchorPings, true);
    document.addEventListener('auxclick', markAnchorPings, true);
  } catch (_error) {}
})();`;
  }
}
