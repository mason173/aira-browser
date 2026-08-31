export function resolveSiteIconFallbackLabel(primaryText: string, secondaryText: string = ''): string {
  const primary = normalizeFallbackText(primaryText);
  if (primary.length > 0) {
    return primary.substring(0, 1).toUpperCase();
  }

  const secondary = normalizeFallbackText(stripUrlScheme(secondaryText));
  if (secondary.length > 0) {
    return secondary.substring(0, 1).toUpperCase();
  }

  return '#';
}

function normalizeFallbackText(value: string): string {
  return value
    .trim()
    .replace(/^www\./i, '')
    .replace(/\s+/g, ' ');
}

function stripUrlScheme(value: string): string {
  const normalized = value.trim().replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
  return normalized.split('/')[0]?.split('?')[0]?.split('#')[0] ?? normalized;
}

