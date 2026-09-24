import { describe, expect, it } from '@ohos/hypium';
import { resolveBrowserDesktopMenuShortcutLabel } from '../main/ets/core/browser/BrowserDesktopMenuShortcutCatalog';
import {
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
  BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
} from '../main/ets/core/browser/BrowserDesktopMenuPresentationTokens';

export default function browserDesktopMenuShortcutCatalogTest(): void {
  describe('browserDesktopMenuShortcutCatalogTest', () => {
    it('labels the overflow commands that already have or now gain a shortcut', 0, () => {
      expect(resolveBrowserDesktopMenuShortcutLabel('history')).assertEqual('Ctrl+H');
      expect(resolveBrowserDesktopMenuShortcutLabel('historyPage')).assertEqual('Ctrl+H');
      expect(resolveBrowserDesktopMenuShortcutLabel('openBookmarks')).assertEqual('Ctrl+Shift+O');
      expect(resolveBrowserDesktopMenuShortcutLabel('manager')).assertEqual('Ctrl+Shift+O');
      expect(resolveBrowserDesktopMenuShortcutLabel('downloads')).assertEqual('Ctrl+J');
      expect(resolveBrowserDesktopMenuShortcutLabel('add')).assertEqual('Ctrl+D');
      expect(resolveBrowserDesktopMenuShortcutLabel('bar')).assertEqual('Ctrl+Shift+B');
      expect(resolveBrowserDesktopMenuShortcutLabel('settings')).assertEqual('Ctrl+,');
      expect(resolveBrowserDesktopMenuShortcutLabel('newPrivateTab')).assertEqual('Ctrl+Shift+N');
      expect(resolveBrowserDesktopMenuShortcutLabel('print')).assertEqual('Ctrl+P');
      expect(resolveBrowserDesktopMenuShortcutLabel('elementInspection')).assertEqual('Ctrl+Shift+I');
      expect(resolveBrowserDesktopMenuShortcutLabel('find')).assertEqual('Ctrl+F');
      expect(resolveBrowserDesktopMenuShortcutLabel('offline')).assertEqual('Ctrl+S');
      expect(resolveBrowserDesktopMenuShortcutLabel('novel')).assertEqual('');
    });

    it('keeps a hovered row on the same arc as the menu container', 0, () => {
      expect(BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP).assertEqual(BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP);
      expect(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP).assertEqual(
        BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP - BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP
      );
    });
  });
}
