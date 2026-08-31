const YOUTUBE_PAGE_PROBE_SCRIPT_PREFIX: string = `(function () {
  var nativeExpectedVideoId = `;

const YOUTUBE_PAGE_PROBE_SCRIPT_SUFFIX: string = `;

  function isVideoIdLike(value) {
    return typeof value === 'string' && /^[A-Za-z0-9_-]{8,16}$/.test(value);
  }

  function extractQueryParam(url, name) {
    try {
      var queryIndex = url.indexOf('?');
      if (queryIndex < 0) return undefined;
      var hashIndex = url.indexOf('#', queryIndex);
      var query = hashIndex >= 0 ? url.substring(queryIndex + 1, hashIndex) : url.substring(queryIndex + 1);
      var parts = query.split('&');
      for (var i = 0; i < parts.length; i++) {
        var eq = parts[i].indexOf('=');
        if (eq < 0) continue;
        if (decodeURIComponent(parts[i].substring(0, eq)) === name) {
          return decodeURIComponent(parts[i].substring(eq + 1));
        }
      }
    } catch (e) {}
    return undefined;
  }

  function extractPathVideoId(url, marker) {
    try {
      var index = url.indexOf(marker);
      if (index < 0) return undefined;
      var tail = url.substring(index + marker.length);
      var cut = tail.length;
      var cuts = ['?', '#', '/'];
      for (var i = 0; i < cuts.length; i++) {
        var at = tail.indexOf(cuts[i]);
        if (at >= 0 && at < cut) cut = at;
      }
      var value = tail.substring(0, cut);
      return isVideoIdLike(value) ? value : undefined;
    } catch (e) {}
    return undefined;
  }

  function currentUrlVideoId() {
    var href = location.href || '';
    var fromQuery = extractQueryParam(href, 'v');
    if (isVideoIdLike(fromQuery)) return fromQuery;
    var fromShorts = extractPathVideoId(href, '/shorts/');
    if (isVideoIdLike(fromShorts)) return fromShorts;
    var fromEmbed = extractPathVideoId(href, '/embed/');
    if (isVideoIdLike(fromEmbed)) return fromEmbed;
    var fromShortLink = extractPathVideoId(href, 'youtu.be/');
    if (isVideoIdLike(fromShortLink)) return fromShortLink;
    return undefined;
  }

  function extractPlayerVideoId(playerJson) {
    try {
      var parsed = typeof playerJson === 'string' ? JSON.parse(playerJson) : playerJson;
      return parsed && parsed.videoDetails && isVideoIdLike(parsed.videoDetails.videoId) ? parsed.videoDetails.videoId : undefined;
    } catch (e) {}
    return undefined;
  }

  function playerJsonMatchesExpected(playerJson, expectedVideoId) {
    if (!isVideoIdLike(expectedVideoId)) return true;
    var id = extractPlayerVideoId(playerJson);
    return !isVideoIdLike(id) || id === expectedVideoId;
  }

  function getInitialPlayerResponse(expectedVideoId) {
    try {
      var direct = window.ytInitialPlayerResponse;
      if (direct && typeof direct === 'object') {
        var directJson = JSON.stringify(direct);
        if (playerJsonMatchesExpected(directJson, expectedVideoId)) {
          return directJson;
        }
      }
    } catch (e) {}
    try {
      var args = window.ytplayer && window.ytplayer.config && window.ytplayer.config.args;
      var fromArgs = args && args.player_response;
      if (typeof fromArgs === 'string' && fromArgs.length > 0 && playerJsonMatchesExpected(fromArgs, expectedVideoId)) {
        return fromArgs;
      }
    } catch (e) {}
    try {
      var html = document.documentElement.innerHTML || '';
      var marker = 'ytInitialPlayerResponse';
      var idx = html.indexOf(marker);
      if (idx < 0) return undefined;
      var assign = html.indexOf('=', idx);
      if (assign < 0) return undefined;
      var start = assign + 1;
      while (start < html.length && (html.charAt(start) === ' ' || html.charAt(start) === '\\n' || html.charAt(start) === '\\r' || html.charAt(start) === '\\t')) {
        start++;
      }
      if (html.charAt(start) !== '{') return undefined;
      var depth = 0;
      var inStr = false;
      var escape = false;
      for (var i = start; i < html.length; i++) {
        var ch = html.charAt(i);
        if (inStr) {
          if (escape) {
            escape = false;
          } else if (ch === '\\\\') {
            escape = true;
          } else if (ch === '"') {
            inStr = false;
          }
          continue;
        }
        if (ch === '"') {
          inStr = true;
          continue;
        }
        if (ch === '{') depth++;
        else if (ch === '}') {
          depth--;
          if (depth === 0) {
            var htmlJson = html.substring(start, i + 1);
            if (playerJsonMatchesExpected(htmlJson, expectedVideoId)) {
              return htmlJson;
            }
            return undefined;
          }
        }
      }
    } catch (e2) {}
    return undefined;
  }

  function safeGet(fn) {
    try {
      return fn();
    } catch (e) {
      return undefined;
    }
  }

  try {
    var payload = {
      ok: true,
      pageUrl: location.href || '',
      videoId: undefined,
      title: undefined,
      playerResponseJson: undefined,
      innertubeApiKey: undefined,
      innertubeClientName: undefined,
      innertubeClientVersion: undefined,
      playerJsUrl: undefined,
      visitorData: undefined,
      userAgent: undefined
    };
    var expectedVideoId = isVideoIdLike(nativeExpectedVideoId) ? nativeExpectedVideoId : currentUrlVideoId();
    if (isVideoIdLike(expectedVideoId)) {
      payload.videoId = expectedVideoId;
    }
    var playerJson = getInitialPlayerResponse(expectedVideoId);
    if (playerJson) {
      payload.playerResponseJson = playerJson;
      try {
        var pr = JSON.parse(playerJson);
        if (pr && pr.videoDetails) {
          if (!isVideoIdLike(payload.videoId)) {
            payload.videoId = pr.videoDetails.videoId;
          }
          payload.title = pr.videoDetails.title;
        }
      } catch (e3) {}
    }
    payload.innertubeApiKey = safeGet(function () { return window.ytcfg && ytcfg.get('INNERTUBE_API_KEY'); });
    payload.innertubeClientName = safeGet(function () { return window.ytcfg && ytcfg.get('INNERTUBE_CLIENT_NAME'); });
    payload.innertubeClientVersion = safeGet(function () { return window.ytcfg && ytcfg.get('INNERTUBE_CLIENT_VERSION'); });
    payload.playerJsUrl = safeGet(function () { return window.ytcfg && (ytcfg.get('PLAYER_JS_URL') || ytcfg.get('WEB_PLAYER_JS_URL')); });
    payload.visitorData = safeGet(function () { return window.ytcfg && ytcfg.get('VISITOR_DATA'); });
    payload.userAgent = safeGet(function () { return navigator.userAgent; });
    return JSON.stringify(payload);
  } catch (e4) {
    return JSON.stringify({ ok: false, pageUrl: location.href || '', error: String((e4 && e4.message) || e4) });
  }
})();`;

export class YoutubePageProbeScript {
  build(expectedVideoId: string = ''): string {
    return YOUTUBE_PAGE_PROBE_SCRIPT_PREFIX + JSON.stringify(expectedVideoId.trim()) + YOUTUBE_PAGE_PROBE_SCRIPT_SUFFIX;
  }
}
