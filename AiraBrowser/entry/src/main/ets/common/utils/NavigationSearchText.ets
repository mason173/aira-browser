/** Shared normalization for omnibox matches and full bookmark-search handoffs. */
export function normalizeNavigationSearchText(value: string): string {
  let compact = value.trim().toLowerCase().replace(/\s+/g, '');
  if (compact.startsWith('https://')) {
    compact = compact.substring('https://'.length);
  } else if (compact.startsWith('http://')) {
    compact = compact.substring('http://'.length);
  }
  if (compact.startsWith('www.')) {
    compact = compact.substring('www.'.length);
  }
  if (compact.endsWith('/') && compact.indexOf('?') < 0 && compact.indexOf('#') < 0) {
    compact = compact.substring(0, compact.length - 1);
  }
  return compact;
}

