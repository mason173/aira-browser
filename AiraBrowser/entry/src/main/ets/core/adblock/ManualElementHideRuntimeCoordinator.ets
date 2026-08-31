import {
  ManualElementHideApplyResult,
  ManualElementHideFinishResult,
  ManualElementHideNavigationResult,
  ManualElementHideSelectionState,
  ManualElementHideService
} from '../../services/adblock/ManualElementHideService';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { AIRA_FEATURE_MANUAL_ELEMENT_HIDE } from '../../common/constants/MembershipFeatureKeys';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { normalizeNavigationTarget } from '../browser/AddressDisplayFormatter';
import { BrowserAdBlockCoordinator } from '../browser/BrowserAdBlockCoordinator';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import { BrowserSiteControlsRuntimeCoordinator } from '../browser/BrowserSiteControlsRuntimeCoordinator';
import { BrowserTabScopedEventContextCoordinator } from '../browser/BrowserTabScopedEventContextCoordinator';
import { FeatureGateCoordinator } from '../membership/FeatureGateCoordinator';

export interface ManualElementHideRuntimeApplyContext {
  tabId: string;
  pageUrl: string;
  appServiceModeEnabled: boolean;
}

interface ManualElementHideRuntimeApplyResult {
  appliedSelectorCount: number;
  hiddenElementCount: number;
  pageUrl: string;
  phase: string;
}

export interface ManualElementHideRuntimeHiddenContext {
  tabId: string;
  payloadJson: string;
}

export interface ManualElementHideRuntimeFacts {
  activeTabId: string;
  showHomePage: boolean;
  showTabsSheet: boolean;
  pageHost: string;
  pageUrl: string;
}

export interface ManualElementHideSelectionPresentation {
  active: boolean;
  selectedCount: number;
  selectedElementSelector: string;
  host: string;
  busy: boolean;
}

export type ManualElementHideSelectionAction =
  'cancel' | 'finish' | 'navigate_parent' | 'navigate_child';

export interface ManualElementHideRuntimeShell {
  resolveFacts: () => ManualElementHideRuntimeFacts;
  publishSelection: (presentation: ManualElementHideSelectionPresentation) => void;
  prepareSelectionChrome: () => void;
  showToast: (message: string) => void;
  publishError: (message: string) => void;
}

interface ManualElementHideRuntimeErrorLike {
  message?: string;
  name?: string;
}

interface ManualElementHideRuntimeHiddenPayload {
  pageUrl?: string;
  count?: number;
  phase?: string;
}

interface ManualElementHideRuntimePendingApply {
  context: ManualElementHideRuntimeApplyContext;
  generation: number;
}

export class ManualElementHideRuntimeCoordinator {
  private manualElementHideService: ManualElementHideService;
  private runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private adBlockCoordinator: BrowserAdBlockCoordinator;
  private tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  private membershipFeature: MembershipFeature;
  private featureGateCoordinator: FeatureGateCoordinator;
  private siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator;
  private shell: ManualElementHideRuntimeShell;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private latestApplyByTab: Map<string, ManualElementHideRuntimePendingApply> = new Map();
  private applyGeneration: number = 0;
  private repositoryReadinessPromise?: Promise<void>;
  private selectionPresentation: ManualElementHideSelectionPresentation = {
    active: false,
    selectedCount: 0,
    selectedElementSelector: '',
    host: '',
    busy: false
  };
  private selectionPollTimer: number = -1;
  private selectionNavigationPending: boolean = false;

  constructor(
    manualElementHideService: ManualElementHideService,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    adBlockCoordinator: BrowserAdBlockCoordinator,
    tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator,
    membershipFeature: MembershipFeature,
    featureGateCoordinator: FeatureGateCoordinator,
    siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator,
    shell: ManualElementHideRuntimeShell,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.manualElementHideService = manualElementHideService;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.adBlockCoordinator = adBlockCoordinator;
    this.tabScopedEventContextCoordinator = tabScopedEventContextCoordinator;
    this.membershipFeature = membershipFeature;
    this.featureGateCoordinator = featureGateCoordinator;
    this.siteControlsRuntimeCoordinator = siteControlsRuntimeCoordinator;
    this.shell = shell;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  applyForPage(context: ManualElementHideRuntimeApplyContext): void {
    if (this.manualElementHideService.isRepositoryReady()) {
      this.latestApplyByTab.delete(context.tabId);
      this.applyContextForPage(context);
      return;
    }
    if (!this.shouldApplyContext(context)) {
      this.latestApplyByTab.delete(context.tabId);
      return;
    }
    this.rememberLatestApply(context);
    this.ensureRepositoryReady();
  }

  recordHiddenFromPayload(context: ManualElementHideRuntimeHiddenContext): void {
    try {
      const payload = JSON.parse(context.payloadJson) as ManualElementHideRuntimeHiddenPayload;
      const hiddenElementCount = this.normalizeCount(payload.count);
      const pageUrl = `${payload.pageUrl ?? ''}`.trim();
      if (hiddenElementCount <= 0 ||
        !this.isSameNavigationTarget(pageUrl, this.runtimeLifecyclePort.resolvePageUrl(context.tabId))) {
        return;
      }
      const phase = `${payload.phase ?? 'mutation'}`.trim();
      this.applyRuntimeResult(context.tabId, {
        appliedSelectorCount: 0,
        hiddenElementCount: hiddenElementCount,
        pageUrl: pageUrl,
        phase: phase.length > 0 ? phase : 'mutation'
      });
    } catch (_error) {
      return;
    }
  }

  snapshotSelection(): ManualElementHideSelectionPresentation {
    return this.cloneSelectionPresentation(this.selectionPresentation);
  }

  canStartSelection(): boolean {
    return this.canStartSelectionForFacts(this.shell.resolveFacts());
  }

  startSelectionSession(): void {
    void this.runStartSelectionSession();
  }

  handleSelectionAction(action: ManualElementHideSelectionAction): void {
    if (action === 'cancel') {
      this.cancelSelectionSession();
      return;
    }
    if (action === 'navigate_parent' || action === 'navigate_child') {
      this.navigateSelectionSession(action);
      return;
    }
    this.finishSelectionSession();
  }

  private cancelSelectionSession(): void {
    if (!this.selectionPresentation.active && !this.selectionPresentation.busy) {
      return;
    }
    this.selectionNavigationPending = false;
    this.setSelectionPresentation(false, 0, '', this.selectionPresentation.host, false);
    this.stopSelectionPolling();
    void this.manualElementHideService.cancelSelectionFromLifecyclePort(this.runtimeLifecyclePort)
      .then(() => {
        this.shell.showToast('已取消标记广告。');
      })
      .catch((error: Error) => {
        this.shell.publishError(`取消标记模式失败：${this.stringifyError(error)}`);
      });
  }

  private navigateSelectionSession(
    action: 'navigate_parent' | 'navigate_child'
  ): void {
    if (!this.selectionPresentation.active || this.selectionPresentation.busy ||
      this.selectionNavigationPending) {
      return;
    }
    this.selectionNavigationPending = true;
    const direction: 'parent' | 'child' = action === 'navigate_parent' ? 'parent' : 'child';
    void this.manualElementHideService.navigateSelectionFromLifecyclePort(this.runtimeLifecyclePort, direction)
      .then((result: ManualElementHideNavigationResult) => {
        this.selectionNavigationPending = false;
        if (!this.selectionPresentation.active) {
          return;
        }
        this.setSelectionPresentation(
          true,
          result.selectedCount,
          result.selectedElementSelector,
          this.selectionPresentation.host,
          this.selectionPresentation.busy
        );
        if (!result.changed) {
          this.showSelectionNavigationFeedback(direction, result.reason);
        }
      })
      .catch((error: Error) => {
        this.selectionNavigationPending = false;
        this.shell.publishError(`调整广告选区失败：${this.stringifyError(error)}`);
      });
  }

  private showSelectionNavigationFeedback(direction: 'parent' | 'child', reason: string): void {
    if (reason === 'no_selection') {
      this.shell.showToast('请先点选一个广告元素。');
      return;
    }
    if (reason === 'no_parent') {
      this.shell.showToast('已到可安全标记的最外层。');
      return;
    }
    if (reason === 'no_child') {
      this.shell.showToast('当前广告元素没有可选子级。');
      return;
    }
    if (reason === 'runtime_unavailable') {
      this.shell.showToast('选区暂时不可调整，请重新进入标记模式。');
      return;
    }
    this.shell.showToast(direction === 'parent' ? '没有可扩大的父级选区。' : '没有可缩小的子级选区。');
  }

  private finishSelectionSession(): void {
    if (!this.selectionPresentation.active || this.selectionPresentation.busy) {
      return;
    }
    void this.runFinishSelectionSession();
  }

  handlePageDisappear(): void {
    this.selectionNavigationPending = false;
    this.stopSelectionPolling();
  }

  getRuleCountForHost(host: string): number {
    return this.manualElementHideService.getRuleCountForHost(host);
  }

  private async evaluatePageApply(
    context: ManualElementHideRuntimeApplyContext
  ): Promise<ManualElementHideRuntimeApplyResult> {
    if (!context.appServiceModeEnabled) {
      return this.emptyResult();
    }
    const host = this.extractHost(context.pageUrl);
    if (host.length <= 0) {
      return this.emptyResult();
    }
    try {
      const result = await this.manualElementHideService.applyForPageFromLifecyclePort(
        this.runtimeLifecyclePort,
        context.tabId,
        host,
        context.pageUrl
      );
      return this.handleApplyResult(context, result);
    } catch (_error) {
      return this.emptyResult();
    }
  }

  private async runStartSelectionSession(): Promise<void> {
    const initialFacts = this.shell.resolveFacts();
    if (!this.canStartSelectionForFacts(initialFacts)) {
      this.shell.showToast('当前页面无法标记广告。');
      return;
    }
    const currentUsage = this.manualElementHideService.getTotalRuleCount();
    const decision = await this.membershipFeature.canUse(AIRA_FEATURE_MANUAL_ELEMENT_HIDE, {
      dataScope: this.tabScopedEventContextCoordinator.resolveDataScope(initialFacts.activeTabId),
      privacyMode: this.tabScopedEventContextCoordinator.resolvePrivacyMode(initialFacts.activeTabId),
      loggedIn: true,
      currentUsage: currentUsage
    });
    if (!decision.allowed) {
      this.featureGateCoordinator.presentDecision(decision);
      return;
    }
    const facts = this.shell.resolveFacts();
    this.shell.prepareSelectionChrome();
    this.setSelectionPresentation(false, 0, '', facts.pageHost, true);
    try {
      const started = await this.manualElementHideService.startSelectionFromLifecyclePort(this.runtimeLifecyclePort);
      if (!started) {
        this.setSelectionPresentation(false, 0, '', facts.pageHost, false);
        this.shell.showToast('当前页面无法进入标记模式。');
        return;
      }
      this.setSelectionPresentation(true, 0, '', facts.pageHost, false);
      this.startSelectionPolling();
      this.shell.showToast('点选想标记的广告内容。');
    } catch (error) {
      this.setSelectionPresentation(false, 0, '', facts.pageHost, false);
      this.shell.publishError(`进入标记模式失败：${this.stringifyError(error as Object)}`);
      this.shell.showToast('标记模式启动失败。');
    }
  }

  private async runFinishSelectionSession(): Promise<void> {
    const facts = this.shell.resolveFacts();
    const host = this.selectionPresentation.host.length > 0
      ? this.selectionPresentation.host
      : facts.pageHost;
    const selectedCount = this.selectionPresentation.selectedCount;
    const selectedElementSelector = this.selectionPresentation.selectedElementSelector;
    this.setSelectionPresentation(true, selectedCount, selectedElementSelector, host, true);
    const currentUsage = this.manualElementHideService.getTotalRuleCount();
    try {
      const decision = await this.membershipFeature.canUse(AIRA_FEATURE_MANUAL_ELEMENT_HIDE, {
        dataScope: this.tabScopedEventContextCoordinator.resolveDataScope(facts.activeTabId),
        privacyMode: this.tabScopedEventContextCoordinator.resolvePrivacyMode(facts.activeTabId),
        loggedIn: true,
        currentUsage: currentUsage + selectedCount
      });
      if (!decision.allowed) {
        this.setSelectionPresentation(true, selectedCount, selectedElementSelector, host, false);
        this.featureGateCoordinator.presentDecision(decision);
        return;
      }
      if (!this.canWriteDevicePreference(this.shell.resolveFacts())) {
        this.setSelectionPresentation(true, selectedCount, selectedElementSelector, host, false);
        this.shell.showToast('当前隐私策略不允许保存隐藏规则。');
        return;
      }
      const result: ManualElementHideFinishResult =
        await this.manualElementHideService.finishSelectionFromLifecyclePort(
          this.runtimeLifecyclePort,
          host,
          facts.pageUrl,
          decision.quota?.limit === undefined || decision.quota.limit < 0
            ? -1
            : Math.max(0, decision.quota.limit - currentUsage)
        );
      this.setSelectionPresentation(false, 0, '', '', false);
      this.stopSelectionPolling();
      if (result.savedSelectorCount <= 0) {
        this.shell.showToast('没有选择要隐藏的元素。');
        return;
      }
      void this.membershipFeature.recordUsage(AIRA_FEATURE_MANUAL_ELEMENT_HIDE, result.savedSelectorCount);
      this.shell.showToast(`已为 ${host} 保存 ${result.totalRuleCount} 条隐藏规则。`);
    } catch (error) {
      const errorLike = error as ManualElementHideRuntimeErrorLike;
      this.setSelectionPresentation(true, selectedCount, selectedElementSelector, host, false);
      this.shell.publishError(`保存隐藏规则失败：${this.stringifyError(error as Object)}`);
      this.shell.showToast(typeof errorLike.message === 'string' && errorLike.message.length > 0
        ? errorLike.message
        : '隐藏规则保存失败。');
    }
  }

  private canStartSelectionForFacts(facts: ManualElementHideRuntimeFacts): boolean {
    if (this.selectionPresentation.active || facts.showHomePage || facts.showTabsSheet) {
      return false;
    }
    if (facts.pageHost.length <= 0) {
      return false;
    }
    return this.runtimeLifecyclePort.resolveActiveController() !== undefined;
  }

  private canWriteDevicePreference(facts: ManualElementHideRuntimeFacts): boolean {
    const context = this.tabScopedEventContextCoordinator.resolveContext(facts.activeTabId);
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        profileId: context.profileId,
        dataScope: context.dataScope,
        privacyMode: context.privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private startSelectionPolling(): void {
    this.stopSelectionPolling();
    this.selectionPollTimer = setInterval(() => {
      if (!this.selectionPresentation.active || this.selectionPresentation.busy) {
        return;
      }
      void this.manualElementHideService.readSelectionStateFromLifecyclePort(this.runtimeLifecyclePort)
        .then((state: ManualElementHideSelectionState) => {
          if (!this.selectionPresentation.active ||
            (state.selectedCount === this.selectionPresentation.selectedCount &&
              state.selectedElementSelector === this.selectionPresentation.selectedElementSelector)) {
            return;
          }
          this.setSelectionPresentation(
            true,
            state.selectedCount,
            state.selectedElementSelector,
            this.selectionPresentation.host,
            this.selectionPresentation.busy
          );
        })
        .catch((_error: Error) => {});
    }, 350);
  }

  private stopSelectionPolling(): void {
    if (this.selectionPollTimer < 0) {
      return;
    }
    clearInterval(this.selectionPollTimer);
    this.selectionPollTimer = -1;
  }

  private setSelectionPresentation(
    active: boolean,
    selectedCount: number,
    selectedElementSelector: string,
    host: string,
    busy: boolean
  ): void {
    const next: ManualElementHideSelectionPresentation = {
      active: active,
      selectedCount: Math.max(0, Math.floor(selectedCount)),
      selectedElementSelector: `${selectedElementSelector ?? ''}`.trim(),
      host: host,
      busy: busy
    };
    const unchanged = this.selectionPresentation.active === next.active &&
      this.selectionPresentation.selectedCount === next.selectedCount &&
      this.selectionPresentation.selectedElementSelector === next.selectedElementSelector &&
      this.selectionPresentation.host === next.host &&
      this.selectionPresentation.busy === next.busy;
    if (unchanged) {
      return;
    }
    this.selectionPresentation = next;
    this.shell.publishSelection(this.cloneSelectionPresentation(next));
  }

  private cloneSelectionPresentation(
    presentation: ManualElementHideSelectionPresentation
  ): ManualElementHideSelectionPresentation {
    return {
      active: presentation.active,
      selectedCount: presentation.selectedCount,
      selectedElementSelector: presentation.selectedElementSelector,
      host: presentation.host,
      busy: presentation.busy
    };
  }

  private applyRuntimeResult(
    tabId: string,
    result: ManualElementHideRuntimeApplyResult
  ): void {
    if (result.hiddenElementCount > 0) {
      this.adBlockCoordinator.recordManualElementsHidden({
        tabId: tabId,
        hiddenElementCount: result.hiddenElementCount,
        profileId: this.tabScopedEventContextCoordinator.resolveProfileId(tabId),
        dataScope: this.tabScopedEventContextCoordinator.resolveDataScope(tabId)
      });
      if (this.shell.resolveFacts().activeTabId === tabId) {
        this.siteControlsRuntimeCoordinator.refreshActiveProtectionPresentation();
      }
    }
  }

  private applyContextForPage(context: ManualElementHideRuntimeApplyContext): void {
    void this.evaluatePageApply(context)
      .then((result: ManualElementHideRuntimeApplyResult) => {
        this.applyRuntimeResult(context.tabId, result);
      })
      .catch((_error: Error) => {});
  }

  private rememberLatestApply(context: ManualElementHideRuntimeApplyContext): void {
    this.applyGeneration += 1;
    this.latestApplyByTab.set(context.tabId, {
      context: this.cloneApplyContext(context),
      generation: this.applyGeneration
    });
  }

  private ensureRepositoryReady(): void {
    if (this.repositoryReadinessPromise !== undefined) {
      return;
    }
    const promise = this.manualElementHideService.ensureRepositoryReady()
      .then(() => {
        this.replayLatestPendingApplies();
      })
      .catch((_error: Error) => undefined)
      .finally(() => {
        if (this.repositoryReadinessPromise === promise) {
          this.repositoryReadinessPromise = undefined;
        }
      });
    this.repositoryReadinessPromise = promise;
  }

  private replayLatestPendingApplies(): void {
    Array.from(this.latestApplyByTab.values()).forEach((pending: ManualElementHideRuntimePendingApply) => {
      this.replayPendingApply(pending.context.tabId, pending.generation);
    });
  }

  private replayPendingApply(tabId: string, generation: number): void {
    const pending = this.latestApplyByTab.get(tabId);
    if (pending === undefined || pending.generation !== generation) {
      return;
    }
    if (!this.isReplayContextCurrent(pending.context)) {
      this.clearLatestPendingApply(tabId, generation);
      return;
    }
    void this.evaluatePageApply(pending.context)
      .then((result: ManualElementHideRuntimeApplyResult) => {
        if (!this.isLatestPendingApply(tabId, generation)) {
          return;
        }
        if (!this.isReplayContextCurrent(pending.context)) {
          this.clearLatestPendingApply(tabId, generation);
          return;
        }
        this.clearLatestPendingApply(tabId, generation);
        this.applyRuntimeResult(tabId, result);
      })
      .catch((_error: Error) => {
        if (!this.isLatestPendingApply(tabId, generation)) {
          return;
        }
        this.clearLatestPendingApply(tabId, generation);
      });
  }

  private isLatestPendingApply(tabId: string, generation: number): boolean {
    return this.latestApplyByTab.get(tabId)?.generation === generation;
  }

  private clearLatestPendingApply(tabId: string, generation: number): void {
    if (this.isLatestPendingApply(tabId, generation)) {
      this.latestApplyByTab.delete(tabId);
    }
  }

  private isReplayContextCurrent(context: ManualElementHideRuntimeApplyContext): boolean {
    if (!this.shouldApplyContext(context)) {
      return false;
    }
    if (this.runtimeLifecyclePort.resolveController(context.tabId) === undefined) {
      return false;
    }
    return this.isSameNavigationTarget(context.pageUrl, this.runtimeLifecyclePort.resolvePageUrl(context.tabId));
  }

  private shouldApplyContext(context: ManualElementHideRuntimeApplyContext): boolean {
    return context.appServiceModeEnabled && this.extractHost(context.pageUrl).length > 0;
  }

  private cloneApplyContext(context: ManualElementHideRuntimeApplyContext): ManualElementHideRuntimeApplyContext {
    return {
      tabId: context.tabId,
      pageUrl: context.pageUrl,
      appServiceModeEnabled: context.appServiceModeEnabled
    };
  }

  private handleApplyResult(
    context: ManualElementHideRuntimeApplyContext,
    result: ManualElementHideApplyResult
  ): ManualElementHideRuntimeApplyResult {
    if (result.appliedSelectorCount <= 0) {
      return this.emptyResult();
    }
    return {
      appliedSelectorCount: result.appliedSelectorCount,
      hiddenElementCount: result.hiddenElementCount,
      pageUrl: context.pageUrl,
      phase: 'initial'
    };
  }

  private emptyResult(): ManualElementHideRuntimeApplyResult {
    return {
      appliedSelectorCount: 0,
      hiddenElementCount: 0,
      pageUrl: '',
      phase: ''
    };
  }

  private normalizeCount(value: number | undefined): number {
    if (typeof value !== 'number' || value <= 0 || !Number.isFinite(value)) {
      return 0;
    }
    return Math.floor(value);
  }

  private isSameNavigationTarget(left: string, right: string): boolean {
    const normalizedLeft = normalizeNavigationTarget(left);
    const normalizedRight = normalizeNavigationTarget(right);
    return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
  }

  private stringifyError(error: Object): string {
    const errorLike = error as ManualElementHideRuntimeErrorLike;
    if (typeof errorLike.message === 'string' && errorLike.message.length > 0) {
      return errorLike.message;
    }
    if (typeof errorLike.name === 'string' && errorLike.name.length > 0) {
      return errorLike.name;
    }
    return 'unknown error';
  }

  private extractHost(url: string): string {
    let value = url.trim().toLowerCase();
    if (value.startsWith('http://')) {
      value = value.substring(7);
    } else if (value.startsWith('https://')) {
      value = value.substring(8);
    } else {
      return '';
    }
    const pathStart = value.indexOf('/');
    if (pathStart >= 0) {
      value = value.substring(0, pathStart);
    }
    const portStart = value.indexOf(':');
    if (portStart >= 0) {
      value = value.substring(0, portStart);
    }
    return value;
  }
}
