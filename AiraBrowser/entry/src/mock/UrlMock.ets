interface ParsedUrlMock {
  protocol: string;
  hostname: string;
  port: string;
  pathname: string;
  search: string;
  href: string;
  origin: string;
}

interface ParsedAuthorityMock {
  hostname: string;
  port: string;
}

class UrlParserMock {
  parseURL(value: string): ParsedUrlMock {
    const input = value.trim();
    const schemeDivider = input.indexOf('://');
    if (schemeDivider <= 0) {
      throw new Error('url-mock-scheme');
    }
    const scheme = input.substring(0, schemeDivider).toLowerCase();
    if (!this.isScheme(scheme)) {
      throw new Error('url-mock-scheme');
    }
    const authorityStart = schemeDivider + 3;
    const authorityEnd = this.findAuthorityEnd(input, authorityStart);
    const authority = input.substring(authorityStart, authorityEnd);
    const hostAndPort = authority.substring(authority.lastIndexOf('@') + 1);
    const parsedAuthority = this.parseAuthority(hostAndPort);
    const normalizedPort = this.normalizeDefaultPort(scheme, parsedAuthority.port);
    const fragmentIndex = input.indexOf('#', authorityEnd);
    const queryIndex = input.indexOf('?', authorityEnd);
    const contentEnd = fragmentIndex >= 0 ? fragmentIndex : input.length;
    const pathEnd = queryIndex >= 0 && queryIndex < contentEnd ? queryIndex : contentEnd;
    const rawPath = input.substring(authorityEnd, pathEnd);
    const pathname = rawPath.length > 0 ? rawPath : '/';
    const search = queryIndex >= 0 && queryIndex < contentEnd
      ? input.substring(queryIndex, contentEnd)
      : '';
    const origin = scheme + '://' + parsedAuthority.hostname +
      (normalizedPort.length > 0 ? ':' + normalizedPort : '');
    return {
      protocol: scheme + ':',
      hostname: parsedAuthority.hostname,
      port: normalizedPort,
      pathname: pathname,
      search: search,
      href: origin + pathname + search,
      origin: origin
    };
  }

  private parseAuthority(value: string): ParsedAuthorityMock {
    if (value.length <= 0 || this.hasWhitespaceOrControl(value)) {
      throw new Error('url-mock-authority');
    }
    if (value.startsWith('[')) {
      const closingBracket = value.indexOf(']');
      if (closingBracket <= 1) {
        throw new Error('url-mock-ipv6');
      }
      const hostname = value.substring(0, closingBracket + 1).toLowerCase();
      const suffix = value.substring(closingBracket + 1);
      if (suffix.length > 0 && !suffix.startsWith(':')) {
        throw new Error('url-mock-ipv6-suffix');
      }
      const port = suffix.length > 0 ? suffix.substring(1) : '';
      this.requirePort(port);
      return { hostname: hostname, port: port };
    }
    const divider = value.lastIndexOf(':');
    if (divider >= 0 && value.indexOf(':') !== divider) {
      throw new Error('url-mock-unbracketed-ipv6');
    }
    const hostname = (divider >= 0 ? value.substring(0, divider) : value).toLowerCase();
    const port = divider >= 0 ? value.substring(divider + 1) : '';
    if (hostname.length <= 0) {
      throw new Error('url-mock-host');
    }
    this.requirePort(port);
    return { hostname: hostname, port: port };
  }

  private findAuthorityEnd(input: string, start: number): number {
    let end = input.length;
    const markers: string[] = ['/', '?', '#'];
    for (let index = 0; index < markers.length; index += 1) {
      const markerIndex = input.indexOf(markers[index], start);
      if (markerIndex >= 0 && markerIndex < end) {
        end = markerIndex;
      }
    }
    return end;
  }

  private normalizeDefaultPort(scheme: string, port: string): string {
    if ((scheme === 'http' && port === '80') || (scheme === 'https' && port === '443')) {
      return '';
    }
    return port;
  }

  private requirePort(value: string): void {
    if (value.length <= 0) {
      return;
    }
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code < 48 || code > 57) {
        throw new Error('url-mock-port');
      }
    }
    const port = Number(value);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      throw new Error('url-mock-port');
    }
  }

  private isScheme(value: string): boolean {
    if (value.length <= 0 || !this.isAlpha(value.charCodeAt(0))) {
      return false;
    }
    for (let index = 1; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      const character = value.charAt(index);
      const numeric = code >= 48 && code <= 57;
      if (!this.isAlpha(code) && !numeric && character !== '+' && character !== '-' && character !== '.') {
        return false;
      }
    }
    return true;
  }

  private isAlpha(code: number): boolean {
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  private hasWhitespaceOrControl(value: string): boolean {
    for (let index = 0; index < value.length; index += 1) {
      if (value.charCodeAt(index) <= 32) {
        return true;
      }
    }
    return false;
  }
}

class UrlModuleMock {
  URL: UrlParserMock = new UrlParserMock();
}

export default new UrlModuleMock();
