import { MediaResourceDomSignal } from '../mediaDiscovery/MediaResourceClassificationModels';
import {
  VIDEO_COMPATIBILITY_XLPLAYER_LINES_RUNTIME_FRAGMENT
} from '../../services/media/VideoCompatibilityProfileXlPlayerLinesRecipeScript';

export interface MediaVideoDeepProbeResult {
  url: string;
  source: 'player' | 'manifest_text' | 'performance' | 'script_text' | 'dom';
  signal?: MediaResourceDomSignal;
  mimeType?: string;
  manifestText?: string;
  manifestBaseUrl?: string;
  pairedAudioUrl?: string;
  pairedAudioMimeType?: string;
  codecs?: string;
  bandwidth?: number;
  initializationRange?: string;
  indexRange?: string;
  pairedAudioCodecs?: string;
  pairedAudioBandwidth?: number;
  pairedAudioInitializationRange?: string;
  pairedAudioIndexRange?: string;
  posterUrl?: string;
  durationMs?: number;
  width?: number;
  height?: number;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  fromBlob: boolean;
}

export interface MediaVideoDeepProbePayload {
  ok: boolean;
  results: MediaVideoDeepProbeResult[];
  diagnostics?: VideoPlaybackDiagnosticSnapshot[];
  pendingAsyncWork?: boolean;
  error?: string;
}

export interface MediaVideoDeepProbeConfiguration {
  strategyIds: string[];
  globalConfigNames: string[];
  mediaFieldNames: string[];
  mediaQueryParameterNames: string[];
  playerMethodNames: string[];
}

const DEFAULT_DEEP_PROBE_CONFIGURATION: MediaVideoDeepProbeConfiguration = {
  strategyIds: [
    'player_adapters', 'metadata', 'player_configs', 'vendor_adapters',
    'performance_entries', 'inline_scripts', 'location'
  ],
  globalConfigNames: [
    '__INITIAL_STATE__', '__INITIAL_DATA__', '__NEXT_DATA__', '__NUXT__', '__playinfo__',
    'playerConfig', 'videoConfig', 'playConfig', 'playurl', 'playUrlInfo', 'videoData',
    'playerData', 'videoInfo', 'mediaInfo', 'streamInfo', 'playInfo', 'jwplayerConfig',
    'dplayerOptions', 'videoSources', 'mediaSources'
  ],
  mediaFieldNames: [
    'url3', 'url_next', 'url', 'src', 'file', 'fileUrl', 'file_url', 'source', 'sources',
    'sourceUrl', 'source_url', 'video', 'video_url', 'videoUrl', 'play_url', 'playUrl',
    'playback_url', 'playbackUrl', 'stream', 'stream_url', 'streamUrl', 'media_url', 'mediaUrl',
    'contentUrl', 'content_url', 'downloadUrl', 'download_url', 'baseUrl', 'base_url',
    'backupUrl', 'backup_url', 'm3u8', 'm3u8_2', 'm3u8Url', 'hls', 'hlsUrl', 'hls_url',
    'mpd', 'mpdUrl', 'dash', 'dashUrl', 'dash_url', 'currentSrc', 'href'
  ],
  mediaQueryParameterNames: [
    'file', 'source', 'src', 'video_url', 'video', 'url', 'hls', 'm3u8', 'mpd', 'dash'
  ],
  playerMethodNames: ['loadSource', 'attachSource', 'setSrc', 'load', 'src', 'initialize', 'setup']
};

export interface VideoPlaybackDiagnosticSnapshot {
  pageUrl: string;
  userAgent: string;
  serviceWorkerAvailable: boolean;
  serviceWorkerControlled: boolean;
  serviceWorkerControllerState?: string;
  mediaSourceAvailable: boolean;
  mseMp4Supported: boolean;
  canPlayMp4: string;
  canPlayHls: string;
  telegramUrlKinds: string[];
  mediaElements: VideoPlaybackElementDiagnostic[];
}

export interface VideoPlaybackElementDiagnostic {
  tagName: string;
  url: string;
  urlKind: string;
  networkState: number;
  readyState: number;
  errorCode: number;
  errorMessage: string;
  recentEvents: string[];
}

const DEEP_PROBE_SCRIPT: string = `(function () {
  try {
    var results = [];
    var seen = Object.create(null);
    var allowBlockingFallback = __AIRA_ALLOW_BLOCKING_FALLBACK__;
    var probeConfiguration = __AIRA_DEEP_PROBE_CONFIGURATION__;
    var pendingAsyncWork = false;
    var mediaUrlPattern = /(?:https?:\\/\\/|\\/\\/)[^"'<>\\s]+?\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\\s])(?:[?#][^"'<>\\s]*)?/ig;
    window.__airaVideoDeepProbeResults = window.__airaVideoDeepProbeResults || [];
    window.__airaVideoDeepProbeSeen = window.__airaVideoDeepProbeSeen || Object.create(null);
    window.__airaVideoDeepProbeSourceHints = window.__airaVideoDeepProbeSourceHints || [];
    window.__airaVideoDeepProbeLooseManifests = window.__airaVideoDeepProbeLooseManifests || [];
    window.__airaVideoDeepProbePerformanceCursor = window.__airaVideoDeepProbePerformanceCursor || 0;
    window.__airaVideoDeepProbePerformanceCheckpoint = window.__airaVideoDeepProbePerformanceCheckpoint || '';
    window.__airaVideoDeepProbeInlineScriptCursor = window.__airaVideoDeepProbeInlineScriptCursor || 0;
    window.__airaVideoDeepProbeInlineScriptInitialized = window.__airaVideoDeepProbeInlineScriptInitialized === true;
    window.__airaVideoDeepProbeInlineScriptObservers = window.__airaVideoDeepProbeInlineScriptObservers ||
      (typeof WeakMap === 'function' ? new WeakMap() : null);
    window.__airaVideoDeepProbeDirtyInlineScripts = window.__airaVideoDeepProbeDirtyInlineScripts ||
      (typeof WeakSet === 'function' ? new WeakSet() : null);

    function buildNameSet(values, lowerCase) {
      var output = Object.create(null);
      var source = Array.isArray(values) ? values : [];
      for (var i = 0; i < source.length; i++) {
        var key = String(source[i] || '');
        if (lowerCase === true) key = key.toLowerCase();
        if (key) output[key] = true;
      }
      return output;
    }

    var strategySet = buildNameSet(probeConfiguration.strategyIds, false);
    var mediaFieldNameSet = buildNameSet(probeConfiguration.mediaFieldNames, true);
    var mediaQueryParameterNameSet = buildNameSet(probeConfiguration.mediaQueryParameterNames, true);
    var playerMethodNameSet = buildNameSet(probeConfiguration.playerMethodNames, true);

    function strategyEnabled(id) {
      return strategySet[String(id || '')] === true;
    }

    function isMediaFieldName(value) {
      return mediaFieldNameSet[String(value || '').toLowerCase()] === true;
    }

    function isMediaQueryParameterName(value) {
      return mediaQueryParameterNameSet[String(value || '').toLowerCase()] === true;
    }

    function isPlayerMethodName(value) {
      return playerMethodNameSet[String(value || '').toLowerCase()] === true;
    }

    function currentReferer() {
      return location && location.href ? location.href : '';
    }

    function currentOrigin() {
      try {
        return location && location.origin ? location.origin : new URL(location.href).origin;
      } catch (e) {
        return '';
      }
    }

    function currentUserAgent() {
      return navigator && navigator.userAgent ? navigator.userAgent : '';
    }

    function classifyMediaUrl(value) {
      var url = normalizeUrl(value || '');
      if (!url) return 'none';
      if (url.indexOf('blob:') === 0) return 'blob';
      try {
        var parsed = new URL(url, location.href);
        var path = parsed.pathname || '';
        if (parsed.hostname === 'web.telegram.org') {
          if (path.indexOf('/hls_stream/') >= 0) return 'telegram_hls_stream';
          if (path.indexOf('/hls/') >= 0) return 'telegram_hls';
          if (path.indexOf('/stream/') >= 0) return 'telegram_stream';
          if (path.indexOf('/progressive/') >= 0) return 'telegram_progressive';
          return 'telegram_same_origin';
        }
        return parsed.protocol.indexOf('http') === 0 ? 'http' : parsed.protocol.replace(':', '') || 'other';
      } catch (e) {
        return 'other';
      }
    }

    function decodeLooseText(value) {
      var text = String(value || '');
      for (var i = 0; i < 3; i++) {
        try {
          var decoded = decodeURIComponent(text);
          if (decoded === text) break;
          text = decoded;
        } catch (e) {
          break;
        }
      }
      return text;
    }

    function normalizeUrl(value) {
      var url = decodeLooseText(value)
        .replace(/\\\\u002[fF]/g, '/')
        .replace(/\\\\+\\//g, '/')
        .replace(/&amp;/g, '&')
        .replace(/\\\\u0026/g, '&')
        .replace(/\\\\u003[dD]/g, '=')
        .replace(/\\\\u003[fF]/g, '?');
      if (url.indexOf('//') === 0) {
        url = location.protocol + url;
      }
      try {
        if (!/^(https?:|blob:)/i.test(url)) {
          url = new URL(url, location.href).href;
        }
      } catch (e) {
      }
      return url;
    }

    function normalizeText(value) {
      return decodeLooseText(value)
        .replace(/\\\\u002[fF]/g, '/')
        .replace(/\\\\+\\//g, '/')
        .replace(/&amp;/g, '&')
        .replace(/\\\\u0026/g, '&')
        .replace(/\\\\u003[dD]/g, '=')
        .replace(/\\\\u003[fF]/g, '?');
    }

    function isLikelyMediaNoiseUrl(value) {
      var raw = String(value || '').toLowerCase();
      var clean = raw.split('?')[0].split('#')[0];
      if (!clean) return true;
      if (/\\.(?:webmanifest|json|map|js|mjs|css|html|htm|xml|wasm|svg|png|jpg|jpeg|webp|gif|ico|avif)(?:$|[?#])/i.test(raw)) return true;
      if (/(?:^|\\/)(?:manifest\\.json|site\\.webmanifest|manifest\\.webmanifest)$/.test(clean)) return true;
      if (clean.indexOf('/favicon') >= 0 || clean.indexOf('/favicons/') >= 0) return true;
      return false;
    }

    function addResult(url, source, extra) {
      var normalizedUrl = normalizeUrl(url);
      if (!normalizedUrl || seen[normalizedUrl]) return;
      if (!/^(https?:|blob:)/i.test(normalizedUrl)) return;
      if (isLikelyMediaNoiseUrl(normalizedUrl)) return;
      seen[normalizedUrl] = true;
      results.push({
        url: normalizedUrl,
        source: source || 'dom',
        signal: extra && extra.signal ? extra.signal : undefined,
        mimeType: extra && extra.mimeType ? extra.mimeType : undefined,
        manifestText: extra && extra.manifestText ? extra.manifestText : undefined,
        manifestBaseUrl: extra && extra.manifestBaseUrl ? normalizeUrl(extra.manifestBaseUrl) : undefined,
        pairedAudioUrl: extra && extra.pairedAudioUrl ? normalizeUrl(extra.pairedAudioUrl) : undefined,
        pairedAudioMimeType: extra && extra.pairedAudioMimeType ? extra.pairedAudioMimeType : undefined,
        codecs: extra && extra.codecs ? extra.codecs : undefined,
        bandwidth: extra && extra.bandwidth ? extra.bandwidth : undefined,
        initializationRange: extra && extra.initializationRange ? extra.initializationRange : undefined,
        indexRange: extra && extra.indexRange ? extra.indexRange : undefined,
        pairedAudioCodecs: extra && extra.pairedAudioCodecs ? extra.pairedAudioCodecs : undefined,
        pairedAudioBandwidth: extra && extra.pairedAudioBandwidth ? extra.pairedAudioBandwidth : undefined,
        pairedAudioInitializationRange: extra && extra.pairedAudioInitializationRange ? extra.pairedAudioInitializationRange : undefined,
        pairedAudioIndexRange: extra && extra.pairedAudioIndexRange ? extra.pairedAudioIndexRange : undefined,
        posterUrl: extra && extra.posterUrl ? extra.posterUrl : undefined,
        durationMs: extra && extra.durationMs ? extra.durationMs : undefined,
        width: extra && extra.width ? extra.width : undefined,
        height: extra && extra.height ? extra.height : undefined,
        referer: extra && extra.referer ? extra.referer : currentReferer(),
        userAgent: extra && extra.userAgent ? extra.userAgent : currentUserAgent(),
        originUrl: extra && extra.originUrl ? extra.originUrl : currentOrigin(),
        fromBlob: normalizedUrl.indexOf('blob:') === 0
      });
    }

    function addRuntimeResult(url, source, extra) {
      var normalizedUrl = normalizeUrl(url);
      if (!normalizedUrl || !/^(https?:|blob:)/i.test(normalizedUrl)) return;
      if (isLikelyMediaNoiseUrl(normalizedUrl)) return;
      if (window.__airaVideoDeepProbeSeen[normalizedUrl]) return;
      window.__airaVideoDeepProbeSeen[normalizedUrl] = true;
      window.__airaVideoDeepProbeResults.push({
        url: normalizedUrl,
        source: source || 'manifest_text',
        signal: extra && extra.signal ? extra.signal : 'script_text',
        mimeType: extra && extra.mimeType ? extra.mimeType : undefined,
        manifestText: extra && extra.manifestText ? extra.manifestText : undefined,
        manifestBaseUrl: extra && extra.manifestBaseUrl ? normalizeUrl(extra.manifestBaseUrl) : undefined,
        pairedAudioUrl: extra && extra.pairedAudioUrl ? normalizeUrl(extra.pairedAudioUrl) : undefined,
        pairedAudioMimeType: extra && extra.pairedAudioMimeType ? extra.pairedAudioMimeType : undefined,
        codecs: extra && extra.codecs ? extra.codecs : undefined,
        bandwidth: extra && extra.bandwidth ? extra.bandwidth : undefined,
        initializationRange: extra && extra.initializationRange ? extra.initializationRange : undefined,
        indexRange: extra && extra.indexRange ? extra.indexRange : undefined,
        pairedAudioCodecs: extra && extra.pairedAudioCodecs ? extra.pairedAudioCodecs : undefined,
        pairedAudioBandwidth: extra && extra.pairedAudioBandwidth ? extra.pairedAudioBandwidth : undefined,
        pairedAudioInitializationRange: extra && extra.pairedAudioInitializationRange ? extra.pairedAudioInitializationRange : undefined,
        pairedAudioIndexRange: extra && extra.pairedAudioIndexRange ? extra.pairedAudioIndexRange : undefined,
        referer: extra && extra.referer ? extra.referer : currentReferer(),
        userAgent: extra && extra.userAgent ? extra.userAgent : currentUserAgent(),
        originUrl: extra && extra.originUrl ? extra.originUrl : currentOrigin(),
        fromBlob: normalizedUrl.indexOf('blob:') === 0
      });
      if (window.__airaVideoDeepProbeResults.length > 80) {
        window.__airaVideoDeepProbeResults.shift();
      }
    }

    function rememberRuntimeSourceHint(url, source, mimeType) {
      var normalizedUrl = normalizeUrl(url || '');
      if (!/^https?:/i.test(normalizedUrl)) return;
      if (isLikelyMediaNoiseUrl(normalizedUrl)) return;
      var lower = normalizedUrl.toLowerCase();
      var lowerMime = String(mimeType || '').toLowerCase();
      var typedMediaHint = lowerMime.indexOf('mpegurl') >= 0 ||
        lowerMime.indexOf('m3u') >= 0 ||
        lowerMime.indexOf('dash') >= 0 ||
        lowerMime.indexOf('mpd') >= 0 ||
        lowerMime.indexOf('video/') >= 0 ||
        lowerMime.indexOf('audio/') >= 0;
      if (!typedMediaHint &&
        !/\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?:[?#]|$)/i.test(lower) &&
        lower.indexOf('.m3u8') < 0 && lower.indexOf('/hls') < 0 && lower.indexOf('/stream') < 0 &&
        lower.indexOf('/playlist') < 0 && lower.indexOf('/manifest') < 0) {
        return;
      }
      window.__airaVideoDeepProbeSourceHints.push({
        url: normalizedUrl,
        source: source || 'player',
        mimeType: mimeType || inferMimeForMediaField('url', normalizedUrl),
        observedAt: Date.now()
      });
      if (window.__airaVideoDeepProbeSourceHints.length > 24) {
        window.__airaVideoDeepProbeSourceHints.shift();
      }
      attachLooseManifestsToSourceHint(normalizedUrl, source || 'player', mimeType || inferMimeForMediaField('url', normalizedUrl));
    }

    function pickRecentRuntimeSourceHint(mimeType) {
      var hints = window.__airaVideoDeepProbeSourceHints || [];
      var preferHls = String(mimeType || '').toLowerCase().indexOf('mpegurl') >= 0 ||
        String(mimeType || '').toLowerCase().indexOf('m3u') >= 0;
      for (var i = hints.length - 1; i >= 0; i--) {
        var item = hints[i] || {};
        var url = item.url || '';
        if (!url) continue;
        if (!preferHls || /\\.(?:m3u8|m3u)(?:[?#]|$)/i.test(url) || url.toLowerCase().indexOf('.m3u8') >= 0) {
          return item;
        }
      }
      return undefined;
    }

    function addRuntimeManifestSource(url, text, source, mimeType) {
      if (!text || String(text).toUpperCase().indexOf('#EXTM3U') < 0) return;
      var manifestText = String(text);
      if (manifestText.length > 250000) {
        manifestText = manifestText.substring(0, 250000);
      }
      var normalizedUrl = normalizeUrl(url || '');
      if (/^https?:/i.test(normalizedUrl)) {
        rememberRuntimeSourceHint(normalizedUrl, source || 'manifest_text', mimeType || 'application/vnd.apple.mpegurl');
        addRuntimeResult(normalizedUrl, source || 'manifest_text', {
          signal: 'video_element',
          mimeType: mimeType || 'application/vnd.apple.mpegurl',
          manifestText: manifestText,
          manifestBaseUrl: normalizedUrl
        });
        addResult(normalizedUrl, source || 'manifest_text', {
          signal: 'video_element',
          mimeType: mimeType || 'application/vnd.apple.mpegurl',
          manifestText: manifestText,
          manifestBaseUrl: normalizedUrl
        });
        return;
      }
      var recent = pickRecentRuntimeSourceHint(mimeType || 'application/vnd.apple.mpegurl');
      if (recent && recent.url) {
        addRuntimeResult(recent.url, source || recent.source || 'manifest_text', {
          signal: 'video_element',
          mimeType: mimeType || recent.mimeType || 'application/vnd.apple.mpegurl',
          manifestText: manifestText,
          manifestBaseUrl: recent.url
        });
        addResult(recent.url, source || recent.source || 'manifest_text', {
          signal: 'video_element',
          mimeType: mimeType || recent.mimeType || 'application/vnd.apple.mpegurl',
          manifestText: manifestText,
          manifestBaseUrl: recent.url
        });
        return;
      }
      rememberLooseManifest(manifestText, source || 'manifest_text', mimeType || 'application/vnd.apple.mpegurl');
    }

    function rememberLooseManifest(manifestText, source, mimeType) {
      var text = String(manifestText || '');
      if (!text || text.toUpperCase().indexOf('#EXTM3U') < 0) return;
      window.__airaVideoDeepProbeLooseManifests.push({
        text: text.length > 250000 ? text.substring(0, 250000) : text,
        source: source || 'manifest_text',
        mimeType: mimeType || 'application/vnd.apple.mpegurl',
        observedAt: Date.now()
      });
      if (window.__airaVideoDeepProbeLooseManifests.length > 8) {
        window.__airaVideoDeepProbeLooseManifests.shift();
      }
    }

    function attachLooseManifestsToSourceHint(url, source, mimeType) {
      var normalizedUrl = normalizeUrl(url || '');
      if (!/^https?:/i.test(normalizedUrl)) return;
      var lowerMime = String(mimeType || '').toLowerCase();
      var isHlsHint = lowerMime.indexOf('mpegurl') >= 0 ||
        lowerMime.indexOf('m3u') >= 0 ||
        /\\.(?:m3u8|m3u)(?:[?#]|$)/i.test(normalizedUrl);
      if (!isHlsHint) return;
      var manifests = window.__airaVideoDeepProbeLooseManifests || [];
      var now = Date.now();
      for (var i = manifests.length - 1; i >= 0; i--) {
        var item = manifests[i] || {};
        if (!item.text || (now - Number(item.observedAt || 0)) > 30000) continue;
        addRuntimeResult(normalizedUrl, source || item.source || 'manifest_text', {
          signal: 'video_element',
          mimeType: mimeType || item.mimeType || 'application/vnd.apple.mpegurl',
          manifestText: item.text,
          manifestBaseUrl: normalizedUrl
        });
        addResult(normalizedUrl, source || item.source || 'manifest_text', {
          signal: 'video_element',
          mimeType: mimeType || item.mimeType || 'application/vnd.apple.mpegurl',
          manifestText: item.text,
          manifestBaseUrl: normalizedUrl
        });
        break;
      }
    }

    function addManifestText(text, source, manifestBaseUrl) {
      if (!text || String(text).toUpperCase().indexOf('#EXTM3U') < 0) return;
      var manifestText = String(text);
      if (manifestText.length > 250000) {
        manifestText = manifestText.substring(0, 250000);
      }
      var url = '';
      try {
        window.__airaVideoDeepProbeInternalObjectUrl = true;
        url = URL.createObjectURL(new Blob([new TextEncoder().encode(manifestText)], {
          type: 'application/vnd.apple.mpegurl'
        }));
      } finally {
        window.__airaVideoDeepProbeInternalObjectUrl = false;
      }
      addRuntimeResult(url, source || 'manifest_text', {
        signal: 'script_text',
        mimeType: 'application/vnd.apple.mpegurl',
        manifestText: manifestText,
        manifestBaseUrl: manifestBaseUrl || undefined
      });
      addResult(url, source || 'manifest_text', {
        signal: 'script_text',
        mimeType: 'application/vnd.apple.mpegurl',
        manifestText: manifestText,
        manifestBaseUrl: manifestBaseUrl || undefined
      });
    }

    function maybeRecordManifestResponse(url, text, source, mimeType) {
      if (!text || String(text).toUpperCase().indexOf('#EXTM3U') < 0) return;
      addRuntimeManifestSource(url, text, source || 'manifest_text', mimeType || 'application/vnd.apple.mpegurl');
      if (url) {
        addRuntimeResult(url, source || 'manifest_text', {
          signal: 'script_text',
          mimeType: mimeType || 'application/vnd.apple.mpegurl',
          manifestText: String(text),
          manifestBaseUrl: url
        });
      }
      addManifestText(String(text), source || 'manifest_text', url || undefined);
    }

    function maybeRecordMediaResponse(url, text, source, mimeType) {
      var responseText = String(text || '');
      if (!responseText) return;
      if (responseText.length > 300000) {
        responseText = responseText.substring(0, 300000);
      }
      maybeRecordManifestResponse(url, responseText, source || 'manifest_text', mimeType);
      scanTextForUrls(responseText, source || 'script_text', 'script_text');
      if (url) {
        scanTextForUrls(String(url), source || 'performance', 'performance_entry');
      }
    }

    function isHlsManifestMimeType(mimeType) {
      var lower = String(mimeType || '').split(';')[0].trim().toLowerCase();
      return lower === 'application/vnd.apple.mpegurl' ||
        lower === 'application/x-mpegurl' ||
        lower === 'application/mpegurl' ||
        lower === 'audio/mpegurl' ||
        lower === 'audio/x-mpegurl';
    }

    function readBlobTextPrefix(blob, callback) {
      try {
        if (!blob || typeof blob.slice !== 'function') return;
        var maxBytes = Math.min(blob.size || 0, 300000);
        if (maxBytes <= 0) return;
        var chunk = blob.slice(0, maxBytes, blob.type || 'text/plain');
        if (chunk && typeof chunk.text === 'function') {
          chunk.text().then(function(text) {
            callback(String(text || ''));
          }).catch(function() {});
          return;
        }
        if (typeof FileReader !== 'undefined') {
          var reader = new FileReader();
          reader.onload = function() {
            callback(String(reader.result || ''));
          };
          reader.onerror = function() {};
          reader.readAsText(chunk);
        }
      } catch (e) {
      }
    }

    function maybeRecordBlobManifest(url, blob, source, mimeType) {
      try {
        if (!blob || typeof Blob === 'undefined' || !(blob instanceof Blob)) return;
        var blobMimeType = mimeType || blob.type || '';
        var shouldRead = isHlsManifestMimeType(blobMimeType) || (blob.size || 0) <= 300000;
        if (!shouldRead) return;
        readBlobTextPrefix(blob, function(text) {
          if (!text || String(text).toUpperCase().indexOf('#EXTM3U') < 0) return;
          if (/^https?:/i.test(String(url || ''))) {
            maybeRecordManifestResponse(url || '', text, source || 'manifest_text',
              blobMimeType || 'application/vnd.apple.mpegurl');
            return;
          }
          addRuntimeResult(url || '', source || 'manifest_text', {
            signal: 'script_text',
            mimeType: blobMimeType || 'application/vnd.apple.mpegurl',
            manifestText: String(text)
          });
          addResult(url || '', source || 'manifest_text', {
            signal: 'script_text',
            mimeType: blobMimeType || 'application/vnd.apple.mpegurl',
            manifestText: String(text)
          });
        });
      } catch (e) {
      }
    }

    function installRuntimeHooks() {
      if (window.__airaVideoDeepProbeInstalled) return;
      window.__airaVideoDeepProbeInstalled = true;
      try {
        var originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          this.__airaVideoDeepProbeUrl = typeof url === 'string' ? url : '';
          this.__airaVideoDeepProbeMethod = typeof method === 'string' ? method.toUpperCase() : 'GET';
          this.addEventListener('readystatechange', function() {
            try {
              if (this.readyState !== 4 || this.status < 200 || this.status >= 300) return;
              var contentType = this.getResponseHeader ? (this.getResponseHeader('content-type') || '') : '';
              if (this.responseType && this.responseType !== '' && this.responseType !== 'text') {
                if (this.responseType === 'blob') {
                  maybeRecordBlobManifest(this.responseURL || this.__airaVideoDeepProbeUrl || '',
                    this.response, 'manifest_text', contentType);
                }
                return;
              }
              var text = typeof this.responseText === 'string' ? this.responseText : '';
              maybeRecordMediaResponse(this.responseURL || this.__airaVideoDeepProbeUrl || '', text, 'manifest_text', contentType);
            } catch (e) {
            }
          });
          return originalOpen.apply(this, arguments);
        };
        XMLHttpRequest.prototype.open.toString = function() { return originalOpen.toString(); };
      } catch (e) {
      }
      try {
        var originalFetch = window.fetch;
        window.fetch = function(input, init) {
          var requestUrl = '';
          try {
            requestUrl = typeof input === 'string' ? input : (input && input.url ? input.url : '');
          } catch (e) {
          }
          return originalFetch.apply(this, arguments).then(function(response) {
            try {
              var clone = response.clone();
              var contentType = clone.headers && clone.headers.get ? (clone.headers.get('content-type') || '') : '';
              clone.text().then(function(text) {
                maybeRecordMediaResponse(response.url || requestUrl, text, 'manifest_text', contentType);
              }).catch(function() {});
            } catch (e) {
            }
            return response;
          });
        };
        window.fetch.toString = function() { return originalFetch.toString(); };
      } catch (e) {
      }
      try {
        if (window.URL && typeof window.URL.createObjectURL === 'function') {
          var originalCreateObjectURL = window.URL.createObjectURL;
          window.URL.createObjectURL = function(value) {
            var objectUrl = originalCreateObjectURL.apply(this, arguments);
            try {
              if (window.__airaVideoDeepProbeInternalObjectUrl !== true) {
                var blobType = value && value.type ? String(value.type) : '';
                var recent = pickRecentRuntimeSourceHint(blobType);
                if (recent && recent.url && /^blob:/i.test(objectUrl)) {
                  addRuntimeResult(recent.url, 'player', {
                    signal: 'video_element',
                    mimeType: recent.mimeType || blobType || undefined
                  });
                }
                maybeRecordBlobManifest(objectUrl || '', value, 'manifest_text', blobType);
                if (value && typeof value.text === 'function') {
                  value.text().then(function(text) {
                    addRuntimeManifestSource(recent && recent.url ? recent.url : '', text, 'manifest_text',
                      blobType || 'application/vnd.apple.mpegurl');
                    maybeRecordMediaResponse(recent && recent.url ? recent.url : objectUrl, text, 'manifest_text',
                      blobType || 'application/vnd.apple.mpegurl');
                  }).catch(function() {});
                }
              }
            } catch (e) {
            }
            return objectUrl;
          };
          window.URL.createObjectURL.toString = function() { return originalCreateObjectURL.toString(); };
        }
      } catch (e) {
      }
      try {
        var originalDecode = TextDecoder.prototype.decode;
        TextDecoder.prototype.decode = function() {
          var text = originalDecode.apply(this, arguments);
          try {
            maybeRecordMediaResponse('', text, 'manifest_text', 'application/vnd.apple.mpegurl');
          } catch (e) {
          }
          return text;
        };
        TextDecoder.prototype.decode.toString = function() { return originalDecode.toString(); };
      } catch (e) {
      }
      try {
        window.__airaMediaDiagnosticEvents = window.__airaMediaDiagnosticEvents || [];
        var eventNames = ['loadstart', 'loadedmetadata', 'canplay', 'playing', 'waiting', 'stalled', 'suspend', 'abort', 'emptied', 'error'];
        eventNames.forEach(function(name) {
          document.addEventListener(name, function(event) {
            try {
              var target = event.target;
              if (!target || !target.tagName || !/^(video|audio)$/i.test(target.tagName)) return;
              var mediaError = target.error || {};
              window.__airaMediaDiagnosticEvents.push({
                type: name,
                url: target.currentSrc || target.src || '',
                code: typeof mediaError.code === 'number' ? mediaError.code : 0,
                readyState: typeof target.readyState === 'number' ? target.readyState : 0,
                networkState: typeof target.networkState === 'number' ? target.networkState : 0
              });
              if (window.__airaMediaDiagnosticEvents.length > 50) {
                window.__airaMediaDiagnosticEvents.shift();
              }
            } catch (e) {
            }
          }, true);
        });
      } catch (e) {
      }
    }

    function scanTextForUrls(text, source, signal) {
      var normalizedText = normalizeText(text);
      mediaUrlPattern.lastIndex = 0;
      var match;
      while ((match = mediaUrlPattern.exec(normalizedText)) !== null && results.length < 80) {
        addResult(match[0], source || 'script_text', { signal: signal || 'script_text' });
      }
      addManifestText(normalizedText, source || 'manifest_text');
      scanStructuredMediaFields(normalizedText, source || 'script_text', signal || 'script_text');
      scanPlayerMethodMediaUrls(normalizedText, source || 'script_text', signal || 'script_text');
      scanQueryStyleMediaFields(normalizedText, source || 'script_text', signal || 'script_text');
      scanEncodedPlayerFields(normalizedText, source || 'script_text', signal || 'script_text');
    }

    function scanEncodedPlayerFields(text, source, signal) {
      var fieldPattern = /["']([A-Za-z_$][A-Za-z0-9_$-]{0,63})["']\\s*:\\s*["']([A-Za-z0-9+/=_-]{24,})["']/ig;
      var match;
      while ((match = fieldPattern.exec(String(text || ''))) !== null && results.length < 80) {
        if (!isMediaFieldName(match[1])) continue;
        var decoded = decodeBase64UrlText(match[2] || '');
        if (decoded) {
          scanDecodedTextForUrls(decoded, source, signal);
        }
      }
    }

    function scanDecodedTextForUrls(text, source, signal) {
      var normalizedText = normalizeText(text);
      mediaUrlPattern.lastIndex = 0;
      var match;
      while ((match = mediaUrlPattern.exec(normalizedText)) !== null && results.length < 80) {
        addResult(match[0], source || 'script_text', { signal: signal || 'script_text' });
      }
      addManifestText(normalizedText, source || 'manifest_text');
      scanStructuredMediaFields(normalizedText, source || 'script_text', signal || 'script_text');
      scanPlayerMethodMediaUrls(normalizedText, source || 'script_text', signal || 'script_text');
      scanQueryStyleMediaFields(normalizedText, source || 'script_text', signal || 'script_text');
    }

    function inferMimeForMediaField(key, url) {
      var lowerKey = String(key || '').toLowerCase();
      var lowerUrl = String(url || '').toLowerCase();
      if (lowerKey.indexOf('m3u8') >= 0 || lowerKey.indexOf('hls') >= 0 || /\\.m3u8(?:[?#]|$)/i.test(lowerUrl)) {
        return 'application/vnd.apple.mpegurl';
      }
      if (lowerKey.indexOf('mpd') >= 0 || lowerKey.indexOf('dash') >= 0 || /\\.mpd(?:[?#]|$)/i.test(lowerUrl)) {
        return 'application/dash+xml';
      }
      if (/\\.(?:mp4|m4v|mov)(?:[?#]|$)/i.test(lowerUrl) || /\\/obj\\/[A-Fa-f0-9]{24,}(?:[?#]|$)/.test(lowerUrl)) {
        return 'video/mp4';
      }
      if (/\\.webm(?:[?#]|$)/i.test(lowerUrl)) {
        return 'video/webm';
      }
      return undefined;
    }

    function looksLikeStructuredMediaUrl(key, value) {
      var normalized = normalizeUrl(value);
      if (!/^(https?:|blob:)/i.test(normalized)) return false;
      if (isLikelyMediaNoiseUrl(normalized)) return false;
      if (/\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?:[?#]|$)/i.test(normalized)) return true;
      if (/\\/obj\\/[A-Fa-f0-9]{24,}(?:[?#]|$)/.test(normalized)) return true;
      if (/(?:\\/media\\/|\\/stream\\/|\\/video\\/)[A-Za-z0-9_-]{32,}(?:[?#]|$)/.test(normalized)) return true;
      if (/googlevideo\\.com\\/videoplayback|\\/videoplayback\\?/i.test(normalized)) return true;
      var lowerKey = String(key || '').toLowerCase();
      return lowerKey.indexOf('m3u8') >= 0 || lowerKey.indexOf('hls') >= 0 ||
        lowerKey.indexOf('mpd') >= 0 || lowerKey.indexOf('dash') >= 0;
    }

    function scanStructuredMediaFields(text, source, signal) {
      var resultSignal = (signal === 'video_element' || signal === 'audio_element') ? signal : 'embedded_attribute';
      var fieldPattern = /["']?([A-Za-z_$][A-Za-z0-9_$-]{0,63})["']?\\s*[:=]\\s*["']((?:https?:\\/\\/|\\/\\/|\\/)[^"'<>\\s]{8,2000})["']/ig;
      var match;
      while ((match = fieldPattern.exec(String(text || ''))) !== null && results.length < 80) {
        if (isMediaFieldName(match[1]) && looksLikeStructuredMediaUrl(match[1], match[2])) {
          addResult(match[2], source || 'script_text', {
            signal: resultSignal,
            mimeType: inferMimeForMediaField(match[1], match[2])
          });
        }
      }
      var relativeFieldPattern = /["']?([A-Za-z_$][A-Za-z0-9_$-]{0,63})["']?\\s*[:=]\\s*["']((?:\\.{1,2}\\/)?[^"'<>\\s\\/][^"'<>\\s]{0,2000}\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\\s])(?:[?#][^"'<>\\s]*)?)["']/ig;
      while ((match = relativeFieldPattern.exec(String(text || ''))) !== null && results.length < 80) {
        if (isMediaFieldName(match[1]) && looksLikeStructuredMediaUrl(match[1], match[2])) {
          addResult(match[2], source || 'script_text', {
            signal: resultSignal,
            mimeType: inferMimeForMediaField(match[1], match[2])
          });
        }
      }
    }

    function scanPlayerMethodMediaUrls(text, source, signal) {
      var resultSignal = (signal === 'video_element' || signal === 'audio_element') ? signal : 'embedded_attribute';
      var methodPattern = /\\b([A-Za-z_$][A-Za-z0-9_$]{0,63})\\s*\\([^)]{0,240}?(["'])((?:https?:\\/\\/|\\/\\/|\\/|\\.{1,2}\\/)?[^"'<>\\s]{1,2000}\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\\s])(?:[?#][^"'<>\\s]*)?)\\2/ig;
      var match;
      while ((match = methodPattern.exec(String(text || ''))) !== null && results.length < 80) {
        if (isPlayerMethodName(match[1]) && looksLikeStructuredMediaUrl('url', match[3])) {
          addResult(match[3], source || 'script_text', {
            signal: resultSignal,
            mimeType: inferMimeForMediaField('url', match[3])
          });
        }
      }
    }

    function scanQueryStyleMediaFields(text, source, signal) {
      var resultSignal = (signal === 'video_element' || signal === 'audio_element') ? signal : 'embedded_attribute';
      var paramPattern = /(?:^|[?&#;,\\s])([A-Za-z_$][A-Za-z0-9_$-]{0,63})=((?:https?:\\/\\/|\\/\\/|\\/|\\.{1,2}\\/)?[^"'&<>\\s]{1,2000}\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#&"'<>\\s])(?:\\?[^"'&<>\\s]*)?)/ig;
      var match;
      while ((match = paramPattern.exec(String(text || ''))) !== null && results.length < 80) {
        if (isMediaQueryParameterName(match[1]) && looksLikeStructuredMediaUrl('url', match[2])) {
          addResult(match[2], source || 'script_text', {
            signal: resultSignal,
            mimeType: inferMimeForMediaField('url', match[2])
          });
        }
      }
    }

    function decodeBase64UrlText(value) {
      try {
        var normalized = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
        if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized) || normalized.length % 4 === 1) {
          return '';
        }
        while (normalized.length % 4 !== 0) {
          normalized += '=';
        }
        var binary = atob(normalized);
        var decoded = '';
        for (var i = 0; i < binary.length; i++) {
          var hex = binary.charCodeAt(i).toString(16);
          decoded += '%' + (hex.length === 1 ? '0' + hex : hex);
        }
        return decodeLooseText(decodeURIComponent(decoded));
      } catch (e) {
        return '';
      }
    }

    function addPlayerSource(value, mimeType) {
      if (!value) return;
      if (typeof value === 'string') {
        rememberRuntimeSourceHint(value, 'player', mimeType);
        addResult(value, 'player', { signal: 'video_element', mimeType: mimeType });
        scanTextForUrls(value, 'player', 'video_element');
        return;
      }
      if (typeof value === 'object') {
        var src = value.src || value.url || value.file || value.href || '';
        var type = value.type || value.mimeType || mimeType || '';
        if (src) {
          rememberRuntimeSourceHint(src, 'player', type);
          addResult(src, 'player', { signal: 'video_element', mimeType: type });
        }
        try {
          scanTextForUrls(JSON.stringify(value), 'player', 'video_element');
        } catch (e) {
        }
      }
    }

    function addRuntimePlayerSource(value, mimeType) {
      if (!value) return;
      if (typeof value === 'string') {
        rememberRuntimeSourceHint(value, 'player', mimeType);
        addRuntimeResult(value, 'player', {
          signal: 'video_element',
          mimeType: mimeType
        });
        return;
      }
      if (typeof value !== 'object') return;
      var type = value.type || value.mimeType || value.mime || mimeType || '';
      var names = probeConfiguration.mediaFieldNames || [];
      for (var i = 0; i < names.length; i++) {
        var item = value[names[i]];
        if (typeof item === 'string' && item.length > 0) {
          rememberRuntimeSourceHint(item, 'player', type || inferMimeForMediaField(names[i], item));
          addRuntimeResult(item, 'player', {
            signal: 'video_element',
            mimeType: type || inferMimeForMediaField(names[i], item)
          });
        } else if (Array.isArray(item)) {
          for (var arrayIndex = 0; arrayIndex < item.length && arrayIndex < 16; arrayIndex++) {
            addRuntimePlayerSource(item[arrayIndex], type);
          }
        }
      }
      try {
        scanRuntimeMediaText(JSON.stringify(value), 'player', 'video_element');
      } catch (e) {
      }
    }

    function scanRuntimeMediaText(text, source, signal) {
      var normalizedText = normalizeText(text);
      mediaUrlPattern.lastIndex = 0;
      var match;
      while ((match = mediaUrlPattern.exec(normalizedText)) !== null &&
        window.__airaVideoDeepProbeResults.length < 80) {
        addRuntimeResult(match[0], source || 'player', { signal: signal || 'video_element' });
      }
      var structuredPattern = /["']?([A-Za-z_$][A-Za-z0-9_$-]{0,63})["']?\\s*[:=]\\s*["']((?:https?:\\/\\/|\\/\\/|\\/)[^"'<>\\s]{8,2000})["']/ig;
      while ((match = structuredPattern.exec(normalizedText)) !== null &&
        window.__airaVideoDeepProbeResults.length < 80) {
        if (isMediaFieldName(match[1]) && looksLikeStructuredMediaUrl(match[1], match[2])) {
          addRuntimeResult(match[2], source || 'player', {
            signal: signal || 'video_element',
            mimeType: inferMimeForMediaField(match[1], match[2])
          });
        }
      }
    }

    function scanPlayerObjectMediaFields(root, source, signal) {
      var seenObjects = [];
      function visit(value, depth, keyHint) {
        if (!value || depth > 4 || results.length >= 80) return;
        if (typeof value === 'string') {
          if (value.length > 0 && value.length < 4000) {
            if (looksLikeStructuredMediaUrl(keyHint || 'url', value)) {
              addResult(value, source || 'player', {
                signal: signal || 'video_element',
                mimeType: inferMimeForMediaField(keyHint || 'url', value)
              });
            } else {
              scanTextForUrls(value, source || 'player', signal || 'video_element');
            }
          }
          return;
        }
        if (typeof value !== 'object' && typeof value !== 'function') return;
        if (value === window || value === document || value.nodeType || seenObjects.indexOf(value) >= 0) return;
        seenObjects.push(value);
        var directNames = probeConfiguration.mediaFieldNames || [];
        for (var directIndex = 0; directIndex < directNames.length; directIndex++) {
          try {
            var direct = value[directNames[directIndex]];
            if (typeof direct === 'string' && direct.length > 0) {
              addPlayerSource(direct, value.type || value.mimeType || value.mime ||
                inferMimeForMediaField(directNames[directIndex], direct));
            }
          } catch (directError) {
          }
        }
        var keys = [];
        try {
          keys = Object.keys(value);
        } catch (keysError) {
          return;
        }
        for (var i = 0; i < keys.length && i < 80 && results.length < 80; i++) {
          var key = keys[i];
          if (key === 'window' || key === 'document' || key === 'parent' || key === 'top' ||
            key === 'ownerDocument' || key === 'el_' || key === 'eventBusEl_') {
            continue;
          }
          if (!isMediaFieldName(key) &&
            !/(url|src|source|file|hls|vhs|m3u8|mpd|dash|media|manifest|playlist|level|frag|stream)/i.test(key) &&
            depth >= 2) {
            continue;
          }
          try {
            visit(value[key], depth + 1, key);
          } catch (visitError) {
          }
        }
      }
      visit(root, 0, '');
    }

    function collectMediaElements(root, output, depth) {
      if (!root || depth > 3 || output.length >= 64) return;
      try {
        var elements = root.querySelectorAll ? root.querySelectorAll('video, audio') : [];
        for (var index = 0; index < elements.length && output.length < 64; index++) {
          output.push(elements[index]);
        }
        var frames = root.querySelectorAll ? root.querySelectorAll('iframe,frame') : [];
        for (var frameIndex = 0; frameIndex < frames.length && output.length < 64; frameIndex++) {
          try {
            var doc = frames[frameIndex].contentDocument;
            if (doc) {
              collectMediaElements(doc, output, depth + 1);
            }
          } catch (e) {
          }
        }
      } catch (e) {
      }
    }

    function isVisibleMedia(el) {
      try {
        var rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { width: 0, height: 0 };
        var viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
        var viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
        return rect.width > 8 && rect.height > 8 &&
          rect.bottom > 0 && rect.right > 0 &&
          rect.top < viewportHeight && rect.left < viewportWidth;
      } catch (e) {
        return true;
      }
    }

    function mediaArea(el) {
      try {
        var rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { width: 0, height: 0 };
        return Math.max(0, rect.width || 0) * Math.max(0, rect.height || 0);
      } catch (e) {
        return 0;
      }
    }

    function scoreMedia(el) {
      var score = mediaArea(el);
      if (!el.paused && !el.ended) {
        score += 1000000;
      }
      if ((el.currentTime || 0) > 0) {
        score += 200000;
      }
      if ((el.readyState || 0) >= 2) {
        score += 100000;
      }
      if ((el.videoWidth || 0) > 0 && (el.videoHeight || 0) > 0) {
        score += 50000;
      }
      if (isVisibleMedia(el)) {
        score += 10000;
      }
      return score;
    }

    function mediaSignal(el) {
      return el.tagName && String(el.tagName).toLowerCase() === 'audio' ? 'audio_element' : 'video_element';
    }

    function addSourceRecord(records, url, mimeType) {
      if (!url) return;
      records.push({
        url: url,
        mimeType: mimeType || undefined
      });
    }

    function collectSourceRecords(el) {
      var records = [];
      var elementType = el.getAttribute && el.getAttribute('type') ? el.getAttribute('type') : '';
      addSourceRecord(records, el.currentSrc || '', elementType);
      addSourceRecord(records, el.src || '', elementType);
      addSourceRecord(records, el.getAttribute ? el.getAttribute('src') : '', elementType);
      try {
        var sources = el.querySelectorAll ? el.querySelectorAll('source') : [];
        for (var sourceIndex = 0; sourceIndex < sources.length && sourceIndex < 8; sourceIndex++) {
          addSourceRecord(
            records,
            sources[sourceIndex].src || sources[sourceIndex].getAttribute('src') || '',
            sources[sourceIndex].getAttribute('type') || ''
          );
        }
      } catch (e) {
      }
      var attrNames = ['data-src', 'data-source', 'data-sources', 'data-video', 'data-url', 'data-file',
        'data-stream', 'data-stream-url', 'data-play-url', 'data-playurl', 'data-hls', 'data-m3u8',
        'data-mp4', 'data-dash', 'data-mpd', 'poster'];
      for (var attrIndex = 0; attrIndex < attrNames.length; attrIndex++) {
        addSourceRecord(records, el.getAttribute ? el.getAttribute(attrNames[attrIndex]) : '', '');
      }
      return records;
    }

    function scanNearbyPlayerAttributes(el) {
      var node = el;
      for (var depth = 0; node && depth < 5; depth++) {
        try {
          var signature = String((node.id || '') + ' ' + (node.className || '')).toLowerCase();
          var likelyPlayer = depth === 0 || signature.indexOf('player') >= 0 || signature.indexOf('video') >= 0 ||
            signature.indexOf('dplayer') >= 0 || signature.indexOf('xgplayer') >= 0 ||
            signature.indexOf('artplayer') >= 0 || signature.indexOf('jwplayer') >= 0 ||
            signature.indexOf('prism') >= 0;
          if (likelyPlayer && node.attributes) {
            for (var attrIndex = 0; attrIndex < node.attributes.length && attrIndex < 32; attrIndex++) {
              var value = node.attributes[attrIndex] ? node.attributes[attrIndex].value : '';
              if (value && /(?:https?:\\/\\/|\\/\\/|\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm))/i.test(value)) {
                scanTextForUrls(value, 'dom', mediaSignal(el));
              }
            }
          }
        } catch (e) {
        }
        node = node.parentElement;
      }
    }

    function installPlayerSourceHooks() {
      try {
        var videojsRef = window.videojs;
        if (videojsRef) {
          var players = {};
          if (typeof videojsRef.getPlayers === 'function') {
            players = videojsRef.getPlayers() || {};
          } else if (videojsRef.players) {
            players = videojsRef.players;
          }
          Object.keys(players).forEach(function(key) {
            hookPlayerSrc(players[key]);
          });
        }
      } catch (e) {
      }
      try {
        if (window.player) {
          hookPlayerSrc(window.player);
        }
      } catch (playerError) {
      }
    }

    function hookPlayerSrc(player) {
      try {
        if (!player || player.__airaSrcHookInstalled || typeof player.src !== 'function') return;
        var originalSrc = player.src;
        player.__airaSrcHookInstalled = true;
        player.src = function(value) {
          try {
            addRuntimePlayerSource(value, value && (value.type || value.mimeType || value.mime));
          } catch (recordError) {
          }
          return originalSrc.apply(this, arguments);
        };
        player.src.toString = function() { return originalSrc.toString(); };
      } catch (e) {
      }
    }

    function scanVideoJsPlayers() {
      try {
        if (!window.videojs) return;
        var players = {};
        if (typeof window.videojs.getPlayers === 'function') {
          players = window.videojs.getPlayers() || {};
        } else if (window.videojs.players) {
          players = window.videojs.players;
        }
        Object.keys(players).forEach(function (key) {
          var player = players[key];
          if (!player) return;
          var currentType = typeof player.currentType === 'function' ? player.currentType() : '';
          if (typeof player.currentSrc === 'function') {
            addPlayerSource(player.currentSrc(), currentType);
          }
          var options = player.options_ || (typeof player.options === 'function' ? player.options() : undefined);
          var sources = options && options.sources;
          if (Array.isArray(sources)) {
            sources.forEach(function (item) { addPlayerSource(item, currentType); });
          }
          var cache = player.cache_ || {};
          addPlayerSource(cache.src, currentType);
          if (player.tech_ && player.tech_.el_) {
            addPlayerSource(player.tech_.el_.currentSrc || player.tech_.el_.src || '', currentType);
          }
          scanPlayerObjectMediaFields(player.options_ || {}, 'player', 'video_element');
          scanPlayerObjectMediaFields(player.cache_ || {}, 'player', 'video_element');
          scanPlayerObjectMediaFields(player.tech_ || {}, 'player', 'video_element');
          if (player.tech_ && player.tech_.sourceHandler_) {
            scanPlayerObjectMediaFields(player.tech_.sourceHandler_, 'player', 'video_element');
          }
        });
      } catch (e) {
      }
    }

    function scanArtPlayerInstances() {
      try {
        var instances = [];
        if (window.Artplayer && Array.isArray(window.Artplayer.instances)) {
          instances = window.Artplayer.instances;
        }
        for (var instanceIndex = 0; instanceIndex < instances.length && instanceIndex < 8; instanceIndex++) {
          var art = instances[instanceIndex];
          if (!art) continue;
          var option = art.option || {};
          addPlayerSource(option.url || '', option.type || '');
          try {
            var quality = option.quality || [];
            if (Array.isArray(quality)) {
              for (var qualityIndex = 0; qualityIndex < quality.length && qualityIndex < 16; qualityIndex++) {
                addPlayerSource(quality[qualityIndex], option.type || '');
              }
              scanTextForUrls(JSON.stringify(quality), 'player', 'video_element');
            }
          } catch (e) {
          }
          if (art.video) {
            addPlayerSource(art.video.currentSrc || art.video.src || '', option.type || '');
          }
          if (art.template && art.template.$video) {
            addPlayerSource(art.template.$video.currentSrc || art.template.$video.src || '', option.type || '');
          }
        }
      } catch (e) {
      }
    }

    function scanJwPlayerInstances() {
      try {
        if (typeof window.jwplayer !== 'function') return;
        var players = [];
        try {
          var defaultPlayer = window.jwplayer();
          if (defaultPlayer) {
            players.push(defaultPlayer);
          }
        } catch (e) {
        }
        try {
          var nodes = document.querySelectorAll('.jwplayer, [id*="jwplayer"], [id*="player"]');
          for (var nodeIndex = 0; nodeIndex < nodes.length && nodeIndex < 16; nodeIndex++) {
            var id = nodes[nodeIndex].id || '';
            if (!id) continue;
            try {
              var player = window.jwplayer(id);
              if (player) {
                players.push(player);
              }
            } catch (nodeError) {
            }
          }
        } catch (nodeScanError) {
        }
        for (var playerIndex = 0; playerIndex < players.length && playerIndex < 16; playerIndex++) {
          var jw = players[playerIndex];
          if (!jw) continue;
          try {
            if (typeof jw.getPlaylist === 'function') {
              scanTextForUrls(JSON.stringify(jw.getPlaylist() || []), 'player', 'video_element');
            }
          } catch (playlistError) {
          }
          try {
            if (typeof jw.getConfig === 'function') {
              scanTextForUrls(JSON.stringify(jw.getConfig() || {}), 'player', 'video_element');
            }
          } catch (configError) {
          }
          try {
            if (typeof jw.getPlaylistItem === 'function') {
              var item = jw.getPlaylistItem();
              addPlayerSource(item && (item.file || item.src || item.url || ''), item && (item.type || item.mimeType || ''));
              scanTextForUrls(JSON.stringify(item || {}), 'player', 'video_element');
            }
          } catch (itemError) {
          }
        }
      } catch (e) {
      }
    }

    function scanDPlayerInstances() {
      try {
        var instances = [];
        if (window.DPlayer && Array.isArray(window.DPlayer.instances)) {
          instances = window.DPlayer.instances;
        }
        var globalNames = ['dp', 'dplayer'];
        for (var globalIndex = 0; globalIndex < globalNames.length; globalIndex++) {
          var candidate = window[globalNames[globalIndex]];
          if (candidate) {
            instances.push(candidate);
          }
        }
        for (var instanceIndex = 0; instanceIndex < instances.length && instanceIndex < 8; instanceIndex++) {
          var dp = instances[instanceIndex];
          if (!dp) continue;
          var options = dp.options || dp.option || {};
          addPlayerSource(options.video && (options.video.url || options.video.src || ''), options.video && (options.video.type || ''));
          try {
            scanTextForUrls(JSON.stringify(options.video || options || {}), 'player', 'video_element');
          } catch (optionError) {
          }
          if (dp.video) {
            addPlayerSource(dp.video.currentSrc || dp.video.src || '', options.video && (options.video.type || ''));
          }
        }
      } catch (e) {
      }
    }

    function scanMetaMediaTags() {
      try {
        var metas = document.querySelectorAll('meta[property], meta[name], link[itemprop], [itemprop="contentUrl"], [itemprop="embedUrl"]');
        for (var i = 0; i < metas.length && i < 120 && results.length < 80; i++) {
          var node = metas[i];
          var key = String((node.getAttribute('property') || node.getAttribute('name') || node.getAttribute('itemprop') || '')).toLowerCase();
          if (key.indexOf('og:video') < 0 && key.indexOf('og:audio') < 0 &&
            key.indexOf('twitter:player:stream') < 0 && key !== 'contenturl' && key !== 'embedurl') {
            continue;
          }
          var value = node.getAttribute('content') || node.getAttribute('value') || node.getAttribute('href') || '';
          if (value) {
            scanTextForUrls(value, 'dom', 'embedded_attribute');
          }
        }
      } catch (e) {
      }
    }

    function hasEmbeddedMediaParameter(url) {
      var lower = String(url || '').toLowerCase();
      return lower.indexOf('?url=') >= 0 || lower.indexOf('&url=') >= 0 ||
        lower.indexOf('?src=') >= 0 || lower.indexOf('&src=') >= 0 ||
        lower.indexOf('?file=') >= 0 || lower.indexOf('&file=') >= 0 ||
        lower.indexOf('?video=') >= 0 || lower.indexOf('&video=') >= 0;
    }

    function isLikelyEmbeddedPlayerUrl(value) {
      var normalized = normalizeUrl(value || '');
      if (!/^https?:/i.test(normalized)) return false;
      try {
        var parsed = new URL(normalized, location.href);
        var host = String(parsed.hostname || '').toLowerCase();
        var path = String(parsed.pathname || '').toLowerCase();
        return hasEmbeddedMediaParameter(parsed.href) ||
          host.indexOf('player.') === 0 ||
          host.indexOf('.player.') >= 0 ||
          host.indexOf('play.') === 0 ||
          host.indexOf('.play.') >= 0 ||
          path.indexOf('/player/') >= 0 ||
          path.indexOf('/embed/') >= 0 ||
          path.indexOf('/v2player') >= 0 ||
          path === '/player' ||
          path === '/embed';
      } catch (e) {
        return false;
      }
    }

    function addEmbeddedPlayerUrl(value) {
      if (!isLikelyEmbeddedPlayerUrl(value)) return;
      addResult(value, 'dom', {
        signal: 'embedded_attribute',
        referer: currentReferer(),
        originUrl: currentOrigin(),
        userAgent: currentUserAgent()
      });
    }

    function scanEmbeddedPlayerEntries() {
      try {
        var frames = document.querySelectorAll('iframe[src], frame[src], embed[src], object[data], [data-player], [data-embed]');
        for (var i = 0; i < frames.length && i < 120 && results.length < 80; i++) {
          var node = frames[i];
          addEmbeddedPlayerUrl(node.src || node.getAttribute('src') || '');
          addEmbeddedPlayerUrl(node.data || node.getAttribute('data') || '');
          addEmbeddedPlayerUrl(node.getAttribute('data-src') || '');
          addEmbeddedPlayerUrl(node.getAttribute('data-url') || '');
          addEmbeddedPlayerUrl(node.getAttribute('data-player') || '');
          addEmbeddedPlayerUrl(node.getAttribute('data-embed') || '');
        }
      } catch (e) {
      }
      try {
        var metas = document.querySelectorAll('meta[property], meta[name], link[itemprop], [itemprop="embedUrl"], [itemprop="contentUrl"]');
        for (var metaIndex = 0; metaIndex < metas.length && metaIndex < 120 && results.length < 80; metaIndex++) {
          var meta = metas[metaIndex];
          var key = String((meta.getAttribute('property') || meta.getAttribute('name') || meta.getAttribute('itemprop') || '')).toLowerCase();
          if (key.indexOf('twitter:player') < 0 && key.indexOf('og:video') < 0 &&
            key !== 'embedurl' && key !== 'contenturl') {
            continue;
          }
          addEmbeddedPlayerUrl(meta.getAttribute('content') || meta.getAttribute('value') || meta.getAttribute('href') || '');
        }
      } catch (e) {
      }
    }

    function scanJsonLdScripts() {
      try {
        var scripts = document.querySelectorAll('script[type*="ld+json"]');
        for (var i = 0; i < scripts.length && i < 24 && results.length < 80; i++) {
          var text = scripts[i].textContent || '';
          if (text.length > 220000) {
            text = text.substring(0, 220000);
          }
          scanTextForUrls(text, 'script_text', 'script_text');
        }
      } catch (e) {
      }
    }

    function scanLikelyPlayerConfigNodes() {
      try {
        var nodes = document.querySelectorAll('[data-setup], [data-config], [data-options], [data-player], [data-video], [data-file], [data-hls], [data-m3u8], [data-src], [data-url], video-js, .video-js, .jwplayer, [id*="player"], [class*="player"]');
        for (var i = 0; i < nodes.length && i < 120 && results.length < 80; i++) {
          var node = nodes[i];
          if (!node || !node.attributes) continue;
          for (var attrIndex = 0; attrIndex < node.attributes.length && attrIndex < 64 && results.length < 80; attrIndex++) {
            var value = node.attributes[attrIndex] ? node.attributes[attrIndex].value : '';
            if (value && /(?:https?:\\/\\/|\\/\\/|\\/|\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)|url|src|file|source|video)/i.test(value)) {
              scanTextForUrls(value, 'dom', 'embedded_attribute');
            }
          }
        }
      } catch (e) {
      }
    }

    function scanKnownGlobalConfigs() {
      try {
        var names = probeConfiguration.globalConfigNames || [];
        for (var i = 0; i < names.length && results.length < 80; i++) {
          var value = window[names[i]];
          if (!value) continue;
          if (typeof value === 'string') {
            scanTextForUrls(value, 'script_text', 'script_text');
          } else if (typeof value === 'object') {
            try {
              var text = JSON.stringify(value);
              if (text.length > 300000) {
                text = text.substring(0, 300000);
              }
              scanTextForUrls(text, 'script_text', 'script_text');
            } catch (e) {
            }
          }
        }
      } catch (e) {
      }
    }

    function addXlPlayerLineUrl(value, key, persistRuntime) {
      if (!value) return;
      var urls = String(value).substring(0, 120000).split(',');
      for (var i = 0; i < urls.length && i < 24; i++) {
        var url = String(urls[i] || '').substring(0, 8000);
        if (!url) continue;
        var extra = {
          signal: 'script_text',
          mimeType: inferMimeForMediaField(key || 'url', url)
        };
        if (persistRuntime === true) {
          addRuntimeResult(url, 'player', extra);
        }
        if (results.length < 80) {
          addResult(url, 'player', extra);
        }
      }
    }

__AIRA_XLPLAYER_LINES_RUNTIME_FRAGMENT__

    function scanMediaElements() {
      var elements = [];
      collectMediaElements(document, elements, 0);
      elements.sort(function (left, right) {
        return scoreMedia(right) - scoreMedia(left);
      });
      for (var i = 0; i < elements.length && i < 48; i++) {
        var el = elements[i];
        var signal = mediaSignal(el);
        var records = collectSourceRecords(el);
        for (var recordIndex = 0; recordIndex < records.length && recordIndex < 12; recordIndex++) {
          addResult(records[recordIndex].url, 'dom', {
            signal: signal,
            mimeType: records[recordIndex].mimeType,
            posterUrl: el.poster || undefined,
            durationMs: isFinite(el.duration) && el.duration > 0 ? Math.round(el.duration * 1000) : undefined,
            width: el.videoWidth || undefined,
            height: el.videoHeight || undefined
          });
        }
        scanNearbyPlayerAttributes(el);
      }
    }

    function scanPerformanceEntryUrl(value) {
      var normalizedText = normalizeText(value || '');
      if (!normalizedText) return;
      mediaUrlPattern.lastIndex = 0;
      var match;
      while ((match = mediaUrlPattern.exec(normalizedText)) !== null && results.length < 80) {
        addResult(match[0], 'performance', { signal: 'performance_entry' });
      }
      scanStructuredMediaFields(normalizedText, 'performance', 'performance_entry');
      scanPlayerMethodMediaUrls(normalizedText, 'performance', 'performance_entry');
      scanQueryStyleMediaFields(normalizedText, 'performance', 'performance_entry');
    }

    function performanceEntryCheckpoint(entry) {
      if (!entry) return '';
      return String(entry.name || '') + '|' + String(entry.startTime || 0) + '|' +
        String(entry.duration || 0) + '|' + String(entry.initiatorType || '');
    }

    function scanPerformanceEntries() {
      try {
        var entries = performance && performance.getEntriesByType ? performance.getEntriesByType('resource') : [];
        var cursor = Number(window.__airaVideoDeepProbePerformanceCursor || 0);
        if (!isFinite(cursor) || cursor < 0 || cursor > entries.length) {
          cursor = 0;
        }
        var checkpoint = String(window.__airaVideoDeepProbePerformanceCheckpoint || '');
        if (cursor > 0 && checkpoint && performanceEntryCheckpoint(entries[cursor - 1]) !== checkpoint) {
          cursor = 0;
        }
        var end = Math.min(entries.length, cursor + 300);
        for (var i = cursor; i < end; i++) {
          scanPerformanceEntryUrl(entries[i].name || '');
        }
        window.__airaVideoDeepProbePerformanceCursor = end;
        window.__airaVideoDeepProbePerformanceCheckpoint = end > 0 ?
          performanceEntryCheckpoint(entries[end - 1]) : '';
      } catch (e) {
      }
    }

    function shouldScanInlineScriptNode(scriptNode, observers, dirtyScripts) {
      if (!scriptNode || !observers || !dirtyScripts || typeof MutationObserver !== 'function') {
        return true;
      }
      var observer = observers.get(scriptNode);
      if (!observer) {
        try {
          observer = new MutationObserver(function() {
            dirtyScripts.add(scriptNode);
          });
          observer.observe(scriptNode, {
            childList: true,
            characterData: true,
            subtree: true
          });
          observers.set(scriptNode, observer);
        } catch (observerError) {
          return true;
        }
        return true;
      }
      if (dirtyScripts.has(scriptNode)) {
        dirtyScripts.delete(scriptNode);
        return true;
      }
      return false;
    }

    function scanInlineScriptNode(scriptNode, observers, dirtyScripts) {
      if (!shouldScanInlineScriptNode(scriptNode, observers, dirtyScripts)) {
        return 0;
      }
      var text = scriptNode && scriptNode.textContent ? scriptNode.textContent : '';
      if (!text) return 0;
      if (text.length > 220000) {
        text = text.substring(0, 220000);
      }
      scanTextForUrls(text, 'script_text', 'script_text');
      return text.length;
    }

    function scanInlineScripts() {
      var scripts = document.querySelectorAll('script:not([src])');
      if (!scripts || scripts.length <= 0) return;
      var observers = window.__airaVideoDeepProbeInlineScriptObservers;
      var dirtyScripts = window.__airaVideoDeepProbeDirtyInlineScripts;
      var scannedChars = 0;
      var primaryLimit = Math.min(scripts.length, 32);
      for (var primaryIndex = 0;
        primaryIndex < primaryLimit && scannedChars < 900000 && results.length < 80;
        primaryIndex++) {
        scannedChars += scanInlineScriptNode(scripts[primaryIndex], observers, dirtyScripts);
      }
      if (window.__airaVideoDeepProbeInlineScriptInitialized !== true) {
        window.__airaVideoDeepProbeInlineScriptInitialized = true;
        window.__airaVideoDeepProbeInlineScriptCursor = primaryLimit;
        return;
      }
      var cursor = Number(window.__airaVideoDeepProbeInlineScriptCursor || primaryLimit);
      if (!isFinite(cursor) || cursor < primaryLimit || cursor >= scripts.length) {
        cursor = primaryLimit;
      }
      var tailInspected = 0;
      while (cursor < scripts.length && tailInspected < 32 && scannedChars < 900000 && results.length < 80) {
        scannedChars += scanInlineScriptNode(scripts[cursor], observers, dirtyScripts);
        cursor += 1;
        tailInspected += 1;
      }
      window.__airaVideoDeepProbeInlineScriptCursor = cursor >= scripts.length ? primaryLimit : cursor;
    }

    function recentEventsForUrl(url) {
      var normalized = normalizeUrl(url || '');
      var events = window.__airaMediaDiagnosticEvents || [];
      var result = [];
      for (var i = Math.max(0, events.length - 12); i < events.length; i++) {
        var item = events[i] || {};
        var itemUrl = normalizeUrl(item.url || '');
        if (!normalized || !itemUrl || normalized === itemUrl) {
          result.push(String(item.type || 'event'));
        }
      }
      return result.slice(-6);
    }

    function collectPlaybackDiagnostics() {
      var mediaElements = [];
      var telegramKinds = [];
      var kindSeen = Object.create(null);
      var elements = [];
      collectMediaElements(document, elements, 0);
      elements.sort(function (left, right) {
        return scoreMedia(right) - scoreMedia(left);
      });
      for (var i = 0; i < elements.length && i < 8; i++) {
        var el = elements[i];
        var mediaError = el.error || {};
        var src = el.currentSrc || el.src || '';
        var kind = classifyMediaUrl(src);
        if (kind.indexOf('telegram_') === 0 && !kindSeen[kind]) {
          kindSeen[kind] = true;
          telegramKinds.push(kind);
        }
        mediaElements.push({
          tagName: String(el.tagName || '').toLowerCase(),
          url: src,
          urlKind: kind,
          networkState: typeof el.networkState === 'number' ? el.networkState : 0,
          readyState: typeof el.readyState === 'number' ? el.readyState : 0,
          errorCode: typeof mediaError.code === 'number' ? mediaError.code : 0,
          errorMessage: mediaError.message ? String(mediaError.message).slice(0, 120) : '',
          recentEvents: recentEventsForUrl(src)
        });
      }
      var probeVideo = document.createElement('video');
      var mediaSourceAvailable = typeof window.MediaSource !== 'undefined';
      var mseMp4Supported = false;
      try {
        mseMp4Supported = mediaSourceAvailable &&
          MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E, mp4a.40.2"') === true;
      } catch (e) {
      }
      return [{
        pageUrl: location.href || '',
        userAgent: currentUserAgent(),
        serviceWorkerAvailable: !!(navigator && navigator.serviceWorker),
        serviceWorkerControlled: !!(navigator && navigator.serviceWorker && navigator.serviceWorker.controller),
        serviceWorkerControllerState: navigator && navigator.serviceWorker && navigator.serviceWorker.controller ?
          String(navigator.serviceWorker.controller.state || '') : '',
        mediaSourceAvailable: mediaSourceAvailable,
        mseMp4Supported: mseMp4Supported,
        canPlayMp4: probeVideo.canPlayType ? probeVideo.canPlayType('video/mp4; codecs="avc1.42E01E, mp4a.40.2"') : '',
        canPlayHls: probeVideo.canPlayType ? (probeVideo.canPlayType('application/vnd.apple.mpegurl') ||
          probeVideo.canPlayType('application/x-mpegURL')) : '',
        telegramUrlKinds: telegramKinds,
        mediaElements: mediaElements
      }];
    }

    installRuntimeHooks();
    installPlayerSourceHooks();
    var runtimeResults = window.__airaVideoDeepProbeResults || [];
    for (var runtimeIndex = 0; runtimeIndex < runtimeResults.length && runtimeIndex < 80; runtimeIndex++) {
      var runtimeItem = runtimeResults[runtimeIndex] || {};
      addResult(runtimeItem.url || '', runtimeItem.source || 'manifest_text', {
        signal: runtimeItem.signal || 'script_text',
        mimeType: runtimeItem.mimeType || undefined,
        manifestText: runtimeItem.manifestText || undefined,
        manifestBaseUrl: runtimeItem.manifestBaseUrl || undefined,
        pairedAudioUrl: runtimeItem.pairedAudioUrl || undefined,
        pairedAudioMimeType: runtimeItem.pairedAudioMimeType || undefined,
        codecs: runtimeItem.codecs || undefined,
        bandwidth: runtimeItem.bandwidth || undefined,
        initializationRange: runtimeItem.initializationRange || undefined,
        indexRange: runtimeItem.indexRange || undefined,
        pairedAudioCodecs: runtimeItem.pairedAudioCodecs || undefined,
        pairedAudioBandwidth: runtimeItem.pairedAudioBandwidth || undefined,
        pairedAudioInitializationRange: runtimeItem.pairedAudioInitializationRange || undefined,
        pairedAudioIndexRange: runtimeItem.pairedAudioIndexRange || undefined
      });
    }
    if (strategyEnabled('player_adapters')) {
      scanVideoJsPlayers();
      scanArtPlayerInstances();
      scanJwPlayerInstances();
      scanDPlayerInstances();
    }
    if (strategyEnabled('metadata')) {
      scanMetaMediaTags();
      scanEmbeddedPlayerEntries();
      scanJsonLdScripts();
    }
    if (strategyEnabled('player_configs')) {
      scanLikelyPlayerConfigNodes();
      scanKnownGlobalConfigs();
    }
    if (strategyEnabled('vendor_adapters')) scanXlPlayerLinesEndpoint();
    scanMediaElements();
    if (strategyEnabled('performance_entries')) scanPerformanceEntries();
    if (strategyEnabled('location')) scanTextForUrls(location.href || '', 'dom', 'location');
    if (strategyEnabled('inline_scripts')) scanInlineScripts();
    return JSON.stringify({
      ok: true,
      results: results.slice(0, 80),
      diagnostics: collectPlaybackDiagnostics(),
      pendingAsyncWork: pendingAsyncWork
    });
  } catch (e) {
    return JSON.stringify({ ok: false, results: [], error: String((e && e.message) || e) });
  }
})();`;

export class MediaVideoDeepProbeScript {
  build(
    allowBlockingFallback: boolean = false,
    configuration: MediaVideoDeepProbeConfiguration = DEFAULT_DEEP_PROBE_CONFIGURATION
  ): string {
    return DEEP_PROBE_SCRIPT.replace(
      '__AIRA_ALLOW_BLOCKING_FALLBACK__',
      allowBlockingFallback ? 'true' : 'false'
    ).replace(
      '__AIRA_DEEP_PROBE_CONFIGURATION__',
      JSON.stringify(configuration)
    ).replace(
      '__AIRA_XLPLAYER_LINES_RUNTIME_FRAGMENT__',
      VIDEO_COMPATIBILITY_XLPLAYER_LINES_RUNTIME_FRAGMENT
    );
  }

  parse(raw: string): MediaVideoDeepProbePayload {
    if (raw.length === 0) {
      return { ok: false, results: [], error: 'empty_result' };
    }
    try {
      const parsed: MediaVideoDeepProbePayload = JSON.parse(raw) as MediaVideoDeepProbePayload;
      if (typeof parsed.ok !== 'boolean' || !Array.isArray(parsed.results)) {
        return { ok: false, results: [], error: 'bad_shape' };
      }
      return parsed;
    } catch (error) {
      const message = (error as Error)?.message ?? 'parse_error';
      return { ok: false, results: [], error: message };
    }
  }

}

export function buildVideoPlaybackDiagnosticSummary(diagnostics: VideoPlaybackDiagnosticSnapshot[] | undefined): string {
  if (diagnostics === undefined || diagnostics.length <= 0) {
    return '';
  }
  const snapshot = diagnostics[0];
  const media = selectDiagnosticMediaElement(snapshot.mediaElements);
  const parts: string[] = [];
  parts.push(snapshot.serviceWorkerControlled ? 'SW=接管' : 'SW=未接管');
  if (media !== undefined) {
    parts.push(media.errorCode > 0 ? `video.error=${media.errorCode}` : `ready=${media.readyState}`);
    if (media.urlKind.length > 0 && media.urlKind !== 'none') {
      parts.push(`URL=${media.urlKind}`);
    }
    if (media.recentEvents.length > 0) {
      parts.push(`事件=${media.recentEvents.slice(-4).join('>')}`);
    }
    const diagnosis = buildTelegramPlaybackDiagnosis(snapshot, media);
    if (diagnosis.length > 0) {
      parts.push(`判断=${diagnosis}`);
    }
  } else {
    parts.push('未发现video元素');
  }
  parts.push(snapshot.mediaSourceAvailable ? `MSE=${snapshot.mseMp4Supported ? 'mp4可用' : '可用'}` : 'MSE=无');
  if (snapshot.canPlayHls.length > 0) {
    parts.push(`HLS=${snapshot.canPlayHls}`);
  }
  return `媒体诊断：${parts.join('，')}`;
}

function buildTelegramPlaybackDiagnosis(
  snapshot: VideoPlaybackDiagnosticSnapshot,
  media: VideoPlaybackElementDiagnostic
): string {
  if (!snapshot.serviceWorkerControlled || media.errorCode !== 4 || !isTelegramServiceWorkerMediaUrl(media.urlKind)) {
    return '';
  }
  if (media.urlKind === 'telegram_progressive' || media.urlKind === 'telegram_stream') {
    return 'Telegram SW流失败';
  }
  if (media.urlKind === 'telegram_hls_stream' || media.urlKind === 'telegram_hls') {
    return 'Telegram SW-HLS失败';
  }
  return 'Telegram SW媒体失败';
}

function isTelegramServiceWorkerMediaUrl(urlKind: string): boolean {
  return urlKind === 'telegram_progressive' ||
    urlKind === 'telegram_stream' ||
    urlKind === 'telegram_hls_stream' ||
    urlKind === 'telegram_hls';
}

function selectDiagnosticMediaElement(
  elements: VideoPlaybackElementDiagnostic[] | undefined
): VideoPlaybackElementDiagnostic | undefined {
  if (elements === undefined || elements.length <= 0) {
    return undefined;
  }
  for (let i = 0; i < elements.length; i++) {
    if (elements[i].errorCode > 0) {
      return elements[i];
    }
  }
  return elements[0];
}

export function extractDeepProbeMediaUrlsFromText(text: string): string[] {
  const normalizedText = normalizeDeepProbeText(text);
  const pattern = /(?:https?:\/\/|\/\/)[^"'<>\s]+?\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\s])(?:[?#][^"'<>\s]*)?/ig;
  const results: string[] = [];
  const seen: Record<string, boolean> = {};
  collectDeepProbeUrls(normalizedText, pattern, results, seen, 80);
  collectStructuredDeepProbeFieldUrls(normalizedText, results, seen, 80);
  collectDeepProbePlayerMethodUrls(normalizedText, results, seen, 80);
  collectDeepProbeQueryStyleFieldUrls(normalizedText, results, seen, 80);
  const encodedFields = extractEncodedPlayerFields(normalizedText);
  for (let i = 0; i < encodedFields.length && results.length < 80; i++) {
    const decoded = decodeBase64DeepProbeText(encodedFields[i]);
    if (decoded.length > 0) {
      const normalizedDecoded = normalizeDeepProbeText(decoded);
      collectDeepProbeUrls(normalizedDecoded, pattern, results, seen, 80);
      collectStructuredDeepProbeFieldUrls(normalizedDecoded, results, seen, 80);
      collectDeepProbePlayerMethodUrls(normalizedDecoded, results, seen, 80);
      collectDeepProbeQueryStyleFieldUrls(normalizedDecoded, results, seen, 80);
    }
  }
  return results;
}

function collectDeepProbeUrls(
  text: string,
  pattern: RegExp,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  pattern.lastIndex = 0;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && results.length < limit) {
    const normalizedUrl = normalizeDeepProbeText(match[0]);
    const finalUrl = normalizedUrl.indexOf('//') === 0 ? `https:${normalizedUrl}` : normalizedUrl;
    if (seen[finalUrl] !== true && !isLikelyDeepProbeMediaNoiseUrl(finalUrl)) {
      seen[finalUrl] = true;
      results.push(finalUrl);
    }
    match = pattern.exec(text);
  }
}

function addStructuredDeepProbeUrl(
  key: string,
  url: string,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  if (results.length >= limit) {
    return;
  }
  const normalizedUrl = normalizeDeepProbeText(url);
  const finalUrl = normalizedUrl.indexOf('//') === 0 ? `https:${normalizedUrl}` : normalizedUrl;
  if (looksLikeStructuredDeepProbeMediaUrl(key, finalUrl) && seen[finalUrl] !== true) {
    seen[finalUrl] = true;
    results.push(finalUrl);
  }
}

function collectStructuredDeepProbeFieldUrls(
  text: string,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  const pattern =
    /["']?(url3|url_next|url|src|file|fileUrl|file_url|source|sources|sourceUrl|source_url|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|contentUrl|content_url|downloadUrl|download_url|baseUrl|base_url|backupUrl|backup_url|m3u8|m3u8_2|m3u8Url|hls|hlsUrl|hls_url|mpd|mpdUrl|dash|dashUrl|dash_url)["']?\s*[:=]\s*["']((?:https?:\/\/|\/\/|\/)[^"'<>\s]{8,2000})["']/ig;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && results.length < limit) {
    addStructuredDeepProbeUrl(match[1], match[2], results, seen, limit);
    match = pattern.exec(text);
  }
  const relativePattern =
    /["']?(url3|url_next|url|src|file|fileUrl|file_url|source|sources|sourceUrl|source_url|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|contentUrl|content_url|downloadUrl|download_url|baseUrl|base_url|backupUrl|backup_url|m3u8|m3u8_2|m3u8Url|hls|hlsUrl|hls_url|mpd|mpdUrl|dash|dashUrl|dash_url)["']?\s*[:=]\s*["']((?:\.{1,2}\/)?[^"'<>\s\/][^"'<>\s]{0,2000}\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\s])(?:[?#][^"'<>\s]*)?)["']/ig;
  match = relativePattern.exec(text);
  while (match !== null && results.length < limit) {
    addStructuredDeepProbeUrl(match[1], match[2], results, seen, limit);
    match = relativePattern.exec(text);
  }
}

function collectDeepProbePlayerMethodUrls(
  text: string,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  const pattern =
    /(?:\b(?:loadSource|attachSource|setSrc|load|src)\s*\(\s*|\b(?:initialize|setup)\s*\([^)]{0,240}?)(["'])((?:https?:\/\/|\/\/|\/|\.{1,2}\/)?[^"'<>\s]{1,2000}\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\s])(?:[?#][^"'<>\s]*)?)\1/ig;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && results.length < limit) {
    addStructuredDeepProbeUrl('url', match[2], results, seen, limit);
    match = pattern.exec(text);
  }
}

function collectDeepProbeQueryStyleFieldUrls(
  text: string,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  const pattern =
    /(?:^|[?&#;,\s])(?:file|source|src|video_url|video|url|hls|m3u8|mpd|dash)=((?:https?:\/\/|\/\/|\/|\.{1,2}\/)?[^"'&<>\s]{1,2000}\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#&"'<>\s])(?:\?[^"'&<>\s]*)?)/ig;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && results.length < limit) {
    addStructuredDeepProbeUrl('url', match[1], results, seen, limit);
    match = pattern.exec(text);
  }
}

function looksLikeStructuredDeepProbeMediaUrl(key: string, url: string): boolean {
  if (/^(https?:|blob:)/i.test(url) !== true && /^[./A-Za-z0-9_-]/.test(url) !== true) {
    return false;
  }
  if (isLikelyDeepProbeMediaNoiseUrl(url)) {
    return false;
  }
  if (/\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?:[?#]|$)/i.test(url)) {
    return true;
  }
  if (/\/obj\/[A-Fa-f0-9]{24,}(?:[?#]|$)/.test(url)) {
    return true;
  }
  if (/(?:\/media\/|\/stream\/|\/video\/)[A-Za-z0-9_-]{32,}(?:[?#]|$)/.test(url)) {
    return true;
  }
  if (/googlevideo\.com\/videoplayback|\/videoplayback\?/i.test(url)) {
    return true;
  }
  const lowerKey = key.toLowerCase();
  return lowerKey.indexOf('m3u8') >= 0 || lowerKey.indexOf('hls') >= 0 ||
    lowerKey.indexOf('mpd') >= 0 || lowerKey.indexOf('dash') >= 0;
}

function isLikelyDeepProbeMediaNoiseUrl(value: string): boolean {
  const raw = value.toLowerCase();
  const clean = raw.split('?')[0].split('#')[0];
  if (clean.length <= 0) {
    return true;
  }
  if (/\.(?:webmanifest|json|map|js|mjs|css|html|htm|xml|wasm|svg|png|jpg|jpeg|webp|gif|ico|avif)(?:$|[?#])/i.test(raw)) {
    return true;
  }
  if (/(?:^|\/)(?:manifest\.json|site\.webmanifest|manifest\.webmanifest)$/.test(clean)) {
    return true;
  }
  return clean.indexOf('/favicon') >= 0 || clean.indexOf('/favicons/') >= 0;
}

export function hasHlsManifestText(text: string): boolean {
  return normalizeDeepProbeText(text).toUpperCase().indexOf('#EXTM3U') >= 0;
}

function normalizeDeepProbeText(value: string): string {
  let text = value;
  for (let i = 0; i < 3; i++) {
    try {
      const decoded: string = decodeURIComponent(text);
      if (decoded === text) {
        break;
      }
      text = decoded;
    } catch (_error) {
      break;
    }
  }
  return text
    .replace(/\\u002[fF]/g, '/')
    .replace(/\\\\\//g, '/')
    .replace(/\\\//g, '/')
    .replace(/&amp;/g, '&')
    .replace(/\\u0026/g, '&')
    .replace(/\\u003[dD]/g, '=')
    .replace(/\\u003[fF]/g, '?');
}

function extractEncodedPlayerFields(text: string): string[] {
  const pattern =
    /["'](?:url|url_next|src|file|source|sources|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|hls|hls_url|hlsUrl|m3u8|m3u8Url|mpd|mpdUrl|dash|dashUrl)["']\s*:\s*["']([A-Za-z0-9+/=_-]{24,})["']/ig;
  const fields: string[] = [];
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && fields.length < 24) {
    fields.push(match[1]);
    match = pattern.exec(text);
  }
  return fields;
}

function decodeBase64DeepProbeText(value: string): string {
  return normalizeDeepProbeText(decodeBase64Text(value));
}

function decodeBase64Text(value: string): string {
  let normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized) || normalized.length % 4 === 1) {
    return '';
  }
  while (normalized.length % 4 !== 0) {
    normalized += '=';
  }
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let bits = 0;
  let bitCount = 0;
  let output = '';
  for (let i = 0; i < normalized.length; i++) {
    const ch = normalized.charAt(i);
    if (ch === '=') {
      break;
    }
    const valueIndex = alphabet.indexOf(ch);
    if (valueIndex < 0) {
      return '';
    }
    bits = (bits << 6) | valueIndex;
    bitCount += 6;
    if (bitCount >= 8) {
      bitCount -= 8;
      output += String.fromCharCode((bits >> bitCount) & 0xFF);
    }
  }
  return output;
}
