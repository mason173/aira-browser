import {
  TRANSLATION_RUNTIME_NAME,
  TRANSLATION_RUNTIME_VERSION,
  WebpageTranslationRuntimeProtocolScriptService
} from './WebpageTranslationRuntimeProtocolScriptService';

export class WebpageTranslationRuntimeScriptService {
  private protocolScriptService: WebpageTranslationRuntimeProtocolScriptService =
    new WebpageTranslationRuntimeProtocolScriptService();

  buildInstallScript(): string {
    return `
(function () {
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
    debounceTimer: 0,
    pageSignalVersion: 1,
    routeSignalVersion: 1,
    spaHooked: false,
    nextId: 1
  };
  var inlineTags = {
    '#text': true, a: true, abbr: true, acronym: true, b: true, bdi: true, bdo: true, big: true,
    br: true, cite: true, code: true, del: true, dfn: true, em: true, font: true, i: true,
    ins: true, kbd: true, label: true, mark: true, nobr: true, q: true, rp: true, rt: true,
    ruby: true, s: true, samp: true, small: true, span: true, strong: true, sub: true, sup: true,
    tt: true, u: true, var: true, wbr: true, img: true
  };
  var skipTags = {
    script: true, style: true, noscript: true, input: true, textarea: true, select: true, option: true,
    svg: true, canvas: true, video: true, audio: true, iframe: true, math: true, template: true,
    pre: true, time: true
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
  function findTranslationResult(element) {
    if (!element || !element.parentNode) {
      return null;
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
    if (className.length > 0 && tag !== 'font' && shouldMirrorSourceClass(sourceElement)) {
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
    result.textContent = normalizeText(message).length > 0 ? normalizeText(message) : '翻译失败';
    return result;
  }
  function insertOrUpdateTransientResult(element, result) {
    var existing = findTranslationResult(element);
    if (!existing) {
      if (element.parentNode) {
        element.parentNode.insertBefore(result, element.nextSibling);
      }
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
  function insertOrUpdateTranslationResult(element, originalText, translatedText) {
    var result = findTranslationResult(element);
    if (!result) {
      result = createTranslationResultElement(element, originalText, translatedText);
      if (element.parentNode) {
        element.parentNode.insertBefore(result, element.nextSibling);
      }
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
      result.textContent = translatedText;
      styleTranslationResultElement(result, element, state.displayMode);
    }
    clearTransientIdentity(result);
    result.setAttribute('data-aira-original-text', originalText);
    result.setAttribute('data-aira-translated-text', translatedText);
    if (shouldShowSourceWithTranslation(state.displayMode)) {
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
    if (element.hidden === true ||
      String(element.getAttribute('aria-hidden') || '').toLowerCase() === 'true' ||
      String(element.getAttribute('translate') || '').toLowerCase() === 'no' ||
      element.classList.contains('notranslate') ||
      element.classList.contains('CodeMirror') ||
      element.classList.contains('monaco-editor') ||
      element.classList.contains('ProseMirror') ||
      element.classList.contains('aira-translation-result') ||
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
    var style = window.getComputedStyle(element);
    if (!style || style.display === 'none' || style.visibility === 'hidden' || String(style.opacity || '').trim() === '0') {
      return true;
    }
    if (typeof element.checkVisibility === 'function' && element !== document.body && element !== document.documentElement) {
      try {
        if (!element.checkVisibility()) {
          return true;
        }
      } catch (_error) {
      }
    }
    var rect = element.getBoundingClientRect();
    return element !== document.body && element !== document.documentElement && (rect.width <= 0 || rect.height <= 0);
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
    var rect = element.getBoundingClientRect();
    var viewHeight = window.innerHeight || document.documentElement.clientHeight || 0;
    var viewWidth = window.innerWidth || document.documentElement.clientWidth || 0;
    return rect.bottom >= -160 && rect.right >= -80 && rect.top <= viewHeight + 360 && rect.left <= viewWidth + 80;
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
    function addBlock(element, text) {
      var normalized = normalizeText(text);
      diagnostics.totalTextNodes++;
      if (normalized.length < 2 || noLetterPattern.test(normalized) || isLikelyChromeText(normalized, element)) {
        diagnostics.rejectedByText++;
        return;
      }
      var id = getBlockId(element);
      if (state.translated[id] || state.noopTranslated[id] || hasVisibleTranslationResult(element)) {
        diagnostics.skippedTranslated++;
        return;
      }
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
      var text = visibleTextOfNodes(segment);
      if (normalizeText(text).length < 2) {
        return;
      }
      if (!shouldAllowCollectMutation(parent, onlyNearViewport)) {
        diagnostics.rejectedByViewport++;
        return;
      }
      var wrapper = createInlineWrapper(parent, segment);
      if (!wrapper) {
        diagnostics.rejectedByElement++;
        for (var index = 0; index < segment.length; index++) {
          if (segment[index].nodeType === Node.ELEMENT_NODE) {
            walk(segment[index]);
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
      if (shouldSkipElement(element) || hasSkippedAncestor(element)) {
        diagnostics.rejectedByElement++;
        return;
      }
      var tag = tagNameOf(element);
      if (chromeContainerTags[tag] === true) {
        diagnostics.rejectedByElement++;
        return;
      }
      if (isLeafBlock(element)) {
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
    walk(root || document.body || document.documentElement);
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
    if (shouldSkipElement(element) || hasSkippedAncestor(element) || isChromeContainer(element)) {
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
      if (shouldSkipElement(element) || hasSkippedAncestor(element) || isChromeContainer(element)) {
        return;
      }
      var text = normalizeText(visibleTextOfElement(element));
      if (text.length < 2 || noLetterPattern.test(text) || isLikelyChromeText(text, element)) {
        return;
      }
      var id = getBlockId(element);
      if (state.observedLazyBlocks[id] || state.translated[id] || state.noopTranslated[id] || hasVisibleTranslationResult(element)) {
        return;
      }
      state.observedLazyBlocks[id] = true;
      state.visibilityObserver.observe(element);
      observed++;
    }
    function walk(element) {
      if (!element || element.nodeType !== Node.ELEMENT_NODE || observed >= maxCount) {
        return;
      }
      if (shouldSkipElement(element) || hasSkippedAncestor(element)) {
        return;
      }
      var tag = tagNameOf(element);
      if (chromeContainerTags[tag] === true) {
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
  function extractPageQueue(limitNodes, limitChars, maxItemChars) {
    var nodeLimit = Math.max(1, Number(limitNodes) || 240);
    var charLimit = Math.max(500, Number(limitChars) || 24000);
    var itemLimit = Math.max(200, Number(maxItemChars) || 900);
    var items = [];
    var chars = 0;
    var diagnostics = {
      mode: 'block_queue',
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
      maxItemChars: itemLimit,
      pendingCount: Object.keys(state.pending).length
    };
    var candidates = collectTranslationBlocks(document.body || document.documentElement, diagnostics);
    var scoreFloor = -1000;
    diagnostics.candidateCount = candidates.length;
    diagnostics.strongCandidateCount = candidates.filter(function (candidate) {
      return candidate.score >= 80;
    }).length;
    diagnostics.scoreFloor = scoreFloor;
    candidates.sort(function (left, right) {
      if (left.nearViewport !== right.nearViewport) {
        return left.nearViewport ? -1 : 1;
      }
      if (left.nearViewport && right.nearViewport) {
        var topDiff = left.top - right.top;
        if (topDiff !== 0) {
          return topDiff;
        }
      }
      return left.order - right.order;
    });
    for (var index = 0; index < candidates.length && items.length < nodeLimit && chars < charLimit; index++) {
      var candidate = candidates[index];
      var blockText = candidate.text.length > itemLimit ? candidate.text.substring(0, itemLimit) : candidate.text;
      if (chars > 0 && chars + blockText.length > charLimit) {
        break;
      }
      items.push(buildBlockItem(candidate.element, blockText, candidate.order));
      if (items[items.length - 1].cachedTranslatedText) {
        diagnostics.cachedHitCount++;
      }
      chars += blockText.length;
    }
    diagnostics.acceptedTextNodes = candidates.length;
    diagnostics.selectedCount = items.length;
    diagnostics.selectedChars = chars;
    return buildPayload(items, diagnostics);
  }
  function extractVisibleBatch(limitNodes, limitChars) {
    var nodeLimit = Math.max(1, Number(limitNodes) || 80);
    var charLimit = Math.max(100, Number(limitChars) || 6000);
    var items = [];
    var chars = 0;
    var diagnostics = {
      mode: 'visible_blocks',
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
      maxItemChars: 1500,
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
    diagnostics.candidateCount = candidates.length;
    diagnostics.acceptedTextNodes = candidates.length;
    candidates.sort(function (left, right) {
      var topDiff = left.top - right.top;
      return topDiff !== 0 ? topDiff : right.score - left.score;
    });
    for (var candidateIndex = 0; candidateIndex < candidates.length && items.length < nodeLimit && chars < charLimit; candidateIndex++) {
      var candidate = candidates[candidateIndex];
      var safeText = candidate.text.substring(0, 1500);
      if (chars + safeText.length > charLimit) {
        break;
      }
      items.push(buildBlockItem(candidate.element, safeText, candidate.order));
      if (items[items.length - 1].cachedTranslatedText) {
        diagnostics.cachedHitCount++;
      }
      chars += safeText.length;
    }
    diagnostics.selectedCount = items.length;
    diagnostics.selectedChars = chars;
    return buildPayload(items, diagnostics);
  }
  function extractPendingBatch(limitNodes, limitChars) {
    var nodeLimit = Math.max(1, Number(limitNodes) || 40);
    var charLimit = Math.max(100, Number(limitChars) || 3000);
    var items = [];
    var chars = 0;
    var ids = Object.keys(state.pending);
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
      candidateCount: ids.length,
      strongCandidateCount: 0,
      scoreFloor: 0,
      selectedCount: 0,
      selectedChars: 0,
      limitNodes: nodeLimit,
      limitChars: charLimit,
      maxItemChars: 1500,
      pendingCount: ids.length
    };
    for (var i = 0; i < ids.length && items.length < nodeLimit && chars < charLimit; i++) {
      var id = ids[i];
      var element = state.nodeMap[id];
      if (!element || !element.parentElement) {
        delete state.pending[id];
        continue;
      }
      if (shouldSkipElement(element) || hasSkippedAncestor(element) || isChromeContainer(element)) {
        diagnostics.rejectedByElement++;
        delete state.pending[id];
        continue;
      }
      if (!isNearViewport(element)) {
        diagnostics.rejectedByViewport++;
        continue;
      }
      var text = normalizeText(visibleTextOfElement(element));
      var hasVisibleExistingTranslation = hasVisibleTranslationResult(element);
      if (text.length < 2 || isLikelyChromeText(text, element) || state.translated[id] || state.noopTranslated[id] || hasVisibleExistingTranslation) {
        if (state.translated[id] || state.noopTranslated[id] || hasVisibleExistingTranslation) {
          diagnostics.skippedTranslated++;
        } else {
          diagnostics.rejectedByText++;
        }
        delete state.pending[id];
        continue;
      }
      var safeText = text.substring(0, 1500);
      if (chars + safeText.length > charLimit) {
        break;
      }
      state.originals[id] = safeText;
      items.push(buildBlockItem(element, safeText, i));
      if (items[items.length - 1].cachedTranslatedText) {
        diagnostics.cachedHitCount++;
      }
      chars += safeText.length;
      diagnostics.acceptedTextNodes++;
      delete state.pending[id];
    }
    diagnostics.selectedCount = items.length;
    diagnostics.selectedChars = chars;
    return buildPayload(items, diagnostics);
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
      if (!currentTextMatchesItem(node, original)) {
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
    var message = normalizeText(payload.message || '翻译失败');
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
      if (!currentTextMatchesItem(node, original)) {
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
      if (original.length > 0 && !currentTextMatchesItem(node, original)) {
        changedTextCount++;
        removeTransientResultById(item.id);
        continue;
      }
      if (original.length > 0 &&
        normalizeTranslationComparableText(translatedText) === normalizeTranslationComparableText(original)) {
        unchangedTextCount++;
        state.noopTranslated[item.id] = true;
        putCachedTranslation(original, translatedText);
        removeTransientResultById(item.id);
        applied++;
        appliedIds.push(String(item.id));
        continue;
      }
      insertOrUpdateTranslationResult(node, original, translatedText);
      putCachedTranslation(original, translatedText);
      state.translated[item.id] = true;
      state.noopTranslated[item.id] = false;
      delete state.loading[item.id];
      delete state.failed[item.id];
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
      hideSourceElement(node);
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
    });
    state.nodeMap = {};
    state.originals = {};
    state.translated = {};
    state.noopTranslated = {};
    state.pending = {};
    state.loading = {};
    state.failed = {};
    state.activeLoadingRunId = 0;
    state.nextId = 1;
    return 'cleared';
  }
  function configureCache(namespace) {
    state.cacheNamespace = normalizeText(namespace);
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
      }, { threshold: 0.01, rootMargin: '360px 0px 360px 0px' })
      : null;
    state.observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var mutation = mutations[i];
        if (mutation.type === 'characterData') {
          markPendingNode(mutation.target);
        } else if (mutation.type === 'childList') {
          mutation.addedNodes.forEach(function (node) {
            if (node.nodeType === Node.TEXT_NODE) {
              markPendingNode(node);
              return;
            }
            if (node.nodeType === Node.ELEMENT_NODE) {
              scanLazyObservationCandidates(node, 120);
              var nodes = collectTextNodes(node);
              for (var j = 0; j < nodes.length; j++) {
                markPendingNode(nodes[j]);
              }
            }
          });
        }
      }
      scheduleSignal(debounceMs);
    });
    state.observer.observe(document.body, { childList: true, subtree: true, characterData: true });
    state.clickListener = function () {
      scheduleSignal(200);
    };
    state.toggleListener = function () {
      scheduleSignal(100);
    };
    document.addEventListener('click', state.clickListener, true);
    document.addEventListener('toggle', state.toggleListener, true);
    scanLazyObservationCandidates(document.body, 1200);
    return 'observer_started';
  }
  function stopObserver() {
    if (state.debounceTimer) {
      clearTimeout(state.debounceTimer);
      state.debounceTimer = 0;
    }
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
    return 'observer_stopped';
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
