import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import {
  TRANSLATION_RUNTIME_NAME,
  TRANSLATION_RUNTIME_VERSION,
  WebpageTranslationRuntimeProtocolScriptService
} from './WebpageTranslationRuntimeProtocolScriptService';
import { WEBPAGE_TRANSLATION_SITE_RULES_JSON } from './WebpageTranslationSiteRuleCatalog';

export class WebpageTranslationRuntimeScriptService {
  private protocolScriptService: WebpageTranslationRuntimeProtocolScriptService =
    new WebpageTranslationRuntimeProtocolScriptService();

  buildInstallScript(): string {
    const failedLabel = JSON.stringify(
      resolveAppResourceText($r('app.string.translation_ui_webpage_translation_panel_012'))
    );
    return `
(function () {
  var airaTranslationFailedLabel = ${failedLabel};
  if (window.${TRANSLATION_RUNTIME_NAME} &&
    window.${TRANSLATION_RUNTIME_NAME}.installed === true &&
    window.${TRANSLATION_RUNTIME_NAME}.runtimeVersion === '${TRANSLATION_RUNTIME_VERSION}' &&
    typeof window.${TRANSLATION_RUNTIME_NAME}.extractPageQueue === 'function' &&
    typeof window.${TRANSLATION_RUNTIME_NAME}.extractPendingBatch === 'function' &&
    typeof window.${TRANSLATION_RUNTIME_NAME}.configureCache === 'function' &&
    typeof window.${TRANSLATION_RUNTIME_NAME}.markLoading === 'function' &&
    typeof window.${TRANSLATION_RUNTIME_NAME}.clearTransientStates === 'function' &&
    typeof window.${TRANSLATION_RUNTIME_NAME}.showBilingualTranslations === 'function' &&
    typeof window.${TRANSLATION_RUNTIME_NAME}.showTranslationOnly === 'function' &&
    typeof window.${TRANSLATION_RUNTIME_NAME}.startObserver === 'function') {
    return 'already_installed';
  }
  var state = {
    installed: true,
    runtimeVersion: '${TRANSLATION_RUNTIME_VERSION}',
    nodeMap: {},
    originals: {},
    translated: {},
    translationCache: {},
    cacheNamespace: '',
    displayMode: 'translation_only',
    pending: {},
    loading: {},
    failed: {},
    activeLoadingRunId: 0,
    noopTranslated: {},
    observer: null,
    visibilityObserver: null,
    observedLazyBlocks: {},
    clickListener: null,
    toggleListener: null,
    scrollListener: null,
    loadListener: null,
    debounceTimer: 0,
    lastScrollAt: 0,
    queuedMutationNodes: [],
    mutationFlushTimer: 0,
    viewportRefreshTimer: 0,
    startupScanPasses: 0,
    chunkMeta: {},
    chunkTranslations: {},
    targetLanguage: '',
    pageSignalVersion: 1,
    routeSignalVersion: 1,
    spaHooked: false,
    nextId: 1
  };
  var siteRules = JSON.parse(${JSON.stringify(WEBPAGE_TRANSLATION_SITE_RULES_JSON)});
  var cachedSiteRuleHref = '';
  var cachedSiteRule = null;
  function wildcardContains(source, pattern) {
    if (!source || !pattern) {
      return false;
    }
    var text = '*' + pattern + '*';
    var sIndex = 0;
    var pIndex = 0;
    var sRecord = -1;
    var pRecord = -1;
    while (sIndex < source.length && pRecord < text.length) {
      if (pIndex < text.length && text.charAt(pIndex) === '*') {
        pIndex++;
        sRecord = sIndex;
        pRecord = pIndex;
      } else if (pIndex < text.length && source.charAt(sIndex) === text.charAt(pIndex)) {
        sIndex++;
        pIndex++;
      } else if (sRecord + 1 < source.length) {
        sRecord++;
        sIndex = sRecord;
        pIndex = pRecord;
      } else {
        return false;
      }
    }
    if (pIndex === text.length) {
      return true;
    }
    for (var starIndex = pIndex; starIndex < text.length; starIndex++) {
      if (text.charAt(starIndex) !== '*') {
        return false;
      }
    }
    return true;
  }
  function rulePatternMatches(href, pattern) {
    var source = String(href || '');
    var parts = String(pattern || '').split(/,|\\n/);
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i].trim();
      if (part && wildcardContains(source, part)) {
        return true;
      }
    }
    return false;
  }
  function matchSiteRule(href) {
    var currentHref = String(href || '');
    if (cachedSiteRuleHref === currentHref) {
      return cachedSiteRule;
    }
    cachedSiteRuleHref = currentHref;
    cachedSiteRule = null;
    for (var i = 0; i < siteRules.length; i++) {
      if (rulePatternMatches(currentHref, siteRules[i].pattern)) {
        cachedSiteRule = siteRules[i];
        break;
      }
    }
    return cachedSiteRule;
  }
  function splitTopLevel(value, separator) {
    var parts = [];
    var current = '';
    var paren = 0;
    var bracket = 0;
    var quote = '';
    for (var i = 0; i < value.length; i++) {
      var ch = value.charAt(i);
      if (quote) {
        current += ch;
        if (ch === '\\\\') {
          i++;
          current += value.charAt(i);
          continue;
        }
        if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        current += ch;
        continue;
      }
      if (ch === '(') {
        paren++;
      } else if (ch === ')') {
        paren = Math.max(0, paren - 1);
      } else if (ch === '[') {
        bracket++;
      } else if (ch === ']') {
        bracket = Math.max(0, bracket - 1);
      } else if (ch === separator && paren === 0 && bracket === 0) {
        if (current.trim()) {
          parts.push(current.trim());
        }
        current = '';
        continue;
      }
      current += ch;
    }
    if (current.trim()) {
      parts.push(current.trim());
    }
    return parts;
  }
  function splitShadowSelector(selector) {
    var parts = [];
    var current = '';
    var paren = 0;
    var bracket = 0;
    var quote = '';
    for (var i = 0; i < selector.length; i++) {
      var ch = selector.charAt(i);
      if (quote) {
        current += ch;
        if (ch === '\\\\') {
          i++;
          current += selector.charAt(i);
          continue;
        }
        if (ch === quote) {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        current += ch;
        continue;
      }
      if (ch === '(') {
        paren++;
      } else if (ch === ')') {
        paren = Math.max(0, paren - 1);
      } else if (ch === '[') {
        bracket++;
      } else if (ch === ']') {
        bracket = Math.max(0, bracket - 1);
      } else if (paren === 0 && bracket === 0 && selector.slice(i, i + 3) === '>>>') {
        if (current.trim()) {
          parts.push(current.trim());
        }
        current = '';
        i += 2;
        continue;
      }
      current += ch;
    }
    if (current.trim()) {
      parts.push(current.trim());
    }
    return parts;
  }
  function expandSiteSelectors(selectorText) {
    var groups = splitTopLevel(String(selectorText || ''), ';');
    var selectors = [];
    for (var i = 0; i < groups.length; i++) {
      var items = splitTopLevel(groups[i], ',');
      for (var j = 0; j < items.length; j++) {
        if (items[j]) {
          selectors.push(items[j]);
        }
      }
    }
    return selectors;
  }
  function pushSiteMatch(out, element) {
    if (!element || out.length >= 300) {
      return;
    }
    for (var i = 0; i < out.length; i++) {
      if (out[i] === element) {
        return;
      }
    }
    out.push(element);
  }
  function querySiteParts(base, parts, index, out) {
    if (!base || index >= parts.length || out.length >= 300) {
      return;
    }
    var found = [];
    var part = parts[index];
    if (base.nodeType === 1 && typeof base.matches === 'function') {
      try {
        if (base.matches(part)) {
          found.push(base);
        }
      } catch (ignoreMatch) {
      }
    }
    if (typeof base.querySelectorAll === 'function') {
      try {
        var nodes = base.querySelectorAll(part);
        for (var i = 0; i < nodes.length && found.length < 300; i++) {
          found.push(nodes[i]);
        }
      } catch (ignoreQuery) {
        return;
      }
    }
    if (index === parts.length - 1) {
      for (var j = 0; j < found.length; j++) {
        pushSiteMatch(out, found[j]);
      }
      return;
    }
    for (var k = 0; k < found.length && out.length < 300; k++) {
      if (found[k].shadowRoot) {
        querySiteParts(found[k].shadowRoot, parts, index + 1, out);
      }
    }
  }
  function collectSiteMatches(root, selector, out) {
    var parts = splitShadowSelector(selector);
    if (parts.length === 0) {
      return;
    }
    querySiteParts(root, parts, 0, out);
  }
  function collectSiteMatchesInShadows(root, selector, out) {
    if (!root || out.length >= 300 || typeof root.querySelectorAll !== 'function') {
      return;
    }
    var nodes;
    try {
      nodes = root.querySelectorAll('*');
    } catch (ignoreQuery) {
      return;
    }
    var limit = Math.min(nodes.length, 5000);
    for (var i = 0; i < limit && out.length < 300; i++) {
      var shadow = nodes[i].shadowRoot;
      if (!shadow) {
        continue;
      }
      collectSiteMatches(shadow, selector, out);
      collectSiteMatchesInShadows(shadow, selector, out);
    }
  }
  function isIgnoredBySiteRule(element) {
    var rule = matchSiteRule(String(location.href || ''));
    var selector = rule && String(rule.ignoreSelector || '').trim();
    if (!selector || !element || typeof element.closest !== 'function') {
      return false;
    }
    try {
      return !!element.closest(selector);
    } catch (ignoreMatch) {
      return false;
    }
  }
  function isKeptBySiteRule(element) {
    var rule = matchSiteRule(String(location.href || ''));
    var selector = rule && String(rule.keepSelector || '').trim();
    if (!selector || !element || typeof element.matches !== 'function') {
      return false;
    }
    try {
      return !!element.matches(selector);
    } catch (ignoreMatch) {
      return false;
    }
  }
  function applyRuleStyle(element, styleText) {
    var allowed = {
      '-webkit-line-clamp': true,
      'line-clamp': true,
      'max-height': true,
      'height': true,
      'overflow': true
    };
    var text = String(styleText || '').trim();
    if (!element || !text || typeof element.style === 'undefined') {
      return;
    }
    var parts = text.split(';');
    for (var i = 0; i < parts.length; i++) {
      var piece = parts[i].trim();
      var colon = piece.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      var name = piece.slice(0, colon).trim().toLowerCase();
      var value = piece.slice(colon + 1).trim();
      if (allowed[name] !== true || value.length === 0 || value.length > 40) {
        continue;
      }
      try {
        element.style.setProperty(name, value, 'important');
      } catch (ignoreStyle) {
      }
    }
  }
  var inlineTags = {
    '#text': true, a: true, abbr: true, acronym: true, b: true, bdi: true, bdo: true, big: true,
    br: true, cite: true, code: true, del: true, dfn: true, em: true, font: true, i: true,
    ins: true, kbd: true, label: true, mark: true, nobr: true, q: true, rp: true, rt: true,
    ruby: true, s: true, samp: true, small: true, span: true, strong: true, sub: true, sup: true,
    tt: true, u: true, var: true, wbr: true, img: true
  };
  var skipTags = {
    script: true, style: true, noscript: true, input: true, textarea: true, select: true, option: true,
    svg: true, canvas: true, video: true, audio: true, math: true, template: true
  };
  var leafBlockTags = {
    p: true, h1: true, h2: true, h3: true, h4: true, h5: true, h6: true, li: true,
    td: true, th: true, dd: true, dt: true, blockquote: true, figcaption: true, caption: true
  };
  var bilingualBlockTags = {
    p: true, h1: true, h2: true, h3: true, h4: true, h5: true, h6: true, li: true,
    dd: true, dt: true, blockquote: true, figcaption: true, caption: true
  };
  var chromeContainerTags = {
    nav: true, footer: true
  };
  var interactiveControlTags = {
    a: true, button: true, summary: true, label: true
  };
  var richInlineTags = {
    a: true, abbr: true, b: true, bdi: true, bdo: true, cite: true, code: true, dfn: true,
    em: true, i: true, kbd: true, mark: true, q: true, s: true, samp: true, small: true,
    span: true, strong: true, sub: true, sup: true, time: true, u: true, var: true
  };
  var noLetterPattern = /^[^A-Za-z\\u00C0-\\u024F\\u4E00-\\u9FFF]+$/;
  function normalizeText(value) {
    return String(value || '').replace(/\\s+/g, ' ').trim();
  }
  function normalizeTranslationComparableText(value) {
    return normalizeText(value).toLowerCase();
  }
  function normalizeCacheText(value) {
    return normalizeText(value).toLowerCase();
  }
  function buildTranslationCacheKey(text) {
    return state.cacheNamespace + '::' + normalizeCacheText(text);
  }
  function getCachedTranslation(text) {
    var key = buildTranslationCacheKey(text);
    var cached = state.translationCache[key];
    return typeof cached === 'string' && cached.trim().length > 0 ? cached : '';
  }
  function putCachedTranslation(originalText, translatedText) {
    var original = normalizeText(originalText);
    var translated = normalizeText(translatedText);
    if (original.length === 0 || translated.length === 0) {
      return;
    }
    state.translationCache[buildTranslationCacheKey(original)] = translated;
  }
  function hydrateTranslationCacheFromDom() {
    var results = document.querySelectorAll('.aira-translation-result[data-aira-original-text]');
    for (var i = 0; i < results.length; i++) {
      var result = results[i];
      if (isTransientTranslationResult(result)) {
        continue;
      }
      var original = String(result.getAttribute('data-aira-original-text') || '');
      var translated = String(result.getAttribute('data-aira-translated-text') || '');
      putCachedTranslation(original, translated.length > 0 ? translated : normalizeText(result.textContent));
    }
  }
  function isTranslationResultNode(node) {
    return node &&
      node.nodeType === Node.ELEMENT_NODE &&
      node.classList.contains('aira-translation-result');
  }
  function isLoadingTranslationResult(node) {
    return isTranslationResultNode(node) &&
      String(node.getAttribute('data-aira-translation-loading') || '').toLowerCase() === 'true';
  }
  function isFailedTranslationResult(node) {
    return isTranslationResultNode(node) &&
      String(node.getAttribute('data-aira-translation-failed') || '').toLowerCase() === 'true';
  }
  function isTransientTranslationResult(node) {
    return isLoadingTranslationResult(node) || isFailedTranslationResult(node);
  }
  function findHostedTranslationResult(element) {
    if (!element || !element.childNodes) {
      return null;
    }
    for (var i = 0; i < element.childNodes.length; i++) {
      var child = element.childNodes[i];
      if (isTranslationResultNode(child)) {
        return child;
      }
    }
    return null;
  }
  function findTranslationResult(element) {
    if (!element || !element.parentNode) {
      return null;
    }
    var hosted = findHostedTranslationResult(element);
    if (hosted) {
      return hosted;
    }
    var next = element.nextSibling;
    while (next && isWhitespaceText(next)) {
      next = next.nextSibling;
    }
    return isTranslationResultNode(next) ? next : null;
  }
  function getExistingTranslationText(element) {
    var result = findTranslationResult(element);
    if (!result) {
      return '';
    }
    if (isTransientTranslationResult(result)) {
      return '';
    }
    var text = String(result.getAttribute('data-aira-translated-text') || '');
    return text.trim().length > 0 ? text : normalizeText(result.textContent);
  }
  function hasVisibleTranslationResult(element) {
    var result = findTranslationResult(element);
    if (!result) {
      return false;
    }
    if (isTransientTranslationResult(result)) {
      return false;
    }
    if (result.style && result.style.display === 'none') {
      return false;
    }
    var style = window.getComputedStyle(result);
    return !style || style.display !== 'none';
  }
  function isBlockDisplayElement(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return true;
    }
    var tag = tagNameOf(element);
    if (inlineTags[tag] === true) {
      return false;
    }
    var style = window.getComputedStyle(element);
    return !style || String(style.display || '').toLowerCase().indexOf('inline') !== 0;
  }
  function isFlexOrGridElement(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    var style = window.getComputedStyle(element);
    var display = style ? String(style.display || '').toLowerCase() : '';
    return display.indexOf('flex') >= 0 || display.indexOf('grid') >= 0;
  }
  function isLayoutSensitiveContainer(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    if (isFlexOrGridElement(element)) {
      return true;
    }
    var tag = tagNameOf(element);
    if (tag === 'nav' || tag === 'header' || tag === 'menu' || tag === 'ul' || tag === 'ol') {
      return true;
    }
    var marker = String((element.id || '') + ' ' + (element.className || '') + ' ' +
      (element.getAttribute('role') || '')).toLowerCase();
    return /(tab|nav|channel|toolbar|menu|filter|header|breadcrumb)/.test(marker);
  }
  function hasMultipleElementChildren(nodes) {
    var count = 0;
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].nodeType === Node.ELEMENT_NODE) {
        count++;
        if (count > 1) {
          return true;
        }
      }
    }
    return false;
  }
  function unwrapTranslationWrapper(wrapper) {
    if (!wrapper || !wrapper.parentNode || wrapper.getAttribute('data-aira-translation-wrap') !== 'true') {
      return false;
    }
    var parent = wrapper.parentNode;
    while (wrapper.firstChild) {
      parent.insertBefore(wrapper.firstChild, wrapper);
    }
    parent.removeChild(wrapper);
    return true;
  }
  function repairLayoutSensitiveTranslationWrappers(root) {
    var scope = root || document.body || document.documentElement;
    if (!scope || typeof scope.querySelectorAll !== 'function') {
      return 0;
    }
    var repaired = 0;
    var wrappers = scope.querySelectorAll('[data-aira-translation-wrap="true"]');
    for (var i = 0; i < wrappers.length; i++) {
      var wrapper = wrappers[i];
      var parent = wrapper.parentElement;
      if (parent && isLayoutSensitiveContainer(parent) && unwrapTranslationWrapper(wrapper)) {
        repaired++;
      }
    }
    return repaired;
  }
  function shouldUseBilingualResult(sourceElement) {
    if (!sourceElement || sourceElement.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    var tag = tagNameOf(sourceElement);
    if (bilingualBlockTags[tag] !== true) {
      return false;
    }
    if (sourceElement.getAttribute('data-aira-translation-wrap') === 'true') {
      return false;
    }
    return !isChromeContainer(sourceElement);
  }
  function shouldShowSourceWithTranslation(preferredDisplayMode) {
    return preferredDisplayMode !== 'translation_only';
  }
  function canMirrorTranslationTag(tag) {
    return {
      h1: true, h2: true, h3: true, h4: true, h5: true, h6: true,
      p: true, li: true, dt: true, dd: true, blockquote: true,
      figcaption: true, caption: true, button: true, a: true, span: true,
      strong: true, em: true, label: true
    }[tag] === true;
  }
  function resolveTranslationResultTag(sourceElement) {
    var tag = tagNameOf(sourceElement);
    if (isInteractiveControl(sourceElement)) {
      return 'span';
    }
    if (tag === 'font' && sourceElement.getAttribute('data-aira-translation-wrap') === 'true') {
      return 'span';
    }
    return canMirrorTranslationTag(tag) ? tag : 'span';
  }
  function shouldMirrorSourceClass(sourceElement) {
    return !shouldUseBilingualResult(sourceElement);
  }
  function applyTranslationIdentity(result, sourceElement) {
    var tag = tagNameOf(sourceElement);
    result.className = 'aira-translation-result notranslate';
    if (shouldUseBilingualResult(sourceElement)) {
      result.className += ' aira-translation-bilingual';
    } else {
      result.className += ' aira-translation-replacement';
    }
    var className = String(sourceElement.getAttribute('class') || '').trim();
    if (className.length > 0 && tag !== 'font' && !isInteractiveControl(sourceElement) &&
      shouldMirrorSourceClass(sourceElement)) {
      result.className += ' ' + className;
    }
    result.setAttribute('translate', 'no');
    result.setAttribute('data-aira-translation-result', 'true');
    result.setAttribute('data-aira-source-tag', tag);
    if (className.length > 0) {
      result.setAttribute('data-aira-source-class', className);
    } else {
      result.removeAttribute('data-aira-source-class');
    }
  }
  function setImportantStyle(element, property, value) {
    var normalized = String(value || '').trim();
    if (normalized.length === 0) {
      return;
    }
    element.style.setProperty(property, normalized, 'important');
  }
  var textPresentationProperties = [
    ['fontFamily', 'font-family'],
    ['fontSize', 'font-size'],
    ['fontWeight', 'font-weight'],
    ['fontStyle', 'font-style'],
    ['fontVariant', 'font-variant'],
    ['lineHeight', 'line-height'],
    ['letterSpacing', 'letter-spacing'],
    ['textTransform', 'text-transform'],
    ['textDecorationLine', 'text-decoration-line'],
    ['textAlign', 'text-align'],
    ['color', 'color'],
    ['whiteSpace', 'white-space'],
    ['wordBreak', 'word-break'],
    ['overflowWrap', 'overflow-wrap']
  ];
  function copyTextPresentation(result, sourceElement) {
    var style = window.getComputedStyle(sourceElement);
    if (!style) {
      return;
    }
    textPresentationProperties.forEach(function (pair) {
      var jsProperty = pair[0];
      var cssProperty = pair[1];
      var value = typeof style.getPropertyValue === 'function'
        ? style.getPropertyValue(cssProperty)
        : style[jsProperty];
      setImportantStyle(result, cssProperty, value || style[jsProperty]);
    });
  }
  function styleTranslationResultElement(result, sourceElement, preferredDisplayMode) {
    applyTranslationIdentity(result, sourceElement);
    copyTextPresentation(result, sourceElement);
    var sourceStyle = window.getComputedStyle(sourceElement);
    var showSource = shouldShowSourceWithTranslation(preferredDisplayMode);
    var bilingual = showSource && shouldUseBilingualResult(sourceElement);
    result.setAttribute('data-aira-display-mode', bilingual ? 'bilingual' : 'translation_only');
    if (translationUsesHost(sourceElement)) {
      setImportantStyle(result, 'display', 'inline');
      result.style.removeProperty('margin-top');
      result.style.removeProperty('margin-right');
      result.style.removeProperty('margin-bottom');
      result.style.removeProperty('margin-left');
      result.style.removeProperty('opacity');
      return;
    }
    if (isBlockDisplayElement(sourceElement)) {
      var displayValue = sourceStyle && sourceStyle.display && sourceStyle.display !== 'none'
        ? sourceStyle.display
        : 'block';
      setImportantStyle(result, 'display', displayValue);
      setImportantStyle(result, 'margin-top', bilingual ? '0.2em' : (sourceStyle ? sourceStyle.marginTop : ''));
      setImportantStyle(result, 'margin-right', sourceStyle ? sourceStyle.marginRight : '');
      setImportantStyle(result, 'margin-bottom', sourceStyle ? sourceStyle.marginBottom : '');
      setImportantStyle(result, 'margin-left', sourceStyle ? sourceStyle.marginLeft : '');
      if (bilingual) {
        setImportantStyle(result, 'color', sourceStyle ? sourceStyle.color : '');
        result.style.removeProperty('opacity');
      } else {
        result.style.removeProperty('opacity');
      }
    } else {
      var inlineDisplayValue = sourceStyle && String(sourceStyle.display || '').toLowerCase().indexOf('inline') === 0
        ? sourceStyle.display
        : 'inline';
      setImportantStyle(result, 'display', inlineDisplayValue);
      setImportantStyle(result, 'margin-left', '0.35em');
      result.style.removeProperty('margin-top');
      result.style.removeProperty('opacity');
    }
  }
  function createTranslationResultElement(sourceElement, originalText, translatedText) {
    var result = document.createElement(resolveTranslationResultTag(sourceElement));
    applyTranslationIdentity(result, sourceElement);
    result.setAttribute('data-aira-original-text', originalText);
    result.setAttribute('data-aira-translated-text', translatedText);
    result.textContent = translatedText;
    styleTranslationResultElement(result, sourceElement, state.displayMode);
    return result;
  }
  function isInteractiveControl(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    var tag = tagNameOf(element);
    if (interactiveControlTags[tag] === true) {
      return true;
    }
    var role = String(element.getAttribute('role') || '').toLowerCase();
    return role === 'button' || role === 'link' || role === 'menuitem' ||
      role === 'tab' || role === 'switch';
  }
  function closestInteractiveControl(element) {
    var current = element;
    while (current && current !== document.body && current !== document.documentElement) {
      if (isInteractiveControl(current)) {
        return current;
      }
      current = current.parentElement;
    }
    return null;
  }
  function anchorHref(element) {
    if (!element || tagNameOf(element) !== 'a') {
      return '';
    }
    return String(element.getAttribute('href') || '').trim();
  }
  function isRichInlineElement(element) {
    return element && element.nodeType === Node.ELEMENT_NODE && richInlineTags[tagNameOf(element)] === true;
  }
  function containsAnchor(nodes) {
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (node.nodeType !== Node.ELEMENT_NODE) {
        continue;
      }
      if (tagNameOf(node) === 'a' ||
        (typeof node.querySelector === 'function' && node.querySelector('a, button, [role="button"], [role="link"]'))) {
        return true;
      }
    }
    return false;
  }
  function splitSegmentAroundAnchors(segment) {
    if (!containsAnchor(segment)) {
      return null;
    }
    var parts = [];
    var current = [];
    function pushCurrent() {
      if (current.length > 0) {
        parts.push(current);
        current = [];
      }
    }
    for (var i = 0; i < segment.length; i++) {
      var node = segment[i];
      if (node.nodeType === Node.ELEMENT_NODE && tagNameOf(node) === 'a') {
        pushCurrent();
        parts.push([node]);
        continue;
      }
      if (node.nodeType === Node.ELEMENT_NODE && typeof node.querySelector === 'function' && node.querySelector('a')) {
        if (!isRichInlineElement(node)) {
          return null;
        }
        pushCurrent();
        var inner = [];
        for (var childIndex = 0; childIndex < node.childNodes.length; childIndex++) {
          inner.push(node.childNodes[childIndex]);
        }
        var nested = splitSegmentAroundAnchors(inner);
        if (!nested) {
          return null;
        }
        for (var nestedIndex = 0; nestedIndex < nested.length; nestedIndex++) {
          parts.push(nested[nestedIndex]);
        }
        continue;
      }
      current.push(node);
    }
    pushCurrent();
    return parts.length > 1 ? parts : null;
  }
  function isSafeAnchorHref(href) {
    if (!href) {
      return false;
    }
    var lower = href.toLowerCase();
    if (lower.indexOf('javascript:') === 0 || lower.indexOf('data:') === 0 || lower.indexOf('vbscript:') === 0) {
      return false;
    }
    return true;
  }
  function translationUsesHost(element) {
    return isInteractiveControl(element);
  }
  function placeTranslationResult(element, result) {
    if (!element) {
      return;
    }
    if (translationUsesHost(element)) {
      element.appendChild(result);
      return;
    }
    if (element.parentNode) {
      element.parentNode.insertBefore(result, element.nextSibling);
    }
  }
  function setResultTextPreservingAnchors(result, sourceElement, translatedText) {
    var text = String(translatedText || '');
    if (translationUsesHost(sourceElement)) {
      result.textContent = text;
      return;
    }
    var href = anchorHref(sourceElement);
    if (!isSafeAnchorHref(href)) {
      result.textContent = text;
      return;
    }
    var link = document.createElement('a');
    link.setAttribute('href', href);
    var target = String(sourceElement.getAttribute('target') || '').trim();
    if (target.length > 0 && target.toLowerCase() !== '_top') {
      link.setAttribute('target', target);
    }
    var rel = String(sourceElement.getAttribute('rel') || '').trim();
    if (rel.length > 0) {
      link.setAttribute('rel', rel);
    }
    link.textContent = text;
    result.textContent = '';
    result.appendChild(link);
  }
  function clearTransientIdentity(result) {
    if (!result) {
      return;
    }
    result.removeAttribute('data-aira-translation-loading');
    result.removeAttribute('data-aira-translation-failed');
    result.removeAttribute('data-aira-loading-run-id');
    result.removeAttribute('aria-busy');
    result.removeAttribute('role');
    result.classList.remove('aira-translation-loading');
    result.classList.remove('aira-translation-failed');
  }
  function createSvgElement(tag, attrs) {
    var element = document.createElementNS('http://www.w3.org/2000/svg', tag);
    Object.keys(attrs || {}).forEach(function (key) {
      element.setAttribute(key, attrs[key]);
    });
    return element;
  }
  function createLoadingIndicator() {
    var svg = createSvgElement('svg', {
      viewBox: '-20 0 100 100',
      style: 'display:inline-block;width:1em;height:1em;vertical-align:-0.12em;'
    });
    var dots = [
      { cx: '6', begin: '0.1s', values: '0 15;0 -15;0 15' },
      { cx: '30', begin: '0.2s', values: '0 10;0 -10;0 10' },
      { cx: '54', begin: '0.3s', values: '0 5;0 -5;0 5' }
    ];
    for (var i = 0; i < dots.length; i++) {
      var circle = createSvgElement('circle', {
        fill: 'currentColor',
        stroke: 'none',
        cx: dots[i].cx,
        cy: '50',
        r: '6'
      });
      var animation = createSvgElement('animateTransform', {
        attributeName: 'transform',
        dur: '1s',
        type: 'translate',
        values: dots[i].values,
        repeatCount: 'indefinite',
        begin: dots[i].begin
      });
      circle.appendChild(animation);
      svg.appendChild(circle);
    }
    return svg;
  }
  function styleTransientResultElement(result, sourceElement) {
    styleTranslationResultElement(result, sourceElement, 'bilingual');
    showSourceElement(sourceElement);
    result.style.removeProperty('display');
    result.style.removeProperty('opacity');
    if (isBlockDisplayElement(sourceElement)) {
      setImportantStyle(result, 'display', 'inline-block');
      setImportantStyle(result, 'margin-top', '0.2em');
      setImportantStyle(result, 'margin-bottom', '0');
      setImportantStyle(result, 'min-width', '1.2em');
    } else {
      setImportantStyle(result, 'display', 'inline-block');
      setImportantStyle(result, 'margin-left', '0.35em');
      setImportantStyle(result, 'min-width', '1.2em');
    }
  }
  function createLoadingResultElement(sourceElement, originalText, runId) {
    var result = document.createElement(resolveTranslationResultTag(sourceElement));
    result.setAttribute('data-aira-original-text', originalText);
    result.setAttribute('data-aira-translated-text', '');
    styleTransientResultElement(result, sourceElement);
    result.classList.add('aira-translation-loading');
    result.setAttribute('data-aira-translation-loading', 'true');
    result.setAttribute('data-aira-loading-run-id', String(runId || ''));
    result.setAttribute('aria-busy', 'true');
    result.setAttribute('role', 'status');
    result.textContent = '';
    result.appendChild(createLoadingIndicator());
    return result;
  }
  function createFailedResultElement(sourceElement, originalText, message, runId) {
    var result = document.createElement(resolveTranslationResultTag(sourceElement));
    result.setAttribute('data-aira-original-text', originalText);
    result.setAttribute('data-aira-translated-text', '');
    styleTransientResultElement(result, sourceElement);
    result.classList.add('aira-translation-failed');
    result.setAttribute('data-aira-translation-failed', 'true');
    result.setAttribute('data-aira-loading-run-id', String(runId || ''));
    result.textContent = normalizeText(message).length > 0 ? normalizeText(message) : airaTranslationFailedLabel;
    return result;
  }
  function insertOrUpdateTransientResult(element, result) {
    var existing = findTranslationResult(element);
    if (!existing) {
      placeTranslationResult(element, result);
      return result;
    }
    if (existing.parentNode) {
      existing.parentNode.replaceChild(result, existing);
    }
    return result;
  }
  function removeTransientResultForNode(node, runId) {
    var result = findTranslationResult(node);
    if (!isTransientTranslationResult(result)) {
      return false;
    }
    if (runId !== undefined && runId !== null && String(runId).length > 0) {
      var existingRunId = String(result.getAttribute('data-aira-loading-run-id') || '');
      if (existingRunId.length > 0 && existingRunId !== String(runId)) {
        return false;
      }
    }
    result.remove();
    showSourceElement(node);
    return true;
  }
  function removeTransientResultById(id, runId) {
    var node = state.nodeMap[id];
    if (!node) {
      delete state.loading[id];
      delete state.failed[id];
      return false;
    }
    var removed = removeTransientResultForNode(node, runId);
    delete state.loading[id];
    delete state.failed[id];
    return removed;
  }
  function currentTextMatchesItem(node, expectedText) {
    var expected = normalizeTranslationComparableText(expectedText);
    if (expected.length === 0) {
      return false;
    }
    var current = normalizeTranslationComparableText(visibleTextOfElement(node));
    return current === expected || current.indexOf(expected) === 0 || expected.indexOf(current) === 0;
  }
  function showSourceElement(element) {
    if (!element) {
      return;
    }
    element.classList.remove('aira-translation-original-hidden');
    element.style.removeProperty('display');
    if (element.hasAttribute('data-aira-original-display-style')) {
      var originalDisplay = String(element.getAttribute('data-aira-original-display-style') || '').trim();
      if (originalDisplay.length > 0) {
        element.style.setProperty('display', originalDisplay);
      }
      element.removeAttribute('data-aira-original-display-style');
    }
  }
  function hideSourceElement(element) {
    if (!element) {
      return;
    }
    if (!element.hasAttribute('data-aira-original-display-style')) {
      element.setAttribute('data-aira-original-display-style', element.style.display || '');
    }
    element.classList.add('aira-translation-original-hidden');
    element.style.setProperty('display', 'none', 'important');
  }
  function isNonTextSourceNode(node) {
    if (!node || node.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    var tag = tagNameOf(node);
    if (tag === 'img' || tag === 'svg' || tag === 'br' || tag === 'picture' || tag === 'video' || tag === 'canvas') {
      return true;
    }
    return normalizeText(node.textContent).length === 0;
  }
  function releaseSourceContent(element) {
    if (!element) {
      return;
    }
    var holders = [];
    for (var i = 0; i < element.childNodes.length; i++) {
      var child = element.childNodes[i];
      if (child.nodeType === Node.ELEMENT_NODE && child.classList.contains('aira-translation-source')) {
        holders.push(child);
      }
    }
    for (var holderIndex = 0; holderIndex < holders.length; holderIndex++) {
      var holder = holders[holderIndex];
      showSourceElement(holder);
      var parent = holder.parentNode;
      if (!parent) {
        continue;
      }
      while (holder.firstChild) {
        parent.insertBefore(holder.firstChild, holder);
      }
      parent.removeChild(holder);
    }
    element.removeAttribute('data-aira-source-hidden');
  }
  function showSourceContent(element) {
    if (!element) {
      return;
    }
    for (var i = 0; i < element.childNodes.length; i++) {
      var child = element.childNodes[i];
      if (child.nodeType === Node.ELEMENT_NODE && child.classList.contains('aira-translation-source')) {
        showSourceElement(child);
      }
    }
  }
  function hideSourceContent(element) {
    if (!element) {
      return;
    }
    var holders = [];
    var loose = [];
    for (var i = 0; i < element.childNodes.length; i++) {
      var child = element.childNodes[i];
      if (child.nodeType === Node.ELEMENT_NODE && child.classList.contains('aira-translation-source')) {
        holders.push(child);
        continue;
      }
      if (isTranslationResultNode(child) || isNonTextSourceNode(child)) {
        continue;
      }
      loose.push(child);
    }
    if (loose.length > 0) {
      var holder = holders.length > 0 ? holders[0] : document.createElement('span');
      if (!holder.parentNode) {
        holder.className = 'aira-translation-source';
        element.insertBefore(holder, loose[0]);
        holders.push(holder);
      }
      for (var index = 0; index < loose.length; index++) {
        holder.appendChild(loose[index]);
      }
    }
    for (var holderIndex = 0; holderIndex < holders.length; holderIndex++) {
      hideSourceElement(holders[holderIndex]);
    }
    if (holders.length > 0) {
      element.setAttribute('data-aira-source-hidden', 'true');
    }
  }
  function insertOrUpdateTranslationResult(element, originalText, translatedText) {
    var result = findTranslationResult(element);
    if (!result) {
      result = createTranslationResultElement(element, originalText, translatedText);
      placeTranslationResult(element, result);
    } else {
      var expectedTag = resolveTranslationResultTag(element);
      if (tagNameOf(result) !== expectedTag && result.parentNode) {
        var replacement = createTranslationResultElement(element, originalText, translatedText);
        result.parentNode.replaceChild(replacement, result);
        result = replacement;
      }
      result.setAttribute('data-aira-original-text', originalText);
      result.setAttribute('data-aira-translated-text', translatedText);
      clearTransientIdentity(result);
      setResultTextPreservingAnchors(result, element, translatedText);
      styleTranslationResultElement(result, element, state.displayMode);
    }
    clearTransientIdentity(result);
    result.setAttribute('data-aira-original-text', originalText);
    result.setAttribute('data-aira-translated-text', translatedText);
    if (translationUsesHost(element)) {
      showSourceElement(element);
      if (shouldShowSourceWithTranslation(state.displayMode) || isTransientTranslationResult(result)) {
        releaseSourceContent(element);
      } else {
        hideSourceContent(element);
      }
    } else if (shouldShowSourceWithTranslation(state.displayMode)) {
      showSourceElement(element);
    } else {
      hideSourceElement(element);
    }
  }
  function tagNameOf(element) {
    return String(element && element.tagName ? element.tagName : '').toLowerCase();
  }
  function shouldSkipElement(element) {
    if (!element || !element.tagName) {
      return true;
    }
    var tag = tagNameOf(element);
    if (skipTags[tag] === true) {
      return true;
    }
    if (element.isContentEditable === true) {
      return true;
    }
    if (String(element.getAttribute('translate') || '').toLowerCase() === 'no' ||
      element.classList.contains('notranslate') ||
      element.classList.contains('CodeMirror') ||
      element.classList.contains('monaco-editor') ||
      element.classList.contains('ProseMirror') ||
      element.classList.contains('aira-translation-result') ||
      element.classList.contains('aira-translation-source') ||
      element.classList.contains('aira-translation-original-hidden')) {
      return true;
    }
    var type = String(element.getAttribute('type') || '').toLowerCase();
    if (type === 'password' || type === 'hidden') {
      return true;
    }
    if (closestElement(element, '[contenteditable="true"], [data-lexical-editor], [data-slate-editor], .ql-editor, .ck-editor, .tox-editor-container, .cm-editor, .monaco-editor')) {
      return true;
    }
    return false;
  }
  function isDisplayContents(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    var style = window.getComputedStyle(element);
    return !!style && String(style.display || '').toLowerCase() === 'contents';
  }
  function isCurrentlyHidden(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    if (element.hidden === true) {
      return true;
    }
    var style = window.getComputedStyle(element);
    if (!style || isDisplayContents(element)) {
      return false;
    }
    if (String(style.display || '').toLowerCase() === 'none' || String(style.visibility || '').toLowerCase() === 'hidden') {
      return true;
    }
    return String(style.opacity || '').trim() === '0';
  }
  function isCodePre(element) {
    if (!element || tagNameOf(element) !== 'pre') {
      return false;
    }
    if (typeof element.querySelector === 'function' && element.querySelector('code')) {
      return true;
    }
    var marker = String((element.id || '') + ' ' + (element.className || '')).toLowerCase();
    return /(hljs|highlight|prism|prettyprint|syntax|language-|code-block|codeblock)/.test(marker);
  }
  function hasSkippedAncestor(element) {
    var current = element;
    while (current && current !== document.body && current !== document.documentElement) {
      if (shouldSkipElement(current)) {
        return true;
      }
      current = current.parentElement;
    }
    return false;
  }
  function isChromeContainer(element) {
    var current = element;
    while (current && current !== document.body && current !== document.documentElement) {
      var tag = tagNameOf(current);
      if (chromeContainerTags[tag] === true) {
        return true;
      }
      current = current.parentElement;
    }
    return false;
  }
  function isInlineDisplay(element) {
    var tag = tagNameOf(element);
    if (inlineTags[tag] === true) {
      return true;
    }
    var style = window.getComputedStyle(element);
    return !!style && String(style.display || '').toLowerCase().indexOf('inline') === 0;
  }
  function isInlineish(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return true;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    var element = node;
    if (skipTags[tagNameOf(element)] === true || shouldSkipElement(element)) {
      return false;
    }
    if (hasBlockChild(element)) {
      return false;
    }
    return isInlineDisplay(element);
  }
  function isWhitespaceText(node) {
    return node.nodeType === Node.TEXT_NODE && normalizeText(node.textContent).length === 0;
  }
  function isBr(node) {
    return node.nodeType === Node.ELEMENT_NODE && tagNameOf(node) === 'br';
  }
  function isBlockTag(tag) {
    return inlineTags[tag] !== true && skipTags[tag] !== true;
  }
  function hasBlockChild(element) {
    for (var i = 0; i < element.children.length; i++) {
      var child = element.children[i];
      var tag = tagNameOf(child);
      if (shouldSkipElement(child)) {
        continue;
      }
      if (isBlockTag(tag)) {
        if (tag.indexOf('-') >= 0 && normalizeText(child.textContent).length === 0) {
          continue;
        }
        if (isInlineDisplay(child)) {
          if (hasBlockChild(child)) {
            return true;
          }
          continue;
        }
        return true;
      }
      if (inlineTags[tag] === true && hasBlockChild(child)) {
        return true;
      }
    }
    return false;
  }
  function isLeafBlock(element) {
    var tag = tagNameOf(element);
    return leafBlockTags[tag] === true && !hasBlockChild(element);
  }
  function visibleTextOfChild(child) {
    if (child.nodeType === Node.TEXT_NODE) {
      return child.textContent || '';
    }
    if (child.nodeType !== Node.ELEMENT_NODE) {
      return '';
    }
    var element = child;
    if (shouldSkipElement(element)) {
      return '';
    }
    return visibleTextOfElement(element);
  }
  function visibleTextOfElement(element) {
    var text = '';
    for (var i = 0; i < element.childNodes.length; i++) {
      text += visibleTextOfChild(element.childNodes[i]);
    }
    return text;
  }
  function visibleTextOfNodes(nodes) {
    var text = '';
    for (var i = 0; i < nodes.length; i++) {
      text += visibleTextOfChild(nodes[i]);
    }
    return text;
  }
  function hasBrBrSeparator(element) {
    var brCount = 0;
    for (var i = 0; i < element.childNodes.length; i++) {
      var child = element.childNodes[i];
      if (isBr(child)) {
        brCount++;
        if (brCount >= 2) {
          return true;
        }
      } else if (!isWhitespaceText(child)) {
        brCount = 0;
      }
    }
    return false;
  }
  function closestElement(element, selector) {
    if (!element || typeof element.closest !== 'function') {
      return null;
    }
    try {
      return element.closest(selector);
    } catch (error) {
      return null;
    }
  }
  function isInsideChromeElement(element) {
    return !!closestElement(element,
      '[aria-label*="share" i], [class*="share" i], [class*="social" i], [class*="subscribe" i], [id*="share" i]');
  }
  function isLikelyChromeText(text, element) {
    var normalized = normalizeText(text);
    if (normalized.length === 0) {
      return true;
    }
    var lower = normalized.toLowerCase();
    if (['source'].indexOf(lower) >= 0) {
      return true;
    }
    if (normalized.length <= 40 && !/[A-Za-z\\u00C0-\\u024F\\u4E00-\\u9FFF]/.test(normalized)) {
      return true;
    }
    if (normalized.length <= 18 && isInsideChromeElement(element)) {
      return true;
    }
    return false;
  }
  function contentScore(node) {
    var parent = node && node.parentElement;
    if (!parent) {
      return -1000;
    }
    var text = normalizeText(node.textContent);
    if (isLikelyChromeText(text, parent)) {
      return -1000;
    }
    var tag = String(parent.tagName || '').toLowerCase();
    var score = 0;
    if (closestElement(parent, 'article, main, [class*="article" i], [class*="content" i], [class*="story" i], [class*="detail" i], [id*="article" i], [id*="content" i]')) {
      score += 80;
    }
    if (tag === 'h1') {
      score += 120;
    } else if (tag === 'h2' || tag === 'h3') {
      score += 70;
    } else if (tag === 'p') {
      score += 100;
    } else if (tag === 'li') {
      score += 20;
    }
    if (text.length >= 80) {
      score += 60;
    } else if (text.length >= 35) {
      score += 30;
    } else if (text.length < 12) {
      score -= 80;
    }
    var rect = parent.getBoundingClientRect();
    score -= Math.max(0, rect.top) / 10000;
    return score;
  }
  function isNearViewport(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE || element.hidden === true) {
      return false;
    }
    var inlineStyle = element.style;
    if (inlineStyle && (inlineStyle.display === 'none' || inlineStyle.visibility === 'hidden')) {
      return false;
    }
    var rect = element.getBoundingClientRect();
    var hasBox = rect.width > 0 && rect.height > 0;
    if (!hasBox) {
      if (!isDisplayContents(element)) {
        return false;
      }
      for (var childIndex = 0; childIndex < element.children.length; childIndex++) {
        if (isNearViewport(element.children[childIndex])) {
          return true;
        }
      }
      return false;
    }
    var viewHeight = window.innerHeight || document.documentElement.clientHeight || 0;
    var viewWidth = window.innerWidth || document.documentElement.clientWidth || 0;
    return rect.bottom >= -360 && rect.right >= -80 && rect.top <= viewHeight + 480 && rect.left <= viewWidth + 80;
  }
  function languageFamily(code) {
    var normalized = String(code || '').toLowerCase().split('-')[0];
    if (normalized === 'cmn') {
      return 'zh';
    }
    return normalized;
  }
  function dominantLanguageFamily(text) {
    var sample = String(text || '');
    var cjk = (sample.match(/[\u4E00-\u9FFF]/g) || []).length;
    var kana = (sample.match(/[\u3040-\u30FF]/g) || []).length;
    var hangul = (sample.match(/[\uAC00-\uD7AF]/g) || []).length;
    var latin = (sample.match(/[A-Za-z\u00C0-\u024F]/g) || []).length;
    var total = cjk + kana + hangul + latin;
    if (total < 8) {
      return '';
    }
    if (hangul / total >= 0.4) {
      return 'ko';
    }
    if (kana >= 2 && (kana + cjk) / total >= 0.4) {
      return 'ja';
    }
    if (cjk / total >= 0.5) {
      return 'zh';
    }
    if (latin / total >= 0.72 && cjk === 0 && kana === 0 && hangul === 0) {
      return 'en';
    }
    return '';
  }
  function isTargetLanguageText(text) {
    var target = languageFamily(state.targetLanguage);
    var detected = dominantLanguageFamily(text);
    return target.length > 0 && detected.length > 0 && target === detected;
  }
  function rememberTargetLanguage(namespace) {
    var parts = String(namespace || '').split(':');
    if (parts.length >= 2 && parts[parts.length - 1] === 'v2') {
      state.targetLanguage = String(parts[parts.length - 2] || '').toLowerCase();
    }
  }
  function shouldSkipDocumentElement(element) {
    if (shouldSkipElement(element)) {
      return true;
    }
    var text = normalizeText(element.textContent);
    if (text.length < 2 || isLikelyChromeText(text, element)) {
      return true;
    }
    return false;
  }
  function getNodeId(node) {
    if (node.__airaTranslationId) {
      return node.__airaTranslationId;
    }
    var id = 't_' + state.nextId++;
    try {
      Object.defineProperty(node, '__airaTranslationId', { value: id, configurable: true });
    } catch (error) {
      node.__airaTranslationId = id;
    }
    state.nodeMap[id] = node;
    return id;
  }
  function getBlockId(element) {
    if (element.__airaTranslationBlockId) {
      state.nodeMap[element.__airaTranslationBlockId] = element;
      return element.__airaTranslationBlockId;
    }
    var id = 'b_' + state.nextId++;
    try {
      Object.defineProperty(element, '__airaTranslationBlockId', { value: id, configurable: true });
    } catch (error) {
      element.__airaTranslationBlockId = id;
    }
    state.nodeMap[id] = element;
    return id;
  }
  function scoreBlock(element, text) {
    var tag = tagNameOf(element);
    var score = 0;
    if (closestElement(element, 'article, main, [role="main"], [class*="article" i], [class*="content" i], [class*="story" i], [class*="detail" i], [id*="article" i], [id*="content" i]')) {
      score += 80;
    }
    if (tag === 'h1') {
      score += 130;
    } else if (tag === 'h2' || tag === 'h3') {
      score += 90;
    } else if (tag === 'p' || tag === 'blockquote') {
      score += 100;
    } else if (tag === 'li' || tag === 'td' || tag === 'th') {
      score += 35;
    }
    if (text.length >= 120) {
      score += 70;
    } else if (text.length >= 45) {
      score += 40;
    } else if (text.length < 10) {
      score -= 40;
    }
    if (isChromeContainer(element)) {
      score -= 240;
    }
    var rect = element.getBoundingClientRect();
    score -= Math.max(0, rect.top) / 10000;
    return score;
  }
  function buildBlockItem(element, text, order) {
    var id = getBlockId(element);
    var rect = element.getBoundingClientRect();
    state.originals[id] = text;
    var item = {
      id: id,
      text: text,
      charLength: text.length,
      order: order,
      score: Math.floor(scoreBlock(element, text)),
      nearViewport: isNearViewport(element),
      top: Math.floor(rect.top || 0)
    };
    var existing = getExistingTranslationText(element);
    var cached = existing.length > 0 ? existing : getCachedTranslation(text);
    if (cached.length > 0) {
      item.cachedTranslatedText = cached;
    }
    return item;
  }
  function segmentRunByBrBr(run) {
    var segments = [];
    var current = [];
    var i = 0;
    while (i < run.length) {
      if (!isBr(run[i])) {
        current.push(run[i]);
        i++;
        continue;
      }
      var j = i;
      var brCount = 0;
      while (j < run.length && (isBr(run[j]) || isWhitespaceText(run[j]))) {
        if (isBr(run[j])) {
          brCount++;
        }
        j++;
      }
      if (brCount >= 2) {
        if (current.length > 0) {
          segments.push(current);
          current = [];
        }
        i = j;
      } else {
        while (i < j) {
          current.push(run[i]);
          i++;
        }
      }
    }
    if (current.length > 0) {
      segments.push(current);
    }
    return segments;
  }
  function createInlineWrapper(parent, segment) {
    if (isLayoutSensitiveContainer(parent) && hasMultipleElementChildren(segment)) {
      return null;
    }
    var wrapper = document.createElement('span');
    wrapper.setAttribute('data-aira-translation-wrap', 'true');
    parent.insertBefore(wrapper, segment[0]);
    for (var i = 0; i < segment.length; i++) {
      wrapper.appendChild(segment[i]);
    }
    return wrapper;
  }
  function shouldAllowCollectMutation(element, onlyNearViewport) {
    return onlyNearViewport !== true || isNearViewport(element);
  }
  function collectTranslationBlocks(root, diagnostics, options) {
    var onlyNearViewport = options && options.onlyNearViewport === true;
    var blocks = [];
    var order = 0;
    var seen = {};
    function addBlock(element, text, forced) {
      var normalized = normalizeText(text);
      diagnostics.totalTextNodes++;
      if (normalized.length < 2 || noLetterPattern.test(normalized) || isTargetLanguageText(normalized)) {
        diagnostics.rejectedByText++;
        return;
      }
      if (forced !== true && (isLikelyChromeText(normalized, element) || isIgnoredBySiteRule(element))) {
        diagnostics.rejectedByText++;
        return;
      }
      if (forced !== true && tagNameOf(element).indexOf('-') >= 0 && matchSiteRule(String(location.href || ''))) {
        diagnostics.rejectedByElement++;
        return;
      }
      var id = getBlockId(element);
      if (seen[id] || state.translated[id] || state.noopTranslated[id] || hasVisibleTranslationResult(element)) {
        diagnostics.skippedTranslated++;
        return;
      }
      seen[id] = true;
      blocks.push({
        element: element,
        text: normalized,
        order: order++,
        score: scoreBlock(element, normalized),
        nearViewport: isNearViewport(element),
        top: element.getBoundingClientRect().top
      });
      diagnostics.acceptedTextNodes++;
    }
    function flushSegment(parent, segment) {
      while (segment.length > 0 && (isWhitespaceText(segment[0]) || isBr(segment[0]))) {
        segment.shift();
      }
      while (segment.length > 0 && (isWhitespaceText(segment[segment.length - 1]) || isBr(segment[segment.length - 1]))) {
        segment.pop();
      }
      if (segment.length === 0) {
        return;
      }
      if (segment.length === 1 && segment[0].nodeType === Node.ELEMENT_NODE) {
        walk(segment[0]);
        return;
      }
      var anchorParts = splitSegmentAroundAnchors(segment);
      if (anchorParts) {
        for (var partIndex = 0; partIndex < anchorParts.length; partIndex++) {
          flushSegment(parent, anchorParts[partIndex]);
        }
        return;
      }
      var text = visibleTextOfNodes(segment);
      if (normalizeText(text).length < 2) {
        return;
      }
      if (!shouldAllowCollectMutation(parent, onlyNearViewport)) {
        diagnostics.rejectedByViewport++;
        return;
      }
      if (containsAnchor(segment)) {
        for (var anchorIndex = 0; anchorIndex < segment.length; anchorIndex++) {
          var anchorPart = segment[anchorIndex];
          if (anchorPart.nodeType === Node.ELEMENT_NODE) {
            walk(anchorPart);
          }
        }
        return;
      }
      var wrapper = createInlineWrapper(parent, segment);
      if (!wrapper) {
        for (var index = 0; index < segment.length; index++) {
          var loosePart = segment[index];
          if (loosePart.nodeType === Node.TEXT_NODE) {
            var looseText = normalizeText(loosePart.textContent);
            if (looseText.length >= 2 && loosePart.parentNode) {
              var textWrapper = document.createElement('span');
              textWrapper.setAttribute('data-aira-translation-wrap', 'true');
              loosePart.parentNode.insertBefore(textWrapper, loosePart);
              textWrapper.appendChild(loosePart);
              addBlock(textWrapper, looseText);
            }
          } else if (loosePart.nodeType === Node.ELEMENT_NODE) {
            walk(loosePart);
          }
        }
        return;
      }
      addBlock(wrapper, text);
    }
    function walkMixed(parent) {
      var children = Array.prototype.slice.call(parent.childNodes);
      var run = [];
      function flush() {
        if (run.length === 0) {
          return;
        }
        var segments = segmentRunByBrBr(run);
        for (var i = 0; i < segments.length; i++) {
          flushSegment(parent, segments[i]);
        }
        run = [];
      }
      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (!child.parentNode) {
          continue;
        }
        if (isInlineish(child)) {
          run.push(child);
        } else if (child.nodeType === Node.ELEMENT_NODE) {
          flush();
          walk(child);
        }
      }
      flush();
    }
    function walk(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE) {
        return;
      }
      var tag = tagNameOf(element);
      if (tag === 'iframe') {
        if (shouldSkipElement(element) || hasSkippedAncestor(element) || isIgnoredBySiteRule(element)) {
          diagnostics.rejectedByElement++;
          return;
        }
        try {
          if (element.contentDocument && element.contentDocument.body) {
            walk(element.contentDocument.body);
          }
        } catch (ignoreFrame) {
        }
        return;
      }
      if (shouldSkipElement(element) || hasSkippedAncestor(element) || isCodePre(element) || isIgnoredBySiteRule(element)) {
        diagnostics.rejectedByElement++;
        return;
      }
      if (isLeafBlock(element)) {
        if (typeof element.querySelector === 'function' && element.querySelector('a, button, [role="button"], [role="link"]')) {
          if (onlyNearViewport && !isNearViewport(element)) {
            diagnostics.rejectedByViewport++;
            walkShadow(element);
            return;
          }
          walkMixed(element);
          walkShadow(element);
          return;
        }
        addBlock(element, visibleTextOfElement(element));
        walkShadow(element);
        return;
      }
      if (hasBlockChild(element) || hasBrBrSeparator(element)) {
        if (onlyNearViewport && !isNearViewport(element)) {
          diagnostics.rejectedByViewport++;
          walkShadow(element);
          return;
        }
        walkMixed(element);
        walkShadow(element);
        return;
      }
      var text = visibleTextOfElement(element);
      if (normalizeText(text).length > 0) {
        if (typeof element.querySelector === 'function' &&
          element.querySelector('a, button, [role="button"], [role="link"]')) {
          if (onlyNearViewport && !isNearViewport(element)) {
            diagnostics.rejectedByViewport++;
            walkShadow(element);
            return;
          }
          walkMixed(element);
          walkShadow(element);
          return;
        }
        addBlock(element, text);
        walkShadow(element);
        return;
      }
      for (var i = 0; i < element.children.length; i++) {
        walk(element.children[i]);
      }
      walkShadow(element);
    }
    function walkShadow(element) {
      if (!element.shadowRoot) {
        return;
      }
      for (var i = 0; i < element.shadowRoot.children.length; i++) {
        walk(element.shadowRoot.children[i]);
      }
    }
    function isRuleTargetVisible(element) {
      if (isNearViewport(element)) {
        return true;
      }
      var children = element && element.children ? element.children : [];
      var limit = Math.min(children.length, 6);
      for (var i = 0; i < limit; i++) {
        if (isNearViewport(children[i])) {
          return true;
        }
      }
      return false;
    }
    function appendSiteRuleBlocks(scope) {
      var rule = matchSiteRule(String(location.href || ''));
      if (!rule || !String(rule.selector || '').trim()) {
        return;
      }
      var selectors = expandSiteSelectors(rule.selector);
      var matches = [];
      for (var i = 0; i < selectors.length; i++) {
        collectSiteMatches(scope, selectors[i], matches);
        collectSiteMatchesInShadows(scope, selectors[i], matches);
      }
      for (var j = 0; j < matches.length; j++) {
        var element = matches[j];
        if (!element || shouldSkipElement(element) || hasSkippedAncestor(element) || isIgnoredBySiteRule(element) || isKeptBySiteRule(element)) {
          continue;
        }
        if (onlyNearViewport && !isRuleTargetVisible(element)) {
          continue;
        }
        applyRuleStyle(element, rule.selectStyle);
        if (element.parentElement) {
          applyRuleStyle(element.parentElement, rule.parentStyle);
        }
        addBlock(element, visibleTextOfElement(element), true);
      }
    }
    walk(root || document.body || document.documentElement);
    appendSiteRuleBlocks(root || document.body || document.documentElement);
    return blocks;
  }
  function markPendingNode(node) {
    if (!node || !node.parentElement) {
      return;
    }
    var parent = node.parentElement;
    if (shouldSkipElement(parent) || hasSkippedAncestor(parent) || isChromeContainer(parent) || !isNearViewport(parent)) {
      return;
    }
    var text = normalizeText(node.textContent);
    if (text.length < 2 || isLikelyChromeText(text, parent)) {
      return;
    }
    var block = closestElement(parent, 'p, h1, h2, h3, h4, h5, h6, li, td, th, dd, dt, blockquote, figcaption, caption') || parent;
    var id = getBlockId(block);
    state.pending[id] = true;
  }
  function markPendingBlock(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return false;
    }
    if (shouldSkipElement(element) || hasSkippedAncestor(element) || isCodePre(element)) {
      return false;
    }
    var id = getBlockId(element);
    if (state.translated[id] || state.noopTranslated[id] || hasVisibleTranslationResult(element)) {
      delete state.pending[id];
      return false;
    }
    var text = normalizeText(visibleTextOfElement(element));
    if (text.length < 2 || isLikelyChromeText(text, element)) {
      return false;
    }
    state.pending[id] = true;
    return true;
  }
  function scanLazyObservationCandidates(root, limit) {
    if (!state.visibilityObserver) {
      return 0;
    }
    var maxCount = Math.max(20, Number(limit) || 240);
    var observed = 0;
    function observeElement(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE || observed >= maxCount) {
        return;
      }
      if (shouldSkipElement(element) || hasSkippedAncestor(element) || isCodePre(element)) {
        return;
      }
      var text = normalizeText(visibleTextOfElement(element));
      if (text.length < 2 || noLetterPattern.test(text) || isLikelyChromeText(text, element) || isTargetLanguageText(text)) {
        return;
      }
      var id = getBlockId(element);
      if (state.observedLazyBlocks[id] || state.translated[id] || state.noopTranslated[id] || hasVisibleTranslationResult(element)) {
        return;
      }
      state.observedLazyBlocks[id] = true;
      try {
        state.visibilityObserver.observe(element);
        observed++;
      } catch (ignoreObserve) {
      }
    }
    function walk(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE || observed >= maxCount) {
        return;
      }
      if (shouldSkipElement(element) || hasSkippedAncestor(element) || isCodePre(element)) {
        return;
      }
      var tag = tagNameOf(element);
      if (tag === 'iframe') {
        try {
          if (element.contentDocument && element.contentDocument.body) {
            walk(element.contentDocument.body);
          }
        } catch (ignoreFrame) {
        }
        return;
      }
      if (isLeafBlock(element)) {
        observeElement(element);
        return;
      }
      if (hasBlockChild(element) || hasBrBrSeparator(element)) {
        for (var childIndex = 0; childIndex < element.children.length && observed < maxCount; childIndex++) {
          walk(element.children[childIndex]);
        }
        return;
      }
      observeElement(element);
    }
    walk(root || document.body || document.documentElement);
    return observed;
  }
  function collectTextNodes(root) {
    var results = [];
    if (!root) {
      return results;
    }
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        var parent = node.parentElement;
        if (shouldSkipElement(parent) || !isNearViewport(parent)) {
          return NodeFilter.FILTER_REJECT;
        }
        var text = normalizeText(node.textContent);
        if (text.length < 2 || isLikelyChromeText(text, parent)) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var current = walker.nextNode();
    while (current) {
      results.push(current);
      current = walker.nextNode();
    }
    return results;
  }
  function buildPayload(items, diagnostics) {
    if (diagnostics) {
      var doc = document.documentElement || {};
      var body = document.body || {};
      var viewportHeight = window.innerHeight || doc.clientHeight || 0;
      var scrollHeight = Math.max(doc.scrollHeight || 0, body.scrollHeight || 0);
      diagnostics.viewportHeight = viewportHeight;
      diagnostics.scrollHeight = scrollHeight;
      diagnostics.pageScrollable = scrollHeight > viewportHeight + 240;
    }
    return JSON.stringify({
      url: location.href,
      lang: document.documentElement.lang || '',
      title: document.title || '',
      items: items,
      diagnostics: diagnostics || null
    });
  }
  function buildTextItem(node, order) {
    var text = normalizeText(node.textContent);
    var id = getNodeId(node);
    var parent = node.parentElement;
    var rect = parent ? parent.getBoundingClientRect() : { top: 0 };
    state.originals[id] = text;
    return {
      id: id,
      text: text,
      charLength: text.length,
      order: order,
      score: Math.floor(contentScore(node)),
      nearViewport: parent ? isNearViewport(parent) : false,
      top: Math.floor(rect.top || 0)
    };
  }
  function splitTextIntoChunks(text, maxChars) {
    var normalized = normalizeText(text);
    if (normalized.length <= maxChars) {
      return [normalized];
    }
    var chunks = [];
    var remaining = normalized;
    while (remaining.length > maxChars) {
      var cut = -1;
      var searchWindow = remaining.substring(0, maxChars + 1);
      var marks = ['. ', '! ', '? ', '; ', ': ', '。', '！', '？', '；', '：', ', ', '，'];
      for (var i = 0; i < marks.length; i++) {
        var markIndex = searchWindow.lastIndexOf(marks[i]);
        if (markIndex > Math.floor(maxChars * 0.45)) {
          cut = markIndex + marks[i].length;
          break;
        }
      }
      if (cut < 0) {
        var spaceIndex = searchWindow.lastIndexOf(' ');
        cut = spaceIndex > Math.floor(maxChars * 0.45) ? spaceIndex + 1 : maxChars;
      }
      chunks.push(remaining.substring(0, cut).trim());
      remaining = remaining.substring(cut).trim();
    }
    if (remaining.length > 0) {
      chunks.push(remaining);
    }
    return chunks.filter(function (chunk) {
      return chunk.length > 0;
    });
  }
  function ensureChunkedTextNodes(node, maxChars) {
    var text = normalizeText(node.textContent);
    if (text.length <= maxChars || !node.parentNode) {
      return [node];
    }
    var chunks = splitTextIntoChunks(text, maxChars);
    if (chunks.length <= 1) {
      return [node];
    }
    var parent = node.parentNode;
    var created = [];
    for (var index = 0; index < chunks.length; index++) {
      var chunkNode = document.createTextNode(chunks[index]);
      created.push(chunkNode);
      parent.insertBefore(chunkNode, node);
      if (index < chunks.length - 1) {
        parent.insertBefore(document.createTextNode(' '), node);
      }
    }
    parent.removeChild(node);
    delete node.__airaTranslationId;
    return created;
  }
  function chunkIdFor(baseId, index, count) {
    return count <= 1 ? baseId : baseId + '~' + index + '~' + count;
  }
  function fullTextForId(id, fallback) {
    var meta = state.chunkMeta[id];
    if (meta && meta.fullText) {
      return meta.fullText;
    }
    return fallback || '';
  }
  function joinChunkTranslations(parts) {
    var result = '';
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i];
      if (result.length > 0 && /[A-Za-z0-9]$/.test(result) && /^[A-Za-z0-9]/.test(part)) {
        result += ' ';
      }
      result += part;
    }
    return result;
  }
  function takeChunkItems(candidates, nodeLimit, charLimit, itemLimit) {
    var items = [];
    var chars = 0;
    var remaining = false;
    var cachedHitCount = 0;
    for (var index = 0; index < candidates.length; index++) {
      if (items.length >= nodeLimit || chars >= charLimit) {
        remaining = true;
        break;
      }
      var candidate = candidates[index];
      var chunks = splitTextIntoChunks(candidate.text, itemLimit);
      var baseId = getBlockId(candidate.element);
      if (state.translated[baseId] && state.originals[baseId] === candidate.text) {
        continue;
      }
      if (hasVisibleTranslationResult(candidate.element) && state.originals[baseId] === candidate.text) {
        continue;
      }
      for (var part = 0; part < chunks.length; part++) {
        if (items.length >= nodeLimit) {
          remaining = true;
          break;
        }
        var partText = chunks[part];
        var id = chunkIdFor(baseId, part, chunks.length);
        if ((state.translated[id] || state.noopTranslated[id]) && state.originals[id] === partText) {
          continue;
        }
        if (chars > 0 && chars + partText.length > charLimit) {
          remaining = true;
          break;
        }
        state.nodeMap[id] = candidate.element;
        state.originals[id] = partText;
        state.chunkMeta[id] = {
          baseId: baseId,
          index: part,
          count: chunks.length,
          fullText: candidate.text
        };
        var rect = candidate.element.getBoundingClientRect();
        var item = {
          id: id,
          text: partText,
          charLength: partText.length,
          order: candidate.order,
          score: Math.floor(candidate.score || 0),
          nearViewport: candidate.nearViewport === true,
          top: Math.floor(rect.top || candidate.top || 0)
        };
        var cached = getCachedTranslation(partText);
        if (cached.length > 0) {
          item.cachedTranslatedText = cached;
          cachedHitCount++;
        }
        items.push(item);
        chars += partText.length;
      }
      if (remaining) {
        break;
      }
    }
    return {
      items: items,
      chars: chars,
      remaining: remaining,
      cachedHitCount: cachedHitCount
    };
  }
  function publishChunkSelection(items, chars, remaining, cachedHitCount, diagnostics) {
    diagnostics.cachedHitCount += cachedHitCount;
    diagnostics.candidateCount = remaining ? items.length + 1 : items.length;
    diagnostics.selectedCount = items.length;
    diagnostics.selectedChars = chars;
    diagnostics.acceptedTextNodes = items.length;
    return buildPayload(items, diagnostics);
  }
  function extractViewportBatch(limitNodes, limitChars, mode, itemLimit) {
    var nodeLimit = Math.max(1, Number(limitNodes) || 80);
    var charLimit = Math.max(100, Number(limitChars) || 6000);
    var safeItemLimit = Math.max(200, Number(itemLimit) || 500);
    var diagnostics = {
      mode: mode,
      totalTextNodes: 0,
      acceptedTextNodes: 0,
      rejectedByElement: 0,
      rejectedByText: 0,
      rejectedByViewport: 0,
      rejectedByScore: 0,
      skippedTranslated: 0,
      cachedHitCount: 0,
      candidateCount: 0,
      strongCandidateCount: 0,
      scoreFloor: 0,
      selectedCount: 0,
      selectedChars: 0,
      limitNodes: nodeLimit,
      limitChars: charLimit,
      maxItemChars: safeItemLimit,
      pendingCount: Object.keys(state.pending).length
    };
    var candidates = collectTranslationBlocks(document.body || document.documentElement, diagnostics, { onlyNearViewport: true })
      .filter(function (candidate) {
        if (!candidate.nearViewport) {
          diagnostics.rejectedByViewport++;
          return false;
        }
        return true;
      });
    diagnostics.strongCandidateCount = candidates.filter(function (candidate) {
      return candidate.score >= 80;
    }).length;
    candidates.sort(function (left, right) {
      var topDiff = left.top - right.top;
      return topDiff !== 0 ? topDiff : right.score - left.score;
    });
    var taken = takeChunkItems(candidates, nodeLimit, charLimit, safeItemLimit);
    return publishChunkSelection(taken.items, taken.chars, taken.remaining, taken.cachedHitCount, diagnostics);
  }
  function extractPageQueue(limitNodes, limitChars, maxItemChars) {
    return extractViewportBatch(limitNodes, limitChars, 'block_queue', maxItemChars);
  }
  function extractVisibleBatch(limitNodes, limitChars) {
    return extractViewportBatch(limitNodes, limitChars, 'visible_blocks', 500);
  }
  function extractPendingBatch(limitNodes, limitChars) {
    var ids = Object.keys(state.pending);
    var nodeLimit = Math.max(1, Number(limitNodes) || 80);
    var charLimit = Math.max(100, Number(limitChars) || 6000);
    var diagnostics = {
      mode: 'pending_batch',
      totalTextNodes: ids.length,
      acceptedTextNodes: 0,
      rejectedByElement: 0,
      rejectedByText: 0,
      rejectedByViewport: 0,
      rejectedByScore: 0,
      skippedTranslated: 0,
      cachedHitCount: 0,
      candidateCount: 0,
      strongCandidateCount: 0,
      scoreFloor: 0,
      selectedCount: 0,
      selectedChars: 0,
      limitNodes: nodeLimit,
      limitChars: charLimit,
      maxItemChars: 500,
      pendingCount: ids.length
    };
    if (ids.length === 0) {
      return publishChunkSelection([], 0, 0, 0, diagnostics);
    }
    state.pending = {};
    if (Date.now() - state.lastScrollAt < 180) {
      for (var deferredIndex = 0; deferredIndex < ids.length; deferredIndex++) {
        state.pending[ids[deferredIndex]] = true;
      }
      scheduleSignal(520);
      return publishChunkSelection([], 0, 0, 0, diagnostics);
    }
    var candidates = [];
    for (var index = 0; index < ids.length; index++) {
      var id = ids[index];
      var element = state.nodeMap[id];
      if (!element || element.nodeType !== Node.ELEMENT_NODE || !element.parentNode || isOwnTranslationNode(element)) {
        diagnostics.rejectedByElement++;
        continue;
      }
      if (state.translated[id] || state.noopTranslated[id] || hasVisibleTranslationResult(element)) {
        diagnostics.skippedTranslated++;
        continue;
      }
      if (!isNearViewport(element)) {
        diagnostics.rejectedByViewport++;
        if (state.visibilityObserver && !state.observedLazyBlocks[id]) {
          state.observedLazyBlocks[id] = true;
          try {
            state.visibilityObserver.observe(element);
          } catch (ignoreObserve) {
          }
        }
        continue;
      }
      var text = normalizeText(visibleTextOfElement(element));
      if (text.length < 2 || noLetterPattern.test(text) || isTargetLanguageText(text) || isLikelyChromeText(text, element)) {
        diagnostics.rejectedByText++;
        continue;
      }
      candidates.push({
        element: element,
        text: text,
        order: index,
        score: 100,
        nearViewport: true,
        top: 0
      });
      diagnostics.acceptedTextNodes++;
    }
    var taken = takeChunkItems(candidates, nodeLimit, charLimit, 500);
    return publishChunkSelection(taken.items, taken.chars, taken.remaining, taken.cachedHitCount, diagnostics);
  }
  function parseRuntimeItemsPayload(json) {
    try {
      var payload = JSON.parse(String(json || '{}'));
      if (!payload || !Array.isArray(payload.items)) {
        return null;
      }
      return payload;
    } catch (error) {
      return null;
    }
  }
  function markLoading(json) {
    repairLayoutSensitiveTranslationWrappers(document.body || document.documentElement);
    var payload = parseRuntimeItemsPayload(json);
    if (!payload) {
      return 'invalid_payload';
    }
    var runId = payload.runId === undefined || payload.runId === null ? '' : String(payload.runId);
    state.activeLoadingRunId = runId;
    var marked = 0;
    var missingNodeCount = 0;
    var skippedCount = 0;
    var changedTextCount = 0;
    for (var i = 0; i < payload.items.length; i++) {
      var item = payload.items[i];
      var id = String(item.id || '');
      var node = state.nodeMap[id];
      if (!id || !node || !node.parentElement) {
        missingNodeCount++;
        continue;
      }
      var original = normalizeText(item.text || state.originals[id] || visibleTextOfElement(node));
      if (!currentTextMatchesItem(node, fullTextForId(id, original))) {
        changedTextCount++;
        continue;
      }
      if (state.translated[id] || state.noopTranslated[id]) {
        skippedCount++;
        continue;
      }
      var existing = findTranslationResult(node);
      if (existing && !isTransientTranslationResult(existing)) {
        skippedCount++;
        continue;
      }
      state.originals[id] = original;
      var loading = createLoadingResultElement(node, original, runId);
      insertOrUpdateTransientResult(node, loading);
      state.loading[id] = true;
      delete state.failed[id];
      marked++;
    }
    return JSON.stringify({
      requestedCount: payload.items.length,
      markedCount: marked,
      missingNodeCount: missingNodeCount,
      skippedCount: skippedCount,
      changedTextCount: changedTextCount
    });
  }
  function clearLoading(json) {
    var payload = parseRuntimeItemsPayload(json);
    if (!payload) {
      return 'invalid_payload';
    }
    var runId = payload.runId === undefined || payload.runId === null ? '' : String(payload.runId);
    var cleared = 0;
    var missingNodeCount = 0;
    for (var i = 0; i < payload.items.length; i++) {
      var item = payload.items[i];
      var id = String(item.id || '');
      if (!id || !state.nodeMap[id]) {
        missingNodeCount++;
        delete state.loading[id];
        delete state.failed[id];
        continue;
      }
      if (removeTransientResultById(id, runId)) {
        cleared++;
      }
    }
    return JSON.stringify({
      requestedCount: payload.items.length,
      clearedCount: cleared,
      missingNodeCount: missingNodeCount
    });
  }
  function markFailed(json) {
    repairLayoutSensitiveTranslationWrappers(document.body || document.documentElement);
    var payload = parseRuntimeItemsPayload(json);
    if (!payload) {
      return 'invalid_payload';
    }
    var runId = payload.runId === undefined || payload.runId === null ? '' : String(payload.runId);
    var message = normalizeText(payload.message || airaTranslationFailedLabel);
    var failed = 0;
    var missingNodeCount = 0;
    var skippedCount = 0;
    var changedTextCount = 0;
    for (var i = 0; i < payload.items.length; i++) {
      var item = payload.items[i];
      var id = String(item.id || '');
      var node = state.nodeMap[id];
      if (!id || !node || !node.parentElement) {
        missingNodeCount++;
        delete state.loading[id];
        delete state.failed[id];
        continue;
      }
      var original = normalizeText(item.text || state.originals[id] || visibleTextOfElement(node));
      if (!currentTextMatchesItem(node, fullTextForId(id, original))) {
        changedTextCount++;
        removeTransientResultById(id);
        continue;
      }
      var existing = findTranslationResult(node);
      if (existing && !isTransientTranslationResult(existing)) {
        skippedCount++;
        delete state.loading[id];
        delete state.failed[id];
        continue;
      }
      if (existing && runId.length > 0) {
        var existingRunId = String(existing.getAttribute('data-aira-loading-run-id') || '');
        if (existingRunId.length > 0 && existingRunId !== runId) {
          skippedCount++;
          continue;
        }
      }
      var failedResult = createFailedResultElement(node, original, message, runId);
      insertOrUpdateTransientResult(node, failedResult);
      state.originals[id] = original;
      delete state.loading[id];
      state.failed[id] = message;
      failed++;
    }
    return JSON.stringify({
      requestedCount: payload.items.length,
      failedCount: failed,
      missingNodeCount: missingNodeCount,
      skippedCount: skippedCount,
      changedTextCount: changedTextCount
    });
  }
  function clearTransientStates() {
    var ids = {};
    Object.keys(state.loading).forEach(function (id) {
      ids[id] = true;
    });
    Object.keys(state.failed).forEach(function (id) {
      ids[id] = true;
    });
    var cleared = 0;
    Object.keys(ids).forEach(function (id) {
      if (removeTransientResultById(id)) {
        cleared++;
      }
    });
    state.loading = {};
    state.failed = {};
    state.activeLoadingRunId = 0;
    return String(cleared);
  }
  function applyTranslations(json) {
    repairLayoutSensitiveTranslationWrappers(document.body || document.documentElement);
    var payload;
    try {
      payload = JSON.parse(String(json || '{}'));
    } catch (error) {
      return 'parse_error';
    }
    if (!payload || !Array.isArray(payload.items)) {
      return 'invalid_payload';
    }
    var applied = 0;
    var appliedIds = [];
    var missingNodeCount = 0;
    var invalidTextCount = 0;
    var changedTextCount = 0;
    var unchangedTextCount = 0;
    for (var i = 0; i < payload.items.length; i++) {
      var item = payload.items[i];
      var node = state.nodeMap[item.id];
      if (!node) {
        missingNodeCount++;
        delete state.loading[item.id];
        delete state.failed[item.id];
        continue;
      }
      if (typeof item.translatedText !== 'string' || item.translatedText.trim().length === 0) {
        invalidTextCount++;
        removeTransientResultById(item.id);
        continue;
      }
      var original = state.originals[item.id] || '';
      var translatedText = normalizeText(item.translatedText);
      var meta = state.chunkMeta[item.id];
      var comparableSource = fullTextForId(item.id, original);
      if (comparableSource.length > 0 && !currentTextMatchesItem(node, comparableSource)) {
        changedTextCount++;
        removeTransientResultById(item.id);
        continue;
      }
      if ((!meta || meta.count <= 1) && original.length > 0 &&
        normalizeTranslationComparableText(translatedText) === normalizeTranslationComparableText(original)) {
        unchangedTextCount++;
        state.noopTranslated[item.id] = true;
        state.translated[item.id] = true;
        if (meta) {
          state.noopTranslated[meta.baseId] = true;
          state.translated[meta.baseId] = true;
          state.originals[meta.baseId] = meta.fullText;
        }
        putCachedTranslation(original, translatedText);
        removeTransientResultById(item.id);
        applied++;
        appliedIds.push(String(item.id));
        continue;
      }
      putCachedTranslation(original, translatedText);
      state.translated[item.id] = true;
      state.noopTranslated[item.id] = false;
      delete state.loading[item.id];
      delete state.failed[item.id];
      if (meta && meta.count > 1) {
        state.chunkTranslations[item.id] = translatedText;
        var ready = [];
        var complete = true;
        for (var partIndex = 0; partIndex < meta.count; partIndex++) {
          var partId = chunkIdFor(meta.baseId, partIndex, meta.count);
          var partTranslation = state.chunkTranslations[partId];
          if (!partTranslation) {
            complete = false;
            break;
          }
          ready.push(partTranslation);
        }
        if (!complete) {
          applied++;
          appliedIds.push(String(item.id));
          continue;
        }
        var joined = joinChunkTranslations(ready);
        if (normalizeTranslationComparableText(joined) === normalizeTranslationComparableText(meta.fullText)) {
          unchangedTextCount++;
          state.noopTranslated[meta.baseId] = true;
          state.translated[meta.baseId] = true;
          state.originals[meta.baseId] = meta.fullText;
          removeTransientResultById(item.id);
        } else {
          insertOrUpdateTranslationResult(node, meta.fullText, joined);
          putCachedTranslation(meta.fullText, joined);
          state.translated[meta.baseId] = true;
          state.noopTranslated[meta.baseId] = false;
          state.originals[meta.baseId] = meta.fullText;
        }
        applied++;
        appliedIds.push(String(item.id));
        continue;
      }
      insertOrUpdateTranslationResult(node, original, translatedText);
      if (meta) {
        state.translated[meta.baseId] = true;
        state.originals[meta.baseId] = meta.fullText;
      }
      applied++;
      appliedIds.push(String(item.id));
    }
    return JSON.stringify({
      requestedCount: payload.items.length,
      appliedCount: applied,
      appliedIds: appliedIds,
      missingNodeCount: missingNodeCount,
      invalidTextCount: invalidTextCount,
      changedTextCount: changedTextCount,
      unchangedTextCount: unchangedTextCount
    });
  }
  function restoreOriginals() {
    state.displayMode = 'original';
    repairLayoutSensitiveTranslationWrappers(document.body || document.documentElement);
    clearTransientStates();
    var restored = 0;
    Object.keys(state.originals).forEach(function (id) {
      var node = state.nodeMap[id];
      if (!node) {
        return;
      }
      var result = findTranslationResult(node);
      if (result) {
        if (isTransientTranslationResult(result)) {
          result.remove();
        } else {
          result.style.setProperty('display', 'none', 'important');
        }
      }
      showSourceElement(node);
      releaseSourceContent(node);
      state.translated[id] = false;
      state.noopTranslated[id] = false;
      restored++;
    });
    return String(restored);
  }
  function showBilingualTranslations() {
    state.displayMode = 'bilingual';
    repairLayoutSensitiveTranslationWrappers(document.body || document.documentElement);
    var shown = 0;
    Object.keys(state.originals).forEach(function (id) {
      var node = state.nodeMap[id];
      if (!node) {
        return;
      }
      var result = findTranslationResult(node);
      if (!result || isTransientTranslationResult(result)) {
        return;
      }
      var translatedText = String(result.getAttribute('data-aira-translated-text') || '').trim();
      if (translatedText.length === 0 && normalizeText(result.textContent).length === 0) {
        return;
      }
      styleTranslationResultElement(result, node, 'bilingual');
      showSourceElement(node);
      releaseSourceContent(node);
      state.translated[id] = true;
      state.noopTranslated[id] = false;
      shown++;
    });
    return String(shown);
  }
  function showTranslationOnly() {
    state.displayMode = 'translation_only';
    repairLayoutSensitiveTranslationWrappers(document.body || document.documentElement);
    var shown = 0;
    Object.keys(state.originals).forEach(function (id) {
      var node = state.nodeMap[id];
      if (!node) {
        return;
      }
      var result = findTranslationResult(node);
      if (!result || isTransientTranslationResult(result)) {
        return;
      }
      var translatedText = String(result.getAttribute('data-aira-translated-text') || '').trim();
      if (translatedText.length === 0 && normalizeText(result.textContent).length === 0) {
        return;
      }
      styleTranslationResultElement(result, node, 'translation_only');
      if (translationUsesHost(node)) {
        showSourceElement(node);
        hideSourceContent(node);
      } else {
        hideSourceElement(node);
      }
      result.setAttribute('data-aira-display-mode', 'translation_only');
      state.translated[id] = true;
      state.noopTranslated[id] = false;
      shown++;
    });
    return String(shown);
  }
  function clear() {
    clearTransientStates();
    Object.keys(state.originals).forEach(function (id) {
      var node = state.nodeMap[id];
      if (!node) {
        return;
      }
      var result = findTranslationResult(node);
      if (result) {
        result.remove();
      }
      showSourceElement(node);
      releaseSourceContent(node);
    });
    state.nodeMap = {};
    state.originals = {};
    state.translated = {};
    state.noopTranslated = {};
    state.pending = {};
    state.loading = {};
    state.failed = {};
    state.chunkMeta = {};
    state.chunkTranslations = {};
    state.activeLoadingRunId = 0;
    state.nextId = 1;
    return 'cleared';
  }
  function configureCache(namespace) {
    state.cacheNamespace = normalizeText(namespace);
    rememberTargetLanguage(namespace);
    hydrateTranslationCacheFromDom();
    return 'cache_configured';
  }
  function scheduleSignal(debounceMs) {
    if (state.debounceTimer) {
      clearTimeout(state.debounceTimer);
    }
    state.debounceTimer = setTimeout(function () {
      state.pageSignalVersion++;
    }, Math.max(200, Number(debounceMs) || 800));
  }
  function isOwnTranslationNode(node) {
    var current = node && node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
    while (current && current.nodeType === Node.ELEMENT_NODE) {
      if (current.getAttribute && (
        current.getAttribute('data-aira-translation-result') === 'true' ||
        current.getAttribute('data-aira-translation-wrap') === 'true' ||
        current.getAttribute('data-aira-translation-loading') === 'true' ||
        (current.classList && current.classList.contains('aira-translation-source'))
      )) {
        return true;
      }
      if (current.classList && current.classList.contains('aira-translation-result')) {
        return true;
      }
      if (current === document.body || current === document.documentElement) {
        return false;
      }
      current = current.parentElement;
    }
    return false;
  }
  function userIsScrolling() {
    return Date.now() - state.lastScrollAt < 180;
  }
  function queueMutationNode(node) {
    if (!node || isOwnTranslationNode(node) || state.queuedMutationNodes.length >= 160) {
      return;
    }
    state.queuedMutationNodes.push(node);
  }
  function markPendingNodeCheap(node) {
    if (!node || !node.parentElement || isOwnTranslationNode(node)) {
      return false;
    }
    var parent = node.parentElement;
    if (shouldSkipElement(parent) || hasSkippedAncestor(parent) || isCodePre(parent)) {
      return false;
    }
    var text = normalizeText(node.textContent);
    if (text.length < 2 || isLikelyChromeText(text, parent) || isTargetLanguageText(text)) {
      return false;
    }
    var block = closestElement(parent, 'p, h1, h2, h3, h4, h5, h6, li, td, th, dd, dt, blockquote, figcaption, caption') || parent;
    if (!block || shouldSkipElement(block) || isOwnTranslationNode(block)) {
      return false;
    }
    state.pending[getBlockId(block)] = true;
    return true;
  }
  function scheduleMutationFlush() {
    if (state.mutationFlushTimer) {
      return;
    }
    state.mutationFlushTimer = setTimeout(function () {
      state.mutationFlushTimer = 0;
      if (!state.observer) {
        state.queuedMutationNodes = [];
        return;
      }
      if (userIsScrolling()) {
        scheduleMutationFlush();
        return;
      }
      flushQueuedMutations();
    }, 240);
  }
  function flushQueuedMutations() {
    var nodes = state.queuedMutationNodes;
    state.queuedMutationNodes = [];
    var marked = 0;
    var budget = 48;
    for (var i = 0; i < nodes.length && budget > 0; i++) {
      var node = nodes[i];
      if (!node || isOwnTranslationNode(node)) {
        continue;
      }
      if (node.nodeType === Node.TEXT_NODE) {
        if (markPendingNodeCheap(node)) {
          marked++;
          budget--;
        }
        continue;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) {
        continue;
      }
      if (node.shadowRoot) {
        observeDynamicRoot(node.shadowRoot);
      }
      var observed = scanLazyObservationCandidates(node, Math.min(24, budget));
      budget -= Math.max(1, observed);
      marked += observed;
    }
    if (nodes.length > 48) {
      scheduleMutationFlush();
    }
    if (marked > 0) {
      scheduleSignal(520);
    }
  }
  function scheduleViewportRefresh() {
    if (state.viewportRefreshTimer) {
      return;
    }
    state.viewportRefreshTimer = setTimeout(function () {
      state.viewportRefreshTimer = 0;
      if (!state.observer) {
        return;
      }
      if (userIsScrolling()) {
        scheduleViewportRefresh();
        return;
      }
      var observed = scanLazyObservationCandidates(document.body || document.documentElement, 80);
      if (observed > 0) {
        scheduleSignal(420);
      }
    }, 320);
  }
  function scheduleIdleWork(work, delayMs) {
    if (typeof requestIdleCallback === 'function') {
      requestIdleCallback(function () {
        work();
      }, { timeout: Math.max(240, Number(delayMs) || 700) });
      return;
    }
    setTimeout(work, Math.max(80, Number(delayMs) || 180));
  }
  function scheduleStartupScan() {
    scheduleIdleWork(function () {
      if (!state.observer) {
        return;
      }
      if (userIsScrolling()) {
        setTimeout(scheduleStartupScan, 280);
        return;
      }
      var observed = scanLazyObservationCandidates(document.body || document.documentElement, 400);
      state.startupScanPasses++;
      if (observed >= 400 && state.startupScanPasses < 8) {
        scheduleStartupScan();
        return;
      }
      attachNestedRoots(document.body || document.documentElement);
    }, 700);
  }
  function startObserver(debounceMs) {
    stopObserver();
    if (!document.body) {
      return 'missing_body';
    }
    state.visibilityObserver = typeof IntersectionObserver === 'function'
      ? new IntersectionObserver(function (entries) {
        var marked = 0;
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i];
          if (entry && entry.isIntersecting && markPendingBlock(entry.target)) {
            marked++;
          }
        }
        if (marked > 0) {
          scheduleSignal(debounceMs);
        }
      }, { threshold: 0.01, rootMargin: '480px 0px 480px 0px' })
      : null;
    state.observer = new MutationObserver(function (mutations) {
      var queued = 0;
      for (var i = 0; i < mutations.length; i++) {
        var mutation = mutations[i];
        if (mutation.type === 'characterData') {
          if (!isOwnTranslationNode(mutation.target)) {
            queueMutationNode(mutation.target);
            queued++;
          }
          continue;
        }
        if (mutation.type !== 'childList') {
          continue;
        }
        var added = mutation.addedNodes;
        for (var j = 0; j < added.length; j++) {
          var node = added[j];
          if (isOwnTranslationNode(node)) {
            continue;
          }
          queueMutationNode(node);
          queued++;
        }
      }
      if (queued > 0) {
        scheduleMutationFlush();
      }
    });
    state.observer.observe(document.body, { childList: true, subtree: true, characterData: true });
    state.clickListener = function () {
      scheduleViewportRefresh();
    };
    state.toggleListener = function () {
      scheduleViewportRefresh();
    };
    state.scrollListener = function () {
      state.lastScrollAt = Date.now();
    };
    state.loadListener = function (event) {
      var target = event && event.target;
      if (!target || tagNameOf(target) !== 'iframe') {
        return;
      }
      try {
        if (target.contentDocument && target.contentDocument.body) {
          observeDynamicRoot(target.contentDocument.body);
        }
      } catch (ignoreFrame) {
      }
      scheduleViewportRefresh();
    };
    document.addEventListener('click', state.clickListener, true);
    document.addEventListener('toggle', state.toggleListener, true);
    window.addEventListener('scroll', state.scrollListener, { capture: true, passive: true });
    window.addEventListener('load', state.loadListener, true);
    scheduleStartupScan();
    return 'observer_started';
  }
  function stopObserver() {
    if (state.debounceTimer) {
      clearTimeout(state.debounceTimer);
      state.debounceTimer = 0;
    }
    if (state.mutationFlushTimer) {
      clearTimeout(state.mutationFlushTimer);
      state.mutationFlushTimer = 0;
    }
    if (state.viewportRefreshTimer) {
      clearTimeout(state.viewportRefreshTimer);
      state.viewportRefreshTimer = 0;
    }
    state.queuedMutationNodes = [];
    state.startupScanPasses = 0;
    if (state.observer) {
      state.observer.disconnect();
      state.observer = null;
    }
    if (state.visibilityObserver) {
      state.visibilityObserver.disconnect();
      state.visibilityObserver = null;
    }
    state.observedLazyBlocks = {};
    if (state.clickListener) {
      document.removeEventListener('click', state.clickListener, true);
      state.clickListener = null;
    }
    if (state.toggleListener) {
      document.removeEventListener('toggle', state.toggleListener, true);
      state.toggleListener = null;
    }
    if (state.scrollListener) {
      window.removeEventListener('scroll', state.scrollListener, true);
      state.scrollListener = null;
    }
    if (state.loadListener) {
      window.removeEventListener('load', state.loadListener, true);
      state.loadListener = null;
    }
    return 'observer_stopped';
  }
  function observeDynamicRoot(root) {
    if (!root || !state.observer) {
      return;
    }
    try {
      state.observer.observe(root, { childList: true, subtree: true, characterData: true });
    } catch (ignoreObserve) {
    }
    scanLazyObservationCandidates(root, 800);
  }
  function attachNestedRoots(root) {
    if (!root || typeof root.querySelectorAll !== 'function') {
      return;
    }
    var nodes;
    try {
      nodes = root.querySelectorAll('*');
    } catch (ignoreQuery) {
      return;
    }
    var limit = Math.min(nodes.length, 1200);
    for (var i = 0; i < limit; i++) {
      var el = nodes[i];
      if (el.shadowRoot) {
        observeDynamicRoot(el.shadowRoot);
        attachNestedRoots(el.shadowRoot);
      }
      if (tagNameOf(el) === 'iframe') {
        try {
          if (el.contentDocument && el.contentDocument.body) {
            observeDynamicRoot(el.contentDocument.body);
            attachNestedRoots(el.contentDocument.body);
          }
        } catch (ignoreFrame) {
        }
      }
    }
  }
  function installSpaHooks() {
    if (state.spaHooked) {
      return 'spa_hooked';
    }
    state.spaHooked = true;
    var rawPushState = history.pushState;
    var rawReplaceState = history.replaceState;
    history.pushState = function () {
      var result = rawPushState.apply(this, arguments);
      state.routeSignalVersion++;
      state.pageSignalVersion++;
      return result;
    };
    history.replaceState = function () {
      var result = rawReplaceState.apply(this, arguments);
      state.routeSignalVersion++;
      state.pageSignalVersion++;
      return result;
    };
    window.addEventListener('popstate', function () {
      state.routeSignalVersion++;
      state.pageSignalVersion++;
    });
    window.addEventListener('hashchange', function () {
      state.routeSignalVersion++;
      state.pageSignalVersion++;
    });
    return 'spa_installed';
  }
  function getPageSignalVersion() {
    return String(state.pageSignalVersion);
  }
  function getRouteSignalVersion() {
    return String(state.routeSignalVersion);
  }
  window.${TRANSLATION_RUNTIME_NAME} = {
    installed: true,
    runtimeVersion: '${TRANSLATION_RUNTIME_VERSION}',
    extractVisibleBatch: extractVisibleBatch,
    extractPageQueue: extractPageQueue,
    extractPendingBatch: extractPendingBatch,
    applyTranslations: applyTranslations,
    markLoading: markLoading,
    clearLoading: clearLoading,
    markFailed: markFailed,
    clearTransientStates: clearTransientStates,
    restoreOriginals: restoreOriginals,
    showBilingualTranslations: showBilingualTranslations,
    showTranslationOnly: showTranslationOnly,
    startObserver: startObserver,
    stopObserver: stopObserver,
    installSpaHooks: installSpaHooks,
    getPageSignalVersion: getPageSignalVersion,
    getRouteSignalVersion: getRouteSignalVersion,
    configureCache: configureCache,
    clear: clear
  };
  return 'installed';
})();`;
  }

  buildExtractVisibleBatchScript(limitNodes: number, limitChars: number): string {
    return this.protocolScriptService.buildExtractVisibleBatchScript(limitNodes, limitChars);
  }

  buildExtractPageQueueScript(limitNodes: number, limitChars: number, maxItemChars: number): string {
    return this.protocolScriptService.buildExtractPageQueueScript(limitNodes, limitChars, maxItemChars);
  }

  buildExtractPendingBatchScript(limitNodes: number, limitChars: number): string {
    return this.protocolScriptService.buildExtractPendingBatchScript(limitNodes, limitChars);
  }

  buildApplyTranslationsScript(payloadJson: string): string {
    return this.protocolScriptService.buildApplyTranslationsScript(payloadJson);
  }

  buildMarkLoadingScript(payloadJson: string): string {
    return this.protocolScriptService.buildMarkLoadingScript(payloadJson);
  }

  buildClearLoadingScript(payloadJson: string): string {
    return this.protocolScriptService.buildClearLoadingScript(payloadJson);
  }

  buildMarkFailedScript(payloadJson: string): string {
    return this.protocolScriptService.buildMarkFailedScript(payloadJson);
  }

  buildClearTransientStatesScript(): string {
    return this.protocolScriptService.buildClearTransientStatesScript();
  }

  buildConfigureCacheScript(namespace: string): string {
    return this.protocolScriptService.buildConfigureCacheScript(namespace);
  }

  buildRestoreOriginalsScript(): string {
    return this.protocolScriptService.buildRestoreOriginalsScript();
  }

  buildShowBilingualTranslationsScript(): string {
    return this.protocolScriptService.buildShowBilingualTranslationsScript();
  }

  buildShowTranslationOnlyScript(): string {
    return this.protocolScriptService.buildShowTranslationOnlyScript();
  }

  buildClearScript(): string {
    return this.protocolScriptService.buildClearScript();
  }

  buildStartObserverScript(debounceMs: number): string {
    return this.protocolScriptService.buildStartObserverScript(debounceMs);
  }

  buildStopObserverScript(): string {
    return this.protocolScriptService.buildStopObserverScript();
  }

  buildInstallSpaHooksScript(): string {
    return this.protocolScriptService.buildInstallSpaHooksScript();
  }

  buildGetPageSignalVersionScript(): string {
    return this.protocolScriptService.buildGetPageSignalVersionScript();
  }

  buildGetRouteSignalVersionScript(): string {
    return this.protocolScriptService.buildGetRouteSignalVersionScript();
  }
}
