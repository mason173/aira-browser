import { SitePermissionKind } from '../../common/models/BrowserModels';
import { BrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import {
  SettingsCenterDestination,
  SettingsCenterGroupState,
  SettingsCenterRowState,
  SettingsCenterState
} from './SettingsCenterViewModel';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import {
  SettingsDestinationPanelKind,
  SettingsDestinationCatalog,
  SettingsDestinationCatalogMatch,
  SettingsDestinationCatalogTarget,
  SettingsDestinationSubpagePresentation
} from './SettingsDestinationCatalog';

export interface SettingsCenterSearchResultState {
  id: string;
  destination: SettingsCenterDestination;
  title: string;
  isAvailable: boolean;
  unavailableReason: string;
  icon?: Resource;
  imageIcon?: Resource;
  airaIconId?: AiraRenderableIconId;
}

export interface SettingsCenterSearchGroupState {
  id: string;
  title: string;
  rows: SettingsCenterSearchResultState[];
}

export interface SettingsCenterSearchState {
  query: string;
  isActive: boolean;
  groups: SettingsCenterSearchGroupState[];
  resultCount: number;
}

export const DEFAULT_SETTINGS_CENTER_SEARCH_STATE: SettingsCenterSearchState = {
  query: '',
  isActive: false,
  groups: [],
  resultCount: 0
};

class SettingsSearchCandidate {
  state: SettingsCenterSearchResultState;
  tier: number;
  specificity: number;
  catalogOrder: number;

  constructor(
    state: SettingsCenterSearchResultState,
    tier: number,
    specificity: number,
    catalogOrder: number
  ) {
    this.state = state;
    this.tier = tier;
    this.specificity = specificity;
    this.catalogOrder = catalogOrder;
  }
}

// `twoPane` is reserved for the desktop settings directory. A wide touch
// window can still use split geometry and embedded details, but keeps the
// compact catalog's availability.
export type SettingsNavigationShellMode = 'compact' | 'touchTwoPane' | 'twoPane';
export type SettingsNavigationDetailKind =
  'primary' |
  'web_apps_root' |
  'web_app_detail' |
  'site_permission' |
  'desktop_site' |
  'embedded_subpage';
export type SettingsNavigationIntentKind =
  'set_shell' |
  'select_primary' |
  'select_search_target' |
  'open_web_app_detail' |
  'open_site_permission' |
  'open_desktop_site' |
  'open_embedded_subpage' |
  'start_full_screen_task' |
  'close' |
  'back';
export type SettingsNavigationFailureReason =
  '' |
  'invalid_transition' |
  'capability_missing' |
  'router_failed';

export interface SettingsDestinationNavigationRouter {
  openRoutedDestination(
    target: SettingsRoutedDestination,
    boundary: BrowserBoundaryRouteState
  ): Promise<boolean>;
  exitSettings(): Promise<boolean>;
}

export type SettingsNavigationObserver = (snapshot: SettingsNavigationSnapshot) => void;

export class SettingsNavigationIntent {
  kind: SettingsNavigationIntentKind;
  shellMode: SettingsNavigationShellMode = 'compact';
  destination: SettingsCenterDestination = 'general';
  shortcutId: string = '';
  host: string = '';
  origin: string = '';
  permissionKind: SitePermissionKind = 'camera';
  subpageId: string = '';
  taskId: string = '';
  targetId: string = '';
  centerState: SettingsCenterState | undefined = undefined;
  boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };

  private constructor(kind: SettingsNavigationIntentKind) {
    this.kind = kind;
  }

  static setShell(shellMode: SettingsNavigationShellMode): SettingsNavigationIntent {
    const intent = new SettingsNavigationIntent('set_shell');
    intent.shellMode = shellMode;
    return intent;
  }

  static selectPrimary(
    destination: SettingsCenterDestination,
    centerState: SettingsCenterState,
    boundary: BrowserBoundaryRouteState = new SettingsNavigationBoundary()
  ): SettingsNavigationIntent {
    const intent = new SettingsNavigationIntent('select_primary');
    intent.destination = destination;
    intent.centerState = centerState;
    intent.boundary = boundary;
    return intent;
  }

  static selectSearchTarget(
    targetId: string,
    centerState: SettingsCenterState,
    boundary: BrowserBoundaryRouteState = new SettingsNavigationBoundary()
  ): SettingsNavigationIntent {
    const intent = new SettingsNavigationIntent('select_search_target');
    intent.targetId = targetId.trim();
    intent.centerState = centerState;
    intent.boundary = boundary;
    return intent;
  }

  static openWebAppDetail(shortcutId: string): SettingsNavigationIntent {
    const intent = new SettingsNavigationIntent('open_web_app_detail');
    intent.shortcutId = shortcutId.trim();
    return intent;
  }

  static openSitePermission(
    host: string,
    origin: string,
    permissionKind: SitePermissionKind
  ): SettingsNavigationIntent {
    const intent = new SettingsNavigationIntent('open_site_permission');
    intent.host = host.trim();
    intent.origin = origin.trim();
    intent.permissionKind = permissionKind;
    return intent;
  }

  static openDesktopSite(host: string, origin: string): SettingsNavigationIntent {
    const intent = new SettingsNavigationIntent('open_desktop_site');
    intent.host = host.trim();
    intent.origin = origin.trim();
    return intent;
  }

  static openEmbeddedSubpage(subpageId: string): SettingsNavigationIntent {
    const intent = new SettingsNavigationIntent('open_embedded_subpage');
    intent.subpageId = subpageId.trim();
    return intent;
  }

  static startFullScreenTask(taskId: string): SettingsNavigationIntent {
    const intent = new SettingsNavigationIntent('start_full_screen_task');
    intent.taskId = taskId.trim();
    return intent;
  }

  static back(): SettingsNavigationIntent {
    return new SettingsNavigationIntent('back');
  }

  static close(): SettingsNavigationIntent {
    return new SettingsNavigationIntent('close');
  }
}

export class SettingsNavigationBoundary implements BrowserBoundaryRouteState {
  dataScope: string;
  privacyMode: string;
  boundarySource: string;

  constructor(dataScope: string = '', privacyMode: string = '', boundarySource: string = '') {
    this.dataScope = dataScope;
    this.privacyMode = privacyMode;
    this.boundarySource = boundarySource;
  }
}

export class SettingsNavigationSnapshot {
  shellMode: SettingsNavigationShellMode;
  selectedPrimaryDestination: SettingsCenterDestination;
  activeDetailKind: SettingsNavigationDetailKind;
  detailDepth: number;
  shortcutId: string;
  host: string;
  origin: string;
  permissionKind: SitePermissionKind;
  pathEntries: SettingsNavigationPathEntry[];
  subpageId: string;
  revealTargetId: string;
  revealRevision: number;
  activeDestination: SettingsCenterDestination;
  workspaceTitle: string;
  activePanelKind: SettingsDestinationPanelKind;

  constructor(
    shellMode: SettingsNavigationShellMode,
    selectedPrimaryDestination: SettingsCenterDestination,
    activeDetailKind: SettingsNavigationDetailKind,
    detailDepth: number,
    shortcutId: string,
    host: string,
    origin: string,
    permissionKind: SitePermissionKind,
    pathEntries: SettingsNavigationPathEntry[],
    subpageId: string = '',
    revealTargetId: string = '',
    revealRevision: number = 0,
    activeDestination: SettingsCenterDestination = 'general',
    workspaceTitle: string = '设置',
    activePanelKind: SettingsDestinationPanelKind = 'settings_destination'
  ) {
    this.shellMode = shellMode;
    this.selectedPrimaryDestination = selectedPrimaryDestination;
    this.activeDetailKind = activeDetailKind;
    this.detailDepth = detailDepth;
    this.shortcutId = shortcutId;
    this.host = host;
    this.origin = origin;
    this.permissionKind = permissionKind;
    this.pathEntries = pathEntries;
    this.subpageId = subpageId;
    this.revealTargetId = revealTargetId;
    this.revealRevision = revealRevision;
    this.activeDestination = activeDestination;
    this.workspaceTitle = workspaceTitle;
    this.activePanelKind = activePanelKind;
  }
}

class SettingsNavigationActivePresentation {
  destination: SettingsCenterDestination;
  title: string;
  panelKind: SettingsDestinationPanelKind;

  constructor(
    destination: SettingsCenterDestination,
    title: string,
    panelKind: SettingsDestinationPanelKind = 'settings_destination'
  ) {
    this.destination = destination;
    this.title = title;
    this.panelKind = panelKind;
  }
}

export class SettingsNavigationDispatchResult {
  handled: boolean;
  committed: boolean;
  failureReason: SettingsNavigationFailureReason;
  targetTitle: string;

  constructor(
    handled: boolean,
    committed: boolean,
    failureReason: SettingsNavigationFailureReason = '',
    targetTitle: string = ''
  ) {
    this.handled = handled;
    this.committed = committed;
    this.failureReason = failureReason;
    this.targetTitle = targetTitle;
  }
}

export class SettingsRoutedDestination {
  destination: SettingsCenterDestination;
  targetId: string;
  revealTargetId: string;
  subpageId: string;

  constructor(
    destination: SettingsCenterDestination,
    targetId: string = '',
    revealTargetId: string = '',
    subpageId: string = ''
  ) {
    this.destination = destination;
    this.targetId = targetId;
    this.revealTargetId = revealTargetId;
    this.subpageId = subpageId;
  }
}

export class SettingsNavigationPathEntry {
  readonly pathName: string;
  readonly destination: SettingsCenterDestination;
  readonly detailKind: SettingsNavigationDetailKind;
  readonly shortcutId: string;
  readonly host: string;
  readonly origin: string;
  readonly permissionKind: SitePermissionKind;
  readonly subpageId: string;

  constructor(
    pathName: string,
    destination: SettingsCenterDestination,
    detailKind: SettingsNavigationDetailKind,
    shortcutId: string = '',
    host: string = '',
    origin: string = '',
    permissionKind: SitePermissionKind = 'camera',
    subpageId: string = ''
  ) {
    this.pathName = pathName;
    this.destination = destination;
    this.detailKind = detailKind;
    this.shortcutId = shortcutId;
    this.host = host;
    this.origin = origin;
    this.permissionKind = permissionKind;
    this.subpageId = subpageId;
  }

  copy(): SettingsNavigationPathEntry {
    return new SettingsNavigationPathEntry(
      this.pathName,
      this.destination,
      this.detailKind,
      this.shortcutId,
      this.host,
      this.origin,
      this.permissionKind,
      this.subpageId
    );
  }

  projectionKey(): string {
    return `${this.pathName}:${this.destination}:${this.detailKind}:${this.shortcutId}:` +
      `${this.host}:${this.origin}:${this.permissionKind}:${this.subpageId}`;
  }
}

class SettingsNavigationObserverRecord {
  key: string;
  listener: SettingsNavigationObserver | undefined;

  constructor(key: string, listener: SettingsNavigationObserver) {
    this.key = key;
    this.listener = listener;
  }
}

export class SettingsDestinationNavigationOwner {
  private router: SettingsDestinationNavigationRouter;
  private catalog: SettingsDestinationCatalog = new SettingsDestinationCatalog();
  private shellMode: SettingsNavigationShellMode = 'compact';
  private selectedPrimaryDestination: SettingsCenterDestination = 'general';
  private detailStack: SettingsNavigationPathEntry[] = [
    new SettingsNavigationPathEntry('settings-primary-general', 'general', 'primary')
  ];
  private observers: SettingsNavigationObserverRecord[] = [];
  private observerSerial: number = 0;
  private revealTargetId: string = '';
  private revealRevision: number = 0;

  constructor(router: SettingsDestinationNavigationRouter) {
    this.router = router;
  }

  snapshot(): SettingsNavigationSnapshot {
    const activeEntry = this.resolveActiveEntry();
    const presentation = this.resolveActivePresentation(activeEntry);
    return new SettingsNavigationSnapshot(
      this.shellMode,
      this.selectedPrimaryDestination,
      activeEntry.detailKind,
      this.detailStack.length,
      activeEntry.shortcutId,
      activeEntry.host,
      activeEntry.origin,
      activeEntry.permissionKind,
      this.buildPublishedPathEntries(),
      activeEntry.subpageId,
      this.revealTargetId,
      this.revealRevision,
      presentation.destination,
      presentation.title,
      presentation.panelKind
    );
  }

  observe(listener: SettingsNavigationObserver): string {
    this.observerSerial += 1;
    const key = `settings-navigation-${this.observerSerial}`;
    this.observers.push(new SettingsNavigationObserverRecord(key, listener));
    return key;
  }

  unobserve(key: string): void {
    for (let index = 0; index < this.observers.length; index += 1) {
      const record = this.observers[index];
      if (record.key === key) {
        record.listener = undefined;
        return;
      }
    }
  }

  search(state: SettingsCenterState, query: string): SettingsCenterSearchState {
    if (query.trim().length === 0) {
      return DEFAULT_SETTINGS_CENTER_SEARCH_STATE;
    }
    const matches = this.catalog.search(query, this.shellMode);
    const candidates: SettingsSearchCandidate[] = [];
    for (let index = 0; index < matches.length; index += 1) {
      const match: SettingsDestinationCatalogMatch = matches[index];
      const sourceRow = this.findPrimaryRow(state, match.target.availabilityDestination);
      if (sourceRow === undefined) {
        continue;
      }
      const presentationRow = this.findPrimaryRow(state, match.target.destination) ?? sourceRow;
      const unavailableReason = sourceRow.isEnabled ? '' : this.resolveUnavailableReason(sourceRow);
      candidates.push(new SettingsSearchCandidate({
        id: match.target.id,
        destination: match.target.destination,
        title: match.target.title,
        isAvailable: sourceRow.isEnabled,
        unavailableReason: unavailableReason,
        icon: presentationRow.icon,
        imageIcon: presentationRow.imageIcon,
        airaIconId: presentationRow.airaIconId
      }, match.tier, match.target.kind === 'root' ? 0 : 1, match.catalogOrder));
    }
    candidates.sort((left: SettingsSearchCandidate, right: SettingsSearchCandidate): number => {
      if (left.tier !== right.tier) {
        return left.tier - right.tier;
      }
      if (left.specificity !== right.specificity) {
        return right.specificity - left.specificity;
      }
      if (left.state.isAvailable !== right.state.isAvailable) {
        return left.state.isAvailable ? -1 : 1;
      }
      return left.catalogOrder - right.catalogOrder;
    });
    const rows = candidates.map((candidate: SettingsSearchCandidate): SettingsCenterSearchResultState => {
      return candidate.state;
    });
    return {
      query: query,
      isActive: true,
      groups: rows.length > 0 ? [{
        id: 'settings_search_results',
        title: '搜索结果',
        rows: rows
      }] : [],
      resultCount: rows.length
    };
  }

  projectDirectoryState(state: SettingsCenterState): SettingsCenterState {
    if (this.shellMode === 'compact') {
      return state;
    }
    const rows: SettingsCenterRowState[] = [];
    for (let groupIndex = 0; groupIndex < state.groups.length; groupIndex += 1) {
      const sourceRows = state.groups[groupIndex].rows;
      for (let rowIndex = 0; rowIndex < sourceRows.length; rowIndex += 1) {
        const row = sourceRows[rowIndex];
        const catalogTarget = this.catalog.findTarget(row.id);
        if (catalogTarget !== undefined && this.catalog.isTargetPresentable(catalogTarget, this.shellMode)) {
          rows.push(row);
        }
      }
    }
    return {
      groups: [{
        id: 'desktop_directory',
        title: '',
        rows: rows
      }],
      appProxyNotice: state.appProxyNotice,
      showAccountCard: state.showAccountCard,
      showScanLoginAction: state.showScanLoginAction
    };
  }

  async dispatch(intent: SettingsNavigationIntent): Promise<SettingsNavigationDispatchResult> {
    switch (intent.kind) {
      case 'set_shell':
        return this.applyShell(intent.shellMode);
      case 'select_primary':
        return this.applyPrimarySelection(intent.destination, intent.centerState, intent.boundary);
      case 'select_search_target':
        return this.applySearchTargetSelection(intent);
      case 'open_web_app_detail':
        return this.pushWebAppDetail(intent.shortcutId);
      case 'open_site_permission':
        return this.pushSitePermission(intent.host, intent.origin, intent.permissionKind);
      case 'open_desktop_site':
        return this.pushDesktopSite(intent.host, intent.origin);
      case 'open_embedded_subpage':
        return this.pushEmbeddedSubpage(intent.subpageId);
      case 'start_full_screen_task':
        return new SettingsNavigationDispatchResult(true, false, 'capability_missing');
      case 'close':
        return this.applyExit();
      case 'back':
        return this.applyBack();
      default:
        return new SettingsNavigationDispatchResult(false, false, 'invalid_transition');
    }
  }

  resolveAvailablePrimary(
    state: SettingsCenterState,
    destination: SettingsCenterDestination
  ): SettingsCenterDestination {
    if (this.canOwnPrimarySession(state, destination)) {
      return destination;
    }
    for (let groupIndex = 0; groupIndex < state.groups.length; groupIndex += 1) {
      const group: SettingsCenterGroupState = state.groups[groupIndex];
      for (let rowIndex = 0; rowIndex < group.rows.length; rowIndex += 1) {
        const row: SettingsCenterRowState = group.rows[rowIndex];
        if (this.canOwnPrimarySession(state, row.id)) {
          return row.id;
        }
      }
    }
    return 'general';
  }

  private applyShell(shellMode: SettingsNavigationShellMode): SettingsNavigationDispatchResult {
    if (this.shellMode === shellMode) {
      return new SettingsNavigationDispatchResult(true, false);
    }
    this.shellMode = shellMode;
    this.publish();
    return new SettingsNavigationDispatchResult(true, true);
  }

  private async applyPrimarySelection(
    destination: SettingsCenterDestination,
    centerState: SettingsCenterState | undefined,
    boundary: BrowserBoundaryRouteState
  ): Promise<SettingsNavigationDispatchResult> {
    const target = this.resolvePrimaryTarget(destination);
    if (target === undefined || centerState === undefined ||
      !this.catalog.isTargetPresentable(target, this.shellMode)) {
      return new SettingsNavigationDispatchResult(true, false, 'capability_missing', target?.title ?? '');
    }
    const sourceRow = this.findPrimaryRow(centerState, target.availabilityDestination);
    if (sourceRow === undefined || !sourceRow.isEnabled) {
      return new SettingsNavigationDispatchResult(true, false, 'capability_missing', target.title);
    }
    if (this.catalog.requiresRoutedPresentation(target, this.shellMode)) {
      const didOpen = await this.router.openRoutedDestination(
        new SettingsRoutedDestination(destination, target.id),
        boundary
      );
      if (!didOpen) {
        return new SettingsNavigationDispatchResult(true, false, 'router_failed', target.title);
      }
      return new SettingsNavigationDispatchResult(true, false, '', target.title);
    }
    this.clearReveal();
    this.selectedPrimaryDestination = destination;
    if (destination === 'web_apps') {
      this.detailStack = [new SettingsNavigationPathEntry(
        'settings-web-apps-root',
        'web_apps',
        'web_apps_root'
      )];
    } else {
      this.detailStack = [new SettingsNavigationPathEntry(
        `settings-primary-${destination}`,
        destination,
        'primary'
      )];
    }
    this.publish();
    return new SettingsNavigationDispatchResult(true, true);
  }

  private async applySearchTargetSelection(
    intent: SettingsNavigationIntent
  ): Promise<SettingsNavigationDispatchResult> {
    const target = this.catalog.findTarget(intent.targetId);
    if (target === undefined || intent.centerState === undefined) {
      return new SettingsNavigationDispatchResult(true, false, 'capability_missing');
    }
    if (!this.catalog.isTargetPresentable(target, this.shellMode)) {
      return new SettingsNavigationDispatchResult(true, false, 'capability_missing', target.title);
    }
    if (this.findPrimaryRow(intent.centerState, target.availabilityDestination) === undefined) {
      return new SettingsNavigationDispatchResult(true, false, 'capability_missing', target.title);
    }
    const routedTarget = new SettingsRoutedDestination(
      target.destination,
      target.id,
      target.revealTargetId,
      target.subpageId
    );
    const primaryTarget = this.resolvePrimaryTarget(target.destination);
    if (primaryTarget === undefined) {
      return new SettingsNavigationDispatchResult(true, false, 'capability_missing', target.title);
    }
    if (this.catalog.requiresRoutedPresentation(primaryTarget, this.shellMode)) {
      let didOpen = false;
      try {
        didOpen = await this.router.openRoutedDestination(routedTarget, intent.boundary);
      } catch (_error) {
        return new SettingsNavigationDispatchResult(true, false, 'router_failed', target.title);
      }
      if (!didOpen) {
        return new SettingsNavigationDispatchResult(true, false, 'router_failed', target.title);
      }
      return new SettingsNavigationDispatchResult(true, true, '', target.title);
    }
    let subpagePresentation: SettingsDestinationSubpagePresentation | undefined = undefined;
    if (target.subpageId.length > 0 && target.subpageId !== 'about_details') {
      subpagePresentation = this.catalog.findSubpagePresentation(target.subpageId);
      if (subpagePresentation === undefined || subpagePresentation.primaryDestination !== target.destination) {
        return new SettingsNavigationDispatchResult(true, false, 'capability_missing', target.title);
      }
    }
    this.selectedPrimaryDestination = target.destination;
    this.detailStack = [this.buildPrimaryEntry(target.destination)];
    if (subpagePresentation !== undefined) {
      this.detailStack.push(this.buildEmbeddedSubpageEntry(subpagePresentation));
    }
    this.publishReveal(target.revealTargetId);
    this.publish();
    return new SettingsNavigationDispatchResult(true, true, '', target.title);
  }

  private pushWebAppDetail(shortcutId: string): SettingsNavigationDispatchResult {
    if (!this.isWebAppsSessionActive() || shortcutId.length <= 0) {
      return new SettingsNavigationDispatchResult(true, false, 'invalid_transition');
    }
    this.detailStack.push(new SettingsNavigationPathEntry(
      'settings-web-app-detail',
      'web_apps',
      'web_app_detail',
      shortcutId
    ));
    this.publish();
    return new SettingsNavigationDispatchResult(true, true);
  }

  private pushSitePermission(
    host: string,
    origin: string,
    permissionKind: SitePermissionKind
  ): SettingsNavigationDispatchResult {
    if (!this.isWebAppDetailActive() || host.length <= 0 || origin.length <= 0) {
      return new SettingsNavigationDispatchResult(true, false, 'invalid_transition');
    }
    this.detailStack.push(new SettingsNavigationPathEntry(
      'settings-web-app-site-permission',
      'web_apps',
      'site_permission',
      this.resolveActiveEntry().shortcutId,
      host,
      origin,
      permissionKind
    ));
    this.publish();
    return new SettingsNavigationDispatchResult(true, true);
  }

  private pushDesktopSite(host: string, origin: string): SettingsNavigationDispatchResult {
    if (!this.isWebAppDetailActive() || host.length <= 0 || origin.length <= 0) {
      return new SettingsNavigationDispatchResult(true, false, 'invalid_transition');
    }
    this.detailStack.push(new SettingsNavigationPathEntry(
      'settings-web-app-desktop-site',
      'web_apps',
      'desktop_site',
      this.resolveActiveEntry().shortcutId,
      host,
      origin
    ));
    this.publish();
    return new SettingsNavigationDispatchResult(true, true);
  }

  private pushEmbeddedSubpage(subpageId: string): SettingsNavigationDispatchResult {
    if (this.shellMode === 'compact' || subpageId.length <= 0) {
      return new SettingsNavigationDispatchResult(true, false, 'invalid_transition');
    }
    const presentation = this.catalog.findSubpagePresentation(subpageId);
    if (presentation === undefined || presentation.primaryDestination !== this.selectedPrimaryDestination) {
      return new SettingsNavigationDispatchResult(true, false, 'invalid_transition');
    }
    this.detailStack.push(this.buildEmbeddedSubpageEntry(presentation));
    this.publish();
    return new SettingsNavigationDispatchResult(true, true);
  }

  private async applyBack(): Promise<SettingsNavigationDispatchResult> {
    if (this.detailStack.length > 1) {
      this.detailStack.pop();
      this.publish();
      return new SettingsNavigationDispatchResult(true, true);
    }
    return this.applyExit();
  }

  private async applyExit(): Promise<SettingsNavigationDispatchResult> {
    let didExit = false;
    try {
      didExit = await this.router.exitSettings();
    } catch (_error) {
      return new SettingsNavigationDispatchResult(true, false, 'router_failed');
    }
    if (!didExit) {
      return new SettingsNavigationDispatchResult(true, false, 'router_failed');
    }
    return new SettingsNavigationDispatchResult(true, false);
  }

  private isWebAppsSessionActive(): boolean {
    return this.selectedPrimaryDestination === 'web_apps' && this.detailStack.length > 0;
  }

  private resolvePrimaryTarget(destination: SettingsCenterDestination): SettingsDestinationCatalogTarget | undefined {
    const target = this.catalog.findTarget(destination);
    if (target === undefined || target.kind !== 'root' || target.destination !== destination ||
      target.availabilityDestination !== destination) {
      return undefined;
    }
    return target;
  }

  private canOwnPrimarySession(state: SettingsCenterState, destination: SettingsCenterDestination): boolean {
    const target = this.resolvePrimaryTarget(destination);
    if (target === undefined || !this.catalog.isTargetPresentable(target, this.shellMode) ||
      (this.shellMode !== 'compact' && this.catalog.requiresRoutedPresentation(target, this.shellMode))) {
      return false;
    }
    const row = this.findPrimaryRow(state, target.availabilityDestination);
    return row !== undefined && row.isEnabled;
  }

  private findPrimaryRow(
    state: SettingsCenterState,
    destination: SettingsCenterDestination
  ): SettingsCenterRowState | undefined {
    for (let groupIndex = 0; groupIndex < state.groups.length; groupIndex += 1) {
      const rows = state.groups[groupIndex].rows;
      for (let rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
        if (rows[rowIndex].id === destination) {
          return rows[rowIndex];
        }
      }
    }
    return undefined;
  }

  private resolveUnavailableReason(row: SettingsCenterRowState): string {
    const value = row.value.trim();
    return value.length > 0 ? value : '当前不可用';
  }

  private isWebAppDetailActive(): boolean {
    return this.isWebAppsSessionActive() && this.resolveActiveEntry().detailKind === 'web_app_detail';
  }

  private resolveActiveEntry(): SettingsNavigationPathEntry {
    return this.detailStack[this.detailStack.length - 1];
  }

  private buildPrimaryEntry(destination: SettingsCenterDestination): SettingsNavigationPathEntry {
    if (destination === 'web_apps') {
      return new SettingsNavigationPathEntry('settings-web-apps-root', 'web_apps', 'web_apps_root');
    }
    return new SettingsNavigationPathEntry(`settings-primary-${destination}`, destination, 'primary');
  }

  private buildEmbeddedSubpageEntry(
    presentation: SettingsDestinationSubpagePresentation
  ): SettingsNavigationPathEntry {
    return new SettingsNavigationPathEntry(
      `settings-embedded-subpage-${presentation.subpageId}`,
      presentation.contentDestination,
      'embedded_subpage',
      '',
      '',
      '',
      'camera',
      presentation.subpageId
    );
  }

  private resolveActivePresentation(entry: SettingsNavigationPathEntry): SettingsNavigationActivePresentation {
    if (entry.detailKind === 'embedded_subpage') {
      const subpage = this.catalog.findSubpagePresentation(entry.subpageId);
      if (subpage !== undefined) {
        return new SettingsNavigationActivePresentation(
          subpage.contentDestination,
          subpage.title,
          subpage.panelKind
        );
      }
    }
    if (entry.detailKind === 'web_app_detail') {
      return new SettingsNavigationActivePresentation('web_apps', '网页应用详情');
    }
    if (entry.detailKind === 'site_permission') {
      return new SettingsNavigationActivePresentation('web_apps', '站点权限');
    }
    if (entry.detailKind === 'desktop_site') {
      return new SettingsNavigationActivePresentation('web_apps', '网站版本');
    }
    const target = this.catalog.findTarget(entry.destination);
    return new SettingsNavigationActivePresentation(
      entry.destination,
      target?.title ?? '设置'
    );
  }

  private clearReveal(): void {
    if (this.revealTargetId.length === 0) {
      return;
    }
    this.revealTargetId = '';
    this.revealRevision += 1;
  }

  private publishReveal(targetId: string): void {
    this.revealTargetId = targetId;
    this.revealRevision += 1;
  }

  private buildPublishedPathEntries(): SettingsNavigationPathEntry[] {
    if (this.shellMode === 'compact') {
      return [];
    }
    return this.detailStack.map((entry: SettingsNavigationPathEntry) => entry.copy());
  }

  private publish(): void {
    const nextSnapshot = this.snapshot();
    for (let index = 0; index < this.observers.length; index += 1) {
      const listener = this.observers[index].listener;
      if (listener !== undefined) {
        listener(nextSnapshot);
      }
    }
  }
}
