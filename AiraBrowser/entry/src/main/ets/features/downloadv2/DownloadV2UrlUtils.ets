export function inferDownloadSourceHost(sourceUrl: string): string | undefined {
  const normalizedUrl = sourceUrl.trim();
  if (normalizedUrl.length === 0) {
    return undefined;
  }
  const schemeIndex = normalizedUrl.indexOf('://');
  if (schemeIndex < 0) {
    return undefined;
  }
  const hostStart = schemeIndex + 3;
  const pathStart = normalizedUrl.indexOf('/', hostStart);
  const authority = pathStart >= 0
    ? normalizedUrl.substring(hostStart, pathStart)
    : normalizedUrl.substring(hostStart);
  const host = authority.split('@').pop()?.split(':')[0]?.trim() ?? '';
  return host.length > 0 ? host : undefined;
}
