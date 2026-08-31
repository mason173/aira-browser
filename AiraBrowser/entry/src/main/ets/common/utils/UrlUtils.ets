const SCHEME_PREFIX_RE: RegExp = /^[a-z][a-z0-9+.-]*:/i;
const PASTED_URL_START_RE: RegExp = /[a-z][a-z0-9+.-]*:\/\/|www\./ig;
const IPV4_HOST_RE: RegExp = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
const HOST_PORT_WITHOUT_SCHEME_RE: RegExp = /^(localhost|[a-z0-9.-]+):\d+(?:[/?#].*)?$/i;
const DOMAIN_HOST_RE: RegExp = /^(www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:[/?#].*)?$/i;

export function looksLikeUrl(input: string): boolean {
  const trimmed: string = input.trim();
  const lower: string = trimmed.toLowerCase();
  if (trimmed.length === 0 || trimmed.includes(' ')) {
    return false;
  }

  if (hasExplicitUrlScheme(trimmed) || HOST_PORT_WITHOUT_SCHEME_RE.test(trimmed)) {
    return true;
  }

  const hostname = readHostnameFromUserInput(trimmed);
  return isLikelyLocalUrlHost(hostname) ||
    lower.startsWith('www.') ||
    DOMAIN_HOST_RE.test(trimmed);
}

export function normalizeUrl(input: string): string {
  const trimmed: string = input.trim();
  if (trimmed.length === 0) {
    return '';
  }

  if (hasExplicitUrlScheme(trimmed)) {
    return trimmed;
  }

  if (looksLikeUrl(trimmed)) {
    const hostname = readHostnameFromUserInput(trimmed);
    const scheme = isLikelyLocalUrlHost(hostname) ? 'http://' : 'https://';
    return `${scheme}${trimmed}`;
  }

  return `https://www.baidu.com/s?wd=${encodeURIComponent(trimmed)}`;
}

export function resolveSchemelessHttpFallbackUrl(input: string): string {
  const trimmed: string = input.trim();
  if (trimmed.length === 0 || hasExplicitUrlScheme(trimmed) || !looksLikeUrl(trimmed)) {
    return '';
  }
  const hostname = readHostnameFromUserInput(trimmed);
  if (isLikelyLocalUrlHost(hostname)) {
    return '';
  }
  return `http://${trimmed}`;
}

export function extractFirstUrlFromText(input: string): string {
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    return '';
  }

  const explicitCandidate = extractExplicitPastedUrlCandidate(trimmed);
  if (explicitCandidate.length > 0) {
    return explicitCandidate;
  }
  return extractBarePastedUrlCandidate(trimmed);
}

export function normalizeAddressInputText(input: string): string {
  const extractedUrl = extractFirstUrlFromText(input);
  if (extractedUrl.length > 0) {
    return extractedUrl;
  }
  return input.trim();
}

export function hasExplicitUrlScheme(rawValue: string): boolean {
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

function extractExplicitPastedUrlCandidate(value: string): string {
  PASTED_URL_START_RE.lastIndex = 0;
  let match = PASTED_URL_START_RE.exec(value);
  while (match !== null) {
    const candidate = readPastedUrlCandidate(value, match.index);
    if (isPastedUrlCandidate(candidate, value)) {
      PASTED_URL_START_RE.lastIndex = 0;
      return candidate;
    }
    match = PASTED_URL_START_RE.exec(value);
  }
  PASTED_URL_START_RE.lastIndex = 0;
  return '';
}

function extractBarePastedUrlCandidate(value: string): string {
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
    if (isPastedUrlCandidate(candidate, value)) {
      return candidate;
    }
  }
  return '';
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

function trimPastedUrlCandidate(value: string): string {
  let candidate = value.trim();
  while (candidate.length > 0 && shouldTrimPastedUrlTrailingCharacter(candidate)) {
    candidate = candidate.substring(0, candidate.length - 1);
  }
  return candidate;
}

function isPastedUrlCandidate(candidate: string, fullText: string): boolean {
  if (candidate.length === 0 || !hasUsablePastedUrlCandidateBody(candidate) || !looksLikeUrl(candidate)) {
    return false;
  }
  if (candidate === fullText.trim()) {
    return true;
  }
  if (hasExplicitUrlScheme(candidate) || candidate.toLowerCase().startsWith('www.') ||
    HOST_PORT_WITHOUT_SCHEME_RE.test(candidate)) {
    return true;
  }
  const hostname = readHostnameFromUserInput(candidate);
  if (isLikelyLocalUrlHost(hostname)) {
    return true;
  }
  return hasAsciiLetter(hostname) &&
    (candidate.indexOf('/') >= 0 || candidate.indexOf('?') >= 0 || candidate.indexOf('#') >= 0);
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
