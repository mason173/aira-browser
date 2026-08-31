export interface OfflinePageHtmlSanitizeInput {
  html: string;
  originalUrl: string;
  title: string;
  siteName: string;
  savedAt: number;
}

export interface OfflinePageHtmlSanitizeResult {
  html: string;
  changed: boolean;
}

const OFFLINE_PAGE_STYLE = `
<style id="aira-offline-style">
  * {
    box-sizing: border-box;
  }
  :root {
    color-scheme: light dark;
    font-family: system-ui, -apple-system, BlinkMacSystemFont, "HarmonyOS Sans", sans-serif;
	    background: #f0f2f4;
	    color: #1f2328;
    width: 100%;
    min-width: 0;
  }
  html {
    width: 100%;
    min-width: 0;
  }
  body {
    width: 100%;
    min-width: 0;
    margin: 0;
    padding: 18px 0 40px;
    line-height: 1.72;
    word-break: break-word;
    overflow-wrap: anywhere;
    overflow-x: hidden;
  }
  img, picture, video {
    max-width: 100%;
    height: auto;
  }
  pre, code {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  a {
    color: #1d5fbf;
  }
  .aira-offline-missing-image {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 96px;
    border: 1px dashed rgba(89, 99, 110, 0.45);
    border-radius: 8px;
    color: #59636e;
	    background: rgba(255, 255, 255, 0.72);
  }
  body > * {
    max-width: 100%;
  }
  @media (prefers-color-scheme: dark) {
    :root {
	      background: #0b0d10;
	      color: #e6edf3;
	    }
	    a {
	      color: #7db2ff;
	    }
	    .aira-offline-missing-image {
	      border-color: rgba(255, 255, 255, 0.28);
	      color: #aab6c3;
	      background: rgba(36, 42, 49, 0.72);
	    }
	  }
</style>`;

const OFFLINE_PAGE_VIEWER_COMPAT_STYLE = `
<style id="aira-offline-viewer-compat-style">
  * {
    box-sizing: border-box;
  }
  html, body {
    width: 100% !important;
    min-width: 0 !important;
    max-width: none !important;
  }
  body {
    margin-left: 0 !important;
    margin-right: 0 !important;
    overflow-x: hidden !important;
  }
  img, picture, video, canvas, table, pre {
    max-width: 100% !important;
  }
</style>`;

export class OfflinePageHtmlSanitizerService {
  sanitize(input: OfflinePageHtmlSanitizeInput): OfflinePageHtmlSanitizeResult {
    const source = input.html.trim();
    if (source.length === 0) {
      return {
        html: '',
        changed: false
      };
    }
    let next = source;
    const before = next;
    next = this.removeDangerousBlocks(next);
    next = this.removeEventHandlerAttributes(next);
    next = this.addImageFallbacks(next);
    next = this.injectBaseMetadata(next, input);
    return {
      html: next,
      changed: next !== before
    };
  }

  normalizeForViewer(html: string): string {
    const source = html.trim();
    if (source.length === 0) {
      return '';
    }
    let next = this.removeOfflineBanner(source);
    next = this.removeDangerousBlocks(next);
    next = this.removeEventHandlerAttributes(next);
    next = this.addImageFallbacks(next);
    next = this.injectViewerCompatStyle(next);
    next = this.injectViewportMeta(next);
    return next;
  }

  private removeDangerousBlocks(html: string): string {
    return html
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<iframe\b[^>]*>[\s\S]*?<\/iframe>/gi, this.buildMissingFramePlaceholder())
      .replace(/<form\b[^>]*>[\s\S]*?<\/form>/gi, '')
      .replace(/<object\b[^>]*>[\s\S]*?<\/object>/gi, '')
      .replace(/<embed\b[^>]*>/gi, '')
      .replace(/<base\b[^>]*>/gi, '')
      .replace(/<meta\b[^>]*http-equiv=["']?refresh["']?[^>]*>/gi, '');
  }

  private removeEventHandlerAttributes(html: string): string {
    return html
      .replace(/\s+on[a-z]+\s*=\s*"[^"]*"/gi, '')
      .replace(/\s+on[a-z]+\s*=\s*'[^']*'/gi, '')
      .replace(/\s+on[a-z]+\s*=\s*[^\s>]+/gi, '');
  }

  private addImageFallbacks(html: string): string {
    return html.replace(/<img\b([^>]*)>/gi, (match: string, attrs: string): string => {
      if (/onerror\s*=/i.test(attrs)) {
        return match;
      }
      return `<img${attrs} onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'aira-offline-missing-image',textContent:'图片未能保存'}));">`;
    });
  }

  private injectBaseMetadata(html: string, input: OfflinePageHtmlSanitizeInput): string {
    const headInjection = `${OFFLINE_PAGE_STYLE}\n${this.buildViewportMeta(html)}` +
      `\n<meta name="aira-offline-original-url" content="${this.escapeAttribute(input.originalUrl)}">`;
    let next = html;
    if (/<head\b[^>]*>/i.test(next)) {
      next = next.replace(/<head\b([^>]*)>/i, `<head$1>\n${headInjection}`);
    } else {
      next = next.replace(/<html\b([^>]*)>/i, `<html$1>\n<head>${headInjection}</head>`);
    }
    return next;
  }

  private injectViewerCompatStyle(html: string): string {
    if (/<style\b[^>]*id=["']aira-offline-viewer-compat-style["'][^>]*>/i.test(html)) {
      return html;
    }
    if (/<head\b[^>]*>/i.test(html)) {
      return html.replace(/<head\b([^>]*)>/i, `<head$1>\n${OFFLINE_PAGE_VIEWER_COMPAT_STYLE}`);
    }
    if (/<html\b([^>]*)>/i.test(html)) {
      return html.replace(/<html\b([^>]*)>/i, `<html$1>\n<head>${OFFLINE_PAGE_VIEWER_COMPAT_STYLE}</head>`);
    }
    return `${OFFLINE_PAGE_VIEWER_COMPAT_STYLE}\n${html}`;
  }

  private injectViewportMeta(html: string): string {
    const viewportMeta = this.buildViewportMeta(html);
    if (viewportMeta.length === 0) {
      return html;
    }
    if (/<head\b[^>]*>/i.test(html)) {
      return html.replace(/<head\b([^>]*)>/i, `<head$1>\n${viewportMeta}`);
    }
    if (/<html\b([^>]*)>/i.test(html)) {
      return html.replace(/<html\b([^>]*)>/i, `<html$1>\n<head>${viewportMeta}</head>`);
    }
    return `${viewportMeta}\n${html}`;
  }

  private removeOfflineBanner(html: string): string {
    return html.replace(/<section\b[^>]*class=["'][^"']*\baira-offline-banner\b[^"']*["'][^>]*>[\s\S]*?<\/section>/gi, '');
  }

  private buildViewportMeta(html: string): string {
    if (/<meta\b[^>]*name=["']?viewport["']?[^>]*>/i.test(html)) {
      return '';
    }
    return '<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">';
  }

  private buildMissingFramePlaceholder(): string {
    return '<div class="aira-offline-missing-image">嵌入内容未保存</div>';
  }

  private escapeText(value: string): string {
    return value
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  private escapeAttribute(value: string): string {
    return this.escapeText(value).replace(/"/g, '&quot;');
  }
}
