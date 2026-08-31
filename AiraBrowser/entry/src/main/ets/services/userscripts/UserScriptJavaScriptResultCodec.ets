export function normalizeUserScriptJavaScriptResult(
  rawResult: Object | string | number | boolean | undefined
): string {
  const value = String(rawResult ?? '');
  const trimmed = value.trim();
  if (trimmed.length < 2 || !trimmed.startsWith('"') || !trimmed.endsWith('"')) {
    return trimmed;
  }
  try {
    const parsed = JSON.parse(trimmed) as string;
    return typeof parsed === 'string' ? parsed.trim() : trimmed;
  } catch (_error) {
    return trimmed.substring(1, trimmed.length - 1);
  }
}
