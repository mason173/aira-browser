import { webview } from '@kit.ArkWeb';

export interface WebAppManifestDiscoveryResult {
  ok: boolean;
  reason: string;
  manifestUrl: string;
  documentUrl: string;
  documentTitle: string;
  appleTouchIconUrl: string;
  themeColor: string;
}

interface RawDiscoveryPayload {
  href: string;
  manifestHref: string;
  documentTitle: string;
  appleTouchIconHref: string;
  themeColor: string;
}

export class WebAppManifestDiscoveryService {
  async discover(controller: webview.WebviewController | undefined): Promise<WebAppManifestDiscoveryResult> {
    if (controller === undefined) {
      return this.buildEmpty('controller_missing');
    }
    try {
      const raw = await controller.runJavaScript(this.buildScript());
      return this.parseResult(this.normalizeRaw(raw));
    } catch (_error) {
      return this.buildEmpty('run_javascript_failed');
    }
  }

  buildScript(): string {
    return `
(() => {
  try {
    var manifestHref = '';
    var manifestLink = document.querySelector('link[rel~="manifest"]');
    if (manifestLink && typeof manifestLink.getAttribute === 'function') {
      manifestHref = manifestLink.href || manifestLink.getAttribute('href') || '';
    }
    var appleTouchIconHref = '';
    var appleLink = document.querySelector('link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]');
    if (appleLink) {
      appleTouchIconHref = appleLink.href || appleLink.getAttribute('href') || '';
    }
    var themeColor = '';
    var themeMeta = document.querySelector('meta[name="theme-color"]');
    if (themeMeta) {
      themeColor = themeMeta.getAttribute('content') || '';
    }
    return JSON.stringify({
      href: String(window.location.href || ''),
      manifestHref: String(manifestHref || ''),
      documentTitle: String(document.title || ''),
      appleTouchIconHref: String(appleTouchIconHref || ''),
      themeColor: String(themeColor || '')
    });
  } catch (error) {
    return '';
  }
})()
    `.trim();
  }

  parseResult(raw: string): WebAppManifestDiscoveryResult {
    if (raw.length === 0) {
      return this.buildEmpty('empty_script_result');
    }
    try {
      const parsed = JSON.parse(raw) as RawDiscoveryPayload;
      const documentUrl = String(parsed.href ?? '').trim();
      const manifestHref = String(parsed.manifestHref ?? '').trim();
      const manifestUrl = this.resolveAgainstBase(documentUrl, manifestHref);
      const appleTouchIconUrl = this.resolveAgainstBase(documentUrl, String(parsed.appleTouchIconHref ?? '').trim());
      return {
        ok: manifestUrl.length > 0,
        reason: manifestUrl.length > 0 ? 'manifest_found' : 'manifest_link_missing',
        manifestUrl: manifestUrl,
        documentUrl: documentUrl,
        documentTitle: String(parsed.documentTitle ?? '').trim(),
        appleTouchIconUrl: appleTouchIconUrl,
        themeColor: String(parsed.themeColor ?? '').trim()
      };
    } catch (_error) {
      return this.buildEmpty('parse_failed');
    }
  }

  private buildEmpty(reason: string): WebAppManifestDiscoveryResult {
    return {
      ok: false,
      reason: reason,
      manifestUrl: '',
      documentUrl: '',
      documentTitle: '',
      appleTouchIconUrl: '',
      themeColor: ''
    };
  }

  private normalizeRaw(raw: string): string {
    const trimmed = raw.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        return JSON.parse(trimmed) as string;
      } catch (_error) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  private resolveAgainstBase(baseUrl: string, candidate: string): string {
    if (candidate.length === 0) {
      return '';
    }
    if (/^https?:/i.test(candidate) || /^data:/i.test(candidate)) {
      return candidate;
    }
    if (baseUrl.length === 0) {
      return candidate;
    }
    if (candidate.startsWith('//')) {
      const protoMatch = /^([a-z]+:)/i.exec(baseUrl);
      const proto = protoMatch !== null ? protoMatch[1] : 'https:';
      return `${proto}${candidate}`;
    }
    const match = /^([a-z]+:\/\/[^/?#]+)(\/[^?#]*)?/i.exec(baseUrl);
    if (match === null) {
      return candidate;
    }
    const origin = match[1];
    const basePath = (match[2] ?? '/').substring(0, (match[2] ?? '/').lastIndexOf('/') + 1);
    if (candidate.startsWith('/')) {
      return `${origin}${candidate}`;
    }
    return `${origin}${basePath}${candidate}`;
  }
}
