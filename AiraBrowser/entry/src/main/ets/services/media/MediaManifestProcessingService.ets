import { http } from '@kit.NetworkKit';
import {
  MediaManifestMediaRendition,
  MediaManifestParseResult,
  MediaManifestRequestContext,
  MediaManifestSummary,
  MediaManifestVariant,
  emptyMediaManifestSummary
} from '../../features/mediaDiscovery/MediaManifestModels';
import { WebCookieHeaderService } from '../web/WebCookieHeaderService';

const MANIFEST_FETCH_TIMEOUT_MS: number = 12000;
const MAX_MANIFEST_TEXT_BYTES: number = 1024 * 1024;
const MAX_VARIANT_PROBE_COUNT: number = 6;
const MAX_SAMPLE_SEGMENTS: number = 5;

interface HlsMediaPlaylistAnalysis {
  segmentCount: number;
  targetDuration: number;
  durationSeconds: number;
  encrypted: boolean;
  protectedContent: boolean;
  keyUrls: string[];
  keyMethods: string[];
  mapUrls: string[];
  sampleSegments: string[];
}

interface HlsMasterPlaylistAnalysis {
  variants: MediaManifestVariant[];
  media: MediaManifestMediaRendition[];
}

interface ManifestFetchTextResult {
  ok: boolean;
  text: string;
  errorMessage: string;
}

export class MediaManifestProcessingService {
  private cookieHeaderService: WebCookieHeaderService;

  constructor(cookieHeaderService: WebCookieHeaderService = new WebCookieHeaderService()) {
    this.cookieHeaderService = cookieHeaderService;
  }

  async parse(context: MediaManifestRequestContext): Promise<MediaManifestParseResult> {
    const url = context.url.trim();
    if (!this.isHttpUrl(url)) {
      return this.fail('清单链接必须是 http 或 https。');
    }
    const fetchResult = await this.fetchText(url, context);
    if (!fetchResult.ok) {
      return this.fail(fetchResult.errorMessage);
    }
    return this.parseText(fetchResult.text, url, context);
  }

  async parseText(
    text: string,
    url: string,
    context: MediaManifestRequestContext = { url: '' }
  ): Promise<MediaManifestParseResult> {
    const source = text.trim();
    if (source.length <= 0) {
      return this.fail('清单内容为空。');
    }
    if (this.looksLikeDash(source, url)) {
      const summary = this.createBaseSummary(url);
      summary.kind = 'dash';
      summary.role = 'dash';
      summary.warnings.push('DASH/MPD 已识别，解析明细将在后续版本接入。');
      return { ok: true, summary: summary, errorMessage: '' };
    }
    if (!this.looksLikeHls(source, url)) {
      return this.fail('没有识别到 HLS 或 DASH 清单。');
    }
    const lines = this.normalizeLines(source);
    const master = this.parseHlsMaster(lines, url);
    if (master.variants.length > 0) {
      const summary = this.createBaseSummary(url);
      summary.kind = 'hls';
      summary.role = 'master';
      summary.variants = master.variants;
      summary.media = master.media;
      summary.variantCount = master.variants.length;
      await this.probeHlsVariants(summary, context);
      return { ok: true, summary: summary, errorMessage: '' };
    }
    const media = this.parseHlsMedia(lines, url);
    const summary = this.createBaseSummary(url);
    summary.kind = 'hls';
    summary.role = 'media';
    summary.segmentCount = media.segmentCount;
    summary.keyCount = media.keyUrls.length;
    summary.encrypted = media.encrypted;
    summary.protectedContent = media.protectedContent;
    summary.targetDuration = media.targetDuration;
    summary.durationSeconds = media.durationSeconds;
    summary.sampleSegments = media.sampleSegments;
    summary.keyUrls = media.keyUrls;
    summary.keyMethods = media.keyMethods;
    summary.mapUrls = media.mapUrls;
    return { ok: true, summary: summary, errorMessage: '' };
  }

  private async probeHlsVariants(
    summary: MediaManifestSummary,
    context: MediaManifestRequestContext
  ): Promise<void> {
    const limit = Math.min(summary.variants.length, MAX_VARIANT_PROBE_COUNT);
    for (let i = 0; i < limit; i++) {
      const variant = summary.variants[i];
      const fetchResult = await this.fetchText(variant.url, {
        url: variant.url,
        referer: context.referer,
        userAgent: context.userAgent,
        originUrl: context.originUrl,
        requestHeaders: context.requestHeaders
      });
      if (!fetchResult.ok) {
        summary.warnings.push('无法探测清晰度 ' + (i + 1).toString() + ' 的分片信息。');
        continue;
      }
      const analysis = this.parseHlsMedia(this.normalizeLines(fetchResult.text), variant.url);
      variant.segmentCount = analysis.segmentCount;
      variant.targetDuration = analysis.targetDuration;
      variant.durationSeconds = analysis.durationSeconds;
      variant.encrypted = analysis.encrypted;
      variant.protectedContent = analysis.protectedContent;
      variant.sampleSegments = analysis.sampleSegments;
      variant.keyUrls = analysis.keyUrls;
      variant.keyMethods = analysis.keyMethods;
      variant.mapUrls = analysis.mapUrls;
      summary.segmentCount += analysis.segmentCount;
      summary.durationSeconds = Math.max(summary.durationSeconds, analysis.durationSeconds);
      summary.targetDuration = Math.max(summary.targetDuration, analysis.targetDuration);
      summary.encrypted = summary.encrypted || analysis.encrypted;
      summary.protectedContent = summary.protectedContent || analysis.protectedContent;
      this.appendUniqueUrls(summary.keyUrls, analysis.keyUrls);
      this.appendUniqueStrings(summary.keyMethods, analysis.keyMethods);
      this.appendUniqueUrls(summary.mapUrls, analysis.mapUrls);
      this.appendSampleSegments(summary.sampleSegments, analysis.sampleSegments);
    }
    summary.keyCount = summary.keyUrls.length;
    if (summary.variants.length > limit) {
      summary.warnings.push('仅探测前 ' + limit.toString() + ' 个清晰度，避免页面资源解析过重。');
    }
  }

  private parseHlsMaster(lines: string[], url: string): HlsMasterPlaylistAnalysis {
    const variants: MediaManifestVariant[] = [];
    const media: MediaManifestMediaRendition[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.startsWith('#EXT-X-MEDIA:')) {
        const attrs = this.parseAttributes(line.substring('#EXT-X-MEDIA:'.length));
        media.push({
          type: attrs['TYPE'] ?? '',
          groupId: attrs['GROUP-ID'] ?? '',
          name: attrs['NAME'] ?? '',
          language: attrs['LANGUAGE'] ?? '',
          url: this.resolveMaybeUrl(url, attrs['URI'] ?? '')
        });
      }
      if (!line.startsWith('#EXT-X-STREAM-INF:')) {
        continue;
      }
      const attrs = this.parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length));
      const nextUrl = this.findNextResourceLine(lines, i + 1);
      if (nextUrl.length <= 0) {
        continue;
      }
      variants.push({
        index: variants.length,
        url: this.resolveUrl(url, nextUrl),
        bandwidth: this.parsePositiveNumber(attrs['BANDWIDTH']),
        averageBandwidth: this.parsePositiveNumber(attrs['AVERAGE-BANDWIDTH']),
        resolution: attrs['RESOLUTION'] ?? '',
        codecs: attrs['CODECS'] ?? '',
        name: attrs['NAME'] ?? '',
        segmentCount: 0,
        targetDuration: 0,
        durationSeconds: 0,
        encrypted: false,
        protectedContent: false,
        sampleSegments: [],
        keyUrls: [],
        keyMethods: [],
        mapUrls: []
      });
    }
    return { variants: variants, media: media };
  }

  private parseHlsMedia(lines: string[], url: string): HlsMediaPlaylistAnalysis {
    const result: HlsMediaPlaylistAnalysis = {
      segmentCount: 0,
      targetDuration: 0,
      durationSeconds: 0,
      encrypted: false,
      protectedContent: false,
      keyUrls: [],
      keyMethods: [],
      mapUrls: [],
      sampleSegments: []
    };
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        result.targetDuration = this.parsePositiveNumber(line.substring('#EXT-X-TARGETDURATION:'.length));
        continue;
      }
      if (line.startsWith('#EXTINF:')) {
        result.durationSeconds += this.parseExtInfDuration(line);
        continue;
      }
      if (line.startsWith('#EXT-X-KEY:')) {
        const attrs = this.parseAttributes(line.substring('#EXT-X-KEY:'.length));
        const method = attrs['METHOD'] ?? '';
        if (method.length > 0 && method !== 'NONE') {
          result.encrypted = true;
        }
        this.appendUniqueStrings(result.keyMethods, [method]);
        if (this.isProtectedHlsKey(attrs)) {
          result.protectedContent = true;
        }
        this.appendUniqueUrls(result.keyUrls, [this.resolveMaybeUrl(url, attrs['URI'] ?? '')]);
        continue;
      }
      if (line.startsWith('#EXT-X-MAP:')) {
        const attrs = this.parseAttributes(line.substring('#EXT-X-MAP:'.length));
        this.appendUniqueUrls(result.mapUrls, [this.resolveMaybeUrl(url, attrs['URI'] ?? '')]);
        continue;
      }
      if (line.length > 0 && !line.startsWith('#')) {
        result.segmentCount += 1;
        this.appendSampleSegments(result.sampleSegments, [this.resolveUrl(url, line)]);
      }
    }
    return result;
  }

  private isProtectedHlsKey(attrs: Record<string, string>): boolean {
    const method = (attrs['METHOD'] ?? '').trim().toUpperCase();
    if (method === 'SAMPLE-AES' || method === 'SAMPLE-AES-CENC' || method === 'SAMPLE-AES-CTR') {
      return true;
    }
    const keyFormat = (attrs['KEYFORMAT'] ?? '').trim().toLowerCase();
    if (keyFormat === 'com.apple.streamingkeydelivery' ||
      keyFormat === 'urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed' ||
      keyFormat === 'urn:uuid:9a04f079-9840-4286-ab92-e65be0885f95') {
      return true;
    }
    const uri = (attrs['URI'] ?? '').trim().toLowerCase();
    return uri.startsWith('skd://') || uri.startsWith('data:text/plain;base64,');
  }

  private parseAttributes(input: string): Record<string, string> {
    const attrs: Record<string, string> = {};
    let current = '';
    let insideQuote = false;
    const parts: string[] = [];
    for (let i = 0; i < input.length; i++) {
      const ch = input.charAt(i);
      if (ch === '"') {
        insideQuote = !insideQuote;
        current += ch;
      } else if (ch === ',' && !insideQuote) {
        parts.push(current);
        current = '';
      } else {
        current += ch;
      }
    }
    if (current.length > 0) {
      parts.push(current);
    }
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      const equalIndex = part.indexOf('=');
      if (equalIndex <= 0) {
        continue;
      }
      const key = part.substring(0, equalIndex).trim().toUpperCase();
      const value = this.stripQuotes(part.substring(equalIndex + 1).trim());
      if (key.length > 0) {
        attrs[key] = value;
      }
    }
    return attrs;
  }

  private async fetchText(url: string, context: MediaManifestRequestContext): Promise<ManifestFetchTextResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: MANIFEST_FETCH_TIMEOUT_MS,
        readTimeout: MANIFEST_FETCH_TIMEOUT_MS,
        usingCache: true,
        header: this.buildHeaders(context)
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return { ok: false, text: '', errorMessage: '清单请求失败。' };
      }
      const text = response.result.trim();
      if (text.length <= 0) {
        return { ok: false, text: '', errorMessage: '清单内容为空。' };
      }
      if (text.length > MAX_MANIFEST_TEXT_BYTES) {
        return { ok: false, text: '', errorMessage: '清单内容过大，暂不解析。' };
      }
      return { ok: true, text: text, errorMessage: '' };
    } catch (_error) {
      return { ok: false, text: '', errorMessage: '清单请求失败。' };
    } finally {
      request.destroy();
    }
  }

  private buildHeaders(context: MediaManifestRequestContext): Record<string, string> {
    const headers: Record<string, string> = {};
    const sourceHeaders = context.requestHeaders ?? {};
    const keys = Object.keys(sourceHeaders);
    for (let i = 0; i < keys.length; i++) {
      const rawKey = keys[i];
      if (rawKey === undefined) {
        continue;
      }
      const key = rawKey.trim();
      const rawValue = sourceHeaders[rawKey];
      const value = rawValue === undefined ? '' : rawValue.trim();
      if (key.length > 0 && value.length > 0) {
        headers[key] = value;
      }
    }
    headers['Accept'] = 'application/vnd.apple.mpegurl,application/x-mpegURL,application/dash+xml,text/plain,*/*;q=0.8';
    const userAgent = context.userAgent === undefined ? '' : context.userAgent.trim();
    headers['User-Agent'] = userAgent.length > 0 ? userAgent : 'AiraBrowser/1.0';
    if (context.referer !== undefined && context.referer.trim().length > 0) {
      headers['Referer'] = context.referer.trim();
    }
    if (context.originUrl !== undefined && context.originUrl.trim().length > 0) {
      headers['Origin'] = context.originUrl.trim();
    }
    this.cookieHeaderService.putCookieHeaderIfAbsent(headers, context.url);
    return headers;
  }

  private createBaseSummary(url: string): MediaManifestSummary {
    const summary = emptyMediaManifestSummary();
    summary.url = url;
    summary.sourceHost = this.resolveHost(url);
    summary.fetchedAt = Date.now();
    return summary;
  }

  private normalizeLines(text: string): string[] {
    const raw = text.replace(/\r/g, '').split('\n');
    const lines: string[] = [];
    for (let i = 0; i < raw.length; i++) {
      const line = raw[i].trim();
      if (line.length > 0) {
        lines.push(line);
      }
    }
    return lines;
  }

  private looksLikeHls(text: string, url: string): boolean {
    const lowerUrl = url.toLowerCase();
    return text.indexOf('#EXTM3U') >= 0 || lowerUrl.indexOf('.m3u8') >= 0 || lowerUrl.indexOf('.m3u') >= 0;
  }

  private looksLikeDash(text: string, url: string): boolean {
    const lower = text.substring(0, Math.min(text.length, 512)).toLowerCase();
    return lower.indexOf('<mpd') >= 0 || url.toLowerCase().indexOf('.mpd') >= 0;
  }

  private findNextResourceLine(lines: string[], startIndex: number): string {
    for (let i = startIndex; i < lines.length; i++) {
      if (lines[i].length > 0 && !lines[i].startsWith('#')) {
        return lines[i];
      }
    }
    return '';
  }

  private parseExtInfDuration(line: string): number {
    const value = line.substring('#EXTINF:'.length).split(',')[0].trim();
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  private parsePositiveNumber(value: string | undefined): number {
    const parsed = Number((value ?? '').trim());
    return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 0;
  }

  private resolveMaybeUrl(baseUrl: string, value: string): string {
    const trimmed = value.trim();
    return trimmed.length > 0 ? this.resolveUrl(baseUrl, trimmed) : '';
  }

  private resolveUrl(baseUrl: string, value: string): string {
    const trimmed = value.trim();
    if (this.isHttpUrl(trimmed)) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) {
      return this.resolveScheme(baseUrl) + ':' + trimmed;
    }
    const schemeIndex = baseUrl.indexOf('://');
    if (schemeIndex < 0) {
      return trimmed;
    }
    const pathStart = baseUrl.indexOf('/', schemeIndex + 3);
    const origin = pathStart >= 0 ? baseUrl.substring(0, pathStart) : baseUrl;
    if (trimmed.startsWith('/')) {
      return origin + trimmed;
    }
    const withoutQuery = baseUrl.split('?')[0].split('#')[0];
    const lastSlash = withoutQuery.lastIndexOf('/');
    const baseDir = lastSlash >= 0 ? withoutQuery.substring(0, lastSlash + 1) : origin + '/';
    return this.normalizeUrlPath(baseDir + trimmed);
  }

  private normalizeUrlPath(url: string): string {
    const schemeIndex = url.indexOf('://');
    if (schemeIndex < 0) {
      return url;
    }
    const prefixEnd = url.indexOf('/', schemeIndex + 3);
    if (prefixEnd < 0) {
      return url;
    }
    const prefix = url.substring(0, prefixEnd);
    const path = url.substring(prefixEnd + 1);
    const parts = path.split('/');
    const stack: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      if (parts[i] === '..') {
        if (stack.length > 0) {
          stack.pop();
        }
      } else if (parts[i] !== '.') {
        stack.push(parts[i]);
      }
    }
    return prefix + '/' + stack.join('/');
  }

  private appendUniqueUrls(target: string[], urls: string[]): void {
    for (let i = 0; i < urls.length; i++) {
      const url = urls[i].trim();
      if (url.length > 0 && target.indexOf(url) < 0) {
        target.push(url);
      }
    }
  }

  private appendUniqueStrings(target: string[], values: string[]): void {
    for (let i = 0; i < values.length; i++) {
      const value = values[i].trim();
      if (value.length > 0 && target.indexOf(value) < 0) {
        target.push(value);
      }
    }
  }

  private appendSampleSegments(target: string[], urls: string[]): void {
    for (let i = 0; i < urls.length; i++) {
      if (target.length >= MAX_SAMPLE_SEGMENTS) {
        return;
      }
      const url = urls[i].trim();
      if (url.length > 0 && target.indexOf(url) < 0) {
        target.push(url);
      }
    }
  }

  private stripQuotes(value: string): string {
    const trimmed = value.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  private resolveScheme(url: string): string {
    const schemeIndex = url.indexOf('://');
    return schemeIndex > 0 ? url.substring(0, schemeIndex) : 'https';
  }

  private resolveHost(url: string): string {
    const schemeIndex = url.indexOf('://');
    if (schemeIndex < 0) {
      return '';
    }
    const hostStart = schemeIndex + 3;
    const pathStart = url.indexOf('/', hostStart);
    const authority = pathStart >= 0 ? url.substring(hostStart, pathStart) : url.substring(hostStart);
    return authority.split('@').pop()?.split(':')[0]?.trim() ?? '';
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  private fail(message: string): MediaManifestParseResult {
    return { ok: false, errorMessage: message };
  }
}
