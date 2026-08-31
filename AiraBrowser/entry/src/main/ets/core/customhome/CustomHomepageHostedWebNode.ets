import { BuilderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserWebAttributeModifier } from '../web/WebDefaultContextMenuModifier';
import { WebAppearancePolicy } from '../web/WebAppearancePolicy';

const CUSTOM_HOME_HOSTED_WEB_LOG_DOMAIN: number = 0x0000;
const CUSTOM_HOME_HOSTED_WEB_LOG_TAG: string = 'CustomHomeHostedWeb';
const CUSTOM_HOME_HOSTED_WEB_IDEAL_WIDTH: number = 390;
const CUSTOM_HOME_HOSTED_WEB_IDEAL_HEIGHT: number = 844;
const CUSTOM_HOMEPAGE_EMPTY_EDIT_MENU_OPTIONS: EditMenuOptions = {
  onCreateMenu: (_menuItems: Array<TextMenuItem>): Array<TextMenuItem> => [],
  onMenuItemClick: (_menuItem: TextMenuItem, _range: TextRange): boolean => true
};

type CustomHomepageHostedWebDocumentSignalKind =
  'first_meaningful_paint' |
  'page_end' |
  'load_finished';

export interface CustomHomepageHostedWebDocumentSignal {
  kind: CustomHomepageHostedWebDocumentSignalKind;
  generation: number;
}

interface CustomHomepageHostedWebCallbacks {
  onControllerAttached: (generation: number) => void;
  onOverrideUrlLoading: (request: WebResourceRequest, generation: number) => boolean;
  onLoadIntercept: (event: OnLoadInterceptEvent, generation: number) => boolean;
  onPageBegin: (event: OnPageBeginEvent, generation: number) => void;
  onPageEnd: (event: OnPageEndEvent, signal: CustomHomepageHostedWebDocumentSignal) => void;
  onFirstMeaningfulPaint: (signal: CustomHomepageHostedWebDocumentSignal) => void;
  onScroll: (event: OnScrollEvent, generation: number) => void;
  onLoadFinished: (signal: CustomHomepageHostedWebDocumentSignal) => void;
  onWindowNew: (event: OnWindowNewEvent, generation: number) => void;
  onErrorReceive: (event: OnErrorReceiveEvent, generation: number) => void;
}

export interface CustomHomepageHostedWebConfig {
  documentGeneration: number;
  componentSnapshotId: string;
  appearancePolicy: WebAppearancePolicy;
  forceEnableWebZoom: boolean;
  nativeBridge: Object;
  documentStartScripts: ScriptItem[];
  callbacks: CustomHomepageHostedWebCallbacks;
}

interface CustomHomepageHostedWebResolvedConfig extends CustomHomepageHostedWebConfig {
  controller: webview.WebviewController;
  interactionAllowed: () => boolean;
}

function isCustomHomepageInteractionAllowed(config: CustomHomepageHostedWebResolvedConfig): boolean {
  return config.interactionAllowed();
}

function logRejectedCustomHomepageInteraction(kind: string): void {
  hilog.error(
    CUSTOM_HOME_HOSTED_WEB_LOG_DOMAIN,
    CUSTOM_HOME_HOSTED_WEB_LOG_TAG,
    'policy_home_document_contract_violation reason=hidden_interaction_rejected kind=%{public}s',
    kind
  );
}

function buildCustomHomepageDocumentSignal(
  config: CustomHomepageHostedWebConfig,
  kind: CustomHomepageHostedWebDocumentSignalKind
): CustomHomepageHostedWebDocumentSignal {
  return {
    kind: kind,
    generation: Math.max(0, Math.floor(config.documentGeneration))
  };
}

function rejectCustomHomepageWindowNew(event: OnWindowNewEvent): void {
  logRejectedCustomHomepageInteraction('window_new');
  try {
    event.handler.setWebController(null);
  } catch (_error) {
  }
}

function rejectCustomHomepageFileSelector(event: OnShowFileSelectorEvent): boolean {
  logRejectedCustomHomepageInteraction('file_selector');
  try {
    event.result.handleFileList([]);
  } catch (_error) {
  }
  return true;
}

function rejectCustomHomepagePrompt(event: OnPromptEvent): boolean {
  logRejectedCustomHomepageInteraction('prompt');
  try {
    event.result.handleCancel();
  } catch (_error) {
  }
  return true;
}

function rejectCustomHomepageConfirm(event: OnConfirmEvent): boolean {
  logRejectedCustomHomepageInteraction('confirm');
  try {
    event.result.handleCancel();
  } catch (_error) {
  }
  return true;
}

function rejectCustomHomepageAlert(event: OnAlertEvent): boolean {
  logRejectedCustomHomepageInteraction('alert');
  try {
    event.result.handleConfirm();
  } catch (_error) {
  }
  return true;
}

function resolveCustomHomepageHostedWebConfig(
  config: CustomHomepageHostedWebConfig,
  controller: webview.WebviewController,
  hostedController: CustomHomepageHostedWebNodeController
): CustomHomepageHostedWebResolvedConfig {
  return {
    controller: controller,
    documentGeneration: config.documentGeneration,
    componentSnapshotId: config.componentSnapshotId,
    appearancePolicy: config.appearancePolicy,
    forceEnableWebZoom: config.forceEnableWebZoom,
    nativeBridge: config.nativeBridge,
    documentStartScripts: config.documentStartScripts,
    interactionAllowed: (): boolean => hostedController.isInteractionAllowed(),
    callbacks: {
      onControllerAttached: (generation: number): void => {
        hostedController.markWebControllerAttached();
        config.callbacks.onControllerAttached(generation);
      },
      onOverrideUrlLoading: config.callbacks.onOverrideUrlLoading,
      onLoadIntercept: config.callbacks.onLoadIntercept,
      onPageBegin: config.callbacks.onPageBegin,
      onPageEnd: config.callbacks.onPageEnd,
      onFirstMeaningfulPaint: config.callbacks.onFirstMeaningfulPaint,
      onScroll: config.callbacks.onScroll,
      onLoadFinished: config.callbacks.onLoadFinished,
      onWindowNew: config.callbacks.onWindowNew,
      onErrorReceive: config.callbacks.onErrorReceive
    }
  };
}

@Builder
function CustomHomepageHostedWebBuilder(config: CustomHomepageHostedWebResolvedConfig) {
  Stack({ alignContent: Alignment.Top }) {
    Web({
      src: '',
      controller: config.controller,
      incognitoMode: false
    })
      .id(config.componentSnapshotId)
      .width('100%')
      .height('100%')
      .keyboardAvoidMode(WebKeyboardAvoidMode.OVERLAYS_CONTENT)
      .backgroundColor(config.appearancePolicy.backgroundColor)
      .darkMode(config.appearancePolicy.darkMode)
      .forceDarkAccess(config.appearancePolicy.forceDarkAccess)
      .javaScriptAccess(true)
      .fileAccess(true)
      .domStorageAccess(true)
      .databaseAccess(true)
      .zoomAccess(true)
      .attributeModifier(new BrowserWebAttributeModifier({
        forceEnableWebZoom: config.forceEnableWebZoom,
        enableDefaultContextMenu: false
      }))
      .editMenuOptions(CUSTOM_HOMEPAGE_EMPTY_EDIT_MENU_OPTIONS)
      .imageAccess(true)
      .onlineImageAccess(true)
      .javaScriptProxy({
        object: config.nativeBridge,
        name: '__airaHomeNativeBridge',
        methodList: ['request'],
        controller: config.controller
      })
      .runJavaScriptOnDocumentStart(config.documentStartScripts)
      .multiWindowAccess(true)
      .allowWindowOpenMethod(true)
      .onControllerAttached(() => config.callbacks.onControllerAttached(config.documentGeneration))
      .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
        return config.callbacks.onOverrideUrlLoading(request, config.documentGeneration);
      })
      .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
        return config.callbacks.onLoadIntercept(event, config.documentGeneration);
      })
      .onPageBegin((event: OnPageBeginEvent): void => {
        config.callbacks.onPageBegin(event, config.documentGeneration);
      })
      .onPageEnd((event: OnPageEndEvent): void => {
        config.callbacks.onPageEnd(event, buildCustomHomepageDocumentSignal(config, 'page_end'));
      })
      .onFirstMeaningfulPaint((_paint: FirstMeaningfulPaint): void => {
        config.callbacks.onFirstMeaningfulPaint(
          buildCustomHomepageDocumentSignal(config, 'first_meaningful_paint')
        );
      })
      .onScroll((event: OnScrollEvent): void =>
        config.callbacks.onScroll(event, config.documentGeneration))
      .onLoadFinished((): void => {
        config.callbacks.onLoadFinished(buildCustomHomepageDocumentSignal(config, 'load_finished'));
      })
      .onPermissionRequest((event: OnPermissionRequestEvent): void => {
        if (!isCustomHomepageInteractionAllowed(config)) {
          logRejectedCustomHomepageInteraction('protected_resource_permission');
        }
        event.request.deny();
      })
      .onGeolocationShow((event: OnGeolocationShowEvent): void => {
        if (!isCustomHomepageInteractionAllowed(config)) {
          logRejectedCustomHomepageInteraction('geolocation_permission');
        }
        event.geolocation.invoke(event.origin, false, false);
      })
      .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => {
        return isCustomHomepageInteractionAllowed(config) ? false : rejectCustomHomepageFileSelector(event);
      })
      .onPrompt((event: OnPromptEvent): boolean => {
        return isCustomHomepageInteractionAllowed(config) ? false : rejectCustomHomepagePrompt(event);
      })
      .onConfirm((event: OnConfirmEvent): boolean => {
        return isCustomHomepageInteractionAllowed(config) ? false : rejectCustomHomepageConfirm(event);
      })
      .onAlert((event: OnAlertEvent): boolean => {
        return isCustomHomepageInteractionAllowed(config) ? false : rejectCustomHomepageAlert(event);
      })
      .onWindowNew((event: OnWindowNewEvent): void => {
        if (!isCustomHomepageInteractionAllowed(config)) {
          rejectCustomHomepageWindowNew(event);
          return;
        }
        config.callbacks.onWindowNew(event, config.documentGeneration);
      })
      .onErrorReceive((event: OnErrorReceiveEvent): void => {
        config.callbacks.onErrorReceive(event, config.documentGeneration);
      })
  }
    .width('100%')
    .height('100%')
    .backgroundColor(config.appearancePolicy.backgroundColor)
}

export class CustomHomepageHostedWebNodeController extends NodeController {
  private builderNode: BuilderNode<[CustomHomepageHostedWebResolvedConfig]> | undefined;
  private rootNode: FrameNode | null = null;
  private controller: webview.WebviewController;
  private webControllerAttached: boolean = false;
  private active: boolean = false;
  private interactionAllowed: boolean = false;
  private disposed: boolean = false;

  constructor(
    builderNode: BuilderNode<[CustomHomepageHostedWebResolvedConfig]> | undefined,
    controller: webview.WebviewController
  ) {
    super();
    this.builderNode = builderNode;
    this.controller = controller;
  }

  makeNode(_uiContext: UIContext): FrameNode | null {
    return this.rootNode;
  }

  markWebControllerAttached(): void {
    if (this.disposed) {
      return;
    }
    this.webControllerAttached = true;
  }

  setBuilderNode(builderNode: BuilderNode<[CustomHomepageHostedWebResolvedConfig]>): void {
    if (this.disposed) {
      builderNode.dispose();
      return;
    }
    this.builderNode = builderNode;
  }

  isWebControllerAttached(): boolean {
    return !this.disposed && this.webControllerAttached;
  }

  isSurfaceAttached(): boolean {
    return this.rootNode !== null;
  }

  isInteractionAllowed(): boolean {
    return this.interactionAllowed;
  }

  setInteractionAllowed(allowed: boolean): void {
    this.interactionAllowed = !this.disposed && allowed;
  }

  attachSurface(): boolean {
    if (this.disposed) {
      return false;
    }
    const frameNode = this.builderNode?.getFrameNode();
    if (frameNode === undefined || frameNode === null) {
      return false;
    }
    const parent = frameNode.getParent();
    if (parent !== null && this.rootNode !== frameNode) {
      return false;
    }
    this.rootNode = frameNode;
    this.rebuild();
    return true;
  }

  detachSurface(): void {
    if (this.rootNode === null) {
      return;
    }
    this.rootNode = null;
    this.rebuild();
  }

  activate(): void {
    if (this.disposed || !this.webControllerAttached || this.active) {
      return;
    }
    try {
      this.controller.onActive();
      this.controller.resumeAllMedia();
      this.active = true;
    } catch (error) {
      this.logWarning('activate failed', error);
    }
  }

  deactivate(): void {
    if (!this.webControllerAttached || !this.active) {
      return;
    }
    try {
      this.controller.pauseAllMedia();
      this.controller.onInactive();
      this.active = false;
    } catch (error) {
      this.logWarning('deactivate failed', error);
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.deactivate();
    this.disposed = true;
    const shouldRebuild = this.rootNode !== null;
    this.rootNode = null;
    if (shouldRebuild) {
      this.rebuild();
    }
    this.webControllerAttached = false;
    this.interactionAllowed = false;
    this.builderNode?.dispose();
    this.builderNode = undefined;
  }

  private logWarning(message: string, error: Object): void {
    hilog.warn(
      CUSTOM_HOME_HOSTED_WEB_LOG_DOMAIN,
      CUSTOM_HOME_HOSTED_WEB_LOG_TAG,
      '%{public}s: %{public}s',
      message,
      String((error as Error)?.message ?? error ?? '')
    );
  }

}

export class CustomHomepageHostedWebGeneration {
  private generation: number;
  private controller: webview.WebviewController;
  private nodeController: CustomHomepageHostedWebNodeController;

  constructor(
    generation: number,
    controller: webview.WebviewController,
    nodeController: CustomHomepageHostedWebNodeController
  ) {
    this.generation = Math.max(0, Math.floor(generation));
    this.controller = controller;
    this.nodeController = nodeController;
  }

  getGeneration(): number {
    return this.generation;
  }

  getController(): webview.WebviewController {
    return this.controller;
  }

  getNodeController(): CustomHomepageHostedWebNodeController {
    return this.nodeController;
  }

  dispose(): void {
    this.nodeController.dispose();
  }
}

export function createCustomHomepageHostedWebGeneration(
  uiContext: UIContext,
  config: CustomHomepageHostedWebConfig
): CustomHomepageHostedWebGeneration {
  const controller = new webview.WebviewController();
  const hostedController = new CustomHomepageHostedWebNodeController(undefined, controller);
  const resolvedConfig = resolveCustomHomepageHostedWebConfig(config, controller, hostedController);
  const builderNode: BuilderNode<[CustomHomepageHostedWebResolvedConfig]> = new BuilderNode(uiContext, {
    selfIdealSize: {
      width: CUSTOM_HOME_HOSTED_WEB_IDEAL_WIDTH,
      height: CUSTOM_HOME_HOSTED_WEB_IDEAL_HEIGHT
    }
  });
  builderNode.build(
    wrapBuilder<[CustomHomepageHostedWebResolvedConfig]>(CustomHomepageHostedWebBuilder),
    resolvedConfig
  );
  hostedController.setBuilderNode(builderNode);
  return new CustomHomepageHostedWebGeneration(config.documentGeneration, controller, hostedController);
}
