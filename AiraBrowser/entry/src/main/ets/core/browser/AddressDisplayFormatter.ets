export interface ResolvedAddressDisplay {
  displayText: string;
  pendingDisplayText: string;
  pendingTargetUrl: string;
}

export function formatTopChromeAddress(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return '';
  }
  const hostname = extractCommonWebHostname(trimmed);
  if (hostname.length > 0) {
    return stripTopChromeCommonHostPrefix(hostname);
  }
  return stripCommonWebScheme(trimmed);
}

export function resolveCurrentSiteUrl(currentUrl: string, addressInput: string): string {
  if (currentUrl.length > 0) {
    return currentUrl;
  }
  return addressInput;
}

export function resolveCurrentSiteHost(currentUrl: string, addressInput: string): string {
  return extractSiteHost(resolveCurrentSiteUrl(currentUrl, addressInput));
}

export function resolveConnectionStatusTitle(currentUrl: string, addressInput: string): string {
  if (isSecureCurrentSiteUrl(currentUrl, addressInput)) {
    return '连接安全';
  }
  return '连接未验证';
}

export function isSecureCurrentSiteUrl(currentUrl: string, addressInput: string): boolean {
  return resolveCurrentSiteUrl(currentUrl, addressInput).trim().toLowerCase().startsWith('https://');
}

export function resolveCommittedAddressDisplay(
  url: string,
  pendingDisplayText: string,
  pendingTargetUrl: string
): ResolvedAddressDisplay {
  if (pendingDisplayText.length === 0 || pendingTargetUrl.length === 0) {
    return {
      displayText: url,
      pendingDisplayText: pendingDisplayText,
      pendingTargetUrl: pendingTargetUrl
    };
  }
  if (normalizeNavigationTarget(url) === normalizeNavigationTarget(pendingTargetUrl) ||
    isMatchingSearchNavigation(url, pendingTargetUrl, pendingDisplayText)) {
    return {
      displayText: pendingDisplayText,
      pendingDisplayText: pendingDisplayText,
      pendingTargetUrl: pendingTargetUrl
    };
  }
  return {
    displayText: url,
    pendingDisplayText: '',
    pendingTargetUrl: ''
  };
}

export function normalizeNavigationTarget(url: string): string {
  const trimmed = url.trim().toLowerCase();
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

export function isMatchingSearchNavigation(url: string, targetUrl: string, query: string): boolean {
  const current = parseSearchNavigationUrl(url);
  const target = parseSearchNavigationUrl(targetUrl);
  if (current === undefined || target === undefined ||
    current.host !== target.host || current.path !== target.path) {
    return false;
  }
  const queryParamName = findQueryParamNameByValue(target.query, query);
  if (queryParamName.length === 0) {
    return false;
  }
  return hasQueryParamValue(current.query, queryParamName, query);
}

interface SearchNavigationUrlParts {
  host: string;
  path: string;
  query: string;
}

function parseSearchNavigationUrl(value: string): SearchNavigationUrlParts | undefined {
  const trimmed = value.trim();
  const lower = trimmed.toLowerCase();
  let authorityStart = -1;
  if (lower.startsWith('https://')) {
    authorityStart = 'https://'.length;
  } else if (lower.startsWith('http://')) {
    authorityStart = 'http://'.length;
  }
  if (authorityStart < 0 || authorityStart >= trimmed.length) {
    return undefined;
  }

  const fragmentIndex = trimmed.indexOf('#', authorityStart);
  const contentEnd = fragmentIndex >= 0 ? fragmentIndex : trimmed.length;
  const queryIndex = trimmed.indexOf('?', authorityStart);
  const queryStart = queryIndex >= 0 && queryIndex < contentEnd ? queryIndex : contentEnd;
  const pathIndex = trimmed.indexOf('/', authorityStart);
  const authorityEnd = pathIndex >= 0 && pathIndex < queryStart ? pathIndex : queryStart;
  const authority = trimmed.substring(authorityStart, authorityEnd);
  const host = normalizeSearchNavigationHost(extractHostFromUrlBody(authority));
  if (host.length === 0) {
    return undefined;
  }
  const path = pathIndex >= 0 && pathIndex < queryStart
    ? normalizeSearchNavigationPath(trimmed.substring(pathIndex, queryStart))
    : '/';
  const query = queryIndex >= 0 && queryIndex < contentEnd
    ? trimmed.substring(queryIndex + 1, contentEnd)
    : '';
  return {
    host: host,
    path: path,
    query: query
  };
}

function normalizeSearchNavigationHost(value: string): string {
  let host = value.trim().toLowerCase();
  if (host.startsWith('www.')) {
    host = host.substring('www.'.length);
  }
  if (host === 'bing.com' || host.endsWith('.bing.com')) {
    return 'bing.com';
  }
  if (host.startsWith('google.') || host.indexOf('.google.') > 0) {
    return 'google';
  }
  return host;
}

function normalizeSearchNavigationPath(value: string): string {
  const lower = value.trim().toLowerCase();
  if (lower.length > 1 && lower.endsWith('/')) {
    return lower.substring(0, lower.length - 1);
  }
  return lower.length > 0 ? lower : '/';
}

function findQueryParamNameByValue(query: string, expectedValue: string): string {
  const expected = normalizeSearchQueryValue(expectedValue);
  if (query.length === 0 || expected.length === 0) {
    return '';
  }
  const parts = query.split('&');
  for (let index = 0; index < parts.length; index += 1) {
    const part = parts[index];
    const separatorIndex = part.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }
    const name = decodeSearchQueryPart(part.substring(0, separatorIndex)).trim().toLowerCase();
    const value = normalizeSearchQueryValue(part.substring(separatorIndex + 1));
    if (name.length > 0 && value === expected) {
      return name;
    }
  }
  return '';
}

function hasQueryParamValue(query: string, expectedName: string, expectedValue: string): boolean {
  const normalizedName = expectedName.trim().toLowerCase();
  const normalizedValue = normalizeSearchQueryValue(expectedValue);
  if (query.length === 0 || normalizedName.length === 0 || normalizedValue.length === 0) {
    return false;
  }
  const parts = query.split('&');
  for (let index = 0; index < parts.length; index += 1) {
    const part = parts[index];
    const separatorIndex = part.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }
    const name = decodeSearchQueryPart(part.substring(0, separatorIndex)).trim().toLowerCase();
    if (name === normalizedName &&
      normalizeSearchQueryValue(part.substring(separatorIndex + 1)) === normalizedValue) {
      return true;
    }
  }
  return false;
}

function normalizeSearchQueryValue(value: string): string {
  return decodeSearchQueryPart(value).trim().replace(/\s+/g, ' ').toLowerCase();
}

function decodeSearchQueryPart(value: string): string {
  try {
    return decodeURIComponent(value.replace(/\+/g, '%20'));
  } catch (_error) {
    return value;
  }
}

function stripCommonWebScheme(value: string): string {
  const lower = value.toLowerCase();
  if (lower.startsWith('https://')) {
    return value.substring('https://'.length);
  }
  if (lower.startsWith('http://')) {
    return value.substring('http://'.length);
  }
  return value;
}

function extractCommonWebHostname(value: string): string {
  const withoutScheme = stripCommonWebScheme(value);
  if (withoutScheme === value) {
    return '';
  }
  return extractHostFromUrlBody(withoutScheme);
}

function stripTopChromeCommonHostPrefix(value: string): string {
  return value.toLowerCase().startsWith('www.') ? value.substring('www.'.length) : value;
}

function extractSiteHost(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return '';
  }
  const withoutScheme = trimmed.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
  return extractHostFromUrlBody(withoutScheme);
}

function extractHostFromUrlBody(value: string): string {
  const withoutUserInfo = value.substring(value.lastIndexOf('@') + 1);
  if (withoutUserInfo.length === 0) {
    return '';
  }

  if (withoutUserInfo.startsWith('[')) {
    const closingBracketIndex = withoutUserInfo.indexOf(']');
    return closingBracketIndex >= 0 ? withoutUserInfo.substring(1, closingBracketIndex) : withoutUserInfo;
  }

  const boundaryIndex = findFirstUrlBoundary(withoutUserInfo);
  const hostWithPort = boundaryIndex >= 0 ? withoutUserInfo.substring(0, boundaryIndex) : withoutUserInfo;
  const colonIndex = hostWithPort.indexOf(':');
  return colonIndex >= 0 ? hostWithPort.substring(0, colonIndex) : hostWithPort;
}

function findFirstUrlBoundary(value: string): number {
  const slashIndex = value.indexOf('/');
  const queryIndex = value.indexOf('?');
  const hashIndex = value.indexOf('#');
  let result = -1;
  [slashIndex, queryIndex, hashIndex].forEach((index: number) => {
    if (index >= 0 && (result < 0 || index < result)) {
      result = index;
    }
  });
  return result;
}
