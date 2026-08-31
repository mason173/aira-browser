import {
  BrowserDataBoundaryInput,
  ShortcutKind,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import { ShortcutRepository } from '../../data/repositories/BrowserRepositories';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';
import { BrowserPrivacyEffectPolicyService } from '../privacy/BrowserPrivacyEffectPolicyService';
import { HomeShortcutLogicService } from './HomeShortcutLogicService';
import {
  resolveHomeShortcutKind,
  resolveHomeSystemShortcutDefinitionByUrl
} from './HomeSystemShortcutCatalog';

export interface HomeShortcutToggleTarget {
  title: string;
  url: string;
  kind?: ShortcutKind;
  scenarioId?: string;
}

export interface HomeShortcutToggleResult {
  added: boolean;
  removed: boolean;
  changed: boolean;
  shortcuts: ShortcutRecord[];
}

const DEFAULT_HOME_SHORTCUT_SCENARIO_ID: string = 'aira_default_scenario';

export class HomeShortcutToggleService {
  private static inFlightMutationsByRepository:
    Map<ShortcutRepository, Map<string, Promise<HomeShortcutToggleResult>>> = new Map();
  private repository: ShortcutRepository;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private logicService: HomeShortcutLogicService;

  constructor(
    repository: ShortcutRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService(),
    logicService: HomeShortcutLogicService = new HomeShortcutLogicService()
  ) {
    this.repository = repository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
    this.logicService = logicService;
  }

  async refresh(): Promise<ShortcutRecord[]> {
    await this.repository.initialize();
    await this.repository.refresh();
    return this.repository.listSyncShortcuts().filter((shortcut: ShortcutRecord): boolean => {
      return shortcut.sync?.deletedAt === undefined && this.isAppOwnedShortcut(shortcut);
    });
  }

  refreshForManagement(boundary: BrowserDataBoundaryInput): Promise<ShortcutRecord[]> {
    this.assertManagementEffectAllowed('regular_profile_management_read', boundary);
    return this.refresh();
  }

  isUrlAddedToScenario(url: string, shortcuts: ShortcutRecord[], scenarioId?: string): boolean {
    const targetKey = this.normalizeUrlKey(url);
    if (targetKey.length <= 0) {
      return false;
    }
    return this.findMatchingShortcuts(url, shortcuts, scenarioId).length > 0;
  }

  isTargetAddedToScenario(
    target: HomeShortcutToggleTarget,
    shortcuts: ShortcutRecord[],
    scenarioId?: string
  ): boolean {
    return this.findMatchingShortcutsForTarget(target, shortcuts, scenarioId).length > 0;
  }

  async toggle(target: HomeShortcutToggleTarget): Promise<HomeShortcutToggleResult> {
    return this.runSerializedMutation('toggle', target, (): Promise<HomeShortcutToggleResult> => {
      return this.toggleNow(target);
    });
  }

  private async toggleNow(target: HomeShortcutToggleTarget): Promise<HomeShortcutToggleResult> {
    const shortcuts = await this.refresh();
    const matches = this.findMatchingShortcutsForTarget(target, shortcuts, target.scenarioId);
    if (matches.length > 0) {
      let removedCount = 0;
      for (const shortcut of matches) {
        const deleted = await this.repository.deleteShortcut(shortcut.id);
        if (deleted) {
          removedCount += 1;
        }
      }
      return {
        added: false,
        removed: removedCount > 0,
        changed: removedCount > 0,
        shortcuts: this.repository.listAll()
      };
    }

    return this.createShortcut(target);
  }

  toggleForManagement(
    target: HomeShortcutToggleTarget,
    boundary: BrowserDataBoundaryInput
  ): Promise<HomeShortcutToggleResult> {
    this.assertManagementEffectAllowed('regular_profile_management_mutation', boundary);
    return this.toggle(target);
  }

  async addIfMissing(target: HomeShortcutToggleTarget): Promise<HomeShortcutToggleResult> {
    return this.runSerializedMutation('add_if_missing', target, (): Promise<HomeShortcutToggleResult> => {
      return this.addIfMissingNow(target);
    });
  }

  private async addIfMissingNow(target: HomeShortcutToggleTarget): Promise<HomeShortcutToggleResult> {
    const shortcuts = await this.refresh();
    const matches = this.findMatchingShortcutsForTarget(target, shortcuts, target.scenarioId);
    if (matches.length > 0) {
      return {
        added: false,
        removed: false,
        changed: false,
        shortcuts: shortcuts
      };
    }
    return this.createShortcut(target);
  }

  findMatchingShortcuts(url: string, shortcuts: ShortcutRecord[], _scenarioId?: string): ShortcutRecord[] {
    const targetKey = this.normalizeUrlKey(url);
    if (targetKey.length <= 0) {
      return [];
    }
    return shortcuts.filter((shortcut: ShortcutRecord) => {
      return shortcut.sync?.deletedAt === undefined &&
        this.isAppOwnedShortcut(shortcut) &&
        resolveHomeShortcutKind(shortcut.kind) === 'web' &&
        this.normalizeUrlKey(shortcut.url) === targetKey;
    });
  }

  private findMatchingShortcutsForTarget(
    target: HomeShortcutToggleTarget,
    shortcuts: ShortcutRecord[],
    _scenarioId?: string
  ): ShortcutRecord[] {
    const targetIdentity = this.logicService.resolveDestinationIdentity(target.kind, target.url);
    if (targetIdentity.length <= 0) {
      return [];
    }
    return shortcuts.filter((shortcut: ShortcutRecord) => {
      return shortcut.sync?.deletedAt === undefined &&
        this.isAppOwnedShortcut(shortcut) &&
        this.logicService.resolveShortcutDestinationIdentity(shortcut) === targetIdentity;
    });
  }

  normalizeUrlKey(url: string): string {
    return this.logicService.normalizeUrlKey(url);
  }

  normalizeShortcutUrl(url: string): string {
    return this.logicService.normalizeShortcutUrl(url);
  }

  private resolveShortcutTitle(title: string, fallbackUrl: string): string {
    const trimmed = title.trim();
    return trimmed.length > 0 ? trimmed : fallbackUrl;
  }

  private assertManagementEffectAllowed(
    intent: 'regular_profile_management_read' | 'regular_profile_management_mutation',
    boundary: BrowserDataBoundaryInput
  ): void {
    const decision = this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundary),
      targetScope: 'regular_profile_data',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      throw new Error('Home Shortcut management privacy effect was not allowed.');
    }
  }

  private resolveScenarioId(scenarioId?: string): string {
    const normalized = (scenarioId ?? '').trim();
    return normalized.length > 0 ? normalized : DEFAULT_HOME_SHORTCUT_SCENARIO_ID;
  }

  private isAppOwnedShortcut(shortcut: ShortcutRecord): boolean {
    const source = shortcut.sync?.source;
    return source === undefined || source === 'seed' || source === 'local';
  }

  private async createShortcut(target: HomeShortcutToggleTarget): Promise<HomeShortcutToggleResult> {
    const kind = resolveHomeShortcutKind(target.kind);
    const normalizedUrl = this.normalizeShortcutUrl(target.url);
    if (normalizedUrl.length <= 0 || normalizedUrl === 'about:blank') {
      throw new Error('当前没有可添加到主页的链接。');
    }
    const systemDefinition = kind === 'system' ? resolveHomeSystemShortcutDefinitionByUrl(normalizedUrl) : undefined;
    if (kind === 'system' && systemDefinition === undefined) {
      throw new Error('这个系统入口暂不可添加到主页。');
    }
    await this.repository.createShortcut({
      title: systemDefinition?.title ?? this.resolveShortcutTitle(target.title, normalizedUrl),
      url: normalizedUrl,
      kind: kind,
      scenarioId: this.resolveScenarioId(target.scenarioId),
      icon: ''
    });
    return {
      added: true,
      removed: false,
      changed: true,
      shortcuts: this.repository.listAll()
    };
  }

  private runSerializedMutation(
    operationId: string,
    target: HomeShortcutToggleTarget,
    operation: () => Promise<HomeShortcutToggleResult>
  ): Promise<HomeShortcutToggleResult> {
    const mutationKey = this.buildMutationKey(operationId, target);
    let inFlightMutations = HomeShortcutToggleService.inFlightMutationsByRepository.get(this.repository);
    if (inFlightMutations === undefined) {
      inFlightMutations = new Map();
      HomeShortcutToggleService.inFlightMutationsByRepository.set(this.repository, inFlightMutations);
    }
    const existing = inFlightMutations.get(mutationKey);
    if (existing !== undefined) {
      return existing;
    }
    const run = this.repository.runExclusiveMutation(operation);
    inFlightMutations.set(mutationKey, run);
    void run.then(
      (): void => this.clearInFlightMutation(mutationKey, run),
      (): void => this.clearInFlightMutation(mutationKey, run)
    );
    return run;
  }

  private buildMutationKey(operationId: string, target: HomeShortcutToggleTarget): string {
    const identity = this.logicService.resolveDestinationIdentity(target.kind, target.url);
    const fallbackIdentity = `${resolveHomeShortcutKind(target.kind)}:${target.url.trim().toLowerCase()}`;
    return `${operationId}:${identity.length > 0 ? identity : fallbackIdentity}`;
  }

  private clearInFlightMutation(key: string, completed: Promise<HomeShortcutToggleResult>): void {
    const inFlightMutations = HomeShortcutToggleService.inFlightMutationsByRepository.get(this.repository);
    if (inFlightMutations?.get(key) === completed) {
      inFlightMutations.delete(key);
      if (inFlightMutations.size <= 0) {
        HomeShortcutToggleService.inFlightMutationsByRepository.delete(this.repository);
      }
    }
  }
}
