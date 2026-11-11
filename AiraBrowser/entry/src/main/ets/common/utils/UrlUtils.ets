import { connection } from '@kit.NetworkKit';
import { INTERNATIONAL_DOMAIN_SUFFIXES } from './InternationalDomainSuffixes';

const SCHEME_PREFIX_RE: RegExp = /^[a-z][a-z0-9+.-]*:/i;
const PASTED_URL_START_RE: RegExp = /[a-z][a-z0-9+.-]*:\/\/|www\./ig;
const IPV4_HOST_RE: RegExp = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
const HOST_PORT_WITHOUT_SCHEME_RE: RegExp = /^(localhost|[a-z0-9.-]+):\d+(?:[/?#].*)?$/i;
const DOMAIN_HOST_RE: RegExp = /^(www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:[/?#].*)?$/i;

/** Engine-independent interpretation shared by submission and synchronous navigation.
 * Only navigation results carry URLs; callers choose an engine for search results.
 */
export interface AddressInputResolution {
  intent: 'empty' | 'navigate' | 'search';
  submittedText: string;
  navigationUrl: string;
  httpFallbackUrl: string;
}

export function resolveAddressInput(input: string): AddressInputResolution {
  const extracted = resolveFirstUrlFromText(input);
  if (extracted !== undefined) return extracted;
  const trimmed = input.trim();
  if (/\s/.test(trimmed) && !/^(https?:\/\/|file:\/\/|aira:\/\/)/i.test(trimmed)) {
    return buildAddressInputResolution(trimmed);
  }
  return resolveUrlCandidate(trimmed);
}

/** Classify a complete value without extracting a URL from surrounding prose. */
export function looksLikeUrl(input: string): boolean {
  return !/\s/.test(input.trim()) && resolveUrlCandidate(input).intent === 'navigate';
}

/** Normalize an already selected URL. Search text is rejected, never sent to an engine. */
export function normalizeUrl(input: string): string {
  return resolveUrlCandidate(input).navigationUrl;
}

function resolveUrlCandidate(input: string): AddressInputResolution {
  const trimmed = input.trim();
  if (trimmed.length === 0) return buildAddressInputResolution(trimmed);
  const explicitScheme = hasExplicitUrlScheme(trimmed);
  if (!explicitScheme && /\s/.test(trimmed)) return buildAddressInputResolution(trimmed);
  const asciiInput = normalizeInternationalUrlHost(trimmed);
  if (explicitScheme) return buildAddressInputResolution(trimmed, asciiInput || trimmed);
  if (asciiInput.length === 0) return buildAddressInputResolution(trimmed);
  const hostname = readHostnameFromUserInput(asciiInput);
  const localHost = isLikelyLocalUrlHost(hostname);
  if (!localHost && !HOST_PORT_WITHOUT_SCHEME_RE.test(asciiInput) &&
    !asciiInput.toLowerCase().startsWith('www.') &&
    !(DOMAIN_HOST_RE.test(asciiInput) && (isIpv4UrlHost(hostname) || hasNavigableDomainSuffix(hostname)))) {
    return buildAddressInputResolution(trimmed);
  }
  const scheme = localHost ? 'http://' : 'https://';
  return buildAddressInputResolution(trimmed, `${scheme}${asciiInput}`, localHost ? '' : `http://${asciiInput}`);
}

function buildAddressInputResolution(
  submittedText: string,
  navigationUrl: string = '',
  httpFallbackUrl: string = ''
): AddressInputResolution {
  return {
    intent: submittedText.length === 0 ? 'empty' : navigationUrl.length > 0 ? 'navigate' : 'search',
    submittedText: submittedText,
    navigationUrl: navigationUrl,
    httpFallbackUrl: httpFallbackUrl
  };
}

function hasNavigableDomainSuffix(hostname: string): boolean {
  const normalized = normalizeHostname(hostname);
  const suffix = normalized.substring(normalized.lastIndexOf('.') + 1);
  // Successful IDNA encoding proves syntax, not navigation intent. Version-number
  // queries can also encode as hosts, so inferred IDN suffixes must be delegated.
  return /^[a-z]{2,63}$/.test(suffix) || INTERNATIONAL_DOMAIN_SUFFIXES.has(suffix);
}

function isIpv4UrlHost(hostname: string): boolean {
  const match = normalizeHostname(hostname).match(IPV4_HOST_RE);
  return match !== null && match.slice(1).every((octet: string): boolean => parseIpv4Octet(octet) >= 0);
}

export function extractFirstUrlFromText(input: string): string {
  const result = resolveFirstUrlFromText(input);
  return result?.intent === 'navigate' ? result.submittedText : '';
}

function resolveFirstUrlFromText(input: string): AddressInputResolution | undefined {
  const trimmed = input.trim();
  if (trimmed.length === 0) return undefined;
  const unwrapped = trimPastedUrlCandidate(trimmed);
  const explicitPrefix = /[a-z][a-z0-9+.-]*:\/\//i.exec(unwrapped);
  const firstBoundary = findFirstUrlBoundary(unwrapped);
  // Preserve complete international hosts before the prose extractor sees CJK
  // boundaries. Return the decision too, so submission never converts them again.
  if (!/\s/.test(trimmed) &&
    (explicitPrefix === null || explicitPrefix.index === 0 ||
      (firstBoundary >= 0 && explicitPrefix.index > firstBoundary)) &&
    isInternationalHostnameCandidate(readHostnameFromUserInput(unwrapped))) {
    const prefix = /^[a-z][a-z0-9+.-]*:\/\//i.exec(unwrapped);
    const authorityStart = prefix === null ? 0 : prefix[0].length;
    const boundary = findFirstUrlBoundary(unwrapped.substring(authorityStart));
    const authorityEnd = boundary < 0 ? unwrapped.length : authorityStart + boundary;
    const candidate = trimInternationalPastedUrlCandidate(unwrapped, authorityEnd);
    const result = resolveUrlCandidate(candidate);
    return result.intent === 'navigate' ? result : buildAddressInputResolution(trimmed);
  }
  return extractExplicitPastedUrlCandidate(trimmed) ?? extractBarePastedUrlCandidate(trimmed);
}

function isInternationalHostnameCandidate(hostname: string): boolean {
  if (!/[^\x00-\x7F]/.test(hostname) || !/[.\u3002\uFF0E\uFF61]/.test(hostname)) return false;
  for (let index = 0; index < hostname.length; index += 1) {
    const character = hostname.charAt(index);
    const codePoint = hostname.charCodeAt(index);
    const domainSeparator = codePoint === 0x3002 || codePoint === 0xFF0E || codePoint === 0xFF61;
    if ((codePoint <= 0x7F && !/[a-z0-9.-]/i.test(character)) ||
      (!domainSeparator && isCjkPunctuationCodePoint(codePoint)) ||
      isUrlWrappingBoundaryCharacter(character)) return false;
  }
  return true;
}

function normalizeInternationalUrlHost(value: string): string {
  const prefix = /^https?:\/\//i.exec(value);
  if (hasExplicitUrlScheme(value) && prefix === null) return value;
  const start = prefix === null ? 0 : prefix[0].length;
  const body = value.substring(start);
  const boundary = findFirstUrlBoundary(body);
  const authority = boundary < 0 ? body : body.substring(0, boundary);
  const hostStart = authority.lastIndexOf('@') + 1;
  if (authority.substring(hostStart).startsWith('[')) return value;
  const colon = authority.indexOf(':', hostStart);
  const hostEnd = colon < 0 ? authority.length : colon;
  const hostname = authority.substring(hostStart, hostEnd);
  if (!/[^\x00-\x7F]/.test(hostname)) return value;
  if (prefix === null) {
    // Keep email-like input and malformed ports in the search path.
    if (hostStart > 0 || (colon >= 0 && !/^:\d+$/.test(authority.substring(colon)))) return '';
    if (!/[.\u3002\uFF0E\uFF61]/.test(hostname)) return value;
  }
  try {
    // This API is available from API 23. This converts the hostname only; paths,
    // queries, fragments and credentials keep their existing representation.
    const ascii = connection.getDnsAscii(hostname, connection.ConversionProcess.USE_STD3_ASCII_RULES);
    const labels = ascii.endsWith('.') ? ascii.substring(0, ascii.length - 1).split('.') : ascii.split('.');
    if (ascii.length === 0 || ascii.length > 254 || labels.some((label: string): boolean =>
      label.length === 0 || label.length > 63 || !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i.test(label))) return '';
    return value.substring(0, start + hostStart) + ascii + value.substring(start + hostEnd);
  } catch (_error) {
    return '';
  }
}

function hasExplicitUrlScheme(rawValue: string): boolean {
  const trimmed = rawValue.trim();
  if (!SCHEME_PREFIX_RE.test(trimmed)) {
    return false;
  }
  if (HOST_PORT_WITHOUT_SCHEME_RE.test(trimmed)) {
    return false;
  }
  return true;
}

export function isLikelyLocalUrlHost(hostname: string): boolean {
  const normalized = normalizeHostname(hostname);
  if (normalized.length === 0) {
    return false;
  }
  if (normalized === 'localhost' || normalized.endsWith('.local')) {
    return true;
  }
  if (isPrivateIpv4Host(normalized)) {
    return true;
  }
  return isLocalIpv6Host(normalized);
}

function normalizeHostname(hostname: string): string {
  let normalized = hostname.trim().toLowerCase();
  if (normalized.length === 0) {
    return '';
  }
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  if (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

function isPrivateIpv4Host(hostname: string): boolean {
  const match = normalizeHostname(hostname).match(IPV4_HOST_RE);
  if (match === null) {
    return false;
  }

  const first = parseIpv4Octet(match[1]);
  const second = parseIpv4Octet(match[2]);
  const third = parseIpv4Octet(match[3]);
  const fourth = parseIpv4Octet(match[4]);
  if (first < 0 || second < 0 || third < 0 || fourth < 0) {
    return false;
  }

  if (first === 0 || first === 10 || first === 127) {
    return true;
  }
  if (first === 169 && second === 254) {
    return true;
  }
  if (first === 172 && second >= 16 && second <= 31) {
    return true;
  }
  return first === 192 && second === 168;
}

function parseIpv4Octet(value: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 255) {
    return -1;
  }
  return parsed;
}

function isLocalIpv6Host(hostname: string): boolean {
  const normalized = normalizeHostname(hostname);
  if (!normalized.includes(':')) {
    return false;
  }
  if (normalized === '::1') {
    return true;
  }
  return normalized.startsWith('fe80:') || normalized.startsWith('fc') || normalized.startsWith('fd');
}

function extractExplicitPastedUrlCandidate(value: string): AddressInputResolution | undefined {
  PASTED_URL_START_RE.lastIndex = 0;
  let match = PASTED_URL_START_RE.exec(value);
  while (match !== null) {
    const candidate = readPastedUrlCandidate(value, match.index);
    const result = resolvePastedUrlCandidate(candidate, value);
    if (result !== undefined) {
      PASTED_URL_START_RE.lastIndex = 0;
      return result;
    }
    match = PASTED_URL_START_RE.exec(value);
  }
  PASTED_URL_START_RE.lastIndex = 0;
  return undefined;
}

function extractBarePastedUrlCandidate(value: string): AddressInputResolution | undefined {
  let index = 0;
  while (index < value.length) {
    while (index < value.length && isPastedUrlSegmentStartDelimiter(value.charAt(index), value.charCodeAt(index))) {
      index += 1;
    }
    const start = index;
    while (index < value.length && !isPastedUrlTextBoundary(value.charAt(index), value.charCodeAt(index))) {
      index += 1;
    }
    const candidate = trimPastedUrlCandidate(value.substring(start, index));
    const result = resolvePastedUrlCandidate(candidate, value);
    if (result !== undefined) return result;
  }
  return undefined;
}

function readPastedUrlCandidate(value: string, start: number): string {
  if (startsWithExplicitPastedUrlPrefix(value, start)) {
    return readExplicitPastedUrlCandidate(value, start);
  }
  return readDelimitedPastedUrlCandidate(value, start);
}

function readDelimitedPastedUrlCandidate(value: string, start: number): string {
  let end = start;
  while (end < value.length && !isPastedUrlTextBoundary(value.charAt(end), value.charCodeAt(end))) {
    end += 1;
  }
  return trimPastedUrlCandidate(value.substring(start, end));
}

function readExplicitPastedUrlCandidate(value: string, start: number): string {
  let end = start;
  while (end < value.length) {
    const character = value.charAt(end);
    const codePoint = value.charCodeAt(end);
    if (isExplicitUrlTextBoundary(value, start, end, character, codePoint)) {
      break;
    }
    end += 1;
  }
  return trimPastedUrlCandidate(value.substring(start, end));
}

function trimInternationalPastedUrlCandidate(value: string, authorityEnd: number): string {
  // A complete address has no surrounding prose. Preserve mixed-language paths;
  // apply punctuation cleanup only at the tail, outside its international authority.
  let candidate = trimPastedUrlCandidate(value);
  while (candidate.length > authorityEnd &&
    isCjkPunctuationCodePoint(candidate.charCodeAt(candidate.length - 1))) {
    candidate = trimPastedUrlCandidate(candidate.substring(0, candidate.length - 1));
  }
  return candidate;
}

function trimPastedUrlCandidate(value: string): string {
  let candidate = value.trim();
  while (candidate.length > 0 && shouldTrimPastedUrlTrailingCharacter(candidate)) {
    candidate = candidate.substring(0, candidate.length - 1);
  }
  return candidate;
}

function resolvePastedUrlCandidate(candidate: string, fullText: string): AddressInputResolution | undefined {
  if (candidate.length === 0 || !hasUsablePastedUrlCandidateBody(candidate) || /\s/.test(candidate)) {
    return undefined;
  }
  const hostname = readHostnameFromUserInput(candidate);
  const hasAddressEvidence = candidate === fullText.trim() || hasExplicitUrlScheme(candidate) ||
    candidate.toLowerCase().startsWith('www.') || HOST_PORT_WITHOUT_SCHEME_RE.test(candidate) ||
    isLikelyLocalUrlHost(hostname) || (hasAsciiLetter(hostname) &&
      (candidate.indexOf('/') >= 0 || candidate.indexOf('?') >= 0 || candidate.indexOf('#') >= 0));
  if (!hasAddressEvidence) return undefined;
  const result = resolveUrlCandidate(candidate);
  return result.intent === 'navigate' ? result : undefined;
}

function hasUsablePastedUrlCandidateBody(candidate: string): boolean {
  const trimmed = candidate.trim();
  if (!hasExplicitUrlScheme(trimmed)) {
    return true;
  }
  const schemeEnd = trimmed.indexOf(':');
  if (schemeEnd < 0 || schemeEnd >= trimmed.length - 1) {
    return false;
  }
  if (trimmed.substring(schemeEnd + 1).replace(/\//g, '').length === 0) {
    return false;
  }
  return true;
}

function hasAsciiLetter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const codePoint = value.charCodeAt(index);
    if ((codePoint >= 65 && codePoint <= 90) || (codePoint >= 97 && codePoint <= 122)) {
      return true;
    }
  }
  return false;
}

function shouldTrimPastedUrlTrailingCharacter(candidate: string): boolean {
  const tail = candidate.charAt(candidate.length - 1);
  switch (tail) {
    case '.':
    case ',':
    case ';':
    case ':':
    case '!':
    case '?':
    case '"':
    case '\'':
    case '`':
      return true;
    case ')':
      return hasMoreClosingThanOpening(candidate, '(', ')');
    case ']':
      return hasMoreClosingThanOpening(candidate, '[', ']');
    case '}':
      return hasMoreClosingThanOpening(candidate, '{', '}');
    case '>':
      return hasMoreClosingThanOpening(candidate, '<', '>');
    default:
      return false;
  }
}

function hasMoreClosingThanOpening(value: string, opening: string, closing: string): boolean {
  let openingCount = 0;
  let closingCount = 0;
  for (let index = 0; index < value.length; index += 1) {
    const current = value.charAt(index);
    if (current === opening) {
      openingCount += 1;
    } else if (current === closing) {
      closingCount += 1;
    }
  }
  return closingCount > openingCount;
}

function isPastedUrlSegmentStartDelimiter(character: string, codePoint: number): boolean {
  return isPastedUrlTextBoundary(character, codePoint) ||
    character === ':' ||
    character === ',' ||
    character === ';' ||
    character === '!' ||
    character === '?';
}

function startsWithExplicitPastedUrlPrefix(value: string, start: number): boolean {
  const candidate = value.substring(start).toLowerCase();
  return /^[a-z][a-z0-9+.-]*:\/\//.test(candidate) || candidate.startsWith('www.');
}

function isExplicitUrlTextBoundary(
  value: string,
  start: number,
  index: number,
  character: string,
  codePoint: number
): boolean {
  if (isWhitespaceCodePoint(codePoint) || isCjkPunctuationCodePoint(codePoint) ||
    isUrlWrappingBoundaryCharacter(character)) {
    return true;
  }
  if (!isCjkCodePoint(codePoint)) {
    return false;
  }
  return !shouldKeepCjkCodePointInExplicitUrl(value, start, index);
}

function shouldKeepCjkCodePointInExplicitUrl(value: string, start: number, index: number): boolean {
  if (isInsideExplicitUrlAuthority(value, start, index)) {
    return true;
  }

  const previousNonCjk = findPreviousNonCjkCharacter(value, start, index);
  if (previousNonCjk.length === 0) {
    return false;
  }
  if (isCjkPathRunIntroducer(previousNonCjk)) {
    return true;
  }
  return false;
}

function isInsideExplicitUrlAuthority(value: string, start: number, index: number): boolean {
  const bodyStart = resolveExplicitUrlBodyStart(value, start);
  if (bodyStart < 0 || index < bodyStart) {
    return false;
  }
  for (let current = bodyStart; current < index; current += 1) {
    const character = value.charAt(current);
    if (character === '/' || character === '?' || character === '#') {
      return false;
    }
  }
  return true;
}

function resolveExplicitUrlBodyStart(value: string, start: number): number {
  const candidate = value.substring(start);
  const schemeMatch = /^[a-z][a-z0-9+.-]*:\/\//i.exec(candidate);
  if (schemeMatch !== null) {
    return start + schemeMatch[0].length;
  }
  if (candidate.toLowerCase().startsWith('www.')) {
    return start;
  }
  return -1;
}

function findPreviousNonCjkCharacter(value: string, start: number, index: number): string {
  for (let current = index - 1; current >= start; current -= 1) {
    const character = value.charAt(current);
    if (!isCjkCodePoint(value.charCodeAt(current))) {
      return character;
    }
  }
  return '';
}

function isCjkPathRunIntroducer(character: string): boolean {
  switch (character) {
    case '/':
    case '?':
    case '#':
    case '=':
    case '&':
    case ';':
    case ':':
      return true;
    default:
      return false;
  }
}

function isPastedUrlTextBoundary(character: string, codePoint: number): boolean {
  return isWhitespaceCodePoint(codePoint) ||
    isCjkCodePoint(codePoint) ||
    isCjkPunctuationCodePoint(codePoint) ||
    isUrlWrappingBoundaryCharacter(character);
}

function isWhitespaceCodePoint(codePoint: number): boolean {
  return codePoint === 0x20 ||
    codePoint === 0x09 ||
    codePoint === 0x0A ||
    codePoint === 0x0D ||
    codePoint === 0x0B ||
    codePoint === 0x0C ||
    codePoint === 0x85 ||
    codePoint === 0xA0 ||
    codePoint === 0x1680 ||
    codePoint === 0x180E ||
    (codePoint >= 0x2000 && codePoint <= 0x200A) ||
    codePoint === 0x2028 ||
    codePoint === 0x2029 ||
    codePoint === 0x202F ||
    codePoint === 0x205F ||
    codePoint === 0x3000;
}

function isCjkCodePoint(codePoint: number): boolean {
  return (codePoint >= 0x2E80 && codePoint <= 0x9FFF) ||
    (codePoint >= 0xF900 && codePoint <= 0xFAFF);
}

function isCjkPunctuationCodePoint(codePoint: number): boolean {
  return (codePoint >= 0x3000 && codePoint <= 0x303F) ||
    (codePoint >= 0xFF01 && codePoint <= 0xFF0F) ||
    (codePoint >= 0xFF1A && codePoint <= 0xFF20) ||
    (codePoint >= 0xFF3B && codePoint <= 0xFF40) ||
    (codePoint >= 0xFF5B && codePoint <= 0xFF65);
}

function isUrlWrappingBoundaryCharacter(character: string): boolean {
  switch (character) {
    case '<':
    case '>':
    case '"':
    case '\'':
    case '`':
    case '(':
    case ')':
    case '[':
    case ']':
    case '{':
    case '}':
      return true;
    default:
      return false;
  }
}

function readHostnameFromUserInput(rawValue: string): string {
  let value = rawValue.trim();
  if (value.length === 0) {
    return '';
  }

  value = value.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
  const slashIndex = findFirstUrlBoundary(value);
  if (slashIndex >= 0) {
    value = value.substring(0, slashIndex);
  }
  const atIndex = value.lastIndexOf('@');
  if (atIndex >= 0) {
    value = value.substring(atIndex + 1);
  }
  if (value.startsWith('[')) {
    const closingBracketIndex = value.indexOf(']');
    return closingBracketIndex >= 0 ? value.substring(1, closingBracketIndex) : value;
  }
  const colonIndex = value.indexOf(':');
  if (colonIndex >= 0) {
    value = value.substring(0, colonIndex);
  }
  return value;
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
