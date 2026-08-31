import {
  BrowserRootBottomPanelChromePlan,
  BrowserRootBottomPanelSessionCoordinator,
  BrowserRootBottomPanelTransientSheetFacts
} from './BrowserRootBottomPanelSessionCoordinator';
import { BrowserSystemSheetType } from './BrowserShellRuntimeContracts';

export type BrowserTransientSurfaceId =
  'app_proxy_quick' |
  'translation_target_language' |
  'reader_speech_player' |
  'bookmark_folder_selection' |
  'web_page_tools' |
  'element_inspection' |
  'userscript_page_actions' |
  'resource_candidates' |
  'wifi_qr_result' |
  'feature_gate';

export type BrowserTransientSurfacePhase = 'opening' | 'visible' | 'closing';
export type BrowserTransientSurfaceBackDisposition = 'none' | 'dismiss' | 'delegate_feature';
export type BrowserCustomBottomSurfaceUpdateReason = 'present' | 'reveal' | 'dismiss' | 'dismissed' | 'reset';
export type BrowserSystemSheetUpdateReason = 'system_open' | 'system_close' | 'system_disappear' | 'system_reset';

export type BrowserSystemSheetLifecycleEffect =
  'none' |
  'clear_release_notice' |
  'clear_desktop_login' |
  'reset_home_shortcut_selection';

export interface BrowserTransientSurfacePresentationRequest {
  id: BrowserTransientSurfaceId;
  revealDelayMs: number;
  dismissDurationMs: number;
  systemSheetType?: BrowserSystemSheetType;
  shouldReveal?: () => boolean;
}

export interface BrowserTransientSurfaceToken {
  id: BrowserTransientSurfaceId;
  generation: number;
}

export interface BrowserTransientSurfacePresentationSnapshot {
  id: BrowserTransientSurfaceId;
  phase: BrowserTransientSurfacePhase;
  generation: number;
  mounted: boolean;
  visible: boolean;
  blocksAutomaticPrompts: boolean;
  blocksVideoTakeover: boolean;
  backDisposition: BrowserTransientSurfaceBackDisposition;
  presentationPriority: number;
  presentationOrder: number;
  active: boolean;
}

export interface BrowserSystemSheetSnapshot {
  visible: boolean;
  type: BrowserSystemSheetType;
}

export interface BrowserCustomBottomBackTarget {
  lane: 'custom_bottom';
  surfaceId: BrowserTransientSurfaceId;
  disposition: BrowserTransientSurfaceBackDisposition;
}

export interface BrowserSystemSheetBackTarget {
  lane: 'system_sheet';
  type: BrowserSystemSheetType;
  disposition: 'dismiss' | 'delegate_feature';
}

export type BrowserTransientSurfaceBackTarget = BrowserCustomBottomBackTarget | BrowserSystemSheetBackTarget;

export interface BrowserTransientPromptBlockingFacts {
  tabsSheetVisible: boolean;
  readerModeVisible: boolean;
  releaseNoticeVisible: boolean;
  hlsTakeoverVisible: boolean;
  topFloatingPromptVisible: boolean;
  webContextMenuVisible: boolean;
  pendingJavaScriptPrompt: boolean;
  pendingSitePermissionPrompt: boolean;
  manualElementHideSelectionActive: boolean;
  privateModeLockVisible: boolean;
  downloadPromptVisible: boolean;
}

export interface BrowserTransientSurfaceSnapshot {
  surfaces: BrowserTransientSurfacePresentationSnapshot[];
  customBottomOccupied: boolean;
  blocksAutomaticPrompts: boolean;
  blocksVideoTakeover: boolean;
  systemSheet: BrowserSystemSheetSnapshot;
  activeCustomBottomSurfaceId?: BrowserTransientSurfaceId;
  activeCustomBottomSurfaceVisible: boolean;
  backTarget?: BrowserTransientSurfaceBackTarget;
}

export interface BrowserCustomBottomSurfaceUpdate {
  lane: 'custom_bottom';
  surfaceId: BrowserTransientSurfaceId;
  reason: BrowserCustomBottomSurfaceUpdateReason;
  snapshot: BrowserTransientSurfaceSnapshot;
  chromePlan?: BrowserRootBottomPanelChromePlan;
}

export interface BrowserSystemSheetUpdate {
  lane: 'system_sheet';
  reason: BrowserSystemSheetUpdateReason;
  snapshot: BrowserTransientSurfaceSnapshot;
}

export type BrowserTransientSurfaceUpdate = BrowserCustomBottomSurfaceUpdate | BrowserSystemSheetUpdate;

interface BrowserTransientSurfaceEntry {
  request: BrowserTransientSurfacePresentationRequest;
  phase: BrowserTransientSurfacePhase;
  generation: number;
  presentationOrder: number;
  revealTimer: number;
  dismissTimer: number;
}

interface BrowserTransientSurfaceGenerationCounter {
  id: BrowserTransientSurfaceId;
  generation: number;
}

interface BrowserPendingSystemHostedPresentation {
  request: BrowserTransientSurfacePresentationRequest;
  generation: number;
}

const BROWSER_TRANSIENT_SURFACE_MOUNT_FRAME_DELAY_MS: number = 16;

export class BrowserTransientSurfaceCoordinator {
  private readonly bottomPanelSessionCoordinator: BrowserRootBottomPanelSessionCoordinator;
  private readonly resolveBottomPanelFacts: () => BrowserRootBottomPanelTransientSheetFacts;
  private readonly applyUpdate: (update: BrowserTransientSurfaceUpdate) => void;
  private entries: BrowserTransientSurfaceEntry[] = [];
  private generationCounters: BrowserTransientSurfaceGenerationCounter[] = [];
  private presentationOrder: number = 0;
  private systemSheetVisible: boolean = false;
  private systemSheetType: BrowserSystemSheetType = 'none';
  private systemSheetClosingType: BrowserSystemSheetType = 'none';
  private systemSheetDisappearEffectSuppressed: boolean = false;
  private pendingSystemSheetType: BrowserSystemSheetType = 'none';
  private pendingSystemHostedPresentation: BrowserPendingSystemHostedPresentation | undefined = undefined;
  private pendingSystemHostActivationTimer: number = -1;

  constructor(
    bottomPanelSessionCoordinator: BrowserRootBottomPanelSessionCoordinator,
    resolveBottomPanelFacts: () => BrowserRootBottomPanelTransientSheetFacts,
    applyUpdate: (update: BrowserTransientSurfaceUpdate) => void
  ) {
    this.bottomPanelSessionCoordinator = bottomPanelSessionCoordinator;
    this.resolveBottomPanelFacts = resolveBottomPanelFacts;
    this.applyUpdate = applyUpdate;
  }

  snapshot(): BrowserTransientSurfaceSnapshot {
    return this.buildSnapshot();
  }

  isMounted(id: BrowserTransientSurfaceId): boolean {
    return this.findEntry(id) !== undefined;
  }

  isVisible(id: BrowserTransientSurfaceId): boolean {
    return this.findEntry(id)?.phase === 'visible';
  }

  isReleaseNoticeBlocked(facts: BrowserTransientPromptBlockingFacts): boolean {
    return this.hasManagedAutomaticPromptBlocker() || this.isExternalPromptBlockerVisible(facts);
  }

  isAppReviewPromptBlocked(facts: BrowserTransientPromptBlockingFacts): boolean {
    return this.hasManagedAutomaticPromptBlocker() ||
      this.isExternalPromptBlockerVisible(facts) ||
      facts.releaseNoticeVisible;
  }

  isGestureOnboardingPromptBlocked(facts: BrowserTransientPromptBlockingFacts): boolean {
    return this.hasManagedAutomaticPromptBlocker() ||
      this.isExternalPromptBlockerVisible(facts) ||
      facts.releaseNoticeVisible;
  }

  isVideoTakeoverBlocked(facts: BrowserTransientPromptBlockingFacts): boolean {
    return this.buildSnapshot().blocksVideoTakeover || facts.hlsTakeoverVisible || facts.downloadPromptVisible;
  }

  openSystemSheet(type: BrowserSystemSheetType): void {
    if (type === 'none') {
      this.closeSystemSheet();
      return;
    }
    if (this.resolveCustomBottomSurfaceForSystemSheet(type) !== undefined) {
      return;
    }
    if (this.systemSheetClosingType !== 'none') {
      this.pendingSystemSheetType = type;
      return;
    }
    const activeSystemHostedSurfaceId = this.resolveCustomBottomSurfaceForSystemSheet(this.systemSheetType);
    if (activeSystemHostedSurfaceId !== undefined) {
      this.pendingSystemSheetType = type;
      this.dismiss(activeSystemHostedSurfaceId);
      return;
    }
    if (type === 'releaseNotice' && (this.entries.length > 0 || this.systemSheetVisible)) {
      this.pendingSystemSheetType = type;
      return;
    }
    if (type !== 'releaseNotice' && this.systemSheetVisible && this.systemSheetType === 'releaseNotice') {
      this.pendingSystemSheetType = 'releaseNotice';
    }
    this.systemSheetDisappearEffectSuppressed = false;
    this.systemSheetVisible = true;
    this.systemSheetType = type;
    this.publishSystemSheetUpdate('system_open');
  }

  closeSystemSheet(): void {
    const activeSystemHostedSurfaceId = this.resolveCustomBottomSurfaceForSystemSheet(this.systemSheetType);
    if (activeSystemHostedSurfaceId !== undefined) {
      this.dismiss(activeSystemHostedSurfaceId);
      return;
    }
    if (this.systemSheetType === 'releaseNotice' || this.systemSheetType === 'none') {
      this.pendingSystemSheetType = 'none';
    }
    if (this.systemSheetType === 'none') {
      return;
    }
    this.systemSheetClosingType = this.systemSheetType;
    this.systemSheetDisappearEffectSuppressed = false;
    this.systemSheetVisible = false;
    this.publishSystemSheetUpdate('system_close');
  }

  shouldShowSystemSheetClose(): boolean {
    return this.systemSheetType !== 'releaseNotice' &&
      this.systemSheetType !== 'userScriptInstall' &&
      this.resolveCustomBottomSurfaceForSystemSheet(this.systemSheetType) === undefined;
  }

  handleSystemSheetWillDisappear(): void {
    if (this.systemSheetClosingType === 'none') {
      this.systemSheetClosingType = this.systemSheetType;
    }
  }

  handleSystemSheetDisappear(desktopLoginConfirming: boolean): BrowserSystemSheetLifecycleEffect {
    const disappearingType = this.systemSheetClosingType !== 'none' ?
      this.systemSheetClosingType : this.systemSheetType;
    const suppressDisappearEffect = this.systemSheetDisappearEffectSuppressed;
    const systemHostedSurfaceId = this.resolveCustomBottomSurfaceForSystemSheet(disappearingType);
    if (systemHostedSurfaceId !== undefined) {
      this.systemSheetVisible = false;
      this.systemSheetType = 'none';
      this.systemSheetClosingType = 'none';
      this.systemSheetDisappearEffectSuppressed = false;
      const entry = this.findEntry(systemHostedSurfaceId);
      if (entry !== undefined) {
        this.cancelEntryTimers(entry);
        this.removeEntry(systemHostedSurfaceId);
        const chromePlan = this.bottomPanelSessionCoordinator.endTransientSheetPresentation(
          systemHostedSurfaceId,
          this.resolveBottomPanelFacts()
        );
        this.publishUpdate(systemHostedSurfaceId, 'dismissed', chromePlan);
      }
      this.schedulePendingSystemHostActivation();
      return 'none';
    }
    let effect: BrowserSystemSheetLifecycleEffect = 'none';
    if (!suppressDisappearEffect && disappearingType === 'releaseNotice') {
      effect = 'clear_release_notice';
    } else if (!suppressDisappearEffect && disappearingType === 'desktopLoginConfirm' && !desktopLoginConfirming) {
      effect = 'clear_desktop_login';
    } else if (!suppressDisappearEffect && disappearingType === 'homeShortcutSelection') {
      effect = 'reset_home_shortcut_selection';
    }
    this.systemSheetVisible = false;
    this.systemSheetType = 'none';
    this.systemSheetClosingType = 'none';
    this.systemSheetDisappearEffectSuppressed = false;
    this.publishSystemSheetUpdate('system_disappear');
    this.schedulePendingSystemHostActivation();
    return effect;
  }

  resetSystemSheet(): BrowserSystemSheetLifecycleEffect {
    this.cancelPendingSystemHostActivation();
    const systemHostedSurfaceId = this.resolveCustomBottomSurfaceForSystemSheet(this.systemSheetType);
    if (systemHostedSurfaceId !== undefined) {
      this.pendingSystemSheetType = 'none';
      this.pendingSystemHostedPresentation = undefined;
      this.systemSheetDisappearEffectSuppressed = true;
      if (this.findEntry(systemHostedSurfaceId) !== undefined) {
        this.reset(systemHostedSurfaceId);
      } else {
        this.systemSheetClosingType = this.systemSheetType;
        this.systemSheetVisible = false;
        this.publishSystemSheetUpdate('system_reset');
      }
      return 'none';
    }
    let effect: BrowserSystemSheetLifecycleEffect = 'none';
    if (this.systemSheetType === 'homeShortcutSelection') {
      effect = 'reset_home_shortcut_selection';
    }
    const hasMountedSystemSheet = this.systemSheetType !== 'none';
    this.systemSheetVisible = false;
    this.systemSheetClosingType = hasMountedSystemSheet ? this.systemSheetType : 'none';
    this.systemSheetDisappearEffectSuppressed = hasMountedSystemSheet;
    this.pendingSystemSheetType = 'none';
    this.pendingSystemHostedPresentation = undefined;
    this.publishSystemSheetUpdate('system_reset');
    return effect;
  }

  present(request: BrowserTransientSurfacePresentationRequest): BrowserTransientSurfaceToken {
    const systemSheetType = this.resolveSystemSheetForPresentationRequest(request);
    if (systemSheetType !== 'none' && request.shouldReveal !== undefined && !request.shouldReveal()) {
      const skippedToken: BrowserTransientSurfaceToken = {
        id: request.id,
        generation: this.nextGeneration(request.id)
      };
      this.publishUpdate(request.id, 'reset');
      this.activatePendingSystemSheetIfEligible();
      return skippedToken;
    }
    if (systemSheetType !== 'none') {
      const queuedToken = this.queueSystemHostedPresentationIfBusy(request, systemSheetType);
      if (queuedToken !== undefined) {
        return queuedToken;
      }
    }
    const generation = this.nextGeneration(request.id);
    return this.presentNow(request, systemSheetType, generation);
  }

  private presentNow(
    request: BrowserTransientSurfacePresentationRequest,
    systemSheetType: BrowserSystemSheetType,
    generation: number
  ): BrowserTransientSurfaceToken {
    const existingEntry = this.findEntry(request.id);
    let entry: BrowserTransientSurfaceEntry;
    if (existingEntry === undefined) {
      entry = {
        request: this.copyRequest(request),
        phase: 'opening',
        generation: generation,
        presentationOrder: this.nextPresentationOrder(),
        revealTimer: -1,
        dismissTimer: -1
      };
      this.entries.push(entry);
    } else {
      this.cancelEntryTimers(existingEntry);
      existingEntry.request = this.copyRequest(request);
      existingEntry.phase = 'opening';
      existingEntry.generation = generation;
      existingEntry.presentationOrder = this.nextPresentationOrder();
      entry = existingEntry;
    }
    const token: BrowserTransientSurfaceToken = {
      id: request.id,
      generation: generation
    };
    const chromePlan = this.bottomPanelSessionCoordinator.beginTransientSheetPresentation(
      request.id,
      this.resolveBottomPanelFacts()
    );
    if (systemSheetType !== 'none') {
      entry.phase = 'visible';
      this.systemSheetDisappearEffectSuppressed = false;
      this.systemSheetVisible = true;
      this.systemSheetType = systemSheetType;
      this.publishUpdate(request.id, 'present', chromePlan);
      return token;
    }
    this.publishUpdate(request.id, 'present', chromePlan);
    entry.revealTimer = setTimeout(() => {
      const currentEntry = this.findEntry(request.id);
      if (currentEntry === undefined) {
        return;
      }
      currentEntry.revealTimer = -1;
      if (!this.isCurrentPhase(token, 'opening')) {
        return;
      }
      if (request.shouldReveal !== undefined && !request.shouldReveal()) {
        this.removeEntry(request.id);
        const abandonedChromePlan = this.bottomPanelSessionCoordinator.endTransientSheetPresentation(
          request.id,
          this.resolveBottomPanelFacts()
        );
        this.publishUpdate(request.id, 'reset', abandonedChromePlan);
        this.activatePendingSystemSheetIfEligible();
        return;
      }
      currentEntry.phase = 'visible';
      this.publishUpdate(request.id, 'reveal');
    }, Math.max(BROWSER_TRANSIENT_SURFACE_MOUNT_FRAME_DELAY_MS, request.revealDelayMs));
    return token;
  }

  dismiss(id: BrowserTransientSurfaceId): void {
    if (this.pendingSystemHostedPresentation?.request.id === id) {
      this.pendingSystemHostedPresentation = undefined;
      this.nextGeneration(id);
      this.publishUpdate(id, 'reset');
      this.activatePendingSystemSheetIfEligible();
      return;
    }
    const entry = this.findEntry(id);
    if (entry === undefined) {
      return;
    }
    this.cancelEntryTimers(entry);
    const generation = this.nextGeneration(id);
    entry.generation = generation;
    entry.phase = 'closing';
    const token: BrowserTransientSurfaceToken = {
      id: id,
      generation: generation
    };
    const systemSheetType = this.resolveSystemSheetForPresentationRequest(entry.request);
    if (systemSheetType !== 'none') {
      if (this.systemSheetType === systemSheetType) {
        this.systemSheetClosingType = systemSheetType;
        this.systemSheetDisappearEffectSuppressed = false;
        this.systemSheetVisible = false;
        this.publishUpdate(id, 'dismiss');
        return;
      }
      this.removeEntry(id);
      const chromePlan = this.bottomPanelSessionCoordinator.endTransientSheetPresentation(
        id,
        this.resolveBottomPanelFacts()
      );
      this.publishUpdate(id, 'dismissed', chromePlan);
      this.activatePendingSystemSheetIfEligible();
      return;
    }
    this.publishUpdate(id, 'dismiss');
    entry.dismissTimer = setTimeout(() => {
      const currentEntry = this.findEntry(id);
      if (currentEntry === undefined) {
        return;
      }
      currentEntry.dismissTimer = -1;
      if (!this.isCurrentPhase(token, 'closing')) {
        return;
      }
      this.removeEntry(id);
      const chromePlan = this.bottomPanelSessionCoordinator.endTransientSheetPresentation(
        id,
        this.resolveBottomPanelFacts()
      );
      this.publishUpdate(id, 'dismissed', chromePlan);
      this.activatePendingSystemSheetIfEligible();
    }, Math.max(0, entry.request.dismissDurationMs));
  }

  reset(id: BrowserTransientSurfaceId): void {
    if (this.pendingSystemHostedPresentation?.request.id === id) {
      this.pendingSystemHostedPresentation = undefined;
      this.nextGeneration(id);
      this.publishUpdate(id, 'reset');
      this.activatePendingSystemSheetIfEligible();
      return;
    }
    const entry = this.findEntry(id);
    if (entry === undefined) {
      return;
    }
    this.nextGeneration(id);
    this.cancelEntryTimers(entry);
    this.removeEntry(id);
    this.beginSystemSheetHostResetForSurface(id);
    const chromePlan = this.bottomPanelSessionCoordinator.endTransientSheetPresentation(
      id,
      this.resolveBottomPanelFacts()
    );
    this.publishUpdate(id, 'reset', chromePlan);
    this.activatePendingSystemSheetIfEligible();
  }

  resetAllCustomBottomSurfaces(preservedIds: BrowserTransientSurfaceId[] = []): void {
    const surfaceIds: BrowserTransientSurfaceId[] = [];
    for (let index = 0; index < this.entries.length; index += 1) {
      surfaceIds.push(this.entries[index].request.id);
    }
    for (let index = 0; index < surfaceIds.length; index += 1) {
      const id = surfaceIds[index];
      if (preservedIds.indexOf(id) >= 0) {
        continue;
      }
      const entry = this.findEntry(id);
      if (entry === undefined) {
        continue;
      }
      this.nextGeneration(id);
      this.cancelEntryTimers(entry);
      this.removeEntry(id);
      this.beginSystemSheetHostResetForSurface(id);
      const chromePlan = this.bottomPanelSessionCoordinator.endTransientSheetPresentation(
        id,
        this.resolveBottomPanelFacts()
      );
      this.publishUpdate(id, 'reset', chromePlan);
    }
    if (this.pendingSystemHostedPresentation !== undefined &&
      preservedIds.indexOf(this.pendingSystemHostedPresentation.request.id) < 0) {
      const pendingId = this.pendingSystemHostedPresentation.request.id;
      this.pendingSystemHostedPresentation = undefined;
      this.nextGeneration(pendingId);
      this.publishUpdate(pendingId, 'reset');
    }
    this.activatePendingSystemSheetIfEligible();
  }

  currentToken(id: BrowserTransientSurfaceId): BrowserTransientSurfaceToken | undefined {
    const entry = this.findEntry(id);
    if (entry === undefined) {
      return undefined;
    }
    return {
      id: id,
      generation: entry.generation
    };
  }

  isCurrent(token: BrowserTransientSurfaceToken): boolean {
    const entry = this.findEntry(token.id);
    return entry !== undefined && entry.generation === token.generation;
  }

  private publishUpdate(
    surfaceId: BrowserTransientSurfaceId,
    reason: BrowserCustomBottomSurfaceUpdateReason,
    chromePlan?: BrowserRootBottomPanelChromePlan
  ): void {
    this.applyUpdate({
      lane: 'custom_bottom',
      surfaceId: surfaceId,
      reason: reason,
      snapshot: this.snapshot(),
      chromePlan: chromePlan
    });
  }

  private publishSystemSheetUpdate(reason: BrowserSystemSheetUpdateReason): void {
    this.applyUpdate({
      lane: 'system_sheet',
      reason: reason,
      snapshot: this.snapshot()
    });
  }

  private buildSnapshot(): BrowserTransientSurfaceSnapshot {
    const surfaces: BrowserTransientSurfacePresentationSnapshot[] = [];
    const activeCustomBottomSurfaceId = this.resolveActiveCustomBottomSurfaceId();
    let anySurfaceBlocksAutomaticPrompts = false;
    let anySurfaceBlocksVideoTakeover = false;
    for (let index = 0; index < this.entries.length; index += 1) {
      const entry = this.entries[index];
      const entryBlocksAutomaticPrompts = this.resolveBlocksAutomaticPrompts(entry.request.id);
      const entryBlocksVideoTakeover = this.resolveBlocksVideoTakeover(entry.request.id);
      surfaces.push({
        id: entry.request.id,
        phase: entry.phase,
        generation: entry.generation,
        mounted: true,
        visible: entry.phase === 'visible',
        blocksAutomaticPrompts: entryBlocksAutomaticPrompts,
        blocksVideoTakeover: entryBlocksVideoTakeover,
        backDisposition: this.resolveBackDisposition(entry.request.id),
        presentationPriority: this.resolvePresentationPriority(entry.request.id),
        presentationOrder: entry.presentationOrder,
        active: entry.request.id === activeCustomBottomSurfaceId
      });
      if (entryBlocksAutomaticPrompts) {
        anySurfaceBlocksAutomaticPrompts = true;
      }
      if (entryBlocksVideoTakeover) {
        anySurfaceBlocksVideoTakeover = true;
      }
    }
    return {
      surfaces: surfaces,
      customBottomOccupied: surfaces.length > 0,
      blocksAutomaticPrompts: anySurfaceBlocksAutomaticPrompts || this.systemSheetVisible,
      blocksVideoTakeover: anySurfaceBlocksVideoTakeover || this.systemSheetVisible,
      systemSheet: {
        visible: this.systemSheetVisible,
        type: this.systemSheetType
      },
      activeCustomBottomSurfaceId: activeCustomBottomSurfaceId,
      activeCustomBottomSurfaceVisible: activeCustomBottomSurfaceId !== undefined &&
        this.isVisible(activeCustomBottomSurfaceId),
      backTarget: this.resolveBackTarget()
    };
  }

  private copyRequest(
    request: BrowserTransientSurfacePresentationRequest
  ): BrowserTransientSurfacePresentationRequest {
    return {
      id: request.id,
      revealDelayMs: request.revealDelayMs,
      dismissDurationMs: request.dismissDurationMs,
      systemSheetType: request.systemSheetType,
      shouldReveal: request.shouldReveal
    };
  }

  private resolveBackDisposition(id: BrowserTransientSurfaceId): BrowserTransientSurfaceBackDisposition {
    if (id === 'reader_speech_player') {
      return 'none';
    }
    if (id === 'bookmark_folder_selection' || id === 'web_page_tools' || id === 'element_inspection' ||
      id === 'resource_candidates') {
      return 'delegate_feature';
    }
    return 'dismiss';
  }

  private resolveBlocksAutomaticPrompts(id: BrowserTransientSurfaceId): boolean {
    return id !== 'reader_speech_player';
  }

  private resolveBlocksVideoTakeover(id: BrowserTransientSurfaceId): boolean {
    return id === 'app_proxy_quick' ||
      id === 'resource_candidates' ||
      id === 'wifi_qr_result' ||
      id === 'userscript_page_actions' ||
      id === 'feature_gate' ||
      id === 'bookmark_folder_selection' ||
      id === 'translation_target_language' ||
      id === 'web_page_tools' ||
      id === 'element_inspection';
  }

  private hasManagedAutomaticPromptBlocker(excludedId?: BrowserTransientSurfaceId): boolean {
    if (this.systemSheetVisible) {
      return true;
    }
    for (let index = 0; index < this.entries.length; index += 1) {
      const id = this.entries[index].request.id;
      if (id !== excludedId && this.resolveBlocksAutomaticPrompts(id)) {
        return true;
      }
    }
    return false;
  }

  private isExternalPromptBlockerVisible(facts: BrowserTransientPromptBlockingFacts): boolean {
    return facts.tabsSheetVisible ||
      facts.readerModeVisible ||
      facts.hlsTakeoverVisible ||
      facts.topFloatingPromptVisible ||
      facts.webContextMenuVisible ||
      facts.pendingJavaScriptPrompt ||
      facts.pendingSitePermissionPrompt ||
      facts.manualElementHideSelectionActive ||
      facts.privateModeLockVisible ||
      facts.downloadPromptVisible;
  }

  private resolveBackTarget(): BrowserTransientSurfaceBackTarget | undefined {
    if (this.systemSheetVisible) {
      const systemHostedSurfaceId = this.resolveCustomBottomSurfaceForSystemSheet(this.systemSheetType);
      if (systemHostedSurfaceId !== undefined && this.findEntry(systemHostedSurfaceId) !== undefined) {
        return {
          lane: 'custom_bottom',
          surfaceId: systemHostedSurfaceId,
          disposition: this.resolveBackDisposition(systemHostedSurfaceId)
        };
      }
      return {
        lane: 'system_sheet',
        type: this.systemSheetType,
        disposition: this.systemSheetType === 'desktopLoginConfirm' ? 'dismiss' : 'delegate_feature'
      };
    }
    const activeCustomBottomSurfaceId = this.resolveActiveCustomBottomSurfaceId();
    if (activeCustomBottomSurfaceId === undefined) {
      return undefined;
    }
    const disposition = this.resolveBackDisposition(activeCustomBottomSurfaceId);
    if (disposition === 'none') {
      return undefined;
    }
    return {
      lane: 'custom_bottom',
      surfaceId: activeCustomBottomSurfaceId,
      disposition: disposition
    };
  }

  private resolveActiveCustomBottomSurfaceId(): BrowserTransientSurfaceId | undefined {
    if (this.systemSheetVisible &&
      this.resolveCustomBottomSurfaceForSystemSheet(this.systemSheetType) === undefined) {
      return undefined;
    }
    let activeEntry: BrowserTransientSurfaceEntry | undefined = undefined;
    let activePriority = -1;
    for (let index = 0; index < this.entries.length; index += 1) {
      const entry = this.entries[index];
      const priority = this.resolvePresentationPriority(entry.request.id);
      if (activeEntry === undefined || priority > activePriority ||
        (priority === activePriority && entry.presentationOrder > activeEntry.presentationOrder)) {
        activeEntry = entry;
        activePriority = priority;
      }
    }
    return activeEntry?.request.id;
  }

  private resolvePresentationPriority(id: BrowserTransientSurfaceId): number {
    if (id === 'feature_gate' || id === 'wifi_qr_result') {
      return 400;
    }
    return 300;
  }

  private resolveSystemSheetForCustomBottomSurface(id: BrowserTransientSurfaceId): BrowserSystemSheetType {
    if (id === 'userscript_page_actions') {
      return 'userScriptPageActions';
    }
    if (id === 'app_proxy_quick') {
      return 'appProxyQuick';
    }
    if (id === 'resource_candidates') {
      return 'resourceCandidates';
    }
    return 'none';
  }

  private resolveSystemSheetForPresentationRequest(
    request: BrowserTransientSurfacePresentationRequest
  ): BrowserSystemSheetType {
    if (request.systemSheetType !== undefined) {
      return request.systemSheetType;
    }
    return this.resolveSystemSheetForCustomBottomSurface(request.id);
  }

  private resolveCustomBottomSurfaceForSystemSheet(
    type: BrowserSystemSheetType
  ): BrowserTransientSurfaceId | undefined {
    if (type === 'userScriptPageActions') {
      return 'userscript_page_actions';
    }
    if (type === 'appProxyQuick') {
      return 'app_proxy_quick';
    }
    if (type === 'resourceCandidates') {
      return 'resource_candidates';
    }
    if (type === 'webPageTools') {
      return 'web_page_tools';
    }
    return undefined;
  }

  private queueSystemHostedPresentationIfBusy(
    request: BrowserTransientSurfacePresentationRequest,
    systemSheetType: BrowserSystemSheetType
  ): BrowserTransientSurfaceToken | undefined {
    const replacingVisibleSheet = this.systemSheetVisible && this.systemSheetType !== systemSheetType;
    if (this.systemSheetClosingType === 'none' && !replacingVisibleSheet) {
      return undefined;
    }
    const displacedPendingId = this.pendingSystemHostedPresentation?.request.id;
    const generation = this.nextGeneration(request.id);
    this.pendingSystemHostedPresentation = {
      request: this.copyRequest(request),
      generation: generation
    };
    if (displacedPendingId !== undefined && displacedPendingId !== request.id) {
      this.nextGeneration(displacedPendingId);
      this.publishUpdate(displacedPendingId, 'reset');
    }
    const token: BrowserTransientSurfaceToken = {
      id: request.id,
      generation: generation
    };
    if (replacingVisibleSheet) {
      this.closeCurrentSystemSheetForHostedReplacement();
    }
    return token;
  }

  private closeCurrentSystemSheetForHostedReplacement(): void {
    const visibleSystemHostedSurfaceId = this.resolveCustomBottomSurfaceForSystemSheet(this.systemSheetType);
    if (visibleSystemHostedSurfaceId !== undefined) {
      this.dismiss(visibleSystemHostedSurfaceId);
      return;
    }
    this.closeSystemSheet();
  }

  private beginSystemSheetHostResetForSurface(id: BrowserTransientSurfaceId): void {
    if (this.resolveCustomBottomSurfaceForSystemSheet(this.systemSheetType) !== id) {
      return;
    }
    this.systemSheetClosingType = this.systemSheetType;
    this.systemSheetDisappearEffectSuppressed = true;
    this.systemSheetVisible = false;
  }

  private findEntry(id: BrowserTransientSurfaceId): BrowserTransientSurfaceEntry | undefined {
    for (let index = 0; index < this.entries.length; index += 1) {
      if (this.entries[index].request.id === id) {
        return this.entries[index];
      }
    }
    return undefined;
  }

  private nextGeneration(id: BrowserTransientSurfaceId): number {
    for (let index = 0; index < this.generationCounters.length; index += 1) {
      if (this.generationCounters[index].id === id) {
        this.generationCounters[index].generation += 1;
        return this.generationCounters[index].generation;
      }
    }
    this.generationCounters.push({
      id: id,
      generation: 1
    });
    return 1;
  }

  private nextPresentationOrder(): number {
    this.presentationOrder += 1;
    return this.presentationOrder;
  }

  private activatePendingSystemHostedRequestIfEligible(): void {
    if (this.pendingSystemHostedPresentation === undefined ||
      this.systemSheetVisible || this.systemSheetClosingType !== 'none') {
      return;
    }
    const pending = this.pendingSystemHostedPresentation;
    this.pendingSystemHostedPresentation = undefined;
    if (pending.request.shouldReveal !== undefined && !pending.request.shouldReveal()) {
      this.publishUpdate(pending.request.id, 'reset');
      this.activatePendingSystemSheetIfEligible();
      return;
    }
    this.presentNow(
      pending.request,
      this.resolveSystemSheetForPresentationRequest(pending.request),
      pending.generation
    );
  }

  private schedulePendingSystemHostActivation(): void {
    if ((this.pendingSystemHostedPresentation === undefined && this.pendingSystemSheetType === 'none') ||
      this.pendingSystemHostActivationTimer >= 0) {
      return;
    }
    this.pendingSystemHostActivationTimer = setTimeout(() => {
      this.pendingSystemHostActivationTimer = -1;
      this.activatePendingSystemHostedRequestIfEligible();
      this.activatePendingSystemSheetIfEligible();
    }, 0);
  }

  private cancelPendingSystemHostActivation(): void {
    if (this.pendingSystemHostActivationTimer < 0) {
      return;
    }
    clearTimeout(this.pendingSystemHostActivationTimer);
    this.pendingSystemHostActivationTimer = -1;
  }

  private activatePendingSystemSheetIfEligible(): void {
    if (this.pendingSystemSheetType === 'none' || this.systemSheetVisible ||
      this.systemSheetClosingType !== 'none' || this.entries.length > 0) {
      return;
    }
    const type = this.pendingSystemSheetType;
    this.pendingSystemSheetType = 'none';
    this.systemSheetVisible = true;
    this.systemSheetType = type;
    this.publishSystemSheetUpdate('system_open');
  }

  private removeEntry(id: BrowserTransientSurfaceId): void {
    for (let index = 0; index < this.entries.length; index += 1) {
      if (this.entries[index].request.id === id) {
        this.entries.splice(index, 1);
        return;
      }
    }
  }

  private isCurrentPhase(
    token: BrowserTransientSurfaceToken,
    phase: BrowserTransientSurfacePhase
  ): boolean {
    const entry = this.findEntry(token.id);
    return entry !== undefined && entry.generation === token.generation && entry.phase === phase;
  }

  private cancelEntryTimers(entry: BrowserTransientSurfaceEntry): void {
    if (entry.revealTimer >= 0) {
      clearTimeout(entry.revealTimer);
      entry.revealTimer = -1;
    }
    if (entry.dismissTimer >= 0) {
      clearTimeout(entry.dismissTimer);
      entry.dismissTimer = -1;
    }
  }
}
