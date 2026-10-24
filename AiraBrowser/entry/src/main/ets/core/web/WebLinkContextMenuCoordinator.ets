import { webview } from '@kit.ArkWeb';
import { resolveAppResourceText } from '../resources/AppResourceText';
import { BrowserDataScope, BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import { BrowserAppUrlOpenCoordinator } from '../browser/BrowserAppUrlOpenCoordinator';
import { BrowserWebLayerGeometrySnapshot } from '../browser/BrowserWebLayerGeometryCache';
import { UserScriptPageMenuCommandView } from '../../features/userscripts/UserScriptRuntimeModels';
import { UserScriptRuntimeCoordinator } from '../userscripts/UserScriptRuntimeCoordinator';
import { BrowserWebLoadRuntimeCoordinator } from '../../services/web/BrowserWebLoadRuntimeCoordinator';
import {
  WebImageContextActionInput,
  WebImageContextActionResult,
  WebImageContextActionService
} from '../../services/web/WebImageContextActionService';
import {
  WebContextMenuMeasuredSize,
  WebContextMenuOverlayCoordinator,
  WebContextMenuOverlayLayout,
  WebContextMenuOverlayLayoutRequest,
  WebContextMenuOverlayPresentation,
  WebContextMenuViewportGeometry
} from './WebContextMenuOverlayCoordinator';
import {
  BrowserPrivateOpenTarget,
  BrowserPrivateWindowPolicyService
} from '../../services/browser/BrowserPrivateWindowPolicyService';
import { BrowserWindowRuntime } from '../../app/runtime/BrowserWindowRuntime';

export type WebLinkContextMenuAction =
  'open' |
  'open_new_tab' |
  'open_background_tab' |
  'open_private_tab' |
  'copy_link' |
  'share_link' |
  'add_bookmark' |
  'save_offline' |
  'download_link' |
  'run_userscript' |
  'save_image' |
  'copy_image' |
  'share_image';

export type WebLinkContextMenuGroup = 'open' | 'transfer' | 'save' | 'script' | 'image';

export interface WebLinkContextMenuItem {
  action: WebLinkContextMenuAction;
  label: string;
  group: WebLinkContextMenuGroup;
  scriptId?: string;
  commandId?: string;
}

export interface WebLinkContextMenuState {
  visible: boolean;
  kind: 'link' | 'image';
  tabId: string;
  url: string;
  title: string;
  referer?: string;
  userAgent?: string;
  x: number;
  y: number;
  items: WebLinkContextMenuItem[];
}

export interface WebContextMenuPresentation {
  state: WebLinkContextMenuState;
  layout: WebContextMenuOverlayLayout;
}

export interface WebContextMenuOverlayAction {
  type: 'measured' | 'dismiss' | 'select';
  widthVp?: number;
  heightVp?: number;
  item?: WebLinkContextMenuItem;
}

export interface WebContextMenuViewportFacts {
  rootWidthVp: number;
  rootHeightVp: number;
  hostedWebLayerMeasured: boolean;
  hostedWebLayerLeftVp: number;
  hostedWebLayerTopVp: number;
  hostedWebLayerWidthVp: number;
  hostedWebLayerHeightVp: number;
  reusableGeometry?: BrowserWebLayerGeometrySnapshot;
  webViewportTopInsetVp: number;
}

export interface WebContextMenuSessionFacts {
  activeTabId: string;
  showPageErrorSurface: boolean;
  tabTitle: string;
  currentTitle: string;
  pageUrl: string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
  viewport: WebContextMenuViewportFacts;
}

export type WebContextMenuEffectType =
  'toast' |
  'error_message' |
  'helper_message' |
  'open_current_link' |
  'open_private_tab' |
  'open_private_window' |
  'copy_link' |
  'share_link' |
  'add_bookmark' |
  'save_offline' |
  'download_link';

export interface WebContextMenuEffect {
  type: WebContextMenuEffectType;
  message?: string;
  eventType?: string;
  tabId?: string;
  url?: string;
  title?: string;
  referer?: string;
  userAgent?: string;
}

interface WebContextMenuApplicationResult {
  presentation: WebContextMenuPresentation;
  effects: WebContextMenuEffect[];
  completion?: Promise<WebContextMenuEffect[]>;
}

interface WebContextMenuShowResult extends WebContextMenuApplicationResult {
  handled: boolean;
}

export interface WebLinkContextMenuCoordinatorDependencies {
  userScriptRuntimeCoordinator: UserScriptRuntimeCoordinator;
  webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
}

export interface WebLinkContextMenuApplicationSink {
  publishPresentation: (presentation: WebContextMenuPresentation) => void;
}

export interface WebLinkContextMenuActionApplication {
  applyEffects(effects: WebContextMenuEffect[]): void;
}

export type WebLinkContextMenuActionApplicationResolver = () => WebLinkContextMenuActionApplication;

interface WebLinkContextMenuRequest {
  tabId: string;
  pageTitle: string;
  pageUrl?: string;
  userAgent?: string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
  event: OnContextMenuShowEvent;
  hitTest?: webview.HitTestValue;
  extraItems?: WebLinkContextMenuItem[];
}

interface PendingWebContextMenuResult {
  closeContextMenu: () => void;
}

interface WebContextMenuMediaParam {
  getMediaType?: () => number;
}

const WEB_CONTEXT_MENU_MEDIA_TYPE_IMAGE: number = 1;

const WEB_LINK_CONTEXT_MENU_ACTIONS: WebLinkContextMenuItem[] = [
  { action: 'open', label: '', group: 'open' },
  { action: 'open_new_tab', label: '', group: 'open' },
  { action: 'open_background_tab', label: '', group: 'open' },
  { action: 'open_private_tab', label: '', group: 'open' },
  { action: 'copy_link', label: '', group: 'transfer' },
  { action: 'share_link', label: '', group: 'transfer' },
  { action: 'add_bookmark', label: '', group: 'save' },
  { action: 'save_offline', label: '', group: 'save' },
  { action: 'download_link', label: '', group: 'save' }
];

export class WebLinkContextMenuCoordinator {
  private readonly userScriptRuntimeCoordinator: UserScriptRuntimeCoordinator;
  private readonly webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  private readonly appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  private readonly sink: WebLinkContextMenuApplicationSink;
  private readonly resolveActionApplication: WebLinkContextMenuActionApplicationResolver;
  private readonly imageActionService: WebImageContextActionService = new WebImageContextActionService();
  private readonly overlayCoordinator: WebContextMenuOverlayCoordinator = new WebContextMenuOverlayCoordinator();
  private readonly privateWindowPolicyService: BrowserPrivateWindowPolicyService =
    new BrowserPrivateWindowPolicyService();
  private presentation: WebContextMenuPresentation;
  private pendingResult?: PendingWebContextMenuResult;
  private pendingResultClosed: boolean = true;

  constructor(
    dependencies: WebLinkContextMenuCoordinatorDependencies,
    sink: WebLinkContextMenuApplicationSink,
    resolveActionApplication: WebLinkContextMenuActionApplicationResolver
  ) {
    this.userScriptRuntimeCoordinator = dependencies.userScriptRuntimeCoordinator;
    this.webLoadRuntimeCoordinator = dependencies.webLoadRuntimeCoordinator;
    this.appUrlOpenCoordinator = dependencies.appUrlOpenCoordinator;
    this.sink = sink;
    this.resolveActionApplication = resolveActionApplication;
    this.presentation = this.buildHiddenPresentation();
  }

  createHiddenPresentation(): WebContextMenuPresentation {
    return this.buildHiddenPresentation();
  }

  isVisibleForTab(tabId: string): boolean {
    return this.presentation.state.visible && this.presentation.state.tabId === tabId;
  }

  show(
    tabId: string,
    event: OnContextMenuShowEvent,
    controller: webview.WebviewController,
    facts: WebContextMenuSessionFacts
  ): boolean {
    if (tabId === facts.activeTabId && facts.showPageErrorSurface) {
      this.closeResult(event.result as object as PendingWebContextMenuResult);
      return this.applyShowResult(this.buildShowResult(true, []));
    }
    const state = this.buildState({
      tabId: tabId,
      pageTitle: this.resolvePageTitle(facts),
      pageUrl: facts.pageUrl,
      userAgent: this.resolveDownloadUserAgent(controller),
      privacyMode: facts.privacyMode,
      dataScope: facts.dataScope,
      event: event,
      hitTest: this.resolveLastHitTest(controller),
      extraItems: this.buildUserScriptItems(
        facts.pageUrl,
        this.isPrivateBoundary(facts.privacyMode, facts.dataScope)
      )
    });
    if (state === undefined) {
      return this.applyShowResult(this.buildShowResult(false, []));
    }
    this.closePendingResultOnce();
    this.pendingResult = event.result as object as PendingWebContextMenuResult;
    this.pendingResultClosed = false;
    this.presentation = {
      state: state,
      layout: this.overlayCoordinator.buildInitialLayout(this.buildLayoutRequest(state, facts))
    };
    return this.applyShowResult(this.buildShowResult(true, []));
  }

  hide(tabId: string): void {
    const state = this.presentation.state;
    if (state.tabId !== tabId) {
      return;
    }
  }

  dismiss(): void {
    this.closePendingResultOnce();
    this.presentation = this.buildHiddenPresentation();
    this.applyResult(this.buildResult([]));
  }

  handleOverlayAction(action: WebContextMenuOverlayAction, facts: WebContextMenuSessionFacts): void {
    if (action.type === 'dismiss') {
      this.dismiss();
      return;
    }
    if (action.type === 'measured') {
      this.measure(action.widthVp ?? 0, action.heightVp ?? 0, facts);
      return;
    }
    if (action.item !== undefined) {
      this.select(action.item, facts);
    }
  }

  private measure(
    widthVp: number,
    heightVp: number,
    facts: WebContextMenuSessionFacts
  ): void {
    const state = this.presentation.state;
    if (!state.visible) {
      this.applyResult(this.buildResult([]));
      return;
    }
    const measuredSize: WebContextMenuMeasuredSize = {
      menuWidthVp: widthVp,
      menuHeightVp: heightVp
    };
    const nextLayout = this.overlayCoordinator.buildMeasuredLayout(
      this.buildLayoutRequest(state, facts),
      measuredSize
    );
    if (!this.isLayoutEquivalent(this.presentation.layout, nextLayout)) {
      this.presentation = {
        state: state,
        layout: nextLayout
      };
    }
    this.applyResult(this.buildResult([]));
  }

  private select(
    item: WebLinkContextMenuItem,
    facts: WebContextMenuSessionFacts
  ): void {
    const state = this.presentation.state;
    this.closePendingResultOnce();
    this.presentation = this.buildHiddenPresentation();
    if (state.url.length === 0) {
      this.applyResult(this.buildResult([{
        type: 'toast',
        message: state.kind === 'image'
          ? resolveAppResourceText($r('app.string.context_menu_no_image'))
          : resolveAppResourceText($r('app.string.context_menu_no_link'))
      }]));
      return;
    }
    switch (item.action) {
      case 'save_image':
      case 'copy_image':
      case 'share_image':
        this.applyResult(this.buildResult([], this.executeImageAction(item.action, state, facts)));
        return;
      case 'open':
        this.applyResult(this.buildResult(this.openCurrentLink(state, facts)));
        return;
      case 'open_new_tab':
        this.openLinkInTab(state, 'new_tab');
        this.applyResult(this.buildResult([]));
        return;
      case 'open_background_tab':
        this.openLinkInTab(state, 'background_tab');
        this.applyResult(this.buildResult([]));
        return;
      case 'open_private_tab':
        this.applyResult(this.buildResult([{
          type: this.resolvePrivateOpenEffectType(),
          tabId: state.tabId,
          title: state.title,
          url: state.url
        }]));
        return;
      case 'copy_link':
        this.applyResult(this.buildResult([{ type: 'copy_link', url: state.url }]));
        return;
      case 'share_link':
        this.applyResult(this.buildResult([{ type: 'share_link', title: state.title, url: state.url }]));
        return;
      case 'add_bookmark':
        this.applyResult(this.buildResult([{
          type: 'add_bookmark',
          tabId: state.tabId,
          title: state.title.length > 0 ? state.title : state.url,
          url: state.url
        }]));
        return;
      case 'save_offline':
        this.applyResult(this.buildResult([{
          type: 'save_offline',
          tabId: state.tabId,
          title: state.title,
          url: state.url
        }]));
        return;
      case 'download_link':
        this.applyResult(this.buildResult([{
          type: 'download_link',
          tabId: state.tabId,
          url: state.url,
          referer: state.referer,
          userAgent: state.userAgent
        }]));
        return;
      case 'run_userscript':
        this.applyResult(this.selectUserScriptCommand(state, item, facts));
        return;
      default:
        this.applyResult(this.buildResult([]));
        return;
    }
  }

  private buildState(request: WebLinkContextMenuRequest): WebLinkContextMenuState | undefined {
    const imageState = this.buildImageState(request);
    if (imageState !== undefined) {
      return imageState;
    }
    return this.buildLinkState(request);
  }

  private buildImageState(request: WebLinkContextMenuRequest): WebLinkContextMenuState | undefined {
    const url = this.resolveImageUrl(request.event.param, request.hitTest);
    if (url.length === 0 || !this.isWebImageContext(request.event.param, request.hitTest, url)) {
      return undefined;
    }
    const title = request.pageTitle.trim().length > 0
      ? request.pageTitle.trim()
      : resolveAppResourceText($r('app.string.context_menu_web_image'));
    return {
      visible: true,
      kind: 'image',
      tabId: request.tabId,
      url: url,
      title: title,
      x: this.safeNumber(() => request.event.param.x()),
      y: this.safeNumber(() => request.event.param.y()),
      items: [
        { action: 'save_image', label: resolveAppResourceText($r('app.string.context_menu_save_to_gallery')), group: 'image' },
        { action: 'copy_image', label: resolveAppResourceText($r('app.string.context_menu_copy_image')), group: 'image' },
        { action: 'share_image', label: resolveAppResourceText($r('app.string.context_menu_share_image')), group: 'image' }
      ]
    };
  }

  private buildLinkState(request: WebLinkContextMenuRequest): WebLinkContextMenuState | undefined {
    const url = this.resolveContextUrl(request.event.param, request.hitTest);
    if (url.length === 0 || !this.isHttpLinkContext(request.event.param, request.hitTest, url)) {
      return undefined;
    }
    const title = request.pageTitle.trim().length > 0 ? request.pageTitle.trim() : url;
    return {
      visible: true,
      kind: 'link',
      tabId: request.tabId,
      url: url,
      title: title,
      referer: this.isWebLinkUrl(request.pageUrl ?? '') ? request.pageUrl?.trim() : undefined,
      userAgent: request.userAgent,
      x: this.safeNumber(() => request.event.param.x()),
      y: this.safeNumber(() => request.event.param.y()),
      items: this.cloneItems()
        .concat(this.cloneExtraItems(request.extraItems ?? []))
    };
  }

  private buildHiddenPresentation(): WebContextMenuPresentation {
    return {
      state: this.buildHiddenState(),
      layout: this.overlayCoordinator.createHiddenLayout()
    };
  }

  private buildHiddenState(): WebLinkContextMenuState {
    return {
      visible: false,
      kind: 'link',
      tabId: '',
      url: '',
      title: '',
      x: -1,
      y: -1,
      items: []
    };
  }

  private buildShowResult(handled: boolean, effects: WebContextMenuEffect[]): WebContextMenuShowResult {
    return {
      handled: handled,
      presentation: this.presentation,
      effects: effects
    };
  }

  private buildResult(
    effects: WebContextMenuEffect[],
    completion?: Promise<WebContextMenuEffect[]>
  ): WebContextMenuApplicationResult {
    return {
      presentation: this.presentation,
      effects: effects,
      completion: completion
    };
  }

  private applyShowResult(result: WebContextMenuShowResult): boolean {
    this.applyResult(result);
    return result.handled;
  }

  private applyResult(result: WebContextMenuApplicationResult): void {
    this.sink.publishPresentation(result.presentation);
    this.resolveActionApplication().applyEffects(result.effects);
    if (result.completion !== undefined) {
      void result.completion.then((effects: WebContextMenuEffect[]): void => {
        this.resolveActionApplication().applyEffects(effects);
      });
    }
  }

  private resolvePageTitle(facts: WebContextMenuSessionFacts): string {
    const tabTitle = facts.tabTitle.trim();
    return tabTitle.length > 0 ? tabTitle : facts.currentTitle.trim();
  }

  private buildUserScriptItems(pageUrl: string, privateMode: boolean): WebLinkContextMenuItem[] {
    return this.userScriptRuntimeCoordinator.buildContextMenuCommands(pageUrl, privateMode)
      .map((command: UserScriptPageMenuCommandView): WebLinkContextMenuItem => {
        return {
          action: 'run_userscript',
          label: command.commandName,
          group: 'script',
          scriptId: command.scriptId,
          commandId: command.commandId
        };
      });
  }

  private openCurrentLink(
    state: WebLinkContextMenuState,
    facts: WebContextMenuSessionFacts
  ): WebContextMenuEffect[] {
    if (state.tabId !== facts.activeTabId) {
      if (!this.webLoadRuntimeCoordinator.loadWebContextMenuLinkForTab(state.tabId, state.url)) {
        return [{ type: 'toast', message: resolveAppResourceText($r('app.string.context_menu_open_failed')) }];
      }
      return [{ type: 'helper_message', message: resolveAppResourceText($r('app.string.context_menu_opening')) }];
    }
    return [{ type: 'open_current_link', tabId: state.tabId, url: state.url }];
  }

  private openLinkInTab(state: WebLinkContextMenuState, intent: 'new_tab' | 'background_tab'): void {
    this.appUrlOpenCoordinator.open({
      url: state.url,
      title: state.title,
      intent: intent,
      source: 'web_context_menu',
      openerTabId: state.tabId
    });
  }

  private executeImageAction(
    action: 'save_image' | 'copy_image' | 'share_image',
    state: WebLinkContextMenuState,
    facts: WebContextMenuSessionFacts
  ): Promise<WebContextMenuEffect[]> {
    const input: WebImageContextActionInput = {
      imageUrl: state.url,
      pageUrl: facts.pageUrl,
      title: state.title
    };
    let task: Promise<WebImageContextActionResult>;
    if (action === 'save_image') {
      task = this.imageActionService.saveToGallery(input);
    } else if (action === 'copy_image') {
      task = this.imageActionService.copyImage(input);
    } else {
      task = this.imageActionService.shareImage(input);
    }
    return task.then((result: WebImageContextActionResult): WebContextMenuEffect[] => {
      return [{ type: 'toast', message: result.message }];
    }).catch((_error: Error): WebContextMenuEffect[] => {
      return [{ type: 'toast', message: resolveAppResourceText($r('app.string.context_menu_image_failed')) }];
    });
  }

  private selectUserScriptCommand(
    state: WebLinkContextMenuState,
    item: WebLinkContextMenuItem,
    facts: WebContextMenuSessionFacts
  ): WebContextMenuApplicationResult {
    const scriptId = String(item.scriptId ?? '').trim();
    const commandId = String(item.commandId ?? '').trim();
    if (scriptId.length === 0 || commandId.length === 0) {
      return this.buildResult([{ type: 'toast', message: resolveAppResourceText($r('app.string.context_menu_script_unavailable')) }]);
    }
    const completion = this.userScriptRuntimeCoordinator.executePageCommandForPage(
      state.tabId,
      scriptId,
      commandId,
      facts.pageUrl,
      this.isPrivateBoundary(facts.privacyMode, facts.dataScope)
    ).then((success: boolean): WebContextMenuEffect[] => {
      return [{
        type: 'toast',
        message: success
          ? resolveAppResourceText($r('app.string.context_menu_script_done'))
          : resolveAppResourceText($r('app.string.context_menu_script_failed'))
      }];
    }).catch((error: Error): WebContextMenuEffect[] => {
      return [{
        type: 'error_message',
        message: resolveAppResourceText($r('app.string.context_menu_script_error', this.stringifyError(error)))
      }];
    });
    return this.buildResult([], completion);
  }

  private buildLayoutRequest(
    state: WebLinkContextMenuState,
    facts: WebContextMenuSessionFacts
  ): WebContextMenuOverlayLayoutRequest {
    const presentation = this.resolveOverlayPresentation();
    return {
      point: {
        rawWebXPx: state.x,
        rawWebYPx: state.y
      },
      geometry: this.resolveViewportGeometry(facts.viewport),
      itemCount: state.items.length,
      dividerCount: this.resolveDividerCount(state.items, presentation),
      presentation: presentation
    };
  }

  private resolveOverlayPresentation(): WebContextMenuOverlayPresentation {
    return BrowserWindowRuntime.resolveActiveShellPresentationSurface() === 'large_screen' ? 'desktop' : 'touch';
  }

  private resolveDividerCount(
    items: WebLinkContextMenuItem[],
    presentation: WebContextMenuOverlayPresentation
  ): number {
    if (items.length <= 1) {
      return 0;
    }
    if (presentation === 'touch') {
      return items.length - 1;
    }
    let dividerCount = 0;
    for (let index = 1; index < items.length; index += 1) {
      if (items[index - 1].group !== items[index].group) {
        dividerCount += 1;
      }
    }
    return dividerCount;
  }

  private resolveViewportGeometry(facts: WebContextMenuViewportFacts): WebContextMenuViewportGeometry {
    const reusableGeometry = facts.reusableGeometry;
    const measuredWidth = facts.hostedWebLayerMeasured && facts.hostedWebLayerWidthVp > 1;
    const measuredHeight = facts.hostedWebLayerMeasured && facts.hostedWebLayerHeightVp > 1;
    return {
      rootWidthVp: facts.rootWidthVp,
      rootHeightVp: facts.rootHeightVp,
      webLeftVp: measuredWidth ? Math.max(0, facts.hostedWebLayerLeftVp) :
        (reusableGeometry === undefined ? 0 : Math.max(0, reusableGeometry.webLeft)),
      webTopVp: measuredHeight ? Math.max(0, facts.hostedWebLayerTopVp) :
        (reusableGeometry === undefined ? facts.webViewportTopInsetVp : Math.max(0, reusableGeometry.webTop)),
      webWidthVp: measuredWidth ? Math.max(1, facts.hostedWebLayerWidthVp) :
        (reusableGeometry === undefined ? Math.max(1, facts.rootWidthVp) : Math.max(1, reusableGeometry.webWidth)),
      webHeightVp: measuredHeight ? Math.max(1, facts.hostedWebLayerHeightVp) :
        (reusableGeometry === undefined ? Math.max(1, facts.rootHeightVp - facts.webViewportTopInsetVp) :
          Math.max(1, reusableGeometry.webHeight))
    };
  }

  private isLayoutEquivalent(current: WebContextMenuOverlayLayout, next: WebContextMenuOverlayLayout): boolean {
    return current.visible === next.visible &&
      Math.abs(current.menuLeftVp - next.menuLeftVp) < 0.5 &&
      Math.abs(current.menuTopVp - next.menuTopVp) < 0.5 &&
      Math.abs(current.menuWidthVp - next.menuWidthVp) < 1 &&
      Math.abs(current.menuHeightVp - next.menuHeightVp) < 1 &&
      Math.abs(current.maxHeightVp - next.maxHeightVp) < 1 &&
      current.presentation === next.presentation;
  }

  private resolveLastHitTest(controller: webview.WebviewController): webview.HitTestValue | undefined {
    try {
      return controller.getLastHitTest();
    } catch (_error) {
      return undefined;
    }
  }

  private resolveDownloadUserAgent(controller: webview.WebviewController): string | undefined {
    const custom = this.safeString(() => controller.getCustomUserAgent());
    const userAgent = custom.length > 0 ? custom : this.safeString(() => controller.getUserAgent());
    return userAgent.length > 0 ? userAgent : undefined;
  }

  private closePendingResultOnce(): void {
    if (this.pendingResultClosed) {
      return;
    }
    this.pendingResultClosed = true;
    const result = this.pendingResult;
    this.pendingResult = undefined;
    this.closeResult(result);
  }

  private closeResult(result: PendingWebContextMenuResult | undefined): void {
    if (result === undefined) {
      return;
    }
    try {
      result.closeContextMenu();
    } catch (_error) {
    }
  }

  private resolveContextUrl(param: WebContextMenuParam, hitTest: webview.HitTestValue | undefined): string {
    const linkUrl = this.safeString(() => param.getLinkUrl());
    if (linkUrl.length > 0) {
      return linkUrl;
    }
    const unfilteredLinkUrl = this.safeString(() => param.getUnfilteredLinkUrl());
    if (unfilteredLinkUrl.length > 0) {
      return unfilteredLinkUrl;
    }
    if (hitTest !== undefined && this.isAnchorHitTest(hitTest) && hitTest.extra.trim().length > 0) {
      return hitTest.extra.trim();
    }
    return '';
  }

  private resolveImageUrl(param: WebContextMenuParam, hitTest: webview.HitTestValue | undefined): string {
    if (hitTest !== undefined && this.isImageHitTest(hitTest) && hitTest.extra.trim().length > 0) {
      return hitTest.extra.trim();
    }
    const sourceUrl = this.safeString(() => param.getSourceUrl());
    if (sourceUrl.length > 0) {
      return sourceUrl;
    }
    return '';
  }

  private isHttpLinkContext(
    param: WebContextMenuParam,
    hitTest: webview.HitTestValue | undefined,
    url: string
  ): boolean {
    if (!this.isWebLinkUrl(url)) {
      return false;
    }
    if (hitTest !== undefined && this.isAnchorHitTest(hitTest)) {
      return true;
    }
    return this.safeString(() => param.getLinkUrl()).length > 0 ||
      this.safeString(() => param.getUnfilteredLinkUrl()).length > 0;
  }

  private isAnchorHitTest(hitTest: webview.HitTestValue): boolean {
    return hitTest.type === webview.WebHitTestType.HttpAnchor ||
      hitTest.type === webview.WebHitTestType.HttpAnchorImg;
  }

  private isImageHitTest(hitTest: webview.HitTestValue): boolean {
    return hitTest.type === webview.WebHitTestType.Img ||
      hitTest.type === webview.WebHitTestType.HttpAnchorImg;
  }

  private isWebImageContext(
    param: WebContextMenuParam,
    hitTest: webview.HitTestValue | undefined,
    url: string
  ): boolean {
    if (!this.isImageMediaContext(param)) {
      return false;
    }
    if (hitTest !== undefined && !this.isImageHitTest(hitTest)) {
      return false;
    }
    return this.isWebLinkUrl(url) || this.isDataImageUrl(url);
  }

  private isImageMediaContext(param: WebContextMenuParam): boolean {
    return this.resolveContextMenuMediaType(param) === WEB_CONTEXT_MENU_MEDIA_TYPE_IMAGE;
  }

  private resolveContextMenuMediaType(param: WebContextMenuParam): number {
    try {
      const mediaParam = param as object as WebContextMenuMediaParam;
      if (mediaParam.getMediaType === undefined) {
        return -1;
      }
      const value = mediaParam.getMediaType();
      return Number.isFinite(value) ? value : -1;
    } catch (_error) {
      return -1;
    }
  }

  private isWebLinkUrl(url: string): boolean {
    const lowerUrl = url.trim().toLowerCase();
    return lowerUrl.indexOf('http://') === 0 || lowerUrl.indexOf('https://') === 0;
  }

  private isDataImageUrl(url: string): boolean {
    return url.trim().toLowerCase().indexOf('data:image/') === 0;
  }

  private cloneItems(): WebLinkContextMenuItem[] {
    const privateOpenTarget = this.privateWindowPolicyService.resolveTarget();
    return WEB_LINK_CONTEXT_MENU_ACTIONS
      .map((item: WebLinkContextMenuItem): WebLinkContextMenuItem => {
        return {
          action: item.action,
          label: item.action === 'open_private_tab'
            ? this.resolvePrivateOpenLabel(privateOpenTarget)
            : this.resolveLinkActionLabel(item.action),
          group: item.group,
          scriptId: item.scriptId,
          commandId: item.commandId
        };
      });
  }

  private resolveLinkActionLabel(action: string): string {
    switch (action) {
      case 'open':
        return resolveAppResourceText($r('app.string.ui_open'));
      case 'open_new_tab':
        return resolveAppResourceText($r('app.string.history_open_new_tab_short'));
      case 'open_background_tab':
        return resolveAppResourceText($r('app.string.history_open_background'));
      case 'copy_link':
        return resolveAppResourceText($r('app.string.offline_action_copy_link'));
      case 'share_link':
        return resolveAppResourceText($r('app.string.context_menu_share_link'));
      case 'add_bookmark':
        return resolveAppResourceText($r('app.string.bottom_panel_action_bookmark'));
      case 'save_offline':
        return resolveAppResourceText($r('app.string.context_menu_save_offline'));
      case 'download_link':
        return resolveAppResourceText($r('app.string.context_menu_download_link'));
      default:
        return resolveAppResourceText($r('app.string.ui_open'));
    }
  }

  private resolvePrivateOpenLabel(target: BrowserPrivateOpenTarget): string {
    return target === 'new_window'
      ? resolveAppResourceText($r('app.string.bookmark_bar_open_private'))
      : resolveAppResourceText($r('app.string.context_menu_open_private_tab_long'));
  }

  private resolvePrivateOpenEffectType(): WebContextMenuEffectType {
    return this.privateWindowPolicyService.resolveTarget() === 'new_window'
      ? 'open_private_window'
      : 'open_private_tab';
  }

  private cloneExtraItems(items: WebLinkContextMenuItem[]): WebLinkContextMenuItem[] {
    return items
      .filter((item: WebLinkContextMenuItem) => item.action === 'run_userscript' &&
        String(item.scriptId ?? '').trim().length > 0 &&
        String(item.commandId ?? '').trim().length > 0)
      .map((item: WebLinkContextMenuItem): WebLinkContextMenuItem => {
        return {
          action: item.action,
          label: item.label,
          group: 'script',
          scriptId: String(item.scriptId ?? '').trim(),
          commandId: String(item.commandId ?? '').trim()
        };
      });
  }

  private isPrivateBoundary(
    privacyMode: BrowserSessionPrivacyMode | string | undefined,
    dataScope: BrowserDataScope | string | undefined
  ): boolean {
    return String(privacyMode ?? '').trim() === 'private' ||
      String(dataScope ?? '').trim() === 'session_ephemeral';
  }

  private safeString(resolve: () => string): string {
    try {
      const value = resolve();
      return value === undefined || value === null ? '' : value.trim();
    } catch (_error) {
      return '';
    }
  }

  private safeNumber(resolve: () => number): number {
    try {
      const value = resolve();
      return Number.isFinite(value) ? value : -1;
    } catch (_error) {
      return -1;
    }
  }

  private stringifyError(error: Error): string {
    if (error.message.length > 0) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_stringifyError) {
      return resolveAppResourceText($r('app.string.settings_custom_home_unknown_error'));
    }
  }
}
