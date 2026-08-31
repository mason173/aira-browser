import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserDataScope, BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import { AdBlockRuntimePageProtectionSnapshot } from '../adblock/AdBlockRuntimeStatsCoordinator';

const PROTECTION_FEEDBACK_AGGREGATION_DELAY_MS: number = 0;
const PROTECTION_FEEDBACK_VISIBLE_DURATION_MS: number = 2000;
const PROTECTION_DEBUG_DOMAIN: number = 0x0000;
const PROTECTION_DEBUG_TAG: string = 'ProtectionCountDiag';
const PROTECTION_DEBUG_PREFIX: string = '[DEBUG-protection-count-20260808]';

export interface BrowserWebProtectionFeedbackPresentation {
  visible: boolean;
  tabId: string;
  navigationGeneration: number;
  dataScope: BrowserDataScope;
  privateMode: boolean;
  totalActionCount: number;
  displayText: string;
  accessibilityLabel: string;
}

export const EMPTY_BROWSER_WEB_PROTECTION_FEEDBACK_PRESENTATION: BrowserWebProtectionFeedbackPresentation = {
  visible: false,
  tabId: '',
  navigationGeneration: 0,
  dataScope: 'profile_persistent',
  privateMode: false,
  totalActionCount: 0,
  displayText: '',
  accessibilityLabel: ''
};

interface BrowserWebProtectionFeedbackSession {
  snapshot: AdBlockRuntimePageProtectionSnapshot;
  privateMode: boolean;
  aggregationTimer: number;
  hideTimer: number;
  visible: boolean;
  completed: boolean;
  waitingForLargeScreenEditingEnd: boolean;
}

export interface BrowserWebProtectionFeedbackSessionDependencies {
  isTabActive: (tabId: string) => boolean;
  onPresentationChanged: () => void;
}

/**
 * Owns the one confirmation allowed for a document navigation. Renderers only
 * consume its typed presentation and never own counting or timing themselves.
 */
export class BrowserWebProtectionFeedbackSessionCoordinator {
  private readonly dependencies: BrowserWebProtectionFeedbackSessionDependencies;
  private sessions: Map<string, BrowserWebProtectionFeedbackSession> =
    new Map<string, BrowserWebProtectionFeedbackSession>();
  private largeScreenAddressEditing: boolean = false;
  private phoneChromeCompact: boolean = false;
  private activeTabId: string = '';

  constructor(dependencies: BrowserWebProtectionFeedbackSessionDependencies) {
    this.dependencies = dependencies;
  }

  resetForNavigation(
    snapshot: AdBlockRuntimePageProtectionSnapshot,
    privacyMode: BrowserSessionPrivacyMode
  ): void {
    const key = this.buildKey(snapshot.tabId, snapshot.navigationGeneration);
    const existing = this.sessions.get(key);
    if (existing !== undefined) {
      this.clearTimers(existing);
    }
    this.clearPriorSessionsForTab(snapshot.tabId, key);
    this.sessions.set(key, this.buildSession(snapshot, privacyMode));
    this.dependencies.onPresentationChanged();
  }

  observe(
    snapshot: AdBlockRuntimePageProtectionSnapshot,
    privacyMode: BrowserSessionPrivacyMode
  ): void {
    const key = this.buildKey(snapshot.tabId, snapshot.navigationGeneration);
    let session = this.sessions.get(key);
    if (session === undefined) {
      this.resetForNavigation(snapshot, privacyMode);
      session = this.sessions.get(key);
    }
    if (session === undefined) {
      return;
    }
    const activeSession = session;
    activeSession.snapshot = this.copySnapshot(snapshot);
    activeSession.privateMode = privacyMode === 'private' || snapshot.dataScope === 'session_ephemeral';
    if (activeSession.visible) {
      this.dependencies.onPresentationChanged();
      return;
    }
    if (activeSession.completed || snapshot.totalActionCount <= 0 || activeSession.aggregationTimer >= 0) {
      return;
    }
    if (this.phoneChromeCompact) {
      activeSession.completed = true;
      return;
    }
    activeSession.aggregationTimer = setTimeout((): void => {
      activeSession.aggregationTimer = -1;
      this.completeAggregation(key);
    }, PROTECTION_FEEDBACK_AGGREGATION_DELAY_MS);
    hilog.info(
      PROTECTION_DEBUG_DOMAIN,
      PROTECTION_DEBUG_TAG,
      '%{public}s feedback scheduled generation=%{public}d total=%{public}d',
      PROTECTION_DEBUG_PREFIX,
      snapshot.navigationGeneration,
      snapshot.totalActionCount
    );
  }

  setLargeScreenAddressEditing(editing: boolean): void {
    if (this.largeScreenAddressEditing === editing) {
      return;
    }
    this.largeScreenAddressEditing = editing;
    if (editing) {
      this.sessions.forEach((session: BrowserWebProtectionFeedbackSession): void => {
        if (!session.visible) {
          return;
        }
        session.visible = false;
        session.waitingForLargeScreenEditingEnd = false;
        session.completed = true;
        this.clearHideTimer(session);
      });
      this.dependencies.onPresentationChanged();
      return;
    }
    this.sessions.forEach((session: BrowserWebProtectionFeedbackSession, key: string): void => {
      if (session.waitingForLargeScreenEditingEnd && !session.completed) {
        session.waitingForLargeScreenEditingEnd = false;
        this.presentOrComplete(key, session);
      }
    });
  }

  setPhoneChromeCompact(compact: boolean): void {
    if (this.phoneChromeCompact === compact) {
      return;
    }
    this.phoneChromeCompact = compact;
    if (!compact) {
      return;
    }
    let changed = false;
    this.sessions.forEach((session: BrowserWebProtectionFeedbackSession): void => {
      if (session.completed && !session.visible && session.aggregationTimer < 0) {
        return;
      }
      const generation = session.snapshot.navigationGeneration;
      this.clearTimers(session);
      session.visible = false;
      session.completed = true;
      session.waitingForLargeScreenEditingEnd = false;
      changed = true;
      hilog.info(
        PROTECTION_DEBUG_DOMAIN,
        PROTECTION_DEBUG_TAG,
        '%{public}s feedback dismissed=phone_compact generation=%{public}d',
        PROTECTION_DEBUG_PREFIX,
        generation
      );
    });
    if (changed) {
      this.dependencies.onPresentationChanged();
    }
  }

  handleActiveTabChanged(activeTabId: string): void {
    if (this.activeTabId === activeTabId) {
      return;
    }
    const hadActiveTab = this.activeTabId.length > 0;
    this.activeTabId = activeTabId;
    if (!hadActiveTab) {
      this.dependencies.onPresentationChanged();
      return;
    }
    this.sessions.forEach((session: BrowserWebProtectionFeedbackSession): void => {
      this.clearTimers(session);
      session.visible = false;
      session.completed = true;
      session.waitingForLargeScreenEditingEnd = false;
    });
    this.dependencies.onPresentationChanged();
  }

  getPresentation(activeTabId: string): BrowserWebProtectionFeedbackPresentation {
    let matched: BrowserWebProtectionFeedbackSession | undefined;
    this.sessions.forEach((session: BrowserWebProtectionFeedbackSession): void => {
      if (session.snapshot.tabId === activeTabId && session.visible) {
        matched = session;
      }
    });
    if (matched === undefined) {
      return this.copyPresentation(EMPTY_BROWSER_WEB_PROTECTION_FEEDBACK_PRESENTATION);
    }
    const count = matched.snapshot.totalActionCount;
    const displayedCount = count > 99 ? '99+' : `${Math.max(1, count)}`;
    return {
      visible: true,
      tabId: matched.snapshot.tabId,
      navigationGeneration: matched.snapshot.navigationGeneration,
      dataScope: matched.snapshot.dataScope,
      privateMode: matched.privateMode,
      totalActionCount: count,
      displayText: `本页已保护 ${displayedCount} 项${matched.privateMode ? ' · 私密' : ''}`,
      accessibilityLabel: `本页已保护 ${count} 项${matched.privateMode ? '，仅本次私密会话' : ''}`
    };
  }

  clearTab(tabId: string): void {
    this.sessions.forEach((session: BrowserWebProtectionFeedbackSession, key: string): void => {
      if (session.snapshot.tabId === tabId) {
        this.clearTimers(session);
        this.sessions.delete(key);
      }
    });
    this.dependencies.onPresentationChanged();
  }

  clearPrivateSessions(): void {
    this.sessions.forEach((session: BrowserWebProtectionFeedbackSession, key: string): void => {
      if (session.privateMode) {
        this.clearTimers(session);
        this.sessions.delete(key);
      }
    });
    this.dependencies.onPresentationChanged();
  }

  private completeAggregation(key: string): void {
    const session = this.sessions.get(key);
    if (session === undefined || session.completed || session.snapshot.totalActionCount <= 0) {
      return;
    }
    if (this.largeScreenAddressEditing) {
      session.waitingForLargeScreenEditingEnd = true;
      hilog.info(
        PROTECTION_DEBUG_DOMAIN,
        PROTECTION_DEBUG_TAG,
        '%{public}s feedback deferred=large_screen_editing generation=%{public}d',
        PROTECTION_DEBUG_PREFIX,
        session.snapshot.navigationGeneration
      );
      return;
    }
    this.presentOrComplete(key, session);
  }

  private presentOrComplete(key: string, session: BrowserWebProtectionFeedbackSession): void {
    if (!this.dependencies.isTabActive(session.snapshot.tabId)) {
      session.completed = true;
      hilog.info(
        PROTECTION_DEBUG_DOMAIN,
        PROTECTION_DEBUG_TAG,
        '%{public}s feedback skipped=inactive generation=%{public}d',
        PROTECTION_DEBUG_PREFIX,
        session.snapshot.navigationGeneration
      );
      return;
    }
    session.visible = true;
    session.completed = true;
    this.clearHideTimer(session);
    session.hideTimer = setTimeout((): void => {
      const current = this.sessions.get(key);
      if (current === undefined) {
        return;
      }
      current.hideTimer = -1;
      current.visible = false;
      hilog.info(
        PROTECTION_DEBUG_DOMAIN,
        PROTECTION_DEBUG_TAG,
        '%{public}s feedback hidden generation=%{public}d',
        PROTECTION_DEBUG_PREFIX,
        current.snapshot.navigationGeneration
      );
      this.dependencies.onPresentationChanged();
    }, PROTECTION_FEEDBACK_VISIBLE_DURATION_MS);
    hilog.info(
      PROTECTION_DEBUG_DOMAIN,
      PROTECTION_DEBUG_TAG,
      '%{public}s feedback presented generation=%{public}d total=%{public}d',
      PROTECTION_DEBUG_PREFIX,
      session.snapshot.navigationGeneration,
      session.snapshot.totalActionCount
    );
    this.dependencies.onPresentationChanged();
  }

  private buildSession(
    snapshot: AdBlockRuntimePageProtectionSnapshot,
    privacyMode: BrowserSessionPrivacyMode
  ): BrowserWebProtectionFeedbackSession {
    return {
      snapshot: this.copySnapshot(snapshot),
      privateMode: privacyMode === 'private' || snapshot.dataScope === 'session_ephemeral',
      aggregationTimer: -1,
      hideTimer: -1,
      visible: false,
      completed: false,
      waitingForLargeScreenEditingEnd: false
    };
  }

  private clearPriorSessionsForTab(tabId: string, retainedKey: string): void {
    this.sessions.forEach((session: BrowserWebProtectionFeedbackSession, key: string): void => {
      if (session.snapshot.tabId === tabId && key !== retainedKey) {
        this.clearTimers(session);
        this.sessions.delete(key);
      }
    });
  }

  private clearTimers(session: BrowserWebProtectionFeedbackSession): void {
    if (session.aggregationTimer >= 0) {
      clearTimeout(session.aggregationTimer);
      session.aggregationTimer = -1;
    }
    this.clearHideTimer(session);
  }

  private clearHideTimer(session: BrowserWebProtectionFeedbackSession): void {
    if (session.hideTimer >= 0) {
      clearTimeout(session.hideTimer);
      session.hideTimer = -1;
    }
  }

  private buildKey(tabId: string, navigationGeneration: number): string {
    return `${tabId}\u0001${navigationGeneration}`;
  }

  private copySnapshot(value: AdBlockRuntimePageProtectionSnapshot): AdBlockRuntimePageProtectionSnapshot {
    return {
      tabId: value.tabId,
      navigationGeneration: value.navigationGeneration,
      dataScope: value.dataScope,
      requestBlockingCount: value.requestBlockingCount,
      linkCleaningCount: value.linkCleaningCount,
      elementHidingCount: value.elementHidingCount,
      totalActionCount: value.totalActionCount
    };
  }

  private copyPresentation(
    value: BrowserWebProtectionFeedbackPresentation
  ): BrowserWebProtectionFeedbackPresentation {
    return {
      visible: value.visible,
      tabId: value.tabId,
      navigationGeneration: value.navigationGeneration,
      dataScope: value.dataScope,
      privateMode: value.privateMode,
      totalActionCount: value.totalActionCount,
      displayText: value.displayText,
      accessibilityLabel: value.accessibilityLabel
    };
  }
}
