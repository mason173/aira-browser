import { BrowserAppUrlOpenIntent } from '../browser/BrowserAppUrlOpenCoordinator';

export class BookmarkOpenActionViewModel {
  resolveIntent(actionId: string): BrowserAppUrlOpenIntent | undefined {
    if (actionId === 'open_current_tab') {
      return 'current_tab';
    }
    if (actionId === 'open_new_tab') {
      return 'new_tab';
    }
    if (actionId === 'open_background_tab') {
      return 'background_tab';
    }
    return undefined;
  }
}
