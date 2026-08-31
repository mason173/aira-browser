export type ElementInspectionRuntimeMode = 'selecting' | 'inspected';

export type ElementInspectionNavigationRelation =
  'parent' |
  'first_child' |
  'previous_sibling' |
  'next_sibling';

export interface ElementInspectionRuntimeAttribute {
  name: string;
  value: string;
  redacted: boolean;
}

export interface ElementInspectionRuntimeRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface ElementInspectionRuntimeNodeSnapshot {
  tagName: string;
  elementId: string;
  classTokens: string[];
  selector: string;
  breadcrumb: string[];
  attributes: ElementInspectionRuntimeAttribute[];
  textPreview: string;
  htmlPreview: string;
  htmlLength: number;
  rect: ElementInspectionRuntimeRect;
  hasParent: boolean;
  hasFirstChild: boolean;
  hasPreviousSibling: boolean;
  hasNextSibling: boolean;
}

export interface ElementInspectionRuntimeSnapshot {
  ok: boolean;
  reason: string;
  protocolVersion: number;
  sessionGeneration: number;
  documentToken: string;
  revision: number;
  mode: ElementInspectionRuntimeMode;
  node?: ElementInspectionRuntimeNodeSnapshot;
}

export interface ElementInspectionHtmlChunkResult {
  ok: boolean;
  reason: string;
  protocolVersion: number;
  sessionGeneration: number;
  documentToken: string;
  revision: number;
  offset: number;
  totalLength: number;
  value: string;
}

const ELEMENT_INSPECTION_PROTOCOL_VERSION: number = 2;
const ELEMENT_INSPECTION_HTML_TRANSFER_CHUNK_SIZE: number = 16384;

export class ElementInspectionRuntimeScriptService {
  buildInstallScript(sessionGeneration: number, documentToken: string, highlightColor: string): string {
    const normalizedGeneration = Math.max(0, Math.floor(sessionGeneration));
    const encodedDocumentToken = this.encodeScriptString(documentToken);
    const encodedHighlightColor = this.encodeScriptString(highlightColor);
    return `
;(function airaElementInspectionInstall() {
  var protocolVersion = ${ELEMENT_INSPECTION_PROTOCOL_VERSION};
  var expectedSessionGeneration = ${normalizedGeneration};
  var expectedDocumentToken = ${encodedDocumentToken};
  var runtimeKey = '__airaElementInspectionRuntime';
  var uiAttribute = 'data-aira-element-inspection-ui';
  var highlightId = 'aira-element-inspection-highlight';
  var htmlTransferChunkSize = ${ELEMENT_INSPECTION_HTML_TRANSFER_CHUNK_SIZE};
  var highlightColor = ${encodedHighlightColor} || 'Highlight';
  if (!document.documentElement) {
    return JSON.stringify({
      ok: false,
      reason: 'document_unavailable',
      protocolVersion: protocolVersion,
      sessionGeneration: expectedSessionGeneration,
      documentToken: expectedDocumentToken,
      revision: 0,
      mode: 'selecting'
    });
  }
  var existing = window[runtimeKey];
  if (existing && typeof existing.destroy === 'function') {
    try {
      existing.destroy();
    } catch (error) {}
  }
  function safeString(value, limit) {
    var normalized = String(value === undefined || value === null ? '' : value);
    if (normalized.length <= limit) {
      return normalized;
    }
    return normalized.substring(0, Math.max(0, limit));
  }
  function isSensitiveAttribute(name) {
    var lower = String(name || '').toLowerCase();
    return lower === 'value' || lower === 'srcdoc' || lower.indexOf('nonce') >= 0 ||
      lower.indexOf('password') >= 0 || lower.indexOf('token') >= 0 ||
      lower.indexOf('secret') >= 0 || lower.indexOf('authorization') >= 0;
  }
  function sanitizeAttributeValue(name, value) {
    if (isSensitiveAttribute(name)) {
      return { value: '[已隐藏]', redacted: true };
    }
    return { value: String(value === undefined || value === null ? '' : value), redacted: false };
  }
  function collectAttributes(node) {
    var result = [];
    if (!node || !node.attributes) {
      return result;
    }
    for (var index = 0; index < node.attributes.length; index++) {
      var attribute = node.attributes[index];
      if (!attribute) {
        continue;
      }
      var name = String(attribute.name || '');
      var sanitized = sanitizeAttributeValue(name, attribute.value);
      result.push({
        name: name,
        value: sanitized.value,
        redacted: sanitized.redacted
      });
    }
    return result;
  }
  function sanitizeElementAttributes(node) {
    if (!node || node.nodeType !== 1 || !node.attributes) {
      return;
    }
    for (var index = 0; index < node.attributes.length; index++) {
      var attribute = node.attributes[index];
      if (attribute && isSensitiveAttribute(attribute.name)) {
        attribute.value = '[已隐藏]';
      }
    }
  }
  function sanitizeElementTree(root) {
    var pendingNodes = [root];
    while (pendingNodes.length > 0) {
      var currentNode = pendingNodes.pop();
      if (!currentNode) {
        continue;
      }
      sanitizeElementAttributes(currentNode);
      var childNodes = currentNode.childNodes || [];
      for (var childIndex = childNodes.length - 1; childIndex >= 0; childIndex--) {
        pendingNodes.push(childNodes[childIndex]);
      }
      if (currentNode.nodeType === 1 && String(currentNode.tagName || '').toLowerCase() === 'template' &&
        currentNode.content) {
        var templateChildNodes = currentNode.content.childNodes || [];
        for (var templateChildIndex = templateChildNodes.length - 1; templateChildIndex >= 0;
          templateChildIndex--) {
          pendingNodes.push(templateChildNodes[templateChildIndex]);
        }
      }
    }
  }
  function buildSanitizedHtml(node) {
    var implementation = document.implementation;
    if (!node || node.nodeType !== 1 || !implementation ||
      typeof implementation.createHTMLDocument !== 'function') {
      return '';
    }
    var inertDocument = implementation.createHTMLDocument('');
    if (!inertDocument || typeof inertDocument.importNode !== 'function') {
      return '';
    }
    var importedNode = inertDocument.importNode(node, true);
    sanitizeElementTree(importedNode);
    return String(importedNode.outerHTML || '');
  }
  function buildTextPreview(node) {
    if (!node) {
      return '';
    }
    var tagName = String(node.tagName || '').toLowerCase();
    if (tagName === 'input' || tagName === 'textarea') {
      return '';
    }
    var parts = [];
    var remaining = 512;
    var visited = 0;
    var walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    var current = walker.nextNode();
    while (current && remaining > 0 && visited < 96) {
      var text = String(current.nodeValue || '').replace(/\s+/g, ' ').trim();
      if (text.length > 0) {
        var value = text.length <= remaining ? text : text.substring(0, remaining);
        parts.push(value);
        remaining -= value.length;
      }
      visited += 1;
      current = walker.nextNode();
    }
    return parts.join(' ').substring(0, 512);
  }
  function escapeCssIdentifier(value) {
    return String(value || '').replace(/[^A-Za-z0-9_-]/g, function(character) {
      return '\\\\' + character;
    });
  }
  function selectorResolvesToNode(selector, node) {
    if (!selector || !node) {
      return false;
    }
    try {
      var matches = document.querySelectorAll(selector);
      return matches.length === 1 && matches[0] === node;
    } catch (error) {
      return false;
    }
  }
  function buildSelector(node) {
    if (!node || node.nodeType !== 1) {
      return '';
    }
    var parts = [];
    var current = node;
    var visited = 0;
    while (current && current.nodeType === 1 && visited < 128) {
      var name = String(current.tagName || 'div').toLowerCase();
      var part = name;
      if (current.id && /^[A-Za-z][A-Za-z0-9_-]*$/.test(current.id)) {
        part = '#' + current.id;
      } else {
        var stableClass = '';
        if (current.classList && current.classList.length > 0) {
          for (var classIndex = 0; classIndex < current.classList.length; classIndex++) {
            var className = String(current.classList[classIndex] || '');
            if (/^[A-Za-z_-][A-Za-z0-9_-]*$/.test(className) && !/[0-9]{4,}/.test(className)) {
              stableClass = className;
              break;
            }
          }
        }
        if (stableClass.length > 0) {
          part += '.' + escapeCssIdentifier(stableClass);
        }
      }
      if (current.parentElement) {
        var sameTagIndex = 0;
        var sameTagCount = 0;
        var siblings = current.parentElement.children || [];
        for (var siblingIndex = 0; siblingIndex < siblings.length; siblingIndex++) {
          if (siblings[siblingIndex].tagName === current.tagName) {
            sameTagCount += 1;
            if (siblings[siblingIndex] === current) {
              sameTagIndex = sameTagCount;
            }
          }
        }
        if (sameTagCount > 1 && sameTagIndex > 0) {
          part += ':nth-of-type(' + sameTagIndex + ')';
        }
      }
      parts.unshift(part);
      var candidate = parts.join(' > ');
      if (candidate.length > 2000) {
        return '';
      }
      if (selectorResolvesToNode(candidate, node)) {
        return candidate;
      }
      if (current === document.documentElement) {
        return '';
      }
      visited += 1;
      current = current.parentElement;
    }
    return '';
  }
  function describeNode(node) {
    if (!node || node.nodeType !== 1) {
      return '';
    }
    var value = String(node.tagName || 'div').toLowerCase();
    if (node.id) {
      value += '#' + safeString(node.id, 64);
    }
    if (node.classList && node.classList.length > 0) {
      var classLimit = Math.min(node.classList.length, 2);
      for (var index = 0; index < classLimit; index++) {
        value += '.' + safeString(node.classList[index], 48);
      }
    }
    return safeString(value, 160);
  }
  function buildBreadcrumb(node) {
    var result = [];
    var current = node;
    while (current && current.nodeType === 1 && result.length < 12) {
      result.unshift(describeNode(current));
      current = current.parentElement;
    }
    return result;
  }
  function normalizeElement(node) {
    if (!node) {
      return null;
    }
    if (node.nodeType === 1) {
      return node;
    }
    return node.parentElement || null;
  }
  function isAiraUi(node) {
    return !!(node && node.nodeType === 1 && node.closest && node.closest('[' + uiAttribute + '="true"]'));
  }
  function isSelectable(node) {
    var element = normalizeElement(node);
    if (!element || isAiraUi(element)) {
      return false;
    }
    var rect = element.getBoundingClientRect();
    return rect.width >= 1 && rect.height >= 1;
  }
  function resolveSelectableParent(node) {
    var current = normalizeElement(node);
    var visited = 0;
    while (current && current.parentElement && visited < 128) {
      current = current.parentElement;
      if (isSelectable(current)) {
        return current;
      }
      visited += 1;
    }
    return null;
  }
  function isDirectlySelectable(node) {
    var element = normalizeElement(node);
    if (!isSelectable(element)) {
      return false;
    }
    return element !== document.documentElement && element !== document.body;
  }
  function buildHighlightFillColor(value) {
    var match = /^#([0-9A-Fa-f]{6})$/.exec(String(value || ''));
    if (!match) {
      return 'transparent';
    }
    var hex = match[1];
    return 'rgba(' + parseInt(hex.substring(0, 2), 16) + ',' +
      parseInt(hex.substring(2, 4), 16) + ',' + parseInt(hex.substring(4, 6), 16) + ',0.16)';
  }
  var highlightFillColor = buildHighlightFillColor(highlightColor);
  var highlight = document.createElement('div');
  highlight.id = highlightId;
  highlight.setAttribute(uiAttribute, 'true');
  highlight.style.cssText = [
    'position:fixed!important',
    'left:0!important',
    'top:0!important',
    'width:0!important',
    'height:0!important',
    'pointer-events:none!important',
    'z-index:2147483647!important',
    'background:' + highlightFillColor + '!important',
    'outline:2px solid ' + highlightColor + '!important',
    'outline-offset:-1px!important',
    'box-shadow:0 0 0 2px rgba(10,89,247,0.24)!important',
    'border-radius:3px!important',
    'visibility:visible!important',
    'display:none!important'
  ].join(';');
  document.documentElement.appendChild(highlight);
  var runtime = {
    active: true,
    protocolVersion: protocolVersion,
    sessionGeneration: expectedSessionGeneration,
    documentToken: expectedDocumentToken,
    revision: 0,
    mode: 'selecting',
    currentNode: null,
    currentHtml: '',
    currentHtmlRevision: -1,
    nodeDirty: false,
    mutationObserver: null,
    templateContentRoots: []
  };
  function clearCurrentHtml() {
    runtime.currentHtml = '';
    runtime.currentHtmlRevision = -1;
  }
  function observeMutationRoot(root) {
    if (!runtime.mutationObserver || !root) {
      return;
    }
    runtime.mutationObserver.observe(root, {
      attributes: true,
      characterData: true,
      childList: true,
      subtree: true
    });
  }
  function refreshMutationObservationRoots() {
    if (!runtime.mutationObserver) {
      return;
    }
    runtime.mutationObserver.disconnect();
    runtime.templateContentRoots = [];
    observeMutationRoot(document.documentElement);
    if (!runtime.currentNode) {
      return;
    }
    var pendingNodes = [runtime.currentNode];
    while (pendingNodes.length > 0) {
      var currentNode = pendingNodes.pop();
      if (!currentNode) {
        continue;
      }
      var childNodes = currentNode.childNodes || [];
      for (var childIndex = childNodes.length - 1; childIndex >= 0; childIndex--) {
        pendingNodes.push(childNodes[childIndex]);
      }
      if (currentNode.nodeType === 1 && String(currentNode.tagName || '').toLowerCase() === 'template' &&
        currentNode.content) {
        runtime.templateContentRoots.push(currentNode.content);
        observeMutationRoot(currentNode.content);
        var templateChildNodes = currentNode.content.childNodes || [];
        for (var templateChildIndex = templateChildNodes.length - 1; templateChildIndex >= 0;
          templateChildIndex--) {
          pendingNodes.push(templateChildNodes[templateChildIndex]);
        }
      }
    }
  }
  function markCurrentNodeDirty() {
    if (runtime.mode === 'inspected' && runtime.currentNode && runtime.currentNode.isConnected) {
      runtime.nodeDirty = true;
    }
  }
  function applyPendingNodeMutation() {
    if (!runtime.nodeDirty) {
      return;
    }
    runtime.nodeDirty = false;
    runtime.revision += 1;
    clearCurrentHtml();
  }
  function setCurrentNode(node) {
    runtime.currentNode = node;
    runtime.mode = 'inspected';
    runtime.nodeDirty = false;
    runtime.revision += 1;
    clearCurrentHtml();
    refreshMutationObservationRoots();
  }
  function updateHighlight() {
    var node = runtime.currentNode;
    if (!node || !node.isConnected || runtime.mode !== 'inspected') {
      highlight.style.setProperty('display', 'none', 'important');
      return;
    }
    var rect = node.getBoundingClientRect();
    highlight.style.setProperty('display', 'block', 'important');
    highlight.style.setProperty('left', Math.max(0, rect.left) + 'px', 'important');
    highlight.style.setProperty('top', Math.max(0, rect.top) + 'px', 'important');
    highlight.style.setProperty('width', Math.max(0, rect.width) + 'px', 'important');
    highlight.style.setProperty('height', Math.max(0, rect.height) + 'px', 'important');
  }
  function buildNodeSnapshot(node) {
    var rect = node.getBoundingClientRect();
    var classTokens = [];
    if (node.classList) {
      var classLimit = Math.min(node.classList.length, 16);
      for (var index = 0; index < classLimit; index++) {
        classTokens.push(safeString(node.classList[index], 64));
      }
    }
    var html = buildSanitizedHtml(node);
    runtime.currentHtml = html;
    runtime.currentHtmlRevision = runtime.revision;
    refreshMutationObservationRoots();
    return {
      tagName: String(node.tagName || '').toLowerCase(),
      elementId: safeString(node.id, 128),
      classTokens: classTokens,
      selector: safeString(buildSelector(node), 2048),
      breadcrumb: buildBreadcrumb(node),
      attributes: collectAttributes(node),
      textPreview: buildTextPreview(node),
      htmlPreview: html.substring(0, htmlTransferChunkSize),
      htmlLength: html.length,
      rect: {
        left: Number(rect.left) || 0,
        top: Number(rect.top) || 0,
        width: Number(rect.width) || 0,
        height: Number(rect.height) || 0
      },
      hasParent: !!resolveSelectableParent(node),
      hasFirstChild: !!node.firstElementChild,
      hasPreviousSibling: !!node.previousElementSibling,
      hasNextSibling: !!node.nextElementSibling
    };
  }
  runtime.snapshot = function(knownRevision) {
    if (runtime.currentNode && !runtime.currentNode.isConnected) {
      runtime.currentNode = null;
      runtime.mode = 'selecting';
      runtime.nodeDirty = false;
      runtime.revision += 1;
      clearCurrentHtml();
      refreshMutationObservationRoots();
      highlight.style.setProperty('display', 'none', 'important');
    }
    applyPendingNodeMutation();
    var result = {
      ok: true,
      reason: '',
      protocolVersion: runtime.protocolVersion,
      sessionGeneration: runtime.sessionGeneration,
      documentToken: runtime.documentToken,
      revision: runtime.revision,
      mode: runtime.mode
    };
    var normalizedKnownRevision = Number(knownRevision);
    var nodeChanged = !Number.isFinite(normalizedKnownRevision) ||
      Math.floor(normalizedKnownRevision) !== runtime.revision;
    if (runtime.mode === 'inspected' && runtime.currentNode) {
      updateHighlight();
      if (nodeChanged) {
        result.node = buildNodeSnapshot(runtime.currentNode);
      }
    }
    return result;
  };
  function selectNode(node) {
    var element = normalizeElement(node);
    if (!isSelectable(element)) {
      return false;
    }
    setCurrentNode(element);
    updateHighlight();
    return true;
  }
  runtime.reselect = function() {
    runtime.currentNode = null;
    runtime.mode = 'selecting';
    runtime.nodeDirty = false;
    runtime.revision += 1;
    clearCurrentHtml();
    refreshMutationObservationRoots();
    highlight.style.setProperty('display', 'none', 'important');
    return runtime.snapshot();
  };
  runtime.navigate = function(relation) {
    var node = runtime.currentNode;
    if (!node || !node.isConnected) {
      return runtime.reselect();
    }
    var target = null;
    if (relation === 'parent') {
      target = resolveSelectableParent(node);
    } else if (relation === 'first_child') {
      target = node.firstElementChild;
    } else if (relation === 'previous_sibling') {
      target = node.previousElementSibling;
    } else if (relation === 'next_sibling') {
      target = node.nextElementSibling;
    }
    if (target && isSelectable(target)) {
      setCurrentNode(target);
      updateHighlight();
    }
    return runtime.snapshot();
  };
  runtime.readHtmlChunk = function(expectedRevision, offset) {
    if (!runtime.currentNode || !runtime.currentNode.isConnected) {
      return {
        ok: false,
        reason: 'node_unavailable',
        protocolVersion: runtime.protocolVersion,
        sessionGeneration: runtime.sessionGeneration,
        documentToken: runtime.documentToken,
        revision: runtime.revision,
        offset: 0,
        totalLength: 0,
        value: ''
      };
    }
    var normalizedRevision = Math.max(0, Math.floor(Number(expectedRevision) || 0));
    var normalizedOffset = Math.max(0, Math.floor(Number(offset) || 0));
    if (normalizedRevision !== runtime.revision || runtime.currentHtmlRevision !== runtime.revision) {
      return {
        ok: false,
        reason: 'stale_revision',
        protocolVersion: runtime.protocolVersion,
        sessionGeneration: runtime.sessionGeneration,
        documentToken: runtime.documentToken,
        revision: runtime.revision,
        offset: normalizedOffset,
        totalLength: runtime.currentHtml.length,
        value: ''
      };
    }
    if (normalizedOffset > runtime.currentHtml.length) {
      return {
        ok: false,
        reason: 'invalid_offset',
        protocolVersion: runtime.protocolVersion,
        sessionGeneration: runtime.sessionGeneration,
        documentToken: runtime.documentToken,
        revision: runtime.revision,
        offset: normalizedOffset,
        totalLength: runtime.currentHtml.length,
        value: ''
      };
    }
    var chunkEnd = Math.min(runtime.currentHtml.length, normalizedOffset + htmlTransferChunkSize);
    if (chunkEnd < runtime.currentHtml.length && chunkEnd > normalizedOffset) {
      var lastCodeUnit = runtime.currentHtml.charCodeAt(chunkEnd - 1);
      var nextCodeUnit = runtime.currentHtml.charCodeAt(chunkEnd);
      if (lastCodeUnit >= 0xD800 && lastCodeUnit <= 0xDBFF &&
        nextCodeUnit >= 0xDC00 && nextCodeUnit <= 0xDFFF) {
        chunkEnd -= 1;
      }
    }
    var value = runtime.currentHtml.substring(normalizedOffset, chunkEnd);
    return {
      ok: true,
      reason: '',
      protocolVersion: runtime.protocolVersion,
      sessionGeneration: runtime.sessionGeneration,
      documentToken: runtime.documentToken,
      revision: runtime.revision,
      offset: normalizedOffset,
      totalLength: runtime.currentHtml.length,
      value: value
    };
  };
  function resolveViewportPoint(normalizedX, normalizedY) {
    var xRatio = Math.max(0, Math.min(1, Number(normalizedX) || 0));
    var yRatio = Math.max(0, Math.min(1, Number(normalizedY) || 0));
    var visualViewport = window.visualViewport || null;
    var viewportWidth = visualViewport && Number(visualViewport.width) > 0 ?
      Number(visualViewport.width) : Number(window.innerWidth || document.documentElement.clientWidth || 1);
    var viewportHeight = visualViewport && Number(visualViewport.height) > 0 ?
      Number(visualViewport.height) : Number(window.innerHeight || document.documentElement.clientHeight || 1);
    viewportWidth = Math.max(1, viewportWidth);
    viewportHeight = Math.max(1, viewportHeight);
    return {
      x: Math.min(Math.max(0, viewportWidth - 0.5), xRatio * viewportWidth),
      y: Math.min(Math.max(0, viewportHeight - 0.5), yRatio * viewportHeight)
    };
  }
  function resolveNodeAtNormalizedPoint(normalizedX, normalizedY) {
    var node = null;
    try {
      var viewportPoint = resolveViewportPoint(normalizedX, normalizedY);
      node = document.elementFromPoint(viewportPoint.x, viewportPoint.y);
    } catch (error) {}
    return node;
  }
  function selectAtNormalizedPoint(normalizedX, normalizedY) {
    var node = resolveNodeAtNormalizedPoint(normalizedX, normalizedY);
    if (!isDirectlySelectable(node)) {
      return false;
    }
    return selectNode(node);
  }
  runtime.selectAtNormalizedPoint = function(normalizedX, normalizedY) {
    selectAtNormalizedPoint(normalizedX, normalizedY);
    return runtime.snapshot();
  };
  function onViewportChanged() {
    updateHighlight();
  }
  function mutationTouchesCurrentNode(mutation) {
    var currentNode = runtime.currentNode;
    if (!currentNode || !mutation) {
      return false;
    }
    var target = mutation.target;
    if (target === currentNode || (currentNode.contains && currentNode.contains(target)) ||
      (target && target.contains && target.contains(currentNode))) {
      return true;
    }
    for (var rootIndex = 0; rootIndex < runtime.templateContentRoots.length; rootIndex++) {
      var templateRoot = runtime.templateContentRoots[rootIndex];
      if (templateRoot === target || (templateRoot.contains && templateRoot.contains(target))) {
        return true;
      }
    }
    var removedNodes = mutation.removedNodes || [];
    for (var index = 0; index < removedNodes.length; index++) {
      var removedNode = removedNodes[index];
      if (removedNode === currentNode || (removedNode.contains && removedNode.contains(currentNode))) {
        return true;
      }
    }
    return false;
  }
  function onDocumentMutated(mutations) {
    if (runtime.mode !== 'inspected' || !runtime.currentNode) {
      return;
    }
    for (var index = 0; index < mutations.length; index++) {
      if (mutationTouchesCurrentNode(mutations[index])) {
        markCurrentNodeDirty();
        return;
      }
    }
  }
  if (typeof MutationObserver === 'function') {
    runtime.mutationObserver = new MutationObserver(onDocumentMutated);
    refreshMutationObservationRoots();
  }
  runtime.destroy = function() {
    if (!runtime.active) {
      return;
    }
    runtime.active = false;
    window.removeEventListener('resize', onViewportChanged, true);
    window.removeEventListener('scroll', onViewportChanged, true);
    if (runtime.mutationObserver) {
      runtime.mutationObserver.disconnect();
      runtime.mutationObserver = null;
    }
    if (highlight.parentNode) {
      highlight.parentNode.removeChild(highlight);
    }
    if (window[runtimeKey] === runtime) {
      window[runtimeKey] = undefined;
    }
  };
  window[runtimeKey] = runtime;
  window.addEventListener('resize', onViewportChanged, true);
  window.addEventListener('scroll', onViewportChanged, true);
  return JSON.stringify(runtime.snapshot());
})();`;
  }

  buildReadSnapshotScript(sessionGeneration: number, documentToken: string, knownRevision: number): string {
    const normalizedRevision = Math.max(0, Math.floor(knownRevision));
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.snapshot(${normalizedRevision})`
    );
  }

  buildSelectAtNormalizedPointScript(
    sessionGeneration: number,
    documentToken: string,
    normalizedX: number,
    normalizedY: number
  ): string {
    const clampedX = Number.isFinite(normalizedX) ? Math.min(1, Math.max(0, normalizedX)) : 0;
    const clampedY = Number.isFinite(normalizedY) ? Math.min(1, Math.max(0, normalizedY)) : 0;
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.selectAtNormalizedPoint(${clampedX}, ${clampedY})`
    );
  }

  buildNavigateScript(
    sessionGeneration: number,
    documentToken: string,
    relation: ElementInspectionNavigationRelation
  ): string {
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.navigate(${this.encodeScriptString(relation)})`
    );
  }

  buildReselectScript(sessionGeneration: number, documentToken: string): string {
    return this.buildRuntimeCommandScript(sessionGeneration, documentToken, 'runtime.reselect()');
  }

  buildReadHtmlChunkScript(
    sessionGeneration: number,
    documentToken: string,
    revision: number,
    offset: number
  ): string {
    const normalizedRevision = Math.max(0, Math.floor(revision));
    const normalizedOffset = Math.max(0, Math.floor(offset));
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.readHtmlChunk(${normalizedRevision}, ${normalizedOffset})`
    );
  }

  buildStopScript(sessionGeneration: number, documentToken: string): string {
    const normalizedGeneration = Math.max(0, Math.floor(sessionGeneration));
    return `
;(function airaElementInspectionStop() {
  var runtime = window.__airaElementInspectionRuntime;
  if (!runtime || runtime.sessionGeneration !== ${normalizedGeneration} ||
    runtime.documentToken !== ${this.encodeScriptString(documentToken)}) {
    return 'stopped';
  }
  if (typeof runtime.destroy === 'function') {
    runtime.destroy();
  }
  return 'stopped';
})();`;
  }

  parseSnapshot(rawValue: string): ElementInspectionRuntimeSnapshot {
    const normalized = this.unwrapJsonString(rawValue);
    try {
      const parsed: ElementInspectionRuntimeSnapshot = JSON.parse(normalized) as ElementInspectionRuntimeSnapshot;
      if (parsed.protocolVersion !== ELEMENT_INSPECTION_PROTOCOL_VERSION || parsed.ok !== true) {
        return this.buildUnavailableSnapshot(this.normalizeString(parsed.reason, 'runtime_unavailable'));
      }
      const mode: ElementInspectionRuntimeMode = parsed.mode === 'inspected' ? 'inspected' : 'selecting';
      const result: ElementInspectionRuntimeSnapshot = {
        ok: true,
        reason: '',
        protocolVersion: ELEMENT_INSPECTION_PROTOCOL_VERSION,
        sessionGeneration: this.normalizeCount(parsed.sessionGeneration),
        documentToken: this.normalizeString(parsed.documentToken),
        revision: this.normalizeCount(parsed.revision),
        mode: mode
      };
      if (mode === 'inspected' && parsed.node !== undefined) {
        result.node = this.normalizeNode(parsed.node);
      }
      return result;
    } catch (_error) {
      return this.buildUnavailableSnapshot('invalid_snapshot');
    }
  }

  parseHtmlChunkResult(rawValue: string): ElementInspectionHtmlChunkResult {
    const normalized = this.unwrapJsonString(rawValue);
    try {
      const parsed: ElementInspectionHtmlChunkResult = JSON.parse(normalized) as ElementInspectionHtmlChunkResult;
      return {
        ok: parsed.ok === true && parsed.protocolVersion === ELEMENT_INSPECTION_PROTOCOL_VERSION,
        reason: this.normalizeString(parsed.reason),
        protocolVersion: this.normalizeCount(parsed.protocolVersion),
        sessionGeneration: this.normalizeCount(parsed.sessionGeneration),
        documentToken: this.normalizeString(parsed.documentToken),
        revision: this.normalizeCount(parsed.revision),
        offset: this.normalizeCount(parsed.offset),
        totalLength: this.normalizeCount(parsed.totalLength),
        value: this.normalizeRawString(parsed.value)
      };
    } catch (_error) {
      return {
        ok: false,
        reason: 'invalid_html_chunk_result',
        protocolVersion: ELEMENT_INSPECTION_PROTOCOL_VERSION,
        sessionGeneration: 0,
        documentToken: '',
        revision: 0,
        offset: 0,
        totalLength: 0,
        value: ''
      };
    }
  }

  unwrapJsonString(rawValue: string): string {
    const trimmed = String(rawValue ?? '').trim();
    if (trimmed.length >= 2 && trimmed.charAt(0) === '"' && trimmed.charAt(trimmed.length - 1) === '"') {
      try {
        const decoded: string = JSON.parse(trimmed) as string;
        if (typeof decoded === 'string') {
          return decoded;
        }
      } catch (_error) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  private buildRuntimeCommandScript(
    sessionGeneration: number,
    documentToken: string,
    commandExpression: string
  ): string {
    const normalizedGeneration = Math.max(0, Math.floor(sessionGeneration));
    return `
;(function airaElementInspectionCommand() {
  var runtime = window.__airaElementInspectionRuntime;
  if (!runtime || runtime.sessionGeneration !== ${normalizedGeneration} ||
    runtime.documentToken !== ${this.encodeScriptString(documentToken)}) {
    return JSON.stringify({
      ok: false,
      reason: 'runtime_unavailable',
      protocolVersion: ${ELEMENT_INSPECTION_PROTOCOL_VERSION},
      sessionGeneration: ${normalizedGeneration},
      documentToken: ${this.encodeScriptString(documentToken)},
      revision: 0,
      mode: 'selecting'
    });
  }
  return JSON.stringify(${commandExpression});
})();`;
  }

  private normalizeNode(node: ElementInspectionRuntimeNodeSnapshot): ElementInspectionRuntimeNodeSnapshot {
    const classTokens: string[] = [];
    if (Array.isArray(node.classTokens)) {
      node.classTokens.forEach((value: string): void => {
        const normalized = this.normalizeString(value);
        if (normalized.length > 0) {
          classTokens.push(normalized);
        }
      });
    }
    const breadcrumb: string[] = [];
    if (Array.isArray(node.breadcrumb)) {
      node.breadcrumb.forEach((value: string): void => {
        const normalized = this.normalizeString(value);
        if (normalized.length > 0) {
          breadcrumb.push(normalized);
        }
      });
    }
    const attributes: ElementInspectionRuntimeAttribute[] = [];
    if (Array.isArray(node.attributes)) {
      node.attributes.forEach((attribute: ElementInspectionRuntimeAttribute): void => {
        const normalizedAttribute: ElementInspectionRuntimeAttribute = {
          name: this.normalizeString(attribute.name),
          value: this.normalizeString(attribute.value),
          redacted: attribute.redacted === true
        };
        if (normalizedAttribute.name.length > 0) {
          attributes.push(normalizedAttribute);
        }
      });
    }
    const rect: ElementInspectionRuntimeRect = node.rect ?? {
      left: 0,
      top: 0,
      width: 0,
      height: 0
    };
    return {
      tagName: this.normalizeString(node.tagName, 'element'),
      elementId: this.normalizeString(node.elementId),
      classTokens: classTokens,
      selector: this.normalizeString(node.selector),
      breadcrumb: breadcrumb,
      attributes: attributes,
      textPreview: this.normalizeString(node.textPreview),
      htmlPreview: this.normalizeRawString(node.htmlPreview),
      htmlLength: this.normalizeCount(node.htmlLength),
      rect: {
        left: this.normalizeNumber(rect.left),
        top: this.normalizeNumber(rect.top),
        width: this.normalizeNumber(rect.width),
        height: this.normalizeNumber(rect.height)
      },
      hasParent: node.hasParent === true,
      hasFirstChild: node.hasFirstChild === true,
      hasPreviousSibling: node.hasPreviousSibling === true,
      hasNextSibling: node.hasNextSibling === true
    };
  }

  private buildUnavailableSnapshot(reason: string): ElementInspectionRuntimeSnapshot {
    return {
      ok: false,
      reason: reason,
      protocolVersion: ELEMENT_INSPECTION_PROTOCOL_VERSION,
      sessionGeneration: 0,
      documentToken: '',
      revision: 0,
      mode: 'selecting'
    };
  }

  private normalizeString(value: string | undefined, fallback: string = ''): string {
    const normalized = String(value ?? '').trim();
    return normalized.length > 0 ? normalized : fallback;
  }

  private normalizeRawString(value: string | undefined): string {
    return String(value ?? '');
  }

  private normalizeCount(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  private normalizeNumber(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
  }

  private encodeScriptString(value: string): string {
    return JSON.stringify(String(value ?? ''));
  }
}
