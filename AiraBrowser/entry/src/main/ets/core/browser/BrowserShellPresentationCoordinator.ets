import { BrowserWindowPresentationProfile } from './BrowserWindowPresentationProfile';
import {
  BrowserShellAdapterCatalogSnapshot,
  BrowserShellAdapterDescriptor,
  BrowserShellAdapterKind
} from './BrowserShellAdapterCatalog';
import {
  BrowserLargeScreenPresentationFacts,
  BrowserLargeScreenPresentationSnapshot,
  BrowserLargeScreenPresentationViewModel
} from './BrowserLargeScreenPresentationViewModel';
import { BrowserLargeScreenTabProjection } from './BrowserLargeScreenTabStripViewModel';
import { BrowserLargeScreenTopChromeActionPresentation } from './BrowserLargeScreenTopChromeActionViewModel';
import { BrowserLargeScreenWindowFactsSnapshot } from './BrowserLargeScreenWindowFactsViewModel';
import { BrowserTabState } from '../tabs/TabManager';

export type BrowserShellPresentationMode = 'browser' | 'web_app';
export type BrowserShellPresentationSurface = 'phone' | 'large_screen' | 'web_app' | 'unavailable';

export interface BrowserShellPresentationSnapshot {
  mode: BrowserShellPresentationMode;
  surface: BrowserShellPresentationSurface;
  shellFamily: 'phone' | 'large_screen';
  adapterKind: BrowserShellAdapterKind;
  adapterReady: boolean;
  adapterGeneration: number;
  catalogRevision: number;
  profileRevision: number;
  largeScreenWindowFacts?: BrowserLargeScreenWindowFactsSnapshot;
  largeScreenPresentation?: BrowserLargeScreenPresentationSnapshot;
}

export interface BrowserShellPresentationReconcileResult {
  snapshot?: BrowserShellPresentationSnapshot;
  changed: boolean;
}

/**
 * Owns the stable-host adapter connection. It selects an already-registered
 * adapter from Session facts; it never reads device/window state or creates UI.
 */
export class BrowserShellPresentationCoordinator {
  private catalog?: BrowserShellAdapterCatalogSnapshot;
  private current?: BrowserShellPresentationSnapshot;
  private connected: boolean = false;
  private webAppPresentationActive: boolean = false;
  private largeScreenTabs: BrowserTabState[] = [];
  private largeScreenActiveTabId: string = '';
  private readonly largeScreenPresentationViewModel: BrowserLargeScreenPresentationViewModel =
    new BrowserLargeScreenPresentationViewModel();

  connect(catalog: BrowserShellAdapterCatalogSnapshot): void {
    if (this.connected && this.catalog !== undefined && catalog.revision <= this.catalog.revision) {
      return;
    }
    this.catalog = this.catalog === undefined
      ? this.copyCatalog(catalog)
      : this.mergeCatalog(this.catalog, catalog);
    this.connected = true;
    // Keep the last complete surface while the next profile reconciliation is
    // pending. Clearing it would let a stable host interpret "no snapshot"
    // as Phone and create a silent cross-family fallback during a refresh.
  }

  reconcile(profile: BrowserWindowPresentationProfile): BrowserShellPresentationReconcileResult {
    if (!this.connected || this.catalog === undefined) {
      return { snapshot: undefined, changed: false };
    }
    if (this.current !== undefined && profile.revision < this.current.profileRevision) {
      return { snapshot: this.copySnapshot(this.current), changed: false };
    }

    const mode: BrowserShellPresentationMode = this.webAppPresentationActive ? 'web_app' : 'browser';
    const requestedDescriptor = this.resolveRequestedDescriptor(profile.shellFamily, mode);
    const surface = this.resolveSurface(profile.shellFamily, requestedDescriptor, mode);
    const previousLargeScreenPresentation = profile.shellFamily === 'large_screen' &&
      this.current !== undefined && this.current.shellFamily === 'large_screen'
      ? this.current.largeScreenPresentation
      : undefined;
    const previousLargeScreenWindowFacts = this.current?.largeScreenWindowFacts;
    const largeScreenPresentation = this.resolveLargeScreenPresentationForSurface(
      surface,
      this.current?.surface,
      previousLargeScreenPresentation,
      previousLargeScreenWindowFacts
    );
    const snapshot: BrowserShellPresentationSnapshot = {
      mode: mode,
      surface: surface,
      shellFamily: profile.shellFamily,
      adapterKind: requestedDescriptor.kind,
      adapterReady: requestedDescriptor.ready,
      adapterGeneration: requestedDescriptor.generation,
      catalogRevision: this.catalog.revision,
      profileRevision: profile.revision,
      largeScreenWindowFacts: previousLargeScreenWindowFacts === undefined
        ? undefined
        : this.copyLargeScreenWindowFacts(previousLargeScreenWindowFacts),
      largeScreenPresentation: largeScreenPresentation
    };
    const changed = this.current === undefined || this.hasShellSelectionChanged(this.current, snapshot);
    this.current = snapshot;
    return { snapshot: this.copySnapshot(snapshot), changed: changed };
  }

  reconcileWebAppPresentation(active: boolean): BrowserShellPresentationReconcileResult {
    if (this.webAppPresentationActive === active) {
      return { snapshot: this.snapshot(), changed: false };
    }
    this.webAppPresentationActive = active;
    if (!this.connected || this.catalog === undefined || this.current === undefined) {
      return { snapshot: this.snapshot(), changed: false };
    }

    const mode: BrowserShellPresentationMode = active ? 'web_app' : 'browser';
    const requestedDescriptor = this.resolveRequestedDescriptor(this.current.shellFamily, mode);
    const surface = this.resolveSurface(this.current.shellFamily, requestedDescriptor, mode);
    const largeScreenPresentation = this.resolveLargeScreenPresentationForSurface(
      surface,
      this.current.surface,
      this.current.largeScreenPresentation,
      this.current.largeScreenWindowFacts
    );
    const snapshot: BrowserShellPresentationSnapshot = {
      mode: mode,
      surface: surface,
      shellFamily: this.current.shellFamily,
      adapterKind: requestedDescriptor.kind,
      adapterReady: requestedDescriptor.ready,
      adapterGeneration: requestedDescriptor.generation,
      catalogRevision: this.catalog.revision,
      profileRevision: this.current.profileRevision,
      largeScreenWindowFacts: this.current.largeScreenWindowFacts === undefined
        ? undefined
        : this.copyLargeScreenWindowFacts(this.current.largeScreenWindowFacts),
      largeScreenPresentation: largeScreenPresentation
    };
    const changed = this.hasShellSelectionChanged(this.current, snapshot);
    this.current = snapshot;
    return { snapshot: this.copySnapshot(snapshot), changed: changed };
  }

  reconcileLargeScreenPresentation(
    facts: BrowserLargeScreenPresentationFacts
  ): BrowserShellPresentationSnapshot | undefined {
    if (!this.connected || this.current === undefined || this.current.surface !== 'large_screen' ||
      this.current.shellFamily !== 'large_screen') {
      return this.snapshot();
    }
    const nextLargeScreenPresentation = this.largeScreenPresentationViewModel.resolvePresentation(facts);
    this.current = {
      mode: this.current.mode,
      surface: this.current.surface,
      shellFamily: this.current.shellFamily,
      adapterKind: this.current.adapterKind,
      adapterReady: this.current.adapterReady,
      adapterGeneration: this.current.adapterGeneration,
      catalogRevision: this.current.catalogRevision,
      profileRevision: this.current.profileRevision,
      largeScreenWindowFacts: this.current.largeScreenWindowFacts === undefined
        ? undefined
        : this.copyLargeScreenWindowFacts(this.current.largeScreenWindowFacts),
      largeScreenPresentation: nextLargeScreenPresentation
    };
    return this.copySnapshot(this.current);
  }

  reconcileLargeScreenWindowFacts(
    facts: BrowserLargeScreenWindowFactsSnapshot
  ): BrowserShellPresentationReconcileResult {
    if (!this.connected || this.current === undefined) {
      return { snapshot: this.snapshot(), changed: false };
    }
    if (this.current.largeScreenWindowFacts !== undefined &&
      this.areLargeScreenWindowFactsEqual(this.current.largeScreenWindowFacts, facts)) {
      return { snapshot: this.copySnapshot(this.current), changed: false };
    }
    const largeScreenPresentation = this.current.surface === 'large_screen' &&
      this.current.shellFamily === 'large_screen'
      ? this.largeScreenPresentationViewModel.resolvePresentationForTabs(
        facts,
        this.largeScreenTabs,
        this.largeScreenActiveTabId
      )
      : this.current.largeScreenPresentation;
    this.current = {
      mode: this.current.mode,
      surface: this.current.surface,
      shellFamily: this.current.shellFamily,
      adapterKind: this.current.adapterKind,
      adapterReady: this.current.adapterReady,
      adapterGeneration: this.current.adapterGeneration,
      catalogRevision: this.current.catalogRevision,
      profileRevision: this.current.profileRevision,
      largeScreenWindowFacts: this.copyLargeScreenWindowFacts(facts),
      largeScreenPresentation: largeScreenPresentation
    };
    return { snapshot: this.copySnapshot(this.current), changed: true };
  }

  reconcileLargeScreenTabs(
    tabs: BrowserTabState[],
    activeTabId: string
  ): BrowserShellPresentationSnapshot | undefined {
    this.largeScreenTabs = tabs.slice();
    this.largeScreenActiveTabId = activeTabId.trim();
    if (!this.connected || this.current === undefined || this.current.surface !== 'large_screen' ||
      this.current.shellFamily !== 'large_screen' || this.current.largeScreenWindowFacts === undefined) {
      return this.snapshot();
    }
    const largeScreenPresentation = this.largeScreenPresentationViewModel.resolvePresentationForTabs(
      this.current.largeScreenWindowFacts,
      this.largeScreenTabs,
      this.largeScreenActiveTabId
    );
    this.current = {
      mode: this.current.mode,
      surface: this.current.surface,
      shellFamily: this.current.shellFamily,
      adapterKind: this.current.adapterKind,
      adapterReady: this.current.adapterReady,
      adapterGeneration: this.current.adapterGeneration,
      catalogRevision: this.current.catalogRevision,
      profileRevision: this.current.profileRevision,
      largeScreenWindowFacts: this.copyLargeScreenWindowFacts(this.current.largeScreenWindowFacts),
      largeScreenPresentation: largeScreenPresentation
    };
    return this.copySnapshot(this.current);
  }

  snapshot(): BrowserShellPresentationSnapshot | undefined {
    return this.current === undefined ? undefined : this.copySnapshot(this.current);
  }

  disconnect(): void {
    this.connected = false;
    this.catalog = undefined;
    this.current = undefined;
    this.webAppPresentationActive = false;
    this.largeScreenTabs = [];
    this.largeScreenActiveTabId = '';
  }

  private copyCatalog(catalog: BrowserShellAdapterCatalogSnapshot): BrowserShellAdapterCatalogSnapshot {
    return {
      revision: catalog.revision,
      phone: this.copyDescriptor(catalog.phone),
      largeScreen: this.copyDescriptor(catalog.largeScreen),
      webApp: this.copyDescriptor(catalog.webApp)
    };
  }

  private mergeCatalog(
    previous: BrowserShellAdapterCatalogSnapshot,
    next: BrowserShellAdapterCatalogSnapshot
  ): BrowserShellAdapterCatalogSnapshot {
    return {
      revision: next.revision,
      phone: this.selectDescriptor(previous.phone, next.phone),
      largeScreen: this.selectDescriptor(previous.largeScreen, next.largeScreen),
      webApp: this.selectDescriptor(previous.webApp, next.webApp)
    };
  }

  private selectDescriptor(
    previous: BrowserShellAdapterDescriptor,
    next: BrowserShellAdapterDescriptor
  ): BrowserShellAdapterDescriptor {
    if (!Number.isFinite(next.generation) || next.generation <= previous.generation) {
      return this.copyDescriptor(previous);
    }
    return this.copyDescriptor(next);
  }

  private resolveRequestedDescriptor(
    shellFamily: 'phone' | 'large_screen',
    mode: BrowserShellPresentationMode
  ): BrowserShellAdapterDescriptor {
    if (mode === 'web_app') {
      return this.catalog?.webApp ?? {
        kind: 'web_app',
        ready: false,
        generation: 0
      };
    }
    if (shellFamily === 'large_screen') {
      return this.catalog?.largeScreen ?? {
        kind: 'large_screen',
        ready: false,
        generation: 0
      };
    }
    return this.catalog?.phone ?? {
      kind: 'phone',
      ready: false,
      generation: 0
    };
  }

  private resolveSurface(
    shellFamily: 'phone' | 'large_screen',
    descriptor: BrowserShellAdapterDescriptor,
    mode: BrowserShellPresentationMode
  ): BrowserShellPresentationSurface {
    if (!descriptor.ready) {
      return 'unavailable';
    }
    if (mode === 'web_app') {
      return 'web_app';
    }
    return shellFamily === 'large_screen' ? 'large_screen' : 'phone';
  }

  private resolveLargeScreenPresentationForSurface(
    surface: BrowserShellPresentationSurface,
    previousSurface: BrowserShellPresentationSurface | undefined,
    previousPresentation: BrowserLargeScreenPresentationSnapshot | undefined,
    windowFacts: BrowserLargeScreenWindowFactsSnapshot | undefined
  ): BrowserLargeScreenPresentationSnapshot | undefined {
    if (surface !== 'large_screen') {
      return previousPresentation;
    }
    if (windowFacts === undefined) {
      return previousSurface === 'large_screen' ? previousPresentation : undefined;
    }
    if (previousSurface === 'large_screen' && previousPresentation !== undefined) {
      return previousPresentation;
    }
    return this.largeScreenPresentationViewModel.resolvePresentationForTabs(
      windowFacts,
      this.largeScreenTabs,
      this.largeScreenActiveTabId
    );
  }

  private hasShellSelectionChanged(
    previous: BrowserShellPresentationSnapshot,
    next: BrowserShellPresentationSnapshot
  ): boolean {
    return previous.mode !== next.mode ||
      previous.surface !== next.surface ||
      previous.shellFamily !== next.shellFamily ||
      previous.adapterKind !== next.adapterKind ||
      previous.adapterReady !== next.adapterReady ||
      previous.adapterGeneration !== next.adapterGeneration;
  }

  private areLargeScreenWindowFactsEqual(
    previous: BrowserLargeScreenWindowFactsSnapshot,
    next: BrowserLargeScreenWindowFactsSnapshot
  ): boolean {
    return previous.availableWidthVp === next.availableWidthVp &&
      previous.availableHeightVp === next.availableHeightVp &&
      previous.titleButtonWidthVp === next.titleButtonWidthVp &&
      previous.titleButtonHeightVp === next.titleButtonHeightVp &&
      previous.windowTitleBarIntegrated === next.windowTitleBarIntegrated &&
      previous.safeTopInsetVp === next.safeTopInsetVp &&
      previous.safeBottomInsetVp === next.safeBottomInsetVp &&
      previous.safeLeftInsetVp === next.safeLeftInsetVp &&
      previous.safeRightInsetVp === next.safeRightInsetVp &&
      previous.windowProfile === next.windowProfile &&
      previous.inputProfile === next.inputProfile &&
      previous.dragSupported === next.dragSupported &&
      previous.keyboardHintsAvailable === next.keyboardHintsAvailable;
  }

  private copyDescriptor(descriptor: BrowserShellAdapterDescriptor): BrowserShellAdapterDescriptor {
    return {
      kind: descriptor.kind,
      ready: descriptor.ready,
      generation: descriptor.generation
    };
  }

  private copySnapshot(snapshot: BrowserShellPresentationSnapshot): BrowserShellPresentationSnapshot {
    return {
      mode: snapshot.mode,
      surface: snapshot.surface,
      shellFamily: snapshot.shellFamily,
      adapterKind: snapshot.adapterKind,
      adapterReady: snapshot.adapterReady,
      adapterGeneration: snapshot.adapterGeneration,
      catalogRevision: snapshot.catalogRevision,
      profileRevision: snapshot.profileRevision,
      largeScreenWindowFacts: snapshot.largeScreenWindowFacts === undefined
        ? undefined
        : this.copyLargeScreenWindowFacts(snapshot.largeScreenWindowFacts),
      largeScreenPresentation: snapshot.largeScreenPresentation === undefined
        ? undefined
        : this.copyLargeScreenPresentation(snapshot.largeScreenPresentation)
    };
  }

  private copyLargeScreenWindowFacts(
    facts: BrowserLargeScreenWindowFactsSnapshot
  ): BrowserLargeScreenWindowFactsSnapshot {
    return {
      availableWidthVp: facts.availableWidthVp,
      availableHeightVp: facts.availableHeightVp,
      titleButtonWidthVp: facts.titleButtonWidthVp,
      titleButtonHeightVp: facts.titleButtonHeightVp,
      windowTitleBarIntegrated: facts.windowTitleBarIntegrated,
      safeTopInsetVp: facts.safeTopInsetVp,
      safeBottomInsetVp: facts.safeBottomInsetVp,
      safeLeftInsetVp: facts.safeLeftInsetVp,
      safeRightInsetVp: facts.safeRightInsetVp,
      windowProfile: facts.windowProfile,
      inputProfile: facts.inputProfile,
      dragSupported: facts.dragSupported,
      keyboardHintsAvailable: facts.keyboardHintsAvailable
    };
  }

  private copyLargeScreenPresentation(
    presentation: BrowserLargeScreenPresentationSnapshot
  ): BrowserLargeScreenPresentationSnapshot {
    return {
      windowProfile: presentation.windowProfile,
      inputProfile: presentation.inputProfile,
      topChrome: {
        density: presentation.topChrome.density,
        hoverActionsVisible: presentation.topChrome.hoverActionsVisible,
        keyboardHintsVisible: presentation.topChrome.keyboardHintsVisible,
        actions: presentation.topChrome.actions.map((action: BrowserLargeScreenTopChromeActionPresentation): BrowserLargeScreenTopChromeActionPresentation => {
          return {
            id: action.id,
            slot: action.slot,
            visible: action.visible,
            enabled: action.enabled,
            hoverVisible: action.hoverVisible,
            keyboardHintVisible: action.keyboardHintVisible
          };
        })
      },
      activeTabChrome: {
        scene: presentation.activeTabChrome.scene,
        tabId: presentation.activeTabChrome.tabId,
        title: presentation.activeTabChrome.title,
        displayUrl: presentation.activeTabChrome.displayUrl,
        nativeRouteUrl: presentation.activeTabChrome.nativeRouteUrl,
        canGoBack: presentation.activeTabChrome.canGoBack,
        canGoForward: presentation.activeTabChrome.canGoForward,
        loading: presentation.activeTabChrome.loading,
        privateMode: presentation.activeTabChrome.privateMode
      },
      tabStrip: {
        allTabs: presentation.tabStrip.allTabs.map((tab: BrowserLargeScreenTabProjection): BrowserLargeScreenTabProjection => {
          return this.copyLargeScreenTabProjection(tab);
        }),
        visibleTabs: presentation.tabStrip.visibleTabs.map((tab: BrowserLargeScreenTabProjection): BrowserLargeScreenTabProjection => {
          return this.copyLargeScreenTabProjection(tab);
        }),
        hiddenTabIds: presentation.tabStrip.hiddenTabIds.slice(),
        selectedTabId: presentation.tabStrip.selectedTabId,
        overflowVisible: presentation.tabStrip.overflowVisible,
        dragEnabled: presentation.tabStrip.dragEnabled,
        hoverVisible: presentation.tabStrip.hoverVisible,
        newTabVisible: presentation.tabStrip.newTabVisible,
        titleBarHeightVp: presentation.tabStrip.titleBarHeightVp,
        titleButtonWidthVp: presentation.tabStrip.titleButtonWidthVp,
        windowMoveEnabled: presentation.tabStrip.windowMoveEnabled,
        availableWidthVp: presentation.tabStrip.availableWidthVp,
        consumedWidthVp: presentation.tabStrip.consumedWidthVp
      },
      sidePanel: {
        state: presentation.sidePanel.state,
        position: presentation.sidePanel.position,
        visible: presentation.sidePanel.visible,
        widthVp: presentation.sidePanel.widthVp
      },
      mainStageWidthVp: presentation.mainStageWidthVp,
      safeTopInsetVp: presentation.safeTopInsetVp,
      bottomStatusVisible: presentation.bottomStatusVisible
    };
  }

  private copyLargeScreenTabProjection(tab: BrowserLargeScreenTabProjection): BrowserLargeScreenTabProjection {
    return {
      id: tab.id,
      title: tab.title,
      url: tab.url,
      fallbackIconId: tab.fallbackIconId,
      active: tab.active,
      closable: tab.closable,
      loading: tab.loading,
      muted: tab.muted,
      privateMode: tab.privateMode,
      pinned: tab.pinned,
      audible: tab.audible,
      contextMenu: {
        reloadEnabled: tab.contextMenu.reloadEnabled,
        duplicateEnabled: tab.contextMenu.duplicateEnabled,
        pinEnabled: tab.contextMenu.pinEnabled,
        muteEnabled: tab.contextMenu.muteEnabled,
        closeEnabled: tab.contextMenu.closeEnabled,
        closeOthersEnabled: tab.contextMenu.closeOthersEnabled,
        closeRightEnabled: tab.contextMenu.closeRightEnabled
      },
      widthVp: tab.widthVp,
      leftVp: tab.leftVp
    };
  }
}
