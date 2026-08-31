import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  NovelBookOverview,
  NovelCatalogEntry,
  NovelCatalogPageCursor,
  NovelCatalogPageResult,
  NovelCatalogResult,
  NovelChapterExtract,
  NovelContentKind
} from '../../features/novel/NovelReaderModels';
import {
  NovelSiteRule
} from '../../features/novel/NovelSiteRules';
import {
  ComicChapterAcquisitionEngine,
  sharedComicChapterAcquisitionEngine
} from './ComicChapterAcquisitionEngine';
import { ComicBookOverviewAcquisitionEngine } from './ComicBookOverviewAcquisitionEngine';
import { NovelChapterAcquisitionEngine } from './NovelChapterAcquisitionEngine';
import { NovelCatalogPageAcquisitionEngine } from './NovelCatalogPageAcquisitionEngine';
import { NovelRuleCatalog, sharedNovelRuleCatalog } from './NovelRuleCatalog';

/**
 * 小说章节抽取服务(通用算法版)。
 *
 * 真实站点勘察(biqugie.com)暴露的六个坑,本文件逐一处理:
 * 1. 目录页同时存在"最新章节预览"(倒序,少量)和"正文目录"两个同构容器
 *    → 用「容器聚类 + 打分」选出链接最多、最像章节列表的那个容器,预览块自然被排除。
 * 2. 站点只给部分章节(前20 + 后20,中间缺口),或把完整目录拆成多页
 *    → 不猜测缺失 URL;目录抓取沿严格同路由的「下一页」只合并页面真实提供的条目。
 * 3. #content 可能是整页外壳而非正文
 *    → 按最终可读文本量和壳层残留 UI 密度打分,密集后代保留大部分正文时优先更深的容器。
 * 4. 单章被拆成多页(第1/3页,下一页 528_2.html)
 *    → 抓章节时沿"下一页"把同章各页合并成完整一章。
 * 5. 章节页链接与目录都可能提供相邻章节
 *    → 章节页真实链接优先,NovelReaderController 仅用目录索引补齐缺失值。
 * 6. 目录标题用私有区(PUA)字体混淆
 *    → 清洗掉 U+E000–U+F8FF,避免渲染成豆腐块。
 *
 * 通信约定:runJavaScript 不会 await Promise,所以 fetch 结果先挂 window 全局,ArkTS 侧轮询取回。
 */

interface NovelRawChapter {
  pageUrl?: string;
  title?: string;
  paragraphs?: string[];
  images?: string[];
  prevUrl?: string;
  nextUrl?: string;
  catalogUrl?: string;
  bookTitle?: string;
  pageTotal?: number;
  nextPageUrl?: string;
}

interface NovelRawFetchEnvelope {
  status?: string;
  message?: string;
  data?: NovelRawChapter;
}

interface NovelRawCatalogEntry {
  ordinal?: number;
  title?: string;
  url?: string;
}

interface NovelRawCatalogEnvelope {
  status?: string;
  bookTitle?: string;
  author?: string;
  coverUrl?: string;
  complete?: boolean;
  entries?: NovelRawCatalogEntry[];
}

interface NovelRawBookOverview {
  contentKind?: string;
  title?: string;
  author?: string;
  category?: string;
  latest?: string;
  cover?: string;
  synopsis?: string;
  host?: string;
  catalogUrl?: string;
  startChapterUrl?: string;
  catalogSourceComplete?: boolean;
  catalogTotal?: number;
  initialEntries?: NovelRawCatalogEntry[];
}

const NOVEL_FETCH_GLOBAL: string = '__airaNovelFetch';
const NOVEL_CATALOG_GLOBAL: string = '__airaNovelCatalog';
const NOVEL_POLL_INTERVAL_MS: number = 200;
const NOVEL_POLL_MAX_TIMES: number = 90;
const NOVEL_CATALOG_POLL_MAX_TIMES: number = 525;
const NOVEL_DETECTION_GLOBAL: string = '__airaNovelDetection';
const NOVEL_REQUEST_MISSING: string = '__aira_novel_request_missing__';
/** 目录分块传回:runJavaScript 返回值有大小上限,长书一次性传会被截断(现成阅读模式同样按块传)。 */
const NOVEL_CATALOG_CHUNK: number = 40;
const NOVEL_BOOK_INITIAL_CATALOG_ENTRIES: number = 40;
const NOVEL_LOG_DOMAIN = 0x0000;
const NOVEL_LOG_TAG = 'AiraNovel';

/** 注入网页执行的 JS 辅助库(纯 DOM,尽量少用正则,避免转义问题)。 */
const NOVEL_JS_HELPERS: string = `
function airaNovelClean(t){
  if (!t){ return ''; }
  var out = '';
  for (var i = 0; i < t.length; i++){
    var c = t.charCodeAt(i);
    if (c >= 0xE000 && c <= 0xF8FF){ continue; }   // 私有区字体混淆字符,直接丢弃
    out += t.charAt(i);
  }
  return out.replace(/\\s+/g, ' ').trim();
}
function airaNovelNavigationText(t){
  return airaNovelClean(t).replace(/[—–－_·•-]/g, '');
}
function airaNovelRule(){ try { return (typeof __airaRule !== 'undefined' && __airaRule) ? __airaRule : null; } catch (e){ return null; } }
function airaNovelQOne(doc, sel){ try { return sel ? doc.querySelector(sel) : null; } catch (e){ return null; } }
function airaNovelQAll(doc, sel){ try { return sel ? doc.querySelectorAll(sel) : []; } catch (e){ return []; } }
function airaNovelAbs(href, base){ try { return new URL(href, base).href; } catch (e){ return ''; } }
function airaNovelScopedHttpUrlAllowed(rule, url, base){
  if (!rule || !url){ return false; }
  try {
    var target = new URL(url, base);
    var source = new URL(base);
    if ((target.protocol !== 'http:' && target.protocol !== 'https:') || target.origin !== source.origin){ return false; }
    var prefixes = Array.isArray(rule.pathPrefixes) ? rule.pathPrefixes : [];
    if (prefixes.length === 0){ return true; }
    for (var i = 0; i < prefixes.length; i++){
      if (target.pathname.indexOf(prefixes[i]) === 0){ return true; }
    }
    return false;
  } catch (e){ return false; }
}
function airaNovelRuleUrlAllowed(rule, url, base){
  if (!rule || !rule.requiresContentQualityGate){ return true; }
  return airaNovelScopedHttpUrlAllowed(rule, url, base);
}
/** 识别证据比抽取更严格:规则链接必须是当前页同源 HTTP(S),并留在声明的路径范围。 */
function airaNovelRecognitionUrlAllowed(rule, url, base){
  return airaNovelScopedHttpUrlAllowed(rule, url, base);
}
function airaNovelRecognitionNeighborUrl(rule, url, base){
  if (!airaNovelRecognitionUrlAllowed(rule, url, base)){ return ''; }
  try {
    var target = new URL(url, base);
    var source = new URL(base);
    target.hash = '';
    source.hash = '';
    return target.href !== source.href ? target.href : '';
  } catch (e){ return ''; }
}
function airaNovelDirOf(u){ var i = u.lastIndexOf('/'); return i >= 0 ? u.substring(0, i + 1) : u; }
function airaNovelExtOf(u){ var i = u.lastIndexOf('.'); return i >= 0 ? u.substring(i) : '.html'; }
function airaNovelUrlNum(u){
  var q = u.indexOf('?'); if (q >= 0){ u = u.substring(0, q); }
  var h = u.indexOf('#'); if (h >= 0){ u = u.substring(0, h); }
  var seg = u.substring(u.lastIndexOf('/') + 1);
  var dot = seg.indexOf('.'); if (dot >= 0){ seg = seg.substring(0, dot); }
  // 下划线后缀可能是章节身份的一部分;通用路径不把它折叠成另一章。
  if (seg.indexOf('_') >= 0){ return -1; }
  if (seg.length === 0){ return -1; }
  for (var i = 0; i < seg.length; i++){
    var c = seg.charCodeAt(i);
    if (c < 48 || c > 57){ return -1; }
  }
  return parseInt(seg, 10);
}
function airaNovelLooksChapter(t){
  if (!t){ return 0; }
  if (t.indexOf('章') >= 0 || t.indexOf('节') >= 0 || t.indexOf('節') >= 0 ||
    t.indexOf('话') >= 0 || t.indexOf('話') >= 0 || t.indexOf('回') >= 0) { return 1; }
  if (t.indexOf('楔子') >= 0 || t.indexOf('序章') >= 0 || t.indexOf('番外') >= 0 || t.indexOf('开篇') >= 0){ return 1; }
  return 0;
}
function airaNovelLooksVideoEpisodePage(doc){
  if (!airaNovelQOne(doc, 'video,iframe,object[type*="video"],embed[type*="video"]')){ return false; }
  var links = doc.querySelectorAll('a[href]');
  var limit = Math.min(links.length, 1600);
  var hasEpisodeNavigation = false;
  var numericEpisodeLinks = 0;
  for (var i = 0; i < limit; i++){
    var text = airaNovelNavigationText(links[i].textContent);
    if (text.indexOf('上一集') >= 0 || text.indexOf('下一集') >= 0){
      hasEpisodeNavigation = true;
    }
    if (/^\\d+(?:\\s*[上下])?$/.test(text)){ numericEpisodeLinks++; }
  }
  return hasEpisodeNavigation && numericEpisodeLinks >= 3;
}
function airaNovelFooterBoundary(t){
  if (!t){ return false; }
  var lower = t.toLowerCase();
  return lower.indexOf('copyright') >= 0 || lower.indexOf('all rights reserved') >= 0
    || t.indexOf('版权所有') >= 0
    || (t.indexOf('本站') >= 0 && (t.indexOf('搜索引擎') >= 0 || t.indexOf('信息检索服务') >= 0));
}
function airaNovelBadLine(t){
  if (t.length === 0){ return true; }
  return airaNovelFooterBoundary(t)
    || t.indexOf('笔趣') >= 0 || t.indexOf('請記住') >= 0 || t.indexOf('请记住') >= 0
    || t.indexOf('http') >= 0 || t.indexOf('www.') >= 0 || t.indexOf('最新章节') >= 0
    || t.indexOf('章节目录') >= 0 || t.indexOf('天才一秒') >= 0 || t.indexOf('手机阅读') >= 0
    || t.indexOf('.com') >= 0 || t.indexOf('.net') >= 0 || t.indexOf('加入书签') >= 0
    || t.indexOf('推荐本书') >= 0 || t.indexOf('温馨提示') >= 0;
}
function airaNovelNodeToText(el){
  var out = [];
  function walk(node){
    var kids = node.childNodes;
    for (var i = 0; i < kids.length; i++){
      var c = kids[i];
      if (c.nodeType === 3){ out.push(c.nodeValue || ''); }
      else if (c.nodeType === 1){
        var tag = (c.tagName || '').toLowerCase();
        if (tag === 'br'){ out.push('\\n'); }
        else if (tag === 'script' || tag === 'style' || tag === 'a' || tag === 'ins' || tag === 'button' || tag === 'h1' || tag === 'h2'){ }
        else if (tag === 'p' || tag === 'div'){ out.push('\\n'); walk(c); out.push('\\n'); }
        else { walk(c); }
      }
    }
  }
  walk(el);
  return out.join('');
}
function airaNovelSelectorCount(el, selector){
  try { return el.querySelectorAll(selector).length; } catch (e){ return 0; }
}
function airaNovelContentMetrics(el){
  var textLength = airaNovelClean(airaNovelNodeToText(el)).length;
  var linkCount = airaNovelSelectorCount(el, 'a[href]');
  var controlCount = airaNovelSelectorCount(el, 'button,input,select,textarea');
  var chromeCount = airaNovelSelectorCount(el,
    'nav,footer,aside,form,[role="navigation"],[class*="footer"],[id*="footer"],'
    + '[class*="recommend"],[id*="recommend"],[class*="related"],[id*="related"],'
    + '[class*="sidebar"],[id*="sidebar"]');
  var divisor = 1 + Math.min(3, linkCount * 0.1) + Math.min(2, controlCount * 0.12)
    + Math.min(2, chromeCount * 0.45);
  return {
    textLength: textLength,
    linkCount: linkCount,
    controlCount: controlCount,
    chromeCount: chromeCount,
    score: Math.floor(textLength / divisor)
  };
}
function airaNovelBoundedContentPassesQualityGate(el){
  if (!el){ return false; }
  var metrics = airaNovelContentMetrics(el);
  return metrics.textLength >= 160 && metrics.score >= 120 && metrics.chromeCount === 0
    && metrics.controlCount <= 1
    && (metrics.linkCount <= 2 || metrics.textLength >= metrics.linkCount * 400);
}
function airaNovelDescendantKeepsBody(ancestor, descendant){
  if (descendant.textLength < 400 || descendant.textLength < ancestor.textLength * 0.85){ return false; }
  var removesResidualUi = descendant.linkCount < ancestor.linkCount
    || descendant.controlCount < ancestor.controlCount || descendant.chromeCount < ancestor.chromeCount;
  return removesResidualUi || descendant.textLength >= ancestor.textLength * 0.95;
}
function airaNovelPushContentCandidate(candidates, el){
  if (el && candidates.indexOf(el) < 0){ candidates.push(el); }
}
/** 正文容器:候选 id/class + 全页兜底,以正文量为主并扣除壳层残留 UI。 */
function airaNovelPickContent(doc){
  var rule = airaNovelRule();
  if (rule && rule.contentSelector){
    var ruleEl = airaNovelQOne(doc, rule.contentSelector);
    if (ruleEl){
      var ruleMetrics = airaNovelContentMetrics(ruleEl);
      // 普通规则允许短章；带质量门的规则必须先证明它没有误选标题、导航或广告块。
      if (ruleMetrics.textLength > 0 &&
        (!rule.requiresContentQualityGate || airaNovelBoundedContentPassesQualityGate(ruleEl))){
        return ruleEl;
      }
    }
    if (rule.hasLocalChapterSource && !rule.requiresContentQualityGate){
      // 动态来源规则的精确正文尚未就绪时,禁止退回整页外壳。
      return null;
    }
  }
  var cands = [];
  var ids = ['chaptercontent','content','nr','nr1','text','TextContent','read-content','article','pt-pop','booktext','BookText','htmlContent','txt','chapterContent','articlecontent'];
  for (var i = 0; i < ids.length; i++){
    var e = doc.getElementById(ids[i]);
    airaNovelPushContentCandidate(cands, e);
  }
  var cls = ['content','read-content','chapter-content','article-content','showtxt','txtnav','neirong'];
  for (var j = 0; j < cls.length; j++){
    var l = doc.getElementsByClassName(cls[j]);
    for (var m = 0; m < l.length && m < 3; m++){ airaNovelPushContentCandidate(cands, l[m]); }
  }
  var divs = doc.querySelectorAll('div,article,section');
  for (var d = 0; d < divs.length; d++){
    var tl = (divs[d].textContent || '').length;
    if (tl > 300){ airaNovelPushContentCandidate(cands, divs[d]); }
  }
  var pick = null; var pickMetrics = null;
  for (var c = 0; c < cands.length; c++){
    var el = cands[c];
    var metrics = airaNovelContentMetrics(el);
    if (metrics.textLength < 200){ continue; }
    var prefer = !pickMetrics || metrics.score > pickMetrics.score;
    if (pick && pick !== el && pickMetrics){
      if (pick.contains(el) && airaNovelDescendantKeepsBody(pickMetrics, metrics)){ prefer = true; }
      else if (el.contains(pick) && airaNovelDescendantKeepsBody(metrics, pickMetrics)){ prefer = false; }
    }
    if (prefer){ pickMetrics = metrics; pick = el; }
  }
  return pick;
}
function airaNovelChineseDigit(ch){
  if (ch === '零' || ch === '〇'){ return 0; }
  if (ch === '一'){ return 1; }
  if (ch === '二' || ch === '两'){ return 2; }
  if (ch === '三'){ return 3; }
  if (ch === '四'){ return 4; }
  if (ch === '五'){ return 5; }
  if (ch === '六'){ return 6; }
  if (ch === '七'){ return 7; }
  if (ch === '八'){ return 8; }
  if (ch === '九'){ return 9; }
  return -1;
}
function airaNovelChineseUnit(ch){
  if (ch === '十'){ return 10; }
  if (ch === '百'){ return 100; }
  if (ch === '千'){ return 1000; }
  if (ch === '万'){ return 10000; }
  return -1;
}
function airaNovelOrdinalToken(value){
  if (!value){ return -1; }
  var decimal = true;
  for (var i = 0; i < value.length; i++){
    var code = value.charCodeAt(i);
    if (code < 48 || code > 57){ decimal = false; break; }
  }
  if (decimal){ return parseInt(value, 10); }
  var total = 0; var section = 0; var digit = -1; var recognized = false;
  for (var j = 0; j < value.length; j++){
    var chineseDigit = airaNovelChineseDigit(value.charAt(j));
    if (chineseDigit >= 0){ digit = chineseDigit; recognized = true; continue; }
    var unit = airaNovelChineseUnit(value.charAt(j));
    if (unit < 0){ return -1; }
    recognized = true;
    if (unit === 10000){
      section += digit >= 0 ? digit : 0;
      total += Math.max(1, section) * unit;
      section = 0;
    } else {
      section += (digit >= 0 ? digit : 1) * unit;
    }
    digit = -1;
  }
  return recognized ? total + section + (digit >= 0 ? digit : 0) : -1;
}
/** 从标题里取章节序号:支持章节单位、序号标点和纯数字标题;取不到返回 -1。 */
function airaNovelTitleOrdinal(t){
  if (!t){ return -1; }
  var m = t.match(/第\\s*([0-9零〇一二两三四五六七八九十百千万]+)\\s*[章话話回節节]/);
  if (m){ return airaNovelOrdinalToken(m[1]); }
  m = t.match(/^\\s*([0-9零〇一二两三四五六七八九十百千万]+)\\s*[章话話回節节]/);
  if (m){ return airaNovelOrdinalToken(m[1]); }
  m = t.match(/^\\s*([0-9零〇一二两三四五六七八九十百千万]{1,12})\\s*[、，,。．.]\\s*\\S/);
  if (m){ return airaNovelOrdinalToken(m[1]); }
  m = t.match(/^\\s*(\\d+)\\s*$/);
  if (m){ return parseInt(m[1], 10); }
  return -1;
}
/** 规则选择器优先,失败回退到文字匹配;过滤 0.html 这类到头哨兵。 */
function airaNovelRuleLink(doc, base, rule, sel, keywords){
  if (sel){
    var el = airaNovelQOne(doc, sel);
    if (el){
      var h = el.getAttribute('href');
      if (h && h.indexOf('javascript:') !== 0 && h !== '#'){
        var u = airaNovelAbs(h, base);
        if (u && u.indexOf('/0.html') < 0 && airaNovelRuleUrlAllowed(rule, u, base)){ return u; }
      }
    }
  }
  var fallback = airaNovelFindLink(doc, base, keywords);
  return airaNovelRuleUrlAllowed(rule, fallback, base) ? fallback : '';
}
function airaNovelFindLink(doc, base, keywords){
  var links = doc.querySelectorAll('a[href]');
  for (var i = 0; i < links.length; i++){
    var txt = airaNovelNavigationText(links[i].textContent);
    for (var k = 0; k < keywords.length; k++){
      if (txt.indexOf(airaNovelNavigationText(keywords[k])) >= 0){
        var href = links[i].getAttribute('href');
        if (href && href.indexOf('javascript:') !== 0){
          var u = airaNovelAbs(href, base);
          if (u){ return u; }
        }
      }
    }
  }
  return '';
}
function airaNovelCatalogRouteScore(url){
  var parsed = null;
  try { parsed = new URL(url); } catch (e){ return 0; }
  var path = (parsed.pathname || '').toLowerCase();
  if (path.indexOf('chapter-list') >= 0 || path.indexOf('chapter_list') >= 0 ||
    path.indexOf('chapterlist') >= 0 || path.indexOf('all-chapters') >= 0 ||
    path.indexOf('all_chapters') >= 0){ return 20; }
  var parts = path.replace(/[-_]+/g, '/').split('/');
  for (var i = 0; i < parts.length; i++){
    var part = parts[i];
    if (part === 'catalog' || part === 'catalogue' || part === 'directory' ||
      part === 'dir' || part === 'chapters' || part === 'mulu'){
      return 15;
    }
  }
  var queryScore = 0;
  parsed.searchParams.forEach(function(value, key){
    if (queryScore > 0){ return; }
    var pair = (key + '/' + value).toLowerCase().replace(/[-_]+/g, '/').split('/');
    for (var q = 0; q < pair.length; q++){
      if (pair[q] === 'catalog' || pair[q] === 'catalogue' || pair[q] === 'directory' ||
        pair[q] === 'dir' || pair[q] === 'chapters' || pair[q] === 'mulu'){
        queryScore = 10;
        return;
      }
    }
  });
  return queryScore;
}
function airaNovelIsReadingActionText(text){
  var normalized = airaNovelNavigationText(text).toLowerCase().replace(/\\s+/g, '');
  return normalized.indexOf('开始阅读') >= 0 || normalized.indexOf('開始閱讀') >= 0 ||
    normalized.indexOf('开始观看') >= 0 || normalized.indexOf('開始觀看') >= 0 ||
    normalized.indexOf('立即阅读') >= 0 || normalized.indexOf('立即閱讀') >= 0 ||
    normalized.indexOf('立即观看') >= 0 || normalized.indexOf('立即觀看') >= 0 ||
    normalized.indexOf('在线阅读') >= 0 || normalized.indexOf('線上閱讀') >= 0 || normalized === 'startreading' ||
    normalized === 'readnow' || normalized === 'beginreading' || normalized === 'startviewing' ||
    normalized === 'watchnow';
}
function airaNovelFindReadingActionLink(doc, base){
  var current = null;
  try { current = new URL(base); } catch (e){ return ''; }
  current.hash = '';
  var links = doc.querySelectorAll('a[href]');
  for (var i = 0; i < links.length && i < 1600; i++){
    var rawText = links[i].getAttribute('aria-label') || links[i].getAttribute('title') ||
      links[i].textContent || '';
    if (!airaNovelIsReadingActionText(rawText)){ continue; }
    var href = links[i].getAttribute('href');
    if (!href || href.indexOf('javascript:') === 0 || href.charAt(0) === '#'){ continue; }
    var resolved = airaNovelAbs(href, base);
    var target = null;
    try { target = new URL(resolved); } catch (e2){ target = null; }
    if (!target || (target.protocol !== 'http:' && target.protocol !== 'https:') ||
      target.origin !== current.origin){ continue; }
    target.hash = '';
    if (target.href === current.href || !airaNovelRuleUrlAllowed(airaNovelRule(), target.href, base)){ continue; }
    return target.href;
  }
  return '';
}
/**
 * 显式完整目录入口:只接受同源、可 fetch、且跳到另一文档的 HTTP(S) 链接。
 * “查看更多”太宽泛,这里只认明确指向完整章节集合的文案。
 */
function airaNovelFindFullCatalogPage(doc, base){
  var current = null;
  try { current = new URL(base); } catch (e){ return ''; }
  current.hash = '';
  var links = doc.querySelectorAll('a[href]');
  var bestUrl = ''; var bestScore = -1;
  for (var i = 0; i < links.length; i++){
    var text = airaNovelClean(links[i].textContent);
    var href = (links[i].getAttribute('href') || '').trim();
    if (!href || href.charAt(0) === '#' || href.indexOf('javascript:') === 0){ continue; }
    var target = null;
    try { target = new URL(href, base); } catch (e2){ target = null; }
    if (!target || (target.protocol !== 'http:' && target.protocol !== 'https:')){ continue; }
    if (target.origin !== current.origin){ continue; }
    target.hash = '';
    if (target.href === current.href){ continue; }
    var routeScore = airaNovelCatalogRouteScore(target.href);
    var score = -1;
    if (text === '查看完整目录'){ score = 100; }
    else if (text.indexOf('完整目录') >= 0 || text.indexOf('完整章节目录') >= 0){ score = 90; }
    else if (text.indexOf('全部章节') >= 0 || text.indexOf('所有章节') >= 0){ score = 80; }
    else if (text.indexOf('展开全部章节') >= 0 || text.indexOf('展开目录') >= 0){ score = 75; }
    else if (text.indexOf('查看更多章节') >= 0){ score = 70; }
    else if (airaNovelIsReadingActionText(text) && routeScore > 0){ score = 65; }
    if (score < 0){ continue; }
    score += routeScore;
    if (score > bestScore){ bestScore = score; bestUrl = target.href; }
  }
  return bestUrl;
}
function airaNovelFindPreferredCatalogPage(doc, base){
  return airaNovelFindFullCatalogPage(doc, base) || airaNovelFindLink(doc, base,
    ['章节目录', '完整目录', '全部章节', '所有章节', '查看更多章节', '查看目录', '返回目录', '回目录', '目录']);
}
/** 站点 Profile 只能提供受约束的目录证据,不能直接声明当前页符合小说模式。 */
function airaNovelRuleCatalogEvidenceCount(doc, base, rule){
  if (!rule || rule.kind !== 'novel' || !rule.chapterLinkSelector){ return 0; }
  var nodes = airaNovelQAll(doc, rule.chapterLinkSelector);
  if (nodes.length < 3){ return 0; }
  var seen = {}; var count = 0;
  for (var i = 0; i < nodes.length && i < 1600; i++){
    var href = nodes[i].getAttribute('href') || nodes[i].getAttribute('data-href');
    var title = airaNovelClean(nodes[i].textContent);
    if (!href || !title || href.indexOf('javascript:') === 0){ continue; }
    var resolved = airaNovelAbs(href, base);
    if (!resolved || seen[resolved] || !airaNovelRecognitionUrlAllowed(rule, resolved, base)){ continue; }
    seen[resolved] = true;
    count++;
  }
  return count;
}
/** 目录抽取:容器聚类 + 打分选主目录;通用路径只保留页面实际提供的链接。 */
function airaNovelExtractCatalog(doc, base, allowRule){
  var rule0 = allowRule === false ? null : airaNovelRule();
  if (rule0 && rule0.chapterLinkSelector){
    var nodes = airaNovelQAll(doc, rule0.chapterLinkSelector);
    if (nodes.length >= 3){
      var ruleList = []; var ruleSeen = {};
      for (var ri = 0; ri < nodes.length; ri++){
        var ra = nodes[ri];
        var rh = ra.getAttribute('href') || ra.getAttribute('data-href');
        if (!rh || rh.indexOf('javascript:') === 0){ continue; }
        var ru = airaNovelAbs(rh, base);
        var rt = airaNovelClean(ra.textContent);
        if (!ru || !rt || ruleSeen[ru] || !airaNovelRuleUrlAllowed(rule0, ru, base)){ continue; }
        ruleSeen[ru] = true;
        ruleList.push({ title: rt, url: ru, num: airaNovelUrlNum(ru) });
      }
      if (ruleList.length >= 3){
        if (rule0.reverseCatalog){ ruleList.reverse(); }
        return ruleList;
      }
    }
  }
  if (!rule0 && airaNovelCatalogRouteScore(base) === 0 &&
    airaNovelFindFullCatalogPage(doc, base)){ return []; }
  var origin = '';
  try { origin = new URL(base).origin; } catch (e){ origin = ''; }
  var catalogRouteScore = airaNovelCatalogRouteScore(base);
  var catalogRootPath = airaNovelCatalogRootPath(base);
  var anchors = doc.querySelectorAll('a[href]');
  var groups = {};
  for (var i = 0; i < anchors.length; i++){
    var a = anchors[i];
    var href = a.getAttribute('href');
    if (!href || href.indexOf('javascript:') === 0 || href.charAt(0) === '#'){ continue; }
    var u = airaNovelAbs(href, base);
    if (!u){ continue; }
    var parsedCatalogUrl = null;
    try { parsedCatalogUrl = new URL(u); } catch (e2){ parsedCatalogUrl = null; }
    if (!parsedCatalogUrl || (parsedCatalogUrl.protocol !== 'http:' && parsedCatalogUrl.protocol !== 'https:') ||
      (origin && parsedCatalogUrl.origin !== origin)){ continue; }
    if (!airaNovelRuleUrlAllowed(rule0, u, base)){ continue; }
    var t = airaNovelClean(a.textContent);
    if (t.length === 0 || t.length > 60){ continue; }
    var p1 = a.parentElement ? a.parentElement : a;
    var p2 = p1.parentElement ? p1.parentElement : p1;
    var key = '';
    try { key = (p2.tagName || '') + '#' + (p2.id || '') + '.' + (p2.className || ''); } catch (e3){ key = 'x'; }
    key = key + '||' + airaNovelDirOf(u);
    if (!groups[key]){ groups[key] = { items: [], chap: 0, scoped: 0 }; }
    groups[key].items.push({ title: t, url: u, num: airaNovelUrlNum(u) });
    if (airaNovelLooksChapter(t) || airaNovelTitleOrdinal(t) > 0){ groups[key].chap++; }
    try {
      if (catalogRootPath && new URL(u).pathname.indexOf(catalogRootPath) === 0){ groups[key].scoped++; }
    } catch (e4){ }
  }
  var bestKey = ''; var bestScore = -1; var bestGroup = null;
  for (var k2 in groups){
    var g = groups[k2];
    var n = g.items.length;
    if (n < 3){ continue; }
    var numOk = 0;
    for (var q = 0; q < n; q++){ if (g.items[q].num >= 0){ numOk++; } }
    var structuralCatalog = catalogRouteScore > 0 && g.scoped / n >= 0.8 && numOk / n >= 0.6;
    if (g.chap < 2 && !structuralCatalog){ continue; }
    // 链接数为主 × 章节文字命中率 × URL数字化程度 → 预览块(条目少)自然落败
    var score = n * (0.4 + g.chap / n) * (0.5 + 0.5 * (numOk / n));
    if (structuralCatalog){ score += n; }
    if (score > bestScore){ bestScore = score; bestKey = k2; bestGroup = g; }
  }
  if (bestKey === ''){ return airaNovelExtractSparseComicCatalog(doc, base, anchors, rule0); }
  var raw = bestGroup.items;
  var seen = {}; var uniq = [];
  for (var r = 0; r < raw.length; r++){
    if (seen[raw[r].url]){ continue; }
    seen[raw[r].url] = true;
    uniq.push(raw[r]);
  }
  return uniq;
}
function airaNovelCatalogRootPath(url){
  try {
    var path = new URL(url).pathname || '/';
    if (path.charAt(path.length - 1) === '/'){ return path; }
    var slash = path.lastIndexOf('/');
    return slash >= 0 ? path.substring(0, slash + 1) : '/';
  } catch (e){ return ''; }
}
function airaNovelPositiveInteger(value){
  if (!value){ return -1; }
  for (var i = 0; i < value.length; i++){
    var code = value.charCodeAt(i);
    if (code < 48 || code > 57){ return -1; }
  }
  var number = parseInt(value, 10);
  return number > 0 ? number : -1;
}
function airaNovelIsNextCatalogQueryPage(current, next, rootPath){
  var sameDocumentPath = current.pathname === next.pathname;
  var rootDocumentPath = current.pathname === rootPath && next.pathname === rootPath;
  if (!sameDocumentPath && !rootDocumentPath){ return false; }
  var matched = false;
  next.searchParams.forEach(function(value, key){
    if (matched){ return; }
    var nextNumber = airaNovelPositiveInteger(value);
    if (nextNumber < 2){ return; }
    var currentValue = current.searchParams.get(key);
    var currentNumber = currentValue === null ? 1 : airaNovelPositiveInteger(currentValue);
    if (currentNumber > 0 && nextNumber === currentNumber + 1){ matched = true; }
  });
  return matched;
}
function airaNovelCatalogSiblingPageNumber(path, rootPath){
  var rootStem = rootPath;
  if (rootStem.charAt(rootStem.length - 1) === '/'){
    rootStem = rootStem.substring(0, rootStem.length - 1);
  }
  var prefix = rootStem + '_';
  if (path.indexOf(prefix) !== 0 || path.charAt(path.length - 1) !== '/'){ return -1; }
  return airaNovelPositiveInteger(path.substring(prefix.length, path.length - 1));
}
/**
 * 接受目录根路径下的数字分页(/read/527/2/)、同级编号分页(/read/527_2/)
 * 或同路径递增查询分页(?page=2)。
 * 这会排除章节正文的「下一页」(如 /0/527/527_2.html),避免跨章误抓。
 */
function airaNovelFindNextCatalogPage(doc, currentUrl, catalogRootUrl){
  var rootPath = airaNovelCatalogRootPath(catalogRootUrl);
  if (!rootPath){ return ''; }
  var current = null;
  try { current = new URL(currentUrl); } catch (e){ return ''; }
  var links = doc.querySelectorAll('a[href]');
  for (var i = 0; i < links.length; i++){
    var text = airaNovelNavigationText(links[i].textContent);
    if (text !== '下一页' && text !== '下页'){ continue; }
    var href = links[i].getAttribute('href');
    if (!href || href.indexOf('javascript:') === 0){ continue; }
    var next = null;
    try { next = new URL(href, currentUrl); } catch (e2){ next = null; }
    if (!next || next.origin !== current.origin || next.href === current.href){ continue; }
    if (airaNovelIsNextCatalogQueryPage(current, next, rootPath)){ return next.href; }
    var currentSiblingPage = current.pathname === rootPath
      ? 1 : airaNovelCatalogSiblingPageNumber(current.pathname, rootPath);
    var nextSiblingPage = airaNovelCatalogSiblingPageNumber(next.pathname, rootPath);
    if (currentSiblingPage > 0 && nextSiblingPage === currentSiblingPage + 1){ return next.href; }
    if (next.pathname.indexOf(rootPath) !== 0){ continue; }
    var suffix = next.pathname.substring(rootPath.length);
    if (suffix.charAt(suffix.length - 1) === '/'){
      suffix = suffix.substring(0, suffix.length - 1);
    }
    if (!suffix){ continue; }
    var numeric = true;
    for (var j = 0; j < suffix.length; j++){
      var code = suffix.charCodeAt(j);
      if (code < 48 || code > 57){ numeric = false; break; }
    }
    if (numeric){ return next.href; }
  }
  return '';
}
function airaNovelCatalogControlText(el){
  if (!el){ return ''; }
  var raw = el.getAttribute('aria-label') || el.getAttribute('title') ||
    el.getAttribute('value') || el.textContent || '';
  return airaNovelNavigationText(raw).toLowerCase().replace(/\\s+/g, '');
}
function airaNovelCatalogRevealScore(text){
  if (!text){ return 0; }
  if (text === '查看所有章节' || text === '查看所有章節' ||
    text === '查看全部章节' || text === '查看全部章節'){ return 150; }
  if (text.indexOf('全部章节') >= 0 || text.indexOf('全部章節') >= 0 ||
    text.indexOf('所有章节') >= 0 || text.indexOf('所有章節') >= 0){ return 140; }
  if (text.indexOf('完整目录') >= 0 || text.indexOf('完整目錄') >= 0 ||
    text.indexOf('完整章节目录') >= 0 || text.indexOf('完整章節目錄') >= 0){ return 130; }
  if (text.indexOf('章节列表') >= 0 || text.indexOf('章節列表') >= 0 ||
    text.indexOf('章节目录') >= 0 || text.indexOf('章節目錄') >= 0){ return 120; }
  if (text.indexOf('查看更多章节') >= 0 || text.indexOf('查看更多章節') >= 0 ||
    text.indexOf('展开目录') >= 0 || text.indexOf('展開目錄') >= 0){ return 110; }
  if (text === '目录' || text === '目錄' || text === 'catalog' || text === 'chapters'){ return 90; }
  return 0;
}
function airaNovelFindCatalogRevealControl(doc){
  var nodes = doc.querySelectorAll('a,button,input[type="button"],input[type="submit"],[role="button"]');
  var best = null; var bestScore = 0;
  for (var i = 0; i < nodes.length && i < 1600; i++){
    var score = airaNovelCatalogRevealScore(airaNovelCatalogControlText(nodes[i]));
    if (score <= bestScore || airaNovelCatalogControlDisabled(nodes[i]) ||
      !airaNovelCatalogControlVisible(doc, nodes[i])){ continue; }
    var target = airaNovelCatalogInteractiveTarget(nodes[i]);
    if (!target){ continue; }
    best = target;
    bestScore = score;
  }
  return best;
}
function airaNovelCatalogPagerContext(el){
  var node = el;
  for (var depth = 0; node && depth < 5; depth++){
    var marker = '';
    try {
      marker = ((node.id || '') + ' ' + (node.className || '') + ' ' +
        (node.getAttribute ? (node.getAttribute('role') || '') : '')).toLowerCase();
    } catch (e){ marker = ''; }
    if (marker.indexOf('pagenum') >= 0 || marker.indexOf('pager') >= 0 ||
      marker.indexOf('paging') >= 0 || marker.indexOf('pagination') >= 0 ||
      marker.indexOf('page-nav') >= 0 || marker.indexOf('page_nav') >= 0 ||
      marker.indexOf('fenye') >= 0){ return true; }
    var contextText = airaNovelClean(node.textContent || '');
    if (/\\d+\\s*[\\/／]\\s*\\d+/.test(contextText) || /共\\s*\\d+\\s*页/.test(contextText) ||
      /第\\s*\\d+\\s*页/.test(contextText)){ return true; }
    node = node.parentElement;
  }
  return false;
}
function airaNovelCatalogControlDisabled(el){
  if (!el){ return true; }
  if (el.hasAttribute && el.hasAttribute('disabled')){ return true; }
  if ((el.getAttribute && el.getAttribute('aria-disabled')) === 'true'){ return true; }
  var marker = '';
  try { marker = (' ' + (el.className || '') + ' ').toLowerCase().replace(/\\s+/g, ' '); } catch (e){ marker = ''; }
  return marker.indexOf(' disabled ') >= 0 || marker.indexOf(' off ') >= 0 ||
    marker.indexOf(' inactive ') >= 0 || marker.indexOf(' no-more ') >= 0 ||
    marker.indexOf(' nomore ') >= 0;
}
function airaNovelCatalogControlVisible(doc, el){
  var node = el;
  for (var depth = 0; node && depth < 5; depth++){
    if (node.getAttribute && node.getAttribute('aria-hidden') === 'true'){ return false; }
    if (doc.defaultView && doc.defaultView.getComputedStyle){
      var style = doc.defaultView.getComputedStyle(node);
      if (style && (style.display === 'none' || style.visibility === 'hidden')){ return false; }
    }
    node = node.parentElement;
  }
  return true;
}
function airaNovelCatalogInteractiveTarget(el){
  var node = el;
  for (var depth = 0; node && depth < 3; depth++){
    var tag = (node.tagName || '').toLowerCase();
    var role = node.getAttribute ? (node.getAttribute('role') || '') : '';
    var tabIndex = node.getAttribute ? node.getAttribute('tabindex') : null;
    if (tag === 'a' || tag === 'button' || tag === 'input' || role === 'button' ||
      (node.getAttribute && node.getAttribute('onclick')) || typeof node.onclick === 'function' ||
      (tabIndex !== null && tabIndex !== '-1')){ return node; }
    node = node.parentElement;
  }
  return null;
}
function airaNovelCatalogDocumentBusy(doc){
  var nodes = doc.querySelectorAll('[aria-busy="true"],.loading,.load,.spinner');
  for (var i = 0; i < nodes.length && i < 80; i++){
    var text = airaNovelClean(nodes[i].textContent || '').toLowerCase();
    if (text.indexOf('加载更多') >= 0 || text.indexOf('load more') >= 0){ continue; }
    if (!doc.defaultView || !doc.defaultView.getComputedStyle){ return true; }
    var style = doc.defaultView.getComputedStyle(nodes[i]);
    if (style && style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0'){
      return true;
    }
  }
  return false;
}
function airaNovelCatalogPageReady(doc){
  if (airaNovelCatalogDocumentBusy(doc)){ return false; }
  var selects = doc.querySelectorAll('select');
  for (var i = 0; i < selects.length && i < 20; i++){
    if (airaNovelCatalogPagerContext(selects[i]) && selects[i].options && selects[i].options.length === 0){
      return false;
    }
  }
  return true;
}
function airaNovelCatalogEntryContainer(doc, pageUrl, entries){
  if (!entries || entries.length < 3){ return null; }
  var entryUrls = {};
  for (var i = 0; i < entries.length; i++){
    if (entries[i] && entries[i].url){ entryUrls[entries[i].url] = true; }
  }
  var groups = [];
  var anchors = doc.querySelectorAll('a[href]');
  for (var a = 0; a < anchors.length && a < 2400; a++){
    var href = airaNovelAbs(anchors[a].getAttribute('href') || '', pageUrl);
    if (!href || !entryUrls[href]){ continue; }
    var node = anchors[a].parentElement;
    for (var depth = 0; node && depth < 7 && node !== doc.body && node !== doc.documentElement; depth++){
      var group = null;
      for (var g = 0; g < groups.length; g++){
        if (groups[g].node === node){ group = groups[g]; break; }
      }
      if (!group){ group = { node: node, urls: {}, count: 0 }; groups.push(group); }
      if (!group.urls[href]){ group.urls[href] = true; group.count++; }
      node = node.parentElement;
    }
  }
  var best = null;
  var bestCount = 0;
  var bestLinkCount = 1000000;
  for (var j = 0; j < groups.length; j++){
    if (groups[j].count < 3){ continue; }
    var linkCount = groups[j].node.querySelectorAll('a[href]').length;
    if (groups[j].count > bestCount || (groups[j].count === bestCount && linkCount < bestLinkCount)){
      best = groups[j].node;
      bestCount = groups[j].count;
      bestLinkCount = linkCount;
    }
  }
  return best;
}
function airaNovelCatalogNodeNearContainer(doc, el, catalogContainer){
  if (!catalogContainer){ return false; }
  var catalogAncestors = [];
  var catalogNode = catalogContainer;
  for (var c = 0; catalogNode && c < 4 && catalogNode !== doc.body && catalogNode !== doc.documentElement; c++){
    catalogAncestors.push(catalogNode);
    catalogNode = catalogNode.parentElement;
  }
  var controlNode = el;
  for (var depth = 0; controlNode && depth < 4 && controlNode !== doc.body &&
    controlNode !== doc.documentElement; depth++){
    for (var i = 0; i < catalogAncestors.length; i++){
      if (catalogAncestors[i] !== controlNode){ continue; }
      var catalogLinks = catalogContainer.querySelectorAll('a[href]').length;
      var commonLinks = controlNode.querySelectorAll('a[href]').length;
      if (commonLinks <= Math.max(catalogLinks * 3, catalogLinks + 24)){ return true; }
    }
    controlNode = controlNode.parentElement;
  }
  return false;
}
function airaNovelCatalogControlNearEntries(doc, el, pageUrl, entries){
  return airaNovelCatalogNodeNearContainer(doc, el,
    airaNovelCatalogEntryContainer(doc, pageUrl, entries));
}
function airaNovelCatalogPageProgress(doc, entries, pageUrl){
  var result = { current: 0, total: 0 };
  var catalogContainer = airaNovelCatalogEntryContainer(doc, pageUrl, entries);
  if (!catalogContainer){ return result; }
  var nodes = doc.querySelectorAll('nav,section,div,ul,ol,select');
  for (var i = 0; i < nodes.length && i < 800; i++){
    if (!airaNovelCatalogPagerContext(nodes[i]) ||
      !airaNovelCatalogNodeNearContainer(doc, nodes[i], catalogContainer)){ continue; }
    if (nodes[i].tagName && nodes[i].tagName.toLowerCase() === 'select' && nodes[i].options){
      if (nodes[i].options.length > result.total){ result.total = nodes[i].options.length; }
      if (result.current <= 0 && nodes[i].selectedIndex >= 0){ result.current = nodes[i].selectedIndex + 1; }
    }
    var text = airaNovelClean(nodes[i].textContent || '');
    var pair = text.match(/(\\d+)\\s*[\\/／]\\s*(\\d+)/);
    if (pair){
      var current = airaNovelPositiveInteger(pair[1]);
      var total = airaNovelPositiveInteger(pair[2]);
      if (current > 0 && total >= current &&
        (total > result.total || (total === result.total && current > result.current))){
        result.current = current;
        result.total = total;
      }
    }
    var totalOnly = text.match(/共\\s*(\\d+)\\s*页/);
    if (totalOnly){
      var parsedTotal = airaNovelPositiveInteger(totalOnly[1]);
      if (parsedTotal > result.total){ result.total = parsedTotal; }
    }
  }
  return result;
}
/**
 * 找目录分页的“下一页”交互控件。既支持链接，也支持由站点脚本绑定点击事件的 button/span/div。
 * 只使用控件语义和分页上下文，不读取 host、固定 class 或站点接口。
 */
function airaNovelFindNextCatalogControl(doc, requireInteractive, entries, pageUrl){
  var nodes = doc.querySelectorAll('a,button,input[type="button"],input[type="submit"],[role="button"],span,div,li');
  var best = null; var bestScore = 0;
  var exactLabels = {
    '下一页': 1, '下页': 1, '后一页': 1, '后页': 1,
    'next': 1, 'nextpage': 1, '›': 1, '»': 1, '>': 1, '→': 1
  };
  for (var i = 0; i < nodes.length && i < 1200; i++){
    var el = nodes[i];
    if (airaNovelCatalogControlDisabled(el) || !airaNovelCatalogControlVisible(doc, el) ||
      !airaNovelCatalogPagerContext(el)){ continue; }
    var text = airaNovelCatalogControlText(el);
    if (text.indexOf('下一章') >= 0 || text.indexOf('下章') >= 0 || text.indexOf('nextchapter') >= 0){ continue; }
    var marker = '';
    try {
      marker = ((el.id || '') + ' ' + (el.className || '') + ' ' +
        (el.getAttribute ? (el.getAttribute('rel') || '') : '')).toLowerCase();
    } catch (e){ marker = ''; }
    if (marker.indexOf('next-chapter') >= 0 || marker.indexOf('next_chapter') >= 0 ||
      marker.indexOf('nextchapter') >= 0 ||
      marker.indexOf('chapter-next') >= 0 || marker.indexOf('chapternext') >= 0){ continue; }
    var score = 0;
    if (exactLabels[text]){ score += 120; }
    if (marker.indexOf('next') >= 0){ score += 45; }
    if (el.getAttribute && el.getAttribute('rel') === 'next'){ score += 80; }
    score += 60;
    if (score < 120 || score <= bestScore){ continue; }
    var target = requireInteractive ? airaNovelCatalogInteractiveTarget(el) : el;
    if (!target){ continue; }
    if (requireInteractive && !airaNovelCatalogControlNearEntries(doc, target, pageUrl, entries)){ continue; }
    best = target;
    bestScore = score;
  }
  return best;
}
function airaNovelCatalogFingerprint(entries){
  var urls = [];
  for (var i = 0; i < entries.length; i++){
    if (entries[i] && entries[i].url){ urls.push(entries[i].url); }
  }
  return urls.join('\\n');
}
function airaNovelMergeCatalogEntries(target, indexByUrl, incoming, maxEntries){
  for (var i = 0; i < incoming.length; i++){
    var item = incoming[i];
    if (!item || !item.url){ continue; }
    var existing = indexByUrl[item.url];
    if (existing === undefined){
      if (target.length >= maxEntries){ continue; }
      indexByUrl[item.url] = target.length;
      target.push(item);
    } else {
      // 同一真实 URL 在后续目录页出现时,使用后读到的标题。
      target[existing] = item;
    }
  }
}
function airaNovelSortMergedCatalog(entries){
  if (entries.length < 2){ return entries; }
  var firstOrdinal = -1; var lastOrdinal = -1;
  for (var i = 0; i < entries.length && firstOrdinal < 0; i++){
    firstOrdinal = airaNovelTitleOrdinal(entries[i].title);
  }
  for (var j = entries.length - 1; j >= 0 && lastOrdinal < 0; j--){
    lastOrdinal = airaNovelTitleOrdinal(entries[j].title);
  }
  if (firstOrdinal >= 0 && lastOrdinal >= 0 && firstOrdinal > lastOrdinal){ entries.reverse(); }
  return entries;
}
function airaNovelMetaProperty(doc, propertyName){
  var node = null;
  try { node = doc.querySelector('meta[property="' + propertyName + '"]'); } catch (e){ node = null; }
  return node ? airaNovelClean(node.getAttribute('content')) : '';
}
function airaNovelMetaName(doc, name){
  var node = null;
  try { node = doc.querySelector('meta[name="' + name + '"]'); } catch (e){ node = null; }
  return node ? airaNovelClean(node.getAttribute('content')) : '';
}
function airaNovelFirstElement(doc, selectors){
  for (var i = 0; i < selectors.length; i++){
    var node = airaNovelQOne(doc, selectors[i]);
    if (node){ return node; }
  }
  return null;
}
function airaNovelFirstNonEmptyTextElement(doc, selectors){
  for (var i = 0; i < selectors.length; i++){
    var nodes = airaNovelQAll(doc, selectors[i]);
    var limit = Math.min(nodes.length, 80);
    for (var j = 0; j < limit; j++){
      if (airaNovelClean(nodes[j].textContent || '')){ return nodes[j]; }
    }
  }
  return null;
}
function airaNovelStripFieldLabel(value, labels){
  var text = airaNovelClean(value);
  for (var i = 0; i < labels.length; i++){
    var label = labels[i];
    if (text.indexOf(label) === 0){
      text = text.substring(label.length).replace(/^[：:\\s]+/, '').trim();
      break;
    }
  }
  return text;
}
function airaNovelDocumentBookTitle(doc){
  var title = airaNovelClean(doc.title || '');
  if (!title){ return ''; }
  var quoted = title.match(/[《〈]([^《》〈〉]{1,80})[》〉]/);
  if (quoted){ return airaNovelClean(quoted[1]); }
  var separators = ['_', '｜', '|', ' - ', ' – ', ' — '];
  for (var i = 0; i < separators.length; i++){
    var splitAt = title.indexOf(separators[i]);
    if (splitAt > 0){ title = title.substring(0, splitAt); break; }
  }
  title = title.replace(/^[《〈\\s]+/, '').replace(/[》〉\\s]+$/, '');
  return title.length > 0 && title.length <= 80 ? title : '';
}
function airaNovelBookTitleNearReadingAction(doc, base){
  var readingUrl = airaNovelFindReadingActionLink(doc, base);
  if (!readingUrl){ return ''; }
  var links = doc.querySelectorAll('a[href]');
  var action = null;
  for (var i = 0; i < links.length && i < 1600; i++){
    var href = links[i].getAttribute('href') || '';
    if (!href || href.indexOf('javascript:') === 0){ continue; }
    if (airaNovelAbs(href, base) === readingUrl){ action = links[i]; break; }
  }
  var root = action ? action.parentElement : null;
  for (var depth = 0; root && depth < 5; depth++){
    var candidates = root.querySelectorAll(
      'h1,h2,h3,[itemprop="name"],[class~="title"],[class$="-title"],[class$="_title"]');
    var best = ''; var bestScore = -1;
    for (var j = 0; j < candidates.length && j < 80; j++){
      var text = airaNovelClean(candidates[j].textContent || '');
      if (!text || text.length > 80 || airaNovelIsGenericBookHeading(text) ||
        airaNovelLooksChapter(text) || airaNovelTitleOrdinal(text) >= 0 ||
        text.indexOf('开始阅读') >= 0 || text.indexOf('立即阅读') >= 0){ continue; }
      var tag = String(candidates[j].tagName || '').toLowerCase();
      var score = tag === 'h1' ? 8 : (tag === 'h2' || tag === 'h3' ? 6 : 3);
      if (candidates[j].getAttribute('itemprop') === 'name'){ score += 4; }
      if (String(candidates[j].className || '').split(/\\s+/).indexOf('title') >= 0){ score += 3; }
      if (score > bestScore){ best = text; bestScore = score; }
    }
    if (best){ return best; }
    root = root.parentElement;
  }
  return '';
}
function airaNovelFindLabeledValue(doc, labels){
  var nodes = doc.querySelectorAll('p,span,li,div');
  var limit = Math.min(nodes.length, 1600);
  var best = '';
  for (var i = 0; i < limit; i++){
    var text = airaNovelClean(nodes[i].textContent || '');
    if (!text || text.length > 120){ continue; }
    for (var j = 0; j < labels.length; j++){
      if (text.indexOf(labels[j]) !== 0){ continue; }
      var value = airaNovelStripFieldLabel(text, [labels[j]]);
      if (value && value.length <= 80 && (!best || value.length < best.length)){ best = value; }
    }
  }
  return best;
}
function airaNovelIsGenericBookHeading(value){
  var text = airaNovelClean(value).replace(/[：:]/g, '');
  var headings = ['书籍详情', '小说详情', '作品详情', '图书详情',
    '书籍信息', '小说信息', '作品信息', '图书信息'];
  for (var i = 0; i < headings.length; i++){
    if (text === headings[i]){ return true; }
  }
  return false;
}
function airaNovelSchemaValueText(value){
  if (typeof value === 'string' || typeof value === 'number'){ return airaNovelClean(String(value)); }
  if (!value || typeof value !== 'object'){ return ''; }
  return airaNovelSchemaValueText(value.name || value.headline || value['@value'] || '');
}
function airaNovelSchemaValueList(value){
  var values = Array.isArray(value) ? value : [value];
  var output = [];
  for (var i = 0; i < values.length; i++){
    var text = airaNovelSchemaValueText(values[i]);
    if (text && output.indexOf(text) < 0){ output.push(text); }
  }
  return output.join(', ');
}
function airaNovelSchemaImage(value, base){
  var values = Array.isArray(value) ? value : [value];
  for (var i = 0; i < values.length; i++){
    var raw = typeof values[i] === 'string' ? values[i] :
      (values[i] && typeof values[i] === 'object'
        ? (values[i].contentUrl || values[i].url || values[i]['@id'] || '') : '');
    var resolved = airaNovelAbs(raw, base);
    try {
      var parsed = new URL(resolved);
      if (parsed.protocol === 'http:' || parsed.protocol === 'https:'){ return parsed.href; }
    } catch (e){ }
  }
  return '';
}
function airaNovelSchemaKind(node){
  var rawTypes = node && Array.isArray(node['@type']) ? node['@type'] : [node ? node['@type'] : ''];
  for (var i = 0; i < rawTypes.length; i++){
    var type = String(rawTypes[i] || '').toLowerCase();
    var separator = Math.max(type.lastIndexOf('/'), type.lastIndexOf('#'));
    if (separator >= 0){ type = type.substring(separator + 1); }
    if (type === 'comicseries'){ return 'comic'; }
    if (type === 'book' || type === 'novel'){ return 'novel'; }
  }
  return '';
}
function airaNovelLooseSchemaKind(source){
  var pattern = /[\"']?@type[\"']?\\s*:\\s*[\"']?([A-Za-z][A-Za-z0-9_-]*)[\"']?/g;
  var match;
  while ((match = pattern.exec(source)) !== null){
    var kind = airaNovelSchemaKind({ '@type': match[1] });
    if (kind){ return kind; }
  }
  return '';
}
function airaNovelSchemaCandidates(value, output){
  if (Array.isArray(value)){
    for (var i = 0; i < value.length; i++){ airaNovelSchemaCandidates(value[i], output); }
    return;
  }
  if (!value || typeof value !== 'object'){ return; }
  output.push(value);
  if (Array.isArray(value['@graph'])){ airaNovelSchemaCandidates(value['@graph'], output); }
}
function airaNovelReadBookSchema(doc, base){
  var empty = { kind: '', title: '', author: '', cover: '', synopsis: '', category: '', latest: '' };
  var scripts = doc.querySelectorAll('script[type="application/ld+json"]');
  var limit = Math.min(scripts.length, 20);
  var best = empty; var bestScore = -1;
  for (var i = 0; i < limit; i++){
    var source = scripts[i].textContent || '';
    if (!source || source.length > 1024 * 1024){ continue; }
    var candidates = [];
    try { airaNovelSchemaCandidates(JSON.parse(source), candidates); }
    catch (e){
      var looseKind = airaNovelLooseSchemaKind(source);
      if (looseKind && bestScore < 0){
        best = { kind: looseKind, title: '', author: '', cover: '', synopsis: '', category: '', latest: '' };
        bestScore = 0;
      }
      continue;
    }
    for (var j = 0; j < candidates.length && j < 200; j++){
      var node = candidates[j];
      var kind = airaNovelSchemaKind(node);
      if (!kind){ continue; }
      var candidate = {
        kind: kind,
        title: airaNovelSchemaValueText(node.name || node.headline),
        author: airaNovelSchemaValueList(node.author || node.creator),
        cover: airaNovelSchemaImage(node.image || node.thumbnailUrl, base),
        synopsis: airaNovelSchemaValueText(node.description || node.abstract),
        category: airaNovelSchemaValueList(node.genre),
        latest: airaNovelSchemaValueText(node.hasPart)
      };
      if (!candidate.title){ continue; }
      var score = 8 + (candidate.synopsis ? 3 : 0) + (candidate.author ? 2 : 0) +
        (candidate.cover ? 2 : 0) + (candidate.category ? 1 : 0) + (candidate.latest ? 1 : 0);
      if (score > bestScore){ best = candidate; bestScore = score; }
    }
  }
  return best;
}
function airaNovelHasBookSchema(doc){
  return airaNovelReadBookSchema(doc, doc.baseURI || location.href).kind.length > 0;
}
function airaNovelExtractSparseComicCatalog(doc, base, anchors, rule){
  var schema = airaNovelReadBookSchema(doc, base);
  var readingActionUrl = airaNovelFindReadingActionLink(doc, base);
  if (schema.kind !== 'comic' || !readingActionUrl){ return []; }
  var current = null;
  try { current = new URL(base); } catch (e){ return []; }
  var output = [];
  var seen = {};
  for (var i = 0; i < anchors.length && i < 1600; i++){
    var title = airaNovelClean(anchors[i].textContent);
    if (!airaNovelLooksChapter(title) && airaNovelTitleOrdinal(title) < 0){ continue; }
    var href = anchors[i].getAttribute('href');
    if (!href || href.indexOf('javascript:') === 0 || href.charAt(0) === '#'){ continue; }
    var resolved = airaNovelAbs(href, base);
    var target = null;
    try { target = new URL(resolved); } catch (e2){ target = null; }
    if (!target || (target.protocol !== 'http:' && target.protocol !== 'https:') ||
      target.origin !== current.origin || seen[target.href] ||
      !airaNovelRuleUrlAllowed(rule, target.href, base)){ continue; }
    seen[target.href] = true;
    output.push({ title: title, url: target.href, num: airaNovelUrlNum(target.href) });
    if (output.length > 2){ return []; }
  }
  if (!seen[readingActionUrl]){
    output.push({
      title: schema.latest && (airaNovelLooksChapter(schema.latest) ||
        airaNovelTitleOrdinal(schema.latest) >= 0) ? schema.latest : '第1话',
      url: readingActionUrl,
      num: airaNovelUrlNum(readingActionUrl)
    });
  }
  if (output.length === 0 || output.length > 2){ return []; }
  return airaNovelSortMergedCatalog(output);
}
function airaNovelBookEvidence(doc, entries, base){
  var rule = airaNovelRule();
  var titleSelectors = ['#info h1', '#maininfo h1', '.book-info h1', '.book-detail h1',
    '.novel-info h1', '[itemprop="name"]', 'main h1', 'h1',
    '[class*="book"] h1, [class*="book"] h2, [class*="book"] h3'];
  var synopsisSelectors = ['#intro', '.intro', '#introduction', '.book-intro', '.bookintro .con',
    '.bookintro', '.book-desc', '.book-description', '.novel-intro', '[itemprop="description"]',
    '[class*="book"] [class*="desc"]'];
  var authorSelectors = ['[itemprop="author"]', '.book-author', '.novel-author', '#author', '.author'];
  var schema = airaNovelReadBookSchema(doc, base);
  var ruleTitleElement = rule && rule.bookTitleSelector
    ? airaNovelFirstNonEmptyTextElement(doc, [rule.bookTitleSelector]) : null;
  var titleElement = ruleTitleElement || airaNovelFirstElement(doc, titleSelectors);
  var synopsisElement = rule && rule.synopsisSelector
    ? airaNovelFirstNonEmptyTextElement(doc, [rule.synopsisSelector]) : null;
  if (!synopsisElement){ synopsisElement = airaNovelFirstElement(doc, synopsisSelectors); }
  var authorElement = rule && rule.authorSelector
    ? airaNovelFirstNonEmptyTextElement(doc, [rule.authorSelector]) : null;
  if (!authorElement){ authorElement = airaNovelFirstElement(doc, authorSelectors); }
  var ruleTitle = ruleTitleElement ? airaNovelClean(ruleTitleElement.textContent) : '';
  var headingTitle = titleElement ? airaNovelClean(titleElement.textContent) : '';
  if (airaNovelIsGenericBookHeading(headingTitle)){ headingTitle = ''; }
  var title = schema.title || airaNovelMetaProperty(doc, 'og:novel:book_name') ||
    ruleTitle || airaNovelBookTitleNearReadingAction(doc, base) || headingTitle ||
    airaNovelFindLabeledValue(doc, ['书名', '作品名', '小说名']) || airaNovelDocumentBookTitle(doc);
  var synopsis = schema.synopsis || (synopsisElement ? airaNovelClean(synopsisElement.textContent) : '') ||
    airaNovelMetaName(doc, 'description');
  var author = schema.author || airaNovelMetaProperty(doc, 'og:novel:author') || airaNovelMetaName(doc, 'author') ||
    (authorElement ? airaNovelClean(authorElement.textContent) : '');
  var chapterLike = 0;
  for (var i = 0; i < entries.length; i++){
    if (airaNovelLooksChapter(entries[i].title) || airaNovelTitleOrdinal(entries[i].title) > 0){ chapterLike++; }
  }
  var explicitNovelMeta = airaNovelMetaProperty(doc, 'og:novel:book_name').length > 0;
  var schemaBook = schema.kind.length > 0;
  var pageText = doc.body ? (doc.body.textContent || '') : '';
  var hasBookLabels = pageText.indexOf('简介') >= 0 &&
    (pageText.indexOf('目录') >= 0 || pageText.indexOf('章节') >= 0);
  var readingActionUrl = airaNovelFindReadingActionLink(doc, base);
  var hasStartReadingLink = readingActionUrl.length > 0;
  var hasCatalogLink = airaNovelFindFullCatalogPage(doc, base).length > 0 ||
    !!airaNovelFindCatalogRevealControl(doc);
  var controls = doc.querySelectorAll('a,button,input[type="button"],input[type="submit"],[role="button"]');
  var controlLimit = Math.min(controls.length, 1600);
  for (var j = 0; j < controlLimit; j++){
    if (airaNovelIsReadingActionText(airaNovelCatalogControlText(controls[j]))){
      hasStartReadingLink = true;
      break;
    }
  }
  if (!author && hasStartReadingLink){ author = airaNovelFindLabeledValue(doc, ['作者', '作家']); }
  var structuralBook = title.length > 0 && synopsis.length >= 20 &&
    (author.length > 0 || hasBookLabels);
  var explicitNovelStructure = explicitNovelMeta &&
    ((entries.length >= 3 && chapterLike >= 1) || (hasStartReadingLink && hasCatalogLink));
  // Large news/forum lists often contain a few chapter-like headlines or numeric pagination links.
  var chapterDensity = entries.length > 0 ? chapterLike / entries.length : 0;
  var catalogBookStructure = entries.length >= 5 && chapterLike >= 3 && chapterDensity >= 0.5 &&
    (schemaBook || structuralBook);
  var actionCatalogBookStructure = hasStartReadingLink && entries.length >= 3 && chapterLike >= 3 &&
    chapterDensity >= 0.5 && (hasCatalogLink || entries.length >= 5);
  var structuredActionBook = schemaBook && title.length > 0 &&
    (synopsis.length >= 20 || author.length > 0 || schema.cover.length > 0) &&
    hasStartReadingLink && hasCatalogLink;
  var sparseComicBookStructure = schema.kind === 'comic' && title.length > 0 &&
    (synopsis.length >= 20 || author.length > 0 || schema.cover.length > 0) &&
    readingActionUrl.length > 0 && entries.length >= 1 && entries.length <= 2 && chapterLike >= 1;
  var siteProfileCatalogCount = airaNovelRuleCatalogEvidenceCount(doc, base, rule);
  var siteProfileBookStructure = siteProfileCatalogCount >= 3 && title.length > 0 &&
    (structuralBook || (hasStartReadingLink && (hasCatalogLink || siteProfileCatalogCount >= 5)));
  var eligible = explicitNovelStructure || catalogBookStructure || actionCatalogBookStructure ||
    structuredActionBook || sparseComicBookStructure || siteProfileBookStructure;
  return {
    eligible: eligible,
    title: title,
    synopsis: synopsis,
    author: author,
    chapterLike: chapterLike,
    explicitNovelMeta: explicitNovelMeta,
    schemaBook: schemaBook,
    schemaKind: schema.kind,
    hasStartReadingLink: hasStartReadingLink,
    hasCatalogLink: hasCatalogLink,
    readingActionUrl: readingActionUrl,
    siteProfileCatalogCount: siteProfileCatalogCount,
    siteProfileBookStructure: siteProfileBookStructure
  };
}
function airaNovelPageTotal(doc){
  var content = airaNovelPickContent(doc);
  var h = doc.querySelector('h1');
  var t = (content ? (content.textContent || '') : '') + ' ' + (h ? (h.textContent || '') : '');
  var m = t.match(/第\\s*(\\d+)\\s*\\/\\s*(\\d+)\\s*页/);
  if (m){ return parseInt(m[2], 10); }
  return 1;
}
function airaNovelExtractChapter(doc, base){
  var contentEl = airaNovelPickContent(doc);
  var ruleC = airaNovelRule();
  var allowRuleTitle = ruleC && (!ruleC.requiresContentQualityGate ||
    airaNovelBoundedContentPassesQualityGate(airaNovelQOne(doc, ruleC.contentSelector)));
  var titleEl = allowRuleTitle && ruleC.chapterTitleSelector
    ? airaNovelQOne(doc, ruleC.chapterTitleSelector) : null;
  if (!titleEl || !airaNovelClean(titleEl.textContent || '')){
    titleEl = airaNovelFirstNonEmptyTextElement(doc, [
      '.bookname h1', '#chaptertitle', '.chapter-title', '.titlename', '.read-title h1',
      '[class*="chapter"][class*="title"]', 'h1', '.title'
    ]);
  }
  var title = titleEl ? airaNovelClean(titleEl.textContent) : '';
  title = title.replace(/[（(]\\s*(?:第\\s*)?\\d+\\s*\\/\\s*\\d+\\s*(?:页)?\\s*[)）]/g, '').trim();
  title = title.replace(/^\\s*\\d+\\s*[)）]\\s*/, '');
  var paragraphs = [];
  if (contentEl){
    var lines = airaNovelNodeToText(contentEl).split('\\n');
    for (var i = 0; i < lines.length; i++){
      var t = airaNovelClean(lines[i]);
      if (airaNovelFooterBoundary(t)){ break; }
      if (airaNovelBadLine(t)){ continue; }
      if (t.length < 2){ continue; }
      paragraphs.push(t);
    }
  }
  var infoEl = doc.querySelector('#info h1') || doc.querySelector('.info h1') || doc.querySelector('#bookinfo h1');
  var nextPage = airaNovelFindLink(doc, base, ['下一页', '下页']);
  if (!airaNovelRuleUrlAllowed(ruleC, nextPage, base)){ nextPage = ''; }
  if (nextPage === base){ nextPage = ''; }
  var catalogUrl = airaNovelFindPreferredCatalogPage(doc, base);
  if (!airaNovelRuleUrlAllowed(ruleC, catalogUrl, base)){ catalogUrl = ''; }
  return {
    pageUrl: base,
    title: title,
    paragraphs: paragraphs,
    images: ruleC && ruleC.kind === 'comic'
      ? airaComicCollectChapterImages(doc, base, ruleC.comicChapterSource)
      : [],
    prevUrl: airaNovelRuleLink(doc, base, ruleC, ruleC ? ruleC.prevSelector : '', ['上一章', '上一话', '上章']),
    nextUrl: airaNovelRuleLink(doc, base, ruleC, ruleC ? ruleC.nextSelector : '', ['下一章', '下一话', '下章']),
    catalogUrl: catalogUrl,
    bookTitle: infoEl ? airaNovelClean(infoEl.textContent) : '',
    pageTotal: airaNovelPageTotal(doc),
    nextPageUrl: nextPage
  };
}
function airaNovelDecodeBuffer(buf, contentType){
  var ct = (contentType || '').toLowerCase();
  var charset = '';
  if (ct.indexOf('gbk') >= 0 || ct.indexOf('gb2312') >= 0 || ct.indexOf('gb18030') >= 0){ charset = 'gbk'; }
  if (charset === ''){
    var head = '';
    try { head = new TextDecoder('latin1').decode(new Uint8Array(buf.slice(0, 2000))).toLowerCase(); } catch (e){ head = ''; }
    if (head.indexOf('gb2312') >= 0 || head.indexOf('gbk') >= 0 || head.indexOf('gb18030') >= 0){ charset = 'gbk'; }
  }
  if (charset === ''){ charset = 'utf-8'; }
  try { return new TextDecoder(charset).decode(buf); } catch (e2){ return new TextDecoder('utf-8').decode(buf); }
}
function airaNovelLoadDoc(url){
  return fetch(url, { credentials: 'include' }).then(function(resp){
    var ct = resp.headers.get('content-type') || '';
    var responseUrl = resp.url || url;
    return resp.arrayBuffer().then(function(buf){
      return {
        doc: new DOMParser().parseFromString(airaNovelDecodeBuffer(buf, ct), 'text/html'),
        url: responseUrl
      };
    });
  });
}
`;

export class NovelExtractionService {
  private readonly comicBookOverviewAcquisitionEngine: ComicBookOverviewAcquisitionEngine =
    new ComicBookOverviewAcquisitionEngine();
  private readonly comicChapterAcquisitionEngine: ComicChapterAcquisitionEngine =
    sharedComicChapterAcquisitionEngine;
  private chapterAcquisitionEngine: NovelChapterAcquisitionEngine = new NovelChapterAcquisitionEngine();
  private catalogPageAcquisitionEngine: NovelCatalogPageAcquisitionEngine =
    new NovelCatalogPageAcquisitionEngine();
  private ruleCatalog: NovelRuleCatalog;
  private chapterRequestSequence: number = 0;
  private catalogRequestSequence: number = 0;

  constructor(ruleCatalog: NovelRuleCatalog = sharedNovelRuleCatalog) {
    this.ruleCatalog = ruleCatalog;
  }

  /** 生成注入脚本前缀:把命中的站点规则塞进页面上下文。 */
  private ruleHeader(url: string): string {
    return 'var __airaRule = ' + this.ruleCatalog.buildRuntimePayload(url) + ';\n';
  }

  private runtimeHelpers(): string {
    return NOVEL_JS_HELPERS + this.comicChapterAcquisitionEngine.buildRuntimeHelpers();
  }

  /** 轻量探测当前页类型:'chapter' / 'book' / ''。用于自动接管前的快速判断。 */
  async detectNovelPage(controller: webview.WebviewController, pageUrl: string = ''): Promise<string> {
    const blocked: boolean = this.ruleCatalog.isBlocked(pageUrl);
    if (blocked) {
      return '';
    }
    const pageRule: NovelSiteRule | undefined = this.ruleCatalog.resolveRule(pageUrl);
    const supportsComicBookPage: boolean = pageRule?.comicBookSource !== undefined &&
      this.comicBookOverviewAcquisitionEngine.supportsBookPage(pageUrl, pageRule.comicBookSource);
    if (pageRule?.comicBookSource !== undefined && supportsComicBookPage) {
      const overview: NovelBookOverview | undefined =
        await this.comicBookOverviewAcquisitionEngine.acquireOverview(
          pageUrl,
          pageRule.comicBookSource,
          NOVEL_BOOK_INITIAL_CATALOG_ENTRIES
      );
      const detected: boolean = overview !== undefined && overview.title.length > 0 &&
        overview.startChapterUrl.length > 0;
      return detected ? 'book' : '';
    }
    const script: string = this.ruleHeader(pageUrl) + this.runtimeHelpers() + `
(function(){
  try {
    try { delete window.${NOVEL_DETECTION_GLOBAL}; } catch (cleanupError){ }
    var pageRule = airaNovelRule();
    if (!pageRule && airaNovelLooksVideoEpisodePage(document)){ return ''; }
    var hasPrevOrNext = false;
    var hasChapterNeighbor = false;
    var hasCatalogLink = airaNovelFindFullCatalogPage(document, location.href).length > 0;
    var chapterLikeLinks = 0;
    var links = document.querySelectorAll('a[href]');
    var linkLimit = Math.min(links.length, 1600);
    for (var i = 0; i < linkLimit; i++){
      var t = airaNovelNavigationText(links[i].textContent);
      if (t.indexOf('下一章') >= 0 || t.indexOf('上一章') >= 0 ||
        t.indexOf('下一话') >= 0 || t.indexOf('上一话') >= 0){
        hasPrevOrNext = true;
        hasChapterNeighbor = true;
      } else if (t === '下一页' || t === '上一页' || t === '下页' || t === '上页'){
        hasPrevOrNext = true;
      }
      if (t === '目录' || t.indexOf('章节目录') >= 0 || t.indexOf('完整目录') >= 0 ||
        t.indexOf('全部章节') >= 0 || t.indexOf('所有章节') >= 0 ||
        t.indexOf('查看更多章节') >= 0 || t.indexOf('返回目录') >= 0){ hasCatalogLink = true; }
      if (airaNovelLooksChapter(t) || airaNovelTitleOrdinal(t) > 0){ chapterLikeLinks++; }
    }
    var explicitBookMeta = airaNovelMetaProperty(document, 'og:novel:book_name').length > 0;
    var shouldInspectBook = chapterLikeLinks >= 3 || explicitBookMeta || airaNovelHasBookSchema(document) ||
      (pageRule && (pageRule.bookTitleSelector || pageRule.chapterLinkSelector));
    if (shouldInspectBook){
      var entries = airaNovelExtractCatalog(document, location.href);
      if (airaNovelBookEvidence(document, entries, location.href).eligible){
        window.${NOVEL_DETECTION_GLOBAL} = { pageUrl: location.href, entries: entries };
        return 'book';
      }
    }
    var body = airaNovelPickContent(document);
    var profileContentElement = pageRule && pageRule.contentSelector
      ? airaNovelQOne(document, pageRule.contentSelector) : null;
    var profileContentReady = !!(pageRule && pageRule.kind === 'novel' && profileContentElement &&
      airaNovelClean(airaNovelNodeToText(profileContentElement)).length > 400 &&
      (!pageRule.requiresContentQualityGate || airaNovelBoundedContentPassesQualityGate(profileContentElement)));
    var profileTitleElement = pageRule && pageRule.chapterTitleSelector
      ? airaNovelQOne(document, pageRule.chapterTitleSelector) : null;
    var profileTitleReady = !!(pageRule && pageRule.kind === 'novel' && profileTitleElement &&
      airaNovelClean(profileTitleElement.textContent).length > 0);
    var titleElement = profileTitleReady ? profileTitleElement : airaNovelFirstElement(document,
      ['.bookname h1', '.chapter-title', '.read-title h1', 'article h1', 'main h1', 'h1']);
    var title = titleElement ? airaNovelClean(titleElement.textContent) : '';
    var profilePrevCandidate = pageRule && pageRule.kind === 'novel'
      ? airaNovelRuleLink(document, location.href, pageRule, pageRule.prevSelector, ['上一章', '上一话', '上章']) : '';
    var profileNextCandidate = pageRule && pageRule.kind === 'novel'
      ? airaNovelRuleLink(document, location.href, pageRule, pageRule.nextSelector, ['下一章', '下一话', '下章']) : '';
    var profilePrevUrl = airaNovelRecognitionNeighborUrl(pageRule, profilePrevCandidate, location.href);
    var profileNextUrl = airaNovelRecognitionNeighborUrl(pageRule, profileNextCandidate, location.href);
    var hasProfileChapterNeighbor = profilePrevUrl.length > 0 || profileNextUrl.length > 0;
    if (hasProfileChapterNeighbor){ hasPrevOrNext = true; hasChapterNeighbor = true; }
    var ordinalChapterIdentity = airaNovelTitleOrdinal(title) > 0 && airaNovelUrlNum(location.href) > 0 &&
      hasChapterNeighbor;
    var siteProfileChapterStructure = profileContentReady && profileTitleReady && hasProfileChapterNeighbor;
    var chapterStructure = airaNovelLooksChapter(title) || ordinalChapterIdentity || hasCatalogLink ||
      siteProfileChapterStructure;
    if (hasPrevOrNext && chapterStructure && body &&
      airaNovelClean(airaNovelNodeToText(body)).length > 400){ return 'chapter'; }
    // 漫画引擎保持规则优先,小说页上的推荐封面不能触发漫画模式。
    if (airaComicRecognizesChapter(pageRule, document, location.href, hasPrevOrNext)){ return 'chapter'; }
    return '';
  } catch (e){ return ''; }
})();`;
    try {
      const raw: string = await controller.runJavaScript(script);
      const normalized: string = this.normalizeRawScriptResult(raw);
      return (normalized === 'chapter' || normalized === 'book') ? normalized : '';
    } catch (_error) {
      return '';
    }
  }

  /** 抽取当前页(章节页)。多页章节只返回第一页,由控制器按 pageTotal 决定是否合并抓全。 */
  async extractCurrent(controller: webview.WebviewController, pageUrl: string = ''): Promise<NovelChapterExtract> {
    const script: string = this.ruleHeader(pageUrl) + this.runtimeHelpers() + `
(function(){
  try { return JSON.stringify(airaNovelExtractChapter(document, location.href)); }
  catch (e){ return JSON.stringify({ paragraphs: [] }); }
})();`;
    const retryDelaysMs: number[] = [120, 240, 480, 900, 1500, 2200];
    let current: NovelChapterExtract = this.emptyChapter();
    for (let attempt: number = 0; attempt <= retryDelaysMs.length; attempt += 1) {
      const raw: string = await controller.runJavaScript(script);
      current = this.parseChapter(raw);
      if (current.paragraphs.length > 0 || current.images.length > 0 || attempt >= retryDelaysMs.length) {
        break;
      }
      await this.delay(retryDelaysMs[attempt]);
    }
    const rule: NovelSiteRule | undefined = this.ruleCatalog.resolveRule(pageUrl);
    if (rule?.comicChapterSource !== undefined && !this.comicChapterAcquisitionEngine.isComicArtifact(current.images)) {
      const acquired: NovelChapterExtract | undefined = await this.comicChapterAcquisitionEngine.acquire(
        controller,
        pageUrl,
        rule.comicChapterSource
      );
      if (acquired !== undefined) {
        if (acquired.title.length === 0) {
          acquired.title = current.title;
        }
        if (acquired.prevUrl.length === 0) {
          acquired.prevUrl = current.prevUrl;
        }
        if (acquired.nextUrl.length === 0) {
          acquired.nextUrl = current.nextUrl;
        }
        if (acquired.catalogUrl.length === 0) {
          acquired.catalogUrl = current.catalogUrl;
        }
        return acquired;
      }
    }
    return current;
  }

  /** 抽取接管首屏所需的书籍概览；完整目录由 fetchCatalog 在首屏之外负责。 */
  async extractBookOverview(controller: webview.WebviewController, pageUrl: string = ''): Promise<NovelBookOverview> {
    const pageRule: NovelSiteRule | undefined = this.ruleCatalog.resolveRule(pageUrl);
    const supportsComicBookPage: boolean = pageRule?.comicBookSource !== undefined &&
      this.comicBookOverviewAcquisitionEngine.supportsBookPage(pageUrl, pageRule.comicBookSource);
    if (pageRule?.comicBookSource !== undefined && supportsComicBookPage) {
      const acquired: NovelBookOverview | undefined =
        await this.comicBookOverviewAcquisitionEngine.acquireOverview(
          pageUrl,
          pageRule.comicBookSource,
          NOVEL_BOOK_INITIAL_CATALOG_ENTRIES
        );
      if (acquired !== undefined) {
        hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
          'bookOverview source=comic_book_api initial=%{public}d total=%{public}d completeSource=%{public}s',
          acquired.initialEntries.length, acquired.catalogTotal,
          acquired.catalogSourceComplete ? 'true' : 'false');
        return acquired;
      }
    }
    const script: string = this.ruleHeader(pageUrl) + this.runtimeHelpers() + `
(function(){
  try {
    var rule = airaNovelRule();
    var detection = window.${NOVEL_DETECTION_GLOBAL};
    var entries = detection && detection.pageUrl === location.href && Array.isArray(detection.entries)
      ? detection.entries : airaNovelExtractCatalog(document, location.href);
    try { delete window.${NOVEL_DETECTION_GLOBAL}; } catch (cleanupError){ }
    entries = airaNovelSortMergedCatalog(entries);
    var evidence = airaNovelBookEvidence(document, entries, location.href);
    var schema = airaNovelReadBookSchema(document, location.href);
    var ruleTitleElement = rule && rule.bookTitleSelector
      ? airaNovelFirstNonEmptyTextElement(document, [rule.bookTitleSelector]) : null;
    var title = schema.title ||
      (ruleTitleElement ? airaNovelClean(ruleTitleElement.textContent) : evidence.title);
    var cover = schema.cover;
    if (rule && rule.coverSelector){
      var ruleCoverImage = airaNovelQOne(document, rule.coverSelector);
      if (ruleCoverImage){
        var ruleCoverSource = airaNovelClean(ruleCoverImage.getAttribute('data-src') ||
          ruleCoverImage.getAttribute('data-original') || ruleCoverImage.getAttribute('src') || '');
        var ruleCover = ruleCoverSource ? airaNovelSchemaImage(ruleCoverSource, location.href) : '';
        if (ruleCover){ cover = ruleCover; }
      }
    }
    var metaCover = airaNovelMetaProperty(document, 'og:image');
    if (!cover && metaCover){ cover = airaNovelAbs(metaCover, location.href); }
    if (!cover){
      var coverSelectors = [];
      coverSelectors.push('#fmimg img', '#sidebar img', '.book-cover img', '.novel-cover img',
        '.cover img', '[itemprop="image"]', '[class*="book_cov"] img', '[class*="book-info"] img',
        '[class*="book_info"] img', 'img[class*="book-cover"]', '[class*="book-cover"] img',
        '[class*="book"] img', '[class*="novel"][class*="info"] img',
        '[class*="novel"][class*="cover"] img');
      var image = airaNovelFirstElement(document, coverSelectors);
      if (image){
        cover = airaNovelAbs(image.getAttribute('data-src') || image.getAttribute('data-original') ||
          image.getAttribute('src') || '', location.href);
      }
    }
    var ruleSynopsisElement = rule && rule.synopsisSelector
      ? airaNovelFirstNonEmptyTextElement(document, [rule.synopsisSelector]) : null;
    var synopsisSource = schema.synopsis || (ruleSynopsisElement
      ? airaNovelClean(ruleSynopsisElement.textContent) : evidence.synopsis);
    var synopsis = airaNovelStripFieldLabel(synopsisSource, ['内容简介', '作品简介', '小说简介', '简介']);
    if (!synopsis){ synopsis = airaNovelMetaName(document, 'description'); }
    var ruleAuthorElement = rule && rule.authorSelector
      ? airaNovelFirstNonEmptyTextElement(document, [rule.authorSelector]) : null;
    var authorSource = schema.author ||
      (ruleAuthorElement ? airaNovelClean(ruleAuthorElement.textContent) : evidence.author);
    var author = airaNovelStripFieldLabel(authorSource, ['作者', '作家']);
    var categoryElement = airaNovelFirstElement(document,
      ['[itemprop="genre"]', '.book-category', '.novel-category', '.category']);
    var category = schema.category || airaNovelMetaProperty(document, 'og:novel:category') ||
      (categoryElement ? airaNovelClean(categoryElement.textContent) : '');
    if (!category){ category = airaNovelFindLabeledValue(document, ['作品分类', '小说分类', '类别', '分类']); }
    category = airaNovelStripFieldLabel(category, ['作品分类', '小说分类', '类别', '分类']);
    var latest = schema.latest || airaNovelMetaProperty(document, 'og:novel:latest_chapter_name');
    if (!latest && entries.length > 0){ latest = entries[entries.length - 1].title; }
    var catalogUrl = airaNovelFindPreferredCatalogPage(document, location.href);
    var startChapterUrl = evidence.readingActionUrl || airaNovelFindLink(document, location.href,
      ['开始阅读', '立即阅读', '在线阅读']);
    if (!catalogUrl && evidence.hasCatalogLink){ catalogUrl = location.href; }
    if (!airaNovelRuleUrlAllowed(rule, catalogUrl, location.href)){ catalogUrl = ''; }
    if (!airaNovelRuleUrlAllowed(rule, startChapterUrl, location.href)){ startChapterUrl = ''; }
    if (startChapterUrl && catalogUrl && startChapterUrl === catalogUrl){ startChapterUrl = ''; }
    if (!startChapterUrl && entries.length > 0){ startChapterUrl = entries[0].url; }
    var catalogSourceComplete = !!(rule && rule.catalogIncomplete === false && entries.length >= 5);
    var meta = {
      contentKind: schema.kind === 'comic' || (rule && rule.kind === 'comic') ? 'comic' : 'novel',
      title: title,
      author: author,
      category: category,
      latest: latest,
      cover: cover,
      synopsis: synopsis,
      host: location.hostname,
      catalogUrl: catalogUrl,
      startChapterUrl: startChapterUrl,
      catalogSourceComplete: catalogSourceComplete,
      catalogTotal: entries.length,
      initialEntries: entries.slice(0, ${NOVEL_BOOK_INITIAL_CATALOG_ENTRIES})
    };
    return JSON.stringify(meta);
  } catch (e){
    try { delete window.${NOVEL_DETECTION_GLOBAL}; } catch (cleanupError){ }
    return JSON.stringify({ initialEntries: [], catalogTotal: 0 });
  }
})();`;
    const raw: string = await controller.runJavaScript(script);
    const overview: NovelBookOverview = this.parseBookOverview(raw);
    if (overview.startChapterUrl.length === 0 && overview.initialEntries.length === 0 &&
      overview.catalogUrl.length > 0) {
      try {
        const catalog: NovelCatalogResult = await this.fetchCatalog(
          controller,
          overview.catalogUrl,
          NOVEL_BOOK_INITIAL_CATALOG_ENTRIES
        );
        if (catalog.entries.length > 0) {
          overview.initialEntries = catalog.entries.slice(0, NOVEL_BOOK_INITIAL_CATALOG_ENTRIES);
          overview.startChapterUrl = overview.initialEntries[0].url;
          overview.catalogTotal = Math.max(overview.catalogTotal, catalog.entries.length);
          overview.catalogSourceComplete = catalog.complete;
          if (overview.title.length === 0) {
            overview.title = catalog.bookTitle;
          }
          if (overview.author.length === 0) {
            overview.author = catalog.author;
          }
          if (overview.cover.length === 0) {
            overview.cover = catalog.coverUrl;
          }
          if (overview.latest.length === 0) {
            overview.latest = catalog.entries[catalog.entries.length - 1].title;
          }
        }
      } catch (_error) {
        // Keep the structured overview available; the reader can retry catalog acquisition.
      }
    }
    if (pageRule?.catalogPageSource !== undefined) {
      try {
        overview.catalogPageCursor = await this.catalogPageAcquisitionEngine.resolveInitialCursor(
          controller,
          pageUrl,
          pageRule.id,
          pageRule.catalogPageSource
        );
      } catch (_error) {
        overview.catalogPageCursor = undefined;
      }
    }
    hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
      'bookOverview initial=%{public}d total=%{public}d completeSource=%{public}s',
      overview.initialEntries.length, overview.catalogTotal, overview.catalogSourceComplete ? 'true' : 'false');
    return overview;
  }

  /** 抓某一章(后台 fetch,不导航);自动沿"下一页"把同章多页合并成完整一章。 */
  async fetchChapter(
    controller: webview.WebviewController,
    url: string,
    contentKind: NovelContentKind = 'novel'
  ): Promise<NovelChapterExtract> {
    const siteRule: NovelSiteRule | undefined = this.ruleCatalog.resolveRule(url);
    if (siteRule?.chapterSource !== undefined) {
      const acquired: NovelChapterExtract | undefined = await this.chapterAcquisitionEngine.acquire(
        controller,
        url,
        siteRule.chapterSource
      );
      return acquired ?? this.emptyChapter();
    }
    if (siteRule?.comicChapterSource !== undefined) {
      const acquired: NovelChapterExtract | undefined = await this.comicChapterAcquisitionEngine.acquire(
        controller,
        url,
        siteRule.comicChapterSource
      );
      return acquired ?? this.emptyChapter();
    }
    if (contentKind === 'comic') {
      const acquired: NovelChapterExtract | undefined =
        await this.comicChapterAcquisitionEngine.acquireRenderedPage(controller, url);
      if (acquired !== undefined) {
        return acquired;
      }
    }
    const chapterGlobalName: string = this.nextChapterGlobalName();
    const trigger: string = this.ruleHeader(url) + this.runtimeHelpers() + `
(function(){
  var requestState = { status: 'pending', cancelled: false };
  window.${chapterGlobalName} = requestState;
  var target = ${JSON.stringify(url)};
  var first = null;
  var all = [];
  var guard = 0;
  function publish(payload){
    if (requestState.cancelled || window.${chapterGlobalName} !== requestState){ return false; }
    window.${chapterGlobalName} = payload;
    return true;
  }
  function step(u){
    if (!u || guard >= 12){ finish(); return; }
    guard++;
    airaNovelLoadDoc(u).then(function(result){
      if (requestState.cancelled || window.${chapterGlobalName} !== requestState){ return; }
      var pageUrl = result.url || u;
      if (!airaNovelRuleUrlAllowed(airaNovelRule(), pageUrl, target)){
        publish({ status: 'error', message: 'remote-rule-url-outside-scope' });
        return;
      }
      var ch = airaNovelExtractChapter(result.doc, pageUrl);
      if (!first){ first = ch; }
      for (var i = 0; i < ch.paragraphs.length; i++){ all.push(ch.paragraphs[i]); }
      if (ch.nextUrl){ first.nextUrl = ch.nextUrl; }   // 以最后一页的"下一章"为准
      if (ch.nextPageUrl && ch.nextPageUrl !== pageUrl){ step(ch.nextPageUrl); } else { finish(); }
    }).catch(function(err){
      if (first){ finish(); }
      else { publish({ status: 'error', message: String(err) }); }
    });
  }
  function finish(){
    if (!first){ publish({ status: 'error', message: 'empty' }); return; }
    first.paragraphs = all;
    publish({ status: 'done', data: first });
  }
  step(target);
  return 'ok';
})();`;
    await controller.runJavaScript(trigger);
    try {
      const raw: string = await this.pollGlobal(controller, chapterGlobalName);
      const chapter: NovelChapterExtract = this.parseFetchEnvelope(raw);
      if (!this.chapterAcquisitionEngine.shouldRetryWithDirectHtml(chapter)) {
        return chapter;
      }
      const directHtmlChapter: NovelChapterExtract | undefined =
        await this.chapterAcquisitionEngine.acquireDirectHtmlFallback(
          controller,
          url,
          siteRule?.requiresContentQualityGate === true ? '' : siteRule?.contentSelector ?? '',
          siteRule?.requiresContentQualityGate === true ? '' : siteRule?.chapterTitleSelector ?? ''
        );
      return directHtmlChapter ?? chapter;
    } finally {
      await this.clearPageGlobal(controller, chapterGlobalName);
    }
  }

  async fetchCatalogPage(
    _controller: webview.WebviewController,
    catalogUrl: string,
    cursor: NovelCatalogPageCursor
  ): Promise<NovelCatalogPageResult | undefined> {
    const rule: NovelSiteRule | undefined = this.ruleCatalog.resolveRule(catalogUrl);
    if (rule === undefined || rule.id !== cursor.ruleId || rule.catalogPageSource === undefined) {
      return undefined;
    }
    return this.catalogPageAcquisitionEngine.acquire(
      catalogUrl,
      cursor,
      rule.id,
      rule.catalogPageSource
    );
  }

  /** 抓一个有界目录窗口；正文获取从不进入此流程。 */
  async fetchCatalog(
    controller: webview.WebviewController,
    url: string,
    maximumEntries: number = NOVEL_BOOK_INITIAL_CATALOG_ENTRIES
  ): Promise<NovelCatalogResult> {
    const requestedMaximum: number = Math.max(
      NOVEL_BOOK_INITIAL_CATALOG_ENTRIES,
      Math.min(8000, Math.floor(maximumEntries))
    );
    const siteRule: NovelSiteRule | undefined = this.ruleCatalog.resolveRule(url);
    if (siteRule?.comicBookSource !== undefined &&
      this.comicBookOverviewAcquisitionEngine.supportsBookPage(url, siteRule.comicBookSource)) {
      const acquired: NovelCatalogResult | undefined =
        await this.comicBookOverviewAcquisitionEngine.acquireCatalog(
          url,
          siteRule.comicBookSource,
          requestedMaximum
        );
      if (acquired !== undefined) {
        hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
          'fetchCatalog source=comic_book_api entries=%{public}d complete=%{public}s',
          acquired.entries.length, acquired.complete ? 'true' : 'false');
        return acquired;
      }
    }
    const maximumPages: number = Math.max(2, Math.min(200, Math.ceil(requestedMaximum / 5)));
    const catalogGlobalName: string = this.nextCatalogGlobalName();
    const trigger: string = this.ruleHeader(url) + this.runtimeHelpers() + `
(function(){
  var requestState = { status: 'pending', cancelled: false };
  window.${catalogGlobalName} = requestState;
  var target = ${JSON.stringify(url)};
  var firstDoc = null;
  var firstDocUrl = '';
  var entries = [];
  var indexByUrl = {};
  var fallbackEntries = [];
  var fallbackIndexByUrl = {};
  var visitedPages = {};
  var pageCount = 0;
  var maxPages = ${maximumPages};
  var maxEntries = ${requestedMaximum};
  var interactiveAttempted = false;
  var activeCatalogRoot = target;
  var activeCatalogFirstDoc = null;
  var activeCatalogPageCount = 0;
  function requestActive(){
    return !requestState.cancelled && window.${catalogGlobalName} === requestState;
  }
  function publish(payload){
    if (!requestActive()){ return false; }
    window.${catalogGlobalName} = payload;
    return true;
  }
  function readMetaContent(doc, propertyName){
    var m = doc.querySelector('meta[property="' + propertyName + '"]');
    return m ? airaNovelClean(m.getAttribute('content')) : '';
  }
  function finish(catalogComplete){
    if (!firstDoc){
      publish({ status: 'error', message: 'empty' });
      return;
    }
    if (entries.length === 0 && fallbackEntries.length > 0){
      airaNovelMergeCatalogEntries(entries, indexByUrl, fallbackEntries, maxEntries);
    }
    var schema = airaNovelReadBookSchema(firstDoc, firstDocUrl || target);
    var bookEvidence = airaNovelBookEvidence(firstDoc, entries, firstDocUrl || target);
    var cover = schema.cover || airaNovelAbs(readMetaContent(firstDoc, 'og:image'), firstDocUrl || target);
    if (!cover){
      var im = firstDoc.querySelector('#fmimg img') || firstDoc.querySelector('.cover img');
      if (im){ cover = airaNovelAbs(im.getAttribute('src') || '', firstDocUrl || target); }
    }
    publish({
      status: 'done',
      bookTitle: bookEvidence.title,
      author: schema.author || readMetaContent(firstDoc, 'og:novel:author'),
      coverUrl: cover,
      complete: catalogComplete !== false && entries.length < maxEntries,
      entries: airaNovelSortMergedCatalog(entries)
    });
  }
  function canFetchCatalogPage(pageUrl){
    return requestActive() && !!pageUrl && !visitedPages[pageUrl] && pageCount < maxPages &&
      entries.length < maxEntries && airaNovelRuleUrlAllowed(airaNovelRule(), pageUrl, target);
  }
  function collectInteractiveCatalog(pageUrl){
    return new Promise(function(resolve){
      var parsedTarget = null;
      try { parsedTarget = new URL(pageUrl, location.href); } catch (e){
        resolve({ entries: [], complete: false }); return;
      }
      if (!parsedTarget || parsedTarget.origin !== location.origin ||
        !airaNovelRuleUrlAllowed(airaNovelRule(), parsedTarget.href, target)){
        resolve({ entries: [], complete: false }); return;
      }
      var frame = document.createElement('iframe');
      frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
      frame.setAttribute('aria-hidden', 'true');
      frame.style.position = 'fixed';
      frame.style.left = '-10000px';
      frame.style.top = '0';
      frame.style.width = Math.max(360, Math.min(1600, window.innerWidth || 1024)) + 'px';
      frame.style.height = Math.max(640, Math.min(1200, window.innerHeight || 768)) + 'px';
      frame.style.opacity = '0';
      frame.style.pointerEvents = 'none';
      var collected = [];
      var collectedIndex = {};
      var fingerprints = {};
      var interactivePageCount = 0;
      var expectedPageTotal = 0;
      var settled = false;
      var started = false;
      var catalogRevealAttempted = false;
      var deadline = Date.now() + 45000;
      function removeFrame(){
        try { if (frame.parentNode){ frame.parentNode.removeChild(frame); } } catch (e){ }
      }
      function complete(catalogComplete){
        if (settled){ return; }
        settled = true;
        removeFrame();
        resolve({ entries: collected, complete: catalogComplete !== false });
      }
      function readFrame(){
        try {
          var frameDoc = frame.contentDocument;
          var frameUrl = frame.contentWindow && frame.contentWindow.location ? frame.contentWindow.location.href : pageUrl;
          if (!frameDoc || !airaNovelRuleUrlAllowed(airaNovelRule(), frameUrl, target)){ return null; }
          return { doc: frameDoc, url: frameUrl, entries: airaNovelExtractCatalog(frameDoc, frameUrl) };
        } catch (e){ return null; }
      }
      function waitForChangedPage(beforeFingerprint, waitStartedAt, candidateFingerprint, candidateSince){
        if (settled){ return; }
        if (!requestActive()){ complete(false); return; }
        var state = readFrame();
        if (state && state.entries.length >= 3 && airaNovelCatalogPageReady(state.doc)){
          var nextFingerprint = airaNovelCatalogFingerprint(state.entries);
          if (nextFingerprint && nextFingerprint !== beforeFingerprint){
            if (nextFingerprint === candidateFingerprint && Date.now() - candidateSince >= 300){
              collectPage(state);
              return;
            }
            if (nextFingerprint !== candidateFingerprint){
              candidateFingerprint = nextFingerprint;
              candidateSince = Date.now();
            }
          }
        }
        if (Date.now() >= deadline || Date.now() - waitStartedAt >= 12000){ complete(false); return; }
        setTimeout(function(){
          waitForChangedPage(beforeFingerprint, waitStartedAt, candidateFingerprint, candidateSince);
        }, 80);
      }
      function collectPage(state){
        if (settled || !state || state.entries.length < 3){ complete(false); return; }
        var fingerprint = airaNovelCatalogFingerprint(state.entries);
        var progress = airaNovelCatalogPageProgress(state.doc, state.entries, state.url);
        if (progress.total > expectedPageTotal){ expectedPageTotal = progress.total; }
        if (!fingerprint){ complete(false); return; }
        if (fingerprints[fingerprint]){
          complete(expectedPageTotal <= 0 || (progress.current > 0 && progress.current >= expectedPageTotal));
          return;
        }
        fingerprints[fingerprint] = true;
        interactivePageCount++;
        airaNovelMergeCatalogEntries(collected, collectedIndex, state.entries, maxEntries);
        if (interactivePageCount >= maxPages || collected.length >= maxEntries || Date.now() >= deadline){
          complete(expectedPageTotal > 0 && progress.current >= expectedPageTotal);
          return;
        }
        var control = airaNovelFindNextCatalogControl(state.doc, true, state.entries, state.url);
        if (!control || airaNovelCatalogControlDisabled(control)){
          complete(expectedPageTotal <= 0 || (progress.current > 0 && progress.current >= expectedPageTotal));
          return;
        }
        try {
          if (typeof control.click === 'function'){ control.click(); }
          else {
            var event = state.doc.createEvent('MouseEvents');
            event.initEvent('click', true, true);
            control.dispatchEvent(event);
          }
        } catch (e){ complete(false); return; }
        waitForChangedPage(fingerprint, Date.now(), '', 0);
      }
      function waitForReady(readyStartedAt, candidateFingerprint, candidateSince){
        if (settled){ return; }
        if (!requestActive()){ complete(false); return; }
        var state = readFrame();
        if (state && !catalogRevealAttempted && Date.now() - readyStartedAt >= 900){
          var revealControl = airaNovelFindCatalogRevealControl(state.doc);
          var revealScore = revealControl
            ? airaNovelCatalogRevealScore(airaNovelCatalogControlText(revealControl)) : 0;
          if (revealControl && (state.entries.length < 3 || revealScore >= 110)){
            catalogRevealAttempted = true;
            try {
              if (typeof revealControl.click === 'function'){ revealControl.click(); }
              else {
                var revealEvent = state.doc.createEvent('MouseEvents');
                revealEvent.initEvent('click', true, true);
                revealControl.dispatchEvent(revealEvent);
              }
            } catch (e){ complete(false); return; }
          }
        }
        if (state && state.entries.length >= 3 && airaNovelCatalogPageReady(state.doc)){
          var fingerprint = airaNovelCatalogFingerprint(state.entries);
          if (fingerprint === candidateFingerprint && Date.now() - candidateSince >= 350 &&
            Date.now() - readyStartedAt >= 900){
            var control = airaNovelFindNextCatalogControl(state.doc, true, state.entries, state.url);
            if (control){ collectPage(state); return; }
            if (Date.now() - readyStartedAt >= 3000){
              collectPage(state);
              return;
            }
          } else if (fingerprint !== candidateFingerprint){
            candidateFingerprint = fingerprint;
            candidateSince = Date.now();
          }
        }
        if (Date.now() >= deadline){ complete(false); return; }
        setTimeout(function(){ waitForReady(readyStartedAt, candidateFingerprint, candidateSince); }, 80);
      }
      frame.addEventListener('load', function(){
        if (started){ return; }
        started = true;
        waitForReady(Date.now(), '', 0);
      });
      var host = document.body || document.documentElement;
      if (!host){ resolve({ entries: [], complete: false }); return; }
      frame.src = parsedTarget.href;
      host.appendChild(frame);
      setTimeout(function(){ if (!started){ complete(false); } }, 6000);
    });
  }
  function finishAfterPagination(staticTraversalComplete){
    if (!requestActive()){ return; }
    if (interactiveAttempted || activeCatalogPageCount !== 1 || !activeCatalogFirstDoc ||
      airaNovelFindNextCatalogPage(activeCatalogFirstDoc, activeCatalogRoot, activeCatalogRoot)){
      finish(staticTraversalComplete);
      return;
    }
    interactiveAttempted = true;
    function runInteractive(attempt){
      collectInteractiveCatalog(activeCatalogRoot).then(function(result){
        if (result.entries.length > 0){
          entries = [];
          indexByUrl = {};
          airaNovelMergeCatalogEntries(entries, indexByUrl, result.entries, maxEntries);
          finish(result.complete);
          return;
        }
        if (!result.complete && attempt < 2 && requestActive()){
          runInteractive(attempt + 1);
          return;
        }
        finish(result.complete);
      }).catch(function(){
        if (attempt < 2 && requestActive()){ runInteractive(attempt + 1); }
        else { finish(false); }
      });
    }
    runInteractive(1);
  }
  function acceptCatalogDocument(doc, pageUrl, catalogRootUrl, allowFullCatalogPromotion){
    if (!requestActive()){ return; }
    if (!airaNovelRuleUrlAllowed(airaNovelRule(), pageUrl, target)){
      finishAfterPagination(false);
      return;
    }
    if (!firstDoc){ firstDoc = doc; firstDocUrl = pageUrl; }
    if (!activeCatalogFirstDoc){ activeCatalogFirstDoc = doc; }
    activeCatalogPageCount++;
    var pageEntries = airaNovelExtractCatalog(doc, pageUrl);
    if (allowFullCatalogPromotion){
      var fullCatalogPage = airaNovelFindFullCatalogPage(doc, pageUrl);
      if (fullCatalogPage){
        if (canFetchCatalogPage(fullCatalogPage)){
          airaNovelMergeCatalogEntries(fallbackEntries, fallbackIndexByUrl, pageEntries, maxEntries);
          activeCatalogRoot = fullCatalogPage;
          activeCatalogFirstDoc = null;
          activeCatalogPageCount = 0;
          fetchCatalogPage(fullCatalogPage, fullCatalogPage, false);
        } else {
          airaNovelMergeCatalogEntries(entries, indexByUrl, pageEntries, maxEntries);
          finishAfterPagination(false);
        }
        return;
      }
    }
    airaNovelMergeCatalogEntries(entries, indexByUrl, pageEntries, maxEntries);
    var nextPage = airaNovelFindNextCatalogPage(doc, pageUrl, catalogRootUrl);
    if (nextPage){
      if (canFetchCatalogPage(nextPage)){ fetchCatalogPage(nextPage, catalogRootUrl, false); }
      else { finishAfterPagination(false); }
    } else {
      finishAfterPagination(true);
    }
  }
  function fetchCatalogPage(pageUrl, catalogRootUrl, allowFullCatalogPromotion){
    if (!requestActive()){ return; }
    if (!canFetchCatalogPage(pageUrl)){
      finishAfterPagination(false);
      return;
    }
    visitedPages[pageUrl] = true;
    pageCount++;
    airaNovelLoadDoc(pageUrl).then(function(result){
      if (!requestActive()){ return; }
      var resolvedPageUrl = result.url || pageUrl;
      if (!airaNovelRuleUrlAllowed(airaNovelRule(), resolvedPageUrl, target)){
        if (firstDoc){ finishAfterPagination(false); }
        else { publish({ status: 'error', message: 'remote-rule-url-outside-scope' }); }
        return;
      }
      visitedPages[resolvedPageUrl] = true;
      var resolvedCatalogRootUrl = catalogRootUrl;
      if (pageUrl === catalogRootUrl && resolvedPageUrl !== pageUrl){
        resolvedCatalogRootUrl = resolvedPageUrl;
      }
      if (activeCatalogPageCount === 0 && pageUrl === activeCatalogRoot){
        activeCatalogRoot = resolvedPageUrl;
      }
      acceptCatalogDocument(result.doc, resolvedPageUrl, resolvedCatalogRootUrl, allowFullCatalogPromotion);
    }).catch(function(err){
      if (!requestActive()){ return; }
      if (firstDoc){ finishAfterPagination(false); }
      else { publish({ status: 'error', message: String(err) }); }
    });
  }
  setTimeout(function(){
    if (requestActive()){ finish(false); }
  }, 95000);
  var targetLocation = null;
  try { targetLocation = new URL(target, location.href); } catch (e){ targetLocation = null; }
  if (targetLocation && targetLocation.origin === location.origin &&
    targetLocation.pathname === location.pathname && targetLocation.search === location.search){
    var currentDocumentUrl = location.href;
    visitedPages[currentDocumentUrl] = true;
    pageCount++;
    activeCatalogRoot = currentDocumentUrl;
    acceptCatalogDocument(document, currentDocumentUrl, currentDocumentUrl, true);
  } else {
    fetchCatalogPage(target, target, true);
  }
  return 'ok';
})();`;
    await controller.runJavaScript(trigger);
    try {
      const raw: string = await this.pollGlobal(
        controller,
        catalogGlobalName,
        true,
        NOVEL_CATALOG_POLL_MAX_TIMES
      );
      hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'fetchCatalog url=%{public}s meta=%{public}s', url, raw);
      const result: NovelCatalogResult = this.parseCatalogEnvelope(raw);
      result.entries = await this.drainEntries(controller, catalogGlobalName);
      return result;
    } finally {
      await this.clearPageGlobal(controller, catalogGlobalName);
    }
  }

  private nextCatalogGlobalName(): string {
    this.catalogRequestSequence = this.catalogRequestSequence + 1;
    return NOVEL_CATALOG_GLOBAL + '_' + Date.now().toString() + '_' + this.catalogRequestSequence.toString();
  }

  private nextChapterGlobalName(): string {
    this.chapterRequestSequence = this.chapterRequestSequence + 1;
    return NOVEL_FETCH_GLOBAL + '_' + Date.now().toString() + '_' + this.chapterRequestSequence.toString();
  }

  private async clearPageGlobal(controller: webview.WebviewController, globalName: string): Promise<void> {
    try {
      await controller.runJavaScript(`
(function(){
  try {
    var state = window[${JSON.stringify(globalName)}];
    if (state && typeof state === 'object'){ state.cancelled = true; }
    delete window[${JSON.stringify(globalName)}];
  } catch (e){ }
})();`);
    } catch (_error) {
      // 页面已经销毁时无需清理。
    }
  }

  private async pollGlobal(
    controller: webview.WebviewController,
    globalName: string,
    metaOnly: boolean = false,
    maxTimes: number = NOVEL_POLL_MAX_TIMES
  ): Promise<string> {
    const pollScript: string = metaOnly ? `
(function(){
  if (!Object.prototype.hasOwnProperty.call(window, ${JSON.stringify(globalName)})){
    return ${JSON.stringify(NOVEL_REQUEST_MISSING)};
  }
  var s = window.${globalName};
  if (s.status === 'pending'){ return ''; }
  return JSON.stringify({ status: s.status, message: s.message, bookTitle: s.bookTitle,
    author: s.author, coverUrl: s.coverUrl, complete: s.complete,
    total: (s.entries ? s.entries.length : 0) });
})();` : `
(function(){
  if (!Object.prototype.hasOwnProperty.call(window, ${JSON.stringify(globalName)})){
    return ${JSON.stringify(NOVEL_REQUEST_MISSING)};
  }
  var s = window.${globalName};
  if (s.status === 'pending'){ return ''; }
  return JSON.stringify(s);
})();`;
    for (let i = 0; i < maxTimes; i++) {
      const raw: string = await controller.runJavaScript(pollScript);
      const normalized: string = this.normalizeRawScriptResult(raw);
      if (normalized === NOVEL_REQUEST_MISSING) {
        throw new Error('novel page request no longer exists');
      }
      if (normalized.length > 0 && normalized !== 'null') {
        return normalized;
      }
      await this.delay(NOVEL_POLL_INTERVAL_MS);
    }
    return '';
  }

  /**
   * 分块把 window 上暂存的目录取回。
   * runJavaScript 的返回值有大小上限,长书目录一次性传会被截断
   * (这也是现成阅读模式抽正文时按块传的原因)。
   */
  private async drainEntries(controller: webview.WebviewController, globalName: string): Promise<NovelCatalogEntry[]> {
    const entries: NovelCatalogEntry[] = [];
    let offset: number = 0;
    for (let guard = 0; guard < 200; guard++) {
      const chunkScript: string = `
(function(){
  var s = window.${globalName};
  var list = (s && s.entries) ? s.entries : [];
  if (${offset} >= list.length){ return '[]'; }
  return JSON.stringify(list.slice(${offset}, ${offset} + ${NOVEL_CATALOG_CHUNK}));
})();`;
      const raw: string = await controller.runJavaScript(chunkScript);
      const chunk: NovelCatalogEntry[] = this.parseEntryChunk(raw, offset);
      hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
        'drain %{public}s offset=%{public}d rawLen=%{public}d chunk=%{public}d',
        globalName, offset, raw.length, chunk.length);
      if (chunk.length === 0) {
        break;
      }
      for (let i = 0; i < chunk.length; i++) {
        entries.push(chunk[i]);
      }
      offset = offset + NOVEL_CATALOG_CHUNK;
    }
    hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'drain done %{public}s total=%{public}d', globalName, entries.length);
    return entries;
  }

  private parseEntryChunk(raw: string, ordinalOffset: number): NovelCatalogEntry[] {
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(raw)) as NovelRawCatalogEntry[];
      return this.buildEntries(parsed, ordinalOffset);
    } catch (_error) {
      return [];
    }
  }

  private parseChapter(raw: string): NovelChapterExtract {
    try {
      return this.buildChapter(JSON.parse(this.normalizeRawScriptResult(raw)) as NovelRawChapter);
    } catch (_error) {
      return this.emptyChapter();
    }
  }

  private parseFetchEnvelope(raw: string): NovelChapterExtract {
    if (raw.length === 0) {
      return this.emptyChapter();
    }
    try {
      const parsed = JSON.parse(raw) as NovelRawFetchEnvelope;
      if (parsed.status === 'done' && parsed.data !== undefined) {
        return this.buildChapter(parsed.data);
      }
      return this.emptyChapter();
    } catch (_error) {
      return this.emptyChapter();
    }
  }

  private parseCatalogEnvelope(raw: string): NovelCatalogResult {
    const empty: NovelCatalogResult = {
      bookTitle: '', author: '', coverUrl: '', complete: false, entries: []
    };
    if (raw.length === 0) {
      return empty;
    }
    try {
      const parsed = JSON.parse(raw) as NovelRawCatalogEnvelope;
      return {
        bookTitle: this.normalizeText(parsed.bookTitle),
        author: this.normalizeText(parsed.author),
        coverUrl: this.normalizeText(parsed.coverUrl),
        complete: parsed.status === 'done' && parsed.complete !== false,
        entries: this.buildEntries(parsed.entries)
      };
    } catch (_error) {
      return empty;
    }
  }

  private parseBookOverview(raw: string): NovelBookOverview {
    const empty: NovelBookOverview = {
      contentKind: 'novel',
      title: '', author: '', category: '', latest: '', cover: '', synopsis: '', host: '',
      catalogUrl: '', startChapterUrl: '', catalogSourceComplete: false, catalogTotal: 0,
      initialEntries: []
    };
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(raw)) as NovelRawBookOverview;
      return {
        contentKind: parsed.contentKind === 'comic' ? 'comic' : 'novel',
        title: this.normalizeText(parsed.title),
        author: this.normalizeText(parsed.author),
        category: this.normalizeText(parsed.category),
        latest: this.normalizeText(parsed.latest),
        cover: this.normalizeText(parsed.cover),
        synopsis: this.normalizeText(parsed.synopsis),
        host: this.normalizeText(parsed.host),
        catalogUrl: this.normalizeText(parsed.catalogUrl),
        startChapterUrl: this.normalizeText(parsed.startChapterUrl),
        catalogSourceComplete: parsed.catalogSourceComplete === true,
        catalogTotal: Math.max(0, Math.floor(Number.isFinite(parsed.catalogTotal) ? Number(parsed.catalogTotal) : 0)),
        initialEntries: this.buildEntries(parsed.initialEntries)
      };
    } catch (_error) {
      return empty;
    }
  }

  private buildEntries(
    raw: NovelRawCatalogEntry[] | undefined,
    ordinalOffset: number = 0
  ): NovelCatalogEntry[] {
    const entries: NovelCatalogEntry[] = [];
    if (!Array.isArray(raw)) {
      return entries;
    }
    for (let i = 0; i < raw.length; i++) {
      const title: string = this.normalizeText(raw[i].title);
      const url: string = this.normalizeText(raw[i].url);
      if (title.length > 0 && url.length > 0) {
        const rawOrdinal: number = Number(raw[i].ordinal);
        const ordinal: number = Number.isFinite(rawOrdinal) && rawOrdinal >= 0
          ? Math.floor(rawOrdinal)
          : ordinalOffset + i;
        entries.push({ ordinal: ordinal, title: title, url: url });
      }
    }
    return entries;
  }

  private buildChapter(raw: NovelRawChapter): NovelChapterExtract {
    const paragraphs: string[] = [];
    if (Array.isArray(raw.paragraphs)) {
      for (let i = 0; i < raw.paragraphs.length; i++) {
        const text: string = this.normalizeText(raw.paragraphs[i]);
        if (text.length > 0) {
          paragraphs.push(text);
        }
      }
    }
    const images: string[] = [];
    if (Array.isArray(raw.images)) {
      for (let i = 0; i < raw.images.length; i++) {
        const url: string = this.normalizeText(raw.images[i]);
        if (url.length > 0) {
          images.push(url);
        }
      }
    }
    const total: number = raw.pageTotal === undefined ? 1 : raw.pageTotal;
    return {
      pageUrl: this.normalizeText(raw.pageUrl),
      title: this.normalizeText(raw.title),
      paragraphs: paragraphs,
      images: images,
      prevUrl: this.normalizeText(raw.prevUrl),
      nextUrl: this.normalizeText(raw.nextUrl),
      catalogUrl: this.normalizeText(raw.catalogUrl),
      bookTitle: this.normalizeText(raw.bookTitle),
      pageTotal: total > 0 ? total : 1,
      nextPageUrl: this.normalizeText(raw.nextPageUrl)
    };
  }

  private emptyChapter(): NovelChapterExtract {
    return {
      pageUrl: '', title: '', paragraphs: [], images: [], prevUrl: '', nextUrl: '',
      catalogUrl: '', bookTitle: '', pageTotal: 1, nextPageUrl: ''
    };
  }

  private normalizeText(value: string | undefined): string {
    return (value === undefined || value === null) ? '' : String(value).trim();
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private normalizeRawScriptResult(rawResult: string): string {
    const trimmed: string = rawResult.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        const parsed = JSON.parse(trimmed) as string;
        return typeof parsed === 'string' ? parsed.trim() : trimmed;
      } catch (_error) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }
}
