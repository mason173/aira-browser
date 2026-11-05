import { webview } from '@kit.ArkWeb';
import { WebLinkTextScriptService } from '../../services/web/WebLinkTextScriptService';
import { WebLinkTextSelectionScriptService } from '../../services/web/WebLinkTextSelectionScriptService';
import { WebContextMenuViewportGeometry } from './WebContextMenuOverlayCoordinator';

// Keep the native ring and floating toolbar spacing in the same coordinate contract.
export const WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP: number = 16;
export const WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP: number = 44;

interface WebSelectionEndpoint {
  x: number;
  y: number;
  height: number;
}

interface WebLinkTextSelectionSignal {
  sessionId: string;
  active: boolean;
  revision?: number;
  dragging?: boolean;
  start?: WebSelectionEndpoint;
  end?: WebSelectionEndpoint;
  left?: number;
  top?: number;
  right?: number;
  bottom?: number;
  viewportWidth?: number;
  offsetLeft?: number;
  offsetTop?: number;
  clipLeft?: number;
  clipTop?: number;
  clipRight?: number;
  clipBottom?: number;
}

export interface WebLinkTextSelectionHandle {
  xVp: number;
  yVp: number;
  heightVp: number;
  visible: boolean;
}

export interface WebLinkTextSelectionPresentation {
  start: WebLinkTextSelectionHandle;
  end: WebLinkTextSelectionHandle;
  toolbarLeftVp: number;
  toolbarTopVp: number;
  toolbarWidthVp: number;
  toolbarVisible: boolean;
}

interface WebLinkTextSelectionSession {
  id: string;
  tabId: string;
  controller: webview.WebviewController;
  geometry: WebContextMenuViewportGeometry;
  signal?: WebLinkTextSelectionSignal;
  presentation?: WebLinkTextSelectionPresentation;
  dragHandle?: string;
  dragX: number;
  dragY: number;
  lastOffsetX: number;
  lastOffsetY: number;
  commandInFlight: boolean;
  commands: WebSelectionCommand[];
}

interface WebSelectionCommand {
  script: string;
  phase: string;
}

export class WebLinkTextSelectionCoordinator {
  private readonly scripts: WebLinkTextSelectionScriptService = new WebLinkTextSelectionScriptService();
  private readonly textScripts: WebLinkTextScriptService = new WebLinkTextScriptService();
  private readonly onChange: (presentation: WebLinkTextSelectionPresentation | undefined) => void;
  private session?: WebLinkTextSelectionSession;
  private serial: number = 0;

  constructor(onChange: (presentation: WebLinkTextSelectionPresentation | undefined) => void) {
    this.onChange = onChange;
  }

  start(tabId: string, controller: webview.WebviewController, targetId: string,
    geometry: WebContextMenuViewportGeometry): void {
    this.stop();
    const session: WebLinkTextSelectionSession = {
      id: `${Date.now()}-${++this.serial}`, tabId: tabId, controller: controller,
      geometry: geometry, dragX: 0, dragY: 0, lastOffsetX: 0, lastOffsetY: 0,
      commandInFlight: false, commands: []
    };
    this.session = session;
    this.execute(session, this.scripts.buildStartScript(session.id, targetId));
  }

  stop(): void {
    const session = this.session;
    this.session = undefined;
    if (session !== undefined) {
      try {
        void session.controller.runJavaScript(this.scripts.buildCommandScript(session.id, 'session.dispose()'))
          .catch((_error: Error): void => {});
      } catch (_error) {}
    }
  }

  handleSignal(tabId: string, payloadJson: string, geometry?: WebContextMenuViewportGeometry): void {
    const session = this.session;
    if (session === undefined || session.tabId !== tabId || payloadJson.length > 4096) return;
    try {
      const signal = JSON.parse(payloadJson) as WebLinkTextSelectionSignal;
      if (signal.sessionId !== session.id || typeof signal.active !== 'boolean') return;
      if ((signal.revision ?? 0) < (session.signal?.revision ?? 0)) return;
      if (!signal.active) {
        this.stop();
        this.onChange(undefined);
        return;
      }
      if (!this.validSignal(signal)) return;
      if (geometry !== undefined) session.geometry = geometry;
      session.signal = signal;
      this.publish(session);
    } catch (_error) {}
  }

  updateViewport(geometry: WebContextMenuViewportGeometry): void {
    const session = this.session;
    if (session === undefined) return;
    session.geometry = geometry;
    if (session.signal !== undefined) this.publish(session);
  }

  drag(handle: 'start' | 'end', phase: 'start' | 'update' | 'end', offsetXVp?: number, offsetYVp?: number): void {
    const session = this.session;
    if (session === undefined || session.presentation === undefined) return;
    if (phase === 'start') {
      const point = handle === 'start' ? session.presentation.start : session.presentation.end;
      session.dragX = point.xVp;
      session.dragY = point.yVp + point.heightVp / 2;
      session.dragHandle = handle;
      session.lastOffsetX = 0;
      session.lastOffsetY = 0;
    }
    if (session.dragHandle === undefined) return;
    const offsetX = offsetXVp ?? session.lastOffsetX;
    const offsetY = offsetYVp ?? session.lastOffsetY;
    if (!Number.isFinite(offsetX) || !Number.isFinite(offsetY)) return;
    session.lastOffsetX = offsetX;
    session.lastOffsetY = offsetY;
    const geometry = session.geometry;
    const xRatio = (session.dragX + offsetX - geometry.webLeftVp) / Math.max(1, geometry.webWidthVp);
    const yRatio = (session.dragY + offsetY - geometry.webTopVp) / Math.max(1, geometry.webWidthVp);
    const script = this.scripts.buildMoveScript(session.id, session.dragHandle, xRatio, yRatio, phase);
    // Preserve gesture boundaries while coalescing updates behind the single renderer call.
    const last = session.commands[session.commands.length - 1];
    if (last !== undefined && last.phase === 'update' && phase !== 'start') {
      session.commands[session.commands.length - 1] = { script: script, phase: phase };
    } else session.commands.push({ script: script, phase: phase });
    if (!session.commandInFlight) this.executeNext(session);
    if (phase === 'end') session.dragHandle = undefined;
    this.publish(session);
  }

  selectAll(): void {
    const session = this.session;
    if (session !== undefined && !session.commandInFlight) {
      this.execute(session, this.scripts.buildCommandScript(session.id, 'session.selectAll()'));
    }
  }

  async readText(): Promise<string | undefined> {
    const session = this.session;
    if (session === undefined || session.dragHandle !== undefined || session.commandInFlight) return undefined;
    try {
      const result = await session.controller.runJavaScript(this.scripts.buildCommandScript(session.id, 'session.text()'));
      return this.session === session ? this.textScripts.parseText(result) : undefined;
    } catch (_error) { return undefined; }
  }

  private execute(session: WebLinkTextSelectionSession, script: string): void {
    session.commandInFlight = true;
    try {
      void session.controller.runJavaScript(script).then((result: string): void => {
        if (this.session !== session) return;
        const json = this.textScripts.parseText(result);
        if (json.length > 0) this.handleSignal(session.tabId, json);
        else {
          this.stop();
          this.onChange(undefined);
        }
      }).catch((_error: Error): void => {
        if (this.session === session) { this.stop(); this.onChange(undefined); }
      }).finally((): void => {
        if (this.session !== session) return;
        session.commandInFlight = false;
        this.executeNext(session);
      });
    } catch (_error) {
      this.stop();
      this.onChange(undefined);
    }
  }

  private executeNext(session: WebLinkTextSelectionSession): void {
    const next = session.commands.shift();
    if (next !== undefined) this.execute(session, next.script);
  }

  private validSignal(signal: WebLinkTextSelectionSignal): boolean {
    return signal.start !== undefined && signal.end !== undefined &&
      this.validEndpoint(signal.start) && this.validEndpoint(signal.end) &&
      Number.isFinite(signal.viewportWidth) && (signal.viewportWidth ?? 0) > 0 &&
      Number.isFinite(signal.offsetLeft) && Number.isFinite(signal.offsetTop) &&
      Number.isFinite(signal.left) && Number.isFinite(signal.top) &&
      Number.isFinite(signal.right) && Number.isFinite(signal.bottom) &&
      Number.isFinite(signal.clipLeft) && Number.isFinite(signal.clipTop) &&
      Number.isFinite(signal.clipRight) && Number.isFinite(signal.clipBottom);
  }

  private validEndpoint(point: WebSelectionEndpoint): boolean {
    return Number.isFinite(point.x) && Number.isFinite(point.y) &&
      Number.isFinite(point.height) && point.height > 0;
  }

  private publish(session: WebLinkTextSelectionSession): void {
    const signal = session.signal;
    if (signal === undefined || signal.start === undefined || signal.end === undefined) return;
    const geometry = session.geometry;
    const scale = geometry.webWidthVp / Math.max(1, signal.viewportWidth ?? 1);
    const top = Math.max(geometry.webTopVp, geometry.availableTopVp ?? 0) + 8;
    const bottom = Math.min(geometry.webTopVp + geometry.webHeightVp,
      geometry.availableBottomVp ?? geometry.rootHeightVp) - 8;
    const left = geometry.webLeftVp;
    const right = Math.min(geometry.rootWidthVp, left + geometry.webWidthVp);
    const offsetX = left - (signal.offsetLeft ?? 0) * scale;
    const offsetY = geometry.webTopVp - (signal.offsetTop ?? 0) * scale;
    const clipLeft = Math.max(left, (signal.clipLeft ?? signal.offsetLeft ?? 0) * scale + offsetX);
    const clipRight = Math.min(right, (signal.clipRight ?? ((signal.offsetLeft ?? 0) + (signal.viewportWidth ?? 0))) * scale + offsetX);
    const clipTop = Math.max(top, (signal.clipTop ?? signal.offsetTop ?? 0) * scale + offsetY);
    const clipBottom = Math.min(bottom, (signal.clipBottom ?? geometry.webHeightVp / scale) * scale + offsetY);
    const start = this.projectEndpoint(signal.start, scale, offsetX, offsetY, clipLeft, clipRight, clipTop, clipBottom);
    const end = this.projectEndpoint(signal.end, scale, offsetX, offsetY, clipLeft, clipRight, clipTop, clipBottom);
    const width = Math.min(280, Math.max(1, right - left - 16));
    const selectionTop = (signal.top ?? 0) * scale + offsetY;
    const selectionBottom = (signal.bottom ?? 0) * scale + offsetY;
    const selectionCenter = ((signal.left ?? 0) + (signal.right ?? 0)) * scale / 2 + offsetX;
    const toolbarHeight = WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP;
    const handleGap = WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP + 8;
    const toolbarAbove = Math.max(selectionTop, clipTop) - handleGap - toolbarHeight;
    session.presentation = {
      start: start, end: end,
      toolbarLeftVp: Math.max(left + 8, Math.min(right - width - 8, selectionCenter - width / 2)),
      toolbarTopVp: Math.max(top, Math.min(bottom - toolbarHeight,
        toolbarAbove >= top ? toolbarAbove : Math.min(selectionBottom, clipBottom) + handleGap)),
      toolbarWidthVp: width,
      toolbarVisible: session.dragHandle === undefined && signal.dragging !== true &&
        selectionBottom >= clipTop && selectionTop <= clipBottom &&
        (signal.right ?? 0) * scale + offsetX >= clipLeft &&
        (signal.left ?? 0) * scale + offsetX <= clipRight && clipLeft < clipRight && clipTop < clipBottom
    };
    this.onChange(session.presentation);
  }

  private projectEndpoint(point: WebSelectionEndpoint, scale: number, offsetX: number, offsetY: number,
    left: number, right: number, top: number, bottom: number): WebLinkTextSelectionHandle {
    const x = point.x * scale + offsetX;
    const y = point.y * scale + offsetY;
    const height = point.height * scale;
    return { xVp: x, yVp: y, heightVp: height,
      visible: x >= left && x <= right && y >= top && y + height <= bottom };
  }
}
