import { webview } from '@kit.ArkWeb';
import { WebBottomSafeAreaScriptService } from '../../services/web/WebBottomSafeAreaScriptService';
import {
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT
} from './BrowserBottomAddressPanelMetrics';

export interface BrowserWebBottomSafeAreaFacts {
  tabId: string;
  url: string;
  controller?: webview.WebviewController;
  eligible: boolean;
  // Pauses the page observer without giving up the reserved space: a cover that hides the page
  // (the tabs overview, or a settings page through `setVisible`) must stop detection, but it is not
  // an input surface, so the space the page already needed stays reserved.
  suspended: boolean;
  // Releases the reserved space. Only a surface that occupies the bottom edge for its own input —
  // keyboard, address field, reader overlays — does this; leaving the space reserved under a cover
  // avoids a viewport resize that would reflow the page as the cover dismisses.
  insetSuppressed: boolean;
  systemBottomInsetVp: number;
}

export interface BrowserWebBottomSafeAreaPort {
  readFacts: () => BrowserWebBottomSafeAreaFacts;
  applyBottomInset: (insetVp: number) => void;
}

interface BottomSafeAreaSignal {
  kind: string;
  token: string;
  sequence: number;
  result: string;
}

class BottomSafeAreaDocumentSession {
  tabId: string;
  controller: webview.WebviewController;
  token: string;
  ready: boolean = true;
  running: boolean = false;
  detected: boolean = false;
  pageSuspended: boolean = false;
  sequence: number = 0;

  constructor(tabId: string, controller: webview.WebviewController, token: string) {
    this.tabId = tabId;
    this.controller = controller;
    this.token = token;
  }
}

const BOTTOM_SAFE_AREA_INTERACTION_QUIET_MS: number = 650;

// The page owns event-driven DOM observation. Native code owns document identity and geometry.
// URL changes alone do not discard a live document (SPA navigation/settings return).
export class BrowserWebBottomSafeAreaCoordinator {
  private port: BrowserWebBottomSafeAreaPort;
  private enabled: boolean = false;
  private visible: boolean = false;
  private sessions: Map<string, BottomSafeAreaDocumentSession> = new Map();
  private revision: number = 0;
  private activeTabId: string = '';
  private insetVp: number = 0;
  private lastInteractionAt: number = 0;
  private touchActive: boolean = false;
  private pendingPresentation: boolean = false;
  private timer: number = -1;
  private recheckTimer: number = -1;

  constructor(port: BrowserWebBottomSafeAreaPort) {
    this.port = port;
  }

  setEnabled(enabled: boolean): void {
    if (this.enabled === enabled) return;
    this.enabled = enabled;
    if (!enabled) {
      this.clearSessions();
      this.publish(0);
    } else {
      this.reconcile();
      // Leaving split toolbar for the floating capsule must scan the page already on screen.
      if (this.activeTabId.length > 0) this.requestCheck(this.activeTabId);
    }
  }

  setVisible(visible: boolean): void {
    if (this.visible === visible) return;
    this.visible = visible;
    if (!visible) this.clearInteraction();
    // Keep the document result and geometry while settings cover this shell.
    this.reconcile();
    if (visible && this.enabled && this.activeTabId.length > 0) this.requestCheck(this.activeTabId);
  }

  handleScroll(tabId: string): void {
    if (!this.enabled || !this.visible || tabId !== this.activeTabId) return;
    this.lastInteractionAt = Date.now();
  }

  handleTouch(tabId: string, pressed: boolean): void {
    if (!this.enabled || !this.visible || tabId !== this.activeTabId) return;
    this.touchActive = pressed;
    this.lastInteractionAt = Date.now();
    if (!pressed && this.pendingPresentation) this.schedulePresentation();
  }

  requestCheck(tabId: string): void {
    if (!this.enabled) return;
    const wasRunning = this.sessions.get(tabId)?.running === true;
    this.reconcile();
    const session = this.sessions.get(tabId);
    if (session === undefined) return;
    session.ready = true;
    if (tabId !== this.activeTabId || !this.canRun(this.port.readFacts())) return;
    // Idempotent installation also recovers when a document replaced its JS context.
    if (wasRunning || !session.running) this.install(session);
  }

  handleDocumentBegin(tabId: string): void {
    const previous = this.sessions.get(tabId);
    if (previous !== undefined) this.release(previous);
    this.sessions.delete(tabId);
    if (tabId !== this.port.readFacts().tabId) return;
    this.clearInteraction();
    this.publish(0);
    if (!this.enabled) return;
    const session = this.resolveSession(this.port.readFacts());
    if (session !== undefined) session.ready = false;
    this.scheduleRecheck(tabId);
  }

  retainTabs(tabIds: string[]): void {
    this.sessions.forEach((session: BottomSafeAreaDocumentSession, tabId: string): void => {
      if (tabIds.indexOf(tabId) >= 0) return;
      this.release(session);
      this.sessions.delete(tabId);
    });
  }

  // Share the existing page-behavior transport, with an independent tagged protocol.
  // The token is a document-generation guard, not a security credential.
  handleSignal(tabId: string, payloadJson: string): boolean {
    if (payloadJson.length > 512) return false;
    let signal: BottomSafeAreaSignal;
    try { signal = JSON.parse(payloadJson) as BottomSafeAreaSignal; } catch (_) { return false; }
    if (signal === null || signal.kind !== 'bottom-safe-area') return false;
    const session = this.sessions.get(tabId);
    if (!this.enabled || session === undefined || !session.running ||
      signal.token !== session.token || !Number.isInteger(signal.sequence) ||
      signal.sequence <= session.sequence ||
      (signal.result !== 'detected' && signal.result !== 'absent' && signal.result !== 'suspended')) return true;
    const facts = this.port.readFacts();
    if (facts.tabId !== tabId || facts.controller !== session.controller) return true;
    session.sequence = signal.sequence;
    session.pageSuspended = signal.result === 'suspended';
    if (!session.pageSuspended) session.detected = signal.result === 'detected';
    if (tabId === this.activeTabId) this.applyPresentation(facts, session);
    return true;
  }

  reconcile(): void {
    if (!this.enabled) return;
    const facts = this.port.readFacts();
    if (this.activeTabId !== facts.tabId) {
      this.activeTabId = facts.tabId;
      this.clearInteraction();
    }
    const active = this.resolveSession(facts);
    this.sessions.forEach((session: BottomSafeAreaDocumentSession): void => {
      if (session !== active || !this.canRun(facts)) this.pause(session);
    });
    if (!this.visible) return;
    if (active !== undefined && active.ready && this.canRun(facts) && !active.running) this.install(active);
    this.applyPresentation(facts, active);
  }

  dispose(): void {
    this.enabled = false;
    this.visible = false;
    this.clearSessions();
    this.publish(0);
  }

  private canRun(facts: BrowserWebBottomSafeAreaFacts): boolean {
    return this.enabled && this.visible && facts.eligible && !facts.suspended;
  }

  private resolveSession(facts: BrowserWebBottomSafeAreaFacts): BottomSafeAreaDocumentSession | undefined {
    let session = this.sessions.get(facts.tabId);
    if (session !== undefined && session.controller !== facts.controller) {
      this.release(session);
      this.sessions.delete(facts.tabId);
      session = undefined;
    }
    if (session === undefined && facts.controller !== undefined && /^https?:\/\//i.test(facts.url)) {
      session = new BottomSafeAreaDocumentSession(facts.tabId, facts.controller,
        `${Date.now()}-${++this.revision}`);
      this.sessions.set(facts.tabId, session);
    }
    return session;
  }

  private install(session: BottomSafeAreaDocumentSession): void {
    session.running = true;
    try {
      const script = WebBottomSafeAreaScriptService.buildInstallScript(session.token);
      void session.controller.runJavaScript(script)
        .catch(() => {
          // Retry only at the next lifecycle event, never through a native polling loop.
          if (this.sessions.get(session.tabId) === session) session.running = false;
        });
    } catch (_) { session.running = false; }
  }

  private pause(session: BottomSafeAreaDocumentSession): void {
    if (!session.running) return;
    session.running = false;
    this.command(session, 'pause');
  }

  private release(session: BottomSafeAreaDocumentSession): void {
    session.running = false;
    this.command(session, 'dispose');
  }

  private command(session: BottomSafeAreaDocumentSession, command: string): void {
    try {
      void session.controller.runJavaScript(WebBottomSafeAreaScriptService.buildCommandScript(session.token, command))
        .catch(() => {});
    } catch (_) {}
  }

  private clearSessions(): void {
    this.sessions.forEach((session: BottomSafeAreaDocumentSession): void => this.release(session));
    this.sessions.clear();
    this.clearInteraction();
  }

  private clearInteraction(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
    this.timer = -1;
    if (this.recheckTimer >= 0) clearTimeout(this.recheckTimer);
    this.recheckTimer = -1;
    this.touchActive = false;
    this.pendingPresentation = false;
    this.lastInteractionAt = 0;
  }

  private scheduleRecheck(tabId: string): void {
    if (this.recheckTimer >= 0) clearTimeout(this.recheckTimer);
    this.recheckTimer = setTimeout(() => {
      this.recheckTimer = -1;
      if (!this.enabled || !this.visible || tabId !== this.activeTabId) return;
      const session = this.sessions.get(tabId);
      if (session === undefined || !this.canRun(this.port.readFacts())) return;
      session.ready = true;
      this.install(session);
      this.applyPresentation(this.port.readFacts(), session);
    }, 700);
  }

  private applyPresentation(facts: BrowserWebBottomSafeAreaFacts,
    session: BottomSafeAreaDocumentSession | undefined): void {
    if (!this.visible) return;
    if (!facts.eligible || facts.insetSuppressed || session === undefined) {
      this.publish(0);
      return;
    }
    // A bridge message already queued before a gesture must not resize its viewport mid-scroll.
    if (this.touchActive || Date.now() - this.lastInteractionAt < BOTTOM_SAFE_AREA_INTERACTION_QUIET_MS) {
      this.pendingPresentation = true;
      this.schedulePresentation();
      return;
    }
    this.pendingPresentation = false;
    const envelope = BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT +
      BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP;
    this.publish(session.detected && !session.pageSuspended ?
      Math.ceil(Math.max(envelope, facts.systemBottomInsetVp) + 8) : 0);
  }

  private schedulePresentation(): void {
    if (this.timer >= 0 || this.touchActive) return;
    this.timer = setTimeout(() => {
      this.timer = -1;
      if (this.enabled && this.visible && this.pendingPresentation) {
        this.applyPresentation(this.port.readFacts(), this.sessions.get(this.activeTabId));
      }
    }, BOTTOM_SAFE_AREA_INTERACTION_QUIET_MS);
  }

  private publish(insetVp: number): void {
    if (insetVp === this.insetVp) return;
    this.insetVp = insetVp;
    this.port.applyBottomInset(insetVp);
  }
}
