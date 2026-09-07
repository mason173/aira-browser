const ENCODED_WHITESPACE_SCHEMES = new Set(['http:', 'https:', 'ftp:']);

export const normalizeChromeBookmarkUrl = (url: string): string => {
  const trimmed = url.trim();
  if (!trimmed) return '';
  const restoredBookmarklet = trimmed.replace(/^https?:\/\/(?=javascript:)/i, '');
  const scheme = restoredBookmarklet.slice(0, Math.max(0, restoredBookmarklet.indexOf(':') + 1)).toLowerCase();
  if (scheme === 'javascript:') {
    return restoredBookmarklet.replace(/%20/g, ' ');
  }
  if (!ENCODED_WHITESPACE_SCHEMES.has(scheme)) {
    return restoredBookmarklet;
  }
  return restoredBookmarklet.replace(/[ \t\r\n]/g, (char) => (
    `%${char.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0')}`
  ));
};

export const canonicalizeSnapshotBookmarkUrls = <T extends {
  bookmarkItems: Record<string, { url: string }>;
}>(snapshot: T): T => {
  let changed = false;
  const bookmarkItems = Object.fromEntries(
    Object.entries(snapshot.bookmarkItems).map(([id, item]) => {
      const url = normalizeChromeBookmarkUrl(item.url);
      if (url === item.url) return [id, item];
      changed = true;
      return [id, { ...item, url }];
    }),
  );
  return changed ? { ...snapshot, bookmarkItems } : snapshot;
};
