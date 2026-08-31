import { fileIo } from '@kit.CoreFileKit';
import buffer from '@ohos.buffer';
import { TabRecord } from '../../common/models/BrowserModels';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import { MarkdownDocumentViewerService } from '../markdown/MarkdownDocumentViewerService';

export const DOCUMENT_VIEWER_URL_PREFIX: string = 'aira://document-viewer';

export type DocumentViewerKind = 'markdown' | 'json' | 'text' | 'html';

export interface DocumentViewerInfo {
  kind: DocumentViewerKind;
  fileUri: string;
  displayName: string;
}

export interface DocumentViewerChromePolicy {
  active: boolean;
  kind: DocumentViewerKind | '';
  title: string;
  sourceUri: string;
  expansionEnabled: boolean;
  scrollCollapseEnabled: boolean;
  fullViewport: boolean;
}

export interface DocumentViewerChromeContext {
  url: string;
  policy: DocumentViewerChromePolicy;
  title: string;
}

export interface DocumentViewerFileInfo {
  kind: DocumentViewerKind;
  displayName: string;
  sourceUri: string;
  typeLabel: string;
  sizeBytes: number;
  sizeLabel: string;
  modifiedAtSeconds: number;
  modifiedAtLabel: string;
  readOnlyLabel: string;
  rows: DocumentViewerInfoRow[];
}

export interface DocumentViewerInfoRow {
  label: string;
  value: string;
  multiline: boolean;
}

interface DocumentViewerHtmlInput {
  title: string;
  bodyHtml: string;
  documentClass: string;
}

const DOCUMENT_VIEWER_MAX_BYTES: number = 5 * 1024 * 1024;
const DOCUMENT_VIEWER_CHROME_POLICY_CACHE_LIMIT: number = 32;

export class DocumentViewerService {
  private markdownViewerService: MarkdownDocumentViewerService = new MarkdownDocumentViewerService();
  private chromePolicyByUrl: Map<string, DocumentViewerChromePolicy> = new Map();

  isDocumentSourceUrl(url: string, mimeType: string = ''): boolean {
    return this.resolveSourceKind(url, mimeType) !== undefined;
  }

  buildViewerUrl(fileUri: string, mimeType: string = '', displayName: string = ''): string {
    const normalizedFileUri = fileUri.trim();
    const kind = this.resolveSourceKind(normalizedFileUri, mimeType);
    if (kind === undefined) {
      return normalizedFileUri;
    }
    if (kind === 'markdown') {
      return this.markdownViewerService.buildViewerUrl(normalizedFileUri, displayName);
    }
    const title = displayName.trim().length > 0 ? displayName.trim() : this.resolveDisplayName(normalizedFileUri);
    return `${DOCUMENT_VIEWER_URL_PREFIX}?kind=${encodeURIComponent(kind)}` +
      `&uri=${encodeURIComponent(normalizedFileUri)}&name=${encodeURIComponent(title)}`;
  }

  isDocumentViewerUrl(url: string): boolean {
    if (this.markdownViewerService.isMarkdownViewerUrl(url)) {
      return true;
    }
    return url.trim().startsWith(DOCUMENT_VIEWER_URL_PREFIX);
  }

  parseViewerUrl(url: string): DocumentViewerInfo | undefined {
    const markdownInfo = this.markdownViewerService.parseViewerUrl(url);
    if (markdownInfo !== undefined) {
      return {
        kind: 'markdown',
        fileUri: markdownInfo.fileUri,
        displayName: markdownInfo.displayName
      };
    }
    if (!url.trim().startsWith(DOCUMENT_VIEWER_URL_PREFIX)) {
      return undefined;
    }
    const fileUri = this.readQueryParam(url, 'uri');
    if (fileUri.length === 0) {
      return undefined;
    }
    const kind = this.normalizeViewerKind(this.readQueryParam(url, 'kind'));
    if (kind === undefined) {
      return undefined;
    }
    const displayName = this.readQueryParam(url, 'name');
    return {
      kind: kind,
      fileUri: fileUri,
      displayName: displayName.length > 0 ? displayName : this.resolveDisplayName(fileUri)
    };
  }

  resolveChromePolicy(url: string, mimeType: string = ''): DocumentViewerChromePolicy {
    const cacheKey = this.buildChromePolicyCacheKey(url, mimeType);
    const cached = this.chromePolicyByUrl.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    const policy = this.resolveChromePolicyUncached(url, mimeType);
    this.rememberChromePolicy(cacheKey, policy);
    return policy;
  }

  resolveChromeContext(candidateUrls: string[], fallbackTitle: string): DocumentViewerChromeContext {
    for (let index = 0; index < candidateUrls.length; index += 1) {
      const candidateUrl = candidateUrls[index].trim();
      const policy = this.resolveChromePolicy(candidateUrl);
      if (!policy.active) {
        continue;
      }
      return {
        url: candidateUrl,
        policy: policy,
        title: policy.title.trim().length > 0 ? policy.title.trim() : '文件'
      };
    }
    const normalizedFallbackTitle = fallbackTitle.trim();
    return {
      url: '',
      policy: this.resolveChromePolicy(''),
      title: normalizedFallbackTitle.length > 0 ? normalizedFallbackTitle : '文件'
    };
  }

  private resolveChromePolicyUncached(url: string, mimeType: string): DocumentViewerChromePolicy {
    const viewerInfo = this.parseViewerUrl(url);
    if (viewerInfo !== undefined) {
      return this.buildActivePolicy(viewerInfo.kind, viewerInfo.displayName, viewerInfo.fileUri);
    }
    const sourceKind = this.resolveSourceKind(url, mimeType);
    if (sourceKind === undefined) {
      return {
        active: false,
        kind: '',
        title: '',
        sourceUri: '',
        expansionEnabled: true,
        scrollCollapseEnabled: true,
        fullViewport: false
      };
    }
    return this.buildActivePolicy(sourceKind, this.resolveDisplayName(url), url);
  }

  private buildChromePolicyCacheKey(url: string, mimeType: string): string {
    return `${mimeType}\n${url}`;
  }

  private rememberChromePolicy(cacheKey: string, policy: DocumentViewerChromePolicy): void {
    if (this.chromePolicyByUrl.size >= DOCUMENT_VIEWER_CHROME_POLICY_CACHE_LIMIT) {
      const cachedKeys = Array.from(this.chromePolicyByUrl.keys());
      if (cachedKeys.length > 0) {
        this.chromePolicyByUrl.delete(cachedKeys[0]);
      }
    }
    this.chromePolicyByUrl.set(cacheKey, policy);
  }

  isDocumentViewerTabRecord(record: TabRecord): boolean {
    return this.resolveTabRecordViewerUrl(record).length > 0;
  }

  buildLoadingPayload(url: string): BrowserWebLoadDataPayload | undefined {
    const markdownPayload = this.markdownViewerService.buildLoadingPayload(url);
    if (markdownPayload !== undefined) {
      return markdownPayload;
    }
    const info = this.parseViewerUrl(url);
    if (info === undefined) {
      return undefined;
    }
    return this.buildPayload(
      url,
      info.displayName,
      this.buildHtml({
        title: info.displayName,
        bodyHtml: '<p class="empty">正在读取文件...</p>',
        documentClass: this.resolveDocumentClass(info.kind)
      })
    );
  }

  async buildPayloadFromViewerUrl(url: string): Promise<BrowserWebLoadDataPayload | undefined> {
    const markdownInfo = this.markdownViewerService.parseViewerUrl(url);
    if (markdownInfo !== undefined) {
      return this.markdownViewerService.buildPayloadFromViewerUrl(url);
    }
    const info = this.parseViewerUrl(url);
    if (info === undefined) {
      return undefined;
    }
    try {
      const text = await this.readTextFile(info.fileUri);
      if (info.kind === 'html') {
        const html = text.trim().length > 0 ? text : this.buildHtml({
          title: info.displayName,
          bodyHtml: '<p class="empty">这个 HTML 文件没有内容。</p>',
          documentClass: this.resolveDocumentClass(info.kind)
        });
        return this.buildPayload(url, info.displayName, html);
      }
      const bodyHtml = info.kind === 'json' ? this.renderJson(text) : this.renderText(text);
      return this.buildPayload(
        url,
        info.displayName,
        this.buildHtml({
          title: info.displayName,
          bodyHtml: bodyHtml,
          documentClass: this.resolveDocumentClass(info.kind)
        })
      );
    } catch (error) {
      return this.buildPayload(
        url,
        info.displayName,
        this.buildHtml({
          title: info.displayName,
          bodyHtml: this.buildErrorHtml(this.stringifyError(error)),
          documentClass: this.resolveDocumentClass(info.kind)
        })
      );
    }
  }

  async resolveFileInfo(url: string): Promise<DocumentViewerFileInfo | undefined> {
    const policy = this.resolveChromePolicy(url);
    if (!policy.active || policy.sourceUri.trim().length <= 0 || policy.kind.length <= 0) {
      return undefined;
    }
    const kind = this.normalizeViewerKind(policy.kind);
    if (kind === undefined) {
      return undefined;
    }
    const stat = await fileIo.stat(policy.sourceUri);
    if (stat.isDirectory()) {
      throw new Error('请选择文件。');
    }
    const sizeBytes = Math.max(0, Math.floor(stat.size));
    const modifiedAtSeconds = Math.max(0, Math.floor(stat.mtime));
    const info: DocumentViewerFileInfo = {
      kind: kind,
      displayName: policy.title,
      sourceUri: policy.sourceUri,
      typeLabel: this.resolveKindLabel(kind),
      sizeBytes: sizeBytes,
      sizeLabel: this.formatBytes(sizeBytes),
      modifiedAtSeconds: modifiedAtSeconds,
      modifiedAtLabel: this.formatUnixSeconds(modifiedAtSeconds),
      readOnlyLabel: '只读查看',
      rows: []
    };
    info.rows = this.buildInfoRows(info);
    return info;
  }

  private buildActivePolicy(kind: DocumentViewerKind, title: string, sourceUri: string): DocumentViewerChromePolicy {
    const webLikeDocument = kind === 'html';
    return {
      active: true,
      kind: kind,
      title: title.trim().length > 0 ? title.trim() : '文件',
      sourceUri: sourceUri,
      expansionEnabled: webLikeDocument,
      scrollCollapseEnabled: true,
      fullViewport: true
    };
  }

  private resolveTabRecordViewerUrl(record: TabRecord): string {
    const candidates: string[] = [
      record.pendingUrl ?? '',
      record.url,
      record.lastGoodUrl ?? '',
      record.lastRestorableUrl ?? ''
    ];
    const history = record.navigationHistory ?? [];
    history.forEach((url: string) => {
      candidates.push(url);
    });
    for (let index = 0; index < candidates.length; index += 1) {
      const url = candidates[index].trim();
      if (url.length > 0 && this.resolveChromePolicy(url).active) {
        return url;
      }
    }
    return '';
  }

  private buildPayload(historyUrl: string, title: string, data: string): BrowserWebLoadDataPayload {
    return {
      data: data,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: DOCUMENT_VIEWER_URL_PREFIX,
      historyUrl: historyUrl
    };
  }

  private async readTextFile(uri: string): Promise<string> {
    const stat = await fileIo.stat(uri);
    if (stat.isDirectory()) {
      throw new Error('请选择文件。');
    }
    if (stat.size <= 0) {
      return '';
    }
    if (stat.size > DOCUMENT_VIEWER_MAX_BYTES) {
      throw new Error('文件超过 5 MB，暂不支持查看。');
    }
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(Math.max(1, Math.floor(stat.size)));
      const readLength = await fileIo.read(file.fd, data);
      return readLength > 0 ? buffer.from(data, 0, readLength).toString('utf8') : '';
    } finally {
      await fileIo.close(file);
    }
  }

  private renderJson(text: string): string {
    const normalized = text.trim();
    if (normalized.length === 0) {
      return '<p class="empty">这个 JSON 文件没有内容。</p>';
    }
    try {
      const parsed = JSON.parse(normalized) as Object;
      return `<pre class="document-pre">${this.escapeHtml(JSON.stringify(parsed, null, 2))}</pre>`;
    } catch (_error) {
      return `<pre class="document-pre">${this.escapeHtml(text)}</pre>`;
    }
  }

  private renderText(text: string): string {
    if (text.trim().length === 0) {
      return '<p class="empty">这个文本文件没有内容。</p>';
    }
    return `<pre class="document-pre">${this.escapeHtml(text)}</pre>`;
  }

  private buildHtml(input: DocumentViewerHtmlInput): string {
    const title = input.title.trim().length > 0 ? input.title.trim() : '文件';
    return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${this.escapeHtml(title)}</title>
<style>
${this.buildCss()}
</style>
</head>
<body class="${input.documentClass}">
${input.bodyHtml}
</body>
</html>`;
  }

  private buildCss(): string {
    return `:root {
  color-scheme: light dark;
  --bg: #f6f7f9;
  --text: #18202a;
  --muted: #68717d;
  --line: #dce2ea;
  --code-bg: #f0f3f6;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f1216;
    --text: #e8edf3;
    --muted: #9aa5b1;
    --line: #2b333d;
    --code-bg: #222832;
  }
}
* { box-sizing: border-box; }
html {
  min-height: 100%;
  background: var(--bg);
  scroll-padding-top: calc(env(safe-area-inset-top, 0px) + 14px);
}
body {
  margin: 0;
  min-height: 100vh;
  padding: calc(env(safe-area-inset-top, 0px) + 14px) 14px calc(env(safe-area-inset-bottom, 0px) + 92px);
  background: var(--bg);
  color: var(--text);
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "HarmonyOS Sans", sans-serif;
  line-height: 1.58;
}
.document-pre {
  margin: 0;
  padding: 12px;
  overflow: auto;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--code-bg);
  color: var(--text);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13px;
  line-height: 1.55;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
body.document-json .document-pre {
  white-space: pre;
}
.empty, .error {
  color: var(--muted);
}
.error {
  border: 1px solid var(--line);
  background: var(--code-bg);
  border-radius: 8px;
  padding: 12px;
}`;
  }

  private resolveDocumentClass(kind: DocumentViewerKind): string {
    return `document-${kind}`;
  }

  private resolveKindLabel(kind: DocumentViewerKind): string {
    switch (kind) {
      case 'markdown':
        return 'Markdown 文档';
      case 'json':
        return 'JSON 文档';
      case 'text':
        return '文本文件';
      case 'html':
        return 'HTML 文档';
      default:
        return '文件';
    }
  }

  private buildInfoRows(info: DocumentViewerFileInfo): DocumentViewerInfoRow[] {
    return [
      this.buildInfoRow('文件名', info.displayName, false),
      this.buildInfoRow('类型', info.typeLabel, false),
      this.buildInfoRow('大小', info.sizeLabel, false),
      this.buildInfoRow('修改时间', info.modifiedAtLabel, false),
      this.buildInfoRow('打开方式', info.readOnlyLabel, false),
      this.buildInfoRow('位置', info.sourceUri, true)
    ];
  }

  private buildInfoRow(label: string, value: string, multiline: boolean): DocumentViewerInfoRow {
    return {
      label: label,
      value: value.trim().length > 0 ? value.trim() : '未知',
      multiline: multiline
    };
  }

  private formatBytes(bytes: number): string {
    const normalizedBytes = Math.max(0, Math.floor(bytes));
    if (normalizedBytes < 1024) {
      return `${normalizedBytes} B`;
    }
    const units: string[] = ['KB', 'MB', 'GB'];
    let value = normalizedBytes / 1024;
    let unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    return `${this.formatDecimal(value)} ${units[unitIndex]}`;
  }

  private formatDecimal(value: number): string {
    if (value >= 100) {
      return Math.round(value).toString();
    }
    if (value >= 10) {
      return (Math.round(value * 10) / 10).toFixed(1);
    }
    return (Math.round(value * 100) / 100).toFixed(2);
  }

  private formatUnixSeconds(seconds: number): string {
    if (seconds <= 0) {
      return '未知';
    }
    const date = new Date(seconds * 1000);
    return `${date.getFullYear()}-${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ` +
      `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private pad2(value: number): string {
    const normalized = Math.max(0, Math.floor(value));
    return normalized < 10 ? `0${normalized}` : normalized.toString();
  }

  private buildErrorHtml(message: string): string {
    return `<p class="error">${this.escapeHtml(message)}</p>`;
  }

  private resolveSourceKind(url: string, mimeType: string = ''): DocumentViewerKind | undefined {
    if (!this.isLocalFileLikeUrl(url)) {
      return undefined;
    }
    const normalizedMimeType = this.normalizeMimeType(mimeType);
    if (this.markdownViewerService.isMarkdownSourceUrl(url, normalizedMimeType)) {
      return 'markdown';
    }
    if (normalizedMimeType === 'application/json' || normalizedMimeType === 'text/json') {
      return 'json';
    }
    if (normalizedMimeType === 'text/html' || normalizedMimeType === 'application/xhtml+xml') {
      return 'html';
    }
    if (normalizedMimeType === 'text/plain') {
      return 'text';
    }
    const path = this.stripQueryAndFragment(url).toLowerCase();
    if (path.endsWith('.json')) {
      return 'json';
    }
    if (path.endsWith('.html') || path.endsWith('.htm') || path.endsWith('.xhtml')) {
      return 'html';
    }
    if (path.endsWith('.txt') || path.endsWith('.text') || path.endsWith('.log')) {
      return 'text';
    }
    return undefined;
  }

  private normalizeViewerKind(value: string): DocumentViewerKind | undefined {
    switch (value.trim().toLowerCase()) {
      case 'markdown':
        return 'markdown';
      case 'json':
        return 'json';
      case 'text':
        return 'text';
      case 'html':
        return 'html';
      default:
        return undefined;
    }
  }

  private isLocalFileLikeUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('file://') ||
      normalized.startsWith('datashare://') ||
      normalized.startsWith('content://') ||
      normalized.startsWith('/');
  }

  private resolveDisplayName(uri: string): string {
    const stripped = this.stripQueryAndFragment(uri);
    const slashIndex = Math.max(stripped.lastIndexOf('/'), stripped.lastIndexOf('\\'));
    const rawName = slashIndex >= 0 ? stripped.substring(slashIndex + 1) : stripped;
    const decodedName = this.safeDecode(rawName);
    return decodedName.trim().length > 0 ? decodedName.trim() : '文件';
  }

  private stripQueryAndFragment(url: string): string {
    const queryIndex = url.indexOf('?');
    const hashIndex = url.indexOf('#');
    let endIndex = url.length;
    if (queryIndex >= 0) {
      endIndex = Math.min(endIndex, queryIndex);
    }
    if (hashIndex >= 0) {
      endIndex = Math.min(endIndex, hashIndex);
    }
    return url.substring(0, endIndex);
  }

  private readQueryParam(url: string, name: string): string {
    const queryIndex = url.indexOf('?');
    if (queryIndex < 0) {
      return '';
    }
    const query = url.substring(queryIndex + 1).split('#')[0];
    const pairs = query.split('&');
    for (let index = 0; index < pairs.length; index += 1) {
      const pair = pairs[index];
      const separatorIndex = pair.indexOf('=');
      const key = separatorIndex >= 0 ? pair.substring(0, separatorIndex) : pair;
      if (this.safeDecode(key) === name) {
        const value = separatorIndex >= 0 ? pair.substring(separatorIndex + 1) : '';
        return this.safeDecode(value);
      }
    }
    return '';
  }

  private safeDecode(value: string): string {
    try {
      return decodeURIComponent(value.replace(/\+/g, ' '));
    } catch (_error) {
      return value;
    }
  }

  private normalizeMimeType(mimeType: string): string {
    const separatorIndex = mimeType.indexOf(';');
    const raw = separatorIndex >= 0 ? mimeType.substring(0, separatorIndex) : mimeType;
    return raw.trim().toLowerCase();
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private stringifyError(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
