export type BrowserNavigationTransition =
  'link' |
  'typed' |
  'auto_bookmark' |
  'generated' |
  'explicit';

export type BrowserNavigationScene =
  'bookmark' |
  'history' |
  'shortcut' |
  'context_menu' |
  'offline' |
  'userscript' |
  'app_ui';

export interface BrowserNavigationTransitionResolution {
  transition: BrowserNavigationTransition;
  scene: BrowserNavigationScene;
  reason: string;
}

export class BrowserNavigationTransitionService {
  resolve(source: string, intent: string): BrowserNavigationTransitionResolution {
    const scene = this.resolveScene(source);
    return {
      transition: this.resolveTransition(scene),
      scene: scene,
      reason: `${scene}_${this.normalizeIntent(intent)}`
    };
  }

  private resolveScene(source: string): BrowserNavigationScene {
    if (source === 'bookmark') {
      return 'bookmark';
    }
    if (source === 'history') {
      return 'history';
    }
    if (source === 'home_shortcut') {
      return 'shortcut';
    }
    if (source === 'web_context_menu') {
      return 'context_menu';
    }
    if (source === 'offline') {
      return 'offline';
    }
    if (source === 'userscript_install') {
      return 'userscript';
    }
    return 'app_ui';
  }

  private resolveTransition(scene: BrowserNavigationScene): BrowserNavigationTransition {
    if (scene === 'bookmark') {
      return 'auto_bookmark';
    }
    if (scene === 'history') {
      return 'generated';
    }
    if (scene === 'context_menu') {
      return 'link';
    }
    if (scene === 'app_ui') {
      return 'typed';
    }
    return 'explicit';
  }

  private normalizeIntent(intent: string): string {
    if (intent === 'new_tab' || intent === 'background_tab') {
      return intent;
    }
    return 'current_tab';
  }
}
