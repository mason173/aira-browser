import {
  ExternalNavigationPromptPageContext,
  ExternalNavigationPromptState,
  ExternalNavigationPromptViewModel
} from './ExternalNavigationPromptViewModel';
import {
  BrowserGestureOnboardingPromptEligibilityInput,
  BrowserGestureOnboardingPromptCoordinator,
  BrowserGestureOnboardingTopPromptState,
  HIDDEN_BROWSER_GESTURE_ONBOARDING_TOP_PROMPT_STATE
} from './BrowserGestureOnboardingPromptCoordinator';
import {
  BrowserBackgroundOpenPromptCoordinator,
  BrowserBackgroundOpenPromptItemState,
  BrowserBackgroundOpenPromptState
} from './BrowserBackgroundOpenPromptCoordinator';
import {
  WebpageTranslationCoordinator,
  WebpageTranslationPanelState,
  WebpageTranslationUserAction
} from '../translation/WebpageTranslationCoordinator';
import {
  OfflinePageSaveCoordinator,
  OfflinePageSaveSessionSnapshot
} from '../offline/OfflinePageSaveCoordinator';
import {
  BrowserExternalNavigationPromptUserAction,
  BrowserUnifiedLinkApplicationCoordinator
} from './BrowserUnifiedLinkApplicationCoordinator';
import { BrowserShellRouteCoordinator } from './BrowserShellRouteCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import { image } from '@kit.ImageKit';
import {
  NovelTopPromptKind,
  NovelTopPromptState,
  resolveNovelContentLabel,
  resolveNovelModeLabel
} from '../../features/novel/NovelReaderModels';
import { NovelReaderSessionOperations } from '../../features/novel/NovelReaderController';
import {
  BrowserUserScriptApplicationCoordinator,
  UserScriptInstallSuccessPromptState
} from '../userscripts/BrowserUserScriptApplicationCoordinator';
import { BrowserUrlThreatNoticeState } from './BrowserUrlThreatProtectionCoordinator';

const TOP_FLOATING_PROMPT_HOME_TOP_GAP: number = 8;
const TOP_FLOATING_PROMPT_TRANSLATION_HOME_TOP_GAP: number = 12;
const TOP_FLOATING_PROMPT_WEB_TOP_GAP: number = 12;
const NOVEL_AUTO_TAKEOVER_PROMPT_DURATION_MS: number = 3000;

export type BrowserTopFloatingPromptKind =
  'url_threat' |
  'background_open' |
  'novel' |
  'offline_save' |
  'external_navigation' |
  'webpage_translation' |
  'user_script_install' |
  'gesture_onboarding';

export interface BrowserTopFloatingPromptAction {
  type: 'open_background_tab' | 'dismiss_background_tab' | 'open_offline_save' | 'dismiss_offline_save' |
    'activate_novel_prompt' | 'dismiss_novel_prompt' | 'external_navigation' | 'webpage_translation' |
    'open_user_script_manager' | 'dismiss_user_script_install' | 'dismiss_gesture_onboarding' |
    'dismiss_url_threat';
  tabId?: string;
  novelPromptKind?: NovelTopPromptKind;
  externalNavigationAction?: BrowserExternalNavigationPromptUserAction;
  webpageTranslationAction?: WebpageTranslationUserAction;
}

export interface BrowserTopFloatingPromptActionDependencies {
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  backgroundOpenPromptCoordinator: BrowserBackgroundOpenPromptCoordinator;
  offlinePageSaveCoordinator: OfflinePageSaveCoordinator;
  routeCoordinator: BrowserShellRouteCoordinator;
  unifiedLinkApplicationCoordinator: BrowserUnifiedLinkApplicationCoordinator;
  webpageTranslationCoordinator: WebpageTranslationCoordinator;
  userScriptApplicationCoordinator: BrowserUserScriptApplicationCoordinator;
  gestureOnboardingPromptCoordinator: BrowserGestureOnboardingPromptCoordinator;
  novelReaderSession: NovelReaderSessionOperations;
}

export interface BrowserTopFloatingPromptActionShell {
  readGestureOnboardingState: () => BrowserGestureOnboardingTopPromptState;
  readGestureOnboardingEligibilityInput: () => BrowserGestureOnboardingPromptEligibilityInput;
  publishGestureOnboardingState: (state: BrowserGestureOnboardingTopPromptState) => void;
  dismissUrlThreatNotice: () => void;
}

export interface BrowserTopActionPromptState {
  visible: boolean;
  key: string;
  topOffsetVp: number;
  title: string;
  subtitle: string;
  fallbackLabel: string;
  iconUri: string;
  airaIconId?: AiraRenderableIconId;
  iconColor?: ResourceColor;
  iconBackgroundColor?: ResourceColor;
  favicon?: image.PixelMap;
  actionText: string;
}

export interface BrowserOfflineSaveTopPromptState extends BrowserTopActionPromptState {
}

export interface BrowserNovelTopPromptState extends BrowserTopActionPromptState {
  kind: NovelTopPromptKind;
}

export interface BrowserUserScriptInstallTopPromptState extends BrowserTopActionPromptState {
}

export interface BrowserUrlThreatTopPromptState extends BrowserTopActionPromptState {
}

export interface BrowserBackgroundOpenTopPromptState extends BrowserTopActionPromptState {
  tabId: string;
  progress: number;
  isLoading: boolean;
}

export interface BrowserExternalNavigationTopPromptState {
  state: ExternalNavigationPromptState;
  topOffsetVp: number;
}

export interface BrowserWebpageTranslationTopPromptState {
  visible: boolean;
  state: WebpageTranslationPanelState;
  topOffsetVp: number;
}

export interface BrowserTopFloatingPromptHostInput {
  urlThreat: BrowserUrlThreatTopPromptState;
  backgroundOpen: BrowserBackgroundOpenTopPromptState;
  novelPrompt: BrowserNovelTopPromptState;
  userScriptInstall: BrowserUserScriptInstallTopPromptState;
  offlineSave: BrowserOfflineSaveTopPromptState;
  externalNavigation: BrowserExternalNavigationTopPromptState;
  webpageTranslation: BrowserWebpageTranslationTopPromptState;
  gestureOnboarding: BrowserGestureOnboardingTopPromptState;
}

export interface BrowserTopFloatingPromptHostState {
  mounted: boolean;
  activeKind: BrowserTopFloatingPromptKind;
  urlThreat: BrowserUrlThreatTopPromptState;
  backgroundOpen: BrowserBackgroundOpenTopPromptState;
  novelPrompt: BrowserNovelTopPromptState;
  userScriptInstall: BrowserUserScriptInstallTopPromptState;
  offlineSave: BrowserOfflineSaveTopPromptState;
  externalNavigation: BrowserExternalNavigationTopPromptState;
  webpageTranslation: BrowserWebpageTranslationTopPromptState;
  gestureOnboarding: BrowserGestureOnboardingTopPromptState;
}

export interface BrowserTopFloatingPromptOffsetInput {
  showHomePage: boolean;
  topInsetVp: number;
  webTopChromeOverlayHeightVp: number;
}

export interface BrowserTopFloatingPromptShellInput {
  urlThreatNotice: BrowserUrlThreatNoticeState;
  backgroundOpenState: BrowserBackgroundOpenPromptState;
  tabsSheetVisible: boolean;
  novelPrompt: NovelTopPromptState;
  userScriptInstallPrompt: UserScriptInstallSuccessPromptState;
  externalNavigationState: ExternalNavigationPromptState;
  externalNavigationPageContext: ExternalNavigationPromptPageContext;
  offlineSave: OfflinePageSaveSessionSnapshot;
  webpageTranslationState: WebpageTranslationPanelState;
  webpageTranslationSurfaceVisible: boolean;
  gestureOnboardingState: BrowserGestureOnboardingTopPromptState;
  nativeVideoTakeoverVisible: boolean;
  offsets: BrowserTopFloatingPromptOffsetInput;
}

export class BrowserTopFloatingPromptCoordinator {
  private readonly actionDependencies: BrowserTopFloatingPromptActionDependencies;
  private readonly actionShell: BrowserTopFloatingPromptActionShell;
  private externalNavigationPromptViewModel: ExternalNavigationPromptViewModel =
    new ExternalNavigationPromptViewModel();
  private novelAutoDismissTimer: number = 0;
  private novelAutoDismissKey: string = '';

  constructor(
    actionDependencies: BrowserTopFloatingPromptActionDependencies,
    actionShell: BrowserTopFloatingPromptActionShell
  ) {
    this.actionDependencies = actionDependencies;
    this.actionShell = actionShell;
  }

  handleAction(action: BrowserTopFloatingPromptAction): void {
    if (action.type === 'dismiss_url_threat') {
      this.actionShell.dismissUrlThreatNotice();
      return;
    }
    if (action.type === 'open_background_tab') {
      if (action.tabId !== undefined) {
        void this.actionDependencies.tabSwitchCoordinator.openBackgroundPromptTab(action.tabId);
      }
      return;
    }
    if (action.type === 'dismiss_background_tab') {
      if (action.tabId !== undefined) {
        this.actionDependencies.backgroundOpenPromptCoordinator.dismissTab(action.tabId);
      }
      return;
    }
    if (action.type === 'activate_novel_prompt') {
      if (action.novelPromptKind === 'auto_takeover') {
        this.actionDependencies.novelReaderSession.handleAction({ type: 'return_to_source' });
      } else {
        this.actionDependencies.novelReaderSession.handleAction({ type: 'dismiss_top_prompt' });
        this.actionDependencies.routeCoordinator.openNovelBookshelfPage();
      }
      return;
    }
    if (action.type === 'dismiss_novel_prompt') {
      this.actionDependencies.novelReaderSession.handleAction({ type: 'dismiss_top_prompt' });
      return;
    }
    if (action.type === 'open_offline_save') {
      this.actionDependencies.offlinePageSaveCoordinator.dismissActionPrompt();
      this.actionDependencies.routeCoordinator.openOfflinePagesPage();
      return;
    }
    if (action.type === 'dismiss_offline_save') {
      this.actionDependencies.offlinePageSaveCoordinator.dismissActionPrompt();
      return;
    }
    if (action.type === 'open_user_script_manager') {
      this.actionDependencies.userScriptApplicationCoordinator.openInstallSuccessPrompt();
      return;
    }
    if (action.type === 'dismiss_user_script_install') {
      this.actionDependencies.userScriptApplicationCoordinator.dismissInstallSuccessPrompt();
      return;
    }
    if (action.type === 'external_navigation') {
      if (action.externalNavigationAction !== undefined) {
        this.actionDependencies.unifiedLinkApplicationCoordinator.handleExternalNavigationPromptAction(
          action.externalNavigationAction
        );
      }
      return;
    }
    if (action.type === 'webpage_translation') {
      if (action.webpageTranslationAction !== undefined) {
        this.actionDependencies.webpageTranslationCoordinator.handleUserAction(action.webpageTranslationAction);
      }
      return;
    }
    this.actionShell.publishGestureOnboardingState(
      this.actionDependencies.gestureOnboardingPromptCoordinator.dismiss(
        this.actionShell.readGestureOnboardingState()
      )
    );
  }

  scheduleGestureOnboardingPrompt(): void {
    this.actionDependencies.gestureOnboardingPromptCoordinator.scheduleFirstPrompt(
      (): BrowserGestureOnboardingPromptEligibilityInput =>
        this.actionShell.readGestureOnboardingEligibilityInput(),
      (state: BrowserGestureOnboardingTopPromptState): void => {
        this.actionShell.publishGestureOnboardingState(state);
      }
    );
  }

  buildShellState(input: BrowserTopFloatingPromptShellInput): BrowserTopFloatingPromptHostState {
    this.reconcileNovelAutoDismiss(input.novelPrompt);
    const backgroundTopOffset = this.resolveBackgroundOpenTopOffsetVp(input.offsets);
    const translationTopOffset = this.resolveTranslationTopOffsetVp(input.offsets);
    const externalNavigationState = this.externalNavigationPromptViewModel.resolveForPageContext(
      input.externalNavigationState,
      input.externalNavigationPageContext
    );
    const state = this.buildState({
      urlThreat: this.buildUrlThreatTopPromptState(input.urlThreatNotice, backgroundTopOffset),
      backgroundOpen: this.buildBackgroundOpenTopPromptState(
        input.backgroundOpenState,
        input.backgroundOpenState.items.length > 0 && !input.tabsSheetVisible,
        backgroundTopOffset
      ),
      novelPrompt: this.buildNovelTopPromptState(
        input.novelPrompt,
        backgroundTopOffset
      ),
      userScriptInstall: this.buildUserScriptInstallTopPromptState(
        input.userScriptInstallPrompt,
        backgroundTopOffset
      ),
      offlineSave: this.buildOfflineSaveTopPromptState(input.offlineSave, backgroundTopOffset),
      externalNavigation: {
        state: externalNavigationState,
        topOffsetVp: backgroundTopOffset
      },
      webpageTranslation: {
        visible: input.webpageTranslationState.visible && input.webpageTranslationSurfaceVisible,
        state: input.webpageTranslationState,
        topOffsetVp: translationTopOffset
      },
      gestureOnboarding: this.buildGestureOnboardingTopPromptState(input.gestureOnboardingState, backgroundTopOffset)
    });
    if (!input.nativeVideoTakeoverVisible) {
      return state;
    }
    return {
      mounted: false,
      activeKind: state.activeKind,
      urlThreat: state.urlThreat,
      backgroundOpen: state.backgroundOpen,
      novelPrompt: state.novelPrompt,
      userScriptInstall: state.userScriptInstall,
      offlineSave: state.offlineSave,
      externalNavigation: state.externalNavigation,
      webpageTranslation: state.webpageTranslation,
      gestureOnboarding: state.gestureOnboarding
    };
  }

  buildState(input: BrowserTopFloatingPromptHostInput): BrowserTopFloatingPromptHostState {
    const activeKind = this.resolveActiveKind(input);
    return {
      mounted: activeKind.length > 0,
      activeKind: activeKind.length > 0 ? activeKind as BrowserTopFloatingPromptKind : 'background_open',
      urlThreat: input.urlThreat,
      backgroundOpen: input.backgroundOpen,
      novelPrompt: input.novelPrompt,
      userScriptInstall: input.userScriptInstall,
      offlineSave: input.offlineSave,
      externalNavigation: input.externalNavigation,
      webpageTranslation: input.webpageTranslation,
      gestureOnboarding: input.gestureOnboarding
    };
  }

  resolveBackgroundOpenTopOffsetVp(input: BrowserTopFloatingPromptOffsetInput): number {
    if (input.showHomePage) {
      return input.topInsetVp + TOP_FLOATING_PROMPT_HOME_TOP_GAP;
    }
    return input.webTopChromeOverlayHeightVp + TOP_FLOATING_PROMPT_WEB_TOP_GAP;
  }

  resolveTranslationTopOffsetVp(input: BrowserTopFloatingPromptOffsetInput): number {
    if (input.showHomePage) {
      return input.topInsetVp + TOP_FLOATING_PROMPT_TRANSLATION_HOME_TOP_GAP;
    }
    return input.webTopChromeOverlayHeightVp + TOP_FLOATING_PROMPT_WEB_TOP_GAP;
  }

  private buildUrlThreatTopPromptState(
    state: BrowserUrlThreatNoticeState,
    topOffsetVp: number
  ): BrowserUrlThreatTopPromptState {
    return {
      visible: state.visible,
      key: state.key,
      topOffsetVp: topOffsetVp,
      title: state.title,
      subtitle: state.subtitle,
      fallbackLabel: '网站安全提醒',
      iconUri: '',
      airaIconId: 'browser.toolbar.reportSite',
      actionText: ''
    };
  }

  private buildOfflineSaveTopPromptState(
    state: OfflinePageSaveSessionSnapshot,
    topOffsetVp: number
  ): BrowserOfflineSaveTopPromptState {
    return {
      visible: state.visible,
      key: this.buildOfflineSaveActionPromptKey(state),
      topOffsetVp: topOffsetVp,
      title: state.message,
      subtitle: this.resolveOfflineSaveActionPromptSubtitle(state),
      fallbackLabel: this.resolveOfflineSaveActionPromptFallbackLabel(state),
      iconUri: state.iconUri,
      favicon: state.favicon,
      actionText: '查看'
    };
  }

  private buildNovelTopPromptState(
    state: NovelTopPromptState,
    topOffsetVp: number
  ): BrowserNovelTopPromptState {
    const bookTitle: string = state.bookTitle.trim();
    if (state.kind === 'auto_takeover') {
      const modeLabel: string = resolveNovelModeLabel(state.contentKind);
      return {
        visible: state.visible,
        key: state.key,
        kind: state.kind,
        topOffsetVp: topOffsetVp,
        title: `已自动进入${modeLabel}`,
        subtitle: bookTitle.length > 0 ? bookTitle : modeLabel,
        fallbackLabel: bookTitle.length > 0 ? bookTitle : modeLabel,
        iconUri: '',
        airaIconId: 'browser.toolbar.reader',
        actionText: '返回原网页'
      };
    }
    return {
      visible: state.visible,
      key: state.key,
      kind: state.kind,
      topOffsetVp: topOffsetVp,
      title: '已加入书架',
      subtitle: bookTitle.length > 0 ? bookTitle : `已收藏这本${resolveNovelContentLabel(state.contentKind)}`,
      fallbackLabel: bookTitle.length > 0 ? bookTitle : `我的${resolveNovelContentLabel(state.contentKind)}书架`,
      iconUri: '',
      airaIconId: 'browser.toolbar.bookshelf',
      actionText: '查看'
    };
  }

  private buildUserScriptInstallTopPromptState(
    state: UserScriptInstallSuccessPromptState,
    topOffsetVp: number
  ): BrowserUserScriptInstallTopPromptState {
    return {
      visible: state.visible,
      key: state.key,
      topOffsetVp: topOffsetVp,
      title: state.title,
      subtitle: state.subtitle,
      fallbackLabel: state.scriptName,
      iconUri: '',
      airaIconId: 'userscripts.defaultIcon',
      actionText: '管理'
    };
  }

  private buildBackgroundOpenTopPromptState(
    state: BrowserBackgroundOpenPromptState,
    visible: boolean,
    topOffsetVp: number
  ): BrowserBackgroundOpenTopPromptState {
    const item = this.resolveLatestBackgroundOpenItem(state);
    if (item === undefined) {
      return this.createHiddenBackgroundOpenTopPromptState(topOffsetVp);
    }
    return {
      visible: visible,
      key: item.tabId,
      topOffsetVp: topOffsetVp,
      title: item.title,
      subtitle: item.url.trim().length > 0 ? item.url.trim() : '已在后台打开',
      fallbackLabel: this.resolveBackgroundOpenFallbackLabel(item),
      iconUri: item.iconUri,
      favicon: item.favicon,
      actionText: this.resolveBackgroundOpenActionText(item),
      tabId: item.tabId,
      progress: item.progress,
      isLoading: item.isLoading
    };
  }

  private createHiddenBackgroundOpenTopPromptState(topOffsetVp: number): BrowserBackgroundOpenTopPromptState {
    return {
      visible: false,
      key: '',
      topOffsetVp: topOffsetVp,
      title: '',
      subtitle: '',
      fallbackLabel: '',
      iconUri: '',
      actionText: '',
      tabId: '',
      progress: 0,
      isLoading: false
    };
  }

  private resolveLatestBackgroundOpenItem(
    state: BrowserBackgroundOpenPromptState
  ): BrowserBackgroundOpenPromptItemState | undefined {
    if (state.items.length === 0) {
      return undefined;
    }
    return state.items[state.items.length - 1];
  }

  private resolveBackgroundOpenActionText(item: BrowserBackgroundOpenPromptItemState): string {
    if (!item.isLoading || item.progress >= 100) {
      return '打开';
    }
    return `${Math.max(1, Math.min(99, Math.round(item.progress)))}%`;
  }

  private resolveBackgroundOpenFallbackLabel(item: BrowserBackgroundOpenPromptItemState): string {
    const normalizedTitle = item.title.trim();
    if (normalizedTitle.length > 0) {
      return normalizedTitle;
    }
    const normalizedUrl = item.url.trim();
    return normalizedUrl.length > 0 ? normalizedUrl : '后台打开';
  }

  private resolveOfflineSaveActionPromptSubtitle(state: OfflinePageSaveSessionSnapshot): string {
    const normalizedUrl = state.url.trim();
    if (normalizedUrl.length > 0) {
      return normalizedUrl;
    }
    const normalizedTitle = state.title.trim();
    return normalizedTitle.length > 0 ? normalizedTitle : '已保存离线网页';
  }

  private resolveOfflineSaveActionPromptFallbackLabel(state: OfflinePageSaveSessionSnapshot): string {
    const normalizedTitle = state.title.trim();
    if (normalizedTitle.length > 0) {
      return normalizedTitle;
    }
    const normalizedUrl = state.url.trim();
    return normalizedUrl.length > 0 ? normalizedUrl : state.message;
  }

  private buildOfflineSaveActionPromptKey(state: OfflinePageSaveSessionSnapshot): string {
    return `${state.message}:${state.url}:${state.title}:${state.iconUri}`;
  }

  private buildGestureOnboardingTopPromptState(
    state: BrowserGestureOnboardingTopPromptState,
    topOffsetVp: number
  ): BrowserGestureOnboardingTopPromptState {
    if (!state.visible) {
      return HIDDEN_BROWSER_GESTURE_ONBOARDING_TOP_PROMPT_STATE;
    }
    return {
      visible: true,
      key: state.key,
      topOffsetVp: topOffsetVp,
      title: state.title,
      subtitle: state.subtitle
    };
  }

  private resolveActiveKind(input: BrowserTopFloatingPromptHostInput): string {
    if (input.urlThreat.visible) {
      return 'url_threat';
    }
    if (input.externalNavigation.state.visible) {
      return 'external_navigation';
    }
    if (input.webpageTranslation.visible && input.webpageTranslation.state.visible) {
      return 'webpage_translation';
    }
    if (input.novelPrompt.visible) {
      return 'novel';
    }
    if (input.userScriptInstall.visible) {
      return 'user_script_install';
    }
    if (input.backgroundOpen.visible && input.backgroundOpen.tabId.length > 0) {
      return 'background_open';
    }
    if (input.offlineSave.visible) {
      return 'offline_save';
    }
    if (input.gestureOnboarding.visible) {
      return 'gesture_onboarding';
    }
    return '';
  }

  private reconcileNovelAutoDismiss(state: NovelTopPromptState): void {
    const key: string = state.visible && state.kind === 'auto_takeover' ? state.key : '';
    if (key.length === 0) {
      this.cancelNovelAutoDismiss();
      return;
    }
    if (key === this.novelAutoDismissKey && this.novelAutoDismissTimer !== 0) {
      return;
    }
    this.cancelNovelAutoDismiss();
    this.novelAutoDismissKey = key;
    this.novelAutoDismissTimer = setTimeout((): void => {
      if (this.novelAutoDismissKey !== key) {
        return;
      }
      this.novelAutoDismissTimer = 0;
      this.novelAutoDismissKey = '';
      this.actionDependencies.novelReaderSession.handleAction({ type: 'dismiss_top_prompt' });
    }, NOVEL_AUTO_TAKEOVER_PROMPT_DURATION_MS);
  }

  private cancelNovelAutoDismiss(): void {
    if (this.novelAutoDismissTimer !== 0) {
      clearTimeout(this.novelAutoDismissTimer);
      this.novelAutoDismissTimer = 0;
    }
    this.novelAutoDismissKey = '';
  }
}
