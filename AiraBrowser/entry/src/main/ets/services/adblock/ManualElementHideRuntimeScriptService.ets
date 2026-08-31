const MANUAL_HIDE_STYLE_ID: string = 'aira-manual-element-hide-style';
const MANUAL_HIDE_SESSION_KEY: string = '__airaManualElementHideSession';

export interface ManualElementHideSessionSnapshot {
  selectors: string[];
}

export interface ManualElementHideApplyRuntimeResult {
  selectorCount: number;
  hiddenElementCount: number;
}

export interface ManualElementHideSelectionRuntimeState {
  selectedCount: number;
  selectedElementSelector: string;
}

export interface ManualElementHideNavigationRuntimeResult {
  selectedCount: number;
  selectedElementSelector: string;
  changed: boolean;
  reason: string;
}

export class ManualElementHideRuntimeScriptService {
  buildApplyRulesScript(selectors: string[], pageUrl: string = ''): string {
    const selectorList = JSON.stringify(selectors);
    const pageUrlValue = JSON.stringify(pageUrl);
    return `
;(function airaManualElementHideApply() {
  var selectors = ${selectorList};
  var pageUrl = ${pageUrlValue};
  if (!Array.isArray(selectors) || selectors.length === 0 || !document.documentElement) {
    return '{"selectorCount":0,"hiddenElementCount":0}';
  }
  var styleId = '${MANUAL_HIDE_STYLE_ID}';
  var css = selectors.join(',\\n') + '{display:none!important;visibility:hidden!important;}';
  var style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    style.setAttribute('data-aira-manual-hide', 'true');
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = css;
  var marker = 'data-aira-manual-hidden';
  var runtimeKey = '__airaManualElementHideRuntime';
  window[runtimeKey] = {
    selectors: selectors.slice(0),
    pageUrl: pageUrl || String(location.href || '')
  };
  var hide = function() {
    var runtime = window[runtimeKey] || {};
    var activeSelectors = Array.isArray(runtime.selectors) ? runtime.selectors : selectors;
    var hiddenCount = 0;
    activeSelectors.forEach(function(selector) {
      try {
        document.querySelectorAll(selector).forEach(function(node) {
          if (!node || node.nodeType !== 1 || node.hasAttribute(marker)) {
            return;
          }
          node.setAttribute(marker, 'true');
          node.style.setProperty('display', 'none', 'important');
          node.style.setProperty('visibility', 'hidden', 'important');
          hiddenCount += 1;
        });
      } catch (error) {}
    });
    return hiddenCount;
  };
  var initialHiddenCount = hide();
  var reportHidden = function(count, phase) {
    if (!count || count <= 0) {
      return;
    }
    var runtime = window[runtimeKey] || {};
    try {
      var bridge = window.__airaAdBlockNativeBridge;
      if (bridge && typeof bridge.onManualHidden === 'function') {
        bridge.onManualHidden(JSON.stringify({
          pageUrl: String(runtime.pageUrl || pageUrl || location.href || ''),
          count: count,
          phase: phase
        }));
      }
    } catch (error) {}
  };
  if (!window.__airaManualElementHideObserver) {
    window.__airaManualElementHideObserver = new MutationObserver(function() {
      if (window.__airaManualElementHideTimer) {
        clearTimeout(window.__airaManualElementHideTimer);
      }
      window.__airaManualElementHideTimer = setTimeout(function() {
        reportHidden(hide(), 'mutation');
      }, 80);
    });
    window.__airaManualElementHideObserver.observe(document.documentElement, { childList: true, subtree: true });
  }
  return JSON.stringify({
    selectorCount: selectors.length,
    hiddenElementCount: initialHiddenCount
  });
})();`;
  }

  buildStartSelectionScript(): string {
    return `
;(function airaManualElementHideStartSelection() {
  if (!document.documentElement) {
    return 'unavailable';
  }
  var existing = window.${MANUAL_HIDE_SESSION_KEY};
  if (existing && existing.active && typeof existing.destroy === 'function') {
    existing.destroy(false);
  }
  var selected = [];
  var selectedItems = [];
  var childTrail = [];
  var capture = document.createElement('div');
  capture.id = 'aira-manual-hide-capture';
  capture.setAttribute('data-aira-manual-hide-ui', 'true');
  capture.style.cssText = [
    'position:fixed!important',
    'left:0!important',
    'top:0!important',
    'right:0!important',
    'bottom:0!important',
    'width:auto!important',
    'height:auto!important',
    'display:block!important',
    'visibility:visible!important',
    'opacity:1!important',
    'pointer-events:auto!important',
    'touch-action:auto!important',
    'z-index:2147483647!important',
    'background:transparent!important'
  ].join(';');
  document.documentElement.appendChild(capture);
  var overlay = document.createElement('div');
  overlay.id = 'aira-manual-hide-highlight';
  overlay.setAttribute('data-aira-manual-hide-ui', 'true');
  overlay.style.cssText = [
    'position:fixed!important',
    'left:0!important',
    'top:0!important',
    'width:0',
    'height:0',
    'pointer-events:none!important',
    'z-index:2147483647!important',
    'background:rgba(10,89,247,0.14)',
    'outline:2px solid rgba(10,89,247,0.92)',
    'box-shadow:0 0 0 99999px rgba(0,0,0,0.05)',
    'border-radius:4px',
    'display:none'
  ].join(';');
  document.documentElement.appendChild(overlay);
  var previousCursor = document.documentElement.style.cursor;
  document.documentElement.style.cursor = 'crosshair';
  function isAiraUi(node) {
    return !!(node && node.nodeType === 1 && node.closest && node.closest('[data-aira-manual-hide-ui="true"]'));
  }
  function isSelectable(node) {
    if (!node || node.nodeType !== 1 || node === document.documentElement || node === document.body) {
      return false;
    }
    if (isAiraUi(node)) {
      return false;
    }
    var rect = node.getBoundingClientRect();
    return rect.width >= 8 && rect.height >= 8;
  }
  function resolveNodeAtPoint(clientX, clientY) {
    var previousPointerEvents = capture.style.pointerEvents;
    var previousPointerEventsPriority = capture.style.getPropertyPriority('pointer-events');
    capture.style.setProperty('pointer-events', 'none', 'important');
    var node = null;
    try {
      node = document.elementFromPoint(clientX, clientY);
    } catch (error) {}
    capture.style.setProperty(
      'pointer-events',
      previousPointerEvents || 'auto',
      previousPointerEventsPriority || 'important'
    );
    return node;
  }
  function buildStableInlineStyleSelector(node) {
    if (!node || node.nodeType !== 1 || !node.style || !node.tagName) {
      return '';
    }
    var backgroundPosition = String(node.style.backgroundPosition || '');
    var backgroundSize = String(node.style.backgroundSize || '');
    if (backgroundPosition.length <= 0 || backgroundSize.length <= 0) {
      return '';
    }
    var horizontalEdge = String(node.style.left || '').length > 0
      ? 'left'
      : (String(node.style.right || '').length > 0 ? 'right' : '');
    var verticalEdge = String(node.style.bottom || '').length > 0
      ? 'bottom'
      : (String(node.style.top || '').length > 0 ? 'top' : '');
    if (horizontalEdge.length <= 0 || verticalEdge.length <= 0) {
      return '';
    }
    return node.tagName.toLowerCase() +
      '[style*="background-position"]' +
      '[style*="background-size"]' +
      '[style*="' + horizontalEdge + ':"]' +
      '[style*="' + verticalEdge + ':"]';
  }
  function buildSelector(node) {
    if (!node || node.nodeType !== 1) {
      return '';
    }
    var stableInlineStyleSelector = buildStableInlineStyleSelector(node);
    if (stableInlineStyleSelector.length > 0) {
      return stableInlineStyleSelector;
    }
    if (node.id && /^[A-Za-z][A-Za-z0-9_-]*$/.test(node.id)) {
      return '#' + node.id;
    }
    var parts = [];
    var current = node;
    while (current && current.nodeType === 1 && current !== document.documentElement && current !== document.body && parts.length < 5) {
      var name = current.tagName.toLowerCase();
      var part = name;
      var stableClass = '';
      if (current.classList && current.classList.length > 0) {
        for (var index = 0; index < current.classList.length; index++) {
          var className = current.classList[index];
          if (/^[A-Za-z_-][A-Za-z0-9_-]*$/.test(className) && !/[0-9]{3,}/.test(className)) {
            stableClass = className;
            break;
          }
        }
      }
      if (stableClass.length > 0) {
        part += '.' + stableClass;
      } else if (current.parentElement) {
        var siblings = Array.prototype.filter.call(current.parentElement.children, function(child) {
          return child.tagName === current.tagName;
        });
        if (siblings.length > 1) {
          part += ':nth-of-type(' + (siblings.indexOf(current) + 1) + ')';
        }
      }
      parts.unshift(part);
      if (stableClass.length > 0 && parts.length >= 2) {
        break;
      }
      current = current.parentElement;
    }
    return parts.join(' > ');
  }
  function highlight(node) {
    if (!isSelectable(node)) {
      hideHighlight();
      return;
    }
    var rect = node.getBoundingClientRect();
    overlay.style.display = 'block';
    overlay.style.left = Math.max(0, rect.left) + 'px';
    overlay.style.top = Math.max(0, rect.top) + 'px';
    overlay.style.width = Math.max(0, rect.width) + 'px';
    overlay.style.height = Math.max(0, rect.height) + 'px';
  }
  function hideHighlight() {
    overlay.style.display = 'none';
  }
  function createSelectedNodeState(node) {
    return {
      node: node,
      outline: node.style.outline || '',
      outlineOffset: node.style.outlineOffset || '',
      boxShadow: node.style.boxShadow || ''
    };
  }
  function resolveSelectedNodes(node, selector) {
    var nodes = [];
    try {
      var matches = document.querySelectorAll(selector);
      for (var index = 0; index < matches.length && nodes.length < 120; index++) {
        if (isSelectable(matches[index]) && nodes.indexOf(matches[index]) < 0) {
          nodes.push(matches[index]);
        }
      }
    } catch (error) {}
    if (nodes.indexOf(node) < 0) {
      nodes.push(node);
    }
    return nodes;
  }
  function restoreSelectedItem(item) {
    if (!item || !Array.isArray(item.nodeStates)) {
      return;
    }
    item.nodeStates.forEach(function(state) {
      if (!state || !state.node || !state.node.style) {
        return;
      }
      state.node.style.outline = state.outline;
      state.node.style.outlineOffset = state.outlineOffset;
      state.node.style.boxShadow = state.boxShadow;
      state.node.removeAttribute('data-aira-manual-hide-preview');
    });
  }
  function createSelectedItem(node, selector) {
    var nodeStates = [];
    resolveSelectedNodes(node, selector).forEach(function(selectedNode) {
      nodeStates.push(createSelectedNodeState(selectedNode));
    });
    return {
      node: node,
      nodeStates: nodeStates
    };
  }
  function applySelectedItem(item) {
    if (!item || !Array.isArray(item.nodeStates)) {
      return;
    }
    item.nodeStates.forEach(function(state) {
      if (!state || !state.node || !state.node.style) {
        return;
      }
      state.node.setAttribute('data-aira-manual-hide-preview', 'true');
      state.node.style.setProperty('outline', '2px solid #FF3B30', 'important');
      state.node.style.setProperty('outline-offset', '-2px', 'important');
      state.node.style.setProperty('box-shadow', '0 0 0 2px rgba(255,59,48,0.20)', 'important');
    });
  }
  function selectNode(node, selector) {
    selected.push(selector);
    window.__airaManualElementHideSelectedCount = selected.length;
    var item = createSelectedItem(node, selector);
    selectedItems.push(item);
    applySelectedItem(item);
    childTrail = [];
  }
  function replaceCurrentNode(node) {
    if (!isSelectable(node) || selectedItems.length === 0) {
      return false;
    }
    var selector = buildSelector(node);
    if (selector.length <= 0) {
      return false;
    }
    var currentIndex = selectedItems.length - 1;
    var duplicateIndex = selected.indexOf(selector);
    if (duplicateIndex >= 0 && duplicateIndex !== currentIndex) {
      return false;
    }
    var currentItem = selectedItems[currentIndex];
    if (currentItem && currentItem.node === node) {
      return false;
    }
    restoreSelectedItem(currentItem);
    var nextItem = createSelectedItem(node, selector);
    selected[currentIndex] = selector;
    selectedItems[currentIndex] = nextItem;
    applySelectedItem(nextItem);
    hideHighlight();
    return true;
  }
  function firstSelectableChild(node) {
    if (!node || !node.children) {
      return null;
    }
    for (var index = 0; index < node.children.length; index++) {
      if (isSelectable(node.children[index])) {
        return node.children[index];
      }
    }
    return null;
  }
  function resolveSelectedElementSelector() {
    if (selectedItems.length === 0 || selected.length === 0) {
      return '';
    }
    return String(selected[selected.length - 1] || '').trim();
  }
  function buildSelectionState() {
    return JSON.stringify({
      selectedCount: selected.length,
      selectedElementSelector: resolveSelectedElementSelector()
    });
  }
  function buildNavigationResult(changed, reason) {
    return JSON.stringify({
      selectedCount: selected.length,
      selectedElementSelector: resolveSelectedElementSelector(),
      changed: changed,
      reason: reason
    });
  }
  function navigate(direction) {
    if (selectedItems.length === 0) {
      return buildNavigationResult(false, 'no_selection');
    }
    var currentItem = selectedItems[selectedItems.length - 1];
    var currentNode = currentItem && currentItem.node;
    if (!currentNode) {
      return buildNavigationResult(false, 'runtime_unavailable');
    }
    if (direction === 'parent') {
      var parentNode = currentNode.parentElement;
      if (!isSelectable(parentNode)) {
        return buildNavigationResult(false, 'no_parent');
      }
      if (replaceCurrentNode(parentNode)) {
        childTrail.push(currentNode);
        return buildNavigationResult(true, 'changed');
      }
      return buildNavigationResult(false, 'unchanged');
    }
    if (direction !== 'child') {
      return buildNavigationResult(false, 'runtime_unavailable');
    }
    var trailNode = childTrail.length > 0 ? childTrail[childTrail.length - 1] : null;
    if (trailNode && trailNode.parentElement === currentNode && replaceCurrentNode(trailNode)) {
      childTrail.pop();
      return buildNavigationResult(true, 'changed');
    }
    if (trailNode) {
      childTrail = [];
    }
    var childNode = firstSelectableChild(currentNode);
    if (!childNode) {
      return buildNavigationResult(false, 'no_child');
    }
    if (replaceCurrentNode(childNode)) {
      return buildNavigationResult(true, 'changed');
    }
    return buildNavigationResult(false, 'unchanged');
  }
  function onMove(event) {
    highlight(resolveNodeAtPoint(event.clientX, event.clientY));
  }
  function onClick(event) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    var node = resolveNodeAtPoint(event.clientX, event.clientY);
    if (!isSelectable(node)) {
      hideHighlight();
      return;
    }
    var selector = buildSelector(node);
    if (selector.length <= 0 || selected.indexOf(selector) >= 0) {
      hideHighlight();
      return;
    }
    selectNode(node, selector);
    hideHighlight();
  }
  var touchStartX = 0;
  var touchStartY = 0;
  var touchMoved = false;
  function onTouchStart(event) {
    event.stopPropagation();
    event.stopImmediatePropagation();
    var touch = event.touches && event.touches.length > 0 ? event.touches[0] : null;
    if (!touch) {
      hideHighlight();
      return;
    }
    touchStartX = touch.clientX;
    touchStartY = touch.clientY;
    touchMoved = false;
    highlight(resolveNodeAtPoint(touch.clientX, touch.clientY));
  }
  function onTouchMove(event) {
    event.stopPropagation();
    event.stopImmediatePropagation();
    var touch = event.touches && event.touches.length > 0 ? event.touches[0] : null;
    if (!touch) {
      hideHighlight();
      return;
    }
    if (Math.abs(touch.clientX - touchStartX) > 8 || Math.abs(touch.clientY - touchStartY) > 8) {
      touchMoved = true;
    }
    highlight(resolveNodeAtPoint(touch.clientX, touch.clientY));
  }
  function onTouchEnd(event) {
    event.stopPropagation();
    event.stopImmediatePropagation();
    if (touchMoved) {
      hideHighlight();
      return;
    }
    var touch = event.changedTouches && event.changedTouches.length > 0 ? event.changedTouches[0] : null;
    if (!touch) {
      hideHighlight();
      return;
    }
    event.preventDefault();
    var node = resolveNodeAtPoint(touch.clientX, touch.clientY);
    if (!isSelectable(node)) {
      hideHighlight();
      return;
    }
    var selector = buildSelector(node);
    if (selector.length <= 0 || selected.indexOf(selector) >= 0) {
      hideHighlight();
      return;
    }
    selectNode(node, selector);
    hideHighlight();
  }
  function destroy(restore) {
    capture.removeEventListener('mousemove', onMove, true);
    capture.removeEventListener('click', onClick, true);
    capture.removeEventListener('touchstart', onTouchStart, true);
    capture.removeEventListener('touchmove', onTouchMove, true);
    capture.removeEventListener('touchend', onTouchEnd, true);
    if (capture.parentNode) {
      capture.parentNode.removeChild(capture);
    }
    if (overlay.parentNode) {
      overlay.parentNode.removeChild(overlay);
    }
    document.documentElement.style.cursor = previousCursor || '';
    selectedItems.slice(0).reverse().forEach(function(item) {
      restoreSelectedItem(item);
    });
    childTrail = [];
    window.${MANUAL_HIDE_SESSION_KEY}.active = false;
  }
  function undo() {
    var item = selectedItems.pop();
    var selector = selected.pop();
    window.__airaManualElementHideSelectedCount = selected.length;
    restoreSelectedItem(item);
    childTrail = [];
    return selected.length;
  }
  window.${MANUAL_HIDE_SESSION_KEY} = {
    active: true,
    selected: selected,
    destroy: destroy,
    navigate: navigate,
    undo: undo,
    selectionState: buildSelectionState,
    snapshot: function() {
      return JSON.stringify({ selectors: selected.slice(0) });
    }
  };
  capture.addEventListener('mousemove', onMove, true);
  capture.addEventListener('click', onClick, true);
  capture.addEventListener('touchstart', onTouchStart, true);
  capture.addEventListener('touchmove', onTouchMove, true);
  capture.addEventListener('touchend', onTouchEnd, true);
  return 'started';
})();`;
  }

  buildSnapshotSelectionScript(): string {
    return `
;(function airaManualElementHideSnapshotSelection() {
  var session = window.${MANUAL_HIDE_SESSION_KEY};
  if (!session || typeof session.snapshot !== 'function') {
    return '{"selectors":[]}';
  }
  return session.snapshot();
})();`;
  }

  buildUndoSelectionScript(): string {
    return `
;(function airaManualElementHideUndoSelection() {
  var session = window.${MANUAL_HIDE_SESSION_KEY};
  if (!session || typeof session.undo !== 'function') {
    return '0';
  }
  return String(session.undo());
})();`;
  }

  buildNavigateSelectionScript(direction: 'parent' | 'child'): string {
    return `
;(function airaManualElementHideNavigateSelection() {
  var session = window.${MANUAL_HIDE_SESSION_KEY};
  if (!session || typeof session.navigate !== 'function') {
    return '{"selectedCount":0,"selectedElementSelector":"","changed":false,"reason":"runtime_unavailable"}';
  }
  return session.navigate('${direction}');
})();`;
  }

  buildSelectionStateScript(): string {
    return `
;(function airaManualElementHideSelectionState() {
  var session = window.${MANUAL_HIDE_SESSION_KEY};
  if (!session || typeof session.selectionState !== 'function') {
    return '{"selectedCount":0,"selectedElementSelector":""}';
  }
  return session.selectionState();
})();`;
  }

  buildStopSelectionScript(restore: boolean): string {
    return `
;(function airaManualElementHideStopSelection() {
  var session = window.${MANUAL_HIDE_SESSION_KEY};
  if (!session || typeof session.destroy !== 'function') {
    return 'stopped';
  }
  session.destroy(${restore ? 'true' : 'false'});
  return 'stopped';
})();`;
  }

  parseSessionSnapshot(rawValue: string): ManualElementHideSessionSnapshot {
    const normalized = this.unwrapJsonString(rawValue);
    try {
      const parsed = JSON.parse(normalized) as ManualElementHideSessionSnapshot;
      return {
        selectors: Array.isArray(parsed.selectors) ? parsed.selectors.map((selector: string) => {
          return `${selector ?? ''}`.trim();
        }).filter((selector: string) => selector.length > 0) : []
      };
    } catch (_error) {
      return {
        selectors: []
      };
    }
  }

  parseApplyRuntimeResult(rawValue: string): ManualElementHideApplyRuntimeResult {
    const normalized = this.unwrapJsonString(rawValue);
    try {
      const parsed = JSON.parse(normalized) as ManualElementHideApplyRuntimeResult;
      return {
        selectorCount: this.normalizeCount(parsed.selectorCount),
        hiddenElementCount: this.normalizeCount(parsed.hiddenElementCount)
      };
    } catch (_error) {
      const count = this.normalizeCount(Number.parseInt(normalized, 10));
      return {
        selectorCount: count,
        hiddenElementCount: 0
      };
    }
  }

  parseNavigationRuntimeResult(rawValue: string): ManualElementHideNavigationRuntimeResult {
    const normalized = this.unwrapJsonString(rawValue);
    try {
      const parsed = JSON.parse(normalized) as ManualElementHideNavigationRuntimeResult;
      return {
        selectedCount: this.normalizeCount(parsed.selectedCount),
        selectedElementSelector: this.normalizeElementSelector(`${parsed.selectedElementSelector ?? ''}`),
        changed: parsed.changed === true,
        reason: this.normalizeNavigationReason(`${parsed.reason ?? ''}`)
      };
    } catch (_error) {
      return this.emptyNavigationRuntimeResult();
    }
  }

  parseSelectionRuntimeState(rawValue: string): ManualElementHideSelectionRuntimeState {
    const normalized = this.unwrapJsonString(rawValue);
    try {
      const parsed = JSON.parse(normalized) as ManualElementHideSelectionRuntimeState;
      return {
        selectedCount: this.normalizeCount(parsed.selectedCount),
        selectedElementSelector: this.normalizeElementSelector(`${parsed.selectedElementSelector ?? ''}`)
      };
    } catch (_error) {
      return this.emptySelectionRuntimeState();
    }
  }

  unwrapJsonString(rawValue: string): string {
    const trimmed = String(rawValue ?? '').trim();
    if (trimmed.length >= 2 && trimmed.charAt(0) === '"' && trimmed.charAt(trimmed.length - 1) === '"') {
      try {
        const decoded = JSON.parse(trimmed) as string;
        if (typeof decoded === 'string') {
          return decoded;
        }
      } catch (_error) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  private normalizeCount(value: number): number {
    return typeof value === 'number' && value > 0 ? Math.floor(value) : 0;
  }

  private normalizeElementSelector(value: string): string {
    return `${value ?? ''}`.trim();
  }

  private normalizeNavigationReason(value: string): string {
    switch (value) {
      case 'changed':
      case 'no_selection':
      case 'no_parent':
      case 'no_child':
      case 'unchanged':
      case 'runtime_unavailable':
        return value;
      default:
        return 'runtime_unavailable';
    }
  }

  private emptyNavigationRuntimeResult(): ManualElementHideNavigationRuntimeResult {
    return {
      selectedCount: 0,
      selectedElementSelector: '',
      changed: false,
      reason: 'runtime_unavailable'
    };
  }

  private emptySelectionRuntimeState(): ManualElementHideSelectionRuntimeState {
    return {
      selectedCount: 0,
      selectedElementSelector: ''
    };
  }
}
