import { UserScriptInstallSourceAdapter } from './UserScriptInstallSourceAdapter';

const GFORK_PROXY_HOST_SUFFIX: string = 'greasyfork.org.cn';
const GFORK_OFFICIAL_SCRIPT_ORIGIN: string = 'https://update.greasyfork.org';
const USER_SCRIPT_SUFFIX: string = '.user.js';
// The proxy page never returns the script. After its countdown it picks one of
// these download nodes and opens `${node}/scripts/${hash path}`.
const GFORK_PROXY_DOWNLOAD_ORIGINS: string[] = [
  'https://static-sg-apse1-primary-mirror-aws-s3-cloudfront-public-cdn.dahi.edu.eu.org',
  'https://tencent.api-data-abtest-config.dahi.edu.eu.org',
  'https://api-data-aws-abtest-config.dahi.edu.eu.org'
];

export class UserScriptGforkProxyInstallUrl implements UserScriptInstallSourceAdapter {
  resolveSourceUrls(url: string): string[] {
    const trimmed = url.trim();
    if (!this.isHttpUrl(trimmed) || !this.isProxyHost(this.readHostname(trimmed))) {
      return [];
    }
    const scriptPath = this.readScriptPath(trimmed);
    if (scriptPath.length === 0) {
      return [];
    }
    return this.buildSourceUrls(scriptPath);
  }

  private buildSourceUrls(scriptPath: string): string[] {
    const encodedPath = this.encodeScriptPath(scriptPath);
    const urls: string[] = [];
    for (let index = 0; index < GFORK_PROXY_DOWNLOAD_ORIGINS.length; index++) {
      urls.push(`${GFORK_PROXY_DOWNLOAD_ORIGINS[index]}/scripts/${encodedPath}`);
    }
    urls.push(`${GFORK_OFFICIAL_SCRIPT_ORIGIN}/scripts/${encodedPath}`);
    const scriptId = this.readScriptId(scriptPath);
    const idUrl = `${GFORK_OFFICIAL_SCRIPT_ORIGIN}/scripts/${scriptId}${USER_SCRIPT_SUFFIX}`;
    if (scriptId.length > 0 && urls.indexOf(idUrl) < 0) {
      urls.push(idUrl);
    }
    return urls;
  }

  private readScriptPath(url: string): string {
    const hashIndex = url.indexOf('#');
    const beforeHash = hashIndex >= 0 ? url.substring(0, hashIndex) : url;
    const hash = hashIndex >= 0 ? url.substring(hashIndex) : '';
    if (hash.startsWith('#/')) {
      const fromHash = this.normalizeScriptPath(hash.substring(2));
      if (fromHash.length > 0) {
        return fromHash;
      }
    }
    return this.normalizeScriptPath(this.readQueryParam(beforeHash, 'path'));
  }

  private normalizeScriptPath(rawPath: string): string {
    const trimmed = rawPath.trim().replace(/^\/+/, '');
    if (trimmed.length === 0) {
      return '';
    }
    let decoded = trimmed;
    try {
      decoded = decodeURIComponent(trimmed).trim().replace(/^\/+/, '');
    } catch (_error) {
      return '';
    }
    if (decoded.length === 0 || decoded.indexOf('\\') >= 0 || decoded.indexOf('..') >= 0 ||
      decoded.indexOf('?') >= 0 || decoded.indexOf('#') >= 0) {
      return '';
    }
    if (!/^\d+(?:\/[^/]+)?\.user\.js$/i.test(decoded)) {
      return '';
    }
    return decoded;
  }

  private encodeScriptPath(scriptPath: string): string {
    const parts = scriptPath.split('/');
    const encoded: string[] = [];
    for (let index = 0; index < parts.length; index++) {
      encoded.push(encodeURIComponent(parts[index]));
    }
    return encoded.join('/');
  }

  private readScriptId(scriptPath: string): string {
    const slash = scriptPath.indexOf('/');
    const head = slash < 0 ? scriptPath : scriptPath.substring(0, slash);
    if (/^\d+$/.test(head)) {
      return head;
    }
    if (/^\d+\.user\.js$/i.test(head)) {
      return head.substring(0, head.length - USER_SCRIPT_SUFFIX.length);
    }
    return '';
  }

  private readQueryParam(url: string, key: string): string {
    const queryIndex = url.indexOf('?');
    if (queryIndex < 0) {
      return '';
    }
    const parts = url.substring(queryIndex + 1).split('&');
    for (let index = 0; index < parts.length; index++) {
      const part = parts[index];
      const separator = part.indexOf('=');
      const rawKey = separator < 0 ? part : part.substring(0, separator);
      let decodedKey = rawKey;
      try {
        decodedKey = decodeURIComponent(rawKey);
      } catch (_error) {
        decodedKey = rawKey;
      }
      if (decodedKey !== key) {
        continue;
      }
      const rawValue = separator < 0 ? '' : part.substring(separator + 1);
      try {
        return decodeURIComponent(rawValue);
      } catch (_error) {
        return '';
      }
    }
    return '';
  }

  private readHostname(url: string): string {
    const scheme = url.indexOf('://');
    if (scheme < 0) {
      return '';
    }
    let rest = url.substring(scheme + 3);
    const hashIndex = rest.indexOf('#');
    if (hashIndex >= 0) {
      rest = rest.substring(0, hashIndex);
    }
    const slash = rest.indexOf('/');
    const question = rest.indexOf('?');
    let end = rest.length;
    if (slash >= 0 && slash < end) {
      end = slash;
    }
    if (question >= 0 && question < end) {
      end = question;
    }
    let host = rest.substring(0, end);
    const at = host.lastIndexOf('@');
    if (at >= 0) {
      host = host.substring(at + 1);
    }
    const colon = host.indexOf(':');
    if (colon >= 0) {
      host = host.substring(0, colon);
    }
    return host.toLowerCase();
  }

  private isProxyHost(hostname: string): boolean {
    return hostname === GFORK_PROXY_HOST_SUFFIX || hostname.endsWith(`.${GFORK_PROXY_HOST_SUFFIX}`);
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }
}
