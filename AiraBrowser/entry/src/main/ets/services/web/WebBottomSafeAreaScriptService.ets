// Read-only page runtime. Geometry is owned by the native viewport, never by injected CSS.
// Events invalidate bounded observations; an idle document has no recurring work.
export class WebBottomSafeAreaScriptService {
  static buildSampleScript(): string {
    return `(${WebBottomSafeAreaScriptService.buildDetectorFunction()})(null, function() {})`;
  }

  private static buildDetectorFunction(): string {
    return `function(cached, remember) {
      try {
        var deadline = performance.now() + 4;
        if (document.hidden || document.fullscreenElement) return 'suspended';
        var viewport = window.visualViewport;
        // Our own reserve is about 100px. Only a much larger shrink is the keyboard.
        if (viewport && (Math.abs(viewport.scale - 1) > 0.05 ||
          viewport.height < window.innerHeight - 180)) return 'suspended';
        var width = document.documentElement.clientWidth;
        var height = window.innerHeight;
        if (width < 180 || height < 200) return 'suspended';
        var remainingNodes = 192;
        var deferred = false;
        function withinBudget() {
          if (--remainingNodes < 0 || performance.now() > deadline) {
            deferred = true;
            return false;
          }
          return true;
        }
        var visited = [];
        function visible(node, rect, allowPassthrough) {
          var style = getComputedStyle(node);
          return rect.width > 0 && rect.height > 0 && style.display !== 'none' &&
            style.visibility === 'visible' && Number(style.opacity) > 0 &&
            (allowPassthrough || style.pointerEvents !== 'none');
        }
        function geometry(node, slack) {
          var rect = node.getBoundingClientRect();
          if (rect.width < width * 0.65 || rect.height < 28 ||
            rect.height > Math.min(140, height * 0.24) ||
            rect.left > width * 0.2 || rect.right < width * 0.8 ||
            Math.abs(height - rect.bottom) > slack || !visible(node, rect)) return null;
          return rect;
        }
        function insideDialog(node) {
          return !!node.closest('[role="dialog"], [aria-modal="true"], dialog');
        }
        function stickyRejected(style, rect) {
          // A sticky footer in normal flow is not enough: require a bottom constraint.
          return style.position === 'sticky' && (style.bottom === 'auto' ||
            Math.abs(height - rect.bottom - parseFloat(style.bottom)) > 4);
        }
        function isOverlay(node, style) {
          // Chat shells are often absolute. Body counts only when its own box fills
          // the viewport; a scroll lock that shifts body fails the bottom-edge test.
          if (style.position !== 'fixed' && style.position !== 'absolute') return false;
          var rect = node.getBoundingClientRect();
          if (rect.width <= 0 || rect.height <= 0 || style.display === 'none' ||
            style.visibility === 'hidden' || Number(style.opacity) <= 0) return false;
          if (rect.width < width * 0.65 || rect.height < height * 0.25 ||
            rect.left > width * 0.2 || rect.right < width * 0.8 ||
            Math.abs(height - rect.bottom) > 32) return false;
          return Math.abs(node.scrollTop || 0) <= 1 && Math.abs(node.scrollLeft || 0) <= 1;
        }
        function nearestOverlay(node) {
          // The document root is never an overlay. Body is, when isOverlay accepts it.
          var parent = node.parentElement;
          while (parent && parent !== document.documentElement) {
            if (!withinBudget()) return null;
            var style = getComputedStyle(parent);
            if (isOverlay(parent, style)) return parent;
            parent = parent.parentElement;
          }
          return null;
        }
        function chainUnscrolled(node, overlay) {
          var parent = node.parentElement;
          while (parent && parent !== overlay) {
            if (Math.abs(parent.scrollTop || 0) > 1 || Math.abs(parent.scrollLeft || 0) > 1) return false;
            var style = getComputedStyle(parent);
            if (style.position === 'sticky' || style.position === 'fixed') {
              var rect = parent.getBoundingClientRect();
              // A pinned composer stays at the bottom while the list behind it scrolls.
              if (style.bottom !== 'auto' &&
                Math.abs(height - rect.bottom - parseFloat(style.bottom)) <= 4 &&
                Math.abs(height - rect.bottom) <= 48) return true;
            }
            parent = parent.parentElement;
          }
          return true;
        }
        function hasTargets(node, rect, minimum, relax) {
          var walker = document.createTreeWalker(node, 1);
          var controls = [];
          var child;
          var budget = 96;
          while (budget-- > 0 && (child = walker.nextNode())) {
            if (!withinBudget()) return false;
            var role = child.getAttribute('role');
            var interactive = child.tagName === 'A' && child.hasAttribute('href') ||
              child.tagName === 'BUTTON' || role === 'tab' || role === 'button' ||
              role === 'link' || child.hasAttribute('onclick') ||
              getComputedStyle(child).cursor === 'pointer';
            if (!interactive) continue;
            // A disabled action is still covered by the browser bar. Only the classic
            // two-target bar keeps the enabled-control requirement.
            if (!relax && (child.disabled || child.getAttribute('aria-disabled') === 'true')) continue;
            var item = child.getBoundingClientRect();
            if (!visible(child, item) || item.width < 20 || item.height < 20 ||
              item.width > rect.width * (relax ? 1 : 0.6) || item.top < rect.top - 2 ||
              item.bottom > rect.bottom + 2) continue;
            if (controls.some(function(entry) { return entry.node.contains(child); })) continue;
            var centerX = (item.left + item.right) / 2;
            var centerY = (item.top + item.bottom) / 2;
            var hit = document.elementFromPoint(centerX, centerY);
            // contains() does not include the node itself, and that node is often the hit.
            if (!hit || (hit !== child && !child.contains(hit))) continue;
            if (minimum < 2) return true;
            controls.push({ node: child, x: centerX, y: centerY });
            // Two horizontally separated, visible click targets are sufficient. This also
            // supports framework div-based tabs whose only signal is cursor:pointer.
            for (var i = 0; i < controls.length - 1; i++) {
              if (Math.abs(controls[i].x - centerX) >= rect.width * 0.35 &&
                Math.abs(controls[i].y - centerY) <= 24) return true;
            }
          }
          return false;
        }
        function isEditor(node) {
          if (!node || node.nodeType !== 1) return false;
          var tag = node.tagName;
          if (tag === 'TEXTAREA') return true;
          if (tag === 'INPUT') {
            var type = (node.getAttribute('type') || 'text').toLowerCase();
            return type !== 'hidden' && type !== 'checkbox' && type !== 'radio' &&
              type !== 'button' && type !== 'submit' && type !== 'file' && type !== 'range';
          }
          var editable = node.getAttribute('contenteditable');
          return editable === '' || editable === 'true' || node.isContentEditable === true;
        }
        function containsEditor(node) {
          if (isEditor(node)) return true;
          var shadow = node.shadowRoot;
          if (shadow && shadow.querySelector &&
            shadow.querySelector('textarea, input, [contenteditable="true"], [contenteditable=""]')) {
            return true;
          }
          if (!document.createTreeWalker) return false;
          var walker = document.createTreeWalker(node, 1);
          var child;
          var budget = 24;
          while (budget-- > 0 && (child = walker.nextNode())) {
            if (!withinBudget()) return false;
            if (isEditor(child)) return true;
          }
          return false;
        }
        function composerGeometry(node) {
          // Wider than a tab row: a chat field can be taller than 140px and sit a little
          // above the screen edge, still inside the floating toolbar's cover.
          var rect = node.getBoundingClientRect();
          if (rect.width < width * 0.5 || rect.height < 28 || rect.height > 240 ||
            rect.left > width * 0.25 || rect.right < width * 0.75 ||
            Math.abs(height - rect.bottom) > 96 || !visible(node, rect)) return null;
          return rect;
        }
        function fullShell(node) {
          var rect = node.getBoundingClientRect();
          if (rect.width < width * 0.85 || rect.height < height * 0.8 || Math.abs(rect.top) > 8) {
            return false;
          }
          return Math.abs(height - rect.bottom) <= 32;
        }
        function unscrolledFooter(node) {
          var parent = node.parentElement;
          var guard = 8;
          while (parent && parent !== document.documentElement && guard-- > 0) {
            if (!withinBudget()) return false;
            if (Math.abs(parent.scrollTop || 0) > 1) return false;
            if (fullShell(parent)) return true;
            parent = parent.parentElement;
          }
          return false;
        }
        function pinnedComposer(node) {
          var rect = composerGeometry(node);
          if (!rect || !containsEditor(node)) return false;
          var style = getComputedStyle(node);
          if ((style.position === 'fixed' || style.position === 'sticky') &&
            !stickyRejected(style, rect) && !insideDialog(node)) return true;
          if (style.position === 'absolute') {
            var overlay = nearestOverlay(node);
            return !!overlay && chainUnscrolled(node, overlay) && !insideDialog(node);
          }
          // Flex and normal-flow footers of a full-viewport shell are not position:fixed,
          // but they stay on the screen bottom while the transcript scrolls beside them.
          return !insideDialog(node) && unscrolledFooter(node);
        }
        function bottomIsland(node) {
          // A glass capsule sets pointer-events:none on the full-width shell and puts the
          // buttons in a shorter centered pill. Hit-testing skips the shell, and the buttons
          // are too close together to satisfy a full-width two-target rule.
          var style = getComputedStyle(node);
          if (style.position !== 'fixed' && style.position !== 'sticky') return false;
          if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) <= 0) return false;
          var rect = node.getBoundingClientRect();
          if (stickyRejected(style, rect) || insideDialog(node)) return false;
          if (rect.width < width * 0.85 || rect.height < 36 || rect.height > 96 ||
            rect.left > width * 0.12 || rect.right < width * 0.88 ||
            Math.abs(height - rect.bottom) > 28) return false;
          var controls = [];
          var walker = document.createTreeWalker(node, 1);
          var child;
          var budget = 64;
          while (budget-- > 0 && (child = walker.nextNode())) {
            if (!withinBudget()) return false;
            var role = child.getAttribute('role');
            var interactive = child.tagName === 'A' && child.hasAttribute('href') ||
              child.tagName === 'BUTTON' || role === 'tab' || role === 'button' ||
              role === 'link' || child.hasAttribute('onclick') ||
              getComputedStyle(child).cursor === 'pointer';
            if (!interactive) continue;
            var item = child.getBoundingClientRect();
            var childStyle = getComputedStyle(child);
            if (item.width < 20 || item.height < 20 || childStyle.pointerEvents === 'none' ||
              childStyle.display === 'none' || childStyle.visibility === 'hidden' ||
              Number(childStyle.opacity) <= 0 || item.top < rect.top - 2 ||
              item.bottom > rect.bottom + 8) continue;
            if (controls.some(function(entry) { return entry.contains(child); })) continue;
            var center = (item.left + item.right) / 2;
            var hit = document.elementFromPoint(center, (item.top + item.bottom) / 2);
            if (!hit || (hit !== child && !child.contains(hit) && !node.contains(hit))) continue;
            for (var i = 0; i < controls.length; i++) {
              var other = controls[i].getBoundingClientRect();
              if (Math.abs((other.left + other.right) / 2 - center) >= 24) return true;
            }
            controls.push(child);
          }
          return false;
        }
        function matches(node) {
          if (pinnedComposer(node) || bottomIsland(node)) return true;
          var style = getComputedStyle(node);
          var positioned = style.position === 'fixed' || style.position === 'sticky';
          var rect = geometry(node, 32);
          if (rect && positioned && !stickyRejected(style, rect) &&
            !insideDialog(node) && hasTargets(node, rect, 2, false)) return true;
          // Action row of a tall bottom overlay. The row may sit in normal flow under
          // an inner dialog, or under a sticky composer in an absolute full-screen shell.
          // One target is enough, including a disabled send button.
          rect = geometry(node, 48);
          if (!rect || (positioned && stickyRejected(style, rect))) return false;
          var overlay = nearestOverlay(node);
          if (!overlay || !chainUnscrolled(node, overlay)) return false;
          return hasTargets(node, rect, 1, true);
        }
        if (cached && cached.isConnected && withinBudget() && matches(cached)) {
          if (deferred || performance.now() > deadline) return 'deferred';
          remember(cached);
          return 'detected';
        }
        var depths = [4, 24, 56, 96];
        var columns = [0.1, 0.3, 0.5, 0.7, 0.9];
        for (var y = 0; y < depths.length; y++) {
          for (var x = 0; x < columns.length; x++) {
            var node = document.elementFromPoint(width * columns[x], height - depths[y]);
            for (var level = 0; node && level < 14 && visited.length < 80; level++) {
              if (visited.indexOf(node) >= 0) break;
              if (!withinBudget()) return 'deferred';
              visited.push(node);
              var detected = matches(node);
              if (deferred || performance.now() > deadline) return 'deferred';
              if (detected) { remember(node); return 'detected'; }
              var root = node.getRootNode && node.getRootNode();
              node = node.parentElement || (root && root.host) || null;
            }
          }
        }
        return 'absent';
      } catch (_) { return 'unavailable'; }
    }`;
  }

  static buildCommandScript(token: string, command: string): string {
    return `(() => { var runtime = window.__airaBottomSafeAreaRuntime;
      if (runtime && runtime.token === ${JSON.stringify(token)}) runtime[${JSON.stringify(command)}]();
    })()`;
  }

  static buildInstallScript(token: string): string {
    return `(() => {
      if (window !== window.top) return;
      var token = ${JSON.stringify(token)};
      var previous = window.__airaBottomSafeAreaRuntime;
      if (previous && previous.token === token) { previous.resume(); return; }
      if (previous) previous.dispose();
      var sample = ${WebBottomSafeAreaScriptService.buildDetectorFunction()};
      var candidate = null;
      var lastResult = '';
      var sequence = 0;
      var active = false;
      var hostEnabled = true;
      var disposed = false;
      var timer = 0;
      var pending = false;
      var touched = false;
      var lastInput = -10000;
      var lastScan = -10000;
      var retries = 0;
      var missing = 0;
      var roots = [];
      var force = false;
      var listeners = [];
      var lifecycle = [];
      var mutation;
      var resize;
      var quietMs = 650;
      function listen(list, target, name, fn, capture) {
        if (!target || !target.addEventListener) return;
        var options = { passive: true, capture: !!capture };
        target.addEventListener(name, fn, options);
        list.push(function() { target.removeEventListener(name, fn, options); });
      }
      function remove(list) { while (list.length) list.pop()(); }
      function report(result) {
        if (result === lastResult) return;
        var bridge = window.__airaPageBehaviorNativeBridge;
        if (!bridge || typeof bridge.onSignal !== 'function') return;
        try {
          bridge.onSignal(JSON.stringify({ kind: 'bottom-safe-area', token: token,
            sequence: ++sequence, result: result }));
          lastResult = result;
        } catch (_) {}
      }
      function queue(delay) {
        if (!active || timer || touched || !pending) return;
        timer = setTimeout(flush, Math.max(delay || 120, quietMs - (Date.now() - lastInput),
          300 - (Date.now() - lastScan)));
      }
      function invalidate(unconditional) {
        if (!active) return;
        force = force || unconditional;
        pending = true;
        retries = 0;
        queue(120);
      }
      function marker(node) {
        if (!node || node.nodeType !== 1) return false;
        var tag = node.tagName;
        if (tag === 'STYLE' || tag === 'LINK' || tag === 'NAV' || tag === 'FOOTER' ||
          tag === 'BUTTON' || tag === 'A' || tag === 'DIALOG') return true;
        var hint = (node.getAttribute('id') || '') + ' ' + (node.getAttribute('class') || '') + ' ' +
          (node.getAttribute('role') || '') + ' ' + (node.getAttribute('style') || '');
        return /bottom|footer|tab.?bar|navigation|fixed|sticky|dialog|tablist|button/i.test(hint);
      }
      function interestingRoots() {
        // No whole-document selector collection. Stop after 64 newly changed elements.
        var budget = 64;
        for (var i = 0; i < roots.length && budget > 0; i++) {
          var root = roots[i];
          budget--;
          if (!root || root.nodeType !== 1) continue;
          if (marker(root)) return true;
          var walker = document.createTreeWalker(root, 1);
          var child;
          while (budget-- > 0 && (child = walker.nextNode())) if (marker(child)) return true;
        }
        return false;
      }
      function observeCandidate(node) {
        if (candidate === node) return;
        candidate = node;
        if (resize) { resize.disconnect(); if (candidate) resize.observe(candidate); }
      }
      function flush() {
        timer = 0;
        if (!active || !pending || touched) return;
        if (Date.now() - lastInput < quietMs) { queue(120); return; }
        var relevant = force || candidate && !candidate.isConnected || interestingRoots();
        roots = [];
        force = false;
        pending = false;
        if (!relevant) return;
        lastScan = Date.now();
        var found = null;
        var result = sample(candidate, function(node) { found = node; });
        if (result === 'deferred' || result === 'unavailable') {
          // At most two recovery attempts per invalidation, never an idle polling loop.
          if (retries++ < 2) { force = pending = true; queue(500); }
          return;
        }
        if (result === 'detected') {
          missing = 0;
          observeCandidate(found);
          report(result);
        } else if (result === 'absent') {
          // Confirm removal once to avoid reacting to a framework's transient replacement.
          if (candidate && ++missing < 2) { force = pending = true; queue(300); return; }
          missing = 0;
          observeCandidate(null);
          report(result);
        } else report(result);
      }
      function onMutation(records) {
        if (!active) return;
        var relevant = false;
        // Callbacks only inspect identity/attributes and collect roots, never style or geometry.
        for (var i = 0; i < records.length && i < 48; i++) {
          var record = records[i];
          var target = record.target;
          if (candidate) {
            if (!candidate.isConnected || candidate.contains(target) ||
              record.type === 'attributes' && target.contains(candidate) ||
              target.tagName === 'STYLE' || target.tagName === 'HEAD' ||
              target.parentElement && target.parentElement.tagName === 'STYLE') {
              force = relevant = true;
              break;
            }
            // Unrelated news/feed mutations do not revalidate an already known bar.
            continue;
          }
          if (record.type === 'attributes') { force = relevant = true; break; }
          if (target.tagName === 'STYLE' || target.tagName === 'HEAD' ||
              target.parentElement && target.parentElement.tagName === 'STYLE') { force = relevant = true; break; }
          for (var j = 0; record.addedNodes && j < record.addedNodes.length && j < 16 && roots.length < 16; j++) {
            var node = record.addedNodes[j];
            if (node.nodeType === 1 && roots.indexOf(node) < 0) { roots.push(node); relevant = true; }
          }
        }
        // A truncated batch merits one bounded fallback; do not walk the remaining records.
        if (!candidate && records.length > 48) force = relevant = true;
        if (relevant) invalidate(force);
      }
      function input(event) {
        lastInput = Date.now();
        if (event.type === 'touchstart') touched = true;
        if (event.type === 'touchend' || event.type === 'touchcancel')
          touched = !!(event.touches && event.touches.length);
        // Scrolling itself does not request another detector pass.
        if (pending) queue(quietMs);
      }
      function check() { invalidate(true); }
      function effect(event) {
        if (candidate && (candidate.contains(event.target) || event.target.contains(candidate)) ||
          marker(event.target)) check();
      }
      function stop() {
        active = false;
        if (timer) clearTimeout(timer);
        timer = 0;
        pending = force = false;
        roots = [];
        touched = false;
        if (mutation) mutation.disconnect();
        if (resize) resize.disconnect();
        remove(listeners);
      }
      function start() {
        if (disposed || !hostEnabled || document.hidden) return;
        if (active) { check(); return; }
        active = true;
        if (typeof MutationObserver === 'function') {
          mutation = new MutationObserver(onMutation);
          mutation.observe(document.documentElement || document, { childList: true, subtree: true,
            attributes: true, attributeFilter: ['class', 'id', 'style', 'hidden', 'aria-hidden', 'disabled', 'aria-disabled', 'role', 'href', 'onclick'],
            characterData: true });
        }
        if (typeof ResizeObserver === 'function') {
          resize = new ResizeObserver(check);
          if (candidate) resize.observe(candidate);
        }
        ['scroll', 'touchstart', 'touchmove', 'touchend', 'touchcancel', 'wheel'].forEach(function(name) {
          listen(listeners, document, name, input, true);
        });
        ['resize', 'orientationchange', 'popstate', 'hashchange'].forEach(function(name) {
          listen(listeners, window, name, check);
        });
        listen(listeners, window.visualViewport, 'resize', check);
        listen(listeners, document, 'fullscreenchange', check);
        listen(listeners, document, 'DOMContentLoaded', check);
        listen(listeners, window, 'load', check);
        listen(listeners, document, 'load', effect, true);
        listen(listeners, document, 'transitionend', effect, true);
        listen(listeners, document, 'animationend', effect, true);
        check();
      }
      listen(lifecycle, document, 'visibilitychange', function() { if (document.hidden) stop(); else start(); });
      listen(lifecycle, window, 'pagehide', stop);
      listen(lifecycle, window, 'pageshow', start);
      var runtime = {
        token: token,
        resume: function() {
          lastResult = '';
          hostEnabled = true; start();
        },
        pause: function() { hostEnabled = false; stop(); },
        check: check,
        dispose: function() {
          disposed = true;
          hostEnabled = false;
          stop();
          remove(lifecycle);
          candidate = null;
          if (window.__airaBottomSafeAreaRuntime === runtime) delete window.__airaBottomSafeAreaRuntime;
        }
      };
      window.__airaBottomSafeAreaRuntime = runtime;
      start();
    })()`;
  }
}
