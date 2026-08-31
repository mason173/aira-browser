/**
 * App-compiled XlPlayer `/lines` runtime used by the bounded Profile Recipe. The generic deep probe reuses
 * this exact implementation only as a compatibility fallback for XlPlayer sites without an active Profile.
 *
 * The embedding script supplies `addXlPlayerLineUrl`, `scanTextForUrls`, `allowBlockingFallback`, and
 * `pendingAsyncWork`. No Profile field or remote executable content enters this fragment.
 */
export const VIDEO_COMPATIBILITY_XLPLAYER_LINES_RUNTIME_FRAGMENT: string = `
    function scanXlPlayerLinePayload(payload, persistRuntime) {
      try {
        var data = payload && payload.data ? payload.data : payload;
        if (!data || typeof data !== 'object') return false;
        var added = false;
        if (data.url3) {
          addXlPlayerLineUrl(data.url3, 'url3', persistRuntime);
          added = true;
        }
        if (!added && data.tos) {
          addXlPlayerLineUrl(data.tos, 'tos', persistRuntime);
          added = true;
        }
        if (!added && data.m3u8) {
          addXlPlayerLineUrl(data.m3u8, 'm3u8', persistRuntime);
          added = true;
        }
        if (!added && data.m3u8_2) {
          addXlPlayerLineUrl(data.m3u8_2, 'm3u8_2', persistRuntime);
          added = true;
        }
        return added;
      } catch (e) {
        return false;
      }
    }

    function base64ToHex(value) {
      try {
        var binary = atob(String(value || ''));
        var output = '';
        for (var i = 0; i < binary.length; i++) {
          output += binary.charCodeAt(i).toString(16).padStart(2, '0');
        }
        return output.toUpperCase();
      } catch (e) {
        return '';
      }
    }

    function pageHasXlPlayerLines() {
      try {
        if (typeof pid !== 'undefined' && Number(pid) > 0) {
          return true;
        }
      } catch (e) {
      }
      try {
        var scripts = document.querySelectorAll('script[src], script:not([src])');
        for (var i = 0; i < scripts.length && i < 80; i++) {
          var src = scripts[i].src || '';
          var text = scripts[i].textContent || '';
          if (src.indexOf('xlplayer') >= 0 || src.indexOf('/lines') >= 0 ||
            text.indexOf('/lines') >= 0 || text.indexOf('url3') >= 0) {
            return true;
          }
        }
      } catch (e) {
      }
      return false;
    }

    function scanXlPlayerGlobals() {
      try {
        if (typeof playLines !== 'undefined' && Array.isArray(playLines)) {
          for (var i = 0; i < playLines.length && i < 24; i++) {
            addXlPlayerLineUrl(playLines[i] && playLines[i].url ? playLines[i].url : '', 'url3', false);
          }
        }
      } catch (e) {
      }
      try {
        if (typeof lines !== 'undefined' && Array.isArray(lines)) {
          for (var lineIndex = 0; lineIndex < lines.length && lineIndex < 24; lineIndex++) {
            addXlPlayerLineUrl(lines[lineIndex] || '', 'url3', false);
          }
        }
      } catch (e) {
      }
    }

    function consumeXlPlayerLinesResponse(responseText, persistRuntime) {
      if (!responseText) return false;
      var boundedText = String(responseText).substring(0, 300000);
      try {
        var parsed = JSON.parse(boundedText);
        if (scanXlPlayerLinePayload(parsed, persistRuntime)) {
          return true;
        }
      } catch (jsonError) {
      }
      scanTextForUrls(boundedText, 'script_text', 'script_text');
      return false;
    }

    function pruneXlPlayerRequests(requests, now) {
      var keys = Object.keys(requests || {});
      for (var i = 0; i < keys.length; i++) {
        var item = requests[keys[i]] || {};
        if (now - Number(item.updatedAt || 0) > 60000) {
          delete requests[keys[i]];
        }
      }
      keys = Object.keys(requests || {});
      while (keys.length > 5) {
        var oldestKey = keys[0];
        for (var keyIndex = 1; keyIndex < keys.length; keyIndex++) {
          if (Number((requests[keys[keyIndex]] || {}).updatedAt || 0) <
            Number((requests[oldestKey] || {}).updatedAt || 0)) {
            oldestKey = keys[keyIndex];
          }
        }
        delete requests[oldestKey];
        keys = Object.keys(requests || {});
      }
    }

    function requestXlPlayerLinesAsync(endpoint, requestKey) {
      var requests = window.__airaVideoDeepProbeXlPlayerRequests;
      var now = Date.now();
      pruneXlPlayerRequests(requests, now);
      var existing = requests[requestKey];
      if (existing) {
        if (existing.status === 'pending') {
          var followupCount = Number(existing.followupCount || 0);
          if (followupCount < 2) {
            existing.followupCount = followupCount + 1;
            pendingAsyncWork = true;
          }
          return;
        }
        if ((existing.status === 'complete' && now - Number(existing.updatedAt || 0) < 30000) ||
          (existing.status === 'failed' && now - Number(existing.updatedAt || 0) < 1200)) {
          return;
        }
      }
      var requestRecord = { status: 'pending', updatedAt: now, followupCount: 0 };
      requests[requestKey] = requestRecord;
      pendingAsyncWork = true;
      try {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', endpoint.href, true);
        xhr.setRequestHeader('Accept', 'application/json,text/plain,*/*');
        xhr.onreadystatechange = function() {
          if (xhr.readyState !== 4) return;
          if (requests[requestKey] !== requestRecord) return;
          if (xhr.status >= 200 && xhr.status < 300 && xhr.responseText) {
            var boundedText = String(xhr.responseText).substring(0, 300000);
            consumeXlPlayerLinesResponse(boundedText, true);
            requests[requestKey] = {
              status: 'complete',
              updatedAt: Date.now(),
              responseText: boundedText
            };
          } else {
            requests[requestKey] = { status: 'failed', updatedAt: Date.now() };
          }
        };
        xhr.onerror = function() {
          if (requests[requestKey] === requestRecord) {
            requests[requestKey] = { status: 'failed', updatedAt: Date.now() };
          }
        };
        xhr.send();
      } catch (requestError) {
        if (requests[requestKey] === requestRecord) {
          requests[requestKey] = { status: 'failed', updatedAt: Date.now() };
        }
      }
    }

    function requestXlPlayerLinesBlocking(endpoint, requestKey) {
      try {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', endpoint.href, false);
        xhr.setRequestHeader('Accept', 'application/json,text/plain,*/*');
        xhr.send();
        if (xhr.status < 200 || xhr.status >= 300 || !xhr.responseText) return;
        var boundedText = String(xhr.responseText).substring(0, 300000);
        consumeXlPlayerLinesResponse(boundedText, true);
        window.__airaVideoDeepProbeXlPlayerRequests[requestKey] = {
          status: 'complete',
          updatedAt: Date.now(),
          responseText: boundedText
        };
      } catch (requestError) {
        window.__airaVideoDeepProbeXlPlayerRequests[requestKey] = {
          status: 'failed',
          updatedAt: Date.now()
        };
      }
    }

    function scanXlPlayerLinesEndpoint() {
      try {
        window.__airaVideoDeepProbeXlPlayerRequests =
          window.__airaVideoDeepProbeXlPlayerRequests || Object.create(null);
        scanXlPlayerGlobals();
        if (typeof pid === 'undefined' || !pid || !window.CryptoJS || typeof window.md5 !== 'function') {
          return;
        }
        if (!pageHasXlPlayerLines()) return;
        var now = Date.now();
        var raw = String(pid) + '-' + String(now);
        var key = CryptoJS.enc.Utf8.parse(md5(raw).substring(0, 16));
        var encrypted = CryptoJS.AES.encrypt(raw, key, {
          mode: CryptoJS.mode.ECB,
          padding: CryptoJS.pad.Pkcs7
        });
        var sg = base64ToHex(encrypted.toString());
        if (!sg) return;
        var endpoint = new URL('/lines', location.href);
        endpoint.searchParams.set('t', String(now));
        endpoint.searchParams.set('sg', sg);
        endpoint.searchParams.set('pid', String(pid));
        var requestKey = String(location.origin || '') + ':' + String(pid);
        pruneXlPlayerRequests(window.__airaVideoDeepProbeXlPlayerRequests, now);
        var requestState = window.__airaVideoDeepProbeXlPlayerRequests[requestKey];
        if (requestState && requestState.status === 'complete' &&
          now - Number(requestState.updatedAt || 0) < 30000) {
          consumeXlPlayerLinesResponse(requestState.responseText || '', false);
          return;
        }
        if (allowBlockingFallback === true) {
          requestXlPlayerLinesBlocking(endpoint, requestKey);
        } else {
          requestXlPlayerLinesAsync(endpoint, requestKey);
        }
      } catch (e) {
      }
    }
`;
