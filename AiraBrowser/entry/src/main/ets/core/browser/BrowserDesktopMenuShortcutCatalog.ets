/**
 * Shortcut labels shown on the desktop overflow menu and its flyouts.
 * Labels stay here so the menu, the settings list, and the key bindings cannot drift.
 */
export function resolveBrowserDesktopMenuShortcutLabel(actionId: string): string {
  switch (actionId) {
    case 'history':
    case 'historyPage':
      return 'Ctrl+H';
    case 'openBookmarks':
    case 'manager':
      return 'Ctrl+Shift+O';
    case 'downloads':
      return 'Ctrl+J';
    case 'find':
      return 'Ctrl+F';
    case 'offline':
      return 'Ctrl+S';
    case 'bookmark':
    case 'add':
      return 'Ctrl+D';
    case 'bar':
      return 'Ctrl+Shift+B';
    case 'settings':
      return 'Ctrl+,';
    case 'newPrivateTab':
      return 'Ctrl+Shift+N';
    case 'print':
      return 'Ctrl+P';
    case 'elementInspection':
      return 'Ctrl+Shift+I';
    case 'fullScreenMode':
      return 'F11';
    default:
      return '';
  }
}
