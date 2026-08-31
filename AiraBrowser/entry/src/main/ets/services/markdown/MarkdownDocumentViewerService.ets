import { fileIo } from '@kit.CoreFileKit';
import buffer from '@ohos.buffer';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';

export const MARKDOWN_VIEWER_URL_PREFIX: string = 'aira://markdown-viewer';
export const MARKDOWN_CODE_BLOCK_URL: string = 'aira://markdown-code-block';
export const MARKDOWN_CODE_BLOCK_BACKGROUND_COLOR: string = '#0d1117';

const MARKDOWN_VIEWER_MAX_BYTES: number = 5 * 1024 * 1024;
const MARKDOWN_VIEWER_HIGHLIGHT_CSS_URL: string = 'resource://rawfile/highlight-github-dark.min.css';
const MARKDOWN_VIEWER_HIGHLIGHT_SCRIPT_URL: string = 'resource://rawfile/highlight.min.js';
const MARKDOWN_VIEWER_MARKDOWN_IT_SCRIPT_URL: string = 'resource://rawfile/markdown-it.min.js';
const MARKDOWN_VIEWER_MARKDOWN_BOOTSTRAP_SCRIPT_URL: string = 'resource://rawfile/markdown-render-bootstrap.js';

export interface MarkdownViewerUrlInfo {
  fileUri: string;
  displayName: string;
}

interface MarkdownViewerHtmlInput {
  title: string;
  sourceUri: string;
  bodyHtml: string;
  markdown?: string;
  theme?: MarkdownDocumentTheme;
  layout?: MarkdownViewerLayout;
  initialScrollY?: number;
}

type MarkdownViewerLayout = 'document' | 'code_block';

export interface MarkdownDocumentPayloadInput {
  title: string;
  sourceUri: string;
  markdown: string;
  baseUrl?: string;
  historyUrl?: string;
  theme?: MarkdownDocumentTheme;
}

export interface MarkdownCodeBlockPayloadInput {
  code: string;
  language: string;
  theme?: MarkdownDocumentTheme;
  initialScrollY?: number;
}

export interface MarkdownDocumentTheme {
  pageBackground: string;
  surfaceBackground?: string;
  primaryText: string;
  secondaryText: string;
  divider: string;
  pressedBackground?: string;
  accent?: string;
}

interface MarkdownCssColor {
  red: number;
  green: number;
  blue: number;
  alpha: number;
}

export class MarkdownDocumentViewerService {
  isMarkdownSourceUrl(url: string, mimeType: string = ''): boolean {
    const normalizedMimeType = this.normalizeMimeType(mimeType);
    if (normalizedMimeType === 'text/markdown' ||
      normalizedMimeType === 'text/x-markdown' ||
      normalizedMimeType === 'application/markdown') {
      return true;
    }
    const path = this.stripQueryAndFragment(url).toLowerCase();
    return path.endsWith('.md') ||
      path.endsWith('.markdown') ||
      path.endsWith('.mdown') ||
      path.endsWith('.mkd') ||
      path.endsWith('.mkdn');
  }

  isMarkdownViewerUrl(url: string): boolean {
    return url.trim().startsWith(MARKDOWN_VIEWER_URL_PREFIX);
  }

  buildViewerUrl(fileUri: string, displayName: string = ''): string {
    const normalizedFileUri = fileUri.trim();
    const title = displayName.trim().length > 0 ? displayName.trim() : this.resolveDisplayName(normalizedFileUri);
    return `${MARKDOWN_VIEWER_URL_PREFIX}?uri=${encodeURIComponent(normalizedFileUri)}&name=${encodeURIComponent(title)}`;
  }

  parseViewerUrl(url: string): MarkdownViewerUrlInfo | undefined {
    if (!this.isMarkdownViewerUrl(url)) {
      return undefined;
    }
    const fileUri = this.readQueryParam(url, 'uri');
    if (fileUri.length === 0) {
      return undefined;
    }
    const displayName = this.readQueryParam(url, 'name');
    return {
      fileUri: fileUri,
      displayName: displayName.length > 0 ? displayName : this.resolveDisplayName(fileUri)
    };
  }

  buildLoadingPayload(url: string): BrowserWebLoadDataPayload | undefined {
    const info = this.parseViewerUrl(url);
    if (info === undefined) {
      return undefined;
    }
    const htmlInput: MarkdownViewerHtmlInput = {
      title: info.displayName,
      sourceUri: info.fileUri,
      bodyHtml: '<p class="empty">正在读取 Markdown 文件...</p>'
    };
    return {
      data: this.buildHtml(htmlInput),
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: MARKDOWN_VIEWER_URL_PREFIX,
      historyUrl: url
    };
  }

  buildPayloadFromMarkdown(input: MarkdownDocumentPayloadInput): BrowserWebLoadDataPayload {
    const htmlInput: MarkdownViewerHtmlInput = {
      title: input.title,
      sourceUri: input.sourceUri,
      bodyHtml: '<div id="markdown-root"></div>',
      markdown: input.markdown,
      theme: input.theme
    };
    return this.buildDataPayload(
      htmlInput,
      input.baseUrl ?? MARKDOWN_VIEWER_URL_PREFIX,
      input.historyUrl ?? input.sourceUri
    );
  }

  buildCodeBlockPayload(input: MarkdownCodeBlockPayloadInput): BrowserWebLoadDataPayload {
    const htmlInput: MarkdownViewerHtmlInput = {
      title: 'Code preview',
      sourceUri: MARKDOWN_CODE_BLOCK_URL,
      bodyHtml: '<div id="markdown-root"></div>',
      markdown: this.buildFencedCodeMarkdown(input.code, input.language),
      theme: input.theme,
      layout: 'code_block',
      initialScrollY: input.initialScrollY
    };
    return this.buildDataPayload(htmlInput, MARKDOWN_CODE_BLOCK_URL, MARKDOWN_CODE_BLOCK_URL);
  }

  async buildPayloadFromViewerUrl(url: string): Promise<BrowserWebLoadDataPayload | undefined> {
    const info = this.parseViewerUrl(url);
    if (info === undefined) {
      return undefined;
    }
    try {
      const markdown = await this.readMarkdownFile(info.fileUri);
      const htmlInput: MarkdownViewerHtmlInput = {
        title: info.displayName,
        sourceUri: info.fileUri,
        bodyHtml: '<div id="markdown-root"></div>',
        markdown: markdown
      };
      return {
        data: this.buildHtml(htmlInput),
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: MARKDOWN_VIEWER_URL_PREFIX,
        historyUrl: url
      };
    } catch (error) {
      const htmlInput: MarkdownViewerHtmlInput = {
        title: info.displayName,
        sourceUri: info.fileUri,
        bodyHtml: this.buildErrorHtml(this.stringifyError(error))
      };
      return {
        data: this.buildHtml(htmlInput),
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: MARKDOWN_VIEWER_URL_PREFIX,
        historyUrl: url
      };
    }
  }

  private async readMarkdownFile(uri: string): Promise<string> {
    const stat = await fileIo.stat(uri);
    if (stat.isDirectory()) {
      throw new Error('请选择 Markdown 文件。');
    }
    if (stat.size <= 0) {
      return '';
    }
    if (stat.size > MARKDOWN_VIEWER_MAX_BYTES) {
      throw new Error('Markdown 文件超过 5 MB，暂不支持查看。');
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

  private buildHtml(input: MarkdownViewerHtmlInput): string {
    const title = input.title.trim().length > 0 ? input.title.trim() : 'Markdown 文件';
    const bodyClass = input.layout === 'code_block' ? 'code-preview' : '';
    const htmlClass = input.layout === 'code_block' ? 'code-preview' : '';
    const initialScrollY = this.resolveInitialScrollY(input);
    const bodyVisibilityAttribute = initialScrollY > 0 ? ' style="visibility:hidden"' : '';
    return `<!doctype html>
<html class="${htmlClass}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${this.escapeHtml(title)}</title>
<link rel="stylesheet" href="${MARKDOWN_VIEWER_HIGHLIGHT_CSS_URL}">
<style>
${this.buildCss()}
${this.buildThemeCss(input.theme)}
</style>
</head>
<body class="${bodyClass}"${bodyVisibilityAttribute}>
${input.bodyHtml}
${this.buildMarkdownRuntime(input.markdown)}
<script src="${MARKDOWN_VIEWER_HIGHLIGHT_SCRIPT_URL}"></script>
<script src="${MARKDOWN_VIEWER_MARKDOWN_BOOTSTRAP_SCRIPT_URL}"></script>
${this.buildInitialScrollRuntime(initialScrollY)}
</body>
</html>`;
  }

  private buildDataPayload(
    input: MarkdownViewerHtmlInput,
    baseUrl: string,
    historyUrl: string
  ): BrowserWebLoadDataPayload {
    return {
      data: this.buildHtml(input),
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: baseUrl,
      historyUrl: historyUrl
    };
  }

  private buildMarkdownRuntime(markdown: string | undefined): string {
    if (markdown === undefined) {
      return '';
    }
    return `<script type="application/json" id="markdown-source">${this.escapeScriptJson(markdown)}</script>
<script src="${MARKDOWN_VIEWER_MARKDOWN_IT_SCRIPT_URL}"></script>`;
  }

  private resolveInitialScrollY(input: MarkdownViewerHtmlInput): number {
    if (input.layout !== 'code_block' || input.initialScrollY === undefined ||
      !Number.isFinite(input.initialScrollY)) {
      return 0;
    }
    return Math.max(0, Math.floor(input.initialScrollY));
  }

  private buildInitialScrollRuntime(initialScrollY: number): string {
    if (initialScrollY <= 0) {
      return '';
    }
    return `<script>
(function restoreAiraCodePreviewScroll() {
  var target = ${initialScrollY};
  function applyScroll() {
    try {
      window.scrollTo(0, target);
      if (document.documentElement) {
        document.documentElement.scrollTop = target;
      }
      if (document.body) {
        document.body.scrollTop = target;
        document.body.style.visibility = 'visible';
      }
    } catch (_error) {
      if (document.body) {
        document.body.style.visibility = 'visible';
      }
    }
  }
  applyScroll();
  if (typeof requestAnimationFrame === 'function') {
    requestAnimationFrame(applyScroll);
  }
  setTimeout(applyScroll, 0);
})();
</script>`;
  }

  private buildCss(): string {
    return `:root {
  color-scheme: light dark;
  --bg: #f6f7f9;
  --paper: #ffffff;
  --text: #18202a;
  --muted: #68717d;
  --line: #dce2ea;
  --accent: #0f7b6c;
  --quote: #eef7f4;
  --quote-text: #18202a;
  --code-bg: #f0f3f6;
  --code-text: #18202a;
  --code-block-bg: #0d1117;
  --code-block-text: #e6edf3;
  --code-block-border: #30363d;
  --table-header-bg: #f0f3f6;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f1216;
    --text: #e8edf3;
    --muted: #9aa5b1;
    --line: #2b333d;
    --accent: #5fd1bd;
    --quote: #162723;
    --quote-text: #e8edf3;
    --code-bg: #222832;
    --code-text: #f0f4f8;
    --code-block-bg: #0d1117;
    --code-block-text: #e6edf3;
    --code-block-border: #30363d;
    --table-header-bg: #1a2029;
  }
}
* { box-sizing: border-box; }
html {
  height: 100%;
  min-height: 100%;
  background: var(--bg);
  scroll-padding-top: calc(env(safe-area-inset-top, 0px) + 14px);
}
html.code-preview {
  background: var(--code-block-bg);
}
body {
  margin: 0;
  min-height: 100vh;
  padding: calc(env(safe-area-inset-top, 0px) + 14px) 18px calc(env(safe-area-inset-bottom, 0px) + 92px);
  background: var(--bg);
  color: var(--text);
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "HarmonyOS Sans", sans-serif;
  line-height: 1.68;
}
body.code-preview {
  height: 100%;
  min-height: 100%;
  padding: 0;
  background: var(--code-block-bg);
  overflow: auto;
  --code-preview-syntax-text: #d4d4d4;
  --code-preview-syntax-tag: #569cd6;
  --code-preview-syntax-name: #4ec9b0;
  --code-preview-syntax-attr: #9cdcfe;
  --code-preview-syntax-string: #ce9178;
  --code-preview-syntax-number: #b5cea8;
  --code-preview-syntax-keyword: #c586c0;
  --code-preview-syntax-title: #dcdcaa;
  --code-preview-syntax-comment: #6a9955;
  --code-preview-syntax-meta: #d7ba7d;
  --code-preview-syntax-deletion: #f48771;
  --code-preview-syntax-addition: #b5cea8;
}
body.code-preview #markdown-root,
body.code-preview pre,
body.code-preview pre code {
  min-height: 100%;
}
body.code-preview #markdown-root {
  height: 100%;
}
body.code-preview pre {
  margin: 0;
  border: 0;
  border-radius: 0;
}
body.code-preview pre code,
body.code-preview pre code.hljs {
  padding: 12px 58px 12px 12px;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  tab-size: 2;
}
body.code-preview .hljs {
  background: var(--code-block-bg);
  color: var(--code-preview-syntax-text);
}
body.code-preview .hljs-tag,
body.code-preview .hljs-selector-tag {
  color: var(--code-preview-syntax-tag);
}
body.code-preview .hljs-name,
body.code-preview .hljs-type,
body.code-preview .hljs-selector-class,
body.code-preview .hljs-selector-id {
  color: var(--code-preview-syntax-name);
}
body.code-preview .hljs-attr,
body.code-preview .hljs-attribute,
body.code-preview .hljs-variable,
body.code-preview .hljs-template-variable {
  color: var(--code-preview-syntax-attr);
}
body.code-preview .hljs-string,
body.code-preview .hljs-regexp,
body.code-preview .hljs-meta .hljs-string {
  color: var(--code-preview-syntax-string);
}
body.code-preview .hljs-number,
body.code-preview .hljs-literal,
body.code-preview .hljs-built_in,
body.code-preview .hljs-symbol {
  color: var(--code-preview-syntax-number);
}
body.code-preview .hljs-keyword,
body.code-preview .hljs-doctag,
body.code-preview .hljs-template-tag,
body.code-preview .hljs-operator {
  color: var(--code-preview-syntax-keyword);
}
body.code-preview .hljs-title,
body.code-preview .hljs-title.class_,
body.code-preview .hljs-title.function_,
body.code-preview .hljs-section {
  color: var(--code-preview-syntax-title);
}
body.code-preview .hljs-comment,
body.code-preview .hljs-quote,
body.code-preview .hljs-code,
body.code-preview .hljs-formula {
  color: var(--code-preview-syntax-comment);
}
body.code-preview .hljs-meta,
body.code-preview .hljs-bullet {
  color: var(--code-preview-syntax-meta);
}
body.code-preview .hljs-addition {
  color: var(--code-preview-syntax-addition);
  background: rgba(181, 206, 168, 0.12);
}
body.code-preview .hljs-deletion {
  color: var(--code-preview-syntax-deletion);
  background: rgba(244, 135, 113, 0.12);
}
body.code-preview .hljs-emphasis {
  color: var(--code-preview-syntax-text);
  font-style: italic;
}
body.code-preview .hljs-strong {
  color: var(--code-preview-syntax-text);
  font-weight: 700;
}
h1, h2, h3, h4, h5, h6 {
  margin: 1.2em 0 0.45em;
  line-height: 1.25;
}
body > h1:first-of-type,
body > h2:first-of-type,
body > h3:first-of-type,
body > h4:first-of-type,
body > h5:first-of-type,
body > h6:first-of-type,
body > p:first-of-type,
body > ul:first-of-type,
body > ol:first-of-type,
body > blockquote:first-of-type,
body > pre:first-of-type {
  margin-top: 0;
}
p { margin: 0 0 1em; }
a { color: var(--accent); text-decoration-thickness: 1px; text-underline-offset: 3px; }
ul, ol { margin: 0 0 1em; padding-left: 1.45em; }
li { margin: 0.25em 0; }
figure {
  margin: 0 0 1em;
}
figure img {
  display: block;
  max-width: 100%;
  height: auto;
}
figcaption {
  margin-top: 6px;
  color: var(--muted);
  font-size: 0.88em;
  line-height: 1.45;
  text-align: center;
}
blockquote {
  margin: 0 0 1em;
  padding: 10px 14px;
  border-left: 4px solid var(--accent);
  background: var(--quote);
  border-radius: 0 8px 8px 0;
  color: var(--quote-text);
}
pre {
  margin: 0 0 1em;
  padding: 0;
  overflow: auto;
  background: var(--code-block-bg);
  border-radius: 8px;
  border: 1px solid var(--code-block-border);
}
code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.92em;
}
p code, li code, blockquote code, td code, th code {
  background: var(--code-bg);
  border: 1px solid var(--line);
  border-radius: 5px;
  color: var(--code-text);
  padding: 1px 5px;
}
pre code {
  display: block;
  padding: 14px;
  white-space: pre;
  color: var(--code-block-text);
}
pre code.hljs {
  padding: 14px;
  background: var(--code-block-bg);
}
hr {
  border: 0;
  border-top: 1px solid var(--line);
  margin: 24px 0;
}
table {
  width: 100%;
  border-collapse: collapse;
  margin: 0 0 1em;
  display: block;
  overflow-x: auto;
}
th, td {
  border: 1px solid var(--line);
  padding: 7px 9px;
  text-align: left;
}
th { background: var(--table-header-bg); }
img {
  max-width: 100%;
  height: auto;
}
.empty, .error {
  color: var(--muted);
}
.error {
  border: 1px solid var(--line);
  background: var(--code-bg);
  border-radius: 8px;
  padding: 12px;
}
@media (max-width: 520px) {
  body:not(.code-preview) {
    padding: calc(env(safe-area-inset-top, 0px) + 12px) 14px calc(env(safe-area-inset-bottom, 0px) + 88px);
  }
}`;
  }

  private buildFencedCodeMarkdown(code: string, language: string): string {
    const normalizedLanguage = language.replace(/[^A-Za-z0-9_-]/g, '').substring(0, 32);
    let longestFenceRun: number = 0;
    let currentFenceRun: number = 0;
    for (let index = 0; index < code.length; index += 1) {
      if (code.charAt(index) === '`') {
        currentFenceRun += 1;
        longestFenceRun = Math.max(longestFenceRun, currentFenceRun);
      } else {
        currentFenceRun = 0;
      }
    }
    const fence = '`'.repeat(Math.max(3, longestFenceRun + 1));
    return `${fence}${normalizedLanguage}\n${code}\n${fence}`;
  }

  private buildThemeCss(theme: MarkdownDocumentTheme | undefined): string {
    if (theme === undefined) {
      return '';
    }
    const pageBackground = this.resolveCssColor(theme.pageBackground, '#f6f7f9');
    const surfaceBackground = this.resolveCssColor(theme.surfaceBackground, pageBackground);
    const primaryText = this.resolveCssColor(theme.primaryText, '#18202a');
    const secondaryText = this.resolveCssColor(theme.secondaryText, '#68717d');
    const divider = this.resolveCssColor(theme.divider, '#dce2ea');
    const pressedBackground = this.resolveCssColor(theme.pressedBackground, '#f0f3f6');
    const accent = this.resolveCssColor(theme.accent, '#0f7b6c');
    const isDarkTheme = this.isDarkTheme(pageBackground, primaryText);
    const quoteBackground = this.blendCssColors(accent, surfaceBackground, isDarkTheme ? 0.16 : 0.1, pressedBackground);
    const codeBackground = this.blendCssColors(primaryText, surfaceBackground, isDarkTheme ? 0.11 : 0.07,
      pressedBackground);
    const tableHeaderBackground = this.blendCssColors(primaryText, surfaceBackground, isDarkTheme ? 0.08 : 0.045,
      pressedBackground);
    const codeBlockBorder = isDarkTheme ? 'rgba(255,255,255,0.16)' : 'rgba(15,23,42,0.18)';
    return `:root {
  --bg: ${pageBackground};
  --paper: ${surfaceBackground};
  --text: ${primaryText};
  --muted: ${secondaryText};
  --line: ${divider};
  --accent: ${accent};
  --quote: ${quoteBackground};
  --quote-text: ${primaryText};
  --code-bg: ${codeBackground};
  --code-text: ${primaryText};
  --code-block-bg: #0d1117;
  --code-block-text: #e6edf3;
  --code-block-border: ${codeBlockBorder};
  --table-header-bg: ${tableHeaderBackground};
}`;
  }

  private buildErrorHtml(message: string): string {
    const normalizedMessage = message.trim().length > 0 ? message.trim() : 'Markdown 文件读取失败。';
    return `<p class="error">${this.escapeHtml(normalizedMessage)}</p>`;
  }

  private resolveDisplayName(uri: string): string {
    const normalized = this.stripQueryAndFragment(uri);
    const slashIndex = normalized.lastIndexOf('/');
    const fileName = slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized;
    return this.safeDecode(fileName).trim().length > 0 ? this.safeDecode(fileName).trim() : 'Markdown 文件';
  }

  private readQueryParam(url: string, key: string): string {
    const queryIndex = url.indexOf('?');
    if (queryIndex < 0) {
      return '';
    }
    const query = url.substring(queryIndex + 1).split('#')[0];
    const pairs = query.split('&');
    for (let index = 0; index < pairs.length; index += 1) {
      const pair = pairs[index];
      const separatorIndex = pair.indexOf('=');
      const rawKey = separatorIndex >= 0 ? pair.substring(0, separatorIndex) : pair;
      if (this.safeDecode(rawKey) === key) {
        return this.safeDecode(separatorIndex >= 0 ? pair.substring(separatorIndex + 1) : '');
      }
    }
    return '';
  }

  private resolveCssColor(value: string | undefined, fallback: string): string {
    const normalized = value?.trim() ?? '';
    const cssColor = this.normalizeCssColor(normalized);
    if (cssColor.length > 0) {
      return cssColor;
    }
    const fallbackCssColor = this.normalizeCssColor(fallback);
    return fallbackCssColor.length > 0 ? fallbackCssColor : fallback;
  }

  private normalizeCssColor(value: string): string {
    if (!this.isSafeCssColor(value)) {
      return '';
    }
    const hex = this.normalizeHexColor(value);
    if (hex.length === 8) {
      const alpha = parseInt(hex.substring(0, 2), 16) / 255;
      const red = parseInt(hex.substring(2, 4), 16);
      const green = parseInt(hex.substring(4, 6), 16);
      const blue = parseInt(hex.substring(6, 8), 16);
      return this.formatRgba(red, green, blue, alpha);
    }
    return value;
  }

  private isSafeCssColor(value: string): boolean {
    if (value.length === 0 || value.indexOf(';') >= 0 || value.indexOf('{') >= 0 || value.indexOf('}') >= 0) {
      return false;
    }
    if (value.match(/^#[0-9a-fA-F]{3,8}$/) !== null) {
      return true;
    }
    if (value.match(/^rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$/) !== null) {
      return true;
    }
    return value === 'transparent' || value === 'currentColor';
  }

  private blendCssColors(foreground: string, background: string, amount: number, fallback: string): string {
    const foregroundColor = this.parseCssColor(foreground);
    const backgroundColor = this.parseCssColor(background);
    if (foregroundColor === undefined || backgroundColor === undefined) {
      return fallback;
    }
    const safeAmount = Math.min(1, Math.max(0, amount));
    const foregroundAlpha = foregroundColor.alpha * safeAmount;
    const backgroundAlpha = backgroundColor.alpha * (1 - foregroundAlpha);
    const alpha = foregroundAlpha + backgroundAlpha;
    if (alpha <= 0) {
      return 'rgba(0,0,0,0)';
    }
    const red = Math.round((foregroundColor.red * foregroundAlpha + backgroundColor.red * backgroundAlpha) / alpha);
    const green =
      Math.round((foregroundColor.green * foregroundAlpha + backgroundColor.green * backgroundAlpha) / alpha);
    const blue = Math.round((foregroundColor.blue * foregroundAlpha + backgroundColor.blue * backgroundAlpha) / alpha);
    return this.formatRgba(red, green, blue, alpha);
  }

  private isDarkTheme(background: string, text: string): boolean {
    const backgroundColor = this.parseCssColor(background);
    const textColor = this.parseCssColor(text);
    if (backgroundColor === undefined || textColor === undefined) {
      return false;
    }
    return this.relativeLuminance(textColor) > this.relativeLuminance(backgroundColor);
  }

  private parseCssColor(value: string): MarkdownCssColor | undefined {
    const normalized = value.trim();
    const hex = this.normalizeHexColor(normalized);
    if (hex.length === 3 || hex.length === 4) {
      const red = parseInt(hex.charAt(0) + hex.charAt(0), 16);
      const green = parseInt(hex.charAt(1) + hex.charAt(1), 16);
      const blue = parseInt(hex.charAt(2) + hex.charAt(2), 16);
      const alpha = hex.length === 4 ? parseInt(hex.charAt(3) + hex.charAt(3), 16) / 255 : 1;
      return { red: red, green: green, blue: blue, alpha: alpha };
    }
    if (hex.length === 6) {
      return {
        red: parseInt(hex.substring(0, 2), 16),
        green: parseInt(hex.substring(2, 4), 16),
        blue: parseInt(hex.substring(4, 6), 16),
        alpha: 1
      };
    }
    const rgbMatch = normalized.match(/^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*(0|1|0?\.\d+))?\s*\)$/);
    if (rgbMatch !== null) {
      return {
        red: this.clampColorChannel(Number(rgbMatch[1])),
        green: this.clampColorChannel(Number(rgbMatch[2])),
        blue: this.clampColorChannel(Number(rgbMatch[3])),
        alpha: rgbMatch[4] === undefined ? 1 : Math.min(1, Math.max(0, Number(rgbMatch[4])))
      };
    }
    return undefined;
  }

  private normalizeHexColor(value: string): string {
    if (!value.startsWith('#')) {
      return '';
    }
    const hex = value.substring(1);
    return hex.match(/^[0-9a-fA-F]{3,8}$/) !== null ? hex : '';
  }

  private formatRgba(red: number, green: number, blue: number, alpha: number): string {
    const normalizedAlpha = Math.round(Math.min(1, Math.max(0, alpha)) * 1000) / 1000;
    return `rgba(${this.clampColorChannel(red)},${this.clampColorChannel(green)},${this.clampColorChannel(blue)},${normalizedAlpha})`;
  }

  private clampColorChannel(value: number): number {
    return Math.min(255, Math.max(0, Math.round(value)));
  }

  private relativeLuminance(color: MarkdownCssColor): number {
    return 0.2126 * this.linearizeColorChannel(color.red) +
      0.7152 * this.linearizeColorChannel(color.green) +
      0.0722 * this.linearizeColorChannel(color.blue);
  }

  private linearizeColorChannel(value: number): number {
    const normalized = this.clampColorChannel(value) / 255;
    if (normalized <= 0.03928) {
      return normalized / 12.92;
    }
    return Math.pow((normalized + 0.055) / 1.055, 2.4);
  }

  private normalizeMimeType(mimeType: string): string {
    return mimeType.split(';')[0].trim().toLowerCase();
  }

  private stripQueryAndFragment(value: string): string {
    return value.split('?')[0].split('#')[0];
  }

  private safeDecode(value: string): string {
    try {
      return decodeURIComponent(value.replace(/\+/g, ' '));
    } catch (_error) {
      return value;
    }
  }

  private escapeHtml(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private escapeScriptJson(value: string): string {
    return JSON.stringify(value)
      .replace(/&/g, '\\u0026')
      .replace(/</g, '\\u003c')
      .replace(/>/g, '\\u003e')
      .replace(/\u2028/g, '\\u2028')
      .replace(/\u2029/g, '\\u2029');
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
