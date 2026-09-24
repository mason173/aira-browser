/**
 * Presence signal for the in-app desktop bookmark clipboard.
 *
 * The clipboard owner lives above the chrome, so the bookmark bar context menu reads this
 * AppStorage signal to decide whether "paste" is available. Only presence is published; the
 * clipboard payload itself never leaves its owner.
 */
export const DESKTOP_BOOKMARK_CLIPBOARD_HAS_CONTENT_KEY: string = 'aira.bookmarks.desktopClipboardHasContent';

export class DesktopBookmarkClipboardSignal {
  static hasContent(): boolean {
    return AppStorage.get<boolean>(DESKTOP_BOOKMARK_CLIPBOARD_HAS_CONTENT_KEY) === true;
  }

  static publish(hasContent: boolean): void {
    AppStorage.setOrCreate(DESKTOP_BOOKMARK_CLIPBOARD_HAS_CONTENT_KEY, hasContent);
  }
}
