import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import { sharedShortcutRepository } from '../../app/bootstrap/BrowserAppRuntime';
import { HomeShortcutPresentationState } from '../browser/HomeContentPresentationState';
import { BrowserRecentlyClosedApplicationCoordinator } from '../browser/BrowserRecentlyClosedApplicationCoordinator';
import { BrowserSearchSuggestionCoordinator } from '../browser/BrowserSearchSuggestionCoordinator';
import { BrowserClipboardService } from '../../services/share/BrowserClipboardService';
import {
  BrowserPrivacyDataPolicy,
  BrowserPrivacyEffectPolicyService
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import {
  HomeShortcutLayoutMetrics,
  HomeShortcutLogicService,
  HomeShortcutMoveBoundary,
  HomeShortcutMoveRequest,
  HomeShortcutMoveStep,
  HomeShortcutReorderResult,
  HomeShortcutTreeMutationResult
} from '../../services/shortcuts/HomeShortcutLogicService';
import {
  HomeShortcutOpenCoordinator,
  HomeShortcutOpenOutcome
} from './HomeShortcutOpenCoordinator';
import {
  HomeShortcutSelectionAction,
  HomeShortcutSelectionCoordinator,
  HomeShortcutSelectionShell,
  HomeShortcutSelectionState
} from './HomeShortcutSelectionCoordinator';
import {
  HomeShortcutIconHydrationCallbacks,
  HomeShortcutIconHydrationCoordinator,
  HomeShortcutIconHydrationSnapshot
} from '../../services/shortcuts/HomeShortcutIconHydrationCoordinator';
import { ShortcutIconResolverService } from '../../services/shortcuts/ShortcutIconResolverService';
import {
  HomeShortcutActionDispatchResult,
  HomeShortcutEditDraft,
  HomeShortcutIconState,
  HomeShortcutItemActionId,
  HomeShortcutUserAction
} from '../../features/newtab/HomeShortcutTypes';
import { HomeShortcutViewModel } from '../../features/newtab/HomeShortcutViewModel';

const DOMAIN: number = 0x0000;
const TAG: string = 'HomeShortcutState';
const DEFAULT_HOME_SHORTCUT_SCENARIO_ID: string = 'aira_default_scenario';

export interface HomeShortcutApplicationFacts {
  activeTabId: string;
  dataScope: BrowserDataScope;
  privacyMode: BrowserSessionPrivacyMode;
}

export interface HomeShortcutApplicationSnapshot {
  scenarioId: string;
  shortcuts: ShortcutRecord[];
  layoutVersion: number;
  iconsVersion: number;
  icons: HomeShortcutIconState[];
}

export interface HomeShortcutPresentationInput {
  viewportWidth: number;
  viewportHeight: number;
  gridWidth: number;
  gridTopInset: number;
  metrics: HomeShortcutLayoutMetrics;
}

export interface HomeShortcutDeleteConfirmation {
  shortcutId: string;
  title: string;
}

interface HomeShortcutDismissContextMenuEffect {
  type: 'dismiss_context_menu';
}

interface HomeShortcutOpenEditDialogEffect {
  type: 'open_edit_dialog';
  draft: HomeShortcutEditDraft;
}

interface HomeShortcutConfirmDeleteEffect {
  type: 'confirm_delete';
  confirmation: HomeShortcutDeleteConfirmation;
}

interface HomeShortcutShowToastEffect {
  type: 'show_toast';
  message: string;
}

interface HomeShortcutShowDialogEffect {
  type: 'show_dialog';
  title: string;
  message: string;
}

interface HomeShortcutSetHelperMessageEffect {
  type: 'set_helper_message';
  message: string;
}

interface HomeShortcutPresentBoundaryBlockEffect {
  type: 'present_boundary_block';
  summaryLine: string;
  helperText: string;
}

interface HomeShortcutPublishSelectionSnapshotEffect {
  type: 'publish_selection_snapshot';
  snapshot: HomeShortcutSelectionState;
}

interface HomeShortcutOpenSelectionSheetEffect {
  type: 'open_selection_sheet';
}

interface HomeShortcutCloseSelectionSheetEffect {
  type: 'close_selection_sheet';
}

export type HomeShortcutApplicationEffect =
  HomeShortcutDismissContextMenuEffect |
  HomeShortcutOpenEditDialogEffect |
  HomeShortcutConfirmDeleteEffect |
  HomeShortcutShowToastEffect |
  HomeShortcutShowDialogEffect |
  HomeShortcutSetHelperMessageEffect |
  HomeShortcutPresentBoundaryBlockEffect |
  HomeShortcutPublishSelectionSnapshotEffect |
  HomeShortcutOpenSelectionSheetEffect |
  HomeShortcutCloseSelectionSheetEffect;

export interface HomeShortcutEffectApplication {
  apply: (
    effect: HomeShortcutApplicationEffect,
    confirmDelete: (confirmation: HomeShortcutDeleteConfirmation) => void
  ) => void;
}

export interface HomeShortcutApplicationShell {
  resolveFacts: () => HomeShortcutApplicationFacts;
  publishSnapshot: (snapshot: HomeShortcutApplicationSnapshot) => void;
}

export interface HomeShortcutApplicationDependencies {
  clipboardService: BrowserClipboardService;
  shortcutIconResolver: ShortcutIconResolverService;
  openCoordinator: HomeShortcutOpenCoordinator;
  recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator;
  searchSuggestionCoordinator: BrowserSearchSuggestionCoordinator;
  effectApplication: HomeShortcutEffectApplication;
}

export interface HomeShortcutCustomHomepageRuntime {
  syncBridge(kind: 'shortcuts'): void;
}

interface HomeShortcutMutationPolicy {
  bumpLayoutVersion: boolean;
  refreshIcons: boolean;
  notifyMoveFailure: boolean;
}

type HomeShortcutPersistentWriteAction =
  'toggle_home_shortcut' |
  'edit_home_shortcut' |
  'delete_home_shortcut' |
  'move_home_shortcut';

const STRUCTURAL_MUTATION_POLICY: HomeShortcutMutationPolicy = {
  bumpLayoutVersion: true,
  refreshIcons: true,
  notifyMoveFailure: false
};

const ORDER_MUTATION_POLICY: HomeShortcutMutationPolicy = {
  bumpLayoutVersion: false,
  refreshIcons: false,
  notifyMoveFailure: false
};

const DRAG_ORDER_MUTATION_POLICY: HomeShortcutMutationPolicy = {
  bumpLayoutVersion: false,
  refreshIcons: false,
  notifyMoveFailure: true
};

interface HomeShortcutPersistWaiter {
  resolve: () => void;
  reject: (error: Error) => void;
  notifyMoveFailure: boolean;
}

interface HomeShortcutPersistBatch {
  scenarioId: string;
  shortcuts: ShortcutRecord[];
  waiters: HomeShortcutPersistWaiter[];
}

export class HomeShortcutStateCoordinator {
  private readonly dependencies: HomeShortcutApplicationDependencies;
  private readonly shell: HomeShortcutApplicationShell;
  private readonly logicService: HomeShortcutLogicService = new HomeShortcutLogicService();
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService();
  private readonly viewModel: HomeShortcutViewModel = new HomeShortcutViewModel(this.logicService);
  private readonly iconHydrationCoordinator: HomeShortcutIconHydrationCoordinator;
  private readonly iconHydrationCallbacks: HomeShortcutIconHydrationCallbacks;
  private readonly selectionCoordinator: HomeShortcutSelectionCoordinator;

  private scenarioId: string = DEFAULT_HOME_SHORTCUT_SCENARIO_ID;
  private shortcuts: ShortcutRecord[] = [];
  private layoutVersion: number = 0;
  private iconsVersion: number = 0;
  private icons: HomeShortcutIconState[] = [];
  private initialIconHydrationPending: boolean = true;
  private loadGeneration: number = 0;
  private refreshPending: boolean = false;
  private persistRunning: boolean = false;
  private persistQueue: HomeShortcutPersistBatch[] = [];
  private customHomepageRuntime: HomeShortcutCustomHomepageRuntime | undefined = undefined;

  constructor(
    dependencies: HomeShortcutApplicationDependencies,
    shell: HomeShortcutApplicationShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
    this.iconHydrationCoordinator = new HomeShortcutIconHydrationCoordinator(
      dependencies.shortcutIconResolver
    );
    this.iconHydrationCallbacks = {
      applySnapshot: (snapshot: HomeShortcutIconHydrationSnapshot): void => {
        this.applyIconHydrationSnapshot(snapshot);
      },
      persistResolvedIcon: (shortcutId: string, sourceUrl: string, iconPath: string): void => {
        this.persistResolvedIcon(shortcutId, sourceUrl, iconPath);
      }
    };
    this.adoptPreparedInitialState();
    const selectionShell: HomeShortcutSelectionShell = {
      publishSnapshot: (snapshot: HomeShortcutSelectionState): void => {
        this.executeEffect({ type: 'publish_selection_snapshot', snapshot: snapshot });
      },
      canOpen: (): boolean => this.ensurePersistentWriteAllowed('toggle_home_shortcut'),
      openSheet: (): void => this.executeEffect({ type: 'open_selection_sheet' }),
      closeSheet: (): void => this.executeEffect({ type: 'close_selection_sheet' }),
      refreshHomeShortcuts: (): void => this.refresh(),
      showMessage: (message: string): void => this.showToast(message)
    };
    this.selectionCoordinator = new HomeShortcutSelectionCoordinator(selectionShell);
  }

  private adoptPreparedInitialState(): void {
    const startedAt = Date.now();
    const appOwnedShortcuts = this.logicService.filterAppOwnedShortcuts(sharedShortcutRepository.listAll());
    this.shortcuts = this.logicService.normalizeListPositions(appOwnedShortcuts);
    const iconSnapshot = this.iconHydrationCoordinator.adoptPreparedFor(
      this.shortcuts,
      this.iconHydrationCallbacks
    );
    this.icons = iconSnapshot.icons;
    hilog.info(
      DOMAIN,
      TAG,
      '[DEBUG-FAVICON-COLDSTART] prepared_state shortcuts=%{public}d icons=%{public}d durationMs=%{public}d',
      this.shortcuts.length,
      this.icons.length,
      Date.now() - startedAt
    );
  }

  bindCustomHomepageRuntime(runtime: HomeShortcutCustomHomepageRuntime): void {
    this.customHomepageRuntime = runtime;
  }

  getSnapshot(): HomeShortcutApplicationSnapshot {
    return {
      scenarioId: this.scenarioId,
      shortcuts: this.logicService.cloneList(this.shortcuts),
      layoutVersion: this.layoutVersion,
      iconsVersion: this.iconsVersion,
      icons: this.icons.slice()
    };
  }

  getSelectionSnapshot(): HomeShortcutSelectionState {
    return this.selectionCoordinator.getSnapshot();
  }

  openSelectionSession(): void {
    this.selectionCoordinator.openSession(this.shortcuts, this.scenarioId);
  }

  handleSelectionAction(action: HomeShortcutSelectionAction): void {
    this.selectionCoordinator.handleAction(action);
  }

  handleSelectionBack(): void {
    this.selectionCoordinator.handleSystemBack();
  }

  resetSelectionSession(): void {
    this.selectionCoordinator.resetSession();
  }

  buildPresentationState(
    snapshot: HomeShortcutApplicationSnapshot,
    input: HomeShortcutPresentationInput
  ): HomeShortcutPresentationState {
    const facts = this.shell.resolveFacts();
    return {
      shortcuts: this.viewModel.resolvePresentationShortcuts(snapshot.shortcuts),
      showAddEntry: this.canShowHomeAddEntry(facts.dataScope, facts.privacyMode),
      gridWidth: input.gridWidth,
      gridTopInset: input.gridTopInset,
      layoutVersion: this.viewModel.buildLayoutVersion(
        snapshot.layoutVersion,
        input.viewportWidth,
        input.viewportHeight,
        input.gridWidth,
        input.metrics
      ),
      iconsVersion: snapshot.iconsVersion,
      icons: snapshot.icons,
      metrics: input.metrics
    };
  }

  refresh(): void {
    if (this.persistRunning || this.persistQueue.length > 0) {
      this.refreshPending = true;
      return;
    }
    this.refreshPending = false;
    const refreshStartedAt = Date.now();
    const token = this.nextLoadGeneration();
    hilog.info(
      DOMAIN,
      TAG,
      '[DEBUG-FAVICON-COLDSTART] refresh_start token=%{public}d preparedShortcuts=%{public}d preparedIcons=%{public}d',
      token,
      this.shortcuts.length,
      this.icons.length
    );
    const facts = this.shell.resolveFacts();
    const shortcutPolicy = this.resolveShortcutPolicy(facts.dataScope, facts.privacyMode);
    if (!shortcutPolicy.persistentReadAllowed) {
      this.applyLoadedState(DEFAULT_HOME_SHORTCUT_SCENARIO_ID, [], true, true);
      this.iconHydrationCoordinator.clear(this.iconHydrationCallbacks);
      this.initialIconHydrationPending = false;
      this.executeEffect({ type: 'set_helper_message', message: '' });
      return;
    }
    void this.loadCurrentScenario()
      .then(async (loaded: HomeShortcutApplicationSnapshot): Promise<void> => {
        if (!this.isCurrentLoadGeneration(token)) {
          return;
        }
        const changed = this.buildLoadSignature(this.getSnapshot()) !== this.buildLoadSignature(loaded);
        hilog.info(
          DOMAIN,
          TAG,
          '[DEBUG-FAVICON-COLDSTART] refresh_loaded token=%{public}d changed=%{public}s shortcuts=%{public}d durationMs=%{public}d',
          token,
          `${changed}`,
          loaded.shortcuts.length,
          Date.now() - refreshStartedAt
        );
        if (!changed) {
          if (!this.initialIconHydrationPending) {
            hilog.info(
              DOMAIN,
              TAG,
              '[DEBUG-FAVICON-COLDSTART] refresh_hydration_skipped token=%{public}d reason=already_hydrated',
              token
            );
            this.refreshConsumers(false, false);
            return;
          }
          const hydrationStartedAt = Date.now();
          await this.iconHydrationCoordinator.resolveFor(
            loaded.shortcuts,
            this.iconHydrationCallbacks,
            'settled'
          );
          hilog.info(
            DOMAIN,
            TAG,
            '[DEBUG-FAVICON-COLDSTART] refresh_hydration_settled token=%{public}d shortcuts=%{public}d durationMs=%{public}d totalMs=%{public}d',
            token,
            loaded.shortcuts.length,
            Date.now() - hydrationStartedAt,
            Date.now() - refreshStartedAt
          );
          if (!this.isCurrentLoadGeneration(token)) {
            return;
          }
          this.initialIconHydrationPending = false;
          this.refreshConsumers(false, false);
          return;
        }
        const hydrationStartedAt = Date.now();
        await this.iconHydrationCoordinator.resolveFor(
          loaded.shortcuts,
          this.iconHydrationCallbacks,
          'settled'
        );
        hilog.info(
          DOMAIN,
          TAG,
          '[DEBUG-FAVICON-COLDSTART] refresh_hydration_settled token=%{public}d shortcuts=%{public}d durationMs=%{public}d totalMs=%{public}d',
          token,
          loaded.shortcuts.length,
          Date.now() - hydrationStartedAt,
          Date.now() - refreshStartedAt
        );
        if (!this.isCurrentLoadGeneration(token)) {
          return;
        }
        this.initialIconHydrationPending = false;
        this.applyLoadedState(loaded.scenarioId, loaded.shortcuts, true, true);
      })
      .catch((error: Error): void => {
        if (!this.isCurrentLoadGeneration(token)) {
          return;
        }
        hilog.warn(
          DOMAIN,
          TAG,
          '[DEBUG-FAVICON-COLDSTART] refresh_failed token=%{public}d durationMs=%{public}d',
          token,
          Date.now() - refreshStartedAt
        );
        this.executeEffect({
          type: 'set_helper_message',
          message: `快捷方式加载失败：${this.stringifyError(error)}`
        });
        this.applyLoadedState(DEFAULT_HOME_SHORTCUT_SCENARIO_ID, [], true, true);
        this.iconHydrationCoordinator.clear(this.iconHydrationCallbacks);
      });
  }

  handleUserAction(action: HomeShortcutUserAction): HomeShortcutActionDispatchResult {
    switch (action.type) {
      case 'shortcut_action':
        return this.handleItemAction(action.shortcutId, action.actionId);
      case 'move_shortcut':
        return this.moveShortcutFromTo(action.request);
      case 'confirm_edit_shortcut':
        return this.confirmEdit(action.draft);
      case 'reorder_shortcuts':
        return this.reorderShortcuts(action.orderedShortcutIds);
    }
  }

  private async loadCurrentScenario(): Promise<HomeShortcutApplicationSnapshot> {
    const startedAt = Date.now();
    hilog.info(DOMAIN, TAG, '[DEBUG-FAVICON-COLDSTART] shortcut_load_start');
    await sharedShortcutRepository.initialize();
    const allShortcuts = sharedShortcutRepository.listAll();
    const appOwnedShortcuts = this.logicService.filterAppOwnedShortcuts(allShortcuts);
    const snapshot: HomeShortcutApplicationSnapshot = {
      scenarioId: this.scenarioId.length > 0 ? this.scenarioId : DEFAULT_HOME_SHORTCUT_SCENARIO_ID,
      shortcuts: this.logicService.normalizeListPositions(appOwnedShortcuts),
      layoutVersion: this.layoutVersion,
      iconsVersion: this.iconsVersion,
      icons: this.icons.slice()
    };
    hilog.info(
      DOMAIN,
      TAG,
      '[DEBUG-FAVICON-COLDSTART] shortcut_load_done total=%{public}d appOwned=%{public}d durationMs=%{public}d',
      allShortcuts.length,
      snapshot.shortcuts.length,
      Date.now() - startedAt
    );
    return snapshot;
  }

  private applyLoadedState(
    scenarioId: string,
    shortcuts: ShortcutRecord[],
    bumpLayoutVersion: boolean,
    syncCustomHomepage: boolean
  ): void {
    this.scenarioId = scenarioId.length > 0 ? scenarioId : DEFAULT_HOME_SHORTCUT_SCENARIO_ID;
    this.shortcuts = this.logicService.normalizeListPositions(shortcuts);
    if (bumpLayoutVersion) {
      this.layoutVersion += 1;
    }
    this.publishSnapshot();
    this.refreshConsumers(true, syncCustomHomepage);
  }

  private handleItemAction(
    shortcutId: string,
    actionId: HomeShortcutItemActionId
  ): HomeShortcutActionDispatchResult {
    switch (actionId) {
      case 'open':
        return this.openShortcut(shortcutId, 'current_tab');
      case 'open_new_tab':
        return this.openShortcut(shortcutId, 'new_tab');
      case 'open_background_tab':
        return this.openShortcut(shortcutId, 'background_tab');
      case 'copy_link':
        return this.copyShortcutUrl(shortcutId);
      case 'edit':
        return this.requestEdit(shortcutId);
      case 'move_top':
        return this.moveShortcutToBoundary(shortcutId, 'top');
      case 'move_bottom':
        return this.moveShortcutToBoundary(shortcutId, 'bottom');
      case 'delete':
        return this.requestDelete(shortcutId);
      case 'move_up':
        return this.moveShortcutByStep(shortcutId, 'up');
      case 'move_down':
        return this.moveShortcutByStep(shortcutId, 'down');
      case 'remove':
        return this.removeShortcut(shortcutId, false);
      case 'confirm_delete':
        return this.removeShortcut(shortcutId, true);
    }
  }

  private openShortcut(
    shortcutId: string,
    intent: 'current_tab' | 'new_tab' | 'background_tab'
  ): HomeShortcutActionDispatchResult {
    const shortcut = this.findShortcut(shortcutId);
    if (shortcut === undefined) {
      this.showToast('未找到这个快捷方式。');
      return 'not_found';
    }
    const facts = this.shell.resolveFacts();
    const outcome: HomeShortcutOpenOutcome = this.dependencies.openCoordinator.openShortcut(
      shortcut,
      facts.activeTabId,
      intent
    );
    this.executeEffect({ type: 'dismiss_context_menu' });
    if (outcome.failureMessage.length > 0) {
      this.showToast(outcome.failureMessage);
    }
    return 'accepted';
  }

  private copyShortcutUrl(shortcutId: string): HomeShortcutActionDispatchResult {
    const shortcut = this.findShortcut(shortcutId);
    if (shortcut === undefined) {
      this.showToast('未找到这个快捷方式。');
      return 'not_found';
    }
    this.executeEffect({ type: 'dismiss_context_menu' });
    void this.dependencies.clipboardService.copyText({
      value: shortcut.url.trim(),
      emptyMessage: '当前没有可复制的链接。',
      successMessage: '链接已复制。'
    }).then((result): void => {
      this.showToast(result.message);
    }).catch((error: Error): void => {
      this.showToast(this.stringifyError(error));
    });
    return 'accepted';
  }

  private requestEdit(shortcutId: string): HomeShortcutActionDispatchResult {
    const shortcut = this.findShortcut(shortcutId);
    if (shortcut === undefined) {
      this.showToast('未找到这个快捷方式。');
      return 'not_found';
    }
    const resolvedIcon = this.icons.find((icon: HomeShortcutIconState) => icon.id === shortcut.id);
    this.executeEffect({ type: 'dismiss_context_menu' });
    this.executeEffect({
      type: 'open_edit_dialog',
      draft: {
        shortcutId: shortcut.id,
        title: shortcut.title,
        url: shortcut.url,
        iconPath: resolvedIcon?.path ?? ''
      }
    });
    return 'accepted';
  }

  private confirmEdit(draft: HomeShortcutEditDraft): HomeShortcutActionDispatchResult {
    if (!this.ensurePersistentWriteAllowed('edit_home_shortcut')) {
      return 'not_allowed';
    }
    const shortcut = this.findShortcut(draft.shortcutId);
    if (shortcut === undefined) {
      this.showDialog('保存失败', '未找到要编辑的快捷方式。');
      return 'not_found';
    }
    const normalizedTitle = draft.title.trim();
    const normalizedUrl = draft.url.trim();
    if (normalizedTitle.length === 0) {
      this.showDialog('保存失败', '请输入名称。');
      return 'invalid_request';
    }
    if (normalizedUrl.length === 0) {
      this.showDialog('保存失败', '请输入网址。');
      return 'invalid_request';
    }
    const result = this.replaceShortcutById(shortcut.id, (current: ShortcutRecord): ShortcutRecord => {
      const nextShortcut = this.logicService.cloneRecord(current);
      nextShortcut.title = normalizedTitle;
      nextShortcut.url = normalizedUrl;
      return nextShortcut;
    });
    void this.commitMutation(result, STRUCTURAL_MUTATION_POLICY)
      .then((updated: boolean): void => {
        if (!updated) {
          this.showDialog('保存失败', '未找到要编辑的快捷方式。');
          return;
        }
        this.showToast('快捷方式已保存。');
      })
      .catch((error: Error): void => {
        this.showDialog('保存失败', `保存失败：${this.stringifyError(error)}`);
      });
    return 'accepted';
  }

  private requestDelete(shortcutId: string): HomeShortcutActionDispatchResult {
    const shortcut = this.findShortcut(shortcutId);
    if (shortcut === undefined) {
      this.showToast('未找到这个快捷方式。');
      return 'not_found';
    }
    this.executeEffect({ type: 'dismiss_context_menu' });
    this.executeEffect({
      type: 'confirm_delete',
      confirmation: {
        shortcutId: shortcut.id,
        title: shortcut.title
      }
    });
    return 'accepted';
  }

  private removeShortcut(
    shortcutId: string,
    showSuccessFeedback: boolean
  ): HomeShortcutActionDispatchResult {
    if (!this.ensurePersistentWriteAllowed('delete_home_shortcut')) {
      return 'not_allowed';
    }
    const removal = this.logicService.removeById(this.shortcuts, shortcutId);
    const result: HomeShortcutTreeMutationResult = {
      shortcuts: removal.shortcuts,
      changed: removal.removed
    };
    if (!result.changed) {
      if (showSuccessFeedback) {
        this.showDialog('删除失败', '未找到要删除的快捷方式。');
      }
      return 'not_found';
    }
    void this.commitMutation(result, STRUCTURAL_MUTATION_POLICY)
      .then((deleted: boolean): void => {
        if (showSuccessFeedback && deleted) {
          this.showToast('快捷方式已删除。');
        }
      })
      .catch((error: Error): void => {
        if (showSuccessFeedback) {
          this.showDialog('删除失败', `删除失败：${this.stringifyError(error)}`);
        }
      });
    return 'accepted';
  }

  private moveShortcutToBoundary(
    shortcutId: string,
    boundary: HomeShortcutMoveBoundary
  ): HomeShortcutActionDispatchResult {
    if (!this.ensurePersistentWriteAllowed('move_home_shortcut')) {
      return 'not_allowed';
    }
    const shortcut = this.findShortcut(shortcutId);
    if (shortcut === undefined) {
      this.showToast('未找到要移动的快捷方式。');
      return 'not_found';
    }
    const result = this.logicService.moveById(this.shortcuts, shortcutId, boundary);
    if (!result.changed) {
      this.showToast(boundary === 'top' ? '已经在最前面了。' : '已经在最后面了。');
      return 'unchanged';
    }
    void this.commitMutation(result, ORDER_MUTATION_POLICY)
      .then((): void => {
        this.showToast(boundary === 'top'
          ? `已将“${shortcut.title}”置顶。`
          : `已将“${shortcut.title}”置底。`);
      })
      .catch((error: Error): void => {
        this.showDialog('移动失败', `移动失败：${this.stringifyError(error)}`);
      });
    return 'accepted';
  }

  private moveShortcutByStep(
    shortcutId: string,
    step: HomeShortcutMoveStep
  ): HomeShortcutActionDispatchResult {
    if (!this.ensurePersistentWriteAllowed('move_home_shortcut')) {
      return 'not_allowed';
    }
    const shortcut = this.findShortcut(shortcutId);
    if (shortcut === undefined) {
      this.showToast('未找到要移动的快捷方式。');
      return 'not_found';
    }
    const result = this.logicService.moveByIdStep(this.shortcuts, shortcutId, step);
    if (!result.changed) {
      this.showToast(step === 'up' ? '已经在最前面了。' : '已经在最后面了。');
      return 'unchanged';
    }
    void this.commitMutation(result, ORDER_MUTATION_POLICY)
      .then((): void => {
        this.showToast(step === 'up'
          ? `已上移“${shortcut.title}”。`
          : `已下移“${shortcut.title}”。`);
      })
      .catch((error: Error): void => {
        this.showDialog('移动失败', `移动失败：${this.stringifyError(error)}`);
      });
    return 'accepted';
  }

  private moveShortcutFromTo(request: HomeShortcutMoveRequest): HomeShortcutActionDispatchResult {
    if (!this.ensurePersistentWriteAllowed('move_home_shortcut')) {
      return 'not_allowed';
    }
    const result = this.logicService.moveFromTo(this.shortcuts, request);
    if (!result.changed) {
      return 'unchanged';
    }
    void this.commitMutation(result, DRAG_ORDER_MUTATION_POLICY).catch((error: Error): void => {
      hilog.warn(
        DOMAIN,
        TAG,
        'drag persist failed id=%{public}s from=%{public}d to=%{public}d error=%{public}s',
        request.shortcutId,
        request.expectedFromIndex,
        request.targetIndex,
        this.stringifyError(error)
      );
    });
    return 'accepted';
  }

  private reorderShortcuts(orderedShortcutIds: string[]): HomeShortcutActionDispatchResult {
    if (!this.ensurePersistentWriteAllowed('move_home_shortcut')) {
      return 'not_allowed';
    }
    const result: HomeShortcutReorderResult = this.logicService.reorderByIds(
      this.shortcuts,
      orderedShortcutIds
    );
    if (!result.valid) {
      return 'invalid_request';
    }
    if (!result.changed) {
      return 'unchanged';
    }
    void this.commitMutation(result, DRAG_ORDER_MUTATION_POLICY).catch((error: Error): void => {
      hilog.warn(
        DOMAIN,
        TAG,
        'custom homepage reorder persist failed count=%{public}d error=%{public}s',
        orderedShortcutIds.length,
        this.stringifyError(error)
      );
    });
    return 'accepted';
  }

  private replaceShortcutById(
    shortcutId: string,
    transform: (shortcut: ShortcutRecord) => ShortcutRecord
  ): HomeShortcutTreeMutationResult {
    let updated = false;
    const nextShortcuts = this.logicService.mapList(this.shortcuts, (shortcut: ShortcutRecord): ShortcutRecord => {
      if (shortcut.id !== shortcutId) {
        return shortcut;
      }
      updated = true;
      return transform(shortcut);
    });
    return {
      shortcuts: nextShortcuts,
      changed: updated
    };
  }

  private commitMutation(
    result: HomeShortcutTreeMutationResult,
    policy: HomeShortcutMutationPolicy
  ): Promise<boolean> {
    if (!result.changed) {
      return Promise.resolve(false);
    }
    this.nextLoadGeneration();
    const nextShortcuts = this.logicService.normalizeListPositions(result.shortcuts);
    this.executeEffect({ type: 'dismiss_context_menu' });
    this.shortcuts = nextShortcuts;
    if (policy.bumpLayoutVersion) {
      this.layoutVersion += 1;
    }
    this.publishSnapshot();
    this.refreshConsumers(true, true);
    if (policy.refreshIcons) {
      this.resolveIcons();
    }
    return this.enqueuePersist(nextShortcuts, policy.notifyMoveFailure).then(() => true);
  }

  private enqueuePersist(
    shortcuts: ShortcutRecord[],
    notifyMoveFailure: boolean
  ): Promise<void> {
    const scenarioId = this.scenarioId;
    const snapshot = this.logicService.cloneList(shortcuts);
    return new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      const waiter: HomeShortcutPersistWaiter = {
        resolve: resolve,
        reject: reject,
        notifyMoveFailure: notifyMoveFailure
      };
      const lastIndex = this.persistQueue.length - 1;
      const lastBatch = lastIndex >= 0 ? this.persistQueue[lastIndex] : undefined;
      if (lastBatch !== undefined && lastBatch.scenarioId === scenarioId) {
        lastBatch.shortcuts = snapshot;
        lastBatch.waiters.push(waiter);
      } else {
        this.persistQueue.push({
          scenarioId: scenarioId,
          shortcuts: snapshot,
          waiters: [waiter]
        });
      }
      if (!this.persistRunning) {
        void this.flushPersistQueue();
      }
    });
  }

  private async flushPersistQueue(): Promise<void> {
    if (this.persistRunning) {
      return;
    }
    this.persistRunning = true;
    try {
      while (this.persistQueue.length > 0) {
        const batch = this.persistQueue.shift();
        if (batch === undefined) {
          continue;
        }
        try {
          await this.persistHomeShortcutTree(batch.scenarioId, batch.shortcuts);
          this.resolveWaiters(batch.waiters);
        } catch (error) {
          const normalizedError = this.normalizeThrowable(error);
          const pendingBatches = this.persistQueue.splice(0);
          this.rejectWaiters(batch.waiters, normalizedError);
          pendingBatches.forEach((pending: HomeShortcutPersistBatch): void => {
            this.rejectWaiters(pending.waiters, normalizedError);
          });
          this.recoverPersistFailure(batch, pendingBatches);
          return;
        }
      }
    } finally {
      this.persistRunning = false;
      if (this.refreshPending) {
        this.refreshPending = false;
        this.refresh();
      }
    }
  }

  private persistHomeShortcutTree(
    scenarioId: string,
    shortcuts: ShortcutRecord[]
  ): Promise<ShortcutRecord[]> {
    return sharedShortcutRepository.replaceScenarioShortcuts({
      scenarioId: scenarioId,
      shortcuts: this.logicService.normalizeListPositions(shortcuts)
    });
  }

  private recoverPersistFailure(
    failedBatch: HomeShortcutPersistBatch,
    pendingBatches: HomeShortcutPersistBatch[]
  ): void {
    const batches: HomeShortcutPersistBatch[] = [failedBatch];
    pendingBatches.forEach((batch: HomeShortcutPersistBatch): void => {
      batches.push(batch);
    });
    const notifyMoveFailure = batches.some((batch: HomeShortcutPersistBatch): boolean => {
      return batch.waiters.some((waiter: HomeShortcutPersistWaiter): boolean => waiter.notifyMoveFailure);
    });
    this.refresh();
    if (notifyMoveFailure) {
      this.showToast('排序保存失败，已恢复已保存的顺序。');
    }
  }

  private resolveWaiters(waiters: HomeShortcutPersistWaiter[]): void {
    waiters.forEach((waiter: HomeShortcutPersistWaiter): void => waiter.resolve());
  }

  private rejectWaiters(waiters: HomeShortcutPersistWaiter[], error: Error): void {
    waiters.forEach((waiter: HomeShortcutPersistWaiter): void => waiter.reject(error));
  }

  private resolveIcons(): void {
    void this.iconHydrationCoordinator.resolveFor(this.shortcuts, this.iconHydrationCallbacks);
  }

  private applyIconHydrationSnapshot(snapshot: HomeShortcutIconHydrationSnapshot): void {
    this.icons = snapshot.icons;
    this.iconsVersion += 1;
    this.publishSnapshot();
    this.syncCustomHomepage();
  }

  private persistResolvedIcon(shortcutId: string, sourceUrl: string, iconPath: string): void {
    const normalizedIconPath = iconPath.trim();
    if (normalizedIconPath.length === 0) {
      return;
    }
    const shortcut = this.findShortcut(shortcutId);
    if (shortcut !== undefined && (shortcut.url !== sourceUrl ||
      (shortcut.icon ?? '').trim() === normalizedIconPath)) {
      return;
    }
    void sharedShortcutRepository.updateShortcutIcon(shortcutId, sourceUrl, normalizedIconPath)
      .then((updatedShortcut: ShortcutRecord | undefined): void => {
        const currentShortcut = this.findShortcut(shortcutId);
        if (updatedShortcut === undefined || currentShortcut === undefined || currentShortcut.url !== sourceUrl) {
          return;
        }
        this.shortcuts = this.shortcuts.map((item: ShortcutRecord): ShortcutRecord => {
          if (item.id !== shortcutId) {
            return item;
          }
          const nextShortcut = this.logicService.cloneRecord(item);
          nextShortcut.icon = updatedShortcut.icon;
          return nextShortcut;
        });
        this.publishSnapshot();
        this.syncCustomHomepage();
      })
      .catch((error: Error): void => {
        hilog.warn(
          DOMAIN,
          TAG,
          'persist shortcut icon failed id=%{public}s error=%{public}s',
          shortcutId,
          this.stringifyError(error)
        );
      });
  }

  private canShowHomeAddEntry(dataScope: BrowserDataScope, privacyMode: BrowserSessionPrivacyMode): boolean {
    return this.resolveShortcutPolicy(dataScope, privacyMode).persistentWriteAllowed;
  }

  private ensurePersistentWriteAllowed(action: HomeShortcutPersistentWriteAction): boolean {
    const facts = this.shell.resolveFacts();
    const policy = this.resolveShortcutPolicy(facts.dataScope, facts.privacyMode);
    if (policy.persistentWriteAllowed) {
      return true;
    }
    this.executeEffect({
      type: 'present_boundary_block',
      summaryLine: `${policy.summaryLine} action=${action}`,
      helperText: '当前私密会话不可修改常规首页快捷方式。'
    });
    return false;
  }

  private resolveShortcutPolicy(
    dataScope: BrowserDataScope,
    privacyMode: BrowserSessionPrivacyMode
  ): BrowserPrivacyDataPolicy {
    return this.privacyEffectPolicy.resolveDataPolicy('home_shortcuts', {
      dataScope: dataScope,
      privacyMode: privacyMode
    });
  }

  private refreshConsumers(invalidateSearch: boolean, syncCustomHomepage: boolean): void {
    this.dependencies.recentlyClosedApplicationCoordinator.synchronizeHomeShortcuts(
      this.shortcuts,
      this.scenarioId
    );
    if (invalidateSearch) {
      this.dependencies.searchSuggestionCoordinator.invalidate();
    }
    if (syncCustomHomepage) {
      this.syncCustomHomepage();
    }
  }

  private syncCustomHomepage(): void {
    this.customHomepageRuntime?.syncBridge('shortcuts');
  }

  private publishSnapshot(): void {
    this.shell.publishSnapshot(this.getSnapshot());
  }

  private findShortcut(shortcutId: string): ShortcutRecord | undefined {
    return this.logicService.findById(this.shortcuts, shortcutId);
  }

  private buildLoadSignature(snapshot: HomeShortcutApplicationSnapshot): string {
    const parts: string[] = [snapshot.scenarioId];
    snapshot.shortcuts.forEach((shortcut: ShortcutRecord): void => {
      parts.push([
        shortcut.id,
        shortcut.scenarioId ?? '',
        shortcut.kind ?? 'web',
        shortcut.title,
        shortcut.url,
        shortcut.folderName,
        shortcut.position.toString(),
        shortcut.icon ?? '',
        shortcut.iconRendering ?? '',
        shortcut.iconColor ?? '',
        shortcut.updatedAt?.toString() ?? ''
      ].join('\u0001'));
    });
    return parts.join('\u0002');
  }

  private nextLoadGeneration(): number {
    this.loadGeneration += 1;
    return this.loadGeneration;
  }

  private isCurrentLoadGeneration(token: number): boolean {
    return token === this.loadGeneration;
  }

  private executeEffect(effect: HomeShortcutApplicationEffect): void {
    this.dependencies.effectApplication.apply(
      effect,
      (confirmation: HomeShortcutDeleteConfirmation): void => {
        this.handleUserAction({
          type: 'shortcut_action',
          shortcutId: confirmation.shortcutId,
          actionId: 'confirm_delete'
        });
      }
    );
  }

  private showToast(message: string): void {
    this.executeEffect({ type: 'show_toast', message: message });
  }

  private showDialog(title: string, message: string): void {
    this.executeEffect({ type: 'show_dialog', title: title, message: message });
  }

  private stringifyError(error: Error | Object | string | number | boolean | undefined): string {
    if (error === undefined) {
      return 'unknown error';
    }
    if (error instanceof Error) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_error) {
      return `${error}`;
    }
  }

  private normalizeThrowable(error: Error | Object | string | number | boolean | undefined): Error {
    if (error instanceof Error) {
      return error;
    }
    return new Error(this.stringifyError(error));
  }
}
