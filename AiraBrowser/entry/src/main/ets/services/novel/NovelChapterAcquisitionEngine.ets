import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { NovelChapterExtract } from '../../features/novel/NovelReaderModels';
import { NovelChapterSourceRule } from '../../features/novel/NovelSiteRules';

const NOVEL_SOURCE_CONNECT_TIMEOUT_MS: number = 10000;
const NOVEL_SOURCE_READ_TIMEOUT_MS: number = 15000;
const NOVEL_SOURCE_MAX_BYTES: number = 4 * 1024 * 1024;
const NOVEL_SOURCE_MIN_CONTENT_CHARS: number = 8;

interface NovelChapterSourceMetadataRaw {
  status?: string;
  title?: string;
  bookTitle?: string;
  prevUrl?: string;
  nextUrl?: string;
  catalogUrl?: string;
  resourceHost?: string;
  resourceKey?: string;
  resourceLength?: string;
}

interface NovelChapterSourceMetadata {
  title: string;
  bookTitle: string;
  prevUrl: string;
  nextUrl: string;
  catalogUrl: string;
  resourceHost: string;
  resourceKey: string;
  resourceLength: string;
}

interface NovelNormalizedPayloadRaw {
  title?: string;
  paragraphs?: string[];
}

interface NovelDirectHtmlPageRaw {
  title?: string;
  paragraphs?: string[];
  prevUrl?: string;
  nextUrl?: string;
  nextPageUrl?: string;
  catalogUrl?: string;
  bookTitle?: string;
  chapterId?: string;
}

interface NovelDirectHtmlPage {
  title: string;
  paragraphs: string[];
  prevUrl: string;
  nextUrl: string;
  nextPageUrl: string;
  catalogUrl: string;
  bookTitle: string;
  chapterId: string;
}

interface NovelDirectHtmlFallbackRule {
  contentSelector: string;
  titleSelector: string;
}

/**
 * 小说章节来源获取引擎。
 *
 * NovelExtractionService 仍是对外 owner;本模块只隐藏不同来源策略的获取、解码与质量校验。
 * 站点差异必须由 NovelChapterSourceRule 描述,禁止执行下载来的任意第三方 JavaScript。
 */
export class NovelChapterAcquisitionEngine {
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  async acquire(
    controller: webview.WebviewController,
    chapterUrl: string,
    rule: NovelChapterSourceRule
  ): Promise<NovelChapterExtract | undefined> {
    try {
      if (rule.kind === 'encoded_script_payload') {
        return await this.acquireEncodedScriptPayload(controller, chapterUrl, rule);
      }
      return undefined;
    } catch (_error) {
      return undefined;
    }
  }

  shouldRetryWithDirectHtml(chapter: NovelChapterExtract): boolean {
    if (chapter.images.length > 0) {
      return false;
    }
    if (chapter.paragraphs.length === 0) {
      return true;
    }
    return this.isUnsupportedClientContent(chapter.paragraphs);
  }

  private isUnsupportedClientContent(paragraphs: string[]): boolean {
    let compact: string = '';
    for (let index: number = 0; index < paragraphs.length; index += 1) {
      compact += paragraphs[index].toLowerCase().replace(/\s+/g, '');
      if (compact.length > 400) {
        return false;
      }
    }
    const hasClientSubject: boolean = compact.indexOf('浏览器') >= 0 || compact.indexOf('客户端') >= 0 ||
      compact.indexOf('browser') >= 0 || compact.indexOf('client') >= 0;
    const hasUnsupportedState: boolean = compact.indexOf('停止支持') >= 0 || compact.indexOf('不支持') >= 0 ||
      compact.indexOf('unsupported') >= 0 || compact.indexOf('notsupported') >= 0 ||
      compact.indexOf('nolongersupported') >= 0;
    return hasClientSubject && hasUnsupportedState;
  }

  async acquireDirectHtmlFallback(
    controller: webview.WebviewController,
    chapterUrl: string,
    contentSelector: string,
    titleSelector: string
  ): Promise<NovelChapterExtract | undefined> {
    const sourceOrigin: string = this.extractHttpOrigin(chapterUrl);
    if (sourceOrigin.length === 0) {
      return undefined;
    }
    const rule: NovelDirectHtmlFallbackRule = {
      contentSelector: contentSelector,
      titleSelector: titleSelector
    };
    const seenUrls: string[] = [];
    const paragraphs: string[] = [];
    let firstPage: NovelDirectHtmlPage | undefined = undefined;
    let currentUrl: string = chapterUrl;
    let nextChapterUrl: string = '';
    let loadedPages: number = 0;
    while (currentUrl.length > 0 && loadedPages < 12 && seenUrls.indexOf(currentUrl) < 0) {
      seenUrls.push(currentUrl);
      const html: string = await this.fetchHtmlSource(currentUrl);
      if (html.length === 0) {
        return undefined;
      }
      const page: NovelDirectHtmlPage | undefined = await this.normalizeDirectHtmlPage(
        controller,
        html,
        currentUrl,
        rule
      );
      if (page === undefined || page.paragraphs.length === 0) {
        return undefined;
      }
      if (firstPage === undefined) {
        firstPage = page;
      } else if (page.chapterId.length > 0 && firstPage.chapterId.length > 0 &&
        page.chapterId !== firstPage.chapterId) {
        nextChapterUrl = currentUrl;
        break;
      } else if (page.title.length > 0 && firstPage.title.length > 0 && page.title !== firstPage.title) {
        nextChapterUrl = currentUrl;
        break;
      }
      for (let index: number = 0; index < page.paragraphs.length; index += 1) {
        paragraphs.push(page.paragraphs[index]);
      }
      loadedPages += 1;
      if (this.isSameOriginUrl(page.nextPageUrl, sourceOrigin)) {
        if (loadedPages >= 12) {
          return undefined;
        }
        currentUrl = page.nextPageUrl;
        continue;
      }
      if (this.isSameOriginUrl(page.nextUrl, sourceOrigin) &&
        this.isChapterContinuationUrl(page.nextUrl, page.chapterId, chapterUrl)) {
        if (loadedPages >= 12) {
          return undefined;
        }
        currentUrl = page.nextUrl;
        continue;
      }
      nextChapterUrl = this.isSameOriginUrl(page.nextUrl, sourceOrigin) ? page.nextUrl : '';
      break;
    }
    if (firstPage === undefined || !this.passesQualityGate(paragraphs)) {
      return undefined;
    }
    return {
      pageUrl: chapterUrl,
      title: firstPage.title,
      paragraphs: paragraphs,
      images: [],
      prevUrl: this.isSameOriginUrl(firstPage.prevUrl, sourceOrigin) ? firstPage.prevUrl : '',
      nextUrl: nextChapterUrl,
      catalogUrl: this.isSameOriginUrl(firstPage.catalogUrl, sourceOrigin) ? firstPage.catalogUrl : '',
      bookTitle: firstPage.bookTitle,
      pageTotal: loadedPages,
      nextPageUrl: ''
    };
  }

  private async fetchHtmlSource(url: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: NOVEL_SOURCE_CONNECT_TIMEOUT_MS,
        readTimeout: NOVEL_SOURCE_READ_TIMEOUT_MS,
        usingCache: false,
        maxLimit: NOVEL_SOURCE_MAX_BYTES,
        header: {
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer': this.stripFragment(url),
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 ' +
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return '';
      }
      const html: string = response.result;
      return html.length > 0 && html.length <= NOVEL_SOURCE_MAX_BYTES ? html : '';
    } finally {
      request.destroy();
    }
  }

  private async normalizeDirectHtmlPage(
    controller: webview.WebviewController,
    html: string,
    pageUrl: string,
    rule: NovelDirectHtmlFallbackRule
  ): Promise<NovelDirectHtmlPage | undefined> {
    const script: string = `
(function(){
  try {
    var source = ${JSON.stringify(html)};
    var recipe = ${JSON.stringify(rule)};
    var base = ${JSON.stringify(pageUrl)};
    var doc = new DOMParser().parseFromString(source, 'text/html');
    function clean(value){ return String(value || '').replace(/\\s+/g, ' ').trim(); }
    function absolute(value){
      try { return value ? new URL(value, base).href : ''; } catch (e){ return ''; }
    }
    function nodeToText(element){
      var output = [];
      function walk(node){
        var children = node.childNodes || [];
        for (var index = 0; index < children.length; index++){
          var child = children[index];
          if (child.nodeType === 3){ output.push(child.nodeValue || ''); }
          else if (child.nodeType === 1){
            var tag = String(child.tagName || '').toLowerCase();
            if (tag === 'br'){ output.push('\\n'); }
            else if (tag === 'script' || tag === 'style' || tag === 'a' || tag === 'ins' ||
              tag === 'button' || tag === 'h1' || tag === 'h2'){ }
            else if (tag === 'p' || tag === 'div'){ output.push('\\n'); walk(child); output.push('\\n'); }
            else { walk(child); }
          }
        }
      }
      walk(element);
      return output.join('');
    }
    function metadataValue(key){
      var scripts = doc.querySelectorAll('script');
      var expression = new RegExp(key + "\\s*:\\s*['\\\"]([^'\\\"]*)['\\\"]");
      for (var index = 0; index < scripts.length; index++){
        var code = scripts[index].textContent || '';
        var matched = expression.exec(code);
        if (matched){ return clean(matched[1]); }
      }
      return '';
    }
    function firstElement(selectors){
      for (var index = 0; index < selectors.length; index++){
        if (!selectors[index]){ continue; }
        try {
          var element = doc.querySelector(selectors[index]);
          if (element){ return element; }
        } catch (e){ }
      }
      return null;
    }
    function linkByText(labels){
      var links = doc.querySelectorAll('a[href]');
      for (var labelIndex = 0; labelIndex < labels.length; labelIndex++){
        for (var linkIndex = 0; linkIndex < links.length; linkIndex++){
          var text = clean(links[linkIndex].textContent);
          if (text.indexOf(labels[labelIndex]) < 0){ continue; }
          var href = links[linkIndex].getAttribute('href') || '';
          var resolved = absolute(href);
          if (resolved){ return resolved; }
        }
      }
      return '';
    }
    var content = firstElement([
      recipe.contentSelector, '#chaptercontent', '#content', '#acontent', '#TextContent',
      '#read-content', '.chapter-content', '.read-content', 'article'
    ]);
    var titleElement = firstElement([
      recipe.titleSelector, '#atitle', '.chapter-title', '.read-title h1', '.bookname h1', 'article h1', 'h1'
    ]);
    var paragraphs = [];
    if (content){
      var lines = nodeToText(content).split('\\n');
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++){
        var line = clean(lines[lineIndex]);
        if (line.length >= 2){ paragraphs.push(line); }
      }
    }
    var title = titleElement ? clean(titleElement.textContent) : metadataValue('chaptername');
    title = title.replace(/[（(]\\s*第?\\s*\\d+\\s*(?:\\/\\s*\\d+\\s*)?页?\\s*[)）]$/g, '').trim();
    var metadataNextUrl = absolute(metadataValue('url_next'));
    return JSON.stringify({
      title: title,
      paragraphs: paragraphs,
      prevUrl: absolute(metadataValue('url_previous')) || linkByText(['上一章', '上一话', '上章', '上一页']),
      nextUrl: metadataNextUrl || linkByText(['下一章', '下一话', '下章']),
      nextPageUrl: linkByText(['下一页']),
      catalogUrl: absolute(metadataValue('url_index')) || linkByText(['章节目录', '返回目录', '目录']),
      bookTitle: metadataValue('articlename'),
      chapterId: metadataValue('chapterid')
    });
  } catch (e){
    return JSON.stringify({ paragraphs: [] });
  }
})();`;
    const raw: string = await controller.runJavaScript(script);
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(raw)) as NovelDirectHtmlPageRaw;
      const paragraphs: string[] = [];
      if (Array.isArray(parsed.paragraphs)) {
        for (let index: number = 0; index < parsed.paragraphs.length; index += 1) {
          const paragraph: string = this.normalizeText(parsed.paragraphs[index]);
          if (paragraph.length > 0) {
            paragraphs.push(paragraph);
          }
        }
      }
      return {
        title: this.normalizeText(parsed.title),
        paragraphs: paragraphs,
        prevUrl: this.normalizeHttpUrl(parsed.prevUrl),
        nextUrl: this.normalizeHttpUrl(parsed.nextUrl),
        nextPageUrl: this.normalizeHttpUrl(parsed.nextPageUrl),
        catalogUrl: this.normalizeHttpUrl(parsed.catalogUrl),
        bookTitle: this.normalizeText(parsed.bookTitle),
        chapterId: this.normalizeText(parsed.chapterId)
      };
    } catch (_error) {
      return undefined;
    }
  }

  private isChapterContinuationUrl(value: string, chapterId: string, firstPageUrl: string): boolean {
    if (value.length === 0) {
      return false;
    }
    if (chapterId.length > 0 && (value.indexOf(`/${chapterId}_`) >= 0 ||
      value.indexOf(`/${chapterId}-`) >= 0 || value.indexOf(`/${chapterId}/`) >= 0)) {
      return true;
    }
    const firstQueryIndex: number = firstPageUrl.indexOf('?');
    const valueQueryIndex: number = value.indexOf('?');
    const firstWithoutQuery: string = firstQueryIndex >= 0 ? firstPageUrl.substring(0, firstQueryIndex) : firstPageUrl;
    const valueWithoutQuery: string = valueQueryIndex >= 0 ? value.substring(0, valueQueryIndex) : value;
    if (valueQueryIndex >= 0 && firstWithoutQuery === valueWithoutQuery &&
      this.hasPaginationQuery(value.substring(valueQueryIndex + 1))) {
      return true;
    }
    const lastSlash: number = firstPageUrl.lastIndexOf('/');
    const lastDot: number = firstPageUrl.lastIndexOf('.');
    if (lastSlash < 0 || lastDot <= lastSlash) {
      return false;
    }
    const stem: string = firstPageUrl.substring(lastSlash, lastDot);
    return stem.length > 1 && (value.indexOf(`${stem}_`) >= 0 || value.indexOf(`${stem}-`) >= 0 ||
      value.indexOf(`${stem}/`) >= 0);
  }

  private hasPaginationQuery(query: string): boolean {
    const normalized: string = query.toLowerCase();
    const names: string[] = ['page=', 'pageindex=', 'page_index=', 'p='];
    for (let index: number = 0; index < names.length; index += 1) {
      if (normalized.startsWith(names[index]) || normalized.indexOf(`&${names[index]}`) >= 0) {
        return true;
      }
    }
    return false;
  }

  private async acquireEncodedScriptPayload(
    controller: webview.WebviewController,
    chapterUrl: string,
    rule: NovelChapterSourceRule
  ): Promise<NovelChapterExtract | undefined> {
    const metadata: NovelChapterSourceMetadata | undefined =
      await this.readSourceMetadata(controller, chapterUrl, rule);
    if (metadata === undefined) {
      return undefined;
    }
    const resourceUrl: string = this.buildResourceUrl(metadata, rule);
    if (resourceUrl.length === 0) {
      return undefined;
    }
    const source: string = await this.fetchScriptSource(resourceUrl, chapterUrl);
    const encodedPayload: string = this.extractAssignedString(source, rule.payloadVariable);
    if (encodedPayload.length === 0) {
      return undefined;
    }
    const payloadJson: string = this.decodePayload(encodedPayload, rule.payloadDecode);
    if (payloadJson.length === 0) {
      return undefined;
    }
    const parsedPayload: Object = JSON.parse(payloadJson) as Object;
    const payloadTitle: string = this.readJsonString(parsedPayload, rule.titlePath);
    const contentHtml: string = this.readJsonString(parsedPayload, rule.contentPath);
    if (contentHtml.length === 0) {
      return undefined;
    }
    const normalized: NovelChapterExtract | undefined = await this.normalizeHtmlPayload(
      controller,
      payloadTitle.length > 0 ? payloadTitle : metadata.title,
      contentHtml,
      metadata,
      chapterUrl
    );
    return normalized;
  }

  private async readSourceMetadata(
    controller: webview.WebviewController,
    chapterUrl: string,
    rule: NovelChapterSourceRule
  ): Promise<NovelChapterSourceMetadata | undefined> {
    const script: string = `
(function(){
  try {
    var recipe = ${JSON.stringify(rule)};
    var target = ${JSON.stringify(chapterUrl)};
    var pattern = new RegExp(String(recipe.chapterIndexPattern || ''));
    var matched = pattern.exec(target);
    var groupIndex = Number(recipe.chapterIndexGroup || 1);
    if (!matched || !matched[groupIndex]){ return JSON.stringify({ status: 'chapter_index_missing' }); }
    var targetUrl = null;
    var pageUrl = null;
    try {
      targetUrl = new URL(target, location.href);
      pageUrl = new URL(location.href);
    } catch (urlError){ return JSON.stringify({ status: 'url_invalid' }); }
    function normalizedHost(value){
      var host = String(value || '').toLowerCase();
      return host.indexOf('www.') === 0 ? host.substring(4) : host;
    }
    if (targetUrl.protocol !== 'https:' || normalizedHost(targetUrl.hostname) !== normalizedHost(pageUrl.hostname)){
      return JSON.stringify({ status: 'page_host_mismatch' });
    }
    var pageBook = window[String(recipe.pageBookGlobal || '')];
    var identityFields = Array.isArray(recipe.pageBookIdentityFields) ? recipe.pageBookIdentityFields : [];
    var identityGroups = Array.isArray(recipe.targetBookIdentityGroups) ? recipe.targetBookIdentityGroups : [];
    if (!pageBook || typeof pageBook !== 'object' || identityFields.length === 0 ||
      identityFields.length !== identityGroups.length){
      return JSON.stringify({ status: 'book_identity_missing' });
    }
    for (var identityIndex = 0; identityIndex < identityFields.length; identityIndex++){
      var targetIdentity = String(matched[Number(identityGroups[identityIndex])] || '').trim();
      var pageIdentity = String(pageBook[String(identityFields[identityIndex])] || '').trim();
      if (!targetIdentity || targetIdentity !== pageIdentity){
        return JSON.stringify({ status: 'book_identity_mismatch' });
      }
    }
    var chapterNumber = parseInt(matched[groupIndex], 10);
    var indexBase = Number(recipe.chapterIndexBase || 0);
    var chapterIndex = chapterNumber - indexBase;
    var list = window[String(recipe.chapterListGlobal || '')];
    if (!Array.isArray(list) || chapterIndex < 0 || chapterIndex >= list.length){
      return JSON.stringify({ status: 'chapter_metadata_missing' });
    }
    var entry = list[chapterIndex] || {};
    var resourceHost = String(window[String(recipe.resourceDomainGlobal || '')] || '').trim();
    if (!resourceHost && Array.isArray(recipe.resourceHosts) && recipe.resourceHosts.length > 0){
      resourceHost = String(recipe.resourceHosts[0] || '').trim();
    }
    var matchedText = String(matched[0] || '');
    var chapterToken = String(matched[groupIndex] || '');
    var tokenOffset = matchedText.lastIndexOf(chapterToken);
    if (tokenOffset < 0){ return JSON.stringify({ status: 'chapter_identity_invalid' }); }
    var tokenStart = Number(matched.index || 0) + tokenOffset;
    var tokenEnd = tokenStart + chapterToken.length;
    function chapterUrlAt(number){
      return target.substring(0, tokenStart) + String(number) + target.substring(tokenEnd);
    }
    return JSON.stringify({
      status: 'ok',
      title: String(entry[String(recipe.chapterTitleField || '')] || ''),
      bookTitle: String(pageBook[String(recipe.pageBookTitleField || '')] || ''),
      prevUrl: chapterIndex > 0 ? chapterUrlAt(chapterNumber - 1) : '',
      nextUrl: chapterIndex + 1 < list.length ? chapterUrlAt(chapterNumber + 1) : '',
      catalogUrl: target.substring(0, tokenStart),
      resourceHost: resourceHost,
      resourceKey: String(entry[String(recipe.resourceKeyField || '')] || ''),
      resourceLength: String(entry[String(recipe.resourceLengthField || '')] || '')
    });
  } catch (e){
    return JSON.stringify({ status: 'metadata_error' });
  }
})();`;
    const raw: string = await controller.runJavaScript(script);
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(raw)) as NovelChapterSourceMetadataRaw;
      if (parsed.status !== 'ok') {
        return undefined;
      }
      const resourceHost: string = this.resolveAllowedResourceHost(parsed.resourceHost, rule.resourceHosts);
      const resourceKey: string = this.normalizeText(parsed.resourceKey);
      const resourceLength: string = this.normalizeText(parsed.resourceLength);
      if (resourceHost.length === 0 || !this.isSafeResourceKey(resourceKey) ||
        !this.isSafeResourceLength(resourceLength)) {
        return undefined;
      }
      const metadata: NovelChapterSourceMetadata = {
        title: this.normalizeText(parsed.title),
        bookTitle: this.normalizeText(parsed.bookTitle),
        prevUrl: this.normalizeHttpUrl(parsed.prevUrl),
        nextUrl: this.normalizeHttpUrl(parsed.nextUrl),
        catalogUrl: this.normalizeHttpUrl(parsed.catalogUrl),
        resourceHost: resourceHost,
        resourceKey: resourceKey,
        resourceLength: resourceLength
      };
      return metadata;
    } catch (_error) {
      return undefined;
    }
  }

  private buildResourceUrl(
    metadata: NovelChapterSourceMetadata,
    rule: NovelChapterSourceRule
  ): string {
    let path: string = rule.resourcePathTemplate.trim();
    path = path.replace('{key}', metadata.resourceKey);
    path = path.replace('{length}', metadata.resourceLength);
    if (!path.startsWith('/') || path.indexOf('://') >= 0 || path.indexOf('..') >= 0 || path.indexOf('#') >= 0) {
      return '';
    }
    return `https://${metadata.resourceHost}${path}`;
  }

  private async fetchScriptSource(resourceUrl: string, refererUrl: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(resourceUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: NOVEL_SOURCE_CONNECT_TIMEOUT_MS,
        readTimeout: NOVEL_SOURCE_READ_TIMEOUT_MS,
        usingCache: false,
        maxLimit: NOVEL_SOURCE_MAX_BYTES,
        header: {
          'Accept': 'text/javascript,application/javascript,text/plain,*/*;q=0.8',
          'Referer': this.stripFragment(refererUrl),
          'User-Agent': 'Mozilla/5.0 (Mobile; HarmonyOS) AppleWebKit/537.36 Safari/537.36 AiraBrowser/1.0'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return '';
      }
      const source: string = response.result;
      return source.length > 0 && source.length <= NOVEL_SOURCE_MAX_BYTES ? source : '';
    } finally {
      request.destroy();
    }
  }

  private extractAssignedString(source: string, variableName: string): string {
    const normalizedName: string = variableName.trim();
    if (!this.isSafeIdentifier(normalizedName)) {
      return '';
    }
    let searchIndex: number = 0;
    while (searchIndex < source.length) {
      const variableIndex: number = source.indexOf(normalizedName, searchIndex);
      if (variableIndex < 0) {
        return '';
      }
      const equalsIndex: number = source.indexOf('=', variableIndex + normalizedName.length);
      if (equalsIndex < 0) {
        return '';
      }
      let quoteIndex: number = equalsIndex + 1;
      while (quoteIndex < source.length && this.isWhitespace(source.charCodeAt(quoteIndex))) {
        quoteIndex += 1;
      }
      const quote: string = source.charAt(quoteIndex);
      if (quote !== '"' && quote !== "'") {
        searchIndex = variableIndex + normalizedName.length;
        continue;
      }
      let escaped: boolean = false;
      for (let index = quoteIndex + 1; index < source.length; index += 1) {
        const character: string = source.charAt(index);
        if (escaped) {
          escaped = false;
          continue;
        }
        if (character === '\\') {
          escaped = true;
          continue;
        }
        if (character === quote) {
          return source.substring(quoteIndex + 1, index);
        }
      }
      return '';
    }
    return '';
  }

  private decodePayload(encodedPayload: string, decodeKind: string): string {
    if (decodeKind !== 'base64_uri_json') {
      return '';
    }
    try {
      const decodedBytes: Uint8Array = this.base64Helper.decodeSync(encodedPayload);
      const uriEncodedJson: string = this.textDecoder.decodeToString(decodedBytes);
      return decodeURIComponent(uriEncodedJson);
    } catch (_error) {
      return '';
    }
  }

  private readJsonString(root: Object, path: string): string {
    const segments: string[] = path.split('.');
    let current: Object | undefined = root;
    for (let index = 0; index < segments.length; index += 1) {
      const segment: string = segments[index].trim();
      if (segment.length === 0 || current === undefined || current === null || typeof current !== 'object') {
        return '';
      }
      current = (current as Record<string, Object>)[segment];
    }
    return typeof current === 'string' ? current : '';
  }

  private async normalizeHtmlPayload(
    controller: webview.WebviewController,
    title: string,
    contentHtml: string,
    metadata: NovelChapterSourceMetadata,
    chapterUrl: string
  ): Promise<NovelChapterExtract | undefined> {
    const script: string = `
(function(){
  try {
    function clean(value){
      if (!value){ return ''; }
      var output = '';
      for (var i = 0; i < value.length; i++){
        var code = value.charCodeAt(i);
        if (code >= 0xE000 && code <= 0xF8FF){ continue; }
        output += value.charAt(i);
      }
      return output.replace(/\\s+/g, ' ').trim();
    }
    function footerBoundary(value){
      if (!value){ return false; }
      var lower = value.toLowerCase();
      return lower.indexOf('copyright') >= 0 || lower.indexOf('all rights reserved') >= 0 ||
        value.indexOf('版权所有') >= 0 ||
        (value.indexOf('本站') >= 0 && (value.indexOf('搜索引擎') >= 0 || value.indexOf('信息检索服务') >= 0));
    }
    function badLine(value){
      if (!value){ return true; }
      return footerBoundary(value) ||
        value.indexOf('笔趣') >= 0 || value.indexOf('請記住') >= 0 || value.indexOf('请记住') >= 0 ||
        value.indexOf('http') >= 0 || value.indexOf('www.') >= 0 || value.indexOf('最新章节') >= 0 ||
        value.indexOf('章节目录') >= 0 || value.indexOf('天才一秒') >= 0 || value.indexOf('手机阅读') >= 0 ||
        value.indexOf('.com') >= 0 || value.indexOf('.net') >= 0 || value.indexOf('加入书签') >= 0 ||
        value.indexOf('推荐本书') >= 0 || value.indexOf('温馨提示') >= 0;
    }
    function nodeToText(element){
      var output = [];
      function walk(node){
        var children = node.childNodes || [];
        for (var index = 0; index < children.length; index++){
          var child = children[index];
          if (child.nodeType === 3){ output.push(child.nodeValue || ''); }
          else if (child.nodeType === 1){
            var tag = String(child.tagName || '').toLowerCase();
            if (tag === 'br'){ output.push('\\n'); }
            else if (tag === 'script' || tag === 'style' || tag === 'a' || tag === 'ins' ||
              tag === 'button' || tag === 'h1' || tag === 'h2'){ }
            else if (tag === 'p' || tag === 'div'){ output.push('\\n'); walk(child); output.push('\\n'); }
            else { walk(child); }
          }
        }
      }
      walk(element);
      return output.join('');
    }
    var doc = new DOMParser().parseFromString('<div id="__airaNovelPayloadRoot">' +
      ${JSON.stringify(contentHtml)} + '</div>', 'text/html');
    var root = doc.getElementById('__airaNovelPayloadRoot');
    var paragraphs = [];
    if (root){
      var lines = nodeToText(root).split('\\n');
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++){
        var line = clean(lines[lineIndex]);
        if (footerBoundary(line)){ break; }
        if (line.length >= 2 && !badLine(line)){ paragraphs.push(line); }
      }
    }
    return JSON.stringify({ title: clean(${JSON.stringify(title)}), paragraphs: paragraphs });
  } catch (e){
    return JSON.stringify({ title: '', paragraphs: [] });
  }
})();`;
    const raw: string = await controller.runJavaScript(script);
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(raw)) as NovelNormalizedPayloadRaw;
      const paragraphs: string[] = [];
      if (Array.isArray(parsed.paragraphs)) {
        for (let index = 0; index < parsed.paragraphs.length; index += 1) {
          const paragraph: string = this.normalizeText(parsed.paragraphs[index]);
          if (paragraph.length > 0) {
            paragraphs.push(paragraph);
          }
        }
      }
      if (!this.passesQualityGate(paragraphs)) {
        return undefined;
      }
      const chapter: NovelChapterExtract = {
        pageUrl: chapterUrl,
        title: this.normalizeText(parsed.title),
        paragraphs: paragraphs,
        images: [],
        prevUrl: metadata.prevUrl,
        nextUrl: metadata.nextUrl,
        catalogUrl: metadata.catalogUrl,
        bookTitle: metadata.bookTitle,
        pageTotal: 1,
        nextPageUrl: ''
      };
      return chapter;
    } catch (_error) {
      return undefined;
    }
  }

  private passesQualityGate(paragraphs: string[]): boolean {
    if (paragraphs.length === 0 || this.isUnsupportedClientContent(paragraphs)) {
      return false;
    }
    let meaningfulCharacters: number = 0;
    let placeholderCharacters: number = 0;
    let placeholderLines: number = 0;
    for (let index = 0; index < paragraphs.length; index += 1) {
      const paragraph: string = paragraphs[index];
      if (this.isPlaceholderLine(paragraph)) {
        placeholderLines += 1;
        placeholderCharacters += paragraph.length;
      } else {
        meaningfulCharacters += paragraph.length;
      }
    }
    if (meaningfulCharacters < NOVEL_SOURCE_MIN_CONTENT_CHARS) {
      return false;
    }
    if (placeholderLines * 2 >= paragraphs.length && meaningfulCharacters < 80) {
      return false;
    }
    if (placeholderCharacters > meaningfulCharacters * 2 && meaningfulCharacters < 200) {
      return false;
    }
    return true;
  }

  private isPlaceholderLine(value: string): boolean {
    const normalized: string = value.replace(/\s+/g, '')
      .replace(/[：:，,。.！!？?、（）()【】\[\]~～]/g, '');
    const exactControls: string[] = [
      '关灯', '护眼', '字体', '章节', '大', '中', '小', '上一章', '下一章', '目录'
    ];
    if (exactControls.indexOf(normalized) >= 0 || normalized.startsWith('字体')) {
      return true;
    }
    const placeholderPhrases: string[] = [
      '加载中', '请稍等', '多条线路', '自动选取最快线路', '遇到故障', '修复中',
      '过段时间再尝试', '如果出错', '刷新页面', '转码失败', '内容加载失败', '章节正在加载',
      '客户端浏览器停止支持', '为了使用完整的阅读功能'
    ];
    for (let index = 0; index < placeholderPhrases.length; index += 1) {
      if (normalized.indexOf(placeholderPhrases[index]) >= 0) {
        return true;
      }
    }
    return false;
  }

  private resolveAllowedResourceHost(value: string | undefined, allowedHosts: string[]): string {
    const normalized: string = this.normalizeText(value).toLowerCase();
    for (let index = 0; index < allowedHosts.length; index += 1) {
      const allowed: string = allowedHosts[index].trim().toLowerCase();
      if (allowed.length > 0 && normalized === allowed && this.isSafeHost(allowed)) {
        return allowed;
      }
    }
    if (allowedHosts.length > 0) {
      const fallback: string = allowedHosts[0].trim().toLowerCase();
      return this.isSafeHost(fallback) ? fallback : '';
    }
    return '';
  }

  private isSafeHost(value: string): boolean {
    if (value.length === 0 || value.length > 253 || value.startsWith('.') || value.endsWith('.')) {
      return false;
    }
    for (let index = 0; index < value.length; index += 1) {
      const code: number = value.charCodeAt(index);
      const allowed: boolean = (code >= 48 && code <= 57) || (code >= 97 && code <= 122) ||
        code === 45 || code === 46;
      if (!allowed) {
        return false;
      }
    }
    return true;
  }

  private isSafeResourceKey(value: string): boolean {
    if (value.length === 0 || value.length > 2048 || value.indexOf('..') >= 0) {
      return false;
    }
    for (let index = 0; index < value.length; index += 1) {
      const code: number = value.charCodeAt(index);
      const allowed: boolean = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) || code === 43 || code === 45 || code === 46 || code === 47 ||
        code === 61 || code === 95;
      if (!allowed) {
        return false;
      }
    }
    return true;
  }

  private isSafeResourceLength(value: string): boolean {
    if (value.length === 0 || value.length > 12) {
      return false;
    }
    for (let index = 0; index < value.length; index += 1) {
      const code: number = value.charCodeAt(index);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  private isSafeIdentifier(value: string): boolean {
    if (value.length === 0 || value.length > 80) {
      return false;
    }
    for (let index = 0; index < value.length; index += 1) {
      const code: number = value.charCodeAt(index);
      const allowed: boolean = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) || code === 36 || code === 95;
      if (!allowed || (index === 0 && code >= 48 && code <= 57)) {
        return false;
      }
    }
    return true;
  }

  private isWhitespace(code: number): boolean {
    return code === 9 || code === 10 || code === 13 || code === 32;
  }

  private stripFragment(value: string): string {
    const hashIndex: number = value.indexOf('#');
    return hashIndex >= 0 ? value.substring(0, hashIndex) : value;
  }

  private extractHttpOrigin(value: string): string {
    const normalized: string = this.normalizeHttpUrl(value);
    const schemeEnd: number = normalized.indexOf('://');
    if (schemeEnd < 0) {
      return '';
    }
    const authorityStart: number = schemeEnd + 3;
    const pathStart: number = normalized.indexOf('/', authorityStart);
    const authority: string = pathStart >= 0
      ? normalized.substring(authorityStart, pathStart)
      : normalized.substring(authorityStart);
    if (authority.length === 0 || authority.indexOf('@') >= 0 || authority.indexOf('\\') >= 0) {
      return '';
    }
    return `${normalized.substring(0, schemeEnd).toLowerCase()}://${authority.toLowerCase()}`;
  }

  private isSameOriginUrl(value: string, expectedOrigin: string): boolean {
    return expectedOrigin.length > 0 && this.extractHttpOrigin(value) === expectedOrigin;
  }

  private normalizeHttpUrl(value: string | undefined): string {
    const normalized: string = this.normalizeText(value);
    return normalized.startsWith('https://') || normalized.startsWith('http://') ? normalized : '';
  }

  private normalizeText(value: string | undefined): string {
    return value === undefined || value === null ? '' : String(value).trim();
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
