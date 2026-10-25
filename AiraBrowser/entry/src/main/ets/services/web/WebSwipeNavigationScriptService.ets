// Touch recognition runs in the document so embedded controls can retain their gestures.
// Navigation itself belongs to the native history owner, not window.history.
export const WEB_SWIPE_NAVIGATION_BRIDGE: string = '__airaWebSwipeNavigationBridge';

const INSTALL_SCRIPT: string = `
(function () {
  if (window.top !== window || !/^https?:$/.test(location.protocol) ||
      window.__airaSwipeNavigation) return;
  var gesture = null;
  var indicator = null;
  var listeners = [];
  var cleanupTimer = null;
  var entranceFrame = null;
  var settlingIndicator = null;
  var settleTimer = null;
  function reset() {
    if (cleanupTimer !== null) { window.clearTimeout(cleanupTimer); cleanupTimer = null; }
    if (entranceFrame !== null) { window.cancelAnimationFrame(entranceFrame); entranceFrame = null; }
    if (settleTimer !== null) { window.clearTimeout(settleTimer); settleTimer = null; }
    if (settlingIndicator) { settlingIndicator.remove(); settlingIndicator = null; }
    gesture = null;
    if (indicator) { indicator.remove(); indicator = null; }
  }
  function blockedPage() {
    var viewport = window.visualViewport;
    var layoutWidth = document.documentElement ? document.documentElement.clientWidth : window.innerWidth;
    var zoomed = viewport && (typeof viewport.width === 'number'
      ? viewport.width < layoutWidth - 2 : viewport.scale > 1.05);
    return document.hidden || document.fullscreenElement || zoomed ||
      String(window.getSelection ? window.getSelection() : '').length > 0;
  }
  function blockedTarget(event) {
    var path = typeof event.composedPath === 'function' ? event.composedPath() : [];
    if (!path.length) {
      for (var node = event.target; node && path.length < 32; node = node.parentNode || node.host) path.push(node);
    }
    for (var i = 0; i < path.length && i < 32; i++) {
      var element = path[i];
      if (!element || element.nodeType !== 1) continue;
      if (/^(INPUT|TEXTAREA|SELECT|OPTION|BUTTON|VIDEO|AUDIO|CANVAS|IFRAME|OBJECT|EMBED)$/.test(element.tagName) ||
          element.isContentEditable || element.getAttribute('draggable') === 'true' || element.shadowRoot ||
          /^(slider|scrollbar|spinbutton|textbox)$/.test(element.getAttribute('role') || '') ||
          /carousel|swiper|slick|slider/i.test(String(element.className || ''))) return true;
      var root = element === document.documentElement || element === document.body;
      var style = window.getComputedStyle(element);
      if (!root && style.touchAction && !/^(auto|manipulation|pan-y|pan-y pinch-zoom)$/.test(style.touchAction)) return true;
      if (element.scrollWidth > element.clientWidth + 2 &&
          (root || /^(auto|scroll|overlay|hidden)$/.test(style.overflowX))) return true;
    }
    return false;
  }
  function bridge() { return window.${WEB_SWIPE_NAVIGATION_BRIDGE}; }
  function start(event) {
    reset();
    if (!event.isTrusted || event.defaultPrevented || event.touches.length !== 1 || blockedPage()) return;
    try {
      if (blockedTarget(event)) return;
      var nativeBridge = bridge();
      var capabilities = nativeBridge ? Number(nativeBridge.getCapabilities()) : 0;
      if (!(capabilities & 6)) return;
      var touch = event.touches[0];
      gesture = { id: touch.identifier, x: touch.clientX, y: touch.clientY,
        scrollX: window.scrollX, scrollY: window.scrollY, url: location.href,
        direction: '', capabilities: capabilities, distance: 0, readyFeedbackRequested: false,
        threshold: Math.max(72, Math.min(120, window.innerWidth * 0.22)) };
    } catch (_) { reset(); }
  }
  function update(event, touch) {
    var state = gesture;
    if (!state || !touch || !event.isTrusted || touch.identifier !== state.id || event.defaultPrevented || blockedPage() ||
        location.href !== state.url ||
        Math.abs(window.scrollX - state.scrollX) > 2 || Math.abs(window.scrollY - state.scrollY) > 2) {
      reset(); return false;
    }
    var dx = touch.clientX - state.x;
    var dy = Math.abs(touch.clientY - state.y);
    var distance = Math.abs(dx);
    if (!state.direction) {
      if (Math.max(distance, dy) < 12) return false;
      if (distance < dy * 1.8 || dy > 36) { reset(); return false; }
      var direction = dx > 0 ? 'back' : 'forward';
      if (!(state.capabilities & (direction === 'back' ? 2 : 4))) { reset(); return false; }
      state.direction = direction;
    }
    // Once horizontal intent is established, keep the gesture until release/cancellation.
    // Retreating reduces progress instead of dropping the arrow or changing direction.
    state.distance = Math.max(0, state.direction === 'back' ? dx : -dx);
    return true;
  }
  function reducedMotion() {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }
  function paintIndicator() {
    if (!gesture || !indicator) return;
    var progress = Math.min(1, gesture.distance / gesture.threshold);
    var overdrag = Math.max(0, gesture.distance - gesture.threshold);
    var offset = -26 + 40 * (1 - Math.pow(1 - progress, 2)) + 8 * (1 - Math.exp(-overdrag / 100));
    var sign = gesture.direction === 'back' ? 1 : -1;
    indicator.setAttribute('data-aira-swipe-state', progress >= 1 ? 'ready' : 'tracking');
    indicator.style.setProperty('transform', 'translate3d(' + (sign * offset) + 'px,0,0) scale(' + (0.78 + 0.22 * progress) + ')', 'important');
    indicator.style.setProperty('opacity', String(0.65 + 0.35 * progress), 'important');
    indicator.style.setProperty('background', progress >= 1 ? 'rgba(35,35,38,.96)' : 'rgba(35,35,38,.82)', 'important');
  }
  function showIndicator() {
    if (!gesture || !document.documentElement) return;
    if (!indicator) {
      indicator = document.createElement('div');
      indicator.setAttribute('aria-hidden', 'true');
      indicator.setAttribute('data-aira-swipe-indicator', gesture.direction);
      var viewport = window.visualViewport;
      var minY = (viewport ? viewport.offsetTop : 0) + 40;
      var maxY = minY + (viewport ? viewport.height : window.innerHeight) - 80;
      var top = Math.max(minY, Math.min(maxY, gesture.y)) - 22;
      indicator.style.cssText = 'all:initial!important;position:fixed!important;top:' + top + 'px!important;' +
        (gesture.direction === 'back' ? 'left:0!important;' : 'right:0!important;') +
        'width:44px!important;height:44px!important;border-radius:50%!important;' +
        'display:flex!important;align-items:center!important;justify-content:center!important;' +
        'box-shadow:0 2px 10px rgba(0,0,0,.18)!important;color:white!important;' +
        'pointer-events:none!important;user-select:none!important;z-index:2147483647!important;' +
        'transition:opacity 100ms linear,background 100ms linear!important;opacity:0!important;';
      // Own static markup; no page content is interpolated into the SVG.
      indicator.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ' +
        'style="width:24px!important;height:24px!important;display:block!important;transform:rotate(' +
        (gesture.direction === 'back' ? '0' : '180') + 'deg)!important">' +
        '<path d="M13 5l-7 7 7 7M6 12h14" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      document.documentElement.appendChild(indicator);
      paintIndicator();
      if (!reducedMotion()) {
        indicator.style.setProperty('opacity', '0', 'important');
        entranceFrame = window.requestAnimationFrame(function () { entranceFrame = null; paintIndicator(); });
      }
      return;
    }
    paintIndicator();
  }
  function finish(committed) {
    if (cleanupTimer !== null) { window.clearTimeout(cleanupTimer); cleanupTimer = null; }
    if (entranceFrame !== null) { window.cancelAnimationFrame(entranceFrame); entranceFrame = null; }
    var state = gesture;
    var node = indicator;
    gesture = null;
    indicator = null;
    if (!node) return;
    if (reducedMotion()) { node.remove(); return; }
    settlingIndicator = node;
    node.setAttribute('data-aira-swipe-state', committed ? 'committed' : 'cancelled');
    node.style.setProperty('transition', 'transform 180ms cubic-bezier(.2,.8,.2,1),opacity 160ms ease-out', 'important');
    var sign = state && state.direction === 'forward' ? -1 : 1;
    node.style.setProperty('transform', 'translate3d(' + (sign * (committed ? 22 : -52)) + 'px,0,0) scale(' + (committed ? '1.06' : '.72') + ')', 'important');
    node.style.setProperty('opacity', '0', 'important');
    settleTimer = window.setTimeout(function () {
      node.remove();
      if (settlingIndicator === node) { settlingIndicator = null; settleTimer = null; }
    }, 200);
  }
  function move(event) {
    if (event.touches.length !== 1) { reset(); return; }
    if (!update(event, event.touches[0])) return;
    showIndicator();
    var state = gesture;
    if (state.distance >= state.threshold && !state.readyFeedbackRequested) {
      state.readyFeedbackRequested = true;
      try { var nativeBridge = bridge(); if (nativeBridge) nativeBridge.ready(state.direction, state.url); } catch (_) {}
    }
  }
  function end(event) {
    if (!event.isTrusted || event.touches.length || event.changedTouches.length !== 1 ||
        !update(event, event.changedTouches[0])) { reset(); return; }
    var state = gesture;
    var committed = !!state.direction && state.distance >= state.threshold;
    finish(committed);
    if (!committed) return;
    try { var nativeBridge = bridge(); if (nativeBridge) nativeBridge.navigate(state.direction, state.url); } catch (_) {}
  }
  function listen(target, name, handler, capture) {
    target.addEventListener(name, handler, { passive: true, capture: !!capture });
    listeners.push([target, name, handler, !!capture]);
  }
  function cleanupAfterDispatch() {
    if (!gesture) return;
    var endingGesture = gesture;
    if (cleanupTimer !== null) window.clearTimeout(cleanupTimer);
    // Trusted input performs microtask checkpoints BETWEEN event listeners. A Promise here
    // clears the gesture before the bubble-phase end handler can navigate. Use a task, and
    // bind cleanup to this gesture so a delayed callback cannot cancel the next touch.
    cleanupTimer = window.setTimeout(function () {
      cleanupTimer = null;
      if (gesture === endingGesture) finish(false);
    }, 0);
  }
  // Bubble and remain passive so page controls keep their own gestures. Capture cleanup also
  // removes the hint if a page stops touchend propagation before it reaches our end handler.
  listen(window, 'touchend', cleanupAfterDispatch, true);
  listen(window, 'touchcancel', cleanupAfterDispatch, true);
  listen(window, 'touchstart', start);
  listen(window, 'touchmove', move);
  listen(window, 'touchend', end);
  listen(window, 'touchcancel', function () { finish(false); });
  listen(window, 'pagehide', reset);
  listen(window, 'pageshow', reset);
  listen(document, 'visibilitychange', reset);
  window.__airaSwipeNavigation = { dispose: function () {
    reset();
    listeners.forEach(function (item) { item[0].removeEventListener(item[1], item[2], item[3]); });
    listeners = [];
    delete window.__airaSwipeNavigation;
  } };
})();`;

const DISPOSE_SCRIPT: string = `
(function () { if (window.__airaSwipeNavigation) window.__airaSwipeNavigation.dispose(); })();`;

export class WebSwipeNavigationScriptService {
  buildRuntimeScript(enabled: boolean): string {
    return enabled ? INSTALL_SCRIPT : DISPOSE_SCRIPT;
  }

  buildDocumentStartScriptItem(): ScriptItem {
    return { script: INSTALL_SCRIPT, scriptRules: ['*'] };
  }
}
