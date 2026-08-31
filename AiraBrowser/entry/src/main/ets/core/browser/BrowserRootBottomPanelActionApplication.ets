import { common } from '@kit.AbilityKit';
import {
  BrowserDataBoundaryInput,
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  BrowserThemeMode
} from '../../common/models/BrowserModels';
import { BrowserTabState, isBrowserTabTerminalBackAvailable } from '../tabs/TabManager';
import { BrowserWebPrintService } from '../../services/web/BrowserWebPrintService';
import { WebPageShareService } from '../../services/share/WebPageShareService';
import { BrowserActiveTabRuntimeRestoreCoordinator } from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';
import { ManualElementHideRuntimeCoordinator } from '../adblock/ManualElementHideRuntimeCoordinator';
import { OfflinePageSaveCoordinator } from '../offline/OfflinePageSaveCoordinator';
import { AppProxyQuickSheetCoordinator } from '../settings/AppProxyQuickSheetCoordinator';
import { WebpageTranslationCoordinator } from '../translation/WebpageTranslationCoordinator';
import { BrowserUserScriptApplicationCoordinator } from '../userscripts/BrowserUserScriptApplicationCoordinator';
import { WebAppInstallCoordinator } from '../webapps/WebAppInstallCoordinator';
import { BrowserBottomPanelActionId } from './BrowserBottomPanelActionCatalog';
import {
  BrowserBookmarkActionCoordinator,
  BrowserBookmarkFolderSelectionAction,
  BrowserBookmarkActionTarget
} from './BrowserBookmarkActionCoordinator';
import {
  BrowserFullscreenSessionCoordinator,
  BrowserFullscreenSessionPresentation
} from './BrowserFullscreenSessionCoordinator';
import { BrowserForegroundTabCreationCoordinator } from './BrowserForegroundTabCreationCoordinator';
import { BrowserMediaResourceSessionCoordinator } from './BrowserMediaResourceSessionCoordinator';
import { BrowserPageFindCoordinator } from './BrowserPageFindCoordinator';
import {
  BrowserPhonePagePushCoordinator,
  BrowserPhonePagePushHost
} from './BrowserPhonePagePushCoordinator';
import {
  BrowserRootBottomPanelActionApplication,
  BrowserRootBottomPanelActionDispatch,
  BrowserRootBottomPanelSemanticProjection,
  BrowserRootBottomPanelSemanticState,
  BrowserRootBottomPanelShellAction
} from './BrowserRootBottomPanelSessionCoordinator';
import { BrowserShellRouteCoordinator } from './BrowserShellRouteCoordinator';
import { BrowserSiteControlsRuntimeCoordinator } from './BrowserSiteControlsRuntimeCoordinator';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { ArticleReadingSessionOperations } from './ReaderModeCoordinator';
import { NovelReaderSessionOperations } from '../../features/novel/NovelReaderController';
import {
  BrowserUserReturnHomeCoordinator,
  BrowserUserReturnHomeFlowHost
} from './BrowserUserReturnHomeCoordinator';
import {
  BrowserUserAgentActionCoordinator,
  BrowserUserAgentActionPresentation
} from './BrowserUserAgentActionCoordinator';
import { BrowserWebHistoryCommandRuntimeCoordinator } from './BrowserWebHistoryCommandRuntimeCoordinator';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { AppIconResources } from '../resources/AppIconResources';
import { resolveCurrentSiteHost } from './AddressDisplayFormatter';
import { BrowserBottomAddressPanelHeaderAction } from './BrowserBottomAddressPanelViewModel';
import {
  BrowserBottomPanelActionAvailabilityInput,
  BrowserBottomPanelActionPresentationCoordinator,
  BrowserBottomPanelActionPresentationInput,
  BrowserBottomPanelActionSnapshot,
  BrowserBottomPanelActionSnapshotInput,
  BrowserBottomPanelActionSurfaceInput,
  BrowserBottomPanelActionTarget,
  BrowserBottomPanelActionTargetInput,
  BrowserRootBottomPanelActionPresentationFacts
} from './BrowserBottomPanelActionPresentationCoordinator';
import { BrowserBottomPanelActionEnablement } from './BrowserBottomPanelActionEnablement';
import { BrowserBottomPanelResponsiveState } from './BrowserBottomPanelResponsiveViewModel';
import { BrowserThemeModeCoordinator } from './BrowserThemeModeCoordinator';
import { BrowserWindowContextPort } from './BrowserWindowContextCoordinator';
import { ElementInspectionSessionCoordinator } from './ElementInspectionSessionCoordinator';
import { BrowserToolbarSlotActionState } from './BrowserToolbarCustomizationViewModel';
import {
  BrowserClipboardCopyResult,
  BrowserClipboardReadTextResult,
  BrowserClipboardService
} from '../../services/share/BrowserClipboardService';
import { extractFirstUrlFromText } from '../../common/utils/UrlUtils';
import { BrowserBottomAddressContextAction } from './BrowserBottomChromePresentationViewModel';

export interface BrowserRootBottomPanelFixedActionFacts {
  context: common.UIAbilityContext;
  tabs: BrowserTabState[];
  activeTabId: string;
  showHomePage: boolean;
  showTabsSheet: boolean;
  webPageVisible: boolean;
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  currentTitle: string;
  currentDocumentViewerPage: boolean;
  canGoBack: boolean;
  privateModeActive: boolean;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  appProxyActive: boolean;
  bookmarkActionVersion: number;
  userAgentPresentation: BrowserUserAgentActionPresentation;
  fullscreenPresentation: BrowserFullscreenSessionPresentation;
  textZoomRatio: number;
  textZoomActionVersion: number;
  themeModeActionVersion: number;
  toolbarLayoutVersion: number;
}

export interface BrowserRootBottomPanelFixedActionShell extends
  BrowserPhonePagePushHost,
  BrowserUserReturnHomeFlowHost {
  readFacts: () => BrowserRootBottomPanelFixedActionFacts;
  resolveBookmarkTarget: () => BrowserBookmarkActionTarget;
  resolveCurrentPageActionUrl: () => string;
  submitAddress: (rawInput: string) => void;
}

interface BrowserRootBottomPanelFixedActionDependencies {
  activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator;
  appProxyQuickSheetCoordinator: AppProxyQuickSheetCoordinator;
  bookmarkActionCoordinator: BrowserBookmarkActionCoordinator;
  clipboardService: BrowserClipboardService;
  foregroundTabCreationCoordinator: BrowserForegroundTabCreationCoordinator;
  fullscreenSessionCoordinator: BrowserFullscreenSessionCoordinator;
  elementInspectionSessionCoordinator: ElementInspectionSessionCoordinator;
  manualElementHideRuntimeCoordinator: ManualElementHideRuntimeCoordinator;
  mediaResourceSessionCoordinator: BrowserMediaResourceSessionCoordinator;
  offlinePageSaveCoordinator: OfflinePageSaveCoordinator;
  pageFindCoordinator: BrowserPageFindCoordinator;
  phonePagePushCoordinator: BrowserPhonePagePushCoordinator;
  readerModeCoordinator: ArticleReadingSessionOperations;
  novelReaderSession: NovelReaderSessionOperations;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  shellRouteCoordinator: BrowserShellRouteCoordinator;
  siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator;
  tabHomeCoordinator: BrowserTabHomeCoordinator;
  themeModeCoordinator: BrowserThemeModeCoordinator;
  userReturnHomeCoordinator: BrowserUserReturnHomeCoordinator;
  userAgentActionCoordinator: BrowserUserAgentActionCoordinator;
  userScriptApplicationCoordinator: BrowserUserScriptApplicationCoordinator;
  webAppInstallCoordinator: WebAppInstallCoordinator;
  webHistoryCommandRuntimeCoordinator: BrowserWebHistoryCommandRuntimeCoordinator;
  webPageShareService: WebPageShareService;
  webPrintService: BrowserWebPrintService;
  webpageTranslationCoordinator: WebpageTranslationCoordinator;
  windowContextCoordinator: BrowserWindowContextPort;
  homeUrl: string;
  newTabTitle: string;
}

export class BrowserRootBottomPanelFixedActionApplication implements BrowserRootBottomPanelActionApplication {
  private readonly dependencies: BrowserRootBottomPanelFixedActionDependencies;
  private readonly shell: BrowserRootBottomPanelFixedActionShell;
  private readonly actionPresentationCoordinator: BrowserBottomPanelActionPresentationCoordinator =
    new BrowserBottomPanelActionPresentationCoordinator();

  constructor(
    dependencies: BrowserRootBottomPanelFixedActionDependencies,
    shell: BrowserRootBottomPanelFixedActionShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
  }

  buildSemanticProjection(
    semanticState: BrowserRootBottomPanelSemanticState
  ): BrowserRootBottomPanelSemanticProjection {
    const presentationInput = this.buildActionPresentationInput(semanticState, this.shell.readFacts());
    const leadingHeaderActions =
      this.actionPresentationCoordinator.resolveLeadingHeaderActions(presentationInput);
    const trailingHeaderActions =
      this.actionPresentationCoordinator.resolveTrailingHeaderActions(presentationInput);
    return {
      scene: semanticState.scene,
      headerPresentation: semanticState.headerPresentation,
      contentPresentation: semanticState.contentPresentation,
      effectiveHome: semanticState.effectiveHome,
      effectiveWeb: semanticState.effectiveWeb,
      addressFocused: semanticState.addressFocused,
      leadingHeaderActions,
      trailingHeaderActions
    };
  }

  resolveActionSnapshot(
    semanticState: BrowserRootBottomPanelSemanticState,
    responsiveState: BrowserBottomPanelResponsiveState,
    responsiveLayoutKey: string
  ): BrowserBottomPanelActionSnapshot {
    const facts = this.shell.readFacts();
    const userAgentPresentation = facts.userAgentPresentation;
    const fullscreenPresentation = facts.fullscreenPresentation;
    const themeMode = this.dependencies.tabHomeCoordinator.resolveOptimisticThemeMode();
    const input: BrowserBottomPanelActionSnapshotInput = {
      presentation: this.buildActionPresentationFacts(facts),
      contentMode: semanticState.contentPresentation,
      addressFocused: semanticState.addressFocused,
      effectiveHomeMode: semanticState.effectiveHome,
      effectiveWebMode: semanticState.effectiveWeb,
      surface: this.buildActionSurface(facts),
      pageFindEnabled: this.resolvePageFindEnabled(facts),
      appProxyActive: facts.appProxyActive,
      bookmarkActionState: this.dependencies.bookmarkActionCoordinator.buildActionState(
        this.shell.resolveBookmarkTarget()
      ),
      bookmarkActionVersion: facts.bookmarkActionVersion,
      privateTabModeActive: facts.privateModeActive,
      desktopSiteMode: userAgentPresentation.desktopSiteMode,
      userAgentActionVersion: userAgentPresentation.desktopSiteActionVersion,
      textZoomRatio: facts.textZoomRatio,
      textZoomActionVersion: facts.textZoomActionVersion,
      userAgentPresetSettings: userAgentPresentation.settings,
      userAgentPresetActionVersion: userAgentPresentation.userAgentPresetActionVersion,
      screenOrientationMode: fullscreenPresentation.screenOrientationMode,
      screenOrientationActionVersion: fullscreenPresentation.screenOrientationActionVersion,
      themeMode,
      resolvedThemeMode: this.dependencies.themeModeCoordinator.resolveEffectiveMode(themeMode),
      themeModeIcon: this.dependencies.themeModeCoordinator.resolveMenuIcon(themeMode),
      themeModeActionVersion: facts.themeModeActionVersion,
      fullScreenModeEnabled: fullscreenPresentation.fullScreenModeEnabled,
      fullScreenModeActionVersion: fullscreenPresentation.fullScreenModeActionVersion,
      toolbarLayoutVersion: facts.toolbarLayoutVersion,
      responsiveLayoutKey,
      responsiveState
    };
    return this.actionPresentationCoordinator.resolveActionSnapshot(input);
  }

  resolveActionTarget(input: BrowserBottomPanelActionTargetInput): BrowserBottomPanelActionTarget {
    return this.actionPresentationCoordinator.resolveTarget(input);
  }

  resolveToolbarActionEnablement(actionId: BrowserBottomPanelActionId): BrowserBottomPanelActionEnablement {
    const facts = this.shell.readFacts();
    const presentation = this.buildActionPresentationFacts(facts);
    const input: BrowserBottomPanelActionAvailabilityInput = {
      surface: this.buildActionSurface(facts),
      pageFindEnabled: this.resolvePageFindEnabled(facts),
      bookmarkActionState: this.dependencies.bookmarkActionCoordinator.buildActionState(
        this.shell.resolveBookmarkTarget()
      ),
      manualElementHideEnabled: presentation.manualElementHideEnabled,
      elementInspectionEnabled: presentation.elementInspectionEnabled
    };
    return this.actionPresentationCoordinator.resolveActionEnablement(actionId, input);
  }

  resolveWebpageTranslationPromptAvailability(): boolean {
    return this.actionPresentationCoordinator.resolveWebpageTranslationPromptAvailability(
      this.buildActionSurface(this.shell.readFacts())
    );
  }

  resolveBookmarkActionAvailability(): boolean {
    return this.actionPresentationCoordinator.resolveBookmarkActionAvailability(
      this.buildActionSurface(this.shell.readFacts())
    );
  }

  setWebProtectionFeedbackPhoneChromeCompact(compact: boolean): void {
    this.dependencies.siteControlsRuntimeCoordinator.setPhoneChromeCompact(compact);
  }

  resolveToolbarSlotActions(): BrowserToolbarSlotActionState[] {
    return this.actionPresentationCoordinator.resolveToolbarSlotActions();
  }

  resolveThemeModeActionTitleForMode(mode: BrowserThemeMode): string {
    return this.actionPresentationCoordinator.resolveThemeModeActionTitleForMode(mode);
  }

  toggleCurrentPageBookmark(): void {
    this.dependencies.bookmarkActionCoordinator.toggle(this.shell.resolveBookmarkTarget());
  }

  openLargeScreenBookmark(): void {
    this.dependencies.bookmarkActionCoordinator.openAnchored(this.shell.resolveBookmarkTarget());
  }

  handleLargeScreenBookmarkAction(action: BrowserBookmarkFolderSelectionAction): void {
    this.dependencies.bookmarkActionCoordinator.handleFolderSelectionAction(action);
  }

  handleAddressContextAction(action: BrowserBottomAddressContextAction): void {
    if (action === 'copy_link') {
      void this.copyCurrentPageLink();
      return;
    }
    if (action === 'paste_authorization_failed') {
      this.shell.showToast('无法获取剪贴板临时授权，请重试。');
      return;
    }
    void this.pasteAndGo();
  }

  apply(
    dispatch: BrowserRootBottomPanelActionDispatch,
    showHomePage: boolean
  ): BrowserRootBottomPanelShellAction | undefined {
    if (dispatch.lane === 'header') {
      return this.applyHeaderAction(dispatch.actionId, showHomePage);
    }
    if (dispatch.lane === 'home') {
      return this.applyHomeAction(dispatch.actionId);
    }
    return this.applyWebAction(dispatch.actionId);
  }

  private applyHeaderAction(actionId: string, showHomePage: boolean): BrowserRootBottomPanelShellAction | undefined {
    if (actionId === 'newTab') {
      void this.dependencies.foregroundTabCreationCoordinator.createNewTab({
        initialUrl: this.dependencies.homeUrl,
        initialTitle: this.dependencies.newTabTitle,
        options: this.dependencies.windowContextCoordinator.resolveCurrentTabSessionBoundary(),
        runtimeOptions: {}
      });
      return undefined;
    }
    if (showHomePage) {
      if (actionId === 'webReload') {
        this.dependencies.tabHomeCoordinator.reloadHome();
        return undefined;
      }
      return actionId === 'openTabs' ? 'open_tabs_overview' : undefined;
    }
    switch (actionId) {
      case 'webBack':
        return 'request_browser_back';
      case 'webForward':
        this.dependencies.webHistoryCommandRuntimeCoordinator.handleRootBottomPanelWebForward();
        return undefined;
      case 'webReload':
        this.dependencies.activeTabRuntimeRestoreCoordinator.reloadActive('user_manual_reload');
        return undefined;
      case 'siteSecurity':
        this.dependencies.siteControlsRuntimeCoordinator.open('security');
        return undefined;
      case 'siteInfo':
        this.dependencies.siteControlsRuntimeCoordinator.open();
        return undefined;
      case 'copyLink':
        void this.copyCurrentPageLink();
        return undefined;
      case 'openTabs':
        return 'open_tabs_overview';
      default:
        return undefined;
    }
  }

  private applyHomeAction(actionId: BrowserBottomPanelActionId): BrowserRootBottomPanelShellAction | undefined {
    if (this.dependencies.shellRouteCoordinator.dispatchHomeRouteAction(actionId)) {
      return undefined;
    }
    switch (actionId) {
      case 'scanQr':
        return 'scan_qr';
      case 'appProxySettings':
        this.dependencies.appProxyQuickSheetCoordinator.open(this.buildCurrentBoundaryInput());
        return undefined;
      case 'newPrivateTab':
        return 'toggle_private_mode';
      case 'home':
        void this.dependencies.tabHomeCoordinator.goHome();
        return undefined;
      default:
        return undefined;
    }
  }

  private applyWebAction(actionId: BrowserBottomPanelActionId): BrowserRootBottomPanelShellAction | undefined {
    switch (actionId) {
      case 'viewerInfo':
        return 'open_document_viewer_info';
      case 'bookmark':
        this.dependencies.bookmarkActionCoordinator.toggle(this.shell.resolveBookmarkTarget());
        return undefined;
      case 'scanQr':
        return 'scan_qr';
      case 'newPrivateTab':
        return 'toggle_private_mode';
      case 'openBookmarks':
        void this.dependencies.shellRouteCoordinator.openBookmarkManagerPage();
        return undefined;
      case 'scripts':
        this.dependencies.userScriptApplicationCoordinator.handleAction({ type: 'open_page_actions' });
        return undefined;
      case 'find':
        this.openPageFind();
        return undefined;
      case 'settings':
        this.dependencies.shellRouteCoordinator.openSettingsCenterPage();
        return undefined;
      case 'appProxySettings':
        this.dependencies.appProxyQuickSheetCoordinator.open(this.buildCurrentBoundaryInput());
        return undefined;
      case 'home':
        void this.returnHomeFromWeb();
        return undefined;
      case 'share':
        this.shareCurrentPage();
        return undefined;
      case 'sendToDesktop':
        void this.dependencies.phonePagePushCoordinator.sendCurrentPageFromHost(this.shell);
        return undefined;
      case 'print':
        void this.printCurrentPage();
        return undefined;
      case 'copyLink':
        void this.copyCurrentPageLink();
        return undefined;
      case 'addToDesktop':
        void this.dependencies.webAppInstallCoordinator.begin();
        return undefined;
      case 'userAgent':
        this.dependencies.userAgentActionCoordinator.openDesktopSiteModeSheet();
        return undefined;
      case 'textZoom':
        return 'open_text_zoom';
      case 'userAgentPreset':
        this.dependencies.userAgentActionCoordinator.openUserAgentPresetSheet();
        return undefined;
      case 'screenOrientation':
        this.dependencies.fullscreenSessionCoordinator.openScreenOrientationSheet();
        return undefined;
      case 'themeMode':
        void this.dependencies.tabHomeCoordinator.toggleThemeModeFromBottomPanel();
        return undefined;
      case 'fullScreenMode':
        this.dependencies.fullscreenSessionCoordinator.toggleManualFullscreen();
        return undefined;
      case 'manualElementHide':
        this.dependencies.manualElementHideRuntimeCoordinator.startSelectionSession();
        return undefined;
      case 'elementInspection':
        this.dependencies.elementInspectionSessionCoordinator.startFromToolbar();
        return undefined;
      case 'translate':
        this.dependencies.webpageTranslationCoordinator.handleUserAction('open_panel');
        return undefined;
      case 'reader':
        void this.openReaderMode();
        return undefined;
      case 'novel':
        this.dependencies.shellRouteCoordinator.openNovelBookshelfPage();
        return undefined;
      case 'video':
        this.dependencies.mediaResourceSessionCoordinator.openResources();
        return undefined;
      case 'offline':
        this.dependencies.offlinePageSaveCoordinator.startActiveSave();
        return undefined;
      case 'savedPages':
        this.dependencies.shellRouteCoordinator.openOfflinePagesPage();
        return undefined;
      case 'downloads':
        this.dependencies.shellRouteCoordinator.openDownloadManagementPage();
        return undefined;
      case 'history':
        this.dependencies.shellRouteCoordinator.openHistoryManagerPage();
        return undefined;
      case 'siteInfo':
        this.dependencies.siteControlsRuntimeCoordinator.open();
        return undefined;
      case 'reportSite':
        return 'open_site_report';
      default:
        return undefined;
    }
  }

  private async copyCurrentPageLink(): Promise<void> {
    const result: BrowserClipboardCopyResult = await this.dependencies.clipboardService.copyText({
      value: this.shell.resolveCurrentPageActionUrl().trim(),
      emptyMessage: '当前没有可复制的网址。',
      successMessage: '链接已复制。'
    });
    this.shell.showToast(result.message);
  }

  private async pasteAndGo(): Promise<void> {
    const result: BrowserClipboardReadTextResult = await this.dependencies.clipboardService.readText({
      emptyMessage: '剪贴板中没有可打开的内容。'
    });
    if (!result.ok) {
      this.shell.showToast(result.message);
      return;
    }
    const trimmedValue = result.value.trim();
    const extractedUrl = extractFirstUrlFromText(trimmedValue);
    this.shell.submitAddress(extractedUrl.length > 0 ? extractedUrl : trimmedValue);
  }

  private buildActionPresentationFacts(
    facts: BrowserRootBottomPanelFixedActionFacts
  ): BrowserRootBottomPanelActionPresentationFacts {
    const host = resolveCurrentSiteHost(facts.currentUrl, facts.addressInput);
    const terminalBackAvailable = isBrowserTabTerminalBackAvailable(this.findActiveTab(facts));
    return {
      currentUrl: facts.currentUrl,
      addressInput: facts.addressInput,
      chromeIconTone: AppIconResources.currentChromeTone(),
      currentDocumentViewerPage: facts.currentDocumentViewerPage,
      canGoBack: facts.canGoBack || terminalBackAvailable,
      canGoForward: this.canActiveTabGoForward(facts),
      manualElementHideRuleCount: this.dependencies.manualElementHideRuntimeCoordinator.getRuleCountForHost(host),
      manualElementHideEnabled: this.dependencies.manualElementHideRuntimeCoordinator.canStartSelection(),
      elementInspectionEnabled: this.dependencies.elementInspectionSessionCoordinator.canStart(),
      privateModeActive: facts.privateModeActive
    };
  }

  private buildActionPresentationInput(
    semanticState: BrowserRootBottomPanelSemanticState,
    facts: BrowserRootBottomPanelFixedActionFacts
  ): BrowserBottomPanelActionPresentationInput {
    const presentation = this.buildActionPresentationFacts(facts);
    return {
      currentUrl: presentation.currentUrl,
      addressInput: presentation.addressInput,
      chromeIconTone: presentation.chromeIconTone,
      currentDocumentViewerPage: presentation.currentDocumentViewerPage,
      effectiveWebMode: semanticState.effectiveWeb,
      effectiveHomeMode: semanticState.effectiveHome,
      canGoBack: presentation.canGoBack,
      canGoForward: presentation.canGoForward,
      manualElementHideRuleCount: presentation.manualElementHideRuleCount,
      manualElementHideEnabled: presentation.manualElementHideEnabled,
      elementInspectionEnabled: presentation.elementInspectionEnabled,
      privateModeActive: presentation.privateModeActive
    };
  }

  private buildActionSurface(facts: BrowserRootBottomPanelFixedActionFacts): BrowserBottomPanelActionSurfaceInput {
    const activeTab = this.findActiveTab(facts);
    return {
      activeTabIsWebPage: activeTab !== undefined && !activeTab.isHome,
      webPageVisible: facts.webPageVisible,
      tabsSheetVisible: facts.showTabsSheet,
      targetUrls: this.resolveCurrentActionTarget(facts).urls
    };
  }

  private resolveCurrentActionTarget(facts: BrowserRootBottomPanelFixedActionFacts): BrowserBottomPanelActionTarget {
    return this.actionPresentationCoordinator.resolveTarget({
      currentUrl: facts.currentUrl,
      pendingWebUrl: facts.pendingWebUrl,
      addressInput: facts.addressInput,
      activeTab: this.findActiveTab(facts)
    });
  }

  private resolvePageFindEnabled(facts: BrowserRootBottomPanelFixedActionFacts): boolean {
    return this.dependencies.pageFindCoordinator.canOpen({
      tab: this.findActiveTab(facts),
      webPageVisible: facts.webPageVisible
    });
  }

  private openPageFind(): void {
    const facts = this.shell.readFacts();
    if (!this.resolvePageFindEnabled(facts)) {
      this.shell.showToast('当前页面暂不可查找');
      return;
    }
    this.dependencies.pageFindCoordinator.open(facts.activeTabId);
  }

  private async returnHomeFromWeb(): Promise<void> {
    const facts = this.shell.readFacts();
    if (facts.showHomePage || facts.showTabsSheet) {
      return;
    }
    await this.dependencies.userReturnHomeCoordinator.runFlow({
      source: 'bottom_toolbar_home',
      showHomePage: facts.showHomePage,
      showTabsSheet: facts.showTabsSheet,
      activeTab: this.findActiveTab(facts),
      activeTabId: facts.activeTabId,
      tabs: facts.tabs
    }, this.shell);
  }

  private shareCurrentPage(): void {
    const facts = this.shell.readFacts();
    const url = this.resolveCurrentActionTarget(facts).url;
    if (url.length <= 0) {
      this.shell.showToast('当前没有可分享的网址。');
      return;
    }
    const title = facts.currentTitle.length > 0 ? facts.currentTitle : url;
    this.dependencies.webPageShareService.shareWebPage(facts.context, {
      title: title,
      url: url
    }).catch((_error: Error): void => {
      this.shell.showToast('分享失败，请稍后重试。');
    });
  }

  private async printCurrentPage(): Promise<void> {
    const facts = this.shell.readFacts();
    if (!this.dependencies.webPrintService.canPrintCurrentPage({
      runtimeLifecyclePort: this.dependencies.runtimeLifecyclePort,
      showHomePage: facts.showHomePage,
      showTabsSheet: facts.showTabsSheet,
      webPageVisible: facts.webPageVisible
    })) {
      this.shell.showToast('当前页面暂时无法打印。');
      return;
    }
    const result = await this.dependencies.webPrintService.printCurrentPageFromLifecyclePort({
      runtimeLifecyclePort: this.dependencies.runtimeLifecyclePort,
      context: facts.context,
      title: facts.currentTitle,
      printBackground: true,
      onStatusMessage: (message: string): void => {
        this.shell.showToast(message);
      }
    });
    this.shell.showToast(result.message);
  }

  private async openReaderMode(): Promise<void> {
    const facts = this.shell.readFacts();
    await this.dependencies.readerModeCoordinator.openSessionFromLifecyclePort(
      this.dependencies.runtimeLifecyclePort,
      facts.webPageVisible,
      this.resolveCurrentActionTarget(facts).url,
      facts.activeTabId
    );
  }

  async openNovelModeFromCurrentPage(): Promise<void> {
    const facts = this.shell.readFacts();
    await this.dependencies.novelReaderSession.openFromLifecyclePort({
      runtimeLifecyclePort: this.dependencies.runtimeLifecyclePort,
      webPageVisible: facts.webPageVisible,
      pageUrl: this.resolveCurrentActionTarget(facts).url,
      detectedPageType: '',
      entryReason: 'manual',
      scope: {
        tabId: facts.activeTabId,
        privacyMode: facts.privacyMode,
        dataScope: facts.dataScope
      }
    });
  }

  private buildCurrentBoundaryInput(): BrowserDataBoundaryInput {
    const facts = this.shell.readFacts();
    return {
      privacyMode: facts.privacyMode,
      dataScope: facts.dataScope
    };
  }

  private findActiveTab(facts: BrowserRootBottomPanelFixedActionFacts): BrowserTabState | undefined {
    return facts.tabs.find((tab: BrowserTabState): boolean => tab.id === facts.activeTabId);
  }

  private canActiveTabGoForward(facts: BrowserRootBottomPanelFixedActionFacts): boolean {
    const activeTab = this.findActiveTab(facts);
    return activeTab !== undefined && !activeTab.isHome && activeTab.navigationIndex >= 0 &&
      activeTab.navigationIndex < activeTab.navigationHistory.length - 1;
  }

}
