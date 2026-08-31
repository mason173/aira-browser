import {
  AdBlockCosmeticExecutionRule,
  AdBlockCosmeticSelectorCandidates
} from './AdBlockCosmeticExecutionModels';

const MAX_COSMETIC_NODES_PER_PASS: number = 600;
const MAX_COSMETIC_MUTATION_ROOTS_PER_PASS: number = 24;
const COSMETIC_OBSERVER_DEBOUNCE_MS: number = 120;
const COSMETIC_SELECTOR_QUERY_BATCH_SIZE: number = 32;

export interface AdBlockCosmeticRuntimeScriptResult {
  selectorCount: number;
  hiddenElementCount: number;
  placeholderCollapsedCount: number;
  totalActionCount: number;
  hiddenClickRectCount: number;
  guardListenerCount: number;
}

interface AdBlockCosmeticRuntimeRulePayload {
  selector: string;
  action: 'hide' | 'remove' | 'style' | 'remove-attr' | 'remove-class';
  style: string;
  procedural: boolean;
}

export class AdBlockCosmeticRuntimeScriptService {
  buildSelectorCandidateCollectionScript(): string {
    return `
;(function airaAdBlockCollectSelectorCandidates() {
  var maxValues = 8192;
  var maxLength = 256;
  var classes = [];
  var ids = [];
  var classSet = Object.create(null);
  var idSet = Object.create(null);
  var nodes = document.querySelectorAll('[class],[id]');
  for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex += 1) {
    var node = nodes[nodeIndex];
    var id = String(node.id || '');
    if (id && id.length <= maxLength && ids.length < maxValues && !idSet[id]) {
      idSet[id] = true;
      ids.push(id);
    }
    if (!node.classList || classes.length >= maxValues) {
      continue;
    }
    for (var classIndex = 0; classIndex < node.classList.length; classIndex += 1) {
      var className = String(node.classList.item(classIndex) || '');
      if (className && className.length <= maxLength && !classSet[className]) {
        classSet[className] = true;
        classes.push(className);
        if (classes.length >= maxValues) {
          break;
        }
      }
    }
  }
  return JSON.stringify({ classes: classes, ids: ids });
})();`;
  }

  parseSelectorCandidates(rawResult: string): AdBlockCosmeticSelectorCandidates {
    const raw = this.unwrapJsonString(String(rawResult ?? ''));
    try {
      const payload = JSON.parse(raw) as AdBlockCosmeticSelectorCandidates;
      return {
        classes: this.normalizeCandidateValues(payload.classes),
        ids: this.normalizeCandidateValues(payload.ids)
      };
    } catch (_error) {
      return { classes: [], ids: [] };
    }
  }

  buildInjectedScriptExecutionScript(injectedScript: string, expectedHost: string = ''): string {
    const script = injectedScript.trim();
    if (script.length <= 0) {
      return '';
    }
    const hostGuard = JSON.stringify(expectedHost.trim().toLowerCase());
    return `
;(function airaAdBlockRunRustScriptlets() {
  var expectedHost = ${hostGuard};
  if (expectedHost && String(location.hostname || '').toLowerCase() !== expectedHost) {
    return;
  }
  if (window.__airaAdBlockRustScriptletsInstalled === true) {
    return;
  }
  window.__airaAdBlockRustScriptletsInstalled = true;
${script}
})();`;
  }

  buildClearScript(): string {
    return `
;(function airaAdBlockCosmeticClear() {
  var style = document.getElementById('aira-adblock-cosmetic-style');
  if (style && style.parentNode) {
    try { style.parentNode.removeChild(style); } catch (error) {}
  }
${this.buildRuntimeCleanupScript()}
  return '1';
})();`;
  }

  buildInjectionScript(rules: AdBlockCosmeticExecutionRule[], cssSelectors: string[], pageUrl: string): string {
    if (rules.length === 0) {
      return this.buildCssOnlyInjectionScript(cssSelectors);
    }
    const payloadRules = rules.map((rule: AdBlockCosmeticExecutionRule): AdBlockCosmeticRuntimeRulePayload => {
      return {
        selector: rule.selector,
        action: rule.action,
        style: rule.value,
        procedural: rule.procedural
      };
    });
    const ruleList = JSON.stringify(payloadRules);
    const cssSelectorList = JSON.stringify(cssSelectors);
    const pageUrlValue = JSON.stringify(pageUrl);
    return `
;(function airaAdBlockCosmeticInject() {
  var rules = ${ruleList};
  var cssSelectors = ${cssSelectorList};
  var runtimeSelectors = rules.filter(function(rule) {
    return rule.action === 'hide' && rule.procedural !== true;
  }).map(function(rule) { return String(rule.selector || ''); }).filter(function(selector) {
    return selector.length > 0;
  });
  var simpleIdHideSet = {};
  runtimeSelectors.forEach(function(selector) {
    var match = /^#([A-Za-z_][A-Za-z0-9_-]*)$/.exec(String(selector || '').trim());
    if (match) {
      simpleIdHideSet[match[1]] = true;
    }
  });
  var pageUrl = ${pageUrlValue};
  var maxNodesPerPass = ${MAX_COSMETIC_NODES_PER_PASS};
  var maxMutationRootsPerPass = ${MAX_COSMETIC_MUTATION_ROOTS_PER_PASS};
  var debounceMs = ${COSMETIC_OBSERVER_DEBOUNCE_MS};
  var selectorQueryBatchSize = ${COSMETIC_SELECTOR_QUERY_BATCH_SIZE};
  if (!Array.isArray(rules) || !Array.isArray(cssSelectors) ||
    (rules.length <= 0 && cssSelectors.length <= 0) || !document.documentElement) {
    return '{"hiddenCount":0,"hiddenElementCount":0,"placeholderCollapsedCount":0,"totalActionCount":0,"selectorCount":0}';
  }

  var styleId = 'aira-adblock-cosmetic-style';
  var hiddenMarker = 'data-aira-adblock-hidden';
${this.buildRuntimeCleanupScript()}
  runtime = {
    observer: null,
    timer: 0,
    pageUrl: pageUrl,
    rules: rules.slice(0),
    selectors: runtimeSelectors.slice(0),
    hiddenClickRects: [],
    guardListener: null,
    listenerTypes: [],
    scopeSequence: 0,
    pendingRoots: [],
    fullDocumentPending: false,
    documentRulesPending: false,
    continuation: null,
    mutatedNodes: [],
    mutationRecords: typeof WeakMap === 'function' ? new WeakMap() : null,
    resultNodeSets: typeof WeakMap === 'function' && typeof Set === 'function' ? new WeakMap() : null,
    markedNodes: [],
    restore: null
  };
  window[runtimeKey] = runtime;
  var maxHiddenClickRects = 120;
  var parseCssLength = function(value, axisSize) {
    var raw = String(value || '').trim().toLowerCase();
    if (raw.length <= 0 || raw === 'auto') {
      return NaN;
    }
    var numeric = parseFloat(raw);
    if (!isFinite(numeric)) {
      return NaN;
    }
    if (raw.indexOf('vw') >= 0) {
      return window.innerWidth * numeric / 100;
    }
    if (raw.indexOf('vh') >= 0) {
      return window.innerHeight * numeric / 100;
    }
    if (raw.indexOf('%') >= 0) {
      return axisSize * numeric / 100;
    }
    return numeric;
  };
  var resolveHiddenClickRect = function(node, style) {
    var rect = node.getBoundingClientRect();
    var viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
    var viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
    var width = rect && rect.width >= 4 ? rect.width : parseCssLength(style.width, viewportWidth);
    var height = rect && rect.height >= 4 ? rect.height : parseCssLength(style.height, viewportHeight);
    if (!isFinite(width) || !isFinite(height) || width < 4 || height < 4) {
      return null;
    }
    var left = rect && rect.width >= 4 ? rect.left : parseCssLength(style.left, viewportWidth);
    if (!isFinite(left)) {
      var right = parseCssLength(style.right, viewportWidth);
      left = isFinite(right) ? viewportWidth - right - width : 0;
    }
    var top = rect && rect.height >= 4 ? rect.top : parseCssLength(style.top, viewportHeight);
    if (!isFinite(top)) {
      var bottom = parseCssLength(style.bottom, viewportHeight);
      top = isFinite(bottom) ? viewportHeight - bottom - height : 0;
    }
    return {
      left: Math.max(0, left),
      top: Math.max(0, top),
      right: Math.min(viewportWidth, left + width),
      bottom: Math.min(viewportHeight, top + height)
    };
  };
  var appendHiddenClickRect = function(rect, anchor) {
    if (!rect || runtime.hiddenClickRects.length >= maxHiddenClickRects) {
      return;
    }
    if (rect.right - rect.left < 4 || rect.bottom - rect.top < 4) {
      return;
    }
    for (var index = 0; index < runtime.hiddenClickRects.length; index += 1) {
      var existing = runtime.hiddenClickRects[index];
      if (Math.abs(existing.left - rect.left) < 1 &&
        Math.abs(existing.top - rect.top) < 1 &&
        Math.abs(existing.right - rect.right) < 1 &&
        Math.abs(existing.bottom - rect.bottom) < 1) {
        if (!existing.anchor && anchor) {
          existing.anchor = anchor;
        }
        return;
      }
    }
    var zone = {
      left: rect.left,
      top: rect.top,
      right: rect.right,
      bottom: rect.bottom,
      anchor: anchor || null,
      offsetLeft: 0,
      offsetTop: 0,
      offsetRight: rect.right - rect.left,
      offsetBottom: rect.bottom - rect.top
    };
    if (anchor && typeof anchor.getBoundingClientRect === 'function') {
      try {
        var anchorRect = anchor.getBoundingClientRect();
        zone.offsetLeft = rect.left - anchorRect.left;
        zone.offsetTop = rect.top - anchorRect.top;
        zone.offsetRight = rect.right - anchorRect.left;
        zone.offsetBottom = rect.bottom - anchorRect.top;
      } catch (error) {}
    }
    runtime.hiddenClickRects.push(zone);
  };
  var resolveRetainedSlotAnchor = function(node, nodeRect) {
    try {
      if (!nodeRect || nodeRect.right - nodeRect.left < 4 || nodeRect.bottom - nodeRect.top < 4) {
        return null;
      }
      var anchor = node && node.parentElement;
      if (!anchor || anchor === document.body || anchor === document.documentElement ||
        typeof anchor.getBoundingClientRect !== 'function') {
        return null;
      }
      var rect = anchor.getBoundingClientRect();
      if (!rect || rect.width < 4 || rect.height < 4) {
        return null;
      }
      var overlapWidth = Math.max(0, Math.min(rect.right, nodeRect.right) - Math.max(rect.left, nodeRect.left));
      var overlapHeight = Math.max(0, Math.min(rect.bottom, nodeRect.bottom) - Math.max(rect.top, nodeRect.top));
      var nodeArea = (nodeRect.right - nodeRect.left) * (nodeRect.bottom - nodeRect.top);
      var anchorArea = rect.width * rect.height;
      if (overlapWidth * overlapHeight < nodeArea * 0.5 || anchorArea > nodeArea * 8) {
        return null;
      }
      return anchor;
    } catch (error) {
      return null;
    }
  };
  var rememberRuleFilteredClickRect = function(node) {
    try {
      if (!node || !node.getBoundingClientRect || !window.getComputedStyle) {
        return;
      }
      var style = window.getComputedStyle(node);
      var opacity = parseFloat(style.opacity || '1');
      var rect = resolveHiddenClickRect(node, style);
      var retainedSlotAnchor = resolveRetainedSlotAnchor(node, rect);
      if (retainedSlotAnchor) {
        appendHiddenClickRect(rect, retainedSlotAnchor);
      }
      if (style.position === 'fixed' && isFinite(opacity) && opacity <= 0.05) {
        appendHiddenClickRect(rect, null);
      }
    } catch (error) {}
  };
  var appendUniqueNode = function(nodes, node) {
    if (!node) {
      return;
    }
    if (runtime.resultNodeSets) {
      var nodeSet = runtime.resultNodeSets.get(nodes);
      if (!nodeSet) {
        nodeSet = new Set();
        runtime.resultNodeSets.set(nodes, nodeSet);
      }
      if (nodeSet.has(node)) {
        return;
      }
      nodeSet.add(node);
      nodes.push(node);
      return;
    }
    if (nodes.indexOf(node) < 0) {
      nodes.push(node);
    }
  };
  var isQuoteStart = function(value, index) {
    if (index <= 0) {
      return true;
    }
    var previous = value.charAt(index - 1);
    return previous === '(' || previous === '[' || previous === '{' || previous === '=' || previous === ',' ||
      /\\s/.test(previous);
  };
  var findClosingParenthesis = function(value, openIndex) {
    var depth = 0;
    var quote = '';
    var escaped = false;
    for (var index = openIndex; index < value.length; index += 1) {
      var character = value.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if ((character === '"' || character === "'") && isQuoteStart(value, index)) {
        quote = character;
      } else if (character === '(') {
        depth += 1;
      } else if (character === ')') {
        depth -= 1;
        if (depth === 0) {
          return index;
        }
      }
    }
    return -1;
  };
  var needsDocumentScope = function(rawSelector) {
    var value = String(rawSelector || '').toLowerCase();
    if (value.indexOf(':has(') >= 0) {
      return true;
    }
    var bracketDepth = 0;
    var quote = '';
    var escaped = false;
    for (var index = 0; index < value.length; index += 1) {
      var character = value.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '[') {
        bracketDepth += 1;
        continue;
      }
      if (character === ']') {
        bracketDepth = Math.max(0, bracketDepth - 1);
        continue;
      }
      if (bracketDepth > 0) {
        continue;
      }
      if (character === '+' || character === '~') {
        return true;
      }
    }
    return [
      ':empty',
      ':first-child',
      ':last-child',
      ':only-child',
      ':nth-child(',
      ':nth-last-child(',
      ':first-of-type',
      ':last-of-type',
      ':only-of-type',
      ':nth-of-type(',
      ':nth-last-of-type(',
      ':invalid',
      ':valid',
      ':user-invalid',
      ':user-valid',
      ':focus-within',
      ':root',
      ':scope'
    ].some(function(marker) { return value.indexOf(marker) >= 0; });
  };
  var actionSteps = [];
  var documentScopedRuleCount = 0;
  rules.forEach(function(rule) {
    var ordinaryHide = rule && rule.action === 'hide' && rule.procedural !== true;
    var documentScoped = rule && (rule.procedural === true || needsDocumentScope(rule.selector));
    if (ordinaryHide && !documentScoped) {
      var previousStep = actionSteps.length > 0 ? actionSteps[actionSteps.length - 1] : null;
      if (previousStep && previousStep.kind === 'selectors') {
        previousStep.selectors.push(String(rule.selector || ''));
      } else {
        actionSteps.push({
          kind: 'selectors',
          selectors: [String(rule.selector || '')],
          rule: null,
          documentScoped: false
        });
      }
      return;
    }
    if (documentScoped) {
      documentScopedRuleCount += 1;
    }
    actionSteps.push({
      kind: 'rule',
      selectors: [],
      rule: rule,
      documentScoped: documentScoped
    });
  });
  var hasExtendedMarker = function(value) {
    return value.indexOf(':contains(') >= 0 || value.indexOf(':matches-css(') >= 0 ||
      value.indexOf(':matches-attr(') >= 0 || value.indexOf(':matches-path(') >= 0 ||
      value.indexOf(':upward(') >= 0 || value.indexOf(':xpath(') >= 0 ||
      value.indexOf(':watch-attr(') >= 0 || value.indexOf(':min-text-length(') >= 0;
  };
  var findExtendedPseudo = function(value) {
    var bracketDepth = 0;
    var parenthesisDepth = 0;
    var quote = '';
    var escaped = false;
    for (var index = 0; index < value.length; index += 1) {
      var character = value.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if ((character === '"' || character === "'") && isQuoteStart(value, index)) {
        quote = character;
        continue;
      }
      if (character === '[') {
        bracketDepth += 1;
        continue;
      }
      if (character === ']') {
        bracketDepth = Math.max(0, bracketDepth - 1);
        continue;
      }
      if (bracketDepth > 0) {
        continue;
      }
      if (parenthesisDepth === 0 && character === ':') {
        var names = [
          'contains', 'matches-css', 'matches-attr', 'matches-path', 'min-text-length',
          'upward', 'xpath', 'watch-attr', 'has'
        ];
        for (var nameIndex = 0; nameIndex < names.length; nameIndex += 1) {
          var name = names[nameIndex];
          var marker = ':' + name + '(';
          if (value.slice(index, index + marker.length) !== marker) {
            continue;
          }
          var openIndex = index + marker.length - 1;
          var closeIndex = findClosingParenthesis(value, openIndex);
          if (closeIndex < 0) {
            return null;
          }
          var argument = value.slice(openIndex + 1, closeIndex);
          if (name !== 'has' || hasExtendedMarker(argument)) {
            return {
              name: name,
              start: index,
              end: closeIndex + 1,
              argument: argument
            };
          }
          index = closeIndex;
          break;
        }
        continue;
      }
      if (character === '(') {
        parenthesisDepth += 1;
      } else if (character === ')') {
        parenthesisDepth = Math.max(0, parenthesisDepth - 1);
      }
    }
    return null;
  };
  var toValueMatcher = function(rawValue) {
    var raw = String(rawValue || '').trim();
    if (raw.length >= 2 && ((raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') ||
      (raw.charAt(0) === "'" && raw.charAt(raw.length - 1) === "'"))) {
      raw = raw.slice(1, -1);
    }
    if (raw.startsWith('/') && raw.lastIndexOf('/') > 0) {
      var lastSlash = raw.lastIndexOf('/');
      try {
        var expression = new RegExp(raw.slice(1, lastSlash), raw.slice(lastSlash + 1).replace(/[gy]/g, ''));
        return function(value) { expression.lastIndex = 0; return expression.test(String(value || '')); };
      } catch (error) {}
    }
    return function(value) { return String(value || '').indexOf(raw) >= 0; };
  };
  var splitAttributeMatcher = function(rawValue) {
    var raw = String(rawValue || '').trim();
    var quote = '';
    var regex = false;
    var escaped = false;
    for (var index = 0; index < raw.length; index += 1) {
      var character = raw.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character === '\\\\') {
        escaped = true;
        continue;
      }
      if (quote) {
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        continue;
      }
      if (character === '/') {
        regex = !regex;
        continue;
      }
      if (character === '=' && !regex) {
        return [raw.slice(0, index).trim(), raw.slice(index + 1).trim()];
      }
    }
    return [raw, ''];
  };
  var appendQueryMatches = function(root, selector, results, maximumResultCount, skipMarkedNodes) {
    var normalized = String(selector || '').trim();
    if (!root || !normalized) {
      return;
    }
    var relative = normalized.charAt(0) === '>' || normalized.charAt(0) === '+' || normalized.charAt(0) === '~';
    if (relative) {
      normalized = ':scope ' + normalized;
    }
    if (!relative && root.nodeType === 1 && typeof root.matches === 'function' && root.matches(normalized) &&
      (!skipMarkedNodes || !root.hasAttribute(hiddenMarker))) {
      appendUniqueNode(results, root);
    }
    if (maximumResultCount > 0 && results.length >= maximumResultCount) {
      return;
    }
    var nodes = root.querySelectorAll(normalized);
    for (var index = 0; index < nodes.length; index += 1) {
      if (skipMarkedNodes && nodes[index].hasAttribute && nodes[index].hasAttribute(hiddenMarker)) {
        continue;
      }
      appendUniqueNode(results, nodes[index]);
      if (maximumResultCount > 0 && results.length >= maximumResultCount) {
        return;
      }
    }
  };
  var queryNodes = function(root, selector) {
    var results = [];
    try { appendQueryMatches(root, selector, results, 0, false); } catch (error) {}
    return results;
  };
  var querySelectorBatches = function(root, selectorValues, maximumResultCount, skipMarkedNodes) {
    var results = [];
    for (var start = 0; start < selectorValues.length; start += selectorQueryBatchSize) {
      var batch = selectorValues.slice(start, start + selectorQueryBatchSize);
      try {
        appendQueryMatches(root, batch.join(','), results, maximumResultCount, skipMarkedNodes);
      } catch (error) {
        batch.forEach(function(selector) {
          if (maximumResultCount > 0 && results.length >= maximumResultCount) {
            return;
          }
          try {
            appendQueryMatches(root, selector, results, maximumResultCount, skipMarkedNodes);
          } catch (innerError) {}
        });
      }
      if (maximumResultCount > 0 && results.length >= maximumResultCount) {
        break;
      }
    }
    return results;
  };
  var filterBySuffix;
  var selectExtended;
  var applyExtendedDescriptor;
  var queryRelativeNodes = function(nodes, cssSuffix) {
    var results = [];
    var rawSuffix = String(cssSuffix || '');
    var trimmed = rawSuffix.trim();
    if (!trimmed) {
      nodes.forEach(function(node) { appendUniqueNode(results, node); });
      return results;
    }
    var first = trimmed.charAt(0);
    var relativeSuffix = (/^\\s/.test(rawSuffix) && first !== '>' && first !== '+' && first !== '~')
      ? ' ' + trimmed
      : trimmed;
    nodes.forEach(function(node) {
      if (!node || !node.setAttribute || !node.removeAttribute) {
        return;
      }
      runtime.scopeSequence += 1;
      var attributeName = 'data-aira-adblock-scope';
      var marker = 'a' + String(runtime.scopeSequence);
      var hadAttribute = false;
      var previousValue = '';
      try {
        hadAttribute = node.hasAttribute(attributeName);
        previousValue = hadAttribute ? String(node.getAttribute(attributeName) || '') : '';
        node.setAttribute(attributeName, marker);
        var owner = node.ownerDocument || document;
        var scopedSelector = '[' + attributeName + '="' + marker + '"]' + relativeSuffix;
        var matched = owner.querySelectorAll(scopedSelector);
        for (var index = 0; index < matched.length; index += 1) {
          appendUniqueNode(results, matched[index]);
        }
      } catch (error) {
      } finally {
        try {
          if (hadAttribute) {
            node.setAttribute(attributeName, previousValue);
          } else {
            node.removeAttribute(attributeName);
          }
        } catch (error) {}
      }
    });
    return results;
  };
  applyExtendedDescriptor = function(candidates, descriptor, root, depth) {
    var selected = [];
    if (descriptor.name === 'contains') {
      var textMatches = toValueMatcher(descriptor.argument);
      candidates.forEach(function(node) {
        if (textMatches(node && node.textContent)) {
          appendUniqueNode(selected, node);
        }
      });
    } else if (descriptor.name === 'matches-css') {
      var separator = descriptor.argument.indexOf(':');
      if (separator > 0) {
        var propertySpec = descriptor.argument.slice(0, separator).trim();
        var property = propertySpec;
        var pseudoElement = '';
        var comma = propertySpec.indexOf(',');
        if (comma > 0) {
          var pseudoName = propertySpec.slice(0, comma).trim().toLowerCase();
          if (pseudoName === 'before' || pseudoName === 'after') {
            pseudoElement = '::' + pseudoName;
            property = propertySpec.slice(comma + 1).trim();
          }
        }
        var cssMatches = toValueMatcher(descriptor.argument.slice(separator + 1).trim());
        candidates.forEach(function(node) {
          try {
            var style = pseudoElement
              ? window.getComputedStyle(node, pseudoElement)
              : window.getComputedStyle(node);
            if (property && cssMatches(style.getPropertyValue(property))) {
              appendUniqueNode(selected, node);
            }
          } catch (error) {}
        });
      }
    } else if (descriptor.name === 'matches-attr') {
      var attributeMatchers = splitAttributeMatcher(descriptor.argument);
      var attributeNameMatches = toValueMatcher(attributeMatchers[0]);
      var attributeValueMatches = attributeMatchers[1] ? toValueMatcher(attributeMatchers[1]) : null;
      candidates.forEach(function(node) {
        if (!node || !node.attributes) {
          return;
        }
        for (var attributeIndex = 0; attributeIndex < node.attributes.length; attributeIndex += 1) {
          var attribute = node.attributes[attributeIndex];
          if (attributeNameMatches(attribute && attribute.name) &&
            (!attributeValueMatches || attributeValueMatches(attribute && attribute.value))) {
            appendUniqueNode(selected, node);
            return;
          }
        }
      });
    } else if (descriptor.name === 'matches-path') {
      var pathMatches = toValueMatcher(descriptor.argument);
      var currentPath = '';
      try { currentPath = String(window.location.pathname || '') + String(window.location.search || ''); } catch (error) {}
      if (pathMatches(currentPath)) {
        candidates.forEach(function(node) { appendUniqueNode(selected, node); });
      }
    } else if (descriptor.name === 'min-text-length') {
      var minimumTextLength = Math.max(0, parseInt(String(descriptor.argument || ''), 10) || 0);
      candidates.forEach(function(node) {
        if (String(node && node.textContent || '').length >= minimumTextLength) {
          appendUniqueNode(selected, node);
        }
      });
    } else if (descriptor.name === 'xpath') {
      var xpathExpression = String(descriptor.argument || '').trim();
      if (xpathExpression.length >= 2 && ((xpathExpression.charAt(0) === '"' &&
        xpathExpression.charAt(xpathExpression.length - 1) === '"') ||
        (xpathExpression.charAt(0) === "'" && xpathExpression.charAt(xpathExpression.length - 1) === "'"))) {
        xpathExpression = xpathExpression.slice(1, -1);
      }
      candidates.forEach(function(node) {
        if (!node || !xpathExpression || typeof document.evaluate !== 'function') {
          return;
        }
        try {
          var snapshot = document.evaluate(xpathExpression, node, null,
            XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          for (var xpathIndex = 0; xpathIndex < snapshot.snapshotLength; xpathIndex += 1) {
            var xpathNode = snapshot.snapshotItem(xpathIndex);
            if (xpathNode && xpathNode.nodeType === 1) {
              appendUniqueNode(selected, xpathNode);
            }
          }
        } catch (error) {}
      });
    } else if (descriptor.name === 'watch-attr') {
      candidates.forEach(function(node) { appendUniqueNode(selected, node); });
    } else if (descriptor.name === 'has') {
      candidates.forEach(function(node) {
        if (selectExtended(descriptor.argument, node, depth + 1).length > 0) {
          appendUniqueNode(selected, node);
        }
      });
    } else if (descriptor.name === 'upward') {
      var upwardArgument = String(descriptor.argument || '').trim();
      var numericUpward = /^\\d+$/.test(upwardArgument);
      candidates.forEach(function(node) {
        var current = node ? node.parentElement : null;
        if (numericUpward) {
          var levels = Math.max(1, Math.min(16, parseInt(upwardArgument, 10) || 1));
          for (var level = 1; level < levels && current; level += 1) {
            current = current.parentElement;
          }
          appendUniqueNode(selected, current);
          return;
        }
        while (current) {
          try {
            if (typeof current.matches === 'function' && current.matches(upwardArgument)) {
              appendUniqueNode(selected, current);
              return;
            }
          } catch (error) {
            return;
          }
          current = current.parentElement;
        }
      });
    }
    return selected;
  };
  selectExtended = function(selector, root, depth) {
    if (depth > 12) {
      return [];
    }
    var descriptor = findExtendedPseudo(selector);
    if (!descriptor) {
      return queryNodes(root, selector);
    }
    var baseSelector = selector.slice(0, descriptor.start).trim() ||
      (descriptor.name === 'matches-path' || descriptor.name === 'xpath' ? ':root' : '*');
    var candidates = queryNodes(root, baseSelector);
    var selected = applyExtendedDescriptor(candidates, descriptor, root, depth);
    return filterBySuffix(selected, selector.slice(descriptor.end), root, depth + 1);
  };
  filterBySuffix = function(nodes, suffix, root, depth) {
    if (depth > 12 || !suffix || !String(suffix).trim()) {
      return nodes;
    }
    var rawSuffix = String(suffix);
    var descriptor = findExtendedPseudo(rawSuffix);
    if (!descriptor) {
      return queryRelativeNodes(nodes, rawSuffix);
    }
    var candidates = nodes;
    var cssPrefix = rawSuffix.slice(0, descriptor.start);
    if (cssPrefix.trim()) {
      candidates = queryRelativeNodes(nodes, cssPrefix);
    }
    var selected = applyExtendedDescriptor(candidates, descriptor, root, depth);
    return filterBySuffix(selected, rawSuffix.slice(descriptor.end), root, depth + 1);
  };
  var findMutationRecord = function(node) {
    if (!node) {
      return null;
    }
    if (runtime.mutationRecords) {
      var cachedRecord = runtime.mutationRecords.get(node);
      if (cachedRecord) {
        return cachedRecord;
      }
    } else {
      for (var recordIndex = 0; recordIndex < runtime.mutatedNodes.length; recordIndex += 1) {
        if (runtime.mutatedNodes[recordIndex].node === node) {
          return runtime.mutatedNodes[recordIndex];
        }
      }
    }
    if (runtime.mutatedNodes.length >= maxNodesPerPass * 8) {
      return null;
    }
    var record = {
      node: node,
      properties: {},
      attributes: {}
    };
    runtime.mutatedNodes.push(record);
    if (runtime.mutationRecords) {
      runtime.mutationRecords.set(node, record);
    }
    return record;
  };
  var rememberStyleProperty = function(node, property) {
    var record = findMutationRecord(node);
    if (!record || Object.prototype.hasOwnProperty.call(record.properties, property)) {
      return;
    }
    try {
      record.properties[property] = {
        value: node.style.getPropertyValue(property),
        priority: node.style.getPropertyPriority(property)
      };
    } catch (error) {}
  };
  var rememberAttribute = function(node, attributeName) {
    var record = findMutationRecord(node);
    if (!record || Object.prototype.hasOwnProperty.call(record.attributes, attributeName)) {
      return;
    }
    try {
      record.attributes[attributeName] = {
        present: node.hasAttribute(attributeName),
        value: String(node.getAttribute(attributeName) || '')
      };
    } catch (error) {}
  };
  var splitStyleDeclarations = function(styleText) {
    var declarations = [];
    var current = '';
    var depth = 0;
    var quote = '';
    var escaped = false;
    var raw = String(styleText || '');
    for (var index = 0; index < raw.length; index += 1) {
      var character = raw.charAt(index);
      if (escaped) {
        current += character;
        escaped = false;
        continue;
      }
      if (character === '\\\\') {
        current += character;
        escaped = true;
        continue;
      }
      if (quote) {
        current += character;
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if (character === '"' || character === "'") {
        current += character;
        quote = character;
      } else if (character === '(') {
        current += character;
        depth += 1;
      } else if (character === ')') {
        current += character;
        depth = Math.max(0, depth - 1);
      } else if (character === ';' && depth === 0) {
        declarations.push(current);
        current = '';
      } else {
        current += character;
      }
    }
    if (current.trim()) {
      declarations.push(current);
    }
    return declarations;
  };
  var applyStyle = function(node, styleText) {
    if (!node || !node.style || typeof node.style.setProperty !== 'function') {
      return false;
    }
    var applied = false;
    splitStyleDeclarations(styleText).forEach(function(declaration) {
      var separator = declaration.indexOf(':');
      if (separator <= 0) {
        return;
      }
      var property = declaration.slice(0, separator).trim();
      var value = declaration.slice(separator + 1).trim();
      if (!/^(?:--)?[a-z][a-z0-9-]*$/i.test(property) || !value) {
        return;
      }
      var priority = /!important\\s*$/i.test(value) ? 'important' : '';
      if (priority) {
        value = value.replace(/!important\\s*$/i, '').trim();
      }
      try {
        if (node.style.getPropertyValue(property) === value &&
          node.style.getPropertyPriority(property) === priority) {
          return;
        }
        rememberStyleProperty(node, property);
        node.style.setProperty(property, value, priority);
        applied = true;
      } catch (error) {}
    });
    return applied;
  };
  var markNodeHidden = function(node) {
    if (!node || node.nodeType !== 1) {
      return false;
    }
    var alreadyMarked = node.hasAttribute(hiddenMarker);
    if (!alreadyMarked) {
      rememberRuleFilteredClickRect(node);
      try {
        node.setAttribute(hiddenMarker, 'true');
        runtime.markedNodes.push(node);
      } catch (error) {
        return false;
      }
    }
    var styleChanged = applyStyle(node, 'display:none!important;visibility:hidden!important');
    return !alreadyMarked || styleChanged;
  };
  var enforceSimpleIdHideNode = function(node) {
    if (!node || node.nodeType !== 1 || !node.id || !simpleIdHideSet[node.id]) {
      return false;
    }
    return markNodeHidden(node);
  };
  var enforceSimpleIdHides = function(root) {
    if (!root) {
      return;
    }
    enforceSimpleIdHideNode(root);
    if (typeof root.querySelectorAll !== 'function') {
      return;
    }
    var nodes = [];
    try { nodes = root.querySelectorAll('[id]'); } catch (error) { return; }
    for (var index = 0; index < nodes.length; index += 1) {
      enforceSimpleIdHideNode(nodes[index]);
    }
  };
  runtime.restore = function() {
    for (var recordIndex = runtime.mutatedNodes.length - 1; recordIndex >= 0; recordIndex -= 1) {
      var record = runtime.mutatedNodes[recordIndex];
      if (!record || !record.node || !record.node.style) {
        continue;
      }
      Object.keys(record.properties).forEach(function(property) {
        var original = record.properties[property];
        try {
          if (!original || !original.value) {
            record.node.style.removeProperty(property);
          } else {
            record.node.style.setProperty(property, original.value, original.priority || '');
          }
        } catch (error) {}
      });
      Object.keys(record.attributes || {}).forEach(function(attributeName) {
        var originalAttribute = record.attributes[attributeName];
        try {
          if (originalAttribute && originalAttribute.present) {
            record.node.setAttribute(attributeName, originalAttribute.value);
          } else {
            record.node.removeAttribute(attributeName);
          }
        } catch (error) {}
      });
    }
    runtime.markedNodes.forEach(function(node) {
      try { node.removeAttribute(hiddenMarker); } catch (error) {}
    });
    runtime.mutatedNodes = [];
    runtime.markedNodes = [];
  };
  var visitQueryMatches = function(root, selector, visitor) {
    var normalized = String(selector || '').trim();
    if (!root || !normalized) {
      return true;
    }
    var relative = normalized.charAt(0) === '>' || normalized.charAt(0) === '+' || normalized.charAt(0) === '~';
    if (relative) {
      normalized = ':scope ' + normalized;
    }
    if (!relative && root.nodeType === 1 && typeof root.matches === 'function' && root.matches(normalized) &&
      visitor(root) === false) {
      return false;
    }
    var nodes = root.querySelectorAll(normalized);
    for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex += 1) {
      if (visitor(nodes[nodeIndex]) === false) {
        return false;
      }
    }
    return true;
  };
  var scanHiddenClickRects = function(root) {
    for (var selectorIndex = 0; selectorIndex < runtimeSelectors.length; selectorIndex += 1) {
      try {
        var completed = visitQueryMatches(root, runtimeSelectors[selectorIndex], function(node) {
          rememberRuleFilteredClickRect(node);
          return runtime.hiddenClickRects.length < maxHiddenClickRects;
        });
        if (!completed || runtime.hiddenClickRects.length >= maxHiddenClickRects) {
          return;
        }
      } catch (error) {}
    }
  };
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
  var shouldGuardHiddenClickRect = function(event) {
    var point = eventPoint(event);
    if (typeof point.x !== 'number' || typeof point.y !== 'number' || point.x < 0 || point.y < 0) {
      return false;
    }
    for (var index = 0; index < runtime.hiddenClickRects.length; index += 1) {
      var rect = runtime.hiddenClickRects[index];
      if (rect && rect.anchor && typeof rect.anchor.getBoundingClientRect === 'function') {
        try {
          if (rect.anchor.isConnected === false) {
            continue;
          }
          var anchorRect = rect.anchor.getBoundingClientRect();
          if (!anchorRect || anchorRect.width < 4 || anchorRect.height < 4) {
            continue;
          }
          rect = {
            left: Math.max(anchorRect.left, anchorRect.left + Number(rect.offsetLeft || 0)),
            top: Math.max(anchorRect.top, anchorRect.top + Number(rect.offsetTop || 0)),
            right: Math.min(anchorRect.right, anchorRect.left + Number(rect.offsetRight || anchorRect.width)),
            bottom: Math.min(anchorRect.bottom, anchorRect.top + Number(rect.offsetBottom || anchorRect.height))
          };
        } catch (error) {
          continue;
        }
      }
      if (point.x >= rect.left && point.x <= rect.right && point.y >= rect.top && point.y <= rect.bottom) {
        return true;
      }
    }
    return false;
  };
  var guardHiddenClickEvent = function(event) {
    if (!shouldGuardHiddenClickRect(event)) {
      return;
    }
    var point = eventPoint(event);
    try { event.preventDefault(); } catch (error) {}
    try { event.stopImmediatePropagation(); } catch (error) {}
    try { event.stopPropagation(); } catch (error) {}
    try {
      var bridge = window.__airaAdBlockNativeBridge;
      if (bridge && typeof bridge.onCosmeticHidden === 'function') {
        bridge.onCosmeticHidden(JSON.stringify({
          count: 0,
          hiddenElementCount: 0,
          placeholderCollapsedCount: 0,
          hiddenClickRectCount: runtime.hiddenClickRects.length,
          pageUrl: pageUrl,
          phase: 'guarded_' + String(event && event.type ? event.type : 'event'),
          eventX: point.x,
          eventY: point.y
        }));
      }
    } catch (error) {}
  };
  var addGuardedListener = function(type) {
    try {
      document.addEventListener(type, guardHiddenClickEvent, {
        capture: true,
        passive: false
      });
      runtime.listenerTypes.push(type);
    } catch (error) {
      try {
        document.addEventListener(type, guardHiddenClickEvent, true);
        runtime.listenerTypes.push(type);
      } catch (innerError) {}
    }
  };
  runtime.guardListener = guardHiddenClickEvent;
  addGuardedListener('touchstart');
  addGuardedListener('touchend');
  addGuardedListener('click');
  var style = document.getElementById(styleId);
  if (style) {
    style.textContent = '';
  }
  scanHiddenClickRects(document);
  var css = cssSelectors.map(function(selector) {
    return selector + '{display:none!important;visibility:hidden!important;}';
  }).join('\\n');
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    style.setAttribute('data-aira-adblock', 'cosmetic');
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = css;
  var applyRuleToNode = function(rule, node, result, budget) {
    if (!node || node.nodeType !== 1) {
      return;
    }
    if (rule.action === 'remove') {
      try {
        if (node.parentNode) {
          rememberRuleFilteredClickRect(node);
          node.parentNode.removeChild(node);
          result.removedElementCount += 1;
          result.totalActionCount += 1;
          budget.remaining -= 1;
        }
      } catch (error) {}
    } else if (rule.action === 'style') {
      if (applyStyle(node, rule.style)) {
        result.styledElementCount += 1;
        result.totalActionCount += 1;
        budget.remaining -= 1;
      }
    } else if (rule.action === 'remove-attr') {
      var attributeName = String(rule.style || '').trim();
      if (/^[A-Za-z_:][A-Za-z0-9_.:-]*$/.test(attributeName)) {
        try {
          if (node.hasAttribute(attributeName)) {
            rememberAttribute(node, attributeName);
            node.removeAttribute(attributeName);
            result.styledElementCount += 1;
            result.totalActionCount += 1;
            budget.remaining -= 1;
          }
        } catch (error) {}
      }
    } else if (rule.action === 'remove-class') {
      var rawClassSpec = String(rule.style || '').trim();
      var classNames = rawClassSpec.split(/\\s+/).filter(function(value) { return value.length > 0; });
      var classNameMatcher = rawClassSpec.startsWith('/') && rawClassSpec.lastIndexOf('/') > 0
        ? toValueMatcher(rawClassSpec)
        : null;
      var removedClass = false;
      var candidateClassNames = [];
      try {
        for (var classIndex = 0; node.classList && classIndex < node.classList.length; classIndex += 1) {
          candidateClassNames.push(node.classList.item(classIndex));
        }
      } catch (error) {}
      (classNameMatcher ? candidateClassNames : classNames).forEach(function(className) {
        try {
          if (node.classList && className && node.classList.contains(className) &&
            (!classNameMatcher || classNameMatcher(className))) {
            rememberAttribute(node, 'class');
            node.classList.remove(className);
            removedClass = true;
          }
        } catch (error) {}
      });
      if (removedClass) {
        result.styledElementCount += 1;
        result.totalActionCount += 1;
        budget.remaining -= 1;
      }
    } else if (markNodeHidden(node)) {
      result.hiddenElementCount += 1;
      result.totalActionCount += 1;
      budget.remaining -= 1;
    }
  };
  var runActionPass = function(roots, runDocumentRules, budget, startStepIndex) {
    var result = {
      hiddenElementCount: 0,
      removedElementCount: 0,
      styledElementCount: 0,
      totalActionCount: 0,
      budgetExhausted: false,
      resumeStepIndex: Math.max(0, startStepIndex || 0)
    };
    for (var stepIndex = result.resumeStepIndex; stepIndex < actionSteps.length; stepIndex += 1) {
      var step = actionSteps[stepIndex];
      if (step.kind === 'selectors') {
        for (var selectorRootIndex = 0; selectorRootIndex < roots.length; selectorRootIndex += 1) {
          var selectorNodes = querySelectorBatches(
            roots[selectorRootIndex],
            step.selectors,
            0,
            false
          );
          for (var selectorNodeIndex = 0; selectorNodeIndex < selectorNodes.length; selectorNodeIndex += 1) {
            if (budget.remaining <= 0) {
              result.budgetExhausted = true;
              result.resumeStepIndex = stepIndex;
              return result;
            }
            if (markNodeHidden(selectorNodes[selectorNodeIndex])) {
              result.hiddenElementCount += 1;
              result.totalActionCount += 1;
              budget.remaining -= 1;
            }
          }
        }
        continue;
      }
      if (step.documentScoped && !runDocumentRules) {
        continue;
      }
      var rule = step.rule;
      var ruleRoots = step.documentScoped ? [document] : roots;
      for (var rootIndex = 0; rootIndex < ruleRoots.length; rootIndex += 1) {
        if (rule && rule.procedural !== true) {
          var nonProceduralOverflow = false;
          try {
            visitQueryMatches(ruleRoots[rootIndex], rule.selector, function(node) {
              if (budget.remaining <= 0) {
                nonProceduralOverflow = true;
                return false;
              }
              applyRuleToNode(rule, node, result, budget);
              return true;
            });
          } catch (error) {}
          if (nonProceduralOverflow) {
            result.budgetExhausted = true;
            result.resumeStepIndex = stepIndex;
            return result;
          }
          continue;
        }
        var nodes = selectExtended(rule.selector, ruleRoots[rootIndex], 0);
        for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex += 1) {
          if (budget.remaining <= 0) {
            result.budgetExhausted = true;
            result.resumeStepIndex = stepIndex;
            return result;
          }
          applyRuleToNode(rule, nodes[nodeIndex], result, budget);
        }
      }
    }
    return result;
  };
  var reportActions = function(result, phase) {
    if (!result || result.totalActionCount <= 0) {
      return;
    }
    try {
      var bridge = window.__airaAdBlockNativeBridge;
      if (bridge && typeof bridge.onCosmeticHidden === 'function') {
        bridge.onCosmeticHidden(JSON.stringify({
          count: result.totalActionCount,
          hiddenElementCount: result.hiddenElementCount,
          removedElementCount: result.removedElementCount,
          styledElementCount: result.styledElementCount,
          totalActionCount: result.totalActionCount,
          placeholderCollapsedCount: 0,
          pageUrl: pageUrl,
          phase: phase
        }));
      }
    } catch (error) {}
  };
  var initialBudget = { remaining: maxNodesPerPass };
  var initialRoots = [document];
  enforceSimpleIdHides(document);
  var initialResult = runActionPass(initialRoots, true, initialBudget, 0);
  var appendPendingRoot = function(node) {
    if (!node || node.nodeType !== 1 || node.isConnected === false) {
      return;
    }
    if (runtime.fullDocumentPending) {
      return;
    }
    if (node === document.documentElement) {
      runtime.pendingRoots.splice(0, runtime.pendingRoots.length);
      runtime.fullDocumentPending = true;
      return;
    }
    for (var index = runtime.pendingRoots.length - 1; index >= 0; index -= 1) {
      var existing = runtime.pendingRoots[index];
      try {
        if (existing === node || existing.contains(node)) {
          return;
        }
        if (node.contains(existing)) {
          runtime.pendingRoots.splice(index, 1);
        }
      } catch (error) {}
    }
    runtime.pendingRoots.push(node);
    if (runtime.pendingRoots.length > maxMutationRootsPerPass) {
      runtime.pendingRoots.splice(0, runtime.pendingRoots.length);
      runtime.fullDocumentPending = true;
    }
  };
  var collectMutationWork = function(records) {
    records.forEach(function(record) {
      if (record.type === 'attributes') {
        var attributeTarget = record.target;
        var attributeRoot = attributeTarget && attributeTarget.parentElement
          ? attributeTarget.parentElement
          : attributeTarget;
        appendPendingRoot(attributeRoot);
        if (documentScopedRuleCount > 0) {
          runtime.documentRulesPending = true;
        }
        return;
      }
      if (record.type !== 'childList') {
        return;
      }
      var childListTarget = record.target;
      if (childListTarget && childListTarget.nodeType === 1) {
        appendPendingRoot(childListTarget);
      } else if (childListTarget && childListTarget.nodeType === 9) {
        appendPendingRoot(childListTarget.documentElement);
      }
      if (documentScopedRuleCount > 0) {
        runtime.documentRulesPending = true;
      }
    });
  };
  var schedulePendingPass;
  var runPendingPass = function() {
    runtime.timer = 0;
    var continuation = runtime.continuation;
    runtime.continuation = null;
    var roots = continuation
      ? continuation.roots
      : (runtime.fullDocumentPending ? [document] : runtime.pendingRoots.slice(0));
    var runDocumentRules = continuation ? continuation.runDocumentRules : runtime.documentRulesPending;
    var startStepIndex = continuation ? continuation.startStepIndex : 0;
    if (!continuation) {
      runtime.pendingRoots.splice(0, runtime.pendingRoots.length);
      runtime.fullDocumentPending = false;
      runtime.documentRulesPending = false;
    }
    if (roots.length <= 0 && runDocumentRules) {
      roots = [document];
    } else if (roots.length <= 0) {
      return;
    }
    var budget = { remaining: maxNodesPerPass };
    var result = runActionPass(roots, runDocumentRules, budget, startStepIndex);
    if (runtime.observer && typeof runtime.observer.takeRecords === 'function') {
      try { runtime.observer.takeRecords(); } catch (error) {}
    }
    reportActions(result, 'mutation');
    if (result.budgetExhausted) {
      runtime.continuation = {
        roots: roots,
        runDocumentRules: runDocumentRules,
        startStepIndex: result.resumeStepIndex
      };
    }
    if (runtime.continuation || runtime.pendingRoots.length > 0 || runtime.fullDocumentPending ||
      runtime.documentRulesPending) {
      schedulePendingPass();
    }
  };
  schedulePendingPass = function() {
    if (runtime.timer) {
      return;
    }
    runtime.timer = setTimeout(runPendingPass, debounceMs);
  };
  if (typeof MutationObserver === 'function') {
    runtime.observer = new MutationObserver(function(records) {
      records.forEach(function(record) {
        if (record.type === 'attributes') {
          enforceSimpleIdHideNode(record.target);
          return;
        }
        if (record.type === 'childList') {
          for (var nodeIndex = 0; nodeIndex < record.addedNodes.length; nodeIndex += 1) {
            enforceSimpleIdHides(record.addedNodes[nodeIndex]);
          }
        }
      });
      collectMutationWork(records);
      if (runtime.continuation || runtime.pendingRoots.length > 0 || runtime.fullDocumentPending ||
        runtime.documentRulesPending) {
        schedulePendingPass();
      }
    });
    try {
      var observeOptions = {
        childList: true,
        subtree: true,
        attributes: true
      };
      var watchesArbitraryAttributes = rules.some(function(rule) {
        return String(rule && rule.selector || '').indexOf(':matches-attr(') >= 0;
      });
      if (!watchesArbitraryAttributes) {
        observeOptions.attributeFilter = [
          'class',
          'id',
          'style'
        ];
      }
      runtime.observer.observe(document.documentElement, observeOptions);
    } catch (error) {}
  }
  if (initialResult.budgetExhausted) {
    runtime.continuation = {
      roots: initialRoots,
      runDocumentRules: true,
      startStepIndex: initialResult.resumeStepIndex
    };
    schedulePendingPass();
  }
  return JSON.stringify({
    hiddenCount: initialResult.hiddenElementCount,
    hiddenElementCount: initialResult.hiddenElementCount,
    removedElementCount: initialResult.removedElementCount,
    styledElementCount: initialResult.styledElementCount,
    totalActionCount: initialResult.totalActionCount,
    placeholderCollapsedCount: 0,
    hiddenClickRectCount: runtime.hiddenClickRects.length,
    guardListenerCount: runtime.listenerTypes.length,
    selectorCount: cssSelectors.length
  });
})();`;
  }

  private buildCssOnlyInjectionScript(cssSelectors: string[]): string {
    const cssSelectorList = JSON.stringify(cssSelectors);
    return `
;(function airaAdBlockCssOnlyInject() {
${this.buildRuntimeCleanupScript()}
  var selectors = ${cssSelectorList};
  var styleId = 'aira-adblock-cosmetic-style';
  var style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    style.setAttribute('data-aira-adblock', 'cosmetic');
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = selectors.map(function(selector) {
    return selector + '{display:none!important;visibility:hidden!important;}';
  }).join('\\n');
  return JSON.stringify({
    hiddenCount: 0,
    hiddenElementCount: 0,
    removedElementCount: 0,
    styledElementCount: 0,
    totalActionCount: 0,
    placeholderCollapsedCount: 0,
    hiddenClickRectCount: 0,
    guardListenerCount: 0,
    selectorCount: selectors.length
  });
})();`;
  }

  private buildRuntimeCleanupScript(): string {
    return `  var runtimeKey = '__airaAdBlockCosmeticRuntime';
  var runtime = window[runtimeKey];
  if (runtime && runtime.observer && typeof runtime.observer.disconnect === 'function') {
    try { runtime.observer.disconnect(); } catch (error) {}
  }
  if (runtime && runtime.timer) {
    try { clearTimeout(runtime.timer); } catch (error) {}
  }
  if (runtime && runtime.guardListener && Array.isArray(runtime.listenerTypes)) {
    runtime.listenerTypes.forEach(function(type) {
      try { document.removeEventListener(type, runtime.guardListener, true); } catch (error) {}
    });
  }
  if (runtime && typeof runtime.restore === 'function') {
    try { runtime.restore(); } catch (error) {}
  }
  try { window[runtimeKey] = null; } catch (error) {}`;
  }

  parseRuntimeResult(rawResult: string): AdBlockCosmeticRuntimeScriptResult {
    const raw = this.unwrapJsonString(String(rawResult ?? ''));
    if (raw.length <= 0) {
      return this.emptyRuntimeResult();
    }
    try {
      const payload = JSON.parse(raw) as Record<string, number>;
      const hiddenElementCount = this.normalizeCount(Number(payload.hiddenElementCount ?? payload.hiddenCount ?? 0));
      const totalActionCount = this.normalizeCount(Number(payload.totalActionCount ?? hiddenElementCount));
      return {
        selectorCount: this.normalizeCount(Number(payload.selectorCount ?? 0)),
        hiddenElementCount: hiddenElementCount,
        placeholderCollapsedCount: 0,
        totalActionCount: totalActionCount,
        hiddenClickRectCount: this.normalizeCount(Number(payload.hiddenClickRectCount ?? 0)),
        guardListenerCount: this.normalizeCount(Number(payload.guardListenerCount ?? 0))
      };
    } catch (_error) {
      const count = this.normalizeCount(Number(raw));
      return {
        selectorCount: 0,
        hiddenElementCount: count,
        placeholderCollapsedCount: 0,
        totalActionCount: count,
        hiddenClickRectCount: 0,
        guardListenerCount: 0
      };
    }
  }

  parseHiddenElementCount(rawResult: string): number {
    return this.parseRuntimeResult(rawResult).totalActionCount;
  }

  private unwrapJsonString(raw: string): string {
    if (raw.length >= 2 && raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') {
      try {
        const decoded = JSON.parse(raw) as string;
        if (typeof decoded === 'string') {
          return decoded;
        }
      } catch (_error) {
      }
    }
    return raw;
  }

  private normalizeCount(value: number): number {
    return typeof value === 'number' && !Number.isNaN(value) && value > 0 ? Math.floor(value) : 0;
  }

  private normalizeCandidateValues(values: string[]): string[] {
    if (!Array.isArray(values)) {
      return [];
    }
    const results: string[] = [];
    values.some((value: string): boolean => {
      const normalized = String(value ?? '').trim();
      if (normalized.length > 0 && normalized.length <= 256 && !results.includes(normalized)) {
        results.push(normalized);
      }
      return results.length >= 8192;
    });
    return results;
  }

  private emptyRuntimeResult(): AdBlockCosmeticRuntimeScriptResult {
    return {
      selectorCount: 0,
      hiddenElementCount: 0,
      placeholderCollapsedCount: 0,
      totalActionCount: 0,
      hiddenClickRectCount: 0,
      guardListenerCount: 0
    };
  }
}
