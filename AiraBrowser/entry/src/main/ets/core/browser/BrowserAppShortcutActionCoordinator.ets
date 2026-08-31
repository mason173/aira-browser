export type BrowserAppShortcutInlineAction = 'none' | 'scan_qr' | 'focus_search';

export interface BrowserAppShortcutActionPlan {
  inlineAction: BrowserAppShortcutInlineAction;
  shouldRoute: boolean;
}

export class BrowserAppShortcutActionCoordinator {
  buildPlan(target: string): BrowserAppShortcutActionPlan {
    if (target === 'scanQr') {
      return {
        inlineAction: 'scan_qr',
        shouldRoute: false
      };
    }
    if (target === 'search') {
      return {
        inlineAction: 'focus_search',
        shouldRoute: false
      };
    }
    return {
      inlineAction: 'none',
      shouldRoute: target.length > 0
    };
  }
}
