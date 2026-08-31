import { image } from '@kit.ImageKit';
import { ShortcutRecord } from '../../common/models/BrowserModels';
import {
  ResolvedShortcutIcon,
  ShortcutIconResolverService
} from '../../services/shortcuts/ShortcutIconResolverService';
import { BrowserTabState } from '../tabs/TabManager';

const MAX_BACKGROUND_OPEN_PROMPT_ITEM_COUNT: number = 3;
const BACKGROUND_OPEN_PROMPT_DEFAULT_PROGRESS: number = 1;

export interface BrowserBackgroundOpenPromptItemState {
  tabId: string;
  title: string;
  url: string;
  progress: number;
  isLoading: boolean;
  iconUri: string;
  favicon?: image.PixelMap;
}

export interface BrowserBackgroundOpenPromptState {
  items: BrowserBackgroundOpenPromptItemState[];
}

interface BrowserBackgroundOpenPromptTabPatch {
  title?: string;
  url?: string;
  progress?: number;
  isLoading?: boolean;
  iconUri?: string;
  favicon?: image.PixelMap;
}

export interface BrowserBackgroundOpenPromptShell {
  publishSnapshot: (state: BrowserBackgroundOpenPromptState, animateStack: boolean) => void;
  showQueuedToast: () => void;
}

export class BrowserBackgroundOpenPromptCoordinator {
  private readonly shortcutIconResolver: ShortcutIconResolverService;
  private readonly shell: BrowserBackgroundOpenPromptShell;
  private snapshot: BrowserBackgroundOpenPromptState = {
    items: []
  };
  private iconResolveTokens: Record<string, number> = {};
  private iconResolveGeneration: number = 0;

  constructor(shortcutIconResolver: ShortcutIconResolverService, shell: BrowserBackgroundOpenPromptShell) {
    this.shortcutIconResolver = shortcutIconResolver;
    this.shell = shell;
  }

  getSnapshot(): BrowserBackgroundOpenPromptState {
    return this.snapshot;
  }

  showForTab(tab: BrowserTabState): void {
    const hadPrompt = this.hasPromptForTab(tab.id);
    const nextState = this.buildStateForTab(tab, {
      progress: BACKGROUND_OPEN_PROMPT_DEFAULT_PROGRESS,
      isLoading: !tab.isHome
    });
    const hasPrompt = nextState.items.some((item: BrowserBackgroundOpenPromptItemState) => item.tabId === tab.id);
    if (!hasPrompt && !hadPrompt) {
      this.shell.showQueuedToast();
      return;
    }
    this.publishSnapshot(nextState, true);
    if (!tab.isHome) {
      this.resolveIcon(tab);
    }
  }

  updateTab(tabId: string, patch: BrowserBackgroundOpenPromptTabPatch): void {
    if (this.snapshot.items.length === 0) {
      return;
    }
    let didUpdate = false;
    const nextItems = this.snapshot.items.map((item: BrowserBackgroundOpenPromptItemState) => {
      if (item.tabId !== tabId) {
        return item;
      }
      didUpdate = true;
      const nextUrl = patch.url ?? item.url;
      return {
        tabId: item.tabId,
        title: patch.title !== undefined ? this.resolveTitle(patch.title, nextUrl) : item.title,
        url: nextUrl,
        progress: patch.progress !== undefined ? this.clampProgress(patch.progress) : item.progress,
        isLoading: patch.isLoading ?? item.isLoading,
        iconUri: patch.iconUri ?? item.iconUri,
        favicon: patch.favicon ?? item.favicon
      };
    });
    if (!didUpdate) {
      return;
    }
    this.publishSnapshot({ items: nextItems }, false);
  }

  dismissAll(): void {
    this.iconResolveTokens = {};
    if (this.snapshot.items.length === 0) {
      return;
    }
    this.publishSnapshot({ items: [] }, false);
  }

  dismissTab(tabId: string): void {
    this.removeIconResolveToken(tabId);
    if (this.snapshot.items.length === 0) {
      return;
    }
    const nextItems = this.snapshot.items.filter((item: BrowserBackgroundOpenPromptItemState) => item.tabId !== tabId);
    if (nextItems.length === this.snapshot.items.length) {
      return;
    }
    this.publishSnapshot({ items: nextItems }, false);
  }

  consumeOpenRequest(tabId: string): boolean {
    if (!this.hasPromptForTab(tabId)) {
      return false;
    }
    this.dismissTab(tabId);
    return true;
  }

  private buildStateForTab(
    tab: BrowserTabState,
    patch: BrowserBackgroundOpenPromptTabPatch
  ): BrowserBackgroundOpenPromptState {
    const targetUrl = tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url;
    const item: BrowserBackgroundOpenPromptItemState = {
      tabId: tab.id,
      title: this.resolveTitle(patch.title ?? tab.title, patch.url ?? targetUrl),
      url: patch.url ?? targetUrl,
      progress: patch.progress !== undefined ? this.clampProgress(patch.progress) : 0,
      isLoading: patch.isLoading ?? !tab.isHome,
      iconUri: patch.iconUri ?? '',
      favicon: patch.favicon
    };
    const existingItemIndex = this.snapshot.items.findIndex((currentItem: BrowserBackgroundOpenPromptItemState) =>
      currentItem.tabId === tab.id);
    if (existingItemIndex >= 0) {
      return {
        items: this.snapshot.items.map((currentItem: BrowserBackgroundOpenPromptItemState, index: number) =>
          index === existingItemIndex ? item : currentItem)
      };
    }
    if (this.snapshot.items.length >= MAX_BACKGROUND_OPEN_PROMPT_ITEM_COUNT) {
      return this.snapshot;
    }
    return {
      items: this.snapshot.items.concat([item])
    };
  }

  private resolveIcon(tab: BrowserTabState): void {
    const shortcut = this.buildIconResolutionShortcut(tab);
    if (shortcut === undefined) {
      return;
    }
    const cachedIcon = this.shortcutIconResolver.getCachedShortcutIcon(shortcut);
    if (cachedIcon !== undefined) {
      this.updateTab(tab.id, { iconUri: cachedIcon.path });
      return;
    }
    this.iconResolveGeneration += 1;
    const token = this.iconResolveGeneration;
    this.rememberIconResolveToken(tab.id, token);
    this.shortcutIconResolver.resolveShortcutIcon(shortcut)
      .then((resolvedIcon: ResolvedShortcutIcon | undefined) => {
        if (!this.isIconResolutionCurrent(tab.id, token) || resolvedIcon === undefined ||
          !this.hasPromptForTab(tab.id)) {
          return;
        }
        this.updateTab(tab.id, { iconUri: resolvedIcon.path });
      })
      .catch(() => {
      });
  }

  private buildIconResolutionShortcut(tab: BrowserTabState): ShortcutRecord | undefined {
    const targetUrl = tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url;
    if (targetUrl.trim().length === 0) {
      return undefined;
    }
    return {
      id: `background-open:${tab.id}`,
      title: tab.title,
      url: targetUrl,
      folderName: '',
      position: 0,
      iconRendering: 'favicon'
    };
  }

  private publishSnapshot(state: BrowserBackgroundOpenPromptState, animateStack: boolean): void {
    if (state === this.snapshot) {
      return;
    }
    this.snapshot = state;
    this.shell.publishSnapshot(state, animateStack);
  }

  private hasPromptForTab(tabId: string): boolean {
    return this.snapshot.items.some((item: BrowserBackgroundOpenPromptItemState) => item.tabId === tabId);
  }

  private rememberIconResolveToken(tabId: string, token: number): void {
    const nextTokens: Record<string, number> = {};
    Object.keys(this.iconResolveTokens).forEach((key: string) => {
      nextTokens[key] = this.iconResolveTokens[key];
    });
    nextTokens[tabId] = token;
    this.iconResolveTokens = nextTokens;
  }

  private isIconResolutionCurrent(tabId: string, token: number): boolean {
    return this.iconResolveTokens[tabId] === token;
  }

  private removeIconResolveToken(removedKey: string): void {
    const nextTokens: Record<string, number> = {};
    Object.keys(this.iconResolveTokens).forEach((key: string) => {
      if (key !== removedKey) {
        nextTokens[key] = this.iconResolveTokens[key];
      }
    });
    this.iconResolveTokens = nextTokens;
  }

  private resolveTitle(title: string, url: string): string {
    const normalizedTitle = title.trim();
    if (normalizedTitle.length > 0) {
      return normalizedTitle;
    }
    return url.trim().length > 0 ? url.trim() : '正在后台打开';
  }

  private clampProgress(progress: number): number {
    return Math.max(0, Math.min(100, Math.round(progress)));
  }
}
