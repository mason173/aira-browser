import { webview } from '@kit.ArkWeb';
import {
  SiteIconCandidate,
  SiteIconCandidateSource,
  SiteIconResult
} from '../../common/models/SiteIconModels';
import { SiteIconDiscoveryService } from './SiteIconDiscoveryService';
import { SiteIconResolutionPolicyService } from './SiteIconResolutionPolicyService';
import { SiteIconService } from './SiteIconService';

interface SiteIconPageLinkPayload {
  url?: string;
  source?: string;
  sizes?: string;
  type?: string;
  purpose?: string;
}

interface SiteIconPageDiscoveryPayload {
  documentUrl?: string;
  candidates?: SiteIconPageLinkPayload[];
  manifestPending?: boolean;
}

interface SiteIconCurrentPageDiscoveryResult {
  documentUrl: string;
  candidates: SiteIconCandidate[];
  manifestPending: boolean;
}

export interface SiteIconCurrentPageCollectionResult {
  domain: string;
  candidateCount: number;
  resolved?: SiteIconResult;
}

const MAX_PAGE_ICON_CANDIDATES: number = 12;
const MAX_MANIFEST_ICON_CANDIDATES: number = 12;
const MAX_MANIFEST_TEXT_LENGTH: number = 128 * 1024;
const MANIFEST_POLL_DELAYS_MS: number[] = [250, 650];

export class SiteIconCurrentPageDiscoveryService {
  private readonly siteIconService: SiteIconService;
  private readonly discoveryService: SiteIconDiscoveryService;
  private readonly resolutionPolicyService: SiteIconResolutionPolicyService;
  private manifestTokenSequence: number = 0;

  constructor(
    siteIconService: SiteIconService = new SiteIconService(),
    discoveryService: SiteIconDiscoveryService = new SiteIconDiscoveryService(),
    resolutionPolicyService: SiteIconResolutionPolicyService = new SiteIconResolutionPolicyService()
  ) {
    this.siteIconService = siteIconService;
    this.discoveryService = discoveryService;
    this.resolutionPolicyService = resolutionPolicyService;
  }

  async collect(
    controller: webview.WebviewController,
    expectedDocumentUrl: string
  ): Promise<SiteIconCurrentPageCollectionResult | undefined> {
    const manifestToken = this.buildManifestToken();
    const initial = await this.discover(controller, manifestToken);
    if (!this.isExpectedDocument(initial.documentUrl, expectedDocumentUrl)) {
      return undefined;
    }
    let candidateCount = initial.candidates.length;
    let resolved = await this.siteIconService.ingestPageCandidates(
      initial.documentUrl,
      initial.candidates
    );
    if (initial.manifestPending) {
      const manifest = await this.pollManifestCandidates(controller, expectedDocumentUrl, manifestToken);
      if (manifest !== undefined) {
        candidateCount += manifest.candidates.length;
        if (manifest.candidates.length > 0) {
          resolved = await this.siteIconService.ingestPageCandidates(
            manifest.documentUrl,
            manifest.candidates
          ) ?? resolved;
        }
      }
    }
    return {
      domain: this.siteIconService.resolveDomain(initial.documentUrl),
      candidateCount: candidateCount,
      resolved: resolved
    };
  }

  private async discover(
    controller: webview.WebviewController,
    manifestToken: string
  ): Promise<SiteIconCurrentPageDiscoveryResult> {
    try {
      const rawResult = await controller.runJavaScript(this.buildDiscoveryScript(manifestToken));
      return this.parseResult(rawResult);
    } catch (_error) {
      return this.buildEmptyResult();
    }
  }

  private async readManifestCandidates(
    controller: webview.WebviewController,
    manifestToken: string
  ): Promise<SiteIconCurrentPageDiscoveryResult> {
    try {
      const rawResult = await controller.runJavaScript(this.buildManifestReadScript(manifestToken));
      return this.parseResult(rawResult);
    } catch (_error) {
      return this.buildEmptyResult();
    }
  }

  private buildDiscoveryScript(manifestToken: string): string {
    const tokenLiteral = JSON.stringify(manifestToken);
    return `
(() => {
  try {
    var token = ${tokenLiteral};
    var documentUrl = String(window.location.href || '');
    var candidates = [];
    var seenIndex = Object.create(null);
    var links = document.querySelectorAll('link[rel][href]');
    for (var index = 0; index < links.length && candidates.length < ${MAX_PAGE_ICON_CANDIDATES}; index += 1) {
      var link = links[index];
      var rel = String(link.getAttribute('rel') || '').trim().toLowerCase().replace(/\\s+/g, ' ');
      var source = '';
      if (rel.indexOf('apple-touch-icon') >= 0) {
        source = 'appleTouch';
      } else if ((' ' + rel + ' ').indexOf(' icon ') >= 0) {
        source = 'documentIcon';
      }
      if (!source) {
        continue;
      }
      var href = String(link.href || link.getAttribute('href') || '').trim();
      if (!/^https?:/i.test(href)) {
        continue;
      }
      var descriptor = {
        url: href,
        source: source,
        sizes: String(link.getAttribute('sizes') || ''),
        type: String(link.getAttribute('type') || ''),
        purpose: String(link.getAttribute('purpose') || '')
      };
      var duplicateIndex = seenIndex[href];
      if (typeof duplicateIndex === 'number') {
        if (source === 'appleTouch' && candidates[duplicateIndex].source !== 'appleTouch') {
          candidates[duplicateIndex] = descriptor;
        }
        continue;
      }
      seenIndex[href] = candidates.length;
      candidates.push(descriptor);
    }

    var manifestLink = document.querySelector('link[rel~="manifest"][href]');
    var manifestUrl = manifestLink ? String(manifestLink.href || manifestLink.getAttribute('href') || '').trim() : '';
    var shouldFetchManifest = /^https?:/i.test(manifestUrl);
    window.__airaFaviconManifestProbe = {
      token: token,
      documentUrl: documentUrl,
      manifestPending: shouldFetchManifest,
      candidates: []
    };

    if (shouldFetchManifest && typeof fetch === 'function') {
      fetch(manifestUrl, { credentials: 'include', cache: 'force-cache' })
        .then(function (response) {
          if (!response || !response.ok) {
            throw new Error('manifest_response_invalid');
          }
          return response.text();
        })
        .then(function (text) {
          if (typeof text !== 'string' || text.length <= 0 || text.length > ${MAX_MANIFEST_TEXT_LENGTH}) {
            throw new Error('manifest_payload_invalid');
          }
          var parsed = JSON.parse(text);
          var icons = parsed && Array.isArray(parsed.icons) ? parsed.icons : [];
          var manifestCandidates = [];
          var manifestSeen = Object.create(null);
          for (var iconIndex = 0;
            iconIndex < icons.length && manifestCandidates.length < ${MAX_MANIFEST_ICON_CANDIDATES};
            iconIndex += 1) {
            var icon = icons[iconIndex] || {};
            var src = String(icon.src || '').trim();
            if (!src) {
              continue;
            }
            var resolved = '';
            try {
              resolved = String(new URL(src, manifestUrl).href || '');
            } catch (_error) {
              resolved = '';
            }
            if (!/^https?:/i.test(resolved) || manifestSeen[resolved] === true) {
              continue;
            }
            manifestSeen[resolved] = true;
            manifestCandidates.push({
              url: resolved,
              source: 'manifest',
              sizes: String(icon.sizes || ''),
              type: String(icon.type || ''),
              purpose: String(icon.purpose || '')
            });
          }
          var state = window.__airaFaviconManifestProbe;
          if (state && state.token === token && state.documentUrl === documentUrl) {
            state.manifestPending = false;
            state.candidates = manifestCandidates;
          }
        })
        .catch(function (_error) {
          var state = window.__airaFaviconManifestProbe;
          if (state && state.token === token && state.documentUrl === documentUrl) {
            state.manifestPending = false;
            state.candidates = [];
          }
        });
    }

    return JSON.stringify({
      documentUrl: documentUrl,
      candidates: candidates,
      manifestPending: shouldFetchManifest
    });
  } catch (_error) {
    return '';
  }
})()
    `.trim();
  }

  private buildManifestReadScript(manifestToken: string): string {
    const tokenLiteral = JSON.stringify(manifestToken);
    return `
(() => {
  try {
    var token = ${tokenLiteral};
    var state = window.__airaFaviconManifestProbe;
    if (!state || state.token !== token) {
      return '';
    }
    return JSON.stringify({
      documentUrl: String(state.documentUrl || ''),
      candidates: Array.isArray(state.candidates) ? state.candidates : [],
      manifestPending: state.manifestPending === true
    });
  } catch (_error) {
    return '';
  }
})()
    `.trim();
  }

  private parseResult(rawResult: string): SiteIconCurrentPageDiscoveryResult {
    const normalized = this.normalizeRawResult(rawResult);
    if (normalized.length === 0) {
      return this.buildEmptyResult();
    }
    try {
      const parsed = JSON.parse(normalized) as SiteIconPageDiscoveryPayload;
      const rawCandidates = Array.isArray(parsed.candidates) ? parsed.candidates : [];
      const candidates: SiteIconCandidate[] = [];
      for (let index = 0; index < rawCandidates.length; index += 1) {
        const descriptor = rawCandidates[index];
        const source = this.normalizeSource(descriptor.source ?? '');
        if (source === undefined) {
          continue;
        }
        const candidate = this.discoveryService.buildDeclaredCandidate(
          descriptor.url ?? '',
          source,
          descriptor.sizes ?? '',
          descriptor.type ?? '',
          descriptor.purpose ?? ''
        );
        if (candidate !== undefined) {
          candidates.push(candidate);
        }
      }
      return {
        documentUrl: String(parsed.documentUrl ?? '').trim(),
        candidates: this.resolutionPolicyService.rankCandidates(candidates),
        manifestPending: parsed.manifestPending === true
      };
    } catch (_error) {
      return this.buildEmptyResult();
    }
  }

  private normalizeRawResult(rawResult: string): string {
    const trimmed = rawResult.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        return JSON.parse(trimmed) as string;
      } catch (_error) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  private normalizeSource(source: string): SiteIconCandidateSource | undefined {
    switch (source.trim()) {
      case 'appleTouch':
        return 'appleTouch';
      case 'manifest':
        return 'manifest';
      case 'documentIcon':
        return 'documentIcon';
      default:
        return undefined;
    }
  }

  private buildEmptyResult(): SiteIconCurrentPageDiscoveryResult {
    return {
      documentUrl: '',
      candidates: [],
      manifestPending: false
    };
  }

  private async pollManifestCandidates(
    controller: webview.WebviewController,
    expectedDocumentUrl: string,
    manifestToken: string
  ): Promise<SiteIconCurrentPageDiscoveryResult | undefined> {
    for (let index = 0; index < MANIFEST_POLL_DELAYS_MS.length; index += 1) {
      await this.delay(MANIFEST_POLL_DELAYS_MS[index]);
      const result = await this.readManifestCandidates(controller, manifestToken);
      if (!this.isExpectedDocument(result.documentUrl, expectedDocumentUrl)) {
        return undefined;
      }
      if (!result.manifestPending || result.candidates.length > 0) {
        return result;
      }
    }
    return undefined;
  }

  private isExpectedDocument(actualDocumentUrl: string, expectedDocumentUrl: string): boolean {
    const actualDomain = this.siteIconService.resolveDomain(actualDocumentUrl);
    const expectedDomain = this.siteIconService.resolveDomain(expectedDocumentUrl);
    return actualDomain.length > 0 && actualDomain === expectedDomain;
  }

  private buildManifestToken(): string {
    this.manifestTokenSequence += 1;
    return `${Date.now()}-${this.manifestTokenSequence}`;
  }

  private delay(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, Math.max(0, delayMs));
    });
  }
}
