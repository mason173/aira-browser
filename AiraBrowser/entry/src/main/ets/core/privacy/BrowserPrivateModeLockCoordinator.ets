import { BrowserDataScope, BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  PrivateModeUserAuthResult,
  PrivateModeUserAuthService
} from '../../services/privacy/PrivateModeUserAuthService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

const PRIVATE_MODE_LOCK_DEFAULT_MESSAGE: string = '请验证身份以查看隐私标签页。';
const PRIVATE_MODE_AUTH_START_DELAY_MS: number = 0;

export type BrowserPrivateModeLockReason =
  'enter_private_home' |
  'switch_private_tab' |
  'tabs_overview_private_section' |
  'private_bookmarks' |
  'app_foreground_resume';

interface BrowserPrivateModeLockState {
  locked: boolean;
  hasUnlockedThisSession: boolean;
}

export interface BrowserPrivateModeLockBoundary {
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface BrowserPrivateModeLockSessionFacts {
  tabs: BrowserPrivateModeLockBoundary[];
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  activeTabId: string;
  browserShellVisible: boolean;
}

export interface BrowserPrivateModeLockSessionSnapshot {
  locked: boolean;
  authenticationEnabled: boolean;
  overlayVisible: boolean;
  authenticationInProgress: boolean;
  message: string;
}

export type BrowserPrivateModeLockUserAction = 'unlock' | 'return_to_regular';

export interface BrowserPrivateModeLockSessionShell {
  readFacts: () => BrowserPrivateModeLockSessionFacts;
  publishSnapshot: (snapshot: BrowserPrivateModeLockSessionSnapshot) => void;
  returnToRegularMode: () => void;
}

export class BrowserPrivateModeLockCoordinator {
  private readonly shell: BrowserPrivateModeLockSessionShell;
  private readonly preferencesRepository: PreferencesRepository;
  private readonly profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private readonly userAuthService: PrivateModeUserAuthService = new PrivateModeUserAuthService();
  private state: BrowserPrivateModeLockState = this.buildInitialState();
  private overlayVisible: boolean = false;
  private authenticationInProgress: boolean = false;
  private authenticationMessage: string = PRIVATE_MODE_LOCK_DEFAULT_MESSAGE;
  private authenticationGeneration: number = 0;
  private authenticationCompletion?: (unlocked: boolean) => void;

  constructor(shell: BrowserPrivateModeLockSessionShell, preferencesRepository: PreferencesRepository) {
    this.shell = shell;
    this.preferencesRepository = preferencesRepository;
  }

  getSessionSnapshot(): BrowserPrivateModeLockSessionSnapshot {
    return this.buildSessionSnapshot();
  }

  shouldShowOverlay(
    snapshot: BrowserPrivateModeLockSessionSnapshot,
    currentBoundaryPrivate: boolean
  ): boolean {
    return snapshot.authenticationEnabled &&
      (snapshot.overlayVisible || (snapshot.locked && currentBoundaryPrivate));
  }

  handleForegroundResume(): void {
    const facts = this.shell.readFacts();
    if (!this.isAuthenticationEnabled()) {
      this.unlockWithoutAuthentication(facts);
      return;
    }
    if (!facts.browserShellVisible) {
      return;
    }
    const currentBoundaryPrivate = this.isPrivateBoundary(facts.privacyMode, facts.dataScope);
    if (!this.hasPrivateContent(facts.tabs) && !currentBoundaryPrivate) {
      this.publishSnapshot();
      return;
    }
    if (currentBoundaryPrivate) {
      this.startAuthentication('app_foreground_resume', facts, undefined);
      return;
    }
    this.state = this.lock(this.state);
    this.publishSnapshot();
  }

  synchronizeCurrentBoundary(): void {
    const facts = this.shell.readFacts();
    if (!this.isAuthenticationEnabled()) {
      this.unlockWithoutAuthentication(facts);
      return;
    }
    if (this.isPrivateBoundary(facts.privacyMode, facts.dataScope)) {
      this.publishSnapshot();
      return;
    }
    if (this.hasPrivateContent(facts.tabs)) {
      this.state = this.lock(this.state);
      this.publishSnapshot();
      return;
    }
    this.cancelAuthentication(false);
    this.state = this.buildInitialState();
    this.overlayVisible = false;
    this.authenticationMessage = PRIVATE_MODE_LOCK_DEFAULT_MESSAGE;
    this.publishSnapshot();
  }

  async ensureUnlocked(
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope,
    reason: BrowserPrivateModeLockReason
  ): Promise<boolean> {
    const facts = this.shell.readFacts();
    if (!this.isAuthenticationEnabled()) {
      this.unlockWithoutAuthentication(facts);
      return true;
    }
    if (!this.shouldAuthenticateForPrivateAccess(this.state, privacyMode, dataScope)) {
      return true;
    }
    return new Promise<boolean>((resolve: (unlocked: boolean) => void) => {
      this.startAuthentication(reason, facts, resolve);
    });
  }

  handleUserAction(action: BrowserPrivateModeLockUserAction): void {
    if (action === 'unlock') {
      this.startAuthentication('switch_private_tab', this.shell.readFacts(), undefined);
      return;
    }
    this.cancelAuthentication(false);
    this.overlayVisible = false;
    this.authenticationMessage = PRIVATE_MODE_LOCK_DEFAULT_MESSAGE;
    this.publishSnapshot();
    this.shell.returnToRegularMode();
  }

  private startAuthentication(
    reason: BrowserPrivateModeLockReason,
    facts: BrowserPrivateModeLockSessionFacts,
    completion?: (unlocked: boolean) => void
  ): void {
    if (!this.isAuthenticationEnabled()) {
      this.unlockWithoutAuthentication(facts);
      completion?.(true);
      return;
    }
    this.cancelAuthentication(false);
    const authenticationGeneration = this.authenticationGeneration + 1;
    this.authenticationGeneration = authenticationGeneration;
    this.authenticationCompletion = completion;
    this.state = this.lock(this.state);
    this.overlayVisible = true;
    this.authenticationInProgress = true;
    this.authenticationMessage = PRIVATE_MODE_LOCK_DEFAULT_MESSAGE;
    this.publishSnapshot();
    setTimeout(() => {
      if (this.authenticationGeneration !== authenticationGeneration || !this.authenticationInProgress) {
        return;
      }
      this.userAuthService.authenticate((result: PrivateModeUserAuthResult): void => {
        this.handleAuthenticationResult(authenticationGeneration, reason, result);
      });
    }, PRIVATE_MODE_AUTH_START_DELAY_MS);
  }

  private handleAuthenticationResult(
    authenticationGeneration: number,
    reason: BrowserPrivateModeLockReason,
    result: PrivateModeUserAuthResult
  ): void {
    if (this.authenticationGeneration !== authenticationGeneration) {
      return;
    }
    const completion = this.authenticationCompletion;
    this.authenticationCompletion = undefined;
    this.authenticationInProgress = false;
    if (result.status === 'success') {
      this.state = this.unlock();
      this.overlayVisible = false;
      this.authenticationMessage = '验证成功';
      this.publishSnapshot();
      completion?.(true);
      return;
    }
    this.authenticationMessage = result.message;
    this.publishSnapshot();
    completion?.(false);
  }

  private cancelAuthentication(completionResult: boolean): void {
    this.authenticationGeneration += 1;
    this.userAuthService.cancel();
    this.authenticationInProgress = false;
    const completion = this.authenticationCompletion;
    this.authenticationCompletion = undefined;
    completion?.(completionResult);
  }

  private unlockWithoutAuthentication(facts: BrowserPrivateModeLockSessionFacts): void {
    this.cancelAuthentication(false);
    this.overlayVisible = false;
    this.authenticationMessage = PRIVATE_MODE_LOCK_DEFAULT_MESSAGE;
    if (this.hasPrivateContent(facts.tabs) || this.isPrivateBoundary(facts.privacyMode, facts.dataScope)) {
      this.state = this.lock(this.state);
    } else {
      this.state = this.buildInitialState();
    }
    this.publishSnapshot();
  }

  private buildSessionSnapshot(): BrowserPrivateModeLockSessionSnapshot {
    return {
      locked: this.state.locked,
      authenticationEnabled: this.isAuthenticationEnabled(),
      overlayVisible: this.overlayVisible,
      authenticationInProgress: this.authenticationInProgress,
      message: this.authenticationMessage
    };
  }

  private publishSnapshot(): void {
    this.shell.publishSnapshot(this.buildSessionSnapshot());
  }

  private isAuthenticationEnabled(): boolean {
    return this.preferencesRepository.getPreferences().general.privateModeAuthenticationEnabled;
  }

  private buildInitialState(): BrowserPrivateModeLockState {
    return {
      locked: true,
      hasUnlockedThisSession: false
    };
  }

  private isPrivateBoundary(privacyMode: BrowserSessionPrivacyMode, dataScope: BrowserDataScope): boolean {
    return this.profileBoundaryService.isSessionEphemeral({
      privacyMode: privacyMode,
      dataScope: dataScope
    });
  }

  private hasPrivateContent(tabs: BrowserPrivateModeLockBoundary[]): boolean {
    return tabs.some((tab: BrowserPrivateModeLockBoundary): boolean =>
      this.isPrivateBoundary(tab.privacyMode, tab.dataScope));
  }

  private shouldAuthenticateForPrivateAccess(
    state: BrowserPrivateModeLockState,
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): boolean {
    return this.isPrivateBoundary(privacyMode, dataScope) && (state.locked || !state.hasUnlockedThisSession);
  }

  private lock(state: BrowserPrivateModeLockState): BrowserPrivateModeLockState {
    return {
      locked: true,
      hasUnlockedThisSession: state.hasUnlockedThisSession
    };
  }

  private unlock(): BrowserPrivateModeLockState {
    return {
      locked: false,
      hasUnlockedThisSession: true
    };
  }
}
