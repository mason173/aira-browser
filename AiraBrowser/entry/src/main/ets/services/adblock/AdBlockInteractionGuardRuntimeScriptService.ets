export class AdBlockInteractionGuardRuntimeScriptService {
  buildDocumentStartScriptItem(): ScriptItem {
    return {
      script: this.buildDocumentStartScript(),
      scriptRules: ['.*']
    };
  }

  buildDocumentStartScript(): string {
    return `
;(function airaAdBlockInteractionGuardDocumentStart() {
  var guardKey = '__airaAdBlockInteractionGuardRuntime';
  if (window[guardKey]) {
    return;
  }
  var cosmeticRuntimeKey = '__airaAdBlockCosmeticRuntime';
  var eventPoint = function(event) {
    try {
      var touch = event && event.changedTouches && event.changedTouches.length > 0
        ? event.changedTouches[0]
        : (event && event.touches && event.touches.length > 0 ? event.touches[0] : undefined);
      if (touch) {
        return {
          x: typeof touch.clientX === 'number' ? touch.clientX : touch.screenX,
          y: typeof touch.clientY === 'number' ? touch.clientY : touch.screenY
        };
      }
      return {
        x: event.clientX,
        y: event.clientY
      };
    } catch (error) {
      return {
        x: -1,
        y: -1
      };
    }
  };
  var resolveGuardRect = function(zone) {
    if (!zone) {
      return null;
    }
    var anchor = zone.anchor;
    if (!anchor || typeof anchor.getBoundingClientRect !== 'function') {
      return zone;
    }
    try {
      if (anchor.isConnected === false) {
        return null;
      }
      var anchorRect = anchor.getBoundingClientRect();
      if (!anchorRect || anchorRect.width < 4 || anchorRect.height < 4) {
        return null;
      }
      var left = anchorRect.left + Number(zone.offsetLeft || 0);
      var top = anchorRect.top + Number(zone.offsetTop || 0);
      var right = anchorRect.left + Number(zone.offsetRight || anchorRect.width);
      var bottom = anchorRect.top + Number(zone.offsetBottom || anchorRect.height);
      return {
        left: Math.max(anchorRect.left, left),
        top: Math.max(anchorRect.top, top),
        right: Math.min(anchorRect.right, right),
        bottom: Math.min(anchorRect.bottom, bottom)
      };
    } catch (error) {
      return null;
    }
  };
  var shouldGuard = function(event) {
    var runtime = window[cosmeticRuntimeKey];
    if (!runtime || !Array.isArray(runtime.hiddenClickRects) || runtime.hiddenClickRects.length <= 0) {
      return false;
    }
    var point = eventPoint(event);
    if (typeof point.x !== 'number' || typeof point.y !== 'number' || point.x < 0 || point.y < 0) {
      return false;
    }
    for (var index = 0; index < runtime.hiddenClickRects.length; index += 1) {
      var rect = resolveGuardRect(runtime.hiddenClickRects[index]);
      if (rect && rect.right - rect.left >= 4 && rect.bottom - rect.top >= 4 &&
        point.x >= rect.left && point.x <= rect.right && point.y >= rect.top && point.y <= rect.bottom) {
        return true;
      }
    }
    return false;
  };
  var guardFilteredSlotEvent = function(event) {
    if (!shouldGuard(event)) {
      return;
    }
    var eventType = String(event && event.type ? event.type : 'event');
    if (eventType === 'click') {
      try { event.preventDefault(); } catch (error) {}
    }
    try { event.stopImmediatePropagation(); } catch (error) {}
    try { event.stopPropagation(); } catch (error) {}
    try {
      var bridge = window.__airaAdBlockNativeBridge;
      var runtime = window[cosmeticRuntimeKey];
      if (bridge && typeof bridge.onCosmeticHidden === 'function' && runtime) {
        bridge.onCosmeticHidden(JSON.stringify({
          count: 0,
          hiddenElementCount: 0,
          placeholderCollapsedCount: 0,
          hiddenClickRectCount: runtime.hiddenClickRects.length,
          pageUrl: String(runtime.pageUrl || window.location.href || ''),
          phase: 'guarded_' + eventType
        }));
      }
    } catch (error) {}
  };
  var listenerTypes = [
    'pointerdown',
    'touchstart',
    'touchend',
    'pointerup',
    'click'
  ];
  listenerTypes.forEach(function(type) {
    try {
      window.addEventListener(type, guardFilteredSlotEvent, {
        capture: true,
        passive: type !== 'click'
      });
    } catch (error) {
      try { window.addEventListener(type, guardFilteredSlotEvent, true); } catch (innerError) {}
    }
  });
  window[guardKey] = {
    listener: guardFilteredSlotEvent,
    listenerTypes: listenerTypes
  };
})();`;
  }
}
