import urlUtils from '@ohos.url';
import {
  SiteIconCandidate,
  SiteIconCandidateSource,
  SiteIconDocumentDiscovery
} from '../../common/models/SiteIconModels';
import { SiteIconResolutionPolicyService } from './SiteIconResolutionPolicyService';

interface HtmlLinkDescriptor {
  rel: string;
  href: string;
  sizes: string;
  type: string;
  purpose: string;
}

interface WebManifestIcon {
  src?: string;
  sizes?: string;
  type?: string;
  purpose?: string;
}

interface WebManifestFile {
  icons?: WebManifestIcon[];
}

const SVG_SIZE_SCORE: number = 1024;

export class SiteIconDiscoveryService {
  private readonly resolutionPolicyService: SiteIconResolutionPolicyService;

  constructor(resolutionPolicyService: SiteIconResolutionPolicyService = new SiteIconResolutionPolicyService()) {
    this.resolutionPolicyService = resolutionPolicyService;
  }

  buildDeclaredCandidate(
    iconUrl: string,
    source: SiteIconCandidateSource,
    sizes: string,
    type: string,
    purpose: string
  ): SiteIconCandidate | undefined {
    const normalized = iconUrl.trim();
    if (!/^https?:\/\//i.test(normalized)) {
      return undefined;
    }
    return this.createCandidate(normalized, source, sizes, type, purpose);
  }

  discoverFromDocument(pageUrl: string, html: string): SiteIconDocumentDiscovery {
    const links = this.extractLinkDescriptors(html);
    const manifestUrls: string[] = [];
    const iconCandidates: SiteIconCandidate[] = [];

    links.forEach((link: HtmlLinkDescriptor) => {
      const rel = this.normalizeRel(link.rel);
      const resolvedHref = this.resolveUrl(pageUrl, this.decodeHtmlAttribute(link.href));
      if (resolvedHref.length === 0) {
        return;
      }

      if (this.hasRelToken(rel, 'manifest')) {
        manifestUrls.push(resolvedHref);
        return;
      }

      if (rel.indexOf('apple-touch-icon') >= 0) {
        iconCandidates.push(this.createCandidate(resolvedHref, 'appleTouch', link.sizes, link.type, link.purpose));
        return;
      }

      if (this.hasRelToken(rel, 'icon') || this.hasRelToken(rel, 'shortcut icon')) {
        iconCandidates.push(this.createCandidate(resolvedHref, 'documentIcon', link.sizes, link.type, link.purpose));
      }
    });

    return {
      iconCandidates: this.resolutionPolicyService.rankCandidates(iconCandidates),
      manifestUrls: this.dedupeStrings(manifestUrls)
    };
  }

  discoverFromManifest(manifestUrl: string, payload: string): SiteIconCandidate[] {
    try {
      const manifest = JSON.parse(payload) as WebManifestFile;
      if (manifest.icons === undefined || !Array.isArray(manifest.icons)) {
        return [];
      }

      const candidates: SiteIconCandidate[] = [];
      manifest.icons.forEach((icon: WebManifestIcon) => {
        const src = icon.src ?? '';
        const resolvedSrc = this.resolveUrl(manifestUrl, this.decodeHtmlAttribute(src));
        if (resolvedSrc.length === 0) {
          return;
        }
        candidates.push(this.createCandidate(
          resolvedSrc,
          'manifest',
          icon.sizes ?? '',
          icon.type ?? '',
          icon.purpose ?? ''
        ));
      });
      return this.resolutionPolicyService.rankCandidates(candidates);
    } catch (_error) {
      return [];
    }
  }

  buildFallbackCandidates(domain: string, allowRemoteFallback: boolean): SiteIconCandidate[] {
    const safeDomain = domain.trim().toLowerCase();
    if (safeDomain.length === 0) {
      return [];
    }

    const candidates: SiteIconCandidate[] = [
      this.createCandidate(`https://${safeDomain}/android-chrome-512x512.png`, 'rootIcon', '512x512', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/icon-512.png`, 'rootIcon', '512x512', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/icon-512x512.png`, 'rootIcon', '512x512', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/android-chrome-192x192.png`, 'rootIcon', '192x192', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/icon-192.png`, 'rootIcon', '192x192', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/icon-192x192.png`, 'rootIcon', '192x192', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/apple-touch-icon.png`, 'rootAppleTouch', '180x180', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/apple-touch-icon-precomposed.png`, 'rootAppleTouch', '180x180', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/apple-touch-icon-180x180.png`, 'rootAppleTouch', '180x180', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/apple-touch-icon-167x167.png`, 'rootAppleTouch', '167x167', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/apple-touch-icon-152x152.png`, 'rootAppleTouch', '152x152', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/favicon.svg`, 'rootIcon', 'any', 'image/svg+xml', ''),
      this.createCandidate(`https://${safeDomain}/favicon-196x196.png`, 'rootIcon', '196x196', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/favicon-192x192.png`, 'rootIcon', '192x192', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/favicon-128x128.png`, 'rootIcon', '128x128', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/favicon-96x96.png`, 'rootIcon', '96x96', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/favicon.png`, 'rootIcon', '96x96', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/favicon-32x32.png`, 'rootIcon', '32x32', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/favicon-16x16.png`, 'rootIcon', '16x16', 'image/png', ''),
      this.createCandidate(`https://${safeDomain}/favicon.ico`, 'rootIcon', '32x32', 'image/x-icon', '')
    ];
    if (allowRemoteFallback) {
      candidates.push(this.createCandidate(`https://www.google.com/s2/favicons?domain=${safeDomain}&sz=256`,
        'remoteFallback', '256x256', 'image/png', ''));
      candidates.push(this.createCandidate(`https://www.google.com/s2/favicons?domain=${safeDomain}&sz=128`,
        'remoteFallback', '128x128', 'image/png', ''));
    }
    return this.resolutionPolicyService.rankCandidates(candidates);
  }

  private extractLinkDescriptors(html: string): HtmlLinkDescriptor[] {
    const links: HtmlLinkDescriptor[] = [];
    const linkPattern = /<link\b[^>]*>/gi;
    let linkMatch: RegExpExecArray | null = linkPattern.exec(html);
    while (linkMatch !== null) {
      const tag = linkMatch[0];
      const attrs = this.extractAttributes(tag);
      const rel = attrs['rel'] ?? '';
      const href = attrs['href'] ?? '';
      if (rel.length > 0 && href.length > 0) {
        links.push({
          rel: rel,
          href: href,
          sizes: attrs['sizes'] ?? '',
          type: attrs['type'] ?? '',
          purpose: attrs['purpose'] ?? ''
        });
      }
      linkMatch = linkPattern.exec(html);
    }
    return links;
  }

  private extractAttributes(tag: string): Record<string, string> {
    const attrs: Record<string, string> = {};
    const attrPattern = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/g;
    let attrMatch: RegExpExecArray | null = attrPattern.exec(tag);
    while (attrMatch !== null) {
      const key = attrMatch[1].toLowerCase();
      const value = attrMatch[3] ?? attrMatch[4] ?? attrMatch[5] ?? '';
      attrs[key] = value.trim();
      attrMatch = attrPattern.exec(tag);
    }
    return attrs;
  }

  private createCandidate(
    iconUrl: string,
    source: SiteIconCandidateSource,
    sizes: string,
    type: string,
    purpose: string
  ): SiteIconCandidate {
    const normalizedUrl = iconUrl.trim();
    return {
      url: normalizedUrl,
      source: source,
      size: this.resolveSizeScore(normalizedUrl, sizes, type),
      scalable: this.isScalableIcon(normalizedUrl, sizes, type),
      purpose: purpose.trim().toLowerCase()
    };
  }

  private resolveSizeScore(iconUrl: string, sizes: string, type: string): number {
    if (this.isScalableIcon(iconUrl, sizes, type)) {
      return SVG_SIZE_SCORE;
    }

    const parsedSize = this.parseLargestSize(sizes);
    if (parsedSize > 0) {
      return parsedSize;
    }

    return this.inferSizeFromUrl(iconUrl);
  }

  private parseLargestSize(sizes: string): number {
    const normalized = sizes.trim().toLowerCase();
    if (normalized.length === 0 || normalized === 'any') {
      return normalized === 'any' ? SVG_SIZE_SCORE : 0;
    }

    const sizePattern = /(\d+)\s*x\s*(\d+)/g;
    let largest = 0;
    let sizeMatch: RegExpExecArray | null = sizePattern.exec(normalized);
    while (sizeMatch !== null) {
      const width = Number(sizeMatch[1]);
      const height = Number(sizeMatch[2]);
      if (width > 0 && height > 0) {
        largest = Math.max(largest, Math.min(width, height));
      }
      sizeMatch = sizePattern.exec(normalized);
    }
    return largest;
  }

  private inferSizeFromUrl(iconUrl: string): number {
    const normalized = iconUrl.toLowerCase();
    const sizePattern = /(?:^|[^0-9])(\d{2,4})\s*x\s*(\d{2,4})(?:[^0-9]|$)/g;
    let largest = 0;
    let sizeMatch: RegExpExecArray | null = sizePattern.exec(normalized);
    while (sizeMatch !== null) {
      const width = Number(sizeMatch[1]);
      const height = Number(sizeMatch[2]);
      largest = Math.max(largest, Math.min(width, height));
      sizeMatch = sizePattern.exec(normalized);
    }
    if (largest > 0) {
      return largest;
    }

    if (normalized.includes('sz=256')) {
      return 256;
    }
    if (normalized.includes('sz=128')) {
      return 128;
    }
    if (normalized.includes('sz=64')) {
      return 64;
    }
    return 0;
  }

  private isScalableIcon(iconUrl: string, sizes: string, type: string): boolean {
    const normalizedUrl = iconUrl.toLowerCase();
    return sizes.trim().toLowerCase() === 'any' ||
      type.trim().toLowerCase().includes('svg') ||
      normalizedUrl.includes('.svg');
  }

  private resolveUrl(baseUrl: string, href: string): string {
    const normalizedHref = href.trim();
    if (normalizedHref.length === 0 || normalizedHref.startsWith('data:') || normalizedHref.startsWith('javascript:')) {
      return '';
    }
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(normalizedHref)) {
      return normalizedHref;
    }
    if (normalizedHref.startsWith('//')) {
      return `https:${normalizedHref}`;
    }

    try {
      const parsedBase = urlUtils.URL.parseURL(baseUrl);
      const origin = `${parsedBase.protocol}//${parsedBase.hostname}${parsedBase.port.length > 0 ? `:${parsedBase.port}` : ''}`;
      if (normalizedHref.startsWith('/')) {
        return `${origin}${normalizedHref}`;
      }

      const path = parsedBase.pathname;
      const basePath = path.endsWith('/') ? path : path.substring(0, path.lastIndexOf('/') + 1);
      return this.normalizePathUrl(`${origin}${basePath}${normalizedHref}`);
    } catch (_error) {
      return '';
    }
  }

  private normalizePathUrl(rawUrl: string): string {
    const parts = rawUrl.split('/');
    const normalizedParts: string[] = [];
    parts.forEach((part: string, index: number) => {
      if (index < 3 || part.length === 0 || part === '.') {
        normalizedParts.push(part);
        return;
      }
      if (part === '..') {
        if (normalizedParts.length > 3) {
          normalizedParts.pop();
        }
        return;
      }
      normalizedParts.push(part);
    });
    return normalizedParts.join('/');
  }

  private normalizeRel(rel: string): string {
    return rel.trim().toLowerCase().replace(/\s+/g, ' ');
  }

  private hasRelToken(rel: string, token: string): boolean {
    if (token.indexOf(' ') >= 0) {
      return rel === token;
    }
    return ` ${rel} `.indexOf(` ${token} `) >= 0;
  }

  private decodeHtmlAttribute(value: string): string {
    return value
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>');
  }

  private dedupeStrings(values: string[]): string[] {
    const result: string[] = [];
    values.forEach((value: string) => {
      if (value.length > 0 && result.indexOf(value) < 0) {
        result.push(value);
      }
    });
    return result;
  }
}
