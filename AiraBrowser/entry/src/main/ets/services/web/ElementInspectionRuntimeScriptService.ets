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
  hidden?: boolean;
  expanded?: boolean;
  closing?: boolean;
  rowKind?: string;
  moreCount?: number;
  moreDirection?: string;
  moreStart?: number;
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
  waitMs: number;
  downloadMs: number;
  offsetMs: number;
  timed: boolean;
}

export interface ElementInspectionStorageEntry {
  name: string;
  value: string;
  redacted: boolean;
}

export interface ElementInspectionStorageSnapshot {
  local: ElementInspectionStorageEntry[];
  session: ElementInspectionStorageEntry[];
  cookies: ElementInspectionStorageEntry[];
  databases: string[];
}

export interface ElementInspectionSecuritySummary {
  secure: boolean;
  protocol: string;
  origin: string;
  url: string;
  mixedUrls: string[];
  certificateError: boolean;
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
  storage?: ElementInspectionStorageSnapshot;
  security?: ElementInspectionSecuritySummary;
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

export interface ElementInspectionContextActionResult {
  ok: boolean;
  reason: string;
  protocolVersion: number;
  sessionGeneration: number;
  documentToken: string;
  text: string;
  snapshot: ElementInspectionRuntimeSnapshot;
}

interface ElementInspectionContextActionWire {
  ok?: boolean;
  reason?: string;
  protocolVersion?: number;
  sessionGeneration?: number;
  documentToken?: string;
  text?: string;
  snapshot?: ElementInspectionRuntimeSnapshot;
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
const ELEMENT_INSPECTION_OUTLINE_COMMAND_KINDS: string[] = [
  'copy_selector',
  'copy_js_path',
  'copy_xpath',
  'copy_html',
  'copy_styles',
  'read_html',
  'read_attributes',
  'duplicate',
  'delete',
  'cut',
  'paste',
  'hide',
  'scroll_into_view',
  'focus',
  'store_global',
  'set_attribute',
  'replace_html',
  'paste_html',
  'toggle_outline',
  'outline_more'
];
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
  highlight.appendChild(highlightBorder);
  highlight.appendChild(highlightPadding);
  highlight.appendChild(highlightContent);
  document.documentElement.appendChild(highlight);
  function tooltipNode(styles) {
    var node = document.createElement('div');
    node.setAttribute(uiAttribute, 'true');
    node.style.cssText = styles;
    return node;
  }
  var tooltip = tooltipNode([
    'position:fixed!important',
    'left:8px!important',
    'top:8px!important',
    'width:280px!important',
    'box-sizing:border-box!important',
    'padding:10px 12px 8px!important',
    'background:#ffffff!important',
    'color:#202124!important',
    'border:1px solid rgba(0,0,0,0.08)!important',
    'border-radius:8px!important',
    'box-shadow:0 8px 24px rgba(0,0,0,0.18)!important',
    'font:12px/16px sans-serif!important',
    'pointer-events:none!important',
    'z-index:2147483647!important',
    'display:none!important',
    'text-align:left!important'
  ].join(';'));
  var tooltipCaret = tooltipNode([
    'position:absolute!important',
    'width:12px!important',
    'height:12px!important',
    'background:#ffffff!important',
    'transform:rotate(45deg)!important',
    'bottom:-6px!important',
    'left:24px!important',
    'box-shadow:2px 2px 2px rgba(0,0,0,0.04)!important'
  ].join(';'));
  function tooltipRow() {
    return tooltipNode([
      'display:flex!important',
      'align-items:center!important',
      'justify-content:space-between!important',
      'gap:12px!important',
      'min-height:22px!important',
      'margin:0!important',
      'padding:0!important'
    ].join(';'));
  }
  function tooltipLabel(text) {
    var node = tooltipNode('flex:0 0 auto!important;color:#202124!important;font:12px/16px sans-serif!important;');
    node.textContent = text;
    return node;
  }
  function tooltipValueNode() {
    return tooltipNode([
      'min-width:0!important',
      'color:#202124!important',
      'font:12px/16px sans-serif!important',
      'text-align:right!important',
      'white-space:nowrap!important',
      'overflow:hidden!important',
      'text-overflow:ellipsis!important'
    ].join(';'));
  }
  var tooltipHeader = tooltipRow();
  var tooltipIdentity = tooltipNode('display:flex!important;align-items:center!important;gap:6px!important;min-width:0!important;');
  var tooltipIcon = tooltipNode([
    'width:14px!important',
    'height:14px!important',
    'box-sizing:border-box!important',
    'border:1.5px solid #1a73e8!important',
    'border-radius:2px!important',
    'flex:0 0 auto!important',
    'position:relative!important'
  ].join(';'));
  tooltipIcon.appendChild(tooltipNode([
    'position:absolute!important',
    'left:2px!important',
    'top:2px!important',
    'width:6px!important',
    'height:6px!important',
    'background:#1a73e8!important'
  ].join(';')));
  var tooltipTag = tooltipNode('color:#881280!important;font:700 13px/16px sans-serif!important;');
  var tooltipSize = tooltipValueNode();
  tooltipSize.style.setProperty('color', '#5f6368', 'important');
  tooltipIdentity.appendChild(tooltipIcon);
  tooltipIdentity.appendChild(tooltipTag);
  tooltipHeader.appendChild(tooltipIdentity);
  tooltipHeader.appendChild(tooltipSize);
  var tooltipColorRow = tooltipRow();
  var tooltipColorValue = tooltipNode('display:flex!important;align-items:center!important;justify-content:flex-end!important;gap:6px!important;min-width:0!important;');
  var tooltipSwatch = tooltipNode([
    'width:14px!important',
    'height:14px!important',
    'border-radius:3px!important',
    'border:1px solid rgba(0,0,0,0.16)!important',
    'background:#000000!important',
    'flex:0 0 auto!important'
  ].join(';'));
  var tooltipColorText = tooltipValueNode();
  tooltipColorValue.appendChild(tooltipSwatch);
  tooltipColorValue.appendChild(tooltipColorText);
  tooltipColorRow.appendChild(tooltipLabel('颜色'));
  tooltipColorRow.appendChild(tooltipColorValue);
  var tooltipFontRow = tooltipRow();
  var tooltipFont = tooltipValueNode();
  tooltipFontRow.appendChild(tooltipLabel('字体'));
  tooltipFontRow.appendChild(tooltipFont);
  var tooltipPaddingRow = tooltipRow();
  var tooltipPadding = tooltipValueNode();
  tooltipPaddingRow.appendChild(tooltipLabel('内边距'));
  tooltipPaddingRow.appendChild(tooltipPadding);
  var tooltipA11y = tooltipNode('display:flex!important;align-items:center!important;gap:8px!important;margin:8px 0 2px!important;');
  var tooltipA11yText = tooltipNode('flex:0 0 auto!important;color:#80868b!important;font:11px/16px sans-serif!important;letter-spacing:0.4px!important;');
  tooltipA11yText.textContent = '无障碍';
  tooltipA11y.appendChild(tooltipA11yText);
  tooltipA11y.appendChild(tooltipNode('flex:1 1 auto!important;height:1px!important;background:#e0e0e0!important;'));
  var tooltipNameRow = tooltipRow();
  var tooltipName = tooltipValueNode();
  tooltipNameRow.appendChild(tooltipLabel('名称'));
  tooltipNameRow.appendChild(tooltipName);
  var tooltipRoleRow = tooltipRow();
  var tooltipRole = tooltipValueNode();
  tooltipRoleRow.appendChild(tooltipLabel('角色'));
  tooltipRoleRow.appendChild(tooltipRole);
  var tooltipFocusRow = tooltipRow();
  var tooltipFocusValue = tooltipNode('display:flex!important;justify-content:flex-end!important;');
  function createFocusIcon(focusable) {
    var icon = tooltipNode([
      'width:14px!important',
      'height:14px!important',
      'border-radius:50%!important',
      'box-sizing:border-box!important',
      'border:1.5px solid ' + (focusable ? '#1a73e8' : '#9aa0a6') + '!important',
      'position:relative!important'
    ].join(';'));
    if (focusable) {
      icon.appendChild(tooltipNode([
        'position:absolute!important',
        'left:3px!important',
        'top:3px!important',
        'width:6px!important',
        'height:6px!important',
        'border-radius:50%!important',
        'background:#1a73e8!important'
      ].join(';')));
    } else {
      icon.appendChild(tooltipNode([
        'position:absolute!important',
        'left:6px!important',
        'top:-1px!important',
        'width:1.5px!important',
        'height:16px!important',
        'background:#9aa0a6!important',
        'transform:rotate(45deg)!important'
      ].join(';')));
    }
    return icon;
  }
  var tooltipFocusYes = createFocusIcon(true);
  var tooltipFocusNo = createFocusIcon(false);
  tooltipFocusValue.appendChild(tooltipFocusYes);
  tooltipFocusValue.appendChild(tooltipFocusNo);
  tooltipFocusRow.appendChild(tooltipLabel('可键盘聚焦'));
  tooltipFocusRow.appendChild(tooltipFocusValue);
  tooltip.appendChild(tooltipCaret);
  tooltip.appendChild(tooltipHeader);
  tooltip.appendChild(tooltipColorRow);
  tooltip.appendChild(tooltipFontRow);
  tooltip.appendChild(tooltipPaddingRow);
  tooltip.appendChild(tooltipA11y);
  tooltip.appendChild(tooltipNameRow);
  tooltip.appendChild(tooltipRoleRow);
  tooltip.appendChild(tooltipFocusRow);
  document.documentElement.appendChild(tooltip);
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
    indexedDatabases: [],
    databaseReadPending: false,
    databaseReadAt: 0,
    listenerMap: [],
    debugHooks: null,
    previewNode: null,
    pickerArmed: true,
    lastHoverSelectAt: 0,
    savedCursor: '',
    globalSeq: 0,
    expandedPaths: { '': true },
    outlineCollapsed: {},
    childWindowStart: {},
    outlineRevealPending: false
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
    if (runtime.network.length > 80) {
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
  function isSensitiveStorageName(name) {
    var value = String(name || '').toLowerCase();
    return value.indexOf('password') >= 0 ||
      value.indexOf('passwd') >= 0 ||
      value.indexOf('secret') >= 0 ||
      value.indexOf('token') >= 0 ||
      value.indexOf('authorization') >= 0 ||
      value.indexOf('credential') >= 0;
  }
  function readStorageArea(storage) {
    var result = [];
    if (!storage) {
      return result;
    }
    var length = 0;
    try {
      length = storage.length || 0;
    } catch (error) {
      return result;
    }
    for (var index = 0; index < length && result.length < 40; index++) {
      var name = '';
      var raw = '';
      try {
        name = String(storage.key(index) || '');
        raw = String(storage.getItem(name) || '');
      } catch (error) {
        continue;
      }
      if (!name) {
        continue;
      }
      var redacted = isSensitiveStorageName(name);
      result.push({
        name: safeString(name, 80),
        value: redacted ? '' : safeString(raw, 160),
        redacted: redacted
      });
    }
    return result;
  }
  function readCookies() {
    var result = [];
    var raw = '';
    try {
      raw = String(document.cookie || '');
    } catch (error) {
      return result;
    }
    if (!raw) {
      return result;
    }
    var parts = raw.split(';');
    for (var index = 0; index < parts.length && result.length < 40; index++) {
      var part = parts[index];
      var splitAt = part.indexOf('=');
      var name = splitAt >= 0 ? part.substring(0, splitAt) : part;
      var value = splitAt >= 0 ? part.substring(splitAt + 1) : '';
      name = name.replace(/^\\s+|\\s+$/g, '');
      if (!name) {
        continue;
      }
      var redacted = isSensitiveStorageName(name);
      result.push({
        name: safeString(name, 80),
        value: redacted ? '' : safeString(value, 160),
        redacted: redacted
      });
    }
    return result;
  }
  function refreshIndexedDatabases() {
    if (runtime.databaseReadPending || !window.indexedDB || typeof indexedDB.databases !== 'function') {
      return;
    }
    var now = Date.now();
    if (now - (runtime.databaseReadAt || 0) < 2000) {
      return;
    }
    runtime.databaseReadPending = true;
    runtime.databaseReadAt = now;
    try {
      var pending = indexedDB.databases();
      if (!pending || typeof pending.then !== 'function') {
        runtime.databaseReadPending = false;
        return;
      }
      pending.then(function(list) {
        var names = [];
        var items = list || [];
        for (var index = 0; index < items.length && names.length < 40; index++) {
          var name = items[index] && items[index].name ? String(items[index].name) : '';
          if (name) {
            names.push(safeString(name, 80));
          }
        }
        runtime.indexedDatabases = names;
        runtime.databaseReadPending = false;
      }, function() {
        runtime.databaseReadPending = false;
      });
    } catch (error) {
      runtime.databaseReadPending = false;
    }
  }
  function buildStorage() {
    refreshIndexedDatabases();
    return {
      local: readStorageArea(window.localStorage),
      session: readStorageArea(window.sessionStorage),
      cookies: readCookies(),
      databases: runtime.indexedDatabases || []
    };
  }
  function pushMixed(result, seen, url) {
    var value = safeString(url, 180);
    if (!value || value.toLowerCase().indexOf('http:') !== 0 || seen[value] || result.length >= 8) {
      return;
    }
    seen[value] = true;
    result.push(value);
  }
  function collectMixedFrom(nodes, attribute, result, seen) {
    var list = nodes || [];
    for (var index = 0; index < list.length && result.length < 8 && index < 80; index++) {
      var node = list[index];
      var url = '';
      try {
        url = node && node.getAttribute ? node.getAttribute(attribute) || '' : '';
      } catch (error) {}
      pushMixed(result, seen, url);
    }
  }
  function buildSecurity() {
    var protocol = 'unknown';
    var origin = '';
    var pageUrl = '';
    var secure = false;
    try {
      protocol = String(location.protocol || '').replace(':', '');
      origin = String(location.origin || '');
      pageUrl = String(location.href || '');
      secure = window.isSecureContext === true;
    } catch (error) {}
    var mixed = [];
    var seen = {};
    if (protocol === 'https') {
      try {
        if (window.performance && performance.getEntriesByType) {
          var resources = performance.getEntriesByType('resource') || [];
          for (var index = 0; index < resources.length && mixed.length < 8; index++) {
            pushMixed(mixed, seen, resources[index] && resources[index].name);
          }
        }
      } catch (error) {}
      collectMixedFrom(document.images, 'src', mixed, seen);
      collectMixedFrom(document.scripts, 'src', mixed, seen);
      collectMixedFrom(document.querySelectorAll('link[href]'), 'href', mixed, seen);
    }
    return {
      secure: secure,
      protocol: safeString(protocol, 16),
      origin: safeString(origin, 180),
      url: safeString(pageUrl, 180),
      mixedUrls: mixed,
      certificateError: false
    };
  }
  function absoluteUrl(url) {
    var value = String(url || '');
    if (!value) {
      return '';
    }
    try {
      return new URL(value, location.href).href;
    } catch (error) {
      return value;
    }
  }
  function buildNetwork() {
    var hooked = runtime.network || [];
    var byUrl = {};
    for (var hookIndex = 0; hookIndex < hooked.length; hookIndex++) {
      var hookedEntry = hooked[hookIndex];
      if (hookedEntry && hookedEntry.url) {
        byUrl[absoluteUrl(hookedEntry.url)] = hookedEntry;
      }
    }
    var timings = [];
    try {
      if (window.performance && performance.getEntriesByType) {
        var navigation = performance.getEntriesByType('navigation') || [];
        var resources = performance.getEntriesByType('resource') || [];
        for (var navigationIndex = 0; navigationIndex < navigation.length; navigationIndex++) {
          timings.push(navigation[navigationIndex]);
        }
        for (var resourceIndex = 0; resourceIndex < resources.length; resourceIndex++) {
          timings.push(resources[resourceIndex]);
        }
      }
    } catch (error) {}
    var originStart = 0;
    var hasOrigin = false;
    for (var startIndex = 0; startIndex < timings.length; startIndex++) {
      var startTime = Number(timings[startIndex] && timings[startIndex].startTime) || 0;
      if (!hasOrigin || startTime < originStart) {
        originStart = startTime;
        hasOrigin = true;
      }
    }
    var entries = [];
    var seenUrl = {};
    for (var index = 0; index < timings.length && entries.length < 60; index++) {
      var timing = timings[index];
      if (!timing) {
        continue;
      }
      var url = safeString(timing.name || '', 180);
      if (!url || seenUrl[url]) {
        continue;
      }
      seenUrl[url] = true;
      var matched = byUrl[url] || null;
      var requestStart = Number(timing.requestStart) || 0;
      var responseStart = Number(timing.responseStart) || 0;
      var responseEnd = Number(timing.responseEnd) || 0;
      var timingStart = Number(timing.startTime) || 0;
      var waitMs = 0;
      var downloadMs = 0;
      if (responseStart > 0 && requestStart > 0 && responseStart >= requestStart) {
        waitMs = Math.round(responseStart - requestStart);
      } else if (responseStart > 0 && timingStart > 0 && responseStart >= timingStart) {
        waitMs = Math.round(responseStart - timingStart);
      }
      if (responseEnd > 0 && responseStart > 0 && responseEnd >= responseStart) {
        downloadMs = Math.round(responseEnd - responseStart);
      }
      var durationMs = Math.round(Number(timing.duration) || 0);
      if (durationMs <= 0 && waitMs + downloadMs > 0) {
        durationMs = waitMs + downloadMs;
      }
      var size = Number(timing.transferSize) || Number(timing.encodedBodySize) || Number(timing.decodedBodySize) || 0;
      if (matched && Number(matched.size) > size) {
        size = Number(matched.size) || size;
      }
      var initiator = String(timing.initiatorType || '');
      entries.push({
        method: matched ? String(matched.method || '') : (initiator === 'navigation' ? 'GET' : ''),
        url: url,
        status: matched ? (Number(matched.status) || 0) : 0,
        type: safeString(initiator || (matched ? matched.type : ''), 48),
        size: size,
        durationMs: durationMs,
        startedAt: matched ? (Number(matched.startedAt) || 0) : 0,
        waitMs: waitMs,
        downloadMs: downloadMs,
        offsetMs: hasOrigin ? Math.max(0, Math.round(timingStart - originStart)) : 0,
        timed: true
      });
    }
    for (var extraIndex = 0; extraIndex < hooked.length && entries.length < 60; extraIndex++) {
      var extra = hooked[extraIndex];
      if (!extra || !extra.url || seenUrl[String(extra.url)]) {
        continue;
      }
      var extraUrl = safeString(absoluteUrl(extra.url), 180);
      if (!extraUrl || seenUrl[extraUrl]) {
        continue;
      }
      seenUrl[extraUrl] = true;
      entries.push({
        method: String(extra.method || 'GET'),
        url: extraUrl,
        status: Number(extra.status) || 0,
        type: safeString(extra.type || 'fetch', 48),
        size: Number(extra.size) || 0,
        durationMs: Number(extra.durationMs) || 0,
        startedAt: Number(extra.startedAt) || 0,
        waitMs: Number(extra.durationMs) || 0,
        downloadMs: 0,
        offsetMs: 0,
        timed: false
      });
    }
    return entries;
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
    revealOutlineAncestors(node);
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
  function formatMeasure(value) {
    var scaled = Math.round(Number(value) * 100) / 100;
    if (!isFinite(scaled)) {
      return '0';
    }
    return String(scaled);
  }
  function hexChannel(value) {
    var channel = Math.max(0, Math.min(255, Math.round(Number(value) || 0)));
    var hex = channel.toString(16).toUpperCase();
    return hex.length < 2 ? '0' + hex : hex;
  }
  function cssColorText(value) {
    var text = String(value || '');
    var open = text.indexOf('(');
    var close = text.indexOf(')');
    if (open < 0 || close <= open) {
      return text;
    }
    var parts = text.substring(open + 1, close).split(',');
    if (parts.length < 3) {
      return text;
    }
    var hex = '#' + hexChannel(parts[0]) + hexChannel(parts[1]) + hexChannel(parts[2]);
    if (parts.length > 3) {
      var alpha = parseFloat(parts[3]);
      if (isFinite(alpha) && alpha < 1) {
        return hex + ' / ' + Math.round(alpha * 100) + '%';
      }
    }
    return hex;
  }
  function formatSideShorthand(top, right, bottom, left) {
    var sides = [top || '0px', right || '0px', bottom || '0px', left || '0px'];
    if (sides[0] === sides[1] && sides[1] === sides[2] && sides[2] === sides[3]) {
      return sides[0];
    }
    if (sides[0] === sides[2] && sides[1] === sides[3]) {
      return sides[0] + ' ' + sides[1];
    }
    if (sides[1] === sides[3]) {
      return sides[0] + ' ' + sides[1] + ' ' + sides[2];
    }
    return sides[0] + ' ' + sides[1] + ' ' + sides[2] + ' ' + sides[3];
  }
  function shortText(value, limit) {
    var text = collapseSpace(value);
    if (text.length <= limit) {
      return text;
    }
    return text.substring(0, limit) + '...';
  }
  function labelledByText(node) {
    var labelledBy = node.getAttribute ? node.getAttribute('aria-labelledby') : '';
    if (!labelledBy) {
      return '';
    }
    var ids = String(labelledBy).split(' ');
    var text = '';
    for (var index = 0; index < ids.length && text.length < 80; index++) {
      if (!ids[index]) {
        continue;
      }
      var target = document.getElementById(ids[index]);
      if (target && target.textContent) {
        text += (text ? ' ' : '') + target.textContent;
      }
    }
    return shortText(text, 48);
  }
  function accessibleName(node) {
    if (!node || !node.getAttribute) {
      return '';
    }
    var ariaLabel = node.getAttribute('aria-label');
    if (ariaLabel) {
      return shortText(ariaLabel, 48);
    }
    var labelled = labelledByText(node);
    if (labelled) {
      return labelled;
    }
    var tag = String(node.tagName || '').toLowerCase();
    if ((tag === 'img' || tag === 'input') && node.getAttribute('alt')) {
      return shortText(node.getAttribute('alt'), 48);
    }
    if (node.id) {
      var labels = document.querySelectorAll('label');
      for (var index = 0; index < labels.length; index++) {
        if (labels[index].getAttribute && labels[index].getAttribute('for') === node.id) {
          return shortText(labels[index].textContent || '', 48);
        }
      }
    }
    if (tag === 'button' || tag === 'a' || tag === 'summary' || tag === 'label') {
      return shortText(node.textContent || '', 48);
    }
    var title = node.getAttribute('title');
    return title ? shortText(title, 48) : '';
  }
  function accessibleRole(node) {
    var explicitRole = node.getAttribute ? node.getAttribute('role') : '';
    if (explicitRole) {
      return shortText(explicitRole, 32);
    }
    var tag = String(node.tagName || '').toLowerCase();
    if (tag === 'a' && node.getAttribute && node.getAttribute('href')) {
      return 'link';
    }
    if (tag === 'button') {
      return 'button';
    }
    if (tag === 'img') {
      return 'image';
    }
    if (tag === 'textarea' || tag === 'select') {
      return tag === 'select' ? 'combobox' : 'textbox';
    }
    if (tag === 'input') {
      var inputType = String(node.getAttribute('type') || 'text').toLowerCase();
      if (inputType === 'checkbox' || inputType === 'radio' || inputType === 'button' ||
        inputType === 'submit' || inputType === 'reset') {
        return inputType === 'submit' || inputType === 'reset' ? 'button' : inputType;
      }
      return 'textbox';
    }
    if (tag === 'nav') {
      return 'navigation';
    }
    if (tag === 'ul' || tag === 'ol') {
      return 'list';
    }
    if (tag === 'li') {
      return 'listitem';
    }
    if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
      return 'heading';
    }
    if (tag === 'header') {
      return 'banner';
    }
    if (tag === 'footer') {
      return 'contentinfo';
    }
    if (tag === 'main') {
      return 'main';
    }
    if (tag === 'p') {
      return 'paragraph';
    }
    return 'generic';
  }
  function isKeyboardFocusable(node) {
    if (!node || node.disabled) {
      return false;
    }
    var tab = node.getAttribute ? node.getAttribute('tabindex') : null;
    if (tab !== null && String(tab).length > 0) {
      var tabValue = Number(tab);
      return isFinite(tabValue) && tabValue >= 0;
    }
    var tag = String(node.tagName || '').toLowerCase();
    if (tag === 'a') {
      return !!(node.getAttribute && node.getAttribute('href'));
    }
    if (tag === 'button' || tag === 'input' || tag === 'select' || tag === 'textarea' || tag === 'summary') {
      return true;
    }
    return node.isContentEditable === true;
  }
  function hideTooltip() {
    tooltip.style.setProperty('display', 'none', 'important');
  }
  function placeTooltip(rect) {
    tooltip.style.setProperty('display', 'block', 'important');
    var width = tooltip.offsetWidth || 280;
    var height = tooltip.offsetHeight || 180;
    var gap = 10;
    var viewportWidth = window.innerWidth || document.documentElement.clientWidth || width;
    var viewportHeight = window.innerHeight || document.documentElement.clientHeight || height;
    var left = rect.left + rect.width / 2 - width / 2;
    var top = rect.top - height - gap;
    var below = top < 8;
    if (below) {
      top = rect.bottom + gap;
    }
    var maxLeft = Math.max(8, viewportWidth - width - 8);
    var maxTop = Math.max(8, viewportHeight - height - 8);
    if (left < 8) {
      left = 8;
    } else if (left > maxLeft) {
      left = maxLeft;
    }
    if (top < 8) {
      top = 8;
    } else if (top > maxTop) {
      top = maxTop;
    }
    tooltip.style.setProperty('left', left + 'px', 'important');
    tooltip.style.setProperty('top', top + 'px', 'important');
    var caretLeft = rect.left + rect.width / 2 - left - 6;
    if (caretLeft < 14) {
      caretLeft = 14;
    } else if (caretLeft > width - 26) {
      caretLeft = width - 26;
    }
    tooltipCaret.style.setProperty('left', caretLeft + 'px', 'important');
    if (below) {
      tooltipCaret.style.setProperty('top', '-6px', 'important');
      tooltipCaret.style.setProperty('bottom', 'auto', 'important');
    } else {
      tooltipCaret.style.setProperty('top', 'auto', 'important');
      tooltipCaret.style.setProperty('bottom', '-6px', 'important');
    }
  }
  function fillTooltip(node, style, rect) {
    var color = style.getPropertyValue('color') || '';
    var focusable = isKeyboardFocusable(node);
    tooltipTag.textContent = String(node.tagName || '').toLowerCase();
    tooltipSize.textContent = formatMeasure(rect.width) + ' × ' + formatMeasure(rect.height);
    tooltipSwatch.style.setProperty('background', color || 'transparent', 'important');
    tooltipColorText.textContent = cssColorText(color);
    tooltipFont.textContent = shortText((style.getPropertyValue('font-size') || '') + ' ' +
      (style.getPropertyValue('font-family') || ''), 42);
    tooltipPadding.textContent = formatSideShorthand(
      style.getPropertyValue('padding-top'),
      style.getPropertyValue('padding-right'),
      style.getPropertyValue('padding-bottom'),
      style.getPropertyValue('padding-left')
    );
    tooltipName.textContent = accessibleName(node);
    tooltipRole.textContent = accessibleRole(node);
    tooltipFocusYes.style.setProperty('display', focusable ? 'block' : 'none', 'important');
    tooltipFocusNo.style.setProperty('display', focusable ? 'none' : 'block', 'important');
    placeTooltip(rect);
  }
  function updateHighlight() {
    var previewing = !!(runtime.previewNode && runtime.previewNode.isConnected);
    var node = previewing ? runtime.previewNode : null;
    if (!node && runtime.mode === 'inspected' && runtime.currentNode && runtime.currentNode.isConnected) {
      node = runtime.currentNode;
    }
    if (!node) {
      highlight.style.setProperty('display', 'none', 'important');
      hideTooltip();
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
    if (previewing) {
      fillTooltip(node, style, rect);
    } else {
      hideTooltip();
    }
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
  function outlineElementChildren(node) {
    var source = node && node.children ? node.children : [];
    var result = [];
    for (var index = 0; index < source.length; index++) {
      if (isOutlineTarget(source[index])) {
        result.push(source[index]);
      }
    }
    return result;
  }
  function revealOutlineAncestors(node) {
    var current = node ? node.parentElement : null;
    var guard = 0;
    while (current && current.nodeType === 1 && guard < 64) {
      setOutlineExpandedFlag(pathOf(current), true);
      runtime.outlineRevealPending = true;
      if (current === document.documentElement) {
        break;
      }
      current = current.parentElement;
      guard += 1;
    }
  }
  function setOutlineExpandedFlag(path, expanded) {
    if (!runtime.expandedPaths) {
      runtime.expandedPaths = {};
    }
    if (!runtime.outlineCollapsed) {
      runtime.outlineCollapsed = {};
    }
    if (expanded) {
      runtime.expandedPaths[path] = true;
      runtime.outlineCollapsed[path] = false;
      return;
    }
    runtime.expandedPaths[path] = false;
    runtime.outlineCollapsed[path] = true;
  }
  function isOutlineExpanded(node, path) {
    if (runtime.outlineCollapsed && runtime.outlineCollapsed[path] === true) {
      return false;
    }
    if (runtime.expandedPaths && runtime.expandedPaths[path] === true) {
      return true;
    }
    if (path.length === 0) {
      return true;
    }
    return String(node && node.tagName || '').toLowerCase() === 'body';
  }
  function outlineChildFocus(children, selected) {
    if (!selected) {
      return -1;
    }
    for (var index = 0; index < children.length; index++) {
      var child = children[index];
      if (child === selected || (child.contains && child.contains(selected))) {
        return index;
      }
    }
    return -1;
  }
  function outlineChildStart(path, children, selected) {
    if (!runtime.childWindowStart) {
      runtime.childWindowStart = {};
    }
    var start = Number(runtime.childWindowStart[path]) || 0;
    if (start < 0 || start >= children.length) {
      start = 0;
    }
    if (runtime.outlineRevealPending) {
      var focus = outlineChildFocus(children, selected);
      if (focus >= 0 && (focus < start || focus >= start + 40)) {
        start = Math.max(0, focus - 8);
        runtime.childWindowStart[path] = start;
      }
    }
    return start;
  }
  function pushOutlineRow(nodes, node, selected, expanded, closing, rowKind, moreCount, moreDirection) {
    if (!node || nodes.length >= 160) {
      return false;
    }
    var classTokens = [];
    if (!closing && node.classList) {
      var classLimit = Math.min(node.classList.length, 3);
      for (var classIndex = 0; classIndex < classLimit; classIndex++) {
        classTokens.push(safeString(node.classList[classIndex], 48));
      }
    }
    var children = outlineElementChildren(node);
    var textPreview = '';
    if (!closing && children.length === 0) {
      textPreview = safeString(collapseSpace(node.textContent).trim(), 32);
    }
    nodes.push({
      path: pathOf(node),
      depth: elementDepth(node) + (rowKind === 'more' ? 1 : 0),
      tagName: String(node.tagName || '').toLowerCase(),
      elementId: closing || rowKind === 'more' ? '' : safeString(node.id, 64),
      classTokens: classTokens,
      textPreview: textPreview,
      childCount: children.length,
      selected: selected === true && rowKind !== 'more',
      hidden: !!(node.classList && node.classList.contains('aira-inspect-hidden')),
      expanded: expanded === true,
      closing: closing === true,
      rowKind: rowKind,
      moreCount: moreCount || 0,
      moreDirection: moreDirection || '',
      moreStart: 0
    });
    return true;
  }
  function appendOutlineNode(nodes, node, selected) {
    if (!isOutlineTarget(node) || nodes.length >= 160) {
      return;
    }
    var path = pathOf(node);
    var children = outlineElementChildren(node);
    var expanded = children.length > 0 && isOutlineExpanded(node, path);
    var selectedNode = node === selected;
    pushOutlineRow(nodes, node, selectedNode, expanded, false, 'element', 0, '');
    if (!expanded || nodes.length >= 159) {
      return;
    }
    var start = outlineChildStart(path, children, selected);
    var end = Math.min(children.length, start + 40);
    if (start > 0) {
      var beforeRow = pushOutlineRow(nodes, node, false, false, false, 'more', start, 'before');
      if (beforeRow) {
        nodes[nodes.length - 1].moreStart = Math.max(0, start - 40);
      }
    }
    var rendered = start;
    for (var index = start; index < end && nodes.length < 158; index++) {
      var beforeCount = nodes.length;
      appendOutlineNode(nodes, children[index], selected);
      if (nodes.length === beforeCount) {
        break;
      }
      rendered = index + 1;
    }
    if (rendered < children.length) {
      var afterRow = pushOutlineRow(nodes, node, false, false, false, 'more', children.length - rendered, 'after');
      if (afterRow) {
        nodes[nodes.length - 1].moreStart = rendered;
      }
    }
    pushOutlineRow(nodes, node, selectedNode, true, true, 'close', 0, '');
  }
  function buildOutline(selected) {
    var nodes = [];
    var root = document.documentElement;
    if (!root) {
      return nodes;
    }
    var visibleSelected = selected && selected.isConnected ? selected : null;
    appendOutlineNode(nodes, root, visibleSelected);
    runtime.outlineRevealPending = false;
    return nodes;
  }
  function outlineTreeResult(ok) {
    return {
      ok: ok === true,
      reason: ok === true ? '' : 'node_missing',
      protocolVersion: runtime.protocolVersion,
      sessionGeneration: runtime.sessionGeneration,
      documentToken: runtime.documentToken,
      revision: runtime.revision,
      mode: runtime.mode,
      outline: buildOutline(runtime.currentNode)
    };
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
    result.network = buildNetwork();
    result.sources = buildSources();
    result.pageInfo = buildPageInfo();
    result.storage = buildStorage();
    result.security = buildSecurity();
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
  runtime.previewByPath = function(path) {
    var node = resolveOutlinePath(path);
    if (!isOutlineTarget(node)) {
      runtime.previewNode = null;
      updateHighlight();
      return { ok: false };
    }
    runtime.previewNode = node;
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
  runtime.setOutlineExpanded = function(path, expanded) {
    var node = resolveOutlinePath(path);
    if (!isOutlineTarget(node)) {
      return outlineTreeResult(false);
    }
    setOutlineExpandedFlag(pathOf(node), expanded === true);
    return outlineTreeResult(true);
  };
  runtime.shiftOutlineWindow = function(path, nextStart) {
    var node = resolveOutlinePath(path);
    if (!isOutlineTarget(node)) {
      return outlineTreeResult(false);
    }
    var children = outlineElementChildren(node);
    if (!runtime.childWindowStart) {
      runtime.childWindowStart = {};
    }
    var start = Math.floor(Number(nextStart) || 0);
    if (start < 0) {
      start = 0;
    }
    if (children.length > 0 && start >= children.length) {
      start = Math.max(0, children.length - 1);
    }
    runtime.childWindowStart[pathOf(node)] = start;
    runtime.outlineRevealPending = false;
    return outlineTreeResult(true);
  };
  function isStructuralTag(node) {
    var tag = String(node && node.tagName || '').toLowerCase();
    return tag === 'html' || tag === 'head' || tag === 'body';
  }
  function isAttributeName(value) {
    var name = String(value || '');
    if (name.length === 0 || name.length > 64) {
      return false;
    }
    var first = name.charCodeAt(0);
    if (!((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first === 95 || first === 58)) {
      return false;
    }
    for (var index = 1; index < name.length; index++) {
      var code = name.charCodeAt(index);
      var allowed = (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
        (code >= 48 && code <= 57) || code === 45 || code === 58 || code === 95;
      if (!allowed) {
        return false;
      }
    }
    return true;
  }
  function isDomId(value) {
    var text = String(value || '');
    if (text.length === 0 || text.length > 64) {
      return false;
    }
    var first = text.charCodeAt(0);
    if (!((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first === 95)) {
      return false;
    }
    for (var index = 1; index < text.length; index++) {
      var code = text.charCodeAt(index);
      var allowed = (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
        (code >= 48 && code <= 57) || code === 45 || code === 95;
      if (!allowed) {
        return false;
      }
    }
    return true;
  }
  function buildJsPath(node) {
    if (!node || node.nodeType !== 1) {
      return '';
    }
    if (node === document.body) {
      return 'document.body';
    }
    if (node === document.head) {
      return 'document.head';
    }
    if (node === document.documentElement) {
      return 'document.documentElement';
    }
    if (node.id && isDomId(node.id)) {
      return 'document.getElementById(' + JSON.stringify(node.id) + ')';
    }
    var selector = buildSelector(node);
    if (selector.length === 0) {
      return '';
    }
    return 'document.querySelector(' + JSON.stringify(selector) + ')';
  }
  function buildXPath(node) {
    if (!node || node.nodeType !== 1) {
      return '';
    }
    var elementId = node.id ? String(node.id) : '';
    if (elementId.length > 0 && elementId.indexOf('"') < 0 && elementId.indexOf("'") < 0) {
      return '//*[@id="' + elementId + '"]';
    }
    var parts = [];
    var current = node;
    var guard = 0;
    while (current && current.nodeType === 1 && guard < 64) {
      var tag = String(current.tagName || '').toLowerCase();
      var index = 1;
      var sibling = current.previousElementSibling;
      while (sibling) {
        if (String(sibling.tagName || '').toLowerCase() === tag) {
          index += 1;
        }
        sibling = sibling.previousElementSibling;
      }
      parts.unshift(tag + '[' + index + ']');
      if (current === document.documentElement) {
        break;
      }
      current = current.parentElement;
      guard += 1;
    }
    return '/' + parts.join('/');
  }
  function ensureHideStyle() {
    if (document.getElementById('aira-element-inspection-hide-style')) {
      return;
    }
    var style = document.createElement('style');
    style.id = 'aira-element-inspection-hide-style';
    style.setAttribute(uiAttribute, 'true');
    style.textContent = '.aira-inspect-hidden{display:none !important}';
    var parent = document.head || document.documentElement;
    if (parent) {
      parent.appendChild(style);
    }
  }
  function canProgrammaticFocus(node) {
    if (!node || node.disabled || typeof node.focus !== 'function') {
      return false;
    }
    if (isKeyboardFocusable(node)) {
      return true;
    }
    var tab = node.getAttribute ? node.getAttribute('tabindex') : null;
    if (tab === null || String(tab).length === 0) {
      return false;
    }
    var tabValue = Number(tab);
    return isFinite(tabValue);
  }
  function restoreInspectedTabIndex(node, previousTab) {
    try {
      if (previousTab === null) {
        node.removeAttribute('tabindex');
      } else {
        node.setAttribute('tabindex', previousTab);
      }
    } catch (error) {}
  }
  function focusInspectedNode(node) {
    if (!node || node.disabled || typeof node.focus !== 'function') {
      return false;
    }
    var previousTab = node.getAttribute ? node.getAttribute('tabindex') : null;
    var addedTab = false;
    if (!canProgrammaticFocus(node)) {
      try {
        node.setAttribute('tabindex', '-1');
        addedTab = true;
      } catch (error) {
        return false;
      }
    }
    try {
      node.focus();
    } catch (error) {
      if (addedTab) {
        node.removeAttribute('tabindex');
      }
      return false;
    }
    if (document.activeElement !== node) {
      if (addedTab) {
        restoreInspectedTabIndex(node, previousTab);
      }
      return false;
    }
    if (addedTab) {
      restoreInspectedTabIndex(node, previousTab);
      if (document.activeElement !== node) {
        try {
          node.setAttribute('tabindex', '-1');
          node.focus();
        } catch (error) {
          restoreInspectedTabIndex(node, previousTab);
          return false;
        }
        if (document.activeElement !== node) {
          restoreInspectedTabIndex(node, previousTab);
          return false;
        }
      }
    }
    try {
      node.scrollIntoView({ block: 'center', inline: 'nearest' });
    } catch (error) {
      try {
        node.scrollIntoView(true);
      } catch (scrollError) {}
    }
    return true;
  }
  function buildCopiedStyles(node) {
    var lines = [];
    var inlineStyle = node.getAttribute ? node.getAttribute('style') : '';
    if (inlineStyle && String(inlineStyle).length > 0) {
      lines.push(safeString(inlineStyle, 2000));
    }
    var sheets = document.styleSheets || [];
    for (var sheetIndex = 0; sheetIndex < sheets.length && lines.length < 40; sheetIndex++) {
      var rules = null;
      try {
        rules = sheets[sheetIndex].cssRules;
      } catch (error) {
        rules = null;
      }
      if (!rules) {
        continue;
      }
      for (var ruleIndex = 0; ruleIndex < rules.length && lines.length < 40; ruleIndex++) {
        var rule = rules[ruleIndex];
        if (!rule || !rule.selectorText) {
          continue;
        }
        var matched = false;
        try {
          matched = typeof node.matches === 'function' && node.matches(rule.selectorText);
        } catch (error) {
          matched = false;
        }
        if (!matched) {
          continue;
        }
        var cssText = safeString(rule.cssText, 2000);
        if (cssText.length > 0) {
          lines.push(cssText);
        }
      }
    }
    if (lines.length > 0) {
      return lines.join('\\n');
    }
    var computed = null;
    try {
      computed = window.getComputedStyle(node);
    } catch (error) {
      computed = null;
    }
    if (!computed) {
      return '';
    }
    var computedNames = ['display', 'position', 'color', 'background-color', 'font-size', 'font-weight',
      'line-height', 'width', 'height', 'margin', 'padding', 'border', 'overflow', 'z-index', 'opacity',
      'box-sizing', 'flex'];
    for (var computedIndex = 0; computedIndex < computedNames.length; computedIndex++) {
      var computedName = computedNames[computedIndex];
      var computedValue = '';
      try {
        computedValue = safeString(computed.getPropertyValue(computedName), 80);
      } catch (error) {
        computedValue = '';
      }
      if (computedValue.length > 0) {
        lines.push(computedName + ': ' + computedValue + ';');
      }
    }
    return lines.join('\\n');
  }
  function contextResult(ok, reason, text) {
    return {
      ok: ok === true,
      reason: reason || '',
      protocolVersion: runtime.protocolVersion,
      sessionGeneration: runtime.sessionGeneration,
      documentToken: runtime.documentToken,
      text: text || '',
      snapshot: runtime.snapshot()
    };
  }
  runtime.contextAction = function(kind, path, payload) {
    var action = String(kind || '');
    var node = resolveOutlinePath(path);
    if (!isOutlineTarget(node)) {
      return contextResult(false, 'node_missing', '');
    }
    if (action === 'copy_selector') {
      var selector = buildSelector(node);
      return contextResult(selector.length > 0, selector.length > 0 ? '' : 'selector_unavailable', selector);
    }
    if (action === 'copy_js_path') {
      var jsPath = buildJsPath(node);
      return contextResult(jsPath.length > 0, jsPath.length > 0 ? '' : 'selector_unavailable', jsPath);
    }
    if (action === 'copy_xpath') {
      var xpath = buildXPath(node);
      return contextResult(xpath.length > 0, xpath.length > 0 ? '' : 'selector_unavailable', xpath);
    }
    if (action === 'copy_styles') {
      var styles = buildCopiedStyles(node);
      if (styles.length === 0) {
        return contextResult(false, 'styles_unavailable', '');
      }
      if (styles.length > 20000) {
        return contextResult(true, 'style_truncated', styles.substring(0, 20000));
      }
      return contextResult(true, '', styles);
    }
    if (action === 'read_attributes') {
      var attrs = collectAttributes(node);
      var compact = [];
      var attrLimit = Math.min(attrs.length, 40);
      for (var attrIndex = 0; attrIndex < attrLimit; attrIndex++) {
        var attr = attrs[attrIndex];
        compact.push({
          name: attr.name,
          value: attr.redacted ? '' : safeString(attr.value, 500),
          redacted: attr.redacted === true
        });
      }
      return contextResult(true, '', JSON.stringify(compact));
    }
    if (action === 'copy_html' || action === 'read_html') {
      var html = '';
      try {
        html = String(node.outerHTML || '');
      } catch (error) {
        html = '';
      }
      if (action === 'read_html' && html.length > 12000) {
        return contextResult(false, 'html_too_large', '');
      }
      if (html.length > 20000) {
        return contextResult(true, 'html_truncated', html.substring(0, 20000));
      }
      return contextResult(html.length > 0, html.length > 0 ? '' : 'html_unavailable', html);
    }
    if (action === 'duplicate') {
      if (isStructuralTag(node) || !node.parentElement) {
        return contextResult(false, 'node_protected', '');
      }
      var copy = node.cloneNode(true);
      node.parentElement.insertBefore(copy, node.nextSibling);
      if (isOutlineTarget(copy)) {
        setCurrentNode(copy);
        updateHighlight();
      }
      return contextResult(true, '', '');
    }
    if (action === 'delete') {
      if (isStructuralTag(node) || !node.parentElement) {
        return contextResult(false, 'node_protected', '');
      }
      var parent = node.parentElement;
      parent.removeChild(node);
      if (isOutlineTarget(parent)) {
        setCurrentNode(parent);
        updateHighlight();
      }
      return contextResult(true, '', '');
    }
    if (action === 'hide') {
      if (isStructuralTag(node) || !node.classList) {
        return contextResult(false, 'node_protected', '');
      }
      ensureHideStyle();
      var hidden = true;
      if (node.classList.contains('aira-inspect-hidden')) {
        node.classList.remove('aira-inspect-hidden');
        hidden = false;
      } else {
        node.classList.add('aira-inspect-hidden');
        hidden = true;
      }
      setCurrentNode(node);
      updateHighlight();
      return contextResult(true, '', hidden ? 'hidden' : 'shown');
    }
    if (action === 'scroll_into_view') {
      try {
        node.scrollIntoView({ block: 'center', inline: 'nearest' });
      } catch (error) {
        node.scrollIntoView(true);
      }
      updateHighlight();
      return contextResult(true, '', '');
    }
    if (action === 'focus') {
      if (!focusInspectedNode(node)) {
        return contextResult(false, 'not_focusable', '');
      }
      setCurrentNode(node);
      updateHighlight();
      return contextResult(true, '', 'focused');
    }
    if (action === 'store_global') {
      runtime.globalSeq = (runtime.globalSeq || 0) + 1;
      var globalName = 'temp' + runtime.globalSeq;
      try {
        window[globalName] = node;
      } catch (error) {
        return contextResult(false, 'store_failed', '');
      }
      pushLog('log', [globalName]);
      return contextResult(true, '', globalName);
    }
    if (action === 'set_attribute') {
      var parsed = null;
      try {
        parsed = JSON.parse(String(payload || ''));
      } catch (error) {
        parsed = null;
      }
      var attrName = parsed && parsed.name ? String(parsed.name) : '';
      var previousName = parsed && parsed.previousName ? String(parsed.previousName) : '';
      var attrValue = parsed && parsed.value !== undefined && parsed.value !== null ? String(parsed.value) : '';
      if (!isAttributeName(attrName) || attrValue.length > 500 ||
        (previousName.length > 0 && previousName !== attrName && !isAttributeName(previousName))) {
        return contextResult(false, 'attribute_invalid', '');
      }
      try {
        if (previousName.length > 0 && previousName !== attrName) {
          node.removeAttribute(previousName);
        }
        if (attrValue.length === 0) {
          node.removeAttribute(attrName);
        } else {
          node.setAttribute(attrName, attrValue);
        }
      } catch (error) {
        return contextResult(false, 'attribute_rejected', '');
      }
      setCurrentNode(node);
      updateHighlight();
      return contextResult(true, '', '');
    }
    if (action === 'replace_html') {
      if (node === document.documentElement || !node.parentElement) {
        return contextResult(false, 'node_protected', '');
      }
      var nextHtml = String(payload || '');
      if (nextHtml.length === 0 || nextHtml.length > 12000) {
        return contextResult(false, 'html_rejected', '');
      }
      var holder = document.createElement('div');
      holder.innerHTML = nextHtml;
      var replacement = holder.firstElementChild;
      if (!replacement || holder.children.length !== 1) {
        return contextResult(false, 'html_rejected', '');
      }
      node.parentElement.replaceChild(replacement, node);
      if (isOutlineTarget(replacement)) {
        setCurrentNode(replacement);
        updateHighlight();
      }
      return contextResult(true, '', '');
    }
    if (action === 'paste_html') {
      if (node === document.documentElement || !node.parentElement) {
        return contextResult(false, 'node_protected', '');
      }
      var pasted = String(payload || '');
      if (pasted.length === 0 || pasted.length > 20000) {
        return contextResult(false, 'html_rejected', '');
      }
      try {
        node.insertAdjacentHTML('afterend', pasted);
      } catch (error) {
        return contextResult(false, 'html_rejected', '');
      }
      var inserted = node.nextElementSibling;
      if (isOutlineTarget(inserted)) {
        setCurrentNode(inserted);
        updateHighlight();
      }
      return contextResult(true, '', '');
    }
    return contextResult(false, 'action_unsupported', '');
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
    if (tooltip.parentNode) {
      tooltip.parentNode.removeChild(tooltip);
    }
    var hideStyle = document.getElementById('aira-element-inspection-hide-style');
    if (hideStyle && hideStyle.parentNode) {
      hideStyle.parentNode.removeChild(hideStyle);
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

  buildOutlineTreeScript(
    sessionGeneration: number,
    documentToken: string,
    kind: string,
    path: string,
    value: string
  ): string {
    if (!this.isOutlinePath(path) || (kind !== 'toggle_outline' && kind !== 'outline_more')) {
      return this.buildRuntimeCommandScript(sessionGeneration, documentToken, 'runtime.snapshot()');
    }
    if (kind === 'toggle_outline') {
      return this.buildRuntimeCommandScript(
        sessionGeneration,
        documentToken,
        `runtime.setOutlineExpanded(${this.encodeScriptString(path)}, ${value === '1' ? 'true' : 'false'})`
      );
    }
    const start = Math.max(0, Math.min(100000, Math.floor(Number(value))));
    const normalizedStart = Number.isFinite(start) ? start : 0;
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.shiftOutlineWindow(${this.encodeScriptString(path)}, ${normalizedStart})`
    );
  }

  buildPreviewOutlineScript(sessionGeneration: number, documentToken: string, path: string): string {
    if (!this.isOutlinePath(path)) {
      return this.buildRuntimeCommandScript(sessionGeneration, documentToken, 'runtime.clearPreview()');
    }
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.previewByPath(${this.encodeScriptString(path)})`
    );
  }

  isOutlineCommandKind(kind: string): boolean {
    return ELEMENT_INSPECTION_OUTLINE_COMMAND_KINDS.indexOf(kind) >= 0;
  }

  buildOutlineCommandScript(
    sessionGeneration: number,
    documentToken: string,
    kind: string,
    path: string,
    payload: string
  ): string {
    if (kind === 'cut' || kind === 'paste' || kind === 'toggle_outline' || kind === 'outline_more' ||
      !this.isOutlineCommandKind(kind) || !this.isOutlinePath(path)) {
      return this.buildRuntimeCommandScript(sessionGeneration, documentToken, 'runtime.snapshot()');
    }
    const normalizedPayload = payload.length > 20000 ? payload.substring(0, 20000) : payload;
    return this.buildRuntimeCommandScript(
      sessionGeneration,
      documentToken,
      `runtime.contextAction(${this.encodeScriptString(kind)}, ${this.encodeScriptString(path)}, ${this.encodeScriptString(normalizedPayload)})`
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
      if (parsed.storage !== undefined) {
        result.storage = this.normalizeStorage(parsed.storage);
      }
      if (parsed.security !== undefined) {
        result.security = this.normalizeSecurity(parsed.security);
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

  parseContextActionResult(rawValue: string): ElementInspectionContextActionResult {
    const failed: ElementInspectionContextActionResult = {
      ok: false,
      reason: 'invalid_context_action',
      protocolVersion: ELEMENT_INSPECTION_PROTOCOL_VERSION,
      sessionGeneration: 0,
      documentToken: '',
      text: '',
      snapshot: this.buildUnavailableSnapshot('invalid_context_action')
    };
    try {
      const parsed: ElementInspectionContextActionWire =
        JSON.parse(this.unwrapJsonString(rawValue)) as ElementInspectionContextActionWire;
      const snapshot = parsed.snapshot === undefined ?
        this.buildUnavailableSnapshot('missing_snapshot') :
        this.parseSnapshot(JSON.stringify(parsed.snapshot));
      return {
        ok: parsed.ok === true && parsed.protocolVersion === ELEMENT_INSPECTION_PROTOCOL_VERSION,
        reason: this.normalizeString(parsed.reason),
        protocolVersion: this.normalizeCount(parsed.protocolVersion),
        sessionGeneration: this.normalizeCount(parsed.sessionGeneration),
        documentToken: this.normalizeString(parsed.documentToken),
        text: this.normalizeRawString(parsed.text).substring(0, 20000),
        snapshot: snapshot
      };
    } catch (_error) {
      return failed;
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
      if (result.length >= 160) {
        return;
      }
      const path = this.normalizeString(node.path);
      const rowKind = node.rowKind === 'close' || node.rowKind === 'more' ? node.rowKind : 'element';
      const moreDirection = node.moreDirection === 'before' ? 'before' : 'after';
      const identity = rowKind === 'more' ? `${path}:more:${moreDirection}` :
        (rowKind === 'close' ? `${path}:close` : path);
      if (!this.isOutlinePath(path) || seen.indexOf(identity) >= 0) {
        return;
      }
      seen.push(identity);
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
        selected: node.selected === true && rowKind !== 'more',
        hidden: node.hidden === true,
        expanded: node.expanded === true,
        closing: rowKind === 'close',
        rowKind: rowKind,
        moreCount: this.normalizeCount(node.moreCount),
        moreDirection: moreDirection,
        moreStart: this.normalizeCount(node.moreStart)
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
      if (result.length >= 60) {
        return;
      }
      const url = this.normalizeString(entry.url);
      if (url.length === 0) {
        return;
      }
      result.push({
        method: this.normalizeString(entry.method).substring(0, 12),
        url: url.substring(0, 180),
        status: this.normalizeCount(entry.status),
        type: this.normalizeString(entry.type).substring(0, 48),
        size: this.normalizeCount(entry.size),
        durationMs: this.normalizeCount(entry.durationMs),
        startedAt: this.normalizeCount(entry.startedAt),
        waitMs: this.normalizeCount(entry.waitMs),
        downloadMs: this.normalizeCount(entry.downloadMs),
        offsetMs: this.normalizeCount(entry.offsetMs),
        timed: entry.timed === true
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

  private normalizeStorage(snapshot: ElementInspectionStorageSnapshot): ElementInspectionStorageSnapshot {
    return {
      local: this.normalizeStorageEntries(snapshot.local),
      session: this.normalizeStorageEntries(snapshot.session),
      cookies: this.normalizeStorageEntries(snapshot.cookies),
      databases: this.normalizeDatabaseNames(snapshot.databases)
    };
  }

  private normalizeStorageEntries(entries: ElementInspectionStorageEntry[] | undefined): ElementInspectionStorageEntry[] {
    const result: ElementInspectionStorageEntry[] = [];
    (entries ?? []).forEach((entry: ElementInspectionStorageEntry): void => {
      if (result.length >= 40) {
        return;
      }
      const name = this.normalizeString(entry.name);
      if (name.length === 0) {
        return;
      }
      const redacted = entry.redacted === true;
      result.push({
        name: name.substring(0, 80),
        value: redacted ? '' : this.normalizeRawString(entry.value).substring(0, 160),
        redacted: redacted
      });
    });
    return result;
  }

  private normalizeDatabaseNames(names: string[] | undefined): string[] {
    const result: string[] = [];
    (names ?? []).forEach((name: string): void => {
      if (result.length >= 40) {
        return;
      }
      const normalized = this.normalizeString(name);
      if (normalized.length > 0) {
        result.push(normalized.substring(0, 80));
      }
    });
    return result;
  }

  private normalizeSecurity(summary: ElementInspectionSecuritySummary): ElementInspectionSecuritySummary {
    const mixedUrls: string[] = [];
    (summary.mixedUrls ?? []).forEach((url: string): void => {
      if (mixedUrls.length >= 8) {
        return;
      }
      const normalized = this.normalizeString(url);
      if (normalized.toLowerCase().startsWith('http:')) {
        mixedUrls.push(normalized.substring(0, 180));
      }
    });
    return {
      secure: summary.secure === true,
      protocol: this.normalizeString(summary.protocol, 'unknown').substring(0, 16),
      origin: this.normalizeString(summary.origin).substring(0, 180),
      url: this.normalizeString(summary.url).substring(0, 180),
      mixedUrls: mixedUrls,
      certificateError: summary.certificateError === true
    };
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
