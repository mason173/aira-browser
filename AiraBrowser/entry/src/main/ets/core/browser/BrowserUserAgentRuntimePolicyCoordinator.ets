import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserProfileId } from '../../common/models/BrowserModels';
import { BrowserActiveTabRuntimeRestoreCoordinator } from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';
import {
  BrowserBrowsingIdentityDecision
} from '../../services/web/BrowserBrowsingIdentityDecisionService';
import { BrowserUserAgentRuntimeService } from '../../services/web/BrowserUserAgentRuntimeService';
import { BrowserQuickSearchReloadOwner } from '../search/BrowserQuickSearchSwitchingCoordinator';
import { BrowserPageReloadReason } from './BrowserRuntimeActionReason';
import { BrowserBrowsingIdentityPolicyCoordinator } from './BrowserBrowsingIdentityPolicyCoordinator';
import {
  BrowserUserAgentRuntimeTransitionCoordinator,
  BrowserUserAgentRuntimeTransitionReason
} from './BrowserUserAgentRuntimeTransitionCoordinator';
import { BrowserShellPresentationRefreshSignal } from './BrowserShellPresentationRefreshSignal';

const USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_LOG_DOMAIN: number = 0x0000;
const USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_LOG_TAG: string = 'BrowsingIdentity';
const USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_PREFIX: string = '[DEBUG-UA-ACTION-20260828]';

export interface BrowserUserAgentRuntimePolicyFacts {
  activeTabId: string;
  activeTabIsWebPage: boolean;
  currentUrl: string;
  profileId: BrowserProfileId;
  privateTabIds: string[];
}

export interface BrowserUserAgentRuntimePolicyHost {
  resolveFacts: () => BrowserUserAgentRuntimePolicyFacts;
}

export type BrowserUserAgentRuntimePolicyStatus =
  'identity_unchanged' |
  'non_web_tab_skipped' |
  'runtime_reload_started' |
  'native_transition_started' |
  'transition_superseded' |
  'transition_deferred';

export interface BrowserUserAgentRuntimePolicyResult {
  status: BrowserUserAgentRuntimePolicyStatus;
  tabId: string;
  resolution?: BrowserBrowsingIdentityDecision;
  transitionReason?: BrowserUserAgentRuntimeTransitionReason;
}

export interface BrowserUserAgentRuntimePolicyDependencies {
  activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator;
  quickSearchReloadOwner: BrowserQuickSearchReloadOwner;
  userAgentRuntimeService: BrowserUserAgentRuntimeService;
  runtimeTransitionCoordinator: BrowserUserAgentRuntimeTransitionCoordinator;
  browsingIdentityPolicyCoordinator: BrowserBrowsingIdentityPolicyCoordinator;
}

export class BrowserUserAgentRuntimePolicyCoordinator {
  private readonly dependencies: BrowserUserAgentRuntimePolicyDependencies;
  private readonly host: BrowserUserAgentRuntimePolicyHost;
  private presentationRefreshListenerKey: string = '';

  constructor(
    dependencies: BrowserUserAgentRuntimePolicyDependencies,
    host: BrowserUserAgentRuntimePolicyHost
  ) {
    this.dependencies = dependencies;
    this.host = host;
  }

  bindPresentationRefresh(): void {
    if (this.presentationRefreshListenerKey.length > 0) {
      return;
    }
    this.presentationRefreshListenerKey = BrowserShellPresentationRefreshSignal.subscribe((): void => {
      void this.reconcile('user_agent_application_profile_change');
    });
  }

  dispose(): void {
    if (this.presentationRefreshListenerKey.length <= 0) {
      return;
    }
    BrowserShellPresentationRefreshSignal.unsubscribe(this.presentationRefreshListenerKey);
    this.presentationRefreshListenerKey = '';
  }

  cancelPending(tabId: string = ''): void {
    this.dependencies.runtimeTransitionCoordinator.cancelPending(tabId);
  }

  async reconcile(
    reloadReason: BrowserPageReloadReason,
    reloadIfIdentityUnchanged: boolean = false
  ): Promise<BrowserUserAgentRuntimePolicyResult> {
    const facts = this.host.resolveFacts();
    if (!facts.activeTabIsWebPage) {
      this.dependencies.runtimeTransitionCoordinator.cancelPending(facts.activeTabId);
      return this.buildResult('non_web_tab_skipped', facts.activeTabId);
    }
    const resolution = this.dependencies.browsingIdentityPolicyCoordinator.resolveWithSystemDefault(
      facts.activeTabId,
      facts.currentUrl,
      facts.profileId,
      facts.privateTabIds.includes(facts.activeTabId)
    );
    const requiresControllerTransition = this.dependencies.userAgentRuntimeService.requiresControllerTransition(
      facts.activeTabId,
      resolution
    );
    const hasEffectiveIdentityChange = this.dependencies.userAgentRuntimeService.hasEffectiveIdentityChange(
      facts.activeTabId,
      resolution
    );
    hilog.info(
      USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_LOG_DOMAIN,
      USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_LOG_TAG,
      `${USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_PREFIX} reconcile tab=%{public}s winner=%{public}s ` +
        'identity=%{public}s presentation=%{public}s changed=%{public}s transition=%{public}s forceReload=%{public}s',
      facts.activeTabId,
      resolution.winningSource,
      resolution.profile.identityId,
      resolution.profile.presentationMode,
      hasEffectiveIdentityChange ? '1' : '0',
      requiresControllerTransition ? '1' : '0',
      reloadIfIdentityUnchanged ? '1' : '0'
    );
    if (!hasEffectiveIdentityChange) {
      this.dependencies.runtimeTransitionCoordinator.cancelUncommittedTransition(facts.activeTabId);
      if (reloadIfIdentityUnchanged) {
        this.dependencies.quickSearchReloadOwner.prepareQuickSearchForReload(facts.activeTabId);
        this.dependencies.activeTabRuntimeRestoreCoordinator.reloadActive(reloadReason);
        return this.buildResult('runtime_reload_started', facts.activeTabId, resolution);
      }
      return this.buildResult('identity_unchanged', facts.activeTabId, resolution);
    }
    if (requiresControllerTransition) {
      const transition = await this.dependencies.runtimeTransitionCoordinator.transitionToNative(
        facts.activeTabId,
        reloadReason
      );
      if (transition.status === 'started') {
        return this.buildResult(
          'native_transition_started',
          facts.activeTabId,
          resolution,
          transition.reason
        );
      }
      if (transition.status === 'superseded') {
        return this.buildResult('transition_superseded', facts.activeTabId, resolution, transition.reason);
      }
      return this.buildResult('transition_deferred', facts.activeTabId, resolution, transition.reason);
    }
    this.dependencies.runtimeTransitionCoordinator.cancelPending(facts.activeTabId);
    this.dependencies.quickSearchReloadOwner.prepareQuickSearchForReload(facts.activeTabId);
    this.dependencies.activeTabRuntimeRestoreCoordinator.reloadActive(reloadReason);
    return this.buildResult('runtime_reload_started', facts.activeTabId, resolution);
  }

  private buildResult(
    status: BrowserUserAgentRuntimePolicyStatus,
    tabId: string,
    resolution?: BrowserBrowsingIdentityDecision,
    transitionReason?: BrowserUserAgentRuntimeTransitionReason
  ): BrowserUserAgentRuntimePolicyResult {
    hilog.info(
      USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_LOG_DOMAIN,
      USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_LOG_TAG,
      `${USER_AGENT_RUNTIME_POLICY_DIAGNOSTIC_PREFIX} result tab=%{public}s status=%{public}s ` +
        'winner=%{public}s identity=%{public}s',
      tabId,
      status,
      resolution?.winningSource ?? '',
      resolution?.profile.identityId ?? ''
    );
    return {
      status: status,
      tabId: tabId,
      resolution: resolution,
      transitionReason: transitionReason
    };
  }
}
