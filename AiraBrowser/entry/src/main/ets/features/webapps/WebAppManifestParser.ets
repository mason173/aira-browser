export type WebAppManifestDisplay = 'browser' | 'minimal-ui' | 'standalone' | 'fullscreen';

interface ParsedUrl {
  origin: string;
  path: string;
}

export interface WebAppManifestIcon {
  src: string;
  sizes: string;
  type: string;
  purpose: string;
  largestSize: number;
}

export interface WebAppManifest {
  rawJson: string;
  manifestUrl: string;
  documentUrl: string;
  name: string;
  shortName: string;
  startUrl: string;
  scope: string;
  display: WebAppManifestDisplay;
  themeColor: string;
  backgroundColor: string;
  icons: WebAppManifestIcon[];
  bestIconUrl: string;
}

export interface WebAppManifestParseResult {
  ok: boolean;
  reason: string;
  manifest?: WebAppManifest;
}

const MIN_INSTALLABLE_ICON_SIZE: number = 48;

export class WebAppManifestParser {
  parse(rawJson: string, manifestUrl: string, documentUrl: string): WebAppManifestParseResult {
    const trimmed = rawJson.trim();
    if (trimmed.length === 0) {
      return { ok: false, reason: 'empty_manifest' };
    }
    let parsed: object;
    try {
      parsed = JSON.parse(trimmed) as object;
    } catch (_error) {
      return { ok: false, reason: 'invalid_json' };
    }
    if (parsed === null || typeof parsed !== 'object') {
      return { ok: false, reason: 'manifest_not_object' };
    }
    const record = parsed as Record<string, Object>;
    const name = this.readString(record['name']);
    const shortName = this.readString(record['short_name']);
    const documentBaseUrl = this.resolveBaseUrl(manifestUrl, documentUrl);
    const startUrlRaw = this.readString(record['start_url']);
    const startUrl = this.resolveAgainstBase(documentBaseUrl, startUrlRaw.length > 0 ? startUrlRaw : documentUrl);
    const scopeRaw = this.readString(record['scope']);
    const scope = this.resolveScope(documentBaseUrl, scopeRaw, startUrl);
    const display = this.normalizeDisplay(this.readString(record['display']));
    const themeColor = this.readString(record['theme_color']);
    const backgroundColor = this.readString(record['background_color']);
    const icons = this.parseIcons(record['icons'], manifestUrl);
    const bestIconUrl = this.pickBestIcon(icons);
    if (name.length === 0 && shortName.length === 0) {
      return { ok: false, reason: 'missing_name' };
    }
    const manifest: WebAppManifest = {
      rawJson: trimmed,
      manifestUrl: manifestUrl,
      documentUrl: documentUrl,
      name: name,
      shortName: shortName,
      startUrl: startUrl,
      scope: scope,
      display: display,
      themeColor: themeColor,
      backgroundColor: backgroundColor,
      icons: icons,
      bestIconUrl: bestIconUrl
    };
    return { ok: true, reason: 'ok', manifest: manifest };
  }

  hasInstallableIcon(manifest: WebAppManifest): boolean {
    return manifest.icons.some((icon: WebAppManifestIcon) => icon.largestSize >= MIN_INSTALLABLE_ICON_SIZE);
  }

  private parseIcons(value: Object | undefined, manifestUrl: string): WebAppManifestIcon[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const documentBaseUrl = this.resolveBaseUrl(manifestUrl, manifestUrl);
    const icons: WebAppManifestIcon[] = [];
    (value as Object[]).forEach((entry: Object) => {
      if (entry === null || typeof entry !== 'object') {
        return;
      }
      const record = entry as Record<string, Object>;
      const src = this.resolveAgainstBase(documentBaseUrl, this.readString(record['src']));
      if (src.length === 0) {
        return;
      }
      const sizes = this.readString(record['sizes']);
      icons.push({
        src: src,
        sizes: sizes,
        type: this.readString(record['type']),
        purpose: this.readString(record['purpose']),
        largestSize: this.computeLargestIconSize(sizes)
      });
    });
    return icons;
  }

  private computeLargestIconSize(sizesAttr: string): number {
    const parts = sizesAttr.split(/\s+/);
    let largest = 0;
    parts.forEach((part: string) => {
      const lower = part.trim().toLowerCase();
      if (lower === 'any') {
        largest = Math.max(largest, 1024);
        return;
      }
      const dimensions = lower.split('x');
      if (dimensions.length !== 2) {
        return;
      }
      const width = Number.parseInt(dimensions[0], 10);
      const height = Number.parseInt(dimensions[1], 10);
      if (!Number.isFinite(width) || !Number.isFinite(height)) {
        return;
      }
      largest = Math.max(largest, Math.min(width, height));
    });
    return largest;
  }

  pickBestIcon(icons: WebAppManifestIcon[]): string {
    if (icons.length === 0) {
      return '';
    }
    let best: WebAppManifestIcon = icons[0];
    for (let index = 1; index < icons.length; index++) {
      const current = icons[index];
      const currentScore = this.iconScore(current);
      const bestScore = this.iconScore(best);
      if (currentScore > bestScore) {
        best = current;
      }
    }
    return best.src;
  }

  private iconScore(icon: WebAppManifestIcon): number {
    let score = icon.largestSize;
    if (icon.type.toLowerCase().indexOf('png') >= 0) {
      score += 10;
    }
    if (icon.purpose.toLowerCase().indexOf('maskable') >= 0) {
      score -= 5;
    }
    if (icon.purpose.toLowerCase().indexOf('monochrome') >= 0) {
      score -= 20;
    }
    return score;
  }

  private normalizeDisplay(value: string): WebAppManifestDisplay {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'standalone' || normalized === 'minimal-ui' || normalized === 'fullscreen' || normalized === 'browser') {
      return normalized;
    }
    return 'browser';
  }

  private readString(value: Object | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    if (typeof value === 'string') {
      return value.trim();
    }
    return '';
  }

  private resolveBaseUrl(manifestUrl: string, documentUrl: string): string {
    if (manifestUrl.length > 0) {
      return manifestUrl;
    }
    return documentUrl;
  }

  resolveAgainstBase(baseUrl: string, candidate: string): string {
    const trimmedCandidate = candidate.trim();
    if (trimmedCandidate.length === 0) {
      return '';
    }
    if (/^https?:/i.test(trimmedCandidate) || /^data:/i.test(trimmedCandidate)) {
      return trimmedCandidate;
    }
    const trimmedBase = baseUrl.trim();
    if (trimmedBase.length === 0) {
      return trimmedCandidate;
    }
    if (trimmedCandidate.startsWith('//')) {
      const protoMatch = /^([a-z]+:)/i.exec(trimmedBase);
      const proto = protoMatch !== null ? protoMatch[1] : 'https:';
      return `${proto}${trimmedCandidate}`;
    }
    const parsedBase = this.splitUrl(trimmedBase);
    if (parsedBase === undefined) {
      return trimmedCandidate;
    }
    if (trimmedCandidate.startsWith('/')) {
      return `${parsedBase.origin}${trimmedCandidate}`;
    }
    const basePath = parsedBase.path.substring(0, parsedBase.path.lastIndexOf('/') + 1);
    return `${parsedBase.origin}${this.normalizePath(`${basePath}${trimmedCandidate}`)}`;
  }

  private splitUrl(url: string): ParsedUrl | undefined {
    const match = /^([a-z]+:\/\/[^/?#]+)(\/[^?#]*)?/i.exec(url);
    if (match === null) {
      return undefined;
    }
    const parsed: ParsedUrl = {
      origin: match[1],
      path: match[2] ?? '/'
    };
    return parsed;
  }

  private normalizePath(path: string): string {
    const segments = path.split('/');
    const stack: string[] = [];
    segments.forEach((segment: string) => {
      if (segment === '' || segment === '.') {
        return;
      }
      if (segment === '..') {
        stack.pop();
        return;
      }
      stack.push(segment);
    });
    return `/${stack.join('/')}`;
  }

  private resolveScope(baseUrl: string, scopeRaw: string, startUrl: string): string {
    if (scopeRaw.length > 0) {
      const resolved = this.resolveAgainstBase(baseUrl, scopeRaw);
      return resolved;
    }
    if (startUrl.length === 0) {
      return '';
    }
    const split = this.splitUrl(startUrl);
    if (split === undefined) {
      return '';
    }
    const lastSlash = split.path.lastIndexOf('/');
    const scopePath = lastSlash >= 0 ? split.path.substring(0, lastSlash + 1) : '/';
    return `${split.origin}${scopePath}`;
  }
}
