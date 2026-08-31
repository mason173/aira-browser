import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NovelChapterExtract } from '../../features/novel/NovelReaderModels';
import { ComicChapterSourceRule } from '../../features/novel/NovelSiteRules';

export type ComicChapterContentKind = 'novel' | 'comic';

export const COMIC_CHAPTER_AUTHENTICATION_REQUIRED_ERROR: string =
  'comic_chapter_authentication_required';

const COMIC_ARTIFACT_MIN_IMAGE_COUNT: number = 2;
const COMIC_POLL_INTERVAL_MS: number = 200;
const COMIC_POLL_MAX_TIMES: number = 90;
const COMIC_RUN_JAVASCRIPT_TIMEOUT_MS: number = 3000;
const COMIC_ACQUISITION_TIMEOUT_MS: number = 20000;
const COMIC_SCRIPT_TIMEOUT_RESULT: string = '__aira_comic_script_timeout__';
const COMIC_LOG_DOMAIN: number = 0x0000;
const COMIC_LOG_TAG: string = 'AiraComic';
const GENERIC_RENDERED_COMIC_SOURCE: ComicChapterSourceRule = {
  kind: 'rendered_live_page_images',
  imageSelector: '[id*="chap"] img, [class*="chap"] img, [id*="reader"] img, [class*="reader"] img, ' +
    '[id*="read"] img, [class*="read"] img, [id*="comic"] img, [class*="comic"] img, article img, main img',
  imageAttributes: ['data-src', 'data-original', 'data-echo', 'data-url', 'data-path', 'src'],
  chapterPathPattern: ''
};

/**
 * Comic extraction uses reviewed local strategies. The page may provide data,
 * but it never provides executable code to this helper.
 */
const COMIC_RUNTIME_HELPERS: string = `
function airaComicIsJunkImage(url){
  if (!url){ return true; }
  var normalized = String(url).toLowerCase();
  if (normalized.indexOf('data:') === 0){ return true; }
  if (normalized.indexOf('loading') >= 0 || normalized.indexOf('click_reload') >= 0){ return true; }
  var path = normalized;
  try { path = new URL(normalized).pathname.toLowerCase(); } catch (e){ }
  if (/(^|[/_.-])404([/_.-]|$)/.test(path)){ return true; }
  if (normalized.indexOf('logo') >= 0 || normalized.indexOf('avatar') >= 0 ||
    normalized.indexOf('icon') >= 0){ return true; }
  if (normalized.indexOf('.gif') >= 0){ return true; }
  if (normalized.indexOf('blank') >= 0 || normalized.indexOf('placeholder') >= 0){ return true; }
  return false;
}
function airaComicAbs(raw, base){
  try {
    var value = String(raw || '').trim();
    if (!value || airaComicIsJunkImage(value)){ return ''; }
    return new URL(value, base).href;
  } catch (e){ return ''; }
}
function airaComicPushImage(output, seen, raw, base){
  var resolved = airaComicAbs(raw, base);
  if (!resolved || seen[resolved]){ return; }
  seen[resolved] = true;
  output.push(resolved);
}
function airaComicDecodeQuoted(value){
  if (!value || value.length < 2){ return ''; }
  var quote = value.charAt(0);
  var end = value.charAt(value.length - 1) === quote ? value.length - 1 : value.length;
  var output = '';
  for (var i = 1; i < end; i++){
    var current = value.charAt(i);
    if (current !== '\\\\'){
      output += current;
      continue;
    }
    i++;
    if (i >= end){ break; }
    var escaped = value.charAt(i);
    if (escaped === 'n'){ output += '\\n'; }
    else if (escaped === 'r'){ output += '\\r'; }
    else if (escaped === 't'){ output += '\\t'; }
    else if (escaped === 'b'){ output += '\\b'; }
    else if (escaped === 'f'){ output += '\\f'; }
    else if (escaped === 'v'){ output += '\\v'; }
    else if (escaped === 'x' && i + 2 < end){
      var hex = value.substring(i + 1, i + 3);
      if (/^[0-9a-fA-F]{2}$/.test(hex)){ output += String.fromCharCode(parseInt(hex, 16)); i += 2; }
      else { output += escaped; }
    } else if (escaped === 'u' && i + 4 < end){
      var unicode = value.substring(i + 1, i + 5);
      if (/^[0-9a-fA-F]{4}$/.test(unicode)){ output += String.fromCharCode(parseInt(unicode, 16)); i += 4; }
      else { output += escaped; }
    } else { output += escaped; }
  }
  return output;
}
function airaComicPackerToken(value, radix){
  var alphabet = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  var number = parseInt(value, 10);
  if (!isFinite(number) || number < 0 || radix < 2 || radix > alphabet.length){ return ''; }
  if (number === 0){ return '0'; }
  var token = '';
  while (number > 0){
    var digit = number % radix;
    token = alphabet.charAt(digit) + token;
    number = Math.floor(number / radix);
  }
  return token;
}
function airaComicUnpackPacker(code){
  var match = code.match(/\\}\\(\\s*(['\"](?:\\\\.|[^'\"\\\\])*['\"])\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(['\"](?:\\\\.|[^'\"\\\\])*['\"])\\.split\\(\\s*['\"]\\|['\"]\\s*\\)/);
  if (!match){ return []; }
  var payload = airaComicDecodeQuoted(match[1]);
  var radix = parseInt(match[2], 10);
  var count = parseInt(match[3], 10);
  var dictionaryText = airaComicDecodeQuoted(match[4]);
  if (!payload || !(radix >= 2 && radix <= 62) || !(count > 0 && count <= 4096)){ return []; }
  var dictionary = dictionaryText.split('|');
  var decoded = payload;
  for (var index = count - 1; index >= 0; index--){
    var token = airaComicPackerToken(index, radix);
    var replacement = dictionary[index] || token;
    if (!token || !replacement){ continue; }
    decoded = decoded.replace(new RegExp('(^|[^A-Za-z0-9_$])' + token + '([^A-Za-z0-9_$]|$)', 'g'), '$1' + replacement + '$2');
  }
  var images = [];
  var imageMatch;
  var imagePattern = /(['\"])(https?:\\/\\/[^'\"]+)\\1/g;
  while ((imageMatch = imagePattern.exec(decoded)) !== null){
    images.push(airaComicDecodeQuoted(imageMatch[1] + imageMatch[2] + imageMatch[1]));
    if (images.length >= 400){ break; }
  }
  return images;
}
function airaComicCollectPackerImages(doc){
  var scripts = doc.querySelectorAll('script');
  var output = [];
  for (var index = 0; index < scripts.length; index++){
    var code = scripts[index].textContent || '';
    if (code.indexOf('eval(function') < 0 || code.indexOf('newImgs') < 0){ continue; }
    var decoded = airaComicUnpackPacker(code);
    for (var imageIndex = 0; imageIndex < decoded.length; imageIndex++){
      output.push(decoded[imageIndex]);
    }
    if (output.length >= 2){ return output; }
  }
  return output;
}
function airaComicCollectCountBaseImages(doc, base){
  var scripts = doc.querySelectorAll('script');
  var output = [];
  for (var index = 0; index < scripts.length; index++){
    var code = scripts[index].textContent || '';
    if (code.indexOf('http') < 0){ continue; }
    var baseMatch = code.match(/[\"'](https?:\\/\\/[^\"']+\\/)[\"']/);
    var countMatch = code.match(/=\\s*(?:eval\\(\\s*)?[\"']?(\\d{1,4})[\"']?\\s*\\)?\\s*[;\\n]/);
    if (!baseMatch || !countMatch){ continue; }
    var total = parseInt(countMatch[1], 10);
    if (!(total > 0 && total <= 400)){ continue; }
    var extension = code.indexOf('.jpg') >= 0 ? '.jpg' : (code.indexOf('.png') >= 0 ? '.png' : '.webp');
    for (var number = 1; number <= total; number++){
      output.push(baseMatch[1] + number + extension);
    }
    if (output.length >= 2){ return output; }
  }
  return output;
}
function airaComicReadCmsEncryptedPayload(doc){
  var scripts = doc.querySelectorAll('script');
  for (var index = 0; index < scripts.length; index++){
    var code = scripts[index].textContent || '';
    var match = code.match(/\\bparams\\s*=\\s*(['\"])([^'\"]+)\\1/);
    if (match){ return match[2]; }
  }
  return '';
}
function airaComicCmsPayloadMatchesHost(payload, base){
  var expectedHost = payload ? String(payload.host || '').trim().toLowerCase() : '';
  if (!expectedHost){ return false; }
  var responseHost = '';
  var pageHost = '';
  try { responseHost = new URL(base).host.toLowerCase(); } catch (e){ responseHost = ''; }
  try { pageHost = String(location.host || '').toLowerCase(); } catch (e2){ pageHost = ''; }
  return expectedHost === responseHost || expectedHost === pageHost;
}
function airaComicEncodeUtf8Base64(value){
  try {
    var bytes = new TextEncoder().encode(String(value || ''));
    var binary = '';
    for (var index = 0; index < bytes.length; index++){
      binary += String.fromCharCode(bytes[index]);
    }
    return btoa(binary);
  } catch (e){ return ''; }
}
function airaComicCmsPayloadImages(payload, base){
  if (!payload || !Array.isArray(payload.chapter_images) ||
    !airaComicCmsPayloadMatchesHost(payload, base)){ return []; }
  var hosts = Array.isArray(payload.images_hosts) ? payload.images_hosts : [];
  var host = hosts.length > 0 ? String(hosts[0]).replace(/\\/$/, '') : '';
  var output = [];
  for (var imageIndex = 0; imageIndex < payload.chapter_images.length && imageIndex < 400; imageIndex++){
    var value = String(payload.chapter_images[imageIndex] || '');
    if (!value){ continue; }
    if (/^(?:https?:)?\\/\\//.test(value)){
      // XHR-mode payloads may already carry signed absolute URLs.
    } else if (payload.images_base64){
      var encoded = '';
      if (typeof CMS !== 'undefined' && CMS.base64 && CMS.base64.encode){
        try { encoded = CMS.base64.encode(value); } catch (e){ encoded = ''; }
      }
      if (!encoded){ encoded = airaComicEncodeUtf8Base64(value); }
      if (!host || !encoded){ continue; }
      value = host + '/' + encoded;
    } else if (host) {
      value = host + (value.charAt(0) === '/' ? value : '/' + value);
    }
    var resolved = airaComicAbs(value, base);
    if (resolved){ output.push(resolved); }
  }
  return output;
}
function airaComicCollectCmsImages(doc, base){
  var encrypted = airaComicReadCmsEncryptedPayload(doc);
  if (!encrypted || typeof CMS === 'undefined' || !CMS.chapter || !CMS.chapter.decrypt){ return []; }
  try { return airaComicCmsPayloadImages(CMS.chapter.decrypt(encrypted), base); }
  catch (e){ return []; }
}
async function airaComicDecryptCmsPayload(encrypted, base){
  var cryptoApi = typeof window !== 'undefined' ? window.crypto : null;
  if (!encrypted || !cryptoApi || !cryptoApi.subtle || typeof atob !== 'function' ||
    typeof TextEncoder === 'undefined' || typeof TextDecoder === 'undefined'){ return null; }
  try {
    var binary = atob(encrypted);
    var bytes = new Uint8Array(binary.length);
    for (var index = 0; index < binary.length; index++){
      bytes[index] = binary.charCodeAt(index);
    }
    if (bytes.length <= 16 || (bytes.length - 16) % 16 !== 0){ return null; }
    // The public CMS format stores a 16-byte IV directly before the AES-CBC ciphertext.
    var key = await cryptoApi.subtle.importKey(
      'raw',
      new TextEncoder().encode('5V&RoR%Jf@pJPydF'),
      { name: 'AES-CBC' },
      false,
      ['decrypt']
    );
    var decrypted = await cryptoApi.subtle.decrypt(
      { name: 'AES-CBC', iv: bytes.slice(0, 16) },
      key,
      bytes.slice(16)
    );
    var payload = JSON.parse(new TextDecoder('utf-8').decode(decrypted));
    return airaComicCmsPayloadMatchesHost(payload, base) ? payload : null;
  } catch (e){ return null; }
}
async function airaComicCollectCmsImagesAsync(doc, base){
  var current = airaComicCollectCmsImages(doc, base);
  if (current.length >= 2){ return current; }
  var payload = await airaComicDecryptCmsPayload(airaComicReadCmsEncryptedPayload(doc), base);
  return airaComicCmsPayloadImages(payload, base);
}
function airaComicImageRaw(element, attributes){
  for (var index = 0; index < attributes.length; index++){
    var raw = element.getAttribute(attributes[index]) || '';
    if (raw){ return raw; }
  }
  return '';
}
function airaComicElementHint(element){
  if (!element || !element.getAttribute){ return ''; }
  return String((element.id || '') + ' ' + (element.className || '') + ' ' +
    (element.getAttribute('role') || '') + ' ' + (element.getAttribute('aria-label') || '')).toLowerCase();
}
function airaComicRejectedImageRegion(element){
  var node = element;
  for (var depth = 0; node && depth < 7; depth++){
    var hint = airaComicElementHint(node);
    if (/(^|[ _-])(recommend|related|ranking|rank-list|catalog|chapter-list|book-list|cover-list|comment|footer|header|navbar|toolbar|advert|ads?)([ _-]|$)/.test(hint)){
      return true;
    }
    node = node.parentElement;
  }
  return false;
}
function airaComicFindImageGroup(groups, node){
  for (var index = 0; index < groups.length; index++){
    if (groups[index].node === node){ return groups[index]; }
  }
  return null;
}
function airaComicCollectRenderedImageGroup(doc, attributes){
  var candidates = doc.querySelectorAll('img');
  var groups = [];
  for (var index = 0; index < candidates.length && index < 1600; index++){
    var image = candidates[index];
    var raw = airaComicImageRaw(image, attributes);
    if (!raw || airaComicIsJunkImage(raw) || airaComicRejectedImageRegion(image)){ continue; }
    var linked = false;
    var linkNode = image.parentElement;
    for (var linkDepth = 0; linkNode && linkDepth < 4; linkDepth++){
      if (String(linkNode.tagName || '').toLowerCase() === 'a'){ linked = true; break; }
      linkNode = linkNode.parentElement;
    }
    var node = image.parentElement;
    for (var depth = 0; node && depth < 7 && node !== doc.body && node !== doc.documentElement; depth++){
      var group = airaComicFindImageGroup(groups, node);
      if (!group){
        group = { node: node, images: [], urls: {}, linked: 0, depth: depth };
        groups.push(group);
      }
      if (!group.urls[raw]){
        group.urls[raw] = true;
        group.images.push(image);
        if (linked){ group.linked++; }
      }
      if (depth < group.depth){ group.depth = depth; }
      node = node.parentElement;
    }
  }
  var best = null;
  var bestScore = -1000000;
  for (var groupIndex = 0; groupIndex < groups.length; groupIndex++){
    var candidate = groups[groupIndex];
    if (candidate.images.length < 2){ continue; }
    var hint = airaComicElementHint(candidate.node);
    var semantic = /(chapter|chap|reader|read|comic|manga|content|image|picture|gallery|scroll|viewer|viewport|pages?)/.test(hint);
    var score = candidate.images.length * 40 + (semantic ? 600 : 0) + (7 - candidate.depth) * 20 -
      candidate.linked * 35;
    if (candidate.linked * 2 >= candidate.images.length){ score -= 300; }
    if (score > bestScore){ best = candidate; bestScore = score; }
  }
  return best ? best.images : [];
}
function airaComicSelectChapterImages(doc, selector, sourceKind, attributes){
  if (sourceKind === 'rendered_live_page_images'){
    var grouped = airaComicCollectRenderedImageGroup(doc, attributes);
    if (grouped.length >= 2){ return grouped; }
    var candidates = selector.split(',');
    for (var index = 0; index < candidates.length; index++){
      var candidate = candidates[index].trim();
      if (!candidate){ continue; }
      try {
        var matched = doc.querySelectorAll(candidate);
        if (matched.length >= 2){ return matched; }
      } catch (e){ }
    }
  }
  try { return doc.querySelectorAll(selector); } catch (e){ return []; }
}
function airaComicCollectChapterImages(doc, base, source){
  var output = [];
  var seen = {};
  var selector = source && source.imageSelector ? source.imageSelector : 'img';
  var sourceKind = source && source.kind ? source.kind : '';
  var attributes = source && Array.isArray(source.imageAttributes) ? source.imageAttributes :
    ['data-src', 'data-original', 'data-echo', 'data-url', 'src'];
  var images = airaComicSelectChapterImages(doc, selector, sourceKind, attributes);
  for (var index = 0; index < images.length; index++){
    var element = images[index];
    var className = String(element.className || '');
    if (className.indexOf('ad-') >= 0 || className.indexOf('ads') >= 0){ continue; }
    var raw = airaComicImageRaw(element, attributes);
    if (raw){ airaComicPushImage(output, seen, raw, base); }
    if (output.length >= 400){ break; }
  }
  if (!sourceKind || sourceKind === 'count_base_reconstruction'){
    var reconstructed = airaComicCollectCountBaseImages(doc, base);
    for (var reconstructedIndex = 0; reconstructedIndex < reconstructed.length; reconstructedIndex++){
      airaComicPushImage(output, seen, reconstructed[reconstructedIndex], base);
    }
  } else if (sourceKind === 'packer_inline_array'){
    var packed = airaComicCollectPackerImages(doc);
    for (var packedIndex = 0; packedIndex < packed.length; packedIndex++){
      airaComicPushImage(output, seen, packed[packedIndex], base);
    }
  } else if (sourceKind === 'cms_encrypted_params'){
    var cmsImages = airaComicCollectCmsImages(doc, base);
    for (var cmsIndex = 0; cmsIndex < cmsImages.length; cmsIndex++){
      airaComicPushImage(output, seen, cmsImages[cmsIndex], base);
    }
  }
  return output;
}
async function airaComicCollectChapterImagesForAcquisition(doc, base, source){
  var output = airaComicCollectChapterImages(doc, base, source);
  if (!source || source.kind !== 'cms_encrypted_params' || output.length >= 2){ return output; }
  var seen = {};
  for (var outputIndex = 0; outputIndex < output.length; outputIndex++){
    seen[output[outputIndex]] = true;
  }
  var cmsImages = await airaComicCollectCmsImagesAsync(doc, base);
  for (var cmsIndex = 0; cmsIndex < cmsImages.length; cmsIndex++){
    airaComicPushImage(output, seen, cmsImages[cmsIndex], base);
  }
  return output;
}
function airaComicPathMatches(base, pattern){
  if (!pattern){ return false; }
  try { return new RegExp(pattern).test(new URL(base).pathname); } catch (e){ return false; }
}
function airaComicChapterShell(pageUrl, title, images){
  return { pageUrl: pageUrl, title: title || '', paragraphs: [], images: images || [],
    prevUrl: '', nextUrl: '', catalogUrl: '', bookTitle: '', pageTotal: 1, nextPageUrl: '' };
}
function airaComicFetchDocument(url){
  return fetch(url, { credentials: 'include' }).then(function(response){
    return response.text().then(function(html){
      return { url: response.url || url, doc: new DOMParser().parseFromString(html, 'text/html') };
    });
  });
}
function airaComicReadTitle(doc){
  var element = doc.querySelector('h1, .chapter-title, .reader-title, #title, title');
  return element ? String(element.textContent || '').replace(/\\s+/g, ' ').trim() : '';
}
function airaComicAcquireZaiman(target){
  var targetUrl;
  try { targetUrl = new URL(target); } catch (e){ return Promise.resolve(null); }
  var path = targetUrl.pathname.split('/');
  var comicId = '';
  var chapterId = '';
  var endpoint = '';
  if (targetUrl.pathname === '/pages/comic/page'){
    comicId = targetUrl.searchParams.get('comic_id') || '';
    chapterId = targetUrl.searchParams.get('chapter_id') || '';
    if (!/^\\d+$/.test(comicId) || !/^\\d+$/.test(chapterId)){ return Promise.resolve(null); }
    endpoint = new URL('/api/app/v1/comic/chapter/' + encodeURIComponent(comicId) + '/' +
      encodeURIComponent(chapterId), targetUrl).href;
  } else {
    if (path.length < 5){ return Promise.resolve(null); }
    comicId = path[3];
    chapterId = path[4];
    if (!/^\\d+$/.test(comicId) || !/^\\d+$/.test(chapterId)){ return Promise.resolve(null); }
    var query = 'channel=pc&app_name=zmh&version=1.0.0&timestamp=' + Date.now() + '&uid=113119197' +
      '&comic_id=' + encodeURIComponent(comicId) + '&chapter_id=' + encodeURIComponent(chapterId);
    endpoint = new URL('/api/v1/comic1/chapter/detail?' + query, targetUrl).href;
  }
  return fetch(endpoint,
    { credentials: 'include', headers: { Platform: 'pc' } }).then(function(response){ return response.json(); }).then(function(body){
    var info = body && body.data ? (body.data.chapterInfo || body.data.data) : null;
    var pages = info && Array.isArray(info.page_url) ? info.page_url : [];
    var images = [];
    for (var index = 0; index < pages.length && index < 400; index++){
      if (typeof pages[index] === 'string'){ images.push(pages[index]); }
    }
    return images.length >= 2 ? airaComicChapterShell(target, info.title || '', images) : null;
  });
}
function airaComicAcquireMkzhan(target){
  var path = new URL(target).pathname.match(/^\\/(\\d+)\\/(\\d+)\\.html$/);
  if (!path){ return Promise.resolve(null); }
  var query = 'chapter_id=' + path[2] + '&comic_id=' + path[1] + '&quality=1&type=1&format=1';
  var endpoint = 'https://comic.mkzcdn.com/chapter/content/v1/?' + query;
  return fetch(endpoint, { credentials: 'omit' }).then(function(response){ return response.json(); }).then(function(body){
    var pages = body && body.data && Array.isArray(body.data.page) ? body.data.page : [];
    var images = [];
    for (var index = 0; index < pages.length && index < 400; index++){
      if (pages[index] && typeof pages[index].image === 'string'){ images.push(pages[index].image); }
    }
    return images.length >= 2 ? airaComicChapterShell(target, '', images) : null;
  });
}
function airaComicAcquireRenderedPage(target, source, progress){
  return new Promise(function(resolve){
    var targetUrl;
    var currentUrl;
    try {
      targetUrl = new URL(target, location.href);
      currentUrl = new URL(location.href);
    } catch (e){ resolve(null); return; }
    if (targetUrl.origin !== currentUrl.origin ||
      (source.chapterPathPattern && !airaComicPathMatches(targetUrl.href, source.chapterPathPattern))){
      resolve(null);
      return;
    }
    var host = document.body || document.documentElement;
    if (!host){ resolve(null); return; }
    var frame = document.createElement('iframe');
    frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
    frame.setAttribute('aria-hidden', 'true');
    frame.style.position = 'fixed';
    frame.style.left = '-10000px';
    frame.style.top = '0';
    frame.style.width = '420px';
    frame.style.height = '840px';
    frame.style.opacity = '0';
    frame.style.pointerEvents = 'none';
    var settled = false;
    var deadline = Date.now() + 15000;
    function finish(result, stage){
      if (settled){ return; }
      settled = true;
      try { if (frame.parentNode){ frame.parentNode.removeChild(frame); } } catch (e){ }
      if (progress){
        progress.inspect = null;
        progress.stage = stage || (result ? 'content_ready' : 'empty');
      }
      resolve(result);
    }
    function inspect(){
      if (settled){ return; }
      try {
        var frameDoc = frame.contentDocument;
        var frameUrl = frame.contentWindow && frame.contentWindow.location
          ? frame.contentWindow.location.href : targetUrl.href;
        var resolvedFrameUrl = new URL(frameUrl, targetUrl.href);
        if (frameDoc && resolvedFrameUrl.origin === targetUrl.origin){
          var images = airaComicCollectChapterImages(frameDoc, resolvedFrameUrl.href, source);
          if (images.length >= 2){
            finish(airaComicChapterShell(resolvedFrameUrl.href, airaComicReadTitle(frameDoc), images), 'content_ready');
            return;
          }
          var passwordInput = frameDoc.querySelector('input[type="password"]');
          var bodyText = frameDoc.body ? String(frameDoc.body.textContent || '').substring(0, 50000) : '';
          if (passwordInput || /请先登录|登录后(?:阅读|观看)|請先登錄|登入後(?:閱讀|觀看)|sign\\s+in\\s+to\\s+(?:read|view)|log\\s+in\\s+to\\s+(?:read|view)/i.test(bodyText)){
            finish(null, 'authentication_required');
            return;
          }
        }
      } catch (e){ }
      if (Date.now() >= deadline){ finish(null, 'frame_timeout'); return; }
      setTimeout(inspect, 120);
    }
    if (progress){
      progress.inspect = inspect;
      progress.stage = 'frame_attached';
    }
    frame.src = targetUrl.href;
    host.appendChild(frame);
    setTimeout(inspect, 120);
  });
}
function airaComicAcquireChapter(target, source, progress){
  if (!source){ return Promise.resolve(null); }
  if (source.kind === 'zaiman_json_api'){ return airaComicAcquireZaiman(target); }
  if (source.kind === 'mkzhan_json_api'){ return airaComicAcquireMkzhan(target); }
  if (source.kind === 'rendered_live_page_images'){
    return airaComicAcquireRenderedPage(target, source, progress);
  }
  return airaComicFetchDocument(target).then(async function(result){
    var images = await airaComicCollectChapterImagesForAcquisition(result.doc, result.url, source);
    return images.length >= 2 ? airaComicChapterShell(result.url, airaComicReadTitle(result.doc), images) : null;
  });
}
function airaComicRecognizesChapter(rule, doc, base, hasChapterNavigation){
  if (!rule){ return hasChapterNavigation && airaComicCollectChapterImages(doc, base, null).length >= 3; }
  if (rule.kind !== 'comic'){ return false; }
  var source = rule.comicChapterSource;
  if (!source){ return hasChapterNavigation && airaComicCollectChapterImages(doc, base, null).length >= 3; }
  if (airaComicPathMatches(base, source.chapterPathPattern) &&
    (source.kind === 'zaiman_json_api' || source.kind === 'mkzhan_json_api' ||
      source.kind === 'rendered_live_page_images')){ return true; }
  return airaComicCollectChapterImages(doc, base, source).length >= 3 && (hasChapterNavigation || source.imageSelector.length > 0);
}
`;

interface ComicFetchEnvelope {
  status?: string;
  stage?: string;
  message?: string;
  data?: NovelChapterExtract;
}

/**
 * Owns comic recognition and acquisition strategies while the Reading Session
 * remains owned by NovelReaderController.
 */
export class ComicChapterAcquisitionEngine {
  private requestSequence: number = 0;

  buildRuntimeHelpers(): string {
    return COMIC_RUNTIME_HELPERS;
  }

  async acquire(
    controller: webview.WebviewController,
    chapterUrl: string,
    rule: ComicChapterSourceRule
  ): Promise<NovelChapterExtract | undefined> {
    const startedAt: number = Date.now();
    this.requestSequence += 1;
    const requestId: number = this.requestSequence;
    const globalName: string = `__airaComicFetch_${requestId}`;
    const sourceJson: string = JSON.stringify(rule);
    const script: string = this.buildRuntimeHelpers() + `
(function(){
  var state = { status: 'pending', stage: 'starting', inspect: null };
  window.${globalName} = state;
  airaComicAcquireChapter(${JSON.stringify(chapterUrl)}, ${sourceJson}, state).then(function(data){
    if (window.${globalName} === state){
      window.${globalName} = data
        ? { status: 'done', stage: state.stage || 'content_ready', data: data }
        : { status: 'empty', stage: state.stage || 'empty' };
    }
  }).catch(function(error){
    if (window.${globalName} === state){
      window.${globalName} = { status: 'error', stage: state.stage || 'error', message: String(error) };
    }
  });
  return 'ok';
})();`;
    hilog.info(COMIC_LOG_DOMAIN, COMIC_LOG_TAG,
      'acquire started kind=%{public}s request=%{public}d', rule.kind, requestId);
    const triggerResult: string = await this.runJavaScriptWithTimeout(controller, script);
    if (triggerResult === COMIC_SCRIPT_TIMEOUT_RESULT) {
      hilog.error(COMIC_LOG_DOMAIN, COMIC_LOG_TAG,
        'acquire trigger timeout kind=%{public}s request=%{public}d', rule.kind, requestId);
      return undefined;
    }
    let lastStage: string = '';
    try {
      for (let attempt: number = 0;
        attempt < COMIC_POLL_MAX_TIMES && Date.now() - startedAt < COMIC_ACQUISITION_TIMEOUT_MS;
        attempt += 1) {
        const raw: string = await this.runJavaScriptWithTimeout(
          controller,
          `(function(){
            var value=window.${globalName};
            if (value && value.status === 'pending' && typeof value.inspect === 'function'){
              try { value.inspect(); } catch (e){ value.stage = 'inspect_error'; }
            }
            if (!value){ return ''; }
            return JSON.stringify({ status: value.status || '', stage: value.stage || '',
              message: value.message || '', data: value.data });
          })();`
        );
        if (raw === COMIC_SCRIPT_TIMEOUT_RESULT) {
          hilog.error(COMIC_LOG_DOMAIN, COMIC_LOG_TAG,
            'acquire poll timeout kind=%{public}s request=%{public}d attempt=%{public}d',
            rule.kind, requestId, attempt);
          return undefined;
        }
        const normalized: string = this.normalizeRawScriptResult(raw);
        if (normalized.length > 0) {
          const envelope: ComicFetchEnvelope = JSON.parse(normalized) as ComicFetchEnvelope;
          const stage: string = envelope.stage ?? '';
          if (stage.length > 0 && stage !== lastStage) {
            lastStage = stage;
            hilog.info(COMIC_LOG_DOMAIN, COMIC_LOG_TAG,
              'acquire stage=%{public}s kind=%{public}s request=%{public}d',
              stage, rule.kind, requestId);
          }
          if (envelope.status === 'done' && envelope.data !== undefined) {
            hilog.info(COMIC_LOG_DOMAIN, COMIC_LOG_TAG,
              'acquire ready kind=%{public}s request=%{public}d images=%{public}d elapsedMs=%{public}d',
              rule.kind, requestId, envelope.data.images.length, Date.now() - startedAt);
            return envelope.data;
          }
          if (envelope.status === 'empty' || envelope.status === 'error') {
            hilog.warn(COMIC_LOG_DOMAIN, COMIC_LOG_TAG,
              'acquire empty kind=%{public}s request=%{public}d stage=%{public}s elapsedMs=%{public}d',
              rule.kind, requestId, stage, Date.now() - startedAt);
            if (stage === 'authentication_required') {
              throw new Error(COMIC_CHAPTER_AUTHENTICATION_REQUIRED_ERROR);
            }
            return undefined;
          }
        }
        await this.delay(COMIC_POLL_INTERVAL_MS);
      }
      hilog.error(COMIC_LOG_DOMAIN, COMIC_LOG_TAG,
        'acquire deadline kind=%{public}s request=%{public}d stage=%{public}s elapsedMs=%{public}d',
        rule.kind, requestId, lastStage, Date.now() - startedAt);
      return undefined;
    } finally {
      void this.runJavaScriptWithTimeout(
        controller,
        `(function(){try{
          var value=window.${globalName};
          if (value && value.inspect){ value.inspect = null; }
          delete window.${globalName};
        }catch(e){} return '';})();`
      ).catch((_error: Error): void => {});
    }
  }

  async acquireRenderedPage(
    controller: webview.WebviewController,
    chapterUrl: string
  ): Promise<NovelChapterExtract | undefined> {
    return this.acquire(controller, chapterUrl, GENERIC_RENDERED_COMIC_SOURCE);
  }

  resolveContentKind(imageUrls: string[]): ComicChapterContentKind {
    return imageUrls.length >= COMIC_ARTIFACT_MIN_IMAGE_COUNT ? 'comic' : 'novel';
  }

  isComicArtifact(imageUrls: string[]): boolean {
    return this.resolveContentKind(imageUrls) === 'comic';
  }

  private normalizeRawScriptResult(rawResult: string): string {
    const trimmed: string = rawResult.trim();
    if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        const decoded: string = JSON.parse(trimmed) as string;
        return typeof decoded === 'string' ? decoded : trimmed;
      } catch (_error) {
        return trimmed;
      }
    }
    return trimmed;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), ms);
    });
  }

  private async runJavaScriptWithTimeout(
    controller: webview.WebviewController,
    script: string
  ): Promise<string> {
    let timer: number = 0;
    const timeoutPromise: Promise<string> = new Promise<string>((resolve: (value: string) => void) => {
      timer = setTimeout((): void => resolve(COMIC_SCRIPT_TIMEOUT_RESULT), COMIC_RUN_JAVASCRIPT_TIMEOUT_MS);
    });
    const result: string = await Promise.race([controller.runJavaScript(script), timeoutPromise]);
    if (timer !== 0) {
      clearTimeout(timer);
    }
    return result;
  }
}

export const sharedComicChapterAcquisitionEngine: ComicChapterAcquisitionEngine =
  new ComicChapterAcquisitionEngine();
