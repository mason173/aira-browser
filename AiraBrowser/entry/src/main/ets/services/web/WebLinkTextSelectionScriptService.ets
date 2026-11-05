/** Owns only a DOM Range. Handles and copy controls stay in the native overlay. */
export class WebLinkTextSelectionScriptService {
  buildStartScript(sessionId: string, targetId: string): string {
    return `(function () {
      var key = '__airaLinkTextSelection';
      var id = ${JSON.stringify(sessionId)};
      var target = window.__airaLinkTextTarget;
      if (window[key]) window[key].dispose();
      if (!target || target.id !== ${JSON.stringify(targetId)} || !target.node.isConnected) return '';
      delete window.__airaLinkTextTarget;
      var anchor = target.node;
      var doc = anchor.ownerDocument;
      var view = doc.defaultView;
      var selection = view.getSelection();
      var range = doc.createRange();
      var disposed = false, dragging = false, fixedPoint = null, frame = 0, revision = 0;
      var outsidePress = null;
      var oldStyles = ['user-select', '-webkit-user-select'].map(function (name) {
        return [name, anchor.style.getPropertyValue(name), anchor.style.getPropertyPriority(name)];
      });
      var shadowRoots = [], root = anchor.getRootNode();
      while (root && root.host) { shadowRoots.push(root); root = root.host.getRootNode(); }
      var views = [], currentView = view;
      while (currentView) {
        views.push(currentView);
        if (currentView === window || !currentView.frameElement) break;
        currentView = currentView.frameElement.ownerDocument.defaultView;
      }
      oldStyles.forEach(function (entry) { anchor.style.setProperty(entry[0], 'text', 'important'); });

      function selectAnchor() {
        var walker = doc.createTreeWalker(anchor, 4);
        var first = null, last = null, node;
        while ((node = walker.nextNode())) {
          if (node.data.trim().length && node.parentElement.getClientRects().length) {
            if (!first) first = node;
            last = node;
          }
        }
        if (!first) return false;
        range.setStart(first, first.data.search(/\\S/));
        range.setEnd(last, last.data.trimEnd().length);
        applyRange();
        return true;
      }

      function applyRange() {
        selection.removeAllRanges();
        selection.addRange(range);
      }

      function frameOffset(sourceView) {
        var x = 0, y = 0, current = sourceView || view;
        while (current !== window) {
          var element = current.frameElement;
          if (!element) break;
          var rect = element.getBoundingClientRect();
          x += rect.left + element.clientLeft;
          y += rect.top + element.clientTop;
          current = element.ownerDocument.defaultView;
        }
        return { x: x, y: y };
      }

      function visibleClip() {
        var clip = { left: -1e9, top: -1e9, right: 1e9, bottom: 1e9 };
        var element = anchor;
        views.forEach(function (current) {
          var offset = frameOffset(current), viewport = current.visualViewport;
          clip.left = Math.max(clip.left, offset.x + (viewport ? viewport.offsetLeft : 0));
          clip.top = Math.max(clip.top, offset.y + (viewport ? viewport.offsetTop : 0));
          clip.right = Math.min(clip.right, offset.x + (viewport ? viewport.offsetLeft + viewport.width : current.innerWidth));
          clip.bottom = Math.min(clip.bottom, offset.y + (viewport ? viewport.offsetTop + viewport.height : current.innerHeight));
          while (element) {
            var style = current.getComputedStyle(element), rect = element.getBoundingClientRect();
            var clipsOverflow = style.display !== 'inline' && style.display !== 'contents';
            if (clipsOverflow && /hidden|clip|scroll|auto/.test(style.overflowX || style.overflow)) {
              clip.left = Math.max(clip.left, rect.left + element.clientLeft + offset.x);
              clip.right = Math.min(clip.right, rect.left + element.clientLeft + element.clientWidth + offset.x);
            }
            if (clipsOverflow && /hidden|clip|scroll|auto/.test(style.overflowY || style.overflow)) {
              clip.top = Math.max(clip.top, rect.top + element.clientTop + offset.y);
              clip.bottom = Math.min(clip.bottom, rect.top + element.clientTop + element.clientHeight + offset.y);
            }
            element = element.parentElement || (element.getRootNode().host);
          }
          element = current.frameElement;
        });
        return clip;
      }

      function endpoint(start, offset) {
        // A collapsed caret at formatting whitespace can have its block's rect (or no rect).
        // Measure one rendered character at the selected edge instead of a container/whole range.
        var common = range.commonAncestorContainer;
        var nodes = [], walker, node;
        if (common.nodeType === 3) nodes.push(common);
        else {
          walker = doc.createTreeWalker(common, 4);
          while ((node = walker.nextNode())) {
            if (range.intersectsNode(node)) nodes.push(node);
          }
        }
        var probe = null;
        for (var pass = 0; pass < 2 && !probe; pass++) {
          for (var index = start ? 0 : nodes.length - 1;
               index >= 0 && index < nodes.length; index += start ? 1 : -1) {
            node = nodes[index];
            if (!node.parentElement || !node.parentElement.getClientRects().length) continue;
            var low = node === range.startContainer ? range.startOffset : 0;
            var high = node === range.endContainer ? range.endOffset : node.data.length;
            var cursor = start ? low : high;
            while (start ? cursor < high : cursor > low) {
              var glyphLow = start ? cursor : Math.max(low, cursor - (node.data.charCodeAt(cursor - 1) >= 0xDC00 &&
                node.data.charCodeAt(cursor - 1) <= 0xDFFF ? 2 : 1));
              var glyphHigh = start ? Math.min(high, cursor + (node.data.codePointAt(cursor) > 0xFFFF ? 2 : 1)) : cursor;
              cursor = start ? glyphHigh : glyphLow;
              var character = node.data.slice(glyphLow, glyphHigh);
              // Search past zero-width controls; preserve rendered spaces when no letters are selected.
              if (/[\\r\\n]/.test(character) || (pass === 0 && /\\s/.test(character))) continue;
              probe = doc.createRange(); probe.setStart(node, glyphLow); probe.setEnd(node, glyphHigh);
              var rects = probe.getClientRects();
              var rect = Array.prototype.find.call(rects, function (value) { return value.width > 0 && value.height > 0; });
              if (rect) break;
              probe = null;
            }
            if (probe) break;
          }
        }
        if (!probe || !rect) return null;
        var caret = range.cloneRange();
        caret.collapse(start);
        var caretRect = caret.getClientRects()[0];
        var rtl = view.getComputedStyle(probe.startContainer.parentElement).direction === 'rtl';
        var x = start !== rtl ? rect.left : rect.right;
        if (caretRect && caretRect.width <= 1 && caretRect.height > 0 &&
            Math.abs(caretRect.top - rect.top) <= 1 && Math.abs(caretRect.height - rect.height) <= 1) x = caretRect.left;
        return { x: x + offset.x,
          y: rect.top + offset.y, height: rect.height };
      }

      function snapshot() {
        if (disposed || !anchor.isConnected || range.collapsed) return { sessionId: id, active: false, revision: ++revision };
        var offset = frameOffset();
        var rect = range.getBoundingClientRect();
        var viewport = window.visualViewport;
        var clip = visibleClip();
        var first = endpoint(true, offset), last = endpoint(false, offset);
        if (!first || !last) return { sessionId: id, active: false, revision: ++revision };
        return { sessionId: id, active: true, dragging: dragging, revision: ++revision,
          start: first, end: last,
          left: rect.left + offset.x, top: rect.top + offset.y,
          right: rect.right + offset.x, bottom: rect.bottom + offset.y,
          viewportWidth: viewport ? viewport.width : window.innerWidth,
          offsetLeft: viewport ? viewport.offsetLeft : 0,
          offsetTop: viewport ? viewport.offsetTop : 0,
          clipLeft: clip.left, clipTop: clip.top, clipRight: clip.right, clipBottom: clip.bottom };
      }

      function notify() {
        frame = 0;
        var value = snapshot();
        try {
          var bridge = window.__airaUserScriptNativeBridge;
          if (bridge && bridge.linkTextSelectionChanged) bridge.linkTextSelectionChanged(JSON.stringify(value));
        } catch (_) {}
        if (!value.active && !disposed) dispose();
      }

      function schedule() {
        if (!disposed && !frame) frame = window.requestAnimationFrame(notify);
      }

      function selectionChanged() {
        if (disposed) return;
        if (!selection.rangeCount || selection.isCollapsed || !anchor.isConnected) { dispose(); return; }
        schedule();
      }

      function onPointerDown(event) { outsidePress = { x: event.clientX, y: event.clientY }; }
      function onPointerUp(event) {
        var press = outsidePress;
        outsidePress = null;
        if (press && Math.hypot(event.clientX - press.x, event.clientY - press.y) < 8) dispose();
      }
      function onPointerCancel() { outsidePress = null; }

      function dispose() {
        if (disposed) return;
        disposed = true;
        if (frame) window.cancelAnimationFrame(frame);
        doc.removeEventListener('selectionchange', selectionChanged);
        views.forEach(function (current) {
          current.document.removeEventListener('pointerdown', onPointerDown, true);
          current.document.removeEventListener('pointerup', onPointerUp, true);
          current.document.removeEventListener('pointercancel', onPointerCancel, true);
          current.removeEventListener('scroll', schedule, true);
          current.removeEventListener('resize', schedule);
        });
        view.removeEventListener('pagehide', dispose);
        if (window.visualViewport) {
          window.visualViewport.removeEventListener('scroll', schedule);
          window.visualViewport.removeEventListener('resize', schedule);
        }
        oldStyles.forEach(function (entry) {
          if (entry[1]) anchor.style.setProperty(entry[0], entry[1], entry[2]);
          else anchor.style.removeProperty(entry[0]);
        });
        selection.removeAllRanges();
        if (window[key] && window[key].id === id) delete window[key];
        notify();
      }

      function move(handle, xRatio, yRatio, phase) {
        if (disposed) return '';
        if (phase === 'start') {
          fixedPoint = handle === 'start' ? { node: range.endContainer, offset: range.endOffset } :
            { node: range.startContainer, offset: range.startOffset };
        }
        if (!fixedPoint) return '';
        dragging = phase !== 'end';
        var viewport = window.visualViewport;
        var width = viewport ? viewport.width : window.innerWidth;
        var offset = frameOffset();
        var x = (viewport ? viewport.offsetLeft : 0) + xRatio * width - offset.x;
        var y = (viewport ? viewport.offsetTop : 0) + yRatio * width - offset.y;
        var caret = null;
        if (doc.caretPositionFromPoint) {
          try {
            var position = doc.caretPositionFromPoint(x, y, { shadowRoots: shadowRoots });
            if (position) { caret = doc.createRange(); caret.setStart(position.offsetNode, position.offset); caret.collapse(true); }
          } catch (_) {}
        }
        if ((!caret || caret.startContainer.nodeType !== 3 ||
             caret.startContainer.getRootNode() !== fixedPoint.node.getRootNode()) && doc.caretRangeFromPoint) {
          caret = doc.caretRangeFromPoint(x, y);
        }
        if (caret && caret.startContainer.nodeType === 3 && caret.startContainer.isConnected &&
            caret.startContainer.ownerDocument === doc && caret.startContainer.getRootNode() === fixedPoint.node.getRootNode()) {
          var fixed = doc.createRange();
          fixed.setStart(fixedPoint.node, fixedPoint.offset);
          fixed.collapse(true);
          var next = doc.createRange();
          if (caret.compareBoundaryPoints(0, fixed) <= 0) {
            next.setStart(caret.startContainer, caret.startOffset);
            next.setEnd(fixedPoint.node, fixedPoint.offset);
          } else {
            next.setStart(fixedPoint.node, fixedPoint.offset);
            next.setEnd(caret.startContainer, caret.startOffset);
          }
          if (!next.collapsed) { range = next; applyRange(); }
        }
        if (phase === 'end') fixedPoint = null;
        schedule();
        return JSON.stringify(snapshot());
      }

      try {
        if (!selection || !selectAnchor()) { dispose(); return ''; }
        window[key] = { id: id, dispose: dispose, move: move,
          selectAll: function () { if (!disposed) { selectAnchor(); schedule(); } return JSON.stringify(snapshot()); },
          text: function () { return disposed ? '' : selection.toString(); } };
        doc.addEventListener('selectionchange', selectionChanged);
        views.forEach(function (current) {
          current.document.addEventListener('pointerdown', onPointerDown, true);
          current.document.addEventListener('pointerup', onPointerUp, true);
          current.document.addEventListener('pointercancel', onPointerCancel, true);
          current.addEventListener('scroll', schedule, true);
          current.addEventListener('resize', schedule);
        });
        view.addEventListener('pagehide', dispose);
        if (window.visualViewport) {
          window.visualViewport.addEventListener('scroll', schedule);
          window.visualViewport.addEventListener('resize', schedule);
        }
        schedule();
        return JSON.stringify(snapshot());
      } catch (_) { dispose(); return ''; }
    })()`;
  }

  buildCommandScript(sessionId: string, command: string): string {
    return `(function () { var session = window.__airaLinkTextSelection;
      if (!session || session.id !== ${JSON.stringify(sessionId)}) return '';
      return ${command}; })()`;
  }

  buildMoveScript(sessionId: string, handle: string, xRatio: number, yRatio: number, phase: string): string {
    return this.buildCommandScript(sessionId,
      `session.move(${JSON.stringify(handle)}, ${xRatio}, ${yRatio}, ${JSON.stringify(phase)})`);
  }
}
