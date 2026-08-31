import { ManualElementHideRuntimeCoordinator } from '../adblock/ManualElementHideRuntimeCoordinator';
import { CustomHomepageRuntimeCoordinator } from '../customhome/CustomHomepageRuntimeCoordinator';
import { FeatureGateCoordinator } from '../membership/FeatureGateCoordinator';
import { AppProxyQuickSheetCoordinator } from '../settings/AppProxyQuickSheetCoordinator';
import { HomeShortcutStateCoordinator } from '../shortcuts/HomeShortcutStateCoordinator';
import { WebpageTranslationCoordinator } from '../translation/WebpageTranslationCoordinator';
import { ReleaseNoticePresentationCoordinator } from '../update/ReleaseNoticePresentationCoordinator';
import { BrowserUserScriptApplicationCoordinator } from '../userscripts/BrowserUserScriptApplicationCoordinator';
import {
  BrowserBottomAddressPanelBackAction,
  BrowserBottomAddressPanelBackController,
  BrowserBottomAddressPanelBackRequest
} from './BrowserBottomAddressPanelBackController';
import { BrowserBookmarkActionCoordinator } from './BrowserBookmarkActionCoordinator';
import { BrowserDownloadConfirmOverlayCoordinator } from './BrowserDownloadConfirmOverlayCoordinator';
import { BrowserKeyboardShortcutCoordinator } from './BrowserKeyboardShortcutCoordinator';
import { BrowserMediaResourceSessionCoordinator } from './BrowserMediaResourceSessionCoordinator';
import { ArticleReadingSessionOperations } from './ReaderModeCoordinator';
import { NovelReaderSessionOperations } from '../../features/novel/NovelReaderController';
import {
  BrowserShellBackAction,
  BrowserShellBackCoordinator,
  BrowserShellBackState
} from './BrowserShellBackCoordinator';
import {
  BrowserSystemBackAction,
  BrowserSystemBackCoordinator,
  BrowserSystemBackRequest
} from './BrowserSystemBackCoordinator';
import { BrowserTabCloseCoordinator } from './BrowserTabCloseCoordinator';
import { BrowserTabsOverviewSessionCoordinator } from './BrowserTabsOverviewSessionCoordinator';
import { BrowserTransientSurfaceCoordinator } from './BrowserTransientSurfaceCoordinator';
import { BrowserUnifiedLinkApplicationCoordinator } from './BrowserUnifiedLinkApplicationCoordinator';
import { BrowserWebHistoryCommandRuntimeCoordinator } from './BrowserWebHistoryCommandRuntimeCoordinator';
import { BrowserWebPageToolsCoordinator } from './BrowserWebPageToolsCoordinator';
import { BrowserWindowOpenApplicationCoordinator } from './BrowserWindowOpenApplicationCoordinator';
import { ElementInspectionSessionCoordinator } from './ElementInspectionSessionCoordinator';

export interface BrowserMainBackDependencies {
  manualElementHideRuntimeCoordinator: ManualElementHideRuntimeCoordinator;
  elementInspectionSessionCoordinator: ElementInspectionSessionCoordinator;
  webpageTranslationCoordinator: WebpageTranslationCoordinator;
  bookmarkActionCoordinator: BrowserBookmarkActionCoordinator;
  appProxyQuickSheetCoordinator: AppProxyQuickSheetCoordinator;
  webPageToolsCoordinator: BrowserWebPageToolsCoordinator;
  readerModeCoordinator: ArticleReadingSessionOperations;
  customHomepageRuntimeCoordinator: CustomHomepageRuntimeCoordinator;
  tabsOverviewSessionCoordinator: BrowserTabsOverviewSessionCoordinator;
  downloadConfirmOverlayCoordinator: BrowserDownloadConfirmOverlayCoordinator;
  mediaResourceSessionCoordinator: BrowserMediaResourceSessionCoordinator;
  userScriptApplicationCoordinator: BrowserUserScriptApplicationCoordinator;
  transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  featureGateCoordinator: FeatureGateCoordinator;
  homeShortcutStateCoordinator: HomeShortcutStateCoordinator;
  releaseNoticePresentationCoordinator: ReleaseNoticePresentationCoordinator;
  unifiedLinkApplicationCoordinator: BrowserUnifiedLinkApplicationCoordinator;
  keyboardShortcutCoordinator: BrowserKeyboardShortcutCoordinator;
  webHistoryCommandRuntimeCoordinator: BrowserWebHistoryCommandRuntimeCoordinator;
  windowOpenApplicationCoordinator: BrowserWindowOpenApplicationCoordinator;
  tabCloseCoordinator: BrowserTabCloseCoordinator;
  novelReaderSession: NovelReaderSessionOperations;
}

export interface BrowserMainBackHost {
  resolveShellBackState: () => BrowserShellBackState;
  confirmCloseReaderMode: () => void;
  resolveBottomAddressPanelBackRequest: () => BrowserBottomAddressPanelBackRequest;
  endSearchInvocation: () => void;
  collapseRootBottomPanel: () => void;
  resolveSystemBackRequest: (now: number) => BrowserSystemBackRequest;
  handleWebAppTerminalBack: (reason: string) => boolean;
  promptExit: (now: number) => void;
}

export class BrowserMainBackCoordinator {
  private readonly dependencies: BrowserMainBackDependencies;
  private shellBackCoordinator: BrowserShellBackCoordinator = new BrowserShellBackCoordinator();
  private bottomPanelBackController: BrowserBottomAddressPanelBackController =
    new BrowserBottomAddressPanelBackController();
  private systemBackCoordinator: BrowserSystemBackCoordinator = new BrowserSystemBackCoordinator();

  constructor(dependencies: BrowserMainBackDependencies) {
    this.dependencies = dependencies;
  }

  onBackPress(host: BrowserMainBackHost, now: number = Date.now()): boolean {
    const shellState = host.resolveShellBackState();
    const shellAction = this.shellBackCoordinator.resolveBackAction(shellState);
    if (shellAction !== 'pass_through' && this.handleShellBackAction(shellAction, shellState, host)) {
      return true;
    }

    const bottomPanelAction = this.bottomPanelBackController.resolveBackAction(
      host.resolveBottomAddressPanelBackRequest()
    );
    if (bottomPanelAction !== 'pass_through' && this.handleBottomPanelBackAction(bottomPanelAction, host)) {
      return true;
    }

    const systemRequest = host.resolveSystemBackRequest(now);
    return this.handleSystemBackAction(
      this.systemBackCoordinator.resolveBackAction(systemRequest),
      host,
      now,
      systemRequest
    );
  }

  private handleShellBackAction(
    action: BrowserShellBackAction,
    state: BrowserShellBackState,
    host: BrowserMainBackHost
  ): boolean {
    switch (action) {
      case 'cancel_manual_element_hide':
        this.dependencies.manualElementHideRuntimeCoordinator.handleSelectionAction('cancel');
        return true;
      case 'dismiss_translation_language_sheet':
        this.dependencies.webpageTranslationCoordinator.handleTargetLanguageAction({ type: 'dismiss' });
        return true;
      case 'handle_bookmark_folder_selection_back':
        this.dependencies.bookmarkActionCoordinator.handleFolderSelectionAction({ type: 'dismiss' });
        return true;
      case 'dismiss_app_proxy_quick_sheet':
        this.dependencies.appProxyQuickSheetCoordinator.handleAction({ type: 'dismiss' });
        return true;
      case 'handle_web_page_tools_sheet_back':
        this.dependencies.webPageToolsCoordinator.handleBack();
        return true;
      case 'close_element_inspection':
        this.dependencies.elementInspectionSessionCoordinator.handleBack();
        return true;
      case 'dismiss_reader_image_preview':
        this.dependencies.readerModeCoordinator.requestImagePreviewDismissal();
        return true;
      case 'dismiss_reader_panel':
        this.dependencies.readerModeCoordinator.requestPanelDismissal();
        return true;
      case 'confirm_close_reader_mode':
        host.confirmCloseReaderMode();
        return true;
      case 'dismiss_novel_reader_panel':
        this.dependencies.novelReaderSession.handleAction({ type: 'dismiss_panel' });
        return true;
      case 'confirm_close_novel_reader':
        this.dependencies.novelReaderSession.handleAction({ type: 'close' });
        return true;
      case 'dismiss_custom_homepage_transient':
        return this.dependencies.customHomepageRuntimeCoordinator.dispatchTransientBack();
      case 'close_tabs_overview':
        this.dependencies.tabsOverviewSessionCoordinator.handle({ type: 'dismiss_to_home' });
        return true;
      case 'cancel_download_prompt':
        if (state.downloadPromptGuid.length > 0) {
          this.dependencies.downloadConfirmOverlayCoordinator.handleAction({
            type: 'cancel',
            guid: state.downloadPromptGuid
          });
        }
        return true;
      case 'close_resource_candidates':
        this.dependencies.mediaResourceSessionCoordinator.handleResourcesOverlayAction({ type: 'close' });
        return true;
      case 'close_user_script_install_sheet':
        this.dependencies.userScriptApplicationCoordinator.closeInstallSheet();
        return true;
      case 'dismiss_user_script_page_actions':
        this.dependencies.userScriptApplicationCoordinator.handleAction({ type: 'dismiss_page_actions' });
        return true;
      case 'dismiss_wifi_qr_result':
        this.dependencies.transientSurfaceCoordinator.dismiss('wifi_qr_result');
        return true;
      case 'dismiss_feature_gate':
        this.dependencies.featureGateCoordinator.handleAction('dismiss');
        return true;
      case 'handle_home_shortcut_selection_back':
        this.dependencies.homeShortcutStateCoordinator.handleSelectionBack();
        return true;
      case 'close_desktop_login_sheet':
        this.dependencies.transientSurfaceCoordinator.closeSystemSheet();
        return true;
      case 'close_system_sheet':
        this.dependencies.transientSurfaceCoordinator.closeSystemSheet();
        return true;
      case 'acknowledge_release_notice':
        this.dependencies.releaseNoticePresentationCoordinator.handleAction('confirm');
        return true;
      case 'dismiss_external_navigation_prompt':
        this.dependencies.unifiedLinkApplicationCoordinator.handleExternalNavigationPromptAction('dismiss');
        return true;
      case 'dismiss_search_invocation':
        host.endSearchInvocation();
        return true;
      case 'pass_through':
      default:
        return false;
    }
  }

  private handleBottomPanelBackAction(
    action: BrowserBottomAddressPanelBackAction,
    host: BrowserMainBackHost
  ): boolean {
    if (action === 'pass_through') {
      return false;
    }
    host.endSearchInvocation();
    if (action === 'release_address_focus') {
      this.dependencies.keyboardShortcutCoordinator.releaseAddressFocus();
      return true;
    }
    host.collapseRootBottomPanel();
    return true;
  }

  private handleSystemBackAction(
    action: BrowserSystemBackAction,
    host: BrowserMainBackHost,
    now: number,
    systemRequest: BrowserSystemBackRequest
  ): boolean {
    switch (action) {
      case 'navigate_web_back': {
        const result = this.dependencies.webHistoryCommandRuntimeCoordinator.handleSystemBack();
        if (result.status === 'unavailable') {
          const unavailableReason = `system_back_web_unavailable:${result.reason}`;
          return this.handleTerminalWebBack(host, systemRequest, unavailableReason);
        }
        if (result.status === 'failed') {
          return true;
        }
        return true;
      }
      case 'prompt_exit':
        host.promptExit(now);
        return true;
      case 'allow_system_default':
      default:
        return false;
    }
  }

  private handleTerminalWebBack(
    host: BrowserMainBackHost,
    systemRequest: BrowserSystemBackRequest,
    reason: string
  ): boolean {
    if (this.dependencies.windowOpenApplicationCoordinator.handleActiveChildTerminalBack(reason)) {
      return true;
    }
    if (systemRequest.webAppMode) {
      return host.handleWebAppTerminalBack(reason);
    }
    void this.dependencies.tabCloseCoordinator.closeActiveTabBackToLastTabOrHome(reason);
    return true;
  }
}
