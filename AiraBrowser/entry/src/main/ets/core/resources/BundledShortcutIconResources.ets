/**
 * Bundled icons for shortcuts whose page is not the thing the shortcut is about.
 *
 * A homepage shortcut normally draws the favicon of the page it opens, which is right
 * for a site and wrong for an app store: an AppGallery detail page's own icon is the
 * store's, not the app's. A shortcut listed here draws an icon that ships with Aira
 * instead, so the tile shows the app the link installs.
 *
 * Rules match on the store page's prefix, not on the exact URL, so the same app keeps
 * its icon whether or not the link carries share parameters. The prefix is deliberately
 * narrow — one app id — so the icon cannot leak onto another AppGallery page.
 */
interface BundledShortcutIconRule {
  urlPrefix: string;
  icon: Resource;
}

const BUNDLED_SHORTCUT_ICON_RULES: BundledShortcutIconRule[] = [
  {
    urlPrefix: 'https://appgallery.huawei.com/app/detail?id=com.noctide.sleep',
    icon: $r('app.media.app_recommendation_shengxi')
  }
];

function matchBundledShortcutIconRule(url: string): BundledShortcutIconRule | undefined {
  const normalizedUrl = url.trim();
  if (normalizedUrl.length === 0) {
    return undefined;
  }
  for (let index = 0; index < BUNDLED_SHORTCUT_ICON_RULES.length; index++) {
    const rule = BUNDLED_SHORTCUT_ICON_RULES[index];
    if (normalizedUrl.startsWith(rule.urlPrefix)) {
      return rule;
    }
  }
  return undefined;
}

/** Whether this shortcut draws a bundled icon instead of the page's favicon. */
export function hasBundledShortcutIcon(url: string): boolean {
  return matchBundledShortcutIconRule(url) !== undefined;
}

/** The bundled icon for this shortcut, or undefined when the page's own icon applies. */
export function resolveBundledShortcutIcon(url: string): Resource | undefined {
  const rule = matchBundledShortcutIconRule(url);
  return rule === undefined ? undefined : rule.icon;
}
