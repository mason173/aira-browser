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

export interface ElementInspectionOutlineNode {
  path: string;
  depth: number;
  tagName: string;
  elementId: string;
  classTokens: string[];
  textPreview: string;
  childCount: number;
  selected: boolean;
}

export interface ElementInspectionBoxModel {
  marginTop: number;
  marginRight: number;
  marginBottom: number;
  marginLeft: number;
  borderTop: number;
  borderRight: number;
  borderBottom: number;
  borderLeft: number;
  paddingTop: number;
  paddingRight: number;
  paddingBottom: number;
  paddingLeft: number;
  contentWidth: number;
  contentHeight: number;
}

export interface ElementInspectionComputedProperty {
  name: string;
  value: string;
}

export interface ElementInspectionConsoleEntry {
  level: string;
  text: string;
  time: number;
}

export interface ElementInspectionNetworkEntry {
  method: string;
  url: string;
  status: number;
  type: string;
  size: number;
  durationMs: number;
  startedAt: number;
}

export interface ElementInspectionSourceEntry {
  id: string;
  kind: string;
  name: string;
  url: string;
}

export interface ElementInspectionListenerEntry {
  type: string;
  capture: boolean;
  source: string;
}

export interface ElementInspectionPageInfo {
  url: string;
  title: string;
  userAgent: string;
  viewportWidth: number;
  viewportHeight: number;
  devicePixelRatio: number;
}

export interface ElementInspectionSourcePreview {
  id: string;
  name: string;
  text: string;
  reason: string;
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
  outline?: ElementInspectionOutlineNode[];
  box?: ElementInspectionBoxModel;
  computed?: ElementInspectionComputedProperty[];
  logs?: ElementInspectionConsoleEntry[];
  network?: ElementInspectionNetworkEntry[];
  sources?: ElementInspectionSourceEntry[];
  listeners?: ElementInspectionListenerEntry[];
  pageInfo?: ElementInspectionPageInfo;
}

export interface ElementInspectionSourceReadResult {
  ok: boolean;
  reason: string;
  protocolVersion: number;
  sessionGeneration: number;
  documentToken: string;
  id: string;
  name: string;
  text: string;
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

const ELEMENT_INSPECTION_PROTOCOL_VERSION: number = 4;
const ELEMENT_INSPECTION_OUTLINE_PATH_PATTERN: RegExp = /^(?:[0-9]+(?:\/[0-9]+)*)?$/;
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
      var text = collapseSpace(current.nodeValue).trim();
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
  function createHighlightLayer(background) {
    var layer = document.createElement('div');
    layer.setAttribute(uiAttribute, 'true');
    layer.style.cssText = [
      'position:absolute!important',
      'left:0!important',
      'top:0!important',
      'width:0!important',
      'height:0!important',
      'pointer-events:none!important',
      'box-sizing:border-box!important',
      'background:' + background + '!important'
    ].join(';');
    return layer;
  }
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
    'box-sizing:border-box!important',
    'background:rgba(246,178,107,0.55)!important',
    'visibility:visible!important',
    'display:none!important'
  ].join(';');
  var highlightBorder = createHighlightLayer('rgba(255,229,153,0.75)');
  var highlightPadding = createHighlightLayer('rgba(147,196,125,0.55)');
  var highlightContent = createHighlightLayer(highlightFillColor);
  highlightContent.style.setProperty('outline', '1px solid ' + highlightColor, 'important');
  var highlightLabel = document.createElement('div');
  highlightLabel.setAttribute(uiAttribute, 'true');
  highlightLabel.style.cssText = [
    'position:absolute!important',
    'left:0!important',
    'top:-18px!important',
    'height:16px!important',
    'max-width:280px!important',
    'padding:0 4px!important',
    'background:#1a73e8!important',
    'color:#ffffff!important',
    'font:11px/16px sans-serif!important',
    'white-space:nowrap!important',
    'overflow:hidden!important',
    'pointer-events:none!important'
  ].join(';');
  highlight.appendChild(highlightBorder);
  highlight.appendChild(highlightPadding);
  highlight.appendChild(highlightContent);
  highlight.appendChild(highlightLabel);
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
    templateContentRoots: [],
    logs: [],
    network: [],
    listenerMap: [],
    debugHooks: null,
    previewNode: null,
    pickerArmed: true,
    lastHoverSelectAt: 0,
    savedCursor: ''
  };
  function formatConsoleValue(value) {
    if (value === null) {
      return 'null';
    }
    if (value === undefined) {
      return 'undefined';
    }
    var valueType = typeof value;
    if (valueType === 'string' || valueType === 'number' || valueType === 'boolean') {
      return String(value);
    }
    if (value instanceof Error) {
      return safeString((value.name || 'Error') + ': ' + (value.message || ''), 240);
    }
    try {
      var json = JSON.stringify(value);
      if (typeof json === 'string') {
        return json;
      }
    } catch (error) {}
    return String(value);
  }
  function pushLog(level, args) {
    var parts = [];
    var values = args || [];
    for (var index = 0; index < values.length; index++) {
      parts.push(formatConsoleValue(values[index]));
    }
    runtime.logs.push({
      level: level,
      text: safeString(parts.join(' '), 240),
      time: Date.now()
    });
    if (runtime.logs.length > 80) {
      runtime.logs.shift();
    }
  }
  function pushNetwork(entry) {
    runtime.network.push({
      method: safeString(entry.method || 'GET', 12),
      url: safeString(entry.url || '', 180),
      status: Number(entry.status) || 0,
      type: safeString(entry.type || '', 48),
      size: Number(entry.size) || 0,
      durationMs: Number(entry.durationMs) || 0,
      startedAt: Number(entry.startedAt) || Date.now()
    });
    if (runtime.network.length > 40) {
      runtime.network.shift();
    }
  }
  function contentTypeOf(headerValue) {
    var value = String(headerValue || '');
    var splitAt = value.indexOf(';');
    if (splitAt >= 0) {
      value = value.substring(0, splitAt);
    }
    return value;
  }
  function recordListener(node, type, options) {
    if (!node || node.nodeType !== 1) {
      return;
    }
    var capture = options === true || (options && options.capture === true);
    runtime.listenerMap.push({
      node: node,
      type: safeString(type, 32),
      capture: capture
    });
    if (runtime.listenerMap.length > 200) {
      runtime.listenerMap.shift();
    }
  }
  function installDebugHooks() {
    if (runtime.debugHooks || !window.console) {
      return;
    }
    var hooks = {
      console: {},
      fetch: window.fetch,
      open: window.XMLHttpRequest && XMLHttpRequest.prototype ? XMLHttpRequest.prototype.open : null,
      send: window.XMLHttpRequest && XMLHttpRequest.prototype ? XMLHttpRequest.prototype.send : null,
      addEventListener: Element.prototype.addEventListener
    };
    var levels = ['log', 'info', 'warn', 'error', 'debug'];
    for (var levelIndex = 0; levelIndex < levels.length; levelIndex++) {
      (function(level) {
        var original = console[level];
        hooks.console[level] = original;
        console[level] = function() {
          try {
            pushLog(level, arguments);
          } catch (error) {}
          if (typeof original === 'function') {
            return original.apply(console, arguments);
          }
        };
      })(levels[levelIndex]);
    }
    hooks.onError = function(event) {
      pushLog('error', [event && event.message ? event.message : 'error']);
    };
    hooks.onRejection = function(event) {
      pushLog('error', ['Unhandled rejection', event ? event.reason : '']);
    };
    window.addEventListener('error', hooks.onError);
    window.addEventListener('unhandledrejection', hooks.onRejection);
    if (typeof hooks.fetch === 'function') {
      window.fetch = function(input, init) {
        var startedAt = Date.now();
        var method = 'GET';
        var url = '';
        try {
          if (typeof input === 'string') {
            url = input;
          } else if (input && input.url) {
            url = String(input.url);
            if (input.method) {
              method = String(input.method);
            }
          }
          if (init && init.method) {
            method = String(init.method);
          }
        } catch (error) {}
        var pending = hooks.fetch.apply(this, arguments);
        if (!pending || typeof pending.then !== 'function') {
          return pending;
        }
        return pending.then(function(response) {
          var type = '';
          var size = 0;
          try {
            type = contentTypeOf(response.headers && response.headers.get ? response.headers.get('content-type') : '');
            size = Number(response.headers && response.headers.get ? response.headers.get('content-length') : 0) || 0;
          } catch (error) {}
          pushNetwork({
            method: method,
            url: url,
            status: response.status || 0,
            type: type,
            size: size,
            durationMs: Date.now() - startedAt,
            startedAt: startedAt
          });
          return response;
        }, function(error) {
          pushNetwork({
            method: method,
            url: url,
            status: 0,
            type: '',
            size: 0,
            durationMs: Date.now() - startedAt,
            startedAt: startedAt
          });
          throw error;
        });
      };
    }
    if (hooks.open && hooks.send) {
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__airaInspectionRequest = {
          method: String(method || 'GET'),
          url: String(url || ''),
          startedAt: 0
        };
        return hooks.open.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        var xhr = this;
        var request = xhr.__airaInspectionRequest || { method: 'GET', url: '', startedAt: 0 };
        request.startedAt = Date.now();
        var onDone = function() {
          var type = '';
          var size = 0;
          try {
            type = contentTypeOf(xhr.getResponseHeader('content-type'));
            size = Number(xhr.getResponseHeader('content-length')) || 0;
          } catch (error) {}
          pushNetwork({
            method: request.method,
            url: request.url,
            status: xhr.status || 0,
            type: type,
            size: size,
            durationMs: Date.now() - request.startedAt,
            startedAt: request.startedAt
          });
          xhr.removeEventListener('loadend', onDone);
        };
        xhr.addEventListener('loadend', onDone);
        return hooks.send.apply(xhr, arguments);
      };
    }
    Element.prototype.addEventListener = function(type, listener, options) {
      try {
        recordListener(this, type, options);
      } catch (error) {}
      if (typeof hooks.addEventListener === 'function') {
        return hooks.addEventListener.apply(this, arguments);
      }
    };
    runtime.debugHooks = hooks;
  }
  function buildListeners(node) {
    var result = [];
    if (!node || !node.attributes) {
      return result;
    }
    for (var index = 0; index < node.attributes.length && result.length < 24; index++) {
      var name = String(node.attributes[index].name || '');
      if (name.indexOf('on') === 0 && name.length > 2) {
        result.push({ type: name.substring(2), capture: false, source: 'attribute' });
      }
    }
    for (var listenerIndex = 0; listenerIndex < runtime.listenerMap.length && result.length < 24; listenerIndex++) {
      var recorded = runtime.listenerMap[listenerIndex];
      if (recorded.node === node) {
        result.push({ type: recorded.type, capture: recorded.capture === true, source: 'listener' });
      }
    }
    return result;
  }
  function buildSources() {
    var result = [{
      id: 'document',
      kind: 'document',
      name: safeString(document.title || location.href, 80),
      url: safeString(location.href, 180)
    }];
    var scripts = document.scripts || [];
    for (var scriptIndex = 0; scriptIndex < scripts.length && result.length < 40; scriptIndex++) {
      var script = scripts[scriptIndex];
      result.push({
        id: 'script:' + scriptIndex,
        kind: 'script',
        name: safeString(script.src || ('inline-' + scriptIndex), 80),
        url: safeString(script.src || '', 180)
      });
    }
    var links = document.querySelectorAll('link[rel]');
    for (var linkIndex = 0; linkIndex < links.length && result.length < 40; linkIndex++) {
      var rel = String(links[linkIndex].rel || '').toLowerCase();
      if (rel.indexOf('stylesheet') < 0) {
        continue;
      }
      result.push({
        id: 'style:' + linkIndex,
        kind: 'style',
        name: safeString(links[linkIndex].href || ('style-' + linkIndex), 80),
        url: safeString(links[linkIndex].href || '', 180)
      });
    }
    var styleNodes = document.querySelectorAll('style');
    for (var inlineIndex = 0; inlineIndex < styleNodes.length && result.length < 40; inlineIndex++) {
      result.push({
        id: 'inline:' + inlineIndex,
        kind: 'style',
        name: 'style-' + inlineIndex,
        url: ''
      });
    }
    return result;
  }
  function buildPageInfo() {
    return {
      url: safeString(location.href, 180),
      title: safeString(document.title, 80),
      userAgent: safeString(navigator.userAgent, 180),
      viewportWidth: Math.round(window.innerWidth || 0),
      viewportHeight: Math.round(window.innerHeight || 0),
      devicePixelRatio: Number(window.devicePixelRatio) || 1
    };
  }
  function readStylesheetText(href) {
    var sheets = document.styleSheets || [];
    for (var index = 0; index < sheets.length; index++) {
      var sheet = sheets[index];
      if (!sheet || String(sheet.href || '') !== String(href || '')) {
        continue;
      }
      try {
        var rules = sheet.cssRules || [];
        var text = '';
        for (var ruleIndex = 0; ruleIndex < rules.length && text.length < 8000; ruleIndex++) {
          text += rules[ruleIndex].cssText + '\\n';
        }
        return text;
      } catch (error) {
        return '';
      }
    }
    return '';
  }
  function restoreDebugHooks() {
    var hooks = runtime.debugHooks;
    if (!hooks) {
      return;
    }
    var levels = ['log', 'info', 'warn', 'error', 'debug'];
    for (var levelIndex = 0; levelIndex < levels.length; levelIndex++) {
      var level = levels[levelIndex];
      if (hooks.console && Object.prototype.hasOwnProperty.call(hooks.console, level)) {
        console[level] = hooks.console[level];
      }
    }
    if (hooks.onError) {
      window.removeEventListener('error', hooks.onError);
    }
    if (hooks.onRejection) {
      window.removeEventListener('unhandledrejection', hooks.onRejection);
    }
    if (hooks.fetch) {
      window.fetch = hooks.fetch;
    }
    if (hooks.open && window.XMLHttpRequest) {
      XMLHttpRequest.prototype.open = hooks.open;
    }
    if (hooks.send && window.XMLHttpRequest) {
      XMLHttpRequest.prototype.send = hooks.send;
    }
    if (hooks.addEventListener) {
      Element.prototype.addEventListener = hooks.addEventListener;
    }
    runtime.debugHooks = null;
  }
  installDebugHooks();
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
  function readHighlightPx(style, name) {
    var value = parseFloat(style.getPropertyValue(name));
    if (!isFinite(value) || value < 0) {
      return 0;
    }
    return value;
  }
  function placeHighlightLayer(layer, x, y, width, height) {
    layer.style.setProperty('left', x + 'px', 'important');
    layer.style.setProperty('top', y + 'px', 'important');
    layer.style.setProperty('width', Math.max(0, width) + 'px', 'important');
    layer.style.setProperty('height', Math.max(0, height) + 'px', 'important');
  }
  function updateHighlight() {
    var node = runtime.previewNode && runtime.previewNode.isConnected ? runtime.previewNode : null;
    if (!node && runtime.mode === 'inspected' && runtime.currentNode && runtime.currentNode.isConnected) {
      node = runtime.currentNode;
    }
    if (!node) {
      highlight.style.setProperty('display', 'none', 'important');
      return;
    }
    var style = window.getComputedStyle(node);
    var rect = node.getBoundingClientRect();
    var marginLeft = readHighlightPx(style, 'margin-left');
    var marginRight = readHighlightPx(style, 'margin-right');
    var marginTop = readHighlightPx(style, 'margin-top');
    var marginBottom = readHighlightPx(style, 'margin-bottom');
    var borderLeft = readHighlightPx(style, 'border-left-width');
    var borderRight = readHighlightPx(style, 'border-right-width');
    var borderTop = readHighlightPx(style, 'border-top-width');
    var borderBottom = readHighlightPx(style, 'border-bottom-width');
    var paddingLeft = readHighlightPx(style, 'padding-left');
    var paddingRight = readHighlightPx(style, 'padding-right');
    var paddingTop = readHighlightPx(style, 'padding-top');
    var paddingBottom = readHighlightPx(style, 'padding-bottom');
    var outerLeft = rect.left - marginLeft;
    var outerTop = rect.top - marginTop;
    var outerWidth = rect.width + marginLeft + marginRight;
    var outerHeight = rect.height + marginTop + marginBottom;
    highlight.style.setProperty('display', 'block', 'important');
    highlight.style.setProperty('left', outerLeft + 'px', 'important');
    highlight.style.setProperty('top', outerTop + 'px', 'important');
    highlight.style.setProperty('width', Math.max(0, outerWidth) + 'px', 'important');
    highlight.style.setProperty('height', Math.max(0, outerHeight) + 'px', 'important');
    placeHighlightLayer(highlightBorder, marginLeft, marginTop, rect.width, rect.height);
    placeHighlightLayer(
      highlightPadding,
      marginLeft + borderLeft,
      marginTop + borderTop,
      rect.width - borderLeft - borderRight,
      rect.height - borderTop - borderBottom
    );
    placeHighlightLayer(
      highlightContent,
      marginLeft + borderLeft + paddingLeft,
      marginTop + borderTop + paddingTop,
      rect.width - borderLeft - borderRight - paddingLeft - paddingRight,
      rect.height - borderTop - borderBottom - paddingTop - paddingBottom
    );
    var tag = String(node.tagName || '').toLowerCase();
    var idText = node.id ? '#' + String(node.id) : '';
    highlightLabel.textContent = tag + idText + '  ' + Math.round(rect.width) + ' \u00d7 ' + Math.round(rect.height);
    highlightLabel.style.setProperty('top', outerTop < 20 ? '0px' : '-18px', 'important');
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
  function pathOf(node) {
    if (!node || node === document.documentElement) {
      return '';
    }
    var parts = [];
    var current = node;
    var guard = 0;
    while (current && current !== document.documentElement && current.parentElement && guard < 64) {
      var siblings = current.parentElement.children || [];
      var index = 0;
      for (var siblingIndex = 0; siblingIndex < siblings.length; siblingIndex++) {
        if (siblings[siblingIndex] === current) {
          index = siblingIndex;
          break;
        }
      }
      parts.push(index);
      current = current.parentElement;
      guard += 1;
    }
    parts.reverse();
    return parts.join('/');
  }
  function collapseSpace(value) {
    var text = String(value || '');
    var result = '';
    var pendingSpace = false;
    for (var index = 0; index < text.length; index++) {
      var code = text.charCodeAt(index);
      var isSpace = code === 9 || code === 10 || code === 12 || code === 13 || code === 32;
      if (isSpace) {
        pendingSpace = result.length > 0;
        continue;
      }
      if (pendingSpace) {
        result += ' ';
        pendingSpace = false;
      }
      result += text.charAt(index);
    }
    return result;
  }
  function isSafeOutlinePath(value) {
    if (value.length === 0) {
      return true;
    }
    var parts = value.split('/');
    for (var index = 0; index < parts.length; index++) {
      var part = parts[index];
      if (part.length === 0) {
        return false;
      }
      for (var digitIndex = 0; digitIndex < part.length; digitIndex++) {
        var code = part.charCodeAt(digitIndex);
        if (code < 48 || code > 57) {
          return false;
        }
      }
    }
    return true;
  }
  function resolveOutlinePath(path) {
    var value = String(path || '');
    if (!isSafeOutlinePath(value)) {
      return null;
    }
    var node = document.documentElement;
    if (!node) {
      return null;
    }
    if (value.length === 0) {
      return node;
    }
    var parts = value.split('/');
    for (var index = 0; index < parts.length; index++) {
      var childIndex = Number(parts[index]);
      var children = node.children || [];
      if (!children[childIndex]) {
        return null;
      }
      node = children[childIndex];
    }
    return node;
  }
  function elementDepth(node) {
    var depth = 0;
    var current = node;
    while (current && current !== document.documentElement && current.parentElement && depth < 64) {
      depth += 1;
      current = current.parentElement;
    }
    return depth;
  }
  function isOutlineTarget(node) {
    var element = normalizeElement(node);
    return !!(element && element.nodeType === 1 && !isAiraUi(element));
  }
  function pushOutline(nodes, seen, node, selected) {
    if (!node || node.nodeType !== 1 || nodes.length >= 80 || isAiraUi(node)) {
      return;
    }
    var path = pathOf(node);
    if (seen[path]) {
      return;
    }
    seen[path] = true;
    var classTokens = [];
    if (node.classList) {
      var classLimit = Math.min(node.classList.length, 3);
      for (var classIndex = 0; classIndex < classLimit; classIndex++) {
        classTokens.push(safeString(node.classList[classIndex], 48));
      }
    }
    var textPreview = '';
    if (!node.children || node.children.length === 0) {
      textPreview = safeString(collapseSpace(node.textContent).trim(), 32);
    }
    nodes.push({
      path: path,
      depth: elementDepth(node),
      tagName: String(node.tagName || '').toLowerCase(),
      elementId: safeString(node.id, 64),
      classTokens: classTokens,
      textPreview: textPreview,
      childCount: node.children ? node.children.length : 0,
      selected: selected === true
    });
  }
  function buildOutline(selected) {
    var nodes = [];
    var seen = {};
    var root = document.documentElement;
    if (!root) {
      return nodes;
    }
    if (!selected || !selected.isConnected) {
      pushOutline(nodes, seen, root, false);
      if (document.head) {
        pushOutline(nodes, seen, document.head, false);
      }
      if (document.body) {
        pushOutline(nodes, seen, document.body, false);
        var bodyChildren = document.body.children || [];
        var bodyCap = Math.min(bodyChildren.length, 24);
        for (var bodyIndex = 0; bodyIndex < bodyCap; bodyIndex++) {
          pushOutline(nodes, seen, bodyChildren[bodyIndex], false);
          var grandchildren = bodyChildren[bodyIndex].children || [];
          var grandchildCap = Math.min(grandchildren.length, 6);
          for (var grandchildIndex = 0; grandchildIndex < grandchildCap; grandchildIndex++) {
            pushOutline(nodes, seen, grandchildren[grandchildIndex], false);
          }
        }
      }
      return nodes;
    }
    var chain = [];
    var current = selected;
    while (current && current.nodeType === 1) {
      chain.push(current);
      if (current === root) {
        break;
      }
      current = current.parentElement;
    }
    chain.reverse();
    pushOutline(nodes, seen, root, selected === root);
    for (var chainIndex = 0; chainIndex < chain.length; chainIndex++) {
      var ancestor = chain[chainIndex];
      if (!ancestor || ancestor === root || !ancestor.parentElement) {
        continue;
      }
      var siblings = ancestor.parentElement.children || [];
      var ancestorIndex = 0;
      for (var siblingIndex = 0; siblingIndex < siblings.length; siblingIndex++) {
        if (siblings[siblingIndex] === ancestor) {
          ancestorIndex = siblingIndex;
          break;
        }
      }
      var start = Math.max(0, ancestorIndex - 4);
      var end = Math.min(siblings.length, ancestorIndex + 5);
      for (var windowIndex = start; windowIndex < end; windowIndex++) {
        pushOutline(nodes, seen, siblings[windowIndex], siblings[windowIndex] === selected);
      }
    }
    var selectedChildren = selected.children || [];
    var childCap = Math.min(selectedChildren.length, 16);
    for (var childIndex = 0; childIndex < childCap; childIndex++) {
      pushOutline(nodes, seen, selectedChildren[childIndex], false);
    }
    return nodes;
  }
  function readPx(style, name) {
    var value = parseFloat(style.getPropertyValue(name));
    if (!isFinite(value)) {
      return 0;
    }
    return Math.round(value * 10) / 10;
  }
  function buildBoxModel(node) {
    var style = window.getComputedStyle(node);
    var rect = node.getBoundingClientRect();
    var borderLeft = readPx(style, 'border-left-width');
    var borderRight = readPx(style, 'border-right-width');
    var borderTop = readPx(style, 'border-top-width');
    var borderBottom = readPx(style, 'border-bottom-width');
    var paddingLeft = readPx(style, 'padding-left');
    var paddingRight = readPx(style, 'padding-right');
    var paddingTop = readPx(style, 'padding-top');
    var paddingBottom = readPx(style, 'padding-bottom');
    return {
      marginTop: readPx(style, 'margin-top'),
      marginRight: readPx(style, 'margin-right'),
      marginBottom: readPx(style, 'margin-bottom'),
      marginLeft: readPx(style, 'margin-left'),
      borderTop: borderTop,
      borderRight: borderRight,
      borderBottom: borderBottom,
      borderLeft: borderLeft,
      paddingTop: paddingTop,
      paddingRight: paddingRight,
      paddingBottom: paddingBottom,
      paddingLeft: paddingLeft,
      contentWidth: Math.max(0, Math.round((rect.width - borderLeft - borderRight - paddingLeft - paddingRight) * 10) / 10),
      contentHeight: Math.max(0, Math.round((rect.height - borderTop - borderBottom - paddingTop - paddingBottom) * 10) / 10)
    };
  }
  function buildComputedProperties(node) {
    var style = window.getComputedStyle(node);
    var names = ['display', 'position', 'color', 'background-color', 'font-size', 'font-weight',
      'line-height', 'width', 'height', 'overflow', 'z-index', 'opacity', 'box-sizing', 'flex'];
    var result = [];
    for (var index = 0; index < names.length; index++) {
      var value = '';
      try {
        value = safeString(style.getPropertyValue(names[index]), 80);
      } catch (error) {
        value = '';
      }
      if (value.length > 0) {
        result.push({ name: names[index], value: value });
      }
    }
    return result;
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
    }
    result.logs = runtime.logs || [];
    result.network = runtime.network || [];
    result.sources = buildSources();
    result.pageInfo = buildPageInfo();
    result.listeners = runtime.mode === 'inspected' && runtime.currentNode ?
      buildListeners(runtime.currentNode) : [];
    if (nodeChanged) {
      result.outline = buildOutline(runtime.currentNode);
      if (runtime.mode === 'inspected' && runtime.currentNode) {
        result.node = buildNodeSnapshot(runtime.currentNode);
        result.box = buildBoxModel(runtime.currentNode);
        result.computed = buildComputedProperties(runtime.currentNode);
      }
    }
    return result;
  };
  runtime.evaluate = function(expression) {
    var source = String(expression || '');
    pushLog('log', ['> ' + source]);
    try {
      var result = (0, eval)(source);
      pushLog('log', [result]);
    } catch (error) {
      pushLog('error', [error]);
    }
    return runtime.snapshot();
  };
  runtime.clearLogs = function() {
    runtime.logs = [];
    return runtime.snapshot();
  };
  runtime.readSource = function(id) {
    var sourceId = String(id || '');
    var name = sourceId;
    var text = '';
    var reason = 'source_unavailable';
    var ok = false;
    if (sourceId === 'document' && document.documentElement) {
      name = document.title || location.href;
      text = safeString(document.documentElement.outerHTML, 8000);
      ok = true;
      reason = '';
    } else if (sourceId.indexOf('script:') === 0) {
      var scriptIndex = Number(sourceId.substring(7));
      var script = document.scripts && document.scripts[scriptIndex];
      if (script) {
        name = script.src || ('inline-' + scriptIndex);
        text = safeString(script.textContent || '', 8000);
        if (text.length > 0) {
          ok = true;
          reason = '';
        } else if (script.src) {
          text = safeString(script.src, 180);
          reason = 'external_script';
        }
      }
    } else if (sourceId.indexOf('inline:') === 0) {
      var inlineIndex = Number(sourceId.substring(7));
      var styleNodes = document.querySelectorAll('style');
      var styleNode = styleNodes[inlineIndex];
      if (styleNode) {
        name = 'style-' + inlineIndex;
        text = safeString(styleNode.textContent || '', 8000);
        if (text.length > 0) {
          ok = true;
          reason = '';
        }
      }
    } else if (sourceId.indexOf('style:') === 0) {
      var links = document.querySelectorAll('link[rel]');
      var styleIndex = Number(sourceId.substring(6));
      var link = links[styleIndex];
      if (link) {
        name = link.href || ('style-' + styleIndex);
        text = safeString(readStylesheetText(link.href), 8000);
        if (text.length > 0) {
          ok = true;
          reason = '';
        } else if (link.href) {
          text = safeString(link.href, 180);
          reason = 'external_style';
        }
      }
    }
    return {
      ok: ok,
      reason: reason,
      protocolVersion: runtime.protocolVersion,
      sessionGeneration: runtime.sessionGeneration,
      documentToken: runtime.documentToken,
      id: sourceId,
      name: safeString(name, 80),
      text: text
    };
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
    runtime.previewNode = null;
    selectAtNormalizedPoint(normalizedX, normalizedY);
    updateHighlight();
    return runtime.snapshot();
  };
  runtime.previewAtNormalizedPoint = function(normalizedX, normalizedY) {
    var node = resolveNodeAtNormalizedPoint(normalizedX, normalizedY);
    if (!isDirectlySelectable(node)) {
      if (runtime.previewNode) {
        runtime.previewNode = null;
        updateHighlight();
      }
      return { ok: true, changed: false };
    }
    var changed = node !== runtime.previewNode;
    runtime.previewNode = node;
    updateHighlight();
    return { ok: true, changed: changed };
  };
  runtime.hoverSelectAtNormalizedPoint = function(normalizedX, normalizedY) {
    var node = resolveNodeAtNormalizedPoint(normalizedX, normalizedY);
    if (!isDirectlySelectable(node)) {
      runtime.previewNode = null;
      updateHighlight();
      return runtime.snapshot();
    }
    if (node !== runtime.currentNode) {
      setCurrentNode(node);
    }
    runtime.previewNode = node;
    updateHighlight();
    var snap = runtime.snapshot();
    if (snap && snap.node && snap.node.htmlPreview && snap.node.htmlLength > snap.node.htmlPreview.length) {
      snap.node.htmlLength = snap.node.htmlPreview.length;
    }
    return snap;
  };
  runtime.clearPreview = function() {
    runtime.previewNode = null;
    updateHighlight();
    return { ok: true };
  };
  function inspectPointerActive() {
    return runtime.active && runtime.pickerArmed === true;
  }
  function nodeAtClientPoint(clientX, clientY) {
    try {
      return document.elementFromPoint(clientX, clientY);
    } catch (error) {
      return null;
    }
  }
  function previewFromClientPoint(clientX, clientY) {
    var node = nodeAtClientPoint(clientX, clientY);
    if (!isDirectlySelectable(node)) {
      if (runtime.previewNode) {
        runtime.previewNode = null;
        updateHighlight();
      }
      return { ok: true, changed: false };
    }
    var changed = node !== runtime.previewNode;
    runtime.previewNode = node;
    updateHighlight();
    return { ok: true, changed: changed };
  }
  function hoverSelectFromClientPoint(clientX, clientY) {
    var node = nodeAtClientPoint(clientX, clientY);
    if (!isDirectlySelectable(node)) {
      runtime.previewNode = null;
      updateHighlight();
      return;
    }
    if (node !== runtime.currentNode) {
      setCurrentNode(node);
    }
    runtime.previewNode = node;
    updateHighlight();
  }
  function onInspectMouseMove(event) {
    if (!inspectPointerActive() || !event) {
      return;
    }
    var result = previewFromClientPoint(event.clientX, event.clientY);
    if (!result || !result.changed) {
      return;
    }
    var now = Date.now();
    if (now - runtime.lastHoverSelectAt < 70) {
      return;
    }
    runtime.lastHoverSelectAt = now;
    hoverSelectFromClientPoint(event.clientX, event.clientY);
  }
  function blockInspectPointer(event) {
    if (!inspectPointerActive() || !event) {
      return;
    }
    if (event.cancelable && event.preventDefault) {
      event.preventDefault();
    }
    if (event.stopPropagation) {
      event.stopPropagation();
    }
  }
  function onInspectClick(event) {
    blockInspectPointer(event);
    if (!inspectPointerActive() || !event) {
      return;
    }
    hoverSelectFromClientPoint(event.clientX, event.clientY);
    runtime.previewNode = runtime.currentNode;
    updateHighlight();
  }
  runtime.onInspectMouseMove = onInspectMouseMove;
  runtime.onInspectMouseDown = blockInspectPointer;
  runtime.onInspectClick = onInspectClick;
  document.addEventListener('mousemove', onInspectMouseMove, true);
  document.addEventListener('mousedown', blockInspectPointer, true);
  document.addEventListener('mouseup', blockInspectPointer, true);
  document.addEventListener('click', onInspectClick, true);
  document.addEventListener('auxclick', blockInspectPointer, true);
  document.addEventListener('contextmenu', blockInspectPointer, true);
  runtime.savedCursor = document.documentElement.style.cursor || '';
  document.documentElement.style.cursor = 'crosshair';
  runtime.setPickerArmed = function(armed) {
    runtime.pickerArmed = armed === true;
    if (runtime.pickerArmed) {
      document.documentElement.style.cursor = 'crosshair';
    } else {
      document.documentElement.style.cursor = runtime.savedCursor || '';
      runtime.previewNode = null;
      updateHighlight();
    }
    return { ok: true, pickerArmed: runtime.pickerArmed };
  };
  runtime.selectByPath = function(path) {
    var node = resolveOutlinePath(path);
    if (!isOutlineTarget(node)) {
      return runtime.snapshot();
    }
    setCurrentNode(node);
    updateHighlight();
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
    runtime.pickerArmed = false;
    document.documentElement.style.cursor = runtime.savedCursor || '';
    document.removeEventListener('mousemove', runtime.onInspectMouseMove, true);
    document.removeEventListener('mousedown', runtime.onInspectMouseDown, true);
    document.removeEventListener('mouseup', runtime.onInspectMouseDown, true);
    document.removeEventListener('click', runtime.onInspectClick, true);
    document.removeEventListener('auxclick', runtime.onInspectMouseDown, true);
    document.removeEventListener('contextmenu', runtime.onInspectMouseDown, true);
    restoreDebugHooks();
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

  isOutlinePath(path: string): boolean {
    return ELEMENT_INSPECTION_OUTLINE_PATH_PATTERN.test(path);
  }

  isSourceId(sourceId: string): boolean {
    if (sourceId === 'document') {
      return true;
    }
    const separator = sourceId.indexOf(':');
    if (separator <= 0 || separator !== sourceId.lastIndexOf(':')) {
      return false;
    }
    const kind = sourceId.substring(0, separator);
    const suffix = sourceId.substring(separator + 1);
    if (kind !== 'script' && kind !== 'style' && kind !== 'inline') {
      return false;
    }
    if (suffix.length === 0 || suffix.length > 4) {
      return false;
    }
    for (let index = 0; index < suffix.length; index += 1) {
      const code = suffix.charCodeAt(index);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  buildEvaluateScript(sessionGeneration: number, documentToken: string, expression: string): string {
    const normalized = expression.length > 2000 ? expression.substring(0, 2000) : expression;
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.evaluate(${this.encodeScriptString(normalized)})`
    );
  }

  buildClearLogsScript(sessionGeneration: number, documentToken: string): string {
    return this.buildRuntimeCommandScript(sessionGeneration, documentToken, 'runtime.clearLogs()');
  }

  buildReadSourceScript(sessionGeneration: number, documentToken: string, sourceId: string): string {
    if (!this.isSourceId(sourceId)) {
      return this.buildRuntimeCommandScript(sessionGeneration, documentToken, 'runtime.snapshot()');
    }
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.readSource(${this.encodeScriptString(sourceId)})`
    );
  }

  buildSelectOutlineScript(sessionGeneration: number, documentToken: string, path: string): string {
    if (!this.isOutlinePath(path)) {
      return this.buildRuntimeCommandScript(sessionGeneration, documentToken, 'runtime.snapshot()');
    }
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.selectByPath(${this.encodeScriptString(path)})`
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

  buildPreviewAtNormalizedPointScript(
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
      `runtime.previewAtNormalizedPoint(${clampedX}, ${clampedY})`
    );
  }

  buildHoverSelectAtNormalizedPointScript(
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
      `runtime.hoverSelectAtNormalizedPoint(${clampedX}, ${clampedY})`
    );
  }

  buildClearPreviewScript(sessionGeneration: number, documentToken: string): string {
    return this.buildRuntimeCommandScript(sessionGeneration, documentToken, 'runtime.clearPreview()');
  }

  buildSetPickerArmedScript(sessionGeneration: number, documentToken: string, armed: boolean): string {
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.setPickerArmed(${armed ? 'true' : 'false'})`
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
      if (Array.isArray(parsed.outline)) {
        result.outline = this.normalizeOutline(parsed.outline);
      }
      if (parsed.box !== undefined) {
        result.box = this.normalizeBox(parsed.box);
      }
      if (Array.isArray(parsed.computed)) {
        result.computed = this.normalizeComputed(parsed.computed);
      }
      if (Array.isArray(parsed.logs)) {
        result.logs = this.normalizeLogs(parsed.logs);
      }
      if (Array.isArray(parsed.network)) {
        result.network = this.normalizeNetwork(parsed.network);
      }
      if (Array.isArray(parsed.sources)) {
        result.sources = this.normalizeSources(parsed.sources);
      }
      if (Array.isArray(parsed.listeners)) {
        result.listeners = this.normalizeListeners(parsed.listeners);
      }
      if (parsed.pageInfo !== undefined) {
        result.pageInfo = this.normalizePageInfo(parsed.pageInfo);
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

  parseSourceReadResult(rawValue: string): ElementInspectionSourceReadResult {
    const normalized = this.unwrapJsonString(rawValue);
    try {
      const parsed: ElementInspectionSourceReadResult = JSON.parse(normalized) as ElementInspectionSourceReadResult;
      return {
        ok: parsed.ok === true && parsed.protocolVersion === ELEMENT_INSPECTION_PROTOCOL_VERSION &&
          this.isSourceId(this.normalizeString(parsed.id)),
        reason: this.normalizeString(parsed.reason),
        protocolVersion: this.normalizeCount(parsed.protocolVersion),
        sessionGeneration: this.normalizeCount(parsed.sessionGeneration),
        documentToken: this.normalizeString(parsed.documentToken),
        id: this.normalizeString(parsed.id),
        name: this.normalizeString(parsed.name).substring(0, 80),
        text: this.normalizeRawString(parsed.text).substring(0, 8000)
      };
    } catch (_error) {
      return {
        ok: false,
        reason: 'invalid_source_result',
        protocolVersion: ELEMENT_INSPECTION_PROTOCOL_VERSION,
        sessionGeneration: 0,
        documentToken: '',
        id: '',
        name: '',
        text: ''
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

  private normalizeOutline(nodes: ElementInspectionOutlineNode[]): ElementInspectionOutlineNode[] {
    const result: ElementInspectionOutlineNode[] = [];
    const seen: string[] = [];
    nodes.forEach((node: ElementInspectionOutlineNode): void => {
      if (result.length >= 80) {
        return;
      }
      const path = this.normalizeString(node.path);
      if (!this.isOutlinePath(path) || seen.indexOf(path) >= 0) {
        return;
      }
      seen.push(path);
      const classTokens: string[] = [];
      if (Array.isArray(node.classTokens)) {
        node.classTokens.forEach((value: string): void => {
          const normalized = this.normalizeString(value);
          if (normalized.length > 0 && classTokens.length < 3) {
            classTokens.push(normalized);
          }
        });
      }
      const normalizedNode: ElementInspectionOutlineNode = {
        path: path,
        depth: Math.min(64, this.normalizeCount(node.depth)),
        tagName: this.normalizeString(node.tagName, 'element'),
        elementId: this.normalizeString(node.elementId),
        classTokens: classTokens,
        textPreview: this.normalizeString(node.textPreview).substring(0, 32),
        childCount: this.normalizeCount(node.childCount),
        selected: node.selected === true
      };
      result.push(normalizedNode);
    });
    return result;
  }

  private normalizeBox(box: ElementInspectionBoxModel): ElementInspectionBoxModel {
    return {
      marginTop: this.normalizeDimension(box.marginTop),
      marginRight: this.normalizeDimension(box.marginRight),
      marginBottom: this.normalizeDimension(box.marginBottom),
      marginLeft: this.normalizeDimension(box.marginLeft),
      borderTop: this.normalizeDimension(box.borderTop),
      borderRight: this.normalizeDimension(box.borderRight),
      borderBottom: this.normalizeDimension(box.borderBottom),
      borderLeft: this.normalizeDimension(box.borderLeft),
      paddingTop: this.normalizeDimension(box.paddingTop),
      paddingRight: this.normalizeDimension(box.paddingRight),
      paddingBottom: this.normalizeDimension(box.paddingBottom),
      paddingLeft: this.normalizeDimension(box.paddingLeft),
      contentWidth: this.normalizeDimension(box.contentWidth),
      contentHeight: this.normalizeDimension(box.contentHeight)
    };
  }

  private normalizeLogs(entries: ElementInspectionConsoleEntry[]): ElementInspectionConsoleEntry[] {
    const result: ElementInspectionConsoleEntry[] = [];
    entries.forEach((entry: ElementInspectionConsoleEntry): void => {
      if (result.length >= 80) {
        return;
      }
      const level = this.normalizeString(entry.level, 'log');
      const text = this.normalizeString(entry.text);
      if (text.length === 0) {
        return;
      }
      result.push({
        level: level === 'info' || level === 'warn' || level === 'error' || level === 'debug' ? level : 'log',
        text: text.substring(0, 240),
        time: this.normalizeCount(entry.time)
      });
    });
    return result;
  }

  private normalizeNetwork(entries: ElementInspectionNetworkEntry[]): ElementInspectionNetworkEntry[] {
    const result: ElementInspectionNetworkEntry[] = [];
    entries.forEach((entry: ElementInspectionNetworkEntry): void => {
      if (result.length >= 40) {
        return;
      }
      const url = this.normalizeString(entry.url);
      if (url.length === 0) {
        return;
      }
      result.push({
        method: this.normalizeString(entry.method, 'GET').substring(0, 12),
        url: url.substring(0, 180),
        status: this.normalizeCount(entry.status),
        type: this.normalizeString(entry.type).substring(0, 48),
        size: this.normalizeCount(entry.size),
        durationMs: this.normalizeCount(entry.durationMs),
        startedAt: this.normalizeCount(entry.startedAt)
      });
    });
    return result;
  }

  private normalizeSources(entries: ElementInspectionSourceEntry[]): ElementInspectionSourceEntry[] {
    const result: ElementInspectionSourceEntry[] = [];
    entries.forEach((entry: ElementInspectionSourceEntry): void => {
      if (result.length >= 40) {
        return;
      }
      const id = this.normalizeString(entry.id);
      if (!this.isSourceId(id)) {
        return;
      }
      result.push({
        id: id,
        kind: this.normalizeString(entry.kind, 'script'),
        name: this.normalizeString(entry.name, id).substring(0, 80),
        url: this.normalizeString(entry.url).substring(0, 180)
      });
    });
    return result;
  }

  private normalizeListeners(entries: ElementInspectionListenerEntry[]): ElementInspectionListenerEntry[] {
    const result: ElementInspectionListenerEntry[] = [];
    entries.forEach((entry: ElementInspectionListenerEntry): void => {
      if (result.length >= 24) {
        return;
      }
      const type = this.normalizeString(entry.type);
      if (type.length === 0) {
        return;
      }
      const source = this.normalizeString(entry.source, 'listener');
      result.push({
        type: type.substring(0, 32),
        capture: entry.capture === true,
        source: source === 'attribute' ? 'attribute' : 'listener'
      });
    });
    return result;
  }

  private normalizePageInfo(info: ElementInspectionPageInfo): ElementInspectionPageInfo {
    return {
      url: this.normalizeString(info.url).substring(0, 180),
      title: this.normalizeString(info.title).substring(0, 80),
      userAgent: this.normalizeString(info.userAgent).substring(0, 180),
      viewportWidth: this.normalizeCount(info.viewportWidth),
      viewportHeight: this.normalizeCount(info.viewportHeight),
      devicePixelRatio: Number.isFinite(info.devicePixelRatio) ? info.devicePixelRatio : 1
    };
  }

  private normalizeComputed(properties: ElementInspectionComputedProperty[]): ElementInspectionComputedProperty[] {
    const result: ElementInspectionComputedProperty[] = [];
    properties.forEach((property: ElementInspectionComputedProperty): void => {
      if (result.length >= 24) {
        return;
      }
      const name = this.normalizeString(property.name);
      const value = this.normalizeString(property.value);
      if (name.length === 0 || value.length === 0) {
        return;
      }
      result.push({ name: name, value: value.substring(0, 80) });
    });
    return result;
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

  private normalizeDimension(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.round(value * 10) / 10);
  }

  private encodeScriptString(value: string): string {
    return JSON.stringify(String(value ?? ''));
  }
}
