import { image } from '@kit.ImageKit';

export type ExternalNavigationPromptTrigger = 'user_gesture' | 'automatic';

export interface ExternalNavigationPromptState {
  visible: boolean;
  tabId: string;
  url: string;
  sourcePageUrl: string;
  title: string;
  subtitle: string;
  appName: string;
  originLabel: string;
  iconUri: string;
  favicon?: image.PixelMap;
  trigger: ExternalNavigationPromptTrigger;
  createdAt: number;
}

export interface ExternalNavigationPromptInput {
  tabId: string;
  url: string;
  sourcePageUrl: string;
  appName: string;
  originLabel: string;
  dataScopeLabel: string;
  iconUri?: string;
  favicon?: image.PixelMap;
  trigger: ExternalNavigationPromptTrigger;
  now: number;
}

export interface ExternalNavigationPromptPageContext {
  activeTabId: string;
  currentPageUrl: string;
  pageVisible: boolean;
}

export interface ExternalNavigationPromptPageContextInput {
  activeTabId: string;
  currentPageUrl: string;
  webPageVisible: boolean;
  tabsOverviewVisible: boolean;
}

export interface ExternalNavigationPromptPresentationContext {
  sourcePageUrl: string;
  favicon?: image.PixelMap;
}

export class ExternalNavigationPromptViewModel {
  createHiddenState(): ExternalNavigationPromptState {
    return {
      visible: false,
      tabId: '',
      url: '',
      sourcePageUrl: '',
      title: '',
      subtitle: '',
      appName: '',
      originLabel: '',
      iconUri: '',
      trigger: 'automatic',
      createdAt: 0
    };
  }

  buildState(input: ExternalNavigationPromptInput): ExternalNavigationPromptState {
    const appName = this.resolveAppName(input.appName);
    const originLabel = this.resolveOriginLabel(input.originLabel, input.dataScopeLabel);
    return {
      visible: true,
      tabId: input.tabId,
      url: input.url,
      sourcePageUrl: input.sourcePageUrl.trim(),
      title: `此网站请求打开 ${appName}`,
      subtitle: `${originLabel} 想切换到其他应用`,
      appName: appName,
      originLabel: originLabel,
      iconUri: input.iconUri ?? '',
      favicon: input.favicon,
      trigger: input.trigger,
      createdAt: input.now
    };
  }

  buildPageContext(input: ExternalNavigationPromptPageContextInput): ExternalNavigationPromptPageContext {
    return {
      activeTabId: input.activeTabId.trim(),
      currentPageUrl: input.currentPageUrl.trim(),
      pageVisible: input.webPageVisible && !input.tabsOverviewVisible
    };
  }

  resolveForPageContext(
    state: ExternalNavigationPromptState,
    context: ExternalNavigationPromptPageContext
  ): ExternalNavigationPromptState {
    if (!state.visible) {
      return state;
    }
    if (!context.pageVisible || state.tabId !== context.activeTabId.trim()) {
      return this.createHiddenState();
    }
    if (!this.matchesSourcePage(state.sourcePageUrl, context.currentPageUrl)) {
      return this.createHiddenState();
    }
    return state;
  }

  hide(state: ExternalNavigationPromptState): ExternalNavigationPromptState {
    if (!state.visible) {
      return state;
    }
    return this.createHiddenState();
  }

  private resolveAppName(appName: string): string {
    const normalized = appName.trim();
    return normalized.length > 0 ? normalized : '其他应用';
  }

  private matchesSourcePage(sourcePageUrl: string, currentPageUrl: string): boolean {
    const source = sourcePageUrl.trim();
    if (source.length <= 0) {
      return true;
    }
    return currentPageUrl.trim() === source;
  }

  private resolveOriginLabel(originLabel: string, dataScopeLabel: string): string {
    const normalizedScope = dataScopeLabel.trim();
    if (normalizedScope.length > 0) {
      return normalizedScope;
    }
    const normalizedOrigin = originLabel.trim();
    return normalizedOrigin.length > 0 ? normalizedOrigin : '当前网站';
  }
}
