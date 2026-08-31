import { UserScriptPageActionsState } from '../../features/userscripts/UserScriptRuntimeModels';
import { UserScriptInstallUrlService } from '../../services/userscripts/UserScriptInstallUrlService';
import { BrowserShellRouteCoordinator } from '../browser/BrowserShellRouteCoordinator';
import {
  BrowserTransientSurfaceCoordinator,
  BrowserTransientSurfaceUpdate
} from '../browser/BrowserTransientSurfaceCoordinator';
import { UserScriptRuntimeCoordinator } from './UserScriptRuntimeCoordinator';
import { UserScriptPackageSuccessResult } from './UserScriptPackageLifecycleCoordinator';
import {
  buildUserScriptPackageSuccessPromptCopy,
  UserScriptPackageSuccessPromptCopy
} from './UserScriptFeatureCopy';
import {
  BrowserDataScope,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';

const USER_SCRIPT_INSTALL_SUCCESS_PROMPT_AUTO_DISMISS_MS: number = 4000;

export interface BrowserUserScriptInstallBoundary {
  dataScope: BrowserDataScope;
  privacyMode: BrowserSessionPrivacyMode;
}

const REGULAR_USER_SCRIPT_INSTALL_BOUNDARY: BrowserUserScriptInstallBoundary = {
  dataScope: 'profile_persistent',
  privacyMode: 'regular'
};

export interface UserScriptInstallSuccessPromptState {
  visible: boolean;
  key: string;
  sourceUrl: string;
  scriptName: string;
  title: string;
  subtitle: string;
}

const HIDDEN_USER_SCRIPT_INSTALL_SUCCESS_PROMPT_STATE: UserScriptInstallSuccessPromptState = {
  visible: false,
  key: '',
  sourceUrl: '',
  scriptName: '',
  title: '',
  subtitle: ''
};

export interface BrowserUserScriptApplicationSnapshot {
  installUrl: string;
  installBoundary: BrowserUserScriptInstallBoundary;
  installSuccessPrompt: UserScriptInstallSuccessPromptState;
  pageActionsPopupVisible: boolean;
  pageActionsState: UserScriptPageActionsState;
}

export function createBrowserUserScriptApplicationSnapshot(): BrowserUserScriptApplicationSnapshot {
  return {
    installUrl: '',
    installBoundary: REGULAR_USER_SCRIPT_INSTALL_BOUNDARY,
    installSuccessPrompt: HIDDEN_USER_SCRIPT_INSTALL_SUCCESS_PROMPT_STATE,
    pageActionsPopupVisible: false,
    pageActionsState: {
      url: '',
      message: '打开网页后会显示当前页脚本菜单。',
      hasPage: false,
      hasMatchingScripts: false,
      hasMenuCommands: false,
      matchingScriptCount: 0,
      commands: [],
      scripts: []
    }
  };
}

export interface BrowserUserScriptApplicationAction {
  type:
    'open_page_actions' |
    'refresh_page_actions' |
    'dismiss_page_actions' |
    'open_manager' |
    'run_page_command';
  scriptId?: string;
  commandId?: string;
}

export interface BrowserUserScriptApplicationFacts {
  activeTabId: string;
  currentUrl: string;
  privateMode: boolean;
  installDataScope: BrowserDataScope;
  installPrivacyMode: BrowserSessionPrivacyMode;
  presentationMode: 'phone' | 'large_screen';
}

export interface BrowserUserScriptApplicationEffect {
  type: 'set_helper_message' | 'set_error_message';
  message: string;
}

export interface BrowserUserScriptApplicationDependencies {
  runtimeCoordinator: UserScriptRuntimeCoordinator;
  transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  routeCoordinator: BrowserShellRouteCoordinator;
  captureFacts: () => BrowserUserScriptApplicationFacts;
  publishSnapshot: (snapshot: BrowserUserScriptApplicationSnapshot) => void;
  executeEffect: (effect: BrowserUserScriptApplicationEffect) => void;
  pageActionsRevealDelayMs: number;
  pageActionsDismissDurationMs: number;
}

export class BrowserUserScriptApplicationCoordinator {
  private readonly dependencies: BrowserUserScriptApplicationDependencies;
  private readonly installUrlService: UserScriptInstallUrlService = new UserScriptInstallUrlService();
  private snapshot: BrowserUserScriptApplicationSnapshot;
  private pageActionsGeneration: number = 0;
  private pageCommandGeneration: number = 0;
  private pageActionsActive: boolean = false;
  private installSuccessPromptDismissTimer: number = 0;

  constructor(dependencies: BrowserUserScriptApplicationDependencies) {
    this.dependencies = dependencies;
    this.snapshot = {
      installUrl: '',
      installBoundary: REGULAR_USER_SCRIPT_INSTALL_BOUNDARY,
      installSuccessPrompt: HIDDEN_USER_SCRIPT_INSTALL_SUCCESS_PROMPT_STATE,
      pageActionsPopupVisible: false,
      pageActionsState: dependencies.runtimeCoordinator.createInitialPageActionsState()
    };
  }

  getSnapshot(): BrowserUserScriptApplicationSnapshot {
    return this.snapshot;
  }

  handleInstallCandidate(url: string): boolean {
    const installUrl = this.installUrlService.resolveInstallUrl(url);
    if (installUrl.length <= 0) {
      return false;
    }
    if (installUrl === this.snapshot.installUrl ||
      (this.snapshot.installSuccessPrompt.visible &&
        installUrl === this.snapshot.installSuccessPrompt.sourceUrl)) {
      return true;
    }
    const facts = this.dependencies.captureFacts();
    const installBoundary: BrowserUserScriptInstallBoundary = {
      dataScope: facts.installDataScope,
      privacyMode: facts.installPrivacyMode
    };
    this.publishInstallRequest(installUrl, installBoundary);
    this.dependencies.transientSurfaceCoordinator.openSystemSheet('userScriptInstall');
    return true;
  }

  closeInstallSheet(): void {
    this.dependencies.transientSurfaceCoordinator.closeSystemSheet();
  }

  handleInstallCompleted(result: UserScriptPackageSuccessResult): void {
    const sourceUrl = this.snapshot.installUrl;
    this.closeInstallSheet();
    const copy: UserScriptPackageSuccessPromptCopy = buildUserScriptPackageSuccessPromptCopy(result);
    this.publishInstallSuccessPrompt({
      visible: true,
      key: `${result.status}:${result.scriptId}:${Date.now()}`,
      sourceUrl: sourceUrl,
      scriptName: result.scriptName,
      title: copy.title,
      subtitle: copy.subtitle
    });
    this.scheduleInstallSuccessPromptDismiss();
  }

  openInstallSuccessPrompt(): void {
    this.dismissInstallSuccessPrompt();
    this.dependencies.routeCoordinator.openUserScriptsPage();
  }

  dismissInstallSuccessPrompt(): void {
    this.clearInstallSuccessPromptDismissTimer();
    if (!this.snapshot.installSuccessPrompt.visible) {
      return;
    }
    this.publishInstallSuccessPrompt(HIDDEN_USER_SCRIPT_INSTALL_SUCCESS_PROMPT_STATE);
  }

  dispose(): void {
    this.dismissInstallSuccessPrompt();
  }

  handleAction(action: BrowserUserScriptApplicationAction): void {
    switch (action.type) {
      case 'open_page_actions':
        this.openPageActions();
        return;
      case 'refresh_page_actions':
        this.refreshPageActions();
        return;
      case 'dismiss_page_actions':
        this.dismissPageActions();
        return;
      case 'open_manager':
        this.openManager();
        return;
      case 'run_page_command':
        this.runPageCommand(action.scriptId ?? '', action.commandId ?? '');
        return;
    }
  }

  handleSurfaceUpdate(update: BrowserTransientSurfaceUpdate): void {
    if (update.lane === 'system_sheet') {
      if (this.snapshot.installUrl.length > 0 &&
        (update.reason === 'system_disappear' || update.reason === 'system_reset')) {
        this.publishInstallRequest('', REGULAR_USER_SCRIPT_INSTALL_BOUNDARY);
      }
      return;
    }
    const terminal = update.reason === 'dismissed' || update.reason === 'reset';
    if (update.surfaceId === 'userscript_page_actions' &&
      (update.reason === 'dismiss' || terminal)) {
      this.invalidatePageActions();
    }
  }

  private openPageActions(): void {
    const facts = this.dependencies.captureFacts();
    if (facts.presentationMode === 'large_screen' && this.snapshot.pageActionsPopupVisible) {
      this.dismissPageActions();
      return;
    }
    this.pageActionsActive = true;
    this.pageActionsGeneration += 1;
    this.pageCommandGeneration += 1;
    this.publishPageActions(this.dependencies.runtimeCoordinator.createInitialPageActionsState());
    this.refreshPageActions();
    if (facts.presentationMode === 'large_screen') {
      this.publishPageActionsPopupVisible(true);
      return;
    }
    this.dependencies.transientSurfaceCoordinator.present({
      id: 'userscript_page_actions',
      revealDelayMs: this.dependencies.pageActionsRevealDelayMs,
      dismissDurationMs: this.dependencies.pageActionsDismissDurationMs,
      shouldReveal: (): boolean => this.pageActionsActive
    });
  }

  private refreshPageActions(): void {
    if (!this.pageActionsActive) {
      return;
    }
    const facts = this.dependencies.captureFacts();
    const generation = ++this.pageActionsGeneration;
    void this.dependencies.runtimeCoordinator.buildPageActionsStateForPage(
      facts.activeTabId,
      facts.currentUrl,
      facts.privateMode
    ).then((state: UserScriptPageActionsState) => {
      if (this.isCurrentPageActionsRequest(facts, generation)) {
        this.publishPageActions(state);
      }
    }).catch((error: Error) => {
      if (this.isCurrentPageActionsRequest(facts, generation)) {
        this.emitMessage('set_error_message', `读取脚本菜单失败：${this.stringifyError(error)}`);
      }
    });
  }

  private dismissPageActions(): void {
    this.invalidatePageActions();
    if (this.snapshot.pageActionsPopupVisible) {
      this.publishPageActionsPopupVisible(false);
      return;
    }
    this.dependencies.transientSurfaceCoordinator.dismiss('userscript_page_actions');
  }

  private openManager(): void {
    this.invalidatePageActions();
    if (this.snapshot.pageActionsPopupVisible) {
      this.publishPageActionsPopupVisible(false);
    } else {
      this.dependencies.transientSurfaceCoordinator.reset('userscript_page_actions');
    }
    this.dependencies.routeCoordinator.openUserScriptsPage();
  }

  private runPageCommand(scriptId: string, commandId: string): void {
    const normalizedScriptId = scriptId.trim();
    const normalizedCommandId = commandId.trim();
    if (!this.pageActionsActive || normalizedScriptId.length <= 0 || normalizedCommandId.length <= 0) {
      return;
    }
    const facts = this.dependencies.captureFacts();
    const generation = ++this.pageCommandGeneration;
    this.dismissPageActions();
    void this.dependencies.runtimeCoordinator.executePageCommandForPage(
      facts.activeTabId,
      normalizedScriptId,
      normalizedCommandId,
      facts.currentUrl,
      facts.privateMode
    ).then((success: boolean) => {
      if (generation === this.pageCommandGeneration && this.isCurrentPage(facts) && !success) {
        this.emitMessage('set_helper_message', '脚本菜单命令执行失败');
      }
    }).catch((error: Error) => {
      if (generation === this.pageCommandGeneration && this.isCurrentPage(facts)) {
        this.emitMessage('set_error_message', `执行脚本菜单失败：${this.stringifyError(error)}`);
      }
    });
  }

  private invalidatePageActions(): void {
    this.pageActionsActive = false;
    this.pageActionsGeneration += 1;
  }

  private isCurrentPageActionsRequest(facts: BrowserUserScriptApplicationFacts, generation: number): boolean {
    return this.pageActionsActive && generation === this.pageActionsGeneration && this.isCurrentPage(facts);
  }

  private isCurrentPage(facts: BrowserUserScriptApplicationFacts): boolean {
    const current = this.dependencies.captureFacts();
    return current.activeTabId === facts.activeTabId &&
      current.currentUrl.trim() === facts.currentUrl.trim() &&
      current.privateMode === facts.privateMode;
  }

  private publishPageActions(state: UserScriptPageActionsState): void {
    if (this.snapshot.pageActionsState !== state) {
      this.publishSnapshot(state);
    }
  }

  private publishInstallRequest(
    installUrl: string,
    installBoundary: BrowserUserScriptInstallBoundary
  ): void {
    if (this.snapshot.installUrl !== installUrl ||
      this.snapshot.installBoundary.dataScope !== installBoundary.dataScope ||
      this.snapshot.installBoundary.privacyMode !== installBoundary.privacyMode) {
      this.snapshot = {
        installUrl: installUrl,
        installBoundary: installBoundary,
        installSuccessPrompt: this.snapshot.installSuccessPrompt,
        pageActionsPopupVisible: this.snapshot.pageActionsPopupVisible,
        pageActionsState: this.snapshot.pageActionsState
      };
      this.dependencies.publishSnapshot(this.snapshot);
    }
  }

  private publishSnapshot(pageActionsState: UserScriptPageActionsState): void {
    this.snapshot = {
      installUrl: this.snapshot.installUrl,
      installBoundary: this.snapshot.installBoundary,
      installSuccessPrompt: this.snapshot.installSuccessPrompt,
      pageActionsPopupVisible: this.snapshot.pageActionsPopupVisible,
      pageActionsState: pageActionsState
    };
    this.dependencies.publishSnapshot(this.snapshot);
  }

  private publishPageActionsPopupVisible(visible: boolean): void {
    if (this.snapshot.pageActionsPopupVisible === visible) {
      return;
    }
    this.snapshot = {
      installUrl: this.snapshot.installUrl,
      installBoundary: this.snapshot.installBoundary,
      installSuccessPrompt: this.snapshot.installSuccessPrompt,
      pageActionsPopupVisible: visible,
      pageActionsState: this.snapshot.pageActionsState
    };
    this.dependencies.publishSnapshot(this.snapshot);
  }

  private publishInstallSuccessPrompt(state: UserScriptInstallSuccessPromptState): void {
    this.snapshot = {
      installUrl: this.snapshot.installUrl,
      installBoundary: this.snapshot.installBoundary,
      installSuccessPrompt: state,
      pageActionsPopupVisible: this.snapshot.pageActionsPopupVisible,
      pageActionsState: this.snapshot.pageActionsState
    };
    this.dependencies.publishSnapshot(this.snapshot);
  }

  private scheduleInstallSuccessPromptDismiss(): void {
    this.clearInstallSuccessPromptDismissTimer();
    const expectedKey = this.snapshot.installSuccessPrompt.key;
    this.installSuccessPromptDismissTimer = setTimeout((): void => {
      this.installSuccessPromptDismissTimer = 0;
      if (this.snapshot.installSuccessPrompt.key === expectedKey) {
        this.publishInstallSuccessPrompt(HIDDEN_USER_SCRIPT_INSTALL_SUCCESS_PROMPT_STATE);
      }
    }, USER_SCRIPT_INSTALL_SUCCESS_PROMPT_AUTO_DISMISS_MS);
  }

  private clearInstallSuccessPromptDismissTimer(): void {
    if (this.installSuccessPromptDismissTimer === 0) {
      return;
    }
    clearTimeout(this.installSuccessPromptDismissTimer);
    this.installSuccessPromptDismissTimer = 0;
  }

  private emitMessage(type: 'set_helper_message' | 'set_error_message', message: string): void {
    this.dependencies.executeEffect({ type: type, message: message });
  }

  private stringifyError(error: Error): string {
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    try {
      const serialized = JSON.stringify(error);
      return serialized.length > 0 ? serialized : '未知错误';
    } catch (_stringifyError) {
      return '未知错误';
    }
  }
}
