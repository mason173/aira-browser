/**
 * Store detail pages that a homepage shortcut hands over to the store app.
 *
 * A shortcut normally opens the page it holds, and a store detail page is a page. When
 * the tile is about an app the user is meant to install rather than about the page, the
 * store app is where that ends: a browser tab of the same page is a read-only facsimile
 * the user then has to leave by hand.
 *
 * This list is the single declaration of which store pages those are. The icon a tile
 * draws and the hand-over its open performs both read it, so the two can never disagree
 * about which app a page belongs to.
 *
 * Rules match the page prefix, not the exact URL, so the same app still hands over when
 * the link carries share or channel parameters. Every prefix stays deliberately narrow —
 * one app id — so a hand-over cannot leak onto another store page the user saved.
 */
export interface ShortcutStoreHandoff {
  urlPrefix: string;
  storeId: string;
}

const SHORTCUT_STORE_HANDOFFS: ShortcutStoreHandoff[] = [
  {
    urlPrefix: 'https://appgallery.huawei.com/app/detail?id=com.noctide.sleep',
    storeId: 'com.noctide.sleep'
  }
];

/** The store app this page belongs to, or undefined for an ordinary page. */
export function resolveShortcutStoreHandoffId(url: string): string | undefined {
  const normalizedUrl = url.trim();
  if (normalizedUrl.length === 0) {
    return undefined;
  }
  for (let index = 0; index < SHORTCUT_STORE_HANDOFFS.length; index++) {
    const rule = SHORTCUT_STORE_HANDOFFS[index];
    if (normalizedUrl.startsWith(rule.urlPrefix)) {
      return rule.storeId;
    }
  }
  return undefined;
}
