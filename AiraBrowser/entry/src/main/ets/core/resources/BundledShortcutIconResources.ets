import { resolveShortcutStoreHandoffId } from '../../services/shortcuts/ShortcutStoreHandoffCatalog';

/**
 * Bundled icons for shortcuts whose page is not the thing the shortcut is about.
 *
 * A homepage shortcut normally draws the favicon of the page it opens, which is right
 * for a site and wrong for an app store: an AppGallery detail page's own icon is the
 * store's, not the app's. A shortcut listed here draws an icon that ships with Aira
 * instead, so the tile shows the app the link installs.
 *
 * A rule names the app, not the page: which pages are store pages is declared once, in
 * `ShortcutStoreHandoffCatalog`, and the icon is looked up by the app that declaration
 * resolves. A store page with no rule here simply keeps drawing the store's own icon.
 */
interface BundledShortcutIconRule {
  storeId: string;
  icon: Resource;
}

const BUNDLED_SHORTCUT_ICON_RULES: BundledShortcutIconRule[] = [
  {
    storeId: 'com.noctide.sleep',
    icon: $r('app.media.app_recommendation_shengxi')
  }
];

function matchBundledShortcutIconRule(url: string): BundledShortcutIconRule | undefined {
  const storeId = resolveShortcutStoreHandoffId(url);
  if (storeId === undefined) {
    return undefined;
  }
  for (let index = 0; index < BUNDLED_SHORTCUT_ICON_RULES.length; index++) {
    const rule = BUNDLED_SHORTCUT_ICON_RULES[index];
    if (rule.storeId === storeId) {
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
