import { common } from '@kit.AbilityKit';
import {
  createCenteredDialogMaterial,
  showCenteredAlertDialog
} from '../common/CenteredDialogSurface';
import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import router from '@ohos.router';
import {
  OfflinePageDeleteResult,
  OfflinePageViewerInfoRow,
  OfflinePageViewerState
} from '../../../common/models/OfflinePageModels';
import { BrowserPageFindBar } from '../browser/BrowserPageFindBar';
import {
  BrowserPageFindBarAction,
  BrowserPageFindBarState,
  BrowserPageFindCoordinator,
  createBrowserPageFindClosedBarState
} from '../../../core/browser/BrowserPageFindCoordinator';
import {
  ReaderModeEffect,
  ReaderModeSessionOpenOutcome,
  ReaderModeSessionSnapshot,
  ReaderModeSessionSnapshotTransition,
  ReaderModeSpeechVoiceDialogPresentation
} from '../../../core/browser/ReaderModeCoordinator';
import {
  BrowserWindowSessionArticleReadingPort
} from '../../../core/browser/BrowserWindowSessionApplication';
import {
  BrowserWindowAvoidAreaCoordinator
} from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';
import {
  BrowserBottomAddressPanel,
  BrowserBottomAddressPanelGestureFrame
} from '../browser/BrowserBottomAddressPanel';
import { BrowserRootBottomPanelExpandedScrim } from '../browser/BrowserRootBottomPanelExpandedScrim';
import {
  BrowserBottomSheetSurface,
  BrowserModalBottomOverlay,
  BrowserSheetActionButton,
  BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS,
  BROWSER_MODAL_BOTTOM_SHEET_ENTER_OFFSET_Y,
  BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS
} from '../browser/BrowserModalBottomSheet';
import { ReaderSpeechPlayerSheet } from '../browser/ReaderSpeechPlayerScreen';
import {
  BrowserBottomAddressPanelAction,
  BrowserBottomAddressPanelActionId,
  BrowserBottomAddressPanelHeaderAction,
  BrowserBottomPanelMotionState
} from '../../../core/browser/BrowserBottomAddressPanelViewModel';
import { BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS } from '../../../core/browser/BrowserBottomPanelMotionTokens';
import { BrowserBottomBackdropViewModel } from '../../../core/browser/BrowserBottomBackdropViewModel';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BrowserBottomChromeScrollCoordinator,
  BrowserBottomChromeScrollPresentation
} from '../../../core/browser/BrowserBottomChromeScrollCoordinator';
import {
  BrowserBottomChromeGestureSource,
  BrowserBottomChromePresentation
} from '../../../core/browser/BrowserBottomChromePresentationViewModel';
import {
  BrowserBottomPanelResponsiveState,
  BrowserBottomPanelResponsiveViewModel
} from '../../../core/browser/BrowserBottomPanelResponsiveViewModel';
import { BrowserTopImmersionScrollCoordinator } from '../../../core/browser/BrowserTopImmersionScrollCoordinator';
import { HomeSearchPanelDetent } from '../../../core/browser/HomeSearchPanelDetentViewModel';
import { OfflinePageListCoordinator } from '../../../core/offline/OfflinePageListCoordinator';
import { OfflinePageOpenCoordinator } from '../../../core/offline/OfflinePageOpenCoordinator';
import {
  OfflinePageViewerBackAction,
  OfflinePageViewerBackState,
  OfflinePageViewerViewModel
} from '../../../core/offline/OfflinePageViewerViewModel';
import { ReaderModeAction } from '../../../features/reader/ReaderModeModels';
import { OfflinePageExportResult, OfflinePageExportService } from '../../../services/offline/OfflinePageExportService';
import { OfflinePageLinkActionResult, OfflinePageLinkActionService } from '../../../services/offline/OfflinePageLinkActionService';
import { OfflineReaderExtractionService } from '../../../services/reader/OfflineReaderExtractionService';
import { BrowserThemePaletteService } from '../../../services/theme/BrowserThemePaletteService';
import { BrowserStatusBarStyleService } from '../../../services/browser/BrowserStatusBarStyleService';
import {
  buildWebAppearanceDocumentStartScript,
  buildWebAppearanceDocumentStartScriptItem,
  resolveWebAppearancePolicy,
  resolveWebAppearancePolicyForTheme,
  WebAppearancePolicy
} from '../../../core/web/WebAppearancePolicy';
import {
  sharedBrowserThemeModeCoordinator,
  sharedOfflinePageRepository,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  requestBrowserShellIntent,
  requestOpenBrowserUrlWithRouteParams
} from '../../../core/navigation/BrowserNativeNavigationRequestCenter';
import {
  BOOKMARK_MANAGER_ROUTE,
  BROWSER_SHELL_ROUTE
} from '../../router/AppRoutes';
import { ReaderModeOverlay } from '../browser/ReaderModeOverlay';
import { ReaderSpeechVoiceDialog } from '../browser/ReaderSpeechVoiceDialog';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';

const OFFLINE_PAGE_FIND_TAB_ID: string = 'offline-page-viewer';
const OFFLINE_PAGE_FIND_BAR_TOP_MARGIN: number = 74;
const OFFLINE_PAGE_TOP_FIXED_SAFETY_HEIGHT: number = 4;
const OFFLINE_READER_MODE_LOAD_SETTLE_DELAY_MS: number = 160;
const OFFLINE_READER_SPEECH_PLAYER_OVERLAY_Z_INDEX: number = 170;
const OFFLINE_READER_SPEECH_PLAYER_OVERLAY_SHEET_HEIGHT: Length = '76%';
@Component
export struct OfflinePageViewerScreen {
  @Prop pageId: string = '';
  @Prop dataScope: string = 'profile_persistent';
  @Prop privacyMode: string = 'regular';
  @Prop backRequestAction: OfflinePageViewerBackAction = 'route_back';
  @Prop
  @Watch('syncBackRequest')
  backRequestVersion: number = 0;
  onBackStateChange: (state: OfflinePageViewerBackState) => void = (_state: OfflinePageViewerBackState) => {};
  private webController: webview.WebviewController = new webview.WebviewController();
  private windowAvoidAreaCoordinator: BrowserWindowAvoidAreaCoordinator = new BrowserWindowAvoidAreaCoordinator();
  private pageFindCoordinator: BrowserPageFindCoordinator = new BrowserPageFindCoordinator({
    resolveController: (_tabId: string): webview.WebviewController | undefined => this.webController,
    isControllerAttached: (_tabId: string): boolean => this.webControllerAttached,
    publishBarState: (_tabId: string, state: BrowserPageFindBarState): void => {
      this.pageFindBarState = state;
    }
  });
  private articleReadingSession: BrowserWindowSessionArticleReadingPort =
    new BrowserWindowSessionArticleReadingPort();
  private offlineReaderExtractionService: OfflineReaderExtractionService = new OfflineReaderExtractionService();
  private readerSpeechVoiceDialogController: CustomDialogController = new CustomDialogController({
    builder: ReaderSpeechVoiceDialog({
      presentation: $readerSpeechVoiceDialogPresentation,
      onSelectVoiceId: (voiceId: string) => {
        void this.articleReadingSession.selectSpeechVoiceById(voiceId);
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true
  });
  private exportService: OfflinePageExportService = new OfflinePageExportService(sharedOfflinePageRepository);
  private openCoordinator: OfflinePageOpenCoordinator = new OfflinePageOpenCoordinator({
    repository: sharedOfflinePageRepository
  });
  private viewerViewModel: OfflinePageViewerViewModel = new OfflinePageViewerViewModel();
  private themePaletteService: BrowserThemePaletteService = new BrowserThemePaletteService();
  private statusBarStyleService: BrowserStatusBarStyleService = new BrowserStatusBarStyleService();
  private bottomChromeScrollCoordinator: BrowserBottomChromeScrollCoordinator =
    new BrowserBottomChromeScrollCoordinator();
  private bottomPanelResponsiveViewModel: BrowserBottomPanelResponsiveViewModel =
    new BrowserBottomPanelResponsiveViewModel();
  private bottomBackdropViewModel: BrowserBottomBackdropViewModel =
    new BrowserBottomBackdropViewModel();
  private topImmersionScrollCoordinator: BrowserTopImmersionScrollCoordinator =
    new BrowserTopImmersionScrollCoordinator();
  private listCoordinator: OfflinePageListCoordinator = new OfflinePageListCoordinator({
    repository: sharedOfflinePageRepository
  });
  private linkActionService: OfflinePageLinkActionService = new OfflinePageLinkActionService();

  @State @Watch('incrementOfflineToolbarActionRevision')
  viewerState: OfflinePageViewerState = this.openCoordinator.buildLoadingState('');
  @State offlineHtmlLoadRequested: boolean = false;
  @State loadedIntoWeb: boolean = false;
  @State webControllerAttached: boolean = false;
  @State pageFindBarState: BrowserPageFindBarState = createBrowserPageFindClosedBarState();
  @State readerModeSessionSnapshot: ReaderModeSessionSnapshot = this.articleReadingSession.getSessionSnapshot();
  @State readerSpeechVoiceDialogPresentation: ReaderModeSpeechVoiceDialogPresentation =
    this.readerModeSessionSnapshot.speech.voiceDialog;
  @State showReaderSpeechPlayerSheet: boolean = false;
  @State readerSpeechPlayerSheetVisible: boolean = false;
  @State detailsSheetVisible: boolean = false;
  @State bottomPanelDetent: HomeSearchPanelDetent = 'low';
  @State bottomChromeScrollPresentation: BrowserBottomChromeScrollPresentation = 'resting';
  @State bottomChromeReturnHomeDrag: boolean = false;
  @State bottomChromeReturnHomeProgress: number = 0;
  @State rootViewportWidth: number = 390;
  @State rootViewportHeight: number = 844;
  @State themedPageBackground: string = '#F0F2F4';
  @State themedPanelBackground: string = '#FFFFFF';
  @State themedControlBackground: string = '#E9EDF2';
  @State themedPressedBackground: string = '#DDE5EF';
  @State themedAccentColor: string = '#0A59F7';
  @State themedTextPrimaryColor: string = '#111827';
  @State themedTextSecondaryColor: string = '#667085';
  @State offlineWebAppearancePolicy: WebAppearancePolicy = resolveWebAppearancePolicy();
  @State themePreferencesListenerKey: string = '';
  @State statusBarVisible: boolean = true;
  @State bottomBackdropProgress: number = 0;
  @State private offlineToolbarActionRevision: number = 1;
  @State private offlineToolbarLayoutRevision: number = 1;
  private offlineWebScrollY: number = 0;
  private statusBarVisibilityTask: Promise<void> = Promise.resolve();
  private bottomBackdropPreviousPanelHeight: number = -1;
  private bottomBackdropExpandedHeight: number = 0;
  private bottomBackdropSettleRunId: number = 0;
  private readerSpeechPlayerOpenTimer: number = -1;
  private readerSpeechPlayerOverlayGeneration: number = 0;

  aboutToAppear(): void {
    this.articleReadingSession.connect(
      BrowserWindowRuntime.connectArticleReadingSession(this.getSharedStageStorage())
    );
    this.readerModeSessionSnapshot = this.articleReadingSession.getSessionSnapshot();
    this.viewerState = this.openCoordinator.buildLoadingState(this.pageId);
    this.refreshThemeTokens();
    this.syncOfflineStatusBarContentStyle();
    this.bindThemePreferencesUpdates();
    this.bindReaderModeSession();
    this.articleReadingSession.loadPreferences();
    this.notifyBackStateChange();
    this.loadOfflinePage();
  }

  aboutToDisappear(): void {
    this.pageFindCoordinator.close(OFFLINE_PAGE_FIND_TAB_ID);
    this.unbindThemePreferencesUpdates();
    this.restoreOfflineChrome('offline-disappear');
    this.statusBarStyleService.restoreDefaultStyle(getContext(this) as common.UIAbilityContext);
    this.resetReaderSpeechPlayerPresentation();
    this.articleReadingSession.shutdownSpeechSession();
    this.articleReadingSession.disconnect();
  }

  build() {
    RelativeContainer() {
      Column() {
        this.buildOfflineWebViewport()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.themedPageBackground)
      .alignRules({
        top: { anchor: '__container__', align: VerticalAlign.Top },
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
        left: { anchor: '__container__', align: HorizontalAlign.Start },
        right: { anchor: '__container__', align: HorizontalAlign.End }
      })

      this.buildExpandedScrim()

      if (this.pageFindBarState.visible && this.viewerState.canOpen) {
        Column() {
          this.buildPageFindOverlay()
        }
        .width('100%')
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start },
          right: { anchor: '__container__', align: HorizontalAlign.End }
        })
        .zIndex(20)
      }

      Column() {
        this.buildBottomPanel()
      }
      .width('100%')
      .height(this.resolveOfflineViewportHostHeight())
      .alignRules({
        bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
        left: { anchor: '__container__', align: HorizontalAlign.Start },
        right: { anchor: '__container__', align: HorizontalAlign.End }
      })
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(10)

      if (this.readerModeSessionSnapshot.state.visible) {
        this.buildReaderModeOverlay()
      }

      if (this.showReaderSpeechPlayerSheet) {
        this.buildReaderSpeechPlayerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themedPageBackground)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const nextWidth = Math.max(1, Math.round(Number(newArea.width)));
      const nextHeight = Math.max(1, Math.round(Number(newArea.height)));
      if (nextWidth === this.rootViewportWidth && nextHeight === this.rootViewportHeight) {
        return;
      }
      this.rootViewportWidth = nextWidth;
      this.rootViewportHeight = nextHeight;
      this.offlineToolbarLayoutRevision += 1;
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.detailsSheetVisible, this.buildDetailsSheet(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.detailsSheetVisible = false;
      }
    })
  }

  @Builder
  private buildOfflineWebViewport() {
    Column({ space: 0 }) {
      Blank()
        .width('100%')
        .height(this.getOfflineWebViewportLayoutTopInsetPx())

      Stack() {
        if (this.viewerState.loading || !this.viewerState.canOpen) {
          this.buildStatus(this.viewerState.message)
        } else {
          this.buildOfflineWeb()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .clip(true)
    }
  }

  @Builder
  private buildOfflineWeb() {
    Web({ src: '', controller: this.webController })
      .width('100%')
      .height('100%')
      .backgroundColor(this.offlineWebAppearancePolicy.backgroundColor)
      .darkMode(this.offlineWebAppearancePolicy.darkMode)
      .forceDarkAccess(this.offlineWebAppearancePolicy.forceDarkAccess)
      .javaScriptAccess(true)
      .domStorageAccess(false)
      .runJavaScriptOnDocumentStart([buildWebAppearanceDocumentStartScriptItem(this.offlineWebAppearancePolicy)])
      .onScroll((event: OnScrollEvent) => {
        this.handleOfflineWebScroll(event);
      })
      .onControllerAttached(() => {
        this.webControllerAttached = true;
        this.pageFindCoordinator.handleControllerAttached(OFFLINE_PAGE_FIND_TAB_ID);
        this.loadHtmlIntoWeb();
      })
      .onPageBegin((_event: OnPageBeginEvent) => {
        this.loadedIntoWeb = false;
        this.restoreOfflineChrome('offline-page-begin');
        this.pageFindCoordinator.handlePageBegin(OFFLINE_PAGE_FIND_TAB_ID);
      })
      .onPageEnd(() => {
        this.loadedIntoWeb = true;
        this.applyOfflineWebAppearanceBootstrap();
      })
      .onLoadFinished(() => {
        this.loadedIntoWeb = true;
        this.pageFindCoordinator.handleLoadFinished(OFFLINE_PAGE_FIND_TAB_ID);
        this.applyOfflineWebAppearanceBootstrap();
      })
      .onTouch((event: TouchEvent) => {
        this.handleOfflineWebTouch(event);
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (!event.request.isMainFrame()) {
          return;
        }
        this.offlineHtmlLoadRequested = false;
        this.loadedIntoWeb = false;
        this.viewerState = this.openCoordinator.buildFailureState(
          this.pageId,
          this.buildWebLoadErrorMessage(event)
        );
      })
      .onSearchResultReceive((event: OnSearchResultReceiveEvent) => {
        this.pageFindCoordinator.handleSearchResult(OFFLINE_PAGE_FIND_TAB_ID, event);
      })
      .onAppear(() => {
        this.loadHtmlIntoWeb();
      })
  }

  @Builder
  private buildBottomPanel() {
    BrowserBottomAddressPanel({
      panelMotionState: this.buildOfflineBottomPanelMotionState(),
      bottomChromePresentation: this.buildOfflineBottomChromePresentation(),
      privateMode: false,
      addressEditable: false,
      primaryActionOverrides: this.buildOfflinePrimaryActions(),
      secondaryActionOverrides: this.buildOfflineSecondaryActions(),
      quickActionsOnly: true,
      responsiveState: this.buildOfflineBottomPanelResponsiveState(),
      toolbarActionRevision: this.offlineToolbarActionRevision,
      toolbarLayoutRevision: this.offlineToolbarLayoutRevision,
      activeDownloadIndicatorEnabled: false,
      onPanelDetentChange: (detent: HomeSearchPanelDetent) => {
        this.bottomPanelDetent = detent;
        this.bottomChromeScrollPresentation = 'resting';
        this.playBottomBackdropSettle(detent);
        this.notifyBackStateChange();
        if (detent !== 'peek') {
          this.restoreOfflineChrome('bottom-panel-detent');
        }
      },
      onPanelGestureFrame: (frame: BrowserBottomAddressPanelGestureFrame) => {
        this.handleBottomPanelGestureFrame(frame);
      },
      onPanelVisualHeightChange: (panelHeight: number, expandedHeight: number) => {
        this.updateBottomBackdropVisualHeight(panelHeight, expandedHeight);
      },
      onPanelDragEnd: (_panelHeight: number, targetDetent: HomeSearchPanelDetent) => {
        this.resetOfflineBottomChromeGesture();
        this.playBottomBackdropSettle(targetDetent);
      },
      onPanelDragEndIntercept: (
        _panelHeight: number,
        _targetDetent: HomeSearchPanelDetent,
        offsetY: number,
        source: BrowserBottomChromeGestureSource
      ): HomeSearchPanelDetent | undefined =>
        this.interceptOfflineBottomChromeGestureEnd(source, offsetY) ? 'low' : undefined,
      onAddressFocusStateChange: (_focused: boolean) => {},
      onAddressChange: (_value: string) => {},
      onAddressSubmit: (_rawInput: string) => {},
      onHeaderAction: (actionId: string) => {
        this.dispatchOfflineHeaderAction(actionId);
      },
      onAction: (actionId: BrowserBottomAddressPanelActionId) => {
        this.dispatchOfflinePanelAction(actionId);
      }
    })
  }

  @Builder
  private buildStatus(message: string) {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.doc_text_fill'))
        .fontSize(38)
        .fontColor([this.themedTextSecondaryColor])
      Text(message)
        .fontSize(15)
        .fontColor(this.themedTextSecondaryColor)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 28, right: 28 })
  }

  @Builder
  private buildPageFindOverlay() {
    Column() {
      BrowserPageFindBar({
        state: this.pageFindBarState,
        onAction: (action: BrowserPageFindBarAction) => {
          this.handlePageFindBarAction(action);
        }
      })
    }
    .width('100%')
    .margin({ top: OFFLINE_PAGE_FIND_BAR_TOP_MARGIN })
    .zIndex(20)
  }

  @Builder
  private buildDetailsSheet() {
    BrowserBottomSheetSurface({ surfaceColor: this.themedPanelBackground }) {
      Column({ space: 16 }) {
        Column({ space: 4 }) {
          Text('离线网页详情')
            .width('100%')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themedTextPrimaryColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.viewerState.siteName.length > 0 ? this.viewerState.siteName : this.viewerState.host)
            .width('100%')
            .fontSize(14)
            .fontColor(this.themedTextSecondaryColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 8 }) {
          ForEach(this.viewerViewModel.buildInfoRows(this.viewerState), (row: OfflinePageViewerInfoRow) => {
            this.buildDetailsInfoRow(row)
          }, (row: OfflinePageViewerInfoRow) => row.label)
        }
        .width('100%')

        Row({ space: 10 }) {
          BrowserSheetActionButton({
            label: '打开原网页',
            actionEnabled: this.resolveOriginalPageUrl().length > 0,
            accentColor: this.themedAccentColor,
            onAction: () => {
              this.detailsSheetVisible = false;
              this.openOriginalPage();
            }
          })

          BrowserSheetActionButton({
            label: '复制链接',
            actionEnabled: this.resolveOriginalPageUrl().length > 0,
            accentColor: this.themedAccentColor,
            onAction: () => {
              this.detailsSheetVisible = false;
              this.copyOriginalUrl();
            }
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private buildDetailsInfoRow(row: OfflinePageViewerInfoRow) {
    Row({ space: 14 }) {
      Text(row.label)
        .width(72)
        .fontSize(14)
        .fontColor(this.themedTextSecondaryColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(row.value.length > 0 ? row.value : '暂无')
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(this.themedTextPrimaryColor)
        .maxLines(row.label === '原网页' ? 2 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  private buildReaderModeOverlay() {
    ReaderModeOverlay({
      state: this.readerModeSessionSnapshot.state,
      presentationMode: this.readerModeSessionSnapshot.reading.presentationMode,
      topSafeInsetVp: this.getOfflineWebViewportLayoutTopInsetPx(),
      bottomSafeInsetVp: 0,
      globalImmersionEnabled: sharedPreferencesRepository.getPreferences().appearance.globalImmersionEnabled,
      alwaysTopImmersionEnabled: sharedPreferencesRepository.getPreferences().appearance.alwaysTopImmersionEnabled,
      statusBarVisible: this.statusBarVisible,
      dismissImagePreviewRequestVersion:
        this.readerModeSessionSnapshot.overlayBackState.dismissImagePreviewRequestVersion,
      dismissPanelRequestVersion:
        this.readerModeSessionSnapshot.overlayBackState.dismissPanelRequestVersion,
      onAction: (action: ReaderModeAction) => {
        this.handleReaderModeAction(action);
      }
    })
  }

  private handleReaderModeAction(action: ReaderModeAction): void {
    this.articleReadingSession.handleAction(action, {
      fallbackTitle: this.viewerState.title,
      fallbackUrl: this.resolveOriginalPageUrl()
    });
  }

  private bindReaderModeSession(): void {
    this.articleReadingSession.connectSessionListener({
      onSnapshotChanged: (
        snapshot: ReaderModeSessionSnapshot,
        _transition: ReaderModeSessionSnapshotTransition
      ): void => {
        this.applyReaderModeSessionSnapshot(snapshot);
      },
      onEffect: (effect: ReaderModeEffect): void => {
        this.handleReaderModeEffect(effect);
      }
    });
  }

  private applyReaderModeSessionSnapshot(snapshot: ReaderModeSessionSnapshot): void {
    const backStateChanged =
      this.readerModeSessionSnapshot.state.visible !== snapshot.state.visible ||
      this.readerModeSessionSnapshot.overlayBackState.imagePreviewVisible !==
      snapshot.overlayBackState.imagePreviewVisible ||
      this.readerModeSessionSnapshot.overlayBackState.panelVisible !== snapshot.overlayBackState.panelVisible;
    this.readerModeSessionSnapshot = snapshot;
    this.readerSpeechVoiceDialogPresentation = snapshot.speech.voiceDialog;
    if (backStateChanged) {
      this.notifyBackStateChange();
    }
  }

  private handleReaderModeEffect(effect: ReaderModeEffect): void {
    switch (effect.type) {
      case 'toast':
        this.showToast(effect.message);
        return;
      case 'copy_link':
        this.copyOriginalUrl(effect.url);
        return;
      case 'share':
        this.shareOriginalUrl(effect.title, effect.url);
        return;
      case 'bookmark':
        this.showToast('离线阅读模式暂不支持加入书签');
        return;
      case 'open_bookmarks':
        this.openBookmarkManager();
        return;
      case 'open_link':
        this.openReaderModeLink(effect.url);
        return;
      case 'sync_status_bar_style':
        this.syncOfflineStatusBarContentStyle();
        return;
      case 'present_speech_player':
        this.presentReaderSpeechPlayer();
        return;
      case 'dismiss_speech_player':
        this.closeReaderSpeechPlayer();
        return;
      case 'reset_speech_player_presentation':
        this.resetReaderSpeechPlayerPresentation();
        return;
      case 'restore_status_bar':
        this.restoreOfflineChrome(effect.source);
        return;
      case 'status_bar_visibility':
        this.setOfflineStatusBarVisible(effect.visible, effect.source);
        return;
      case 'record_diagnostic':
        hilog.info(
          0x0000,
          'OfflinePageViewer',
          'Reader diagnostic %{public}s %{public}s',
          effect.diagnosticEvent,
          effect.diagnosticText
        );
        return;
    }
  }

  @Builder
  private buildReaderSpeechPlayerOverlay() {
    BrowserModalBottomOverlay({
      visible: this.readerSpeechPlayerSheetVisible,
      sheetHeight: OFFLINE_READER_SPEECH_PLAYER_OVERLAY_SHEET_HEIGHT,
      enterOffsetY: BROWSER_MODAL_BOTTOM_SHEET_ENTER_OFFSET_Y,
      animationDurationMs: BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS,
      zIndexValue: OFFLINE_READER_SPEECH_PLAYER_OVERLAY_Z_INDEX,
      onDismiss: () => {
        this.closeReaderSpeechPlayer();
      }
    }) {
      ReaderSpeechPlayerSheet({
        article: this.readerModeSessionSnapshot.state.article,
        chunks: this.readerModeSessionSnapshot.speech.chunks,
        speechState: this.readerModeSessionSnapshot.speech.state,
        readerTheme: this.articleReadingSession.resolveEffectiveTheme(
          sharedBrowserThemeModeCoordinator.resolveEffectiveMode('system')
        ),
        speed: this.readerModeSessionSnapshot.speech.speed,
        voiceLabel: this.readerModeSessionSnapshot.speech.voiceLabel,
        bottomSafeInsetVp: 0,
        onClose: () => {
          this.closeReaderSpeechPlayer();
        },
        onToggleSpeech: () => {
          void this.articleReadingSession.toggleSpeech();
        },
        onPreviousChunk: () => {
          void this.articleReadingSession.playPreviousSpeechChunk();
        },
        onNextChunk: () => {
          void this.articleReadingSession.playNextSpeechChunk();
        },
        onReplayChunk: () => {
          void this.articleReadingSession.replayCurrentSpeechChunk();
        },
        onLocateInReader: () => {
          this.articleReadingSession.locateSpeechChunkInReader();
        },
        onSpeedChange: (speed: number) => {
          void this.articleReadingSession.changeSpeechSpeed(speed);
        },
        onOpenVoicePicker: () => {
          this.openReaderSpeechVoiceDialog();
        }
      })
    }
  }

  private resolveOfflinePanelTitle(): string {
    const title = this.viewerState.title.trim();
    if (title.length > 0) {
      return title;
    }
    const siteName = this.viewerState.siteName.trim();
    if (siteName.length > 0) {
      return `${siteName} · 离线副本`;
    }
    return '离线副本';
  }

  private buildOfflineBottomChromePresentation(): BrowserBottomChromePresentation {
    return this.viewerViewModel.buildBottomChromePresentation({
      currentDetent: this.bottomPanelDetent,
      scrollPresentation: this.bottomChromeScrollPresentation,
      returnHomeDrag: this.bottomChromeReturnHomeDrag,
      returnHomeProgress: this.bottomChromeReturnHomeProgress,
      responsiveState: this.buildOfflineBottomPanelResponsiveState(),
      panelExpansionEnabled: this.buildOfflineBottomPanelMotionState().panelExpansionEnabled,
      addressInput: this.resolveOriginalPageUrl(),
      addressDisplayText: this.resolveOfflinePanelTitle(),
      placeholder: '离线副本',
      leadingHeaderActions: this.buildOfflineLeadingHeaderActions(),
      trailingHeaderActions: this.buildOfflineTrailingHeaderActions()
    });
  }

  private buildOfflineLeadingHeaderActions(): BrowserBottomAddressPanelHeaderAction[] {
    return [
      this.buildOfflineHeaderAction('offlineBack', '返回列表', $r('sys.symbol.chevron_left'), true, '',
        'browser.toolbar.back')
    ];
  }

  private buildOfflineTrailingHeaderActions(): BrowserBottomAddressPanelHeaderAction[] {
    return [
      this.buildOfflineHeaderAction('offlineReload', '刷新', $r('sys.symbol.arrow_clockwise'), true, '',
        'browser.toolbar.refresh'),
      this.buildOfflineHeaderAction('offlineTabs', '标签页', $r('sys.symbol.rectangle_on_rectangle_fill'), true, '',
        'browser.toolbar.tabs')
    ];
  }

  private buildOfflineHeaderAction(
    id: string,
    title: string,
    icon: Resource,
    enabled: boolean,
    disabledMessage: string,
    airaIconId: AiraRenderableIconId
  ): BrowserBottomAddressPanelHeaderAction {
    return {
      id,
      title,
      icon,
      airaIconId,
      enabled,
      disabledMessage,
      triggerPolicy: 'enabledState'
    };
  }

  private refreshThemeTokens(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    const resolvedThemeMode = sharedBrowserThemeModeCoordinator.resolveEffectiveMode(preferences.themeMode);
    const tokens = this.themePaletteService.resolveTokens(
      preferences.appearance.themePaletteId,
      resolvedThemeMode
    );
    this.themedPageBackground = tokens.pageBackground;
    this.themedPanelBackground = tokens.floatingSurface;
    this.themedControlBackground = tokens.controlBackground;
    this.themedPressedBackground = tokens.pressedBackground;
    this.themedAccentColor = tokens.accent;
    this.themedTextPrimaryColor = tokens.textPrimary;
    this.themedTextSecondaryColor = tokens.textSecondary;
    this.offlineWebAppearancePolicy = this.buildOfflineWebAppearancePolicy();
    this.syncOfflineStatusBarContentStyle();
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((_preferences, scope) => {
      if (scope === 'theme_mode' || scope === 'appearance') {
        this.refreshThemeTokens();
        this.applyOfflineWebAppearanceBootstrap();
      }
    });
  }

  private unbindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length <= 0) {
      return;
    }
    sharedPreferencesRepository.unsubscribe(this.themePreferencesListenerKey);
    this.themePreferencesListenerKey = '';
  }

  private buildOfflinePrimaryActions(): BrowserBottomAddressPanelAction[] {
    return [
      {
        id: 'openOriginal',
        title: '打开原网页',
        trailingText: '在线',
        icon: $r('sys.symbol.link'),
        airaIconId: 'offline.openOriginal',
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'find',
        title: '查找网页',
        trailingText: '搜索',
        icon: $r('sys.symbol.magnifyingglass'),
        airaIconId: 'settings.search',
        enabled: true,
        disabledMessage: '页面暂不可查找'
      },
      {
        id: 'reader',
        title: '阅读模式',
        trailingText: '阅读视图',
        icon: $r('sys.symbol.doc_text_fill'),
        airaIconId: 'browser.toolbar.reader',
        enabled: true,
        disabledMessage: '离线页面暂不可阅读'
      },
      {
        id: 'details',
        title: '页面详情',
        trailingText: '信息',
        icon: $r('sys.symbol.doc_text_fill'),
        airaIconId: 'browser.toolbar.siteInfo',
        enabled: true,
        disabledMessage: '离线页面详情不可用'
      },
      {
        id: 'copyLink',
        title: '复制链接',
        trailingText: '链接',
        icon: $r('sys.symbol.link'),
        airaIconId: 'browser.toolbar.copyLink',
        enabled: true,
        disabledMessage: ''
      }
    ];
  }

  private buildOfflineSecondaryActions(): BrowserBottomAddressPanelAction[] {
    return [
      {
        id: 'home',
        title: '返回列表',
        trailingText: '离线页',
        icon: $r('sys.symbol.chevron_left'),
        airaIconId: 'browser.toolbar.back',
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'share',
        title: '分享原网页链接',
        trailingText: '发送',
        icon: $r('sys.symbol.arrow_up'),
        airaIconId: 'browser.toolbar.sharePage',
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'exportPage',
        title: '导出网页',
        trailingText: 'HTML',
        icon: $r('sys.symbol.download_fill'),
        airaIconId: 'settings.downloads',
        enabled: this.viewerState.canOpen,
        disabledMessage: '当前离线页面不可导出'
      },
      {
        id: 'deletePage',
        title: '删除离线页面',
        trailingText: '删除',
        icon: $r('sys.symbol.trash_fill'),
        airaIconId: 'browser.tabs.delete',
        enabled: true,
        disabledMessage: '当前离线页面不可删除'
      },
      {
        id: 'openBookmarks',
        title: '进入书签',
        trailingText: '收藏',
        icon: $r('sys.symbol.bookmark'),
        airaIconId: 'browser.shortcut.bookmarks',
        enabled: true,
        disabledMessage: ''
      }
    ];
  }

  private dispatchOfflinePanelAction(actionId: BrowserBottomAddressPanelActionId): void {
    this.collapseOfflineBottomPanelForAction();
    if (actionId === 'openOriginal') {
      this.openOriginalPage();
      return;
    }
    if (actionId === 'find') {
      this.openPageFind();
      return;
    }
    if (actionId === 'details') {
      this.openDetailsSheet();
      return;
    }
    if (actionId === 'reader') {
      void this.openReaderMode();
      return;
    }
    if (actionId === 'copyLink') {
      this.copyOriginalUrl();
      return;
    }
    if (actionId === 'share') {
      this.shareOriginalUrl();
      return;
    }
    if (actionId === 'exportPage') {
      this.exportOfflinePage();
      return;
    }
    if (actionId === 'deletePage') {
      this.confirmDeleteCurrentPage();
      return;
    }
    if (actionId === 'home') {
      router.back();
      return;
    }
    if (actionId === 'openBookmarks') {
      this.openBookmarkManager();
    }
  }

  private dispatchOfflineHeaderAction(actionId: string): void {
    this.collapseOfflineBottomPanelForAction();
    if (actionId === 'offlineBack') {
      router.back();
      return;
    }
    if (actionId === 'offlineReload') {
      this.reloadOfflinePage();
      return;
    }
    if (actionId === 'bottomChromeMenu') {
      this.bottomPanelDetent = this.viewerViewModel.resolveBottomChromeMenuDetent(this.bottomPanelDetent);
      this.bottomChromeScrollPresentation = 'resting';
      return;
    }
    if (actionId === 'offlineTabs') {
      requestBrowserShellIntent('open_tabs_overview');
      router.back();
    }
  }

  private collapseOfflineBottomPanelForAction(): void {
    if (this.bottomPanelDetent !== 'middle') {
      return;
    }
    this.bottomPanelDetent = 'low';
    this.playBottomBackdropSettle('low');
    this.notifyBackStateChange();
  }

  private syncBackRequest(): void {
    if (this.backRequestVersion <= 0) {
      return;
    }
    if (this.backRequestAction === 'dismiss_reader_image_preview') {
      this.articleReadingSession.requestImagePreviewDismissal();
      return;
    }
    if (this.backRequestAction === 'dismiss_reader_panel') {
      this.articleReadingSession.requestPanelDismissal();
      return;
    }
    if (this.backRequestAction === 'close_reader_mode') {
      this.articleReadingSession.closeSession();
      return;
    }
    if (this.backRequestAction === 'collapse_offline_bottom_panel') {
      this.bottomPanelDetent = 'low';
      this.playBottomBackdropSettle('low');
      this.restoreOfflineChrome('system-back');
      this.notifyBackStateChange();
    }
  }

  private notifyBackStateChange(): void {
    this.onBackStateChange({
      readerModeVisible: this.readerModeSessionSnapshot.state.visible,
      readerImagePreviewVisible: this.readerModeSessionSnapshot.overlayBackState.imagePreviewVisible,
      readerPanelVisible: this.readerModeSessionSnapshot.overlayBackState.panelVisible,
      offlineBottomPanelExpanded: this.bottomPanelDetent === 'middle'
    });
  }

  private handleOfflineWebScroll(event: OnScrollEvent): void {
    this.offlineWebScrollY = Math.max(0, Math.round(event.yOffset));
    this.applyOfflineBottomChromeScroll();
    this.applyOfflineStatusBarScroll();
  }

  private handleOfflineWebTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.viewerViewModel.recordScrollTouchPhase('down');
      return;
    }
    if (event.type === TouchType.Move) {
      this.viewerViewModel.recordScrollTouchPhase('move');
      return;
    }
    if (event.type === TouchType.Up) {
      this.viewerViewModel.recordScrollTouchPhase('up');
      return;
    }
    if (event.type === TouchType.Cancel) {
      this.viewerViewModel.recordScrollTouchPhase('cancel');
    }
  }

  private applyOfflineBottomChromeScroll(): void {
    if (!this.viewerViewModel.isScrollPresentationChangeAllowed()) {
      this.bottomChromeScrollCoordinator.reset(this.pageId, this.offlineWebScrollY);
      return;
    }
    const decision = this.bottomChromeScrollCoordinator.handlePresentationScroll({
      surfaceId: this.pageId,
      scrollOffsetY: this.offlineWebScrollY,
      surfaceVisible: this.viewerState.canOpen,
      addressFocused: this.pageFindBarState.visible || this.detailsSheetVisible,
      currentDetent: this.bottomPanelDetent,
      currentPresentation: this.bottomChromeScrollPresentation,
      presentationChangeAllowed: true,
      showTabsSheet: false,
      scrollBehavior: sharedPreferencesRepository.getPreferences().appearance.bottomToolbarScrollBehavior
    });
    if (decision.changed) {
      this.bottomChromeScrollPresentation = decision.presentation;
    }
  }

  private applyOfflineStatusBarScroll(): void {
    const decision = this.topImmersionScrollCoordinator.handleScroll({
      tabId: this.pageId,
      scrollOffsetY: this.offlineWebScrollY,
      webPageVisible: this.viewerState.canOpen,
      addressFocused: this.pageFindBarState.visible || this.detailsSheetVisible,
      bottomPanelInteractive: this.bottomPanelDetent !== 'peek',
      showTabsSheet: false,
      scrollImmersionEnabled: sharedPreferencesRepository.getPreferences().appearance.globalImmersionEnabled,
      currentStatusBarVisible: this.statusBarVisible
    });
    if (decision.changed) {
      this.setOfflineStatusBarVisible(decision.statusBarVisible, 'offline-scroll');
    }
  }

  private restoreOfflineChrome(source: string): void {
    this.viewerViewModel.resetScrollInteraction();
    this.bottomChromeScrollCoordinator.reset(this.pageId, this.offlineWebScrollY);
    this.topImmersionScrollCoordinator.reset(this.pageId, this.offlineWebScrollY);
    this.bottomChromeScrollPresentation = 'resting';
    if (this.bottomPanelDetent === 'peek') {
      this.bottomPanelDetent = 'low';
    }
    this.playBottomBackdropSettle(this.bottomPanelDetent);
    this.setOfflineStatusBarVisible(true, source);
    this.notifyBackStateChange();
  }

  private setOfflineStatusBarVisible(visible: boolean, source: string): void {
    if (this.statusBarVisible === visible) {
      return;
    }
    this.statusBarVisible = visible;
    this.statusBarVisibilityTask = this.statusBarVisibilityTask
      .catch((_error: Error) => {
      })
      .then(() => this.applyOfflineStatusBarVisibility(visible, source));
  }

  private applyOfflineStatusBarVisibility(visible: boolean, source: string): Promise<void> {
    return window.getLastWindow(getContext(this) as common.UIAbilityContext)
      .then((mainWindow: window.Window) => {
        return mainWindow.setSpecificSystemBarEnabled('status', visible, true);
      })
      .catch((error: Error) => {
        this.statusBarVisible = true;
        hilog.warn(0x0000, 'OfflinePageViewer',
          'Failed to set status bar visible=%{public}s on %{public}s: %{public}s',
          visible ? 'true' : 'false', source, JSON.stringify(error));
      });
  }

  private syncOfflineStatusBarContentStyle(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    this.statusBarStyleService.applyLightContentStyle(
      getContext(this) as common.UIAbilityContext,
      this.viewerViewModel.shouldUseLightStatusBarContent(
        this.readerModeSessionSnapshot.state.visible,
        this.readerModeSessionSnapshot.state.preferences.theme,
        sharedBrowserThemeModeCoordinator.resolveEffectiveMode('system'),
        sharedBrowserThemeModeCoordinator.resolveEffectiveMode(preferences.themeMode)
      )
    );
  }

  private getOfflineBottomPanelHeight(): number {
    return this.bottomPanelResponsiveViewModel.resolveWebPanelHeight({
      viewportHeight: this.resolveOfflineViewportHostHeight(),
      addressFocused: false,
      state: this.buildOfflineBottomPanelResponsiveState()
    });
  }

  private buildOfflineBottomPanelMotionState(): BrowserBottomPanelMotionState {
    return {
      targetDetent: this.bottomPanelDetent,
      immediateLowDetentRequestVersion: 0,
      bottomInset: 0,
      panelHeight: this.getOfflineBottomPanelHeight(),
      middlePanelHeight: 0,
      overlayHostHeight: this.resolveOfflineViewportHostHeight(),
      keyboardOverlayInset: 0,
      visible: this.bottomChromeScrollPresentation !== 'hidden',
      detentDragEnabled: true,
      panelExpansionEnabled: true,
      suppressExpandedContentFromDrag: this.bottomChromeReturnHomeDrag,
      peekEnabled: true,
      peekGestureEnabled: false,
      peekToLowAnimationDurationMs: BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS,
      collapseToPeekAnimationDurationMs: BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS
    };
  }

  private resolveOfflineViewportHostHeight(): number {
    return Math.max(1, this.rootViewportHeight);
  }

  private buildOfflineBottomPanelResponsiveState(): BrowserBottomPanelResponsiveState {
    return this.bottomPanelResponsiveViewModel.buildState({
      viewportWidth: this.rootViewportWidth,
      viewportHeight: this.resolveOfflineViewportHostHeight()
    });
  }

  private incrementOfflineToolbarActionRevision(): void {
    this.offlineToolbarActionRevision += 1;
  }

  private loadOfflinePage(): void {
    this.openCoordinator.open(this.pageId, this.dataScope, this.privacyMode)
      .then((result) => {
        this.viewerState = this.openCoordinator.buildViewerState(result, this.pageId);
        this.offlineHtmlLoadRequested = false;
        this.loadedIntoWeb = false;
        this.loadHtmlIntoWeb();
      })
      .catch((_error: Error) => {
        this.offlineHtmlLoadRequested = false;
        this.loadedIntoWeb = false;
        this.viewerState = this.openCoordinator.buildFailureState(this.pageId, '离线页面打开失败');
      });
  }

  private reloadOfflinePage(): void {
    if (!this.viewerState.canOpen || !this.webControllerAttached) {
      return;
    }
    this.offlineHtmlLoadRequested = false;
    this.loadedIntoWeb = false;
    this.restoreOfflineChrome('offline-reload');
    this.loadHtmlIntoWeb();
  }

  private beginOfflineBottomChromeGesture(source: BrowserBottomChromeGestureSource): void {
    const state = this.viewerViewModel.beginBottomChromeGesture(source);
    this.bottomChromeReturnHomeDrag = state.returnHomeDrag;
    this.bottomChromeReturnHomeProgress = state.progress;
  }

  private updateOfflineBottomChromeGesture(source: BrowserBottomChromeGestureSource, offsetY: number): void {
    const state = this.viewerViewModel.updateBottomChromeGesture(source, offsetY);
    this.bottomChromeReturnHomeDrag = state.returnHomeDrag;
    this.bottomChromeReturnHomeProgress = state.progress;
  }

  private interceptOfflineBottomChromeGestureEnd(
    source: BrowserBottomChromeGestureSource,
    offsetY: number
  ): boolean {
    const releasePlan = this.viewerViewModel.resolveBottomChromeGestureRelease(source, offsetY);
    this.resetOfflineBottomChromeGesture();
    this.bottomPanelDetent = 'low';
    if (releasePlan.shouldReturnHome) {
      requestBrowserShellIntent('return_home');
      router.back();
    }
    return releasePlan.interceptPanelRelease;
  }

  private resetOfflineBottomChromeGesture(): void {
    this.bottomChromeReturnHomeDrag = false;
    this.bottomChromeReturnHomeProgress = 0;
  }

  private loadHtmlIntoWeb(): void {
    if (!this.viewerState.canOpen || this.offlineHtmlLoadRequested || !this.webControllerAttached) {
      return;
    }
    try {
      if (this.viewerState.contentKind === 'web_archive') {
        if (this.viewerState.archiveUri.length <= 0) {
          return;
        }
        this.webController.loadUrl(this.viewerState.archiveUri);
      } else {
        if (this.viewerState.html.length <= 0) {
          return;
        }
        const originalUrl = this.resolveOriginalPageUrl();
        this.webController.loadData(
          this.viewerState.html,
          'text/html',
          'UTF-8',
          originalUrl,
          originalUrl
        );
      }
      this.offlineHtmlLoadRequested = true;
    } catch (_error) {
      this.offlineHtmlLoadRequested = false;
      this.loadedIntoWeb = false;
      this.viewerState = this.openCoordinator.buildFailureState(this.pageId, '离线页面打开失败');
    }
  }

  private buildOfflineWebAppearancePolicy(): WebAppearancePolicy {
    const preferences = sharedPreferencesRepository.getPreferences();
    return resolveWebAppearancePolicyForTheme({
      paletteId: preferences.appearance.themePaletteId,
      resolvedThemeMode: sharedBrowserThemeModeCoordinator.resolveEffectiveMode(preferences.themeMode),
      forceDarkWebContentEnabled: preferences.appearance.forceDarkWebContentEnabled
    }, this.themePaletteService);
  }

  private applyOfflineWebAppearanceBootstrap(): void {
    if (!this.webControllerAttached || !this.viewerState.canOpen) {
      return;
    }
    try {
      void this.webController.runJavaScript(
        buildWebAppearanceDocumentStartScript(this.offlineWebAppearancePolicy)
      ).catch((error: Error) => {
        hilog.warn(0x0000, 'OfflinePageViewer', 'Failed to apply web appearance: %{public}s', error.message);
      });
    } catch (error) {
      hilog.warn(0x0000, 'OfflinePageViewer', 'Failed to schedule web appearance: %{public}s', JSON.stringify(error));
    }
  }

  private buildWebLoadErrorMessage(event: OnErrorReceiveEvent): string {
    try {
      const errorInfo = event.error;
      const message = errorInfo?.getErrorInfo() ?? '';
      if (message.length > 0) {
        return `离线页面加载失败：${message}`;
      }
    } catch (_error) {
    }
    return '离线页面加载失败';
  }

  private getOfflineWebViewportLayoutTopInsetPx(): number {
    if (sharedPreferencesRepository.getPreferences().appearance.alwaysTopImmersionEnabled) {
      return 0;
    }
    if (sharedPreferencesRepository.getPreferences().appearance.globalImmersionEnabled && !this.statusBarVisible) {
      return 0;
    }
    const safeInsets = this.windowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage());
    return Math.max(0, Math.ceil(safeInsets.topInsetVp + OFFLINE_PAGE_TOP_FIXED_SAFETY_HEIGHT));
  }

  private getSharedStageStorage(): LocalStorage | undefined {
    return this.getUIContext().getSharedLocalStorage();
  }

  private openPageFind(): void {
    if (!this.viewerState.canOpen || !this.webControllerAttached) {
      this.showToast('页面暂不可查找');
      return;
    }
    this.pageFindCoordinator.open(OFFLINE_PAGE_FIND_TAB_ID);
    this.restoreOfflineChrome('page-find-open');
  }

  private async openReaderMode(): Promise<void> {
    if (!this.viewerState.canOpen) {
      this.showToast('离线页面暂不可阅读');
      return;
    }
    if (this.viewerState.html.trim().length > 0) {
      const articleUrl = this.resolveOriginalPageUrl();
      const article = this.offlineReaderExtractionService.extract({
        html: this.viewerState.html,
        title: this.viewerState.title,
        siteName: this.viewerState.siteName,
        url: articleUrl
      });
      const outcome = this.articleReadingSession.openSessionFromArticle(article, articleUrl);
      if (outcome === 'unavailable') {
        this.showToast('没有整理出可阅读的正文');
      }
      return;
    }
    this.loadHtmlIntoWeb();
    if (!this.loadedIntoWeb) {
      await this.waitForOfflineReaderModeLoadSettle();
    }
    const articleUrl = this.resolveOriginalPageUrl();
    const outcome: ReaderModeSessionOpenOutcome =
      await this.articleReadingSession.openSessionFromController(this.webController, articleUrl);
    if (outcome === 'unavailable') {
      this.showToast('没有整理出可阅读的正文');
    }
  }

  private async waitForOfflineReaderModeLoadSettle(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, OFFLINE_READER_MODE_LOAD_SETTLE_DELAY_MS);
    });
  }

  private presentReaderSpeechPlayer(): void {
    const overlayGeneration = this.readerSpeechPlayerOverlayGeneration + 1;
    this.readerSpeechPlayerOverlayGeneration = overlayGeneration;
    this.cancelReaderSpeechPlayerOpenTimer();
    this.readerSpeechPlayerSheetVisible = false;
    this.showReaderSpeechPlayerSheet = true;
    this.readerSpeechPlayerOpenTimer = setTimeout(() => {
      this.readerSpeechPlayerOpenTimer = -1;
      if (this.readerSpeechPlayerOverlayGeneration !== overlayGeneration) {
        return;
      }
      if (this.readerModeSessionSnapshot.state.visible && this.showReaderSpeechPlayerSheet) {
        this.readerSpeechPlayerSheetVisible = true;
      }
    }, BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS);
  }

  private closeReaderSpeechPlayer(): void {
    const overlayGeneration = this.readerSpeechPlayerOverlayGeneration + 1;
    this.readerSpeechPlayerOverlayGeneration = overlayGeneration;
    this.cancelReaderSpeechPlayerOpenTimer();
    this.readerSpeechPlayerSheetVisible = false;
    setTimeout(() => {
      if (this.readerSpeechPlayerOverlayGeneration !== overlayGeneration) {
        return;
      }
      this.showReaderSpeechPlayerSheet = false;
    }, BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS);
  }

  private resetReaderSpeechPlayerPresentation(): void {
    this.readerSpeechPlayerOverlayGeneration += 1;
    this.readerSpeechVoiceDialogController.close();
    this.cancelReaderSpeechPlayerOpenTimer();
    this.readerSpeechPlayerSheetVisible = false;
    this.showReaderSpeechPlayerSheet = false;
  }

  private cancelReaderSpeechPlayerOpenTimer(): void {
    if (this.readerSpeechPlayerOpenTimer < 0) {
      return;
    }
    clearTimeout(this.readerSpeechPlayerOpenTimer);
    this.readerSpeechPlayerOpenTimer = -1;
  }

  private openReaderSpeechVoiceDialog(): void {
    this.articleReadingSession.openSpeechVoicePicker(
      sharedBrowserThemeModeCoordinator.resolveEffectiveMode('system')
    );
    this.readerSpeechVoiceDialogController.open();
  }

  private resolveReaderModeUrl(): string {
    const articleUrl = this.readerModeSessionSnapshot.state.article.url.trim();
    if (articleUrl.length > 0) {
      return articleUrl;
    }
    return this.resolveOriginalPageUrl();
  }

  private openReaderModeLink(url: string): void {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length <= 0) {
      return;
    }
    this.articleReadingSession.closeSession();
    router.pushUrl({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(normalizedUrl, 'current_tab', '', 'offline')
    }, router.RouterMode.Single).catch((_error: Error) => {
      router.back();
    });
  }

  private closePageFind(): void {
    this.pageFindCoordinator.close(OFFLINE_PAGE_FIND_TAB_ID);
    this.restoreOfflineChrome('page-find-close');
  }

  private handlePageFindBarAction(action: BrowserPageFindBarAction): void {
    this.pageFindCoordinator.handleBarAction(OFFLINE_PAGE_FIND_TAB_ID, action);
    if (action.type === 'close') {
      this.restoreOfflineChrome('page-find-close');
    }
  }

  @Builder
  private buildExpandedScrim() {
    if (this.shouldMountExpandedScrim()) {
      BrowserRootBottomPanelExpandedScrim({
        scrimOpacity: this.resolveBottomBackdropProgress(),
        blockHitTest: this.shouldBlockExpandedScrimHitTest(),
        onDismiss: () => {
          this.collapseBottomPanelFromScrim();
        }
      })
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
          left: { anchor: '__container__', align: HorizontalAlign.Start },
          right: { anchor: '__container__', align: HorizontalAlign.End }
        })
        .zIndex(5)
    }
  }

  private shouldShowExpandedScrim(): boolean {
    return this.bottomPanelDetent === 'middle';
  }

  private shouldMountExpandedScrim(): boolean {
    return this.shouldShowExpandedScrim() || this.resolveBottomBackdropProgress() > 0.01;
  }

  private shouldBlockExpandedScrimHitTest(): boolean {
    return this.shouldShowExpandedScrim() || this.resolveBottomBackdropProgress() > 0.01;
  }

  private collapseBottomPanelFromScrim(): void {
    if (!this.shouldBlockExpandedScrimHitTest()) {
      return;
    }
    this.bottomPanelDetent = 'low';
    this.playBottomBackdropSettle('low');
    this.restoreOfflineChrome('expanded-scrim');
    this.notifyBackStateChange();
  }

  private beginBottomBackdropDrag(panelHeight: number, targetHeight: number): void {
    this.bottomBackdropSettleRunId += 1;
    this.bottomBackdropPreviousPanelHeight = -1;
    this.bottomBackdropExpandedHeight = Math.max(panelHeight, targetHeight);
    this.updateBottomBackdropVisualHeight(panelHeight, targetHeight);
  }

  private handleBottomPanelGestureFrame(frame: BrowserBottomAddressPanelGestureFrame): void {
    if (frame.phase === 'start') {
      this.beginBottomBackdropDrag(frame.panelHeight, frame.middlePanelHeight);
      this.beginOfflineBottomChromeGesture(frame.source);
      return;
    }
    this.updateBottomBackdropDrag(frame.panelHeight);
    this.updateOfflineBottomChromeGesture(frame.source, frame.offsetY);
  }

  private updateBottomBackdropDrag(panelHeight: number): void {
    this.updateBottomBackdropVisualHeight(panelHeight, this.bottomBackdropExpandedHeight);
  }

  private updateBottomBackdropVisualHeight(panelHeight: number, expandedHeight: number): void {
    const progress = this.bottomBackdropViewModel.resolveProgress({
      panelHeight,
      expandedHeight,
      previousPanelHeight: this.bottomBackdropPreviousPanelHeight
    });
    this.bottomBackdropPreviousPanelHeight = panelHeight;
    this.bottomBackdropProgress = progress;
  }

  private playBottomBackdropSettle(detent: HomeSearchPanelDetent): void {
    this.playBottomBackdropProgressTransition(this.bottomBackdropViewModel.resolveDetentProgress(detent));
  }

  private playBottomBackdropProgressTransition(targetProgress: number): void {
    const currentProgress = this.resolveBottomBackdropProgress();
    const durationMs = this.bottomBackdropViewModel.resolveSettleDurationMs({
      currentProgress,
      targetProgress
    });
    const runId = ++this.bottomBackdropSettleRunId;
    this.bottomBackdropPreviousPanelHeight = -1;
    if (durationMs <= 0) {
      this.bottomBackdropProgress = targetProgress;
      return;
    }
    animateTo({
      duration: durationMs,
      curve: Curve.Linear,
      onFinish: () => {
        if (this.bottomBackdropSettleRunId !== runId) {
          return;
        }
        this.bottomBackdropPreviousPanelHeight = -1;
        this.bottomBackdropProgress = targetProgress;
      }
    }, () => {
      if (this.bottomBackdropSettleRunId !== runId) {
        return;
      }
      this.bottomBackdropProgress = targetProgress;
    });
  }

  private resolveBottomBackdropProgress(): number {
    return this.bottomBackdropViewModel.resolveEffectiveProgress(this.bottomBackdropProgress);
  }

  private openDetailsSheet(): void {
    if (!this.viewerState.canOpen) {
      this.showToast('离线页面详情不可用');
      return;
    }
    this.detailsSheetVisible = true;
    this.restoreOfflineChrome('details-open');
  }

  private openOriginalPage(): void {
    if (!this.listCoordinator.canNavigate(this.dataScope, this.privacyMode)) {
      this.showToast('当前隐私策略不允许打开原网页');
      return;
    }
    const originalUrl = this.resolveOriginalPageUrl();
    if (originalUrl.length === 0) {
      this.showToast('原网页链接不可用');
      return;
    }
    router.pushUrl({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(originalUrl, 'current_tab', '', 'offline', {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      })
    }, router.RouterMode.Single).catch((_error: Error) => {
      router.back();
    });
  }

  private openBookmarkManager(): void {
    router.pushUrl({
      url: BOOKMARK_MANAGER_ROUTE,
      params: {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.privacyMode === 'private' || this.dataScope === 'session_ephemeral'
          ? 'private_session'
          : 'regular_session'
      }
    }).catch((_error: Error) => {
      this.showToast('打开书签管理失败');
    });
  }

  private deleteCurrentPage(): void {
    this.listCoordinator.delete(this.viewerState.pageId, this.dataScope, this.privacyMode)
      .then((result: OfflinePageDeleteResult) => {
        this.showToast(result.message);
        if (result.ok) {
          router.back();
        }
      })
      .catch((_error: Error) => {
        this.showToast('删除离线页面失败');
      });
  }

  private confirmDeleteCurrentPage(): void {
    showCenteredAlertDialog({
      title: '删除离线页面',
      message: `确定删除“${this.viewerState.title}”的离线副本吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.deleteCurrentPage();
        }
      }
    });
  }

  private copyOriginalUrl(url: string = ''): void {
    const normalizedUrl = url.trim();
    this.linkActionService.copyOriginalUrl(
      normalizedUrl.length > 0 ? normalizedUrl : this.resolveOriginalPageUrl(),
      this.dataScope,
      this.privacyMode
    )
      .then((result: OfflinePageLinkActionResult) => {
        this.showToast(result.message);
      });
  }

  private shareOriginalUrl(title: string = '', url: string = ''): void {
    const normalizedTitle = title.trim();
    const normalizedUrl = url.trim();
    this.linkActionService.shareOriginalUrl(
      this.getPickerContext(),
      normalizedTitle.length > 0 ? normalizedTitle : this.viewerState.title,
      normalizedUrl.length > 0 ? normalizedUrl : this.resolveOriginalPageUrl(),
      this.dataScope,
      this.privacyMode
    )
      .then((result: OfflinePageLinkActionResult) => {
        if (!result.ok) {
          this.showToast(result.message);
        }
      });
  }

  private exportOfflinePage(): void {
    this.exportService.exportPage(this.getPickerContext(), this.pageId, this.dataScope, this.privacyMode)
      .then((result: OfflinePageExportResult) => {
        this.showToast(result.message);
      });
  }

  private resolveOriginalPageUrl(): string {
    return this.viewerState.originalUrl.trim();
  }

  private getPickerContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
    }
  }
}
