// Resolve the current document at execution time so retained Web registrations also cover redirects.
// DOM discovery is incremental; only the initial load, explicit refresh or queue overflow scans the root.
const AD_BLOCK_COSMETIC_DISCOVERY_SCRIPT: string = `
;(function airaAdBlockDiscoverCosmetics() {
  try { if (window.top !== window) { return; } } catch (error) { return; }
  function documentUrl(value) {
    try {
      var parsed = new URL(String(value || ''));
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') { return ''; }
      parsed.hash = '';
      return parsed.href;
    } catch (error) { return ''; }
  }
  if (!documentUrl(location.href) || !document.documentElement) { return; }
  var existing = window.__airaAdBlockDiscoveryRuntime;
  if (existing && typeof existing.refresh === 'function') { existing.refresh(); return; }

  var maxNodes = 600;
  var maxBatch = 128;
  var maxTokens = 8192;
  var maxTokenLength = 256;
  var maxSelectors = 4096;
  var maxCssChars = 384 * 1024;
  var maxRetries = 8;
  var styleId = 'aira-adblock-discovered-style';
  var pageUrl = '';
  var style = null;
  var observer = null;
  var timer = null;
  var retryWaiting = false;
  var stopped = true;
  var paused = false;
  var listening = false;
  var initialReady = false;
  var retryCount = 0;
  var exhausted = false;
  var lastImmediateAt = -100;
  var scriptletsRequested = false;
  var replaceStyleOnSuccess = true;
  var seenClasses = new Set();
  var seenIds = new Set();
  var pendingClasses = new Set();
  var pendingIds = new Set();
  var selectors = new Set();
  var cssRules = [];
  var cssChars = 0;
  var jobs = [];
  var queuedRoots = new WeakSet();
  var queuedAttributes = new WeakSet();

  function cancelTimer() {
    if (timer !== null) { clearTimeout(timer); timer = null; }
    retryWaiting = false;
  }
  function disconnect() {
    if (observer) { observer.disconnect(); observer = null; }
    cancelTimer();
  }
  function clearStyle() {
    var previous = style || document.getElementById(styleId);
    if (previous && previous.parentNode) {
      try { previous.parentNode.removeChild(previous); } catch (error) {}
    }
    style = null;
    selectors.clear(); cssRules = []; cssChars = 0;
  }
  function schedule(delay, retry) {
    if (stopped || paused || exhausted || timer !== null) { return; }
    retryWaiting = retry === true;
    timer = setTimeout(function () {
      timer = null; retryWaiting = false;
      if (!stopped && !paused && !exhausted) { pass(); }
    }, delay);
  }
  function failed() {
    cancelTimer();
    retryCount += 1;
    if (retryCount > maxRetries) { exhausted = true; return; }
    schedule(Math.min(250, retryCount * 50), true);
  }
  function attachStyle() {
    if (!cssRules.length || !document.documentElement) { return; }
    if (!style) {
      style = document.getElementById(styleId) || document.createElement('style');
      style.id = styleId;
      style.setAttribute('data-aira-adblock', 'discovered');
    }
    if (!style.parentNode) { (document.head || document.documentElement).appendChild(style); }
  }
  function addSelectors(values) {
    if (replaceStyleOnSuccess) { clearStyle(); replaceStyleOnSuccess = false; }
    if (!Array.isArray(values)) { return; }
    var changed = false;
    for (var i = 0; i < values.length && i < maxSelectors; i += 1) {
      var selector = typeof values[i] === 'string' ? values[i].trim() : '';
      if (!selector || selectors.has(selector) || selectors.size >= maxSelectors) { continue; }
      var rule = selector + '{display:none!important;visibility:hidden!important;}';
      if (rule.length + cssChars + 1 > maxCssChars) { continue; }
      selectors.add(selector); cssRules.push(rule); cssChars += rule.length + 1; changed = true;
    }
    if (changed) { attachStyle(); if (style) { style.textContent = cssRules.join('\\n'); } }
  }
  function runScriptlets(source) {
    if (window.__airaAdBlockRustScriptletsInstalled === true || typeof source !== 'string' || !source.trim()) {
      return;
    }
    try {
      (0, eval)(source);
      window.__airaAdBlockRustScriptletsInstalled = true;
    } catch (error) {
      // CSP can reject eval. Leave the marker unset for the direct native page-end fallback.
    }
  }
  function query(classes, ids) {
    try {
      var bridge = window.__airaUserScriptNativeBridge;
      if (!bridge || typeof bridge.adBlockCosmeticQuery !== 'function') { return false; }
      var response = JSON.parse(bridge.adBlockCosmeticQuery(JSON.stringify({
        classes: classes, ids: ids,
        includeScriptlets: !scriptletsRequested && window.__airaAdBlockRustScriptletsInstalled !== true
      })));
      if (!response || response.ready !== true || typeof response.enabled !== 'boolean' ||
        documentUrl(response.pageUrl) !== pageUrl || documentUrl(location.href) !== pageUrl) {
        return false;
      }
      if (!response.enabled) { stop(); return true; }
      addSelectors(response.cssSelectors);
      runScriptlets(response.injectedScript);
      scriptletsRequested = true;
      classes.forEach(function (value) { pendingClasses.delete(value); seenClasses.add(value); });
      ids.forEach(function (value) { pendingIds.delete(value); seenIds.add(value); });
      retryCount = 0;
      return true;
    } catch (error) { return false; }
  }
  function resetJobs() {
    jobs = []; queuedRoots = new WeakSet(); queuedAttributes = new WeakSet();
  }
  function enqueue(node, subtree) {
    if (!node || node.nodeType !== 1 || node === style || node.id === styleId) { return false; }
    var queued = subtree ? queuedRoots : queuedAttributes;
    if (queued.has(node)) { return false; }
    var overflow = false;
    if (jobs.length >= 256) {
      // Mutation storms collapse into one bounded root walk; there is no periodic full-page scan.
      resetJobs();
      node = document.documentElement; subtree = true; queued = queuedRoots;
      overflow = true;
    }
    queued.add(node);
    jobs.push({ root: node, subtree: subtree, walker: subtree ? document.createTreeWalker(node, 1) : null,
      rootPending: true, current: null, classIndex: 0, idDone: false });
    return overflow;
  }
  function addToken(value, seen, pending) {
    if (typeof value !== 'string' || !value || value.length > maxTokenLength ||
      seen.has(value) || pending.has(value) || seen.size + pending.size >= maxTokens) { return; }
    pending.add(value);
  }
  function finishJob(job) {
    (job.subtree ? queuedRoots : queuedAttributes).delete(job.root);
    jobs.shift();
  }
  function collect() {
    var visited = 0;
    var tokenVisits = 0;
    while (jobs.length && visited < maxNodes && tokenVisits < 2048 &&
      pendingClasses.size < maxBatch && pendingIds.size < maxBatch) {
      var job = jobs[0];
      if (job.root.isConnected === false) { finishJob(job); continue; }
      if (!job.current) {
        job.current = job.rootPending ? job.root : job.walker ? job.walker.nextNode() : null;
        job.rootPending = false; job.classIndex = 0; job.idDone = false;
        if (!job.current) { finishJob(job); continue; }
        visited += 1;
      }
      var node = job.current;
      if (node === style || node.id === styleId) { job.current = null; continue; }
      if (!job.idDone) { addToken(node.getAttribute('id'), seenIds, pendingIds); job.idDone = true; }
      var classes = node.classList;
      var length = classes ? classes.length : 0;
      if (seenClasses.size + pendingClasses.size >= maxTokens) { job.classIndex = length; }
      while (job.classIndex < length && tokenVisits < 2048 && pendingClasses.size < maxBatch) {
        addToken(classes.item(job.classIndex), seenClasses, pendingClasses);
        job.classIndex += 1; tokenVisits += 1;
      }
      if (job.classIndex >= length) { job.current = null; }
    }
  }
  function pass() {
    if (stopped || paused || exhausted) { return; }
    if (documentUrl(location.href) !== pageUrl) { refresh(); return; }
    if (!initialReady) {
      if (!query([], [])) { failed(); return; }
      if (stopped) { return; }
      initialReady = true;
      observe();
      enqueue(document.documentElement, true);
      // The initial URL query stays tiny; existing DOM collection yields to a later task.
      schedule(0, false);
      return;
    }
    collect();
    var classes = Array.from(pendingClasses).slice(0, maxBatch);
    var ids = Array.from(pendingIds).slice(0, maxBatch);
    if ((classes.length || ids.length) && !query(classes, ids)) { failed(); return; }
    if (jobs.length || pendingClasses.size || pendingIds.size) { schedule(0, false); }
  }
  function observe() {
    if (observer || stopped || paused) { return; }
    observer = new MutationObserver(function (records) {
      if (stopped || paused) { return; }
      if (documentUrl(location.href) !== pageUrl) { refresh(); return; }
      var overflow = false;
      for (var i = 0; i < records.length; i += 1) {
        var record = records[i];
        if (record.type === 'attributes') { overflow = enqueue(record.target, false); }
        else {
          for (var j = 0; j < record.addedNodes.length; j += 1) {
            if (enqueue(record.addedNodes[j], true)) { overflow = true; break; }
          }
        }
        // The root job now covers all remaining records; don't enumerate a mutation storm twice.
        if (overflow) { break; }
      }
      attachStyle();
      if (retryWaiting || exhausted || !jobs.length) { return; }
      var now = Date.now();
      if (now - lastImmediateAt >= 16) {
        lastImmediateAt = now;
        cancelTimer();
        pass();
      } else { schedule(0, false); }
    });
    observer.observe(document.documentElement, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'id']
    });
  }
  function onPageHide() { paused = true; disconnect(); }
  function onPageShow(event) {
    if (!stopped && (paused || (event && event.persisted === true))) { refresh(); }
  }
  function onLocationChange() {
    if (!stopped && !paused && documentUrl(location.href) !== pageUrl) { refresh(); }
  }
  function listen() {
    if (listening) { return; }
    listening = true;
    window.addEventListener('pagehide', onPageHide, true);
    window.addEventListener('pageshow', onPageShow, true);
    window.addEventListener('popstate', onLocationChange, true);
    window.addEventListener('hashchange', onLocationChange, true);
  }
  function stop() {
    stopped = true; disconnect(); clearStyle(); resetJobs();
    pendingClasses.clear(); pendingIds.clear(); seenClasses.clear(); seenIds.clear();
    if (listening) {
      listening = false;
      window.removeEventListener('pagehide', onPageHide, true);
      window.removeEventListener('pageshow', onPageShow, true);
      window.removeEventListener('popstate', onLocationChange, true);
      window.removeEventListener('hashchange', onLocationChange, true);
    }
  }
  function refresh() {
    var nextUrl = documentUrl(location.href);
    if (!nextUrl || !document.documentElement) { stop(); return; }
    disconnect();
    if (nextUrl !== pageUrl) { clearStyle(); }
    pageUrl = nextUrl;
    resetJobs(); seenClasses.clear(); seenIds.clear(); pendingClasses.clear(); pendingIds.clear();
    stopped = false; paused = false; initialReady = false; exhausted = false;
    retryCount = 0; lastImmediateAt = -100; scriptletsRequested = false; replaceStyleOnSuccess = true;
    listen(); pass();
  }
  window.__airaAdBlockDiscoveryRuntime = { stop: stop, refresh: refresh };
  refresh();
})();`;

export class AdBlockCosmeticDiscoveryRuntimeScriptService {
  buildDocumentStartScriptItem(): ScriptItem {
    return { script: AD_BLOCK_COSMETIC_DISCOVERY_SCRIPT, scriptRules: ['*'] };
  }
}
