import { common, Want } from '@kit.AbilityKit';
import router from '@ohos.router';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  DESKTOP_WEB_SHORTCUT_SOURCE,
  DESKTOP_WEB_SHORTCUT_WANT_KEYS
} from '../../data/webapps/WebAppInstallModels';
import { AiraAppShortcutTarget } from '../router/AppShortcutNavigationCoordinator';
import { DocumentViewerService } from '../../services/viewer/DocumentViewerService';
import {
  BrowserWindowSessionBackgroundBinding,
  BrowserWindowSessionArticleReadingBinding,
  BrowserWindowSessionShellPresentationBinding,
  BrowserWindowSessionNovelReaderBinding,
  BrowserWindowSessionTabManagerBinding,
  BrowserWindowSessionRuntimeBinding,
  BrowserWindowSessionApplication,
  BrowserWindowPresentationReconcileResult,
  BrowserWindowSessionSeed
} from '../../core/browser/BrowserWindowSessionApplication';
import {
  BrowserWindowSessionContextBinding,
  BrowserWindowSessionContextComposition
} from '../../core/browser/BrowserWindowSessionContextApplication';
import { BrowserWindowSessionContextStateBinding } from '../../core/browser/BrowserWindowSessionContextState';
import {
  BrowserShellFamilyAvailability,
  BrowserWindowPresentationProfile,
  BrowserWindowPresentationProfileInput
} from '../../core/browser/BrowserWindowPresentationProfile';
import { BrowserShellAdapterCatalogSnapshot } from '../../core/browser/BrowserShellAdapterCatalog';
import {
  BrowserLargeScreenPresentationFacts
} from '../../core/browser/BrowserLargeScreenPresentationViewModel';
import {
  BrowserLargeScreenWindowFactsInput,
  BrowserLargeScreenWindowFactsPolicy
} from '../../core/browser/BrowserLargeScreenWindowFactsViewModel';
import {
  BrowserShellPresentationReconcileResult,
  BrowserShellPresentationSnapshot,
  BrowserShellPresentationSurface
} from '../../core/browser/BrowserShellPresentationCoordinator';
import { BrowserTabState } from '../../core/tabs/TabManager';
import { NovelBookshelfBook } from '../../features/novel/NovelLibraryModels';
import { requestNovelBookshelfTakeover } from '../../features/novel/NovelBookshelfOpenRequestCenter';
import {
  requestOpenBrowserUrlWithRouteParams
} from '../../core/navigation/BrowserNativeNavigationRequestCenter';
import { BROWSER_SHELL_ROUTE } from '../router/AppRoutes';
import {
  BrowserContinuationPayload,
  sharedBrowserContinuationCoordinator
} from '../../core/browser/BrowserContinuationCoordinator';

export interface BrowserLaunchShortcutContext {
  shortcutId: string;
  title: string;
  iconPath: string;
  scope: string;
  manifestUrl: string;
  origin: string;
  themeColor: string;
  createdAt: number;
}

export interface BrowserLaunchPayload {
  uri: string;
  action: string;
  type: string;
  source: string;
  appShortcut: AiraAppShortcutTarget | '';
  receivedAt: number;
  openInNewWindow: boolean;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  privateWindowInstanceId: string;
  tabMoveWindowInstanceId: string;
  tabMoveRequestId: string;
  continuation?: BrowserContinuationPayload;
  shortcut?: BrowserLaunchShortcutContext;
}

export interface BrowserLaunchPayloadInput {
  uri: string;
  action?: string;
  type?: string;
  source: string;
  appShortcut?: string;
  receivedAt?: number;
  openInNewWindow?: boolean;
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
  privateWindowInstanceId?: string;
  tabMoveWindowInstanceId?: string;
  tabMoveRequestId?: string;
  continuation?: BrowserContinuationPayload;
  shortcut?: BrowserLaunchShortcutContext;
}

export interface BrowserInitialShellViewport {
  width: number;
  height: number;
}

interface BrowserTrustedLaunchControls {
  openInNewWindow: boolean;
}

export interface BrowserWindowTabSummary {
  windowId: string;
  activeTabId: string;
  tabCount: number;
  tabIds: string[];
  summaryLine: string;
}

export interface BrowserTabWindowMoveRequest {
  requestId: string;
  sourceWindowId: string;
  targetWindowInstanceId: string;
  tab: BrowserTabState;
  stagedAt: number;
}

export interface BrowserTabWindowMoveAcknowledgement {
  requestId: string;
  accepted: boolean;
  targetWindowId: string;
  targetTabId: string;
  message: string;
}

interface BrowserTabWindowMoveRuntimeRecord {
  request: BrowserTabWindowMoveRequest;
  claimedAt: number;
  acknowledgement?: BrowserTabWindowMoveAcknowledgement;
}

const DEFAULT_WINDOW_ID = 'window-main';
const STORAGE_WINDOW_ID_KEY = 'aira.browser.windowId';
const STORAGE_WINDOW_SESSION_ID_KEY = 'aira.browser.windowSessionId';
const BROWSER_INITIAL_HOME_SURFACE_VISIBLE_STORAGE_KEY =
  'aira.browser.initialHomeSurfaceVisible';
const BROWSER_INITIAL_VIEWPORT_WIDTH_STORAGE_KEY =
  'aira.browser.initialViewportWidth';
const BROWSER_INITIAL_VIEWPORT_HEIGHT_STORAGE_KEY =
  'aira.browser.initialViewportHeight';
const DEFAULT_INITIAL_VIEWPORT_WIDTH: number = 390;
const DEFAULT_INITIAL_VIEWPORT_HEIGHT: number = 844;
const STORAGE_LAUNCH_URI_KEY = 'aira.browser.launchUri';
const STORAGE_LAUNCH_ACTION_KEY = 'aira.browser.launchAction';
const STORAGE_LAUNCH_TYPE_KEY = 'aira.browser.launchType';
const STORAGE_LAUNCH_SOURCE_KEY = 'aira.browser.launchSource';
const STORAGE_LAUNCH_APP_SHORTCUT_KEY = 'aira.browser.launchAppShortcut';
const STORAGE_LAUNCH_RECEIVED_AT_KEY = 'aira.browser.launchReceivedAt';
const STORAGE_LAUNCH_NEW_WINDOW_KEY = 'aira.browser.launchOpenInNewWindow';
const STORAGE_LAUNCH_PROFILE_ID_KEY = 'aira.browser.launchProfileId';
const STORAGE_LAUNCH_PRIVACY_MODE_KEY = 'aira.browser.launchPrivacyMode';
const STORAGE_LAUNCH_DATA_SCOPE_KEY = 'aira.browser.launchDataScope';
const STORAGE_LAUNCH_PRIVATE_WINDOW_INSTANCE_ID_KEY = 'aira.browser.launchPrivateWindowInstanceId';
const STORAGE_LAUNCH_TAB_MOVE_WINDOW_INSTANCE_ID_KEY = 'aira.browser.launchTabMoveWindowInstanceId';
const STORAGE_LAUNCH_TAB_MOVE_REQUEST_ID_KEY = 'aira.browser.launchTabMoveRequestId';
const STORAGE_LAUNCH_SHORTCUT_ID_KEY = 'aira.browser.launchShortcutId';
const STORAGE_LAUNCH_SHORTCUT_TITLE_KEY = 'aira.browser.launchShortcutTitle';
const STORAGE_LAUNCH_SHORTCUT_ICON_PATH_KEY = 'aira.browser.launchShortcutIconPath';
const STORAGE_LAUNCH_SHORTCUT_SCOPE_KEY = 'aira.browser.launchShortcutScope';
const STORAGE_LAUNCH_SHORTCUT_MANIFEST_URL_KEY = 'aira.browser.launchShortcutManifestUrl';
const STORAGE_LAUNCH_SHORTCUT_ORIGIN_KEY = 'aira.browser.launchShortcutOrigin';
const STORAGE_LAUNCH_SHORTCUT_THEME_COLOR_KEY = 'aira.browser.launchShortcutThemeColor';
const STORAGE_LAUNCH_SHORTCUT_CREATED_AT_KEY = 'aira.browser.launchShortcutCreatedAt';
const DESKTOP_WEB_PAGE_SHORTCUT_SOURCE = DESKTOP_WEB_SHORTCUT_SOURCE;
const APP_SHORTCUT_WANT_KEY = 'aira.appShortcut';
const SEARCH_INVOCATION_SOURCE_WANT_KEY = 'aira.searchInvocationSource';
const APP_SHORTCUT_SOURCE = 'desktop_app_shortcut';
export const BROWSER_SEARCH_DESKTOP_CARD_SOURCE = 'desktop_card';
export const BROWSER_PRIVATE_WINDOW_LAUNCH_SOURCE = 'aira_private_window';
export const BROWSER_PRIVATE_WINDOW_SOURCE_WANT_KEY = 'aira.privateWindow.source';
export const BROWSER_PRIVATE_WINDOW_INSTANCE_ID_WANT_KEY = 'aira.privateWindow.instanceId';
export const BROWSER_PRIVATE_WINDOW_OPEN_NEW_WANT_KEY = 'aira.privateWindow.openInNewWindow';
export const BROWSER_PRIVATE_WINDOW_PROFILE_ID_WANT_KEY = 'aira.privateWindow.profileId';
export const BROWSER_PRIVATE_WINDOW_PRIVACY_MODE_WANT_KEY = 'aira.privateWindow.privacyMode';
export const BROWSER_PRIVATE_WINDOW_DATA_SCOPE_WANT_KEY = 'aira.privateWindow.dataScope';
export const BROWSER_TAB_WINDOW_MOVE_LAUNCH_SOURCE = 'aira_tab_window_move';
export const BROWSER_TAB_WINDOW_MOVE_SOURCE_WANT_KEY = 'aira.tabMove.source';
export const BROWSER_TAB_WINDOW_MOVE_INSTANCE_ID_WANT_KEY = 'aira.tabMove.windowInstanceId';
export const BROWSER_TAB_WINDOW_MOVE_REQUEST_ID_WANT_KEY = 'aira.tabMove.requestId';
export const BROWSER_TAB_WINDOW_MOVE_PROFILE_ID_WANT_KEY = 'aira.tabMove.profileId';
export const BROWSER_TAB_WINDOW_MOVE_PRIVACY_MODE_WANT_KEY = 'aira.tabMove.privacyMode';
export const BROWSER_TAB_WINDOW_MOVE_DATA_SCOPE_WANT_KEY = 'aira.tabMove.dataScope';
const documentViewerService = new DocumentViewerService();

export class BrowserWindowRuntime {
  private static activeWindowId: string = DEFAULT_WINDOW_ID;
  private static registeredWindowIds: string[] = [];
  private static foregroundWindowIds: string[] = [];
  private static windowStorages: Record<string, LocalStorage> = {};
  private static windowAbilityContexts: Record<string, common.UIAbilityContext> = {};
  private static pendingLaunches: Record<string, BrowserLaunchPayload> = {};
  private static pendingTabWindowMoves: Record<string, BrowserTabWindowMoveRuntimeRecord> = {};
  private static windowTabSummaries: Record<string, BrowserWindowTabSummary> = {};
  private static windowSessions: Record<string, BrowserWindowSessionApplication> = {};
  private static windowSessionLifetimeRevision: number = 0;

  static resolveWindowId(rawWindowId: number | string | undefined): string {
    if (typeof rawWindowId === 'number') {
      return `window-${rawWindowId}`;
    }
    const normalized = String(rawWindowId ?? '').trim();
    return normalized.length > 0 ? normalized : DEFAULT_WINDOW_ID;
  }

  static resolveWindowIdFromStorage(storage: LocalStorage | undefined): string {
    if (storage === undefined) {
      return DEFAULT_WINDOW_ID;
    }
    const stored = storage.get(STORAGE_WINDOW_ID_KEY) as string | undefined;
    return BrowserWindowRuntime.resolveWindowId(stored);
  }

  static registerWindow(
    windowId: string,
    storage?: LocalStorage,
    abilityContext?: common.UIAbilityContext
  ): void {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    if (BrowserWindowRuntime.registeredWindowIds.indexOf(normalizedWindowId) < 0) {
      BrowserWindowRuntime.registeredWindowIds.push(normalizedWindowId);
    }
    const defaultPendingLaunch = BrowserWindowRuntime.pendingLaunches[DEFAULT_WINDOW_ID];
    if (normalizedWindowId !== DEFAULT_WINDOW_ID &&
      BrowserWindowRuntime.pendingLaunches[normalizedWindowId] === undefined &&
      defaultPendingLaunch !== undefined &&
      defaultPendingLaunch.openInNewWindow) {
      BrowserWindowRuntime.pendingLaunches[normalizedWindowId] = defaultPendingLaunch;
      BrowserWindowRuntime.clearPendingLaunchStorage(DEFAULT_WINDOW_ID);
      BrowserWindowRuntime.pendingLaunches = BrowserWindowRuntime.filterRecord(
        BrowserWindowRuntime.pendingLaunches,
        (key: string) => key !== DEFAULT_WINDOW_ID
      );
    }
    if (storage !== undefined) {
      BrowserWindowRuntime.windowStorages[normalizedWindowId] = storage;
      BrowserWindowRuntime.writeWindowId(storage, normalizedWindowId);
      const pendingLaunch = BrowserWindowRuntime.pendingLaunches[normalizedWindowId];
      if (pendingLaunch !== undefined) {
        BrowserWindowRuntime.writeLaunch(storage, pendingLaunch);
      }
    }
    if (abilityContext !== undefined) {
      BrowserWindowRuntime.windowAbilityContexts[normalizedWindowId] = abilityContext;
    }
  }

  static resolveWindowAbilityContext(windowId: string): common.UIAbilityContext | undefined {
    return BrowserWindowRuntime.windowAbilityContexts[BrowserWindowRuntime.resolveWindowId(windowId)];
  }

  static unregisterWindow(windowId: string): void {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    const closingStorage = BrowserWindowRuntime.windowStorages[normalizedWindowId];
    const pendingLaunch = BrowserWindowRuntime.pendingLaunches[normalizedWindowId] ??
      BrowserWindowRuntime.readLaunch(closingStorage);
    if (closingStorage !== undefined) {
      BrowserWindowRuntime.clearLaunch(closingStorage);
    }
    BrowserWindowRuntime.registeredWindowIds = BrowserWindowRuntime.registeredWindowIds
      .filter((item: string) => item !== normalizedWindowId);
    BrowserWindowRuntime.foregroundWindowIds = BrowserWindowRuntime.foregroundWindowIds
      .filter((item: string) => item !== normalizedWindowId);
    BrowserWindowRuntime.windowStorages = BrowserWindowRuntime.filterRecord(
      BrowserWindowRuntime.windowStorages,
      (key: string) => key !== normalizedWindowId
    );
    BrowserWindowRuntime.windowAbilityContexts = BrowserWindowRuntime.filterRecord(
      BrowserWindowRuntime.windowAbilityContexts,
      (key: string) => key !== normalizedWindowId
    );
    BrowserWindowRuntime.windowTabSummaries = BrowserWindowRuntime.filterRecord(
      BrowserWindowRuntime.windowTabSummaries,
      (key: string) => key !== normalizedWindowId
    );
    BrowserWindowRuntime.pendingLaunches = BrowserWindowRuntime.filterRecord(
      BrowserWindowRuntime.pendingLaunches,
      (key: string) => key !== normalizedWindowId
    );
    if (BrowserWindowRuntime.activeWindowId === normalizedWindowId) {
      BrowserWindowRuntime.activeWindowId = BrowserWindowRuntime.registeredWindowIds[0] ?? DEFAULT_WINDOW_ID;
    }
    if (pendingLaunch !== undefined) {
      BrowserWindowRuntime.rehomePendingLaunch(normalizedWindowId, pendingLaunch);
    }
  }

  static markWindowForeground(windowId: string): void {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    BrowserWindowRuntime.activeWindowId = normalizedWindowId;
    if (BrowserWindowRuntime.foregroundWindowIds.indexOf(normalizedWindowId) < 0) {
      BrowserWindowRuntime.foregroundWindowIds.push(normalizedWindowId);
    }
  }

  static markWindowBackground(windowId: string): void {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    BrowserWindowRuntime.foregroundWindowIds = BrowserWindowRuntime.foregroundWindowIds
      .filter((item: string) => item !== normalizedWindowId);
  }

  static acquireSession(seed: BrowserWindowSessionSeed): BrowserWindowSessionApplication {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(seed.windowId);
    const existing = BrowserWindowRuntime.windowSessions[normalizedWindowId];
    if (existing !== undefined) {
      BrowserWindowRuntime.reconcileWebAppPresentationForLaunch(
        normalizedWindowId,
        BrowserWindowRuntime.pendingLaunches[normalizedWindowId]
      );
      return existing;
    }
    const session = new BrowserWindowSessionApplication({
      windowId: normalizedWindowId,
      articleReadingPreferencesRepository: seed.articleReadingPreferencesRepository
    });
    BrowserWindowRuntime.windowSessions[normalizedWindowId] = session;
    BrowserWindowRuntime.reconcileWebAppPresentationForLaunch(
      normalizedWindowId,
      BrowserWindowRuntime.pendingLaunches[normalizedWindowId]
    );
    return session;
  }

  static bindSessionToStorage(storage: LocalStorage, windowSessionId: string): void {
    const normalizedWindowSessionId = BrowserWindowRuntime.resolveWindowId(windowSessionId);
    storage.setOrCreate(STORAGE_WINDOW_SESSION_ID_KEY, normalizedWindowSessionId);
    storage.set(STORAGE_WINDOW_SESSION_ID_KEY, normalizedWindowSessionId);
  }

  static clearSessionFromStorage(storage: LocalStorage): void {
    storage.set(STORAGE_WINDOW_SESSION_ID_KEY, '');
  }

  static connectRuntimeSession(
    storage: LocalStorage | undefined
  ): BrowserWindowSessionRuntimeBinding | undefined {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return undefined;
    }
    return BrowserWindowRuntime.windowSessions[windowSessionId]?.createRuntimeSessionBinding();
  }

  static connectTabManagerSession(
    storage: LocalStorage | undefined
  ): BrowserWindowSessionTabManagerBinding | undefined {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return undefined;
    }
    return BrowserWindowRuntime.windowSessions[windowSessionId]?.createTabManagerBinding();
  }

  static connectNovelReaderSession(
    storage: LocalStorage | undefined
  ): BrowserWindowSessionNovelReaderBinding | undefined {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return undefined;
    }
    return BrowserWindowRuntime.windowSessions[windowSessionId]?.createNovelReaderBinding();
  }

  static async openNovelBookshelfBook(book: NovelBookshelfBook): Promise<void> {
    const windowId: string = BrowserWindowRuntime.activeWindowId;
    const session: BrowserWindowSessionApplication | undefined = BrowserWindowRuntime.windowSessions[windowId];
    const summary: BrowserWindowTabSummary | undefined = BrowserWindowRuntime.windowTabSummaries[windowId];
    if (session !== undefined && summary !== undefined && summary.activeTabId.trim().length > 0) {
      try {
        await session.openNovelBookshelfFromPersistentCache({
          book: book,
          tabId: summary.activeTabId
        });
      } catch (_error) {
        // 持久缓存是加速层；任何异常都必须继续进入原有 Web 识别链路。
      }
    }
    requestNovelBookshelfTakeover(book);
    router.back({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(book.detailUrl, 'current_tab', book.title, 'app_ui', {
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      })
    });
  }

  static openNovelBookshelfOriginalPage(book: NovelBookshelfBook): void {
    const detailUrl: string = book.detailUrl.trim();
    if (detailUrl.length === 0) {
      return;
    }
    router.back({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(detailUrl, 'current_tab', book.title, 'app_ui', {
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      })
    });
  }

  static connectArticleReadingSession(
    storage: LocalStorage | undefined
  ): BrowserWindowSessionArticleReadingBinding | undefined {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return undefined;
    }
    return BrowserWindowRuntime.windowSessions[windowSessionId]?.createArticleReadingBinding();
  }

  static connectWindowContextState(
    storage: LocalStorage | undefined
  ): BrowserWindowSessionContextStateBinding | undefined {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return undefined;
    }
    return BrowserWindowRuntime.windowSessions[windowSessionId]?.createContextStateBinding();
  }

  static connectWindowContext(
    storage: LocalStorage | undefined,
    composition: BrowserWindowSessionContextComposition
  ): BrowserWindowSessionContextBinding | undefined {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return undefined;
    }
    const session = BrowserWindowRuntime.windowSessions[windowSessionId];
    if (session === undefined) {
      return undefined;
    }
    return session.connectWindowContext(composition);
  }

  static disconnectWindowContext(storage: LocalStorage | undefined): void {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return;
    }
    BrowserWindowRuntime.windowSessions[windowSessionId]?.disconnectWindowContext();
  }

  static connectBackground(
    storage: LocalStorage | undefined
  ): BrowserWindowSessionBackgroundBinding | undefined {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return undefined;
    }
    return BrowserWindowRuntime.windowSessions[windowSessionId]?.createBackgroundBinding();
  }

  static reconcileSessionPresentation(
    windowSessionId: string,
    input: BrowserWindowPresentationProfileInput,
    availability: BrowserShellFamilyAvailability,
    revision: number
  ): BrowserWindowPresentationReconcileResult | undefined {
    const normalizedWindowSessionId = BrowserWindowRuntime.resolveWindowId(windowSessionId);
    const session = BrowserWindowRuntime.windowSessions[normalizedWindowSessionId];
    if (session === undefined) {
      return undefined;
    }
    return session.reconcilePresentationProfile(input, availability, revision);
  }

  static reconcileLargeScreenPresentation(
    windowSessionId: string,
    facts: BrowserLargeScreenPresentationFacts
  ): BrowserShellPresentationSnapshot | undefined {
    const normalizedWindowSessionId = BrowserWindowRuntime.resolveWindowId(windowSessionId);
    const session = BrowserWindowRuntime.windowSessions[normalizedWindowSessionId];
    if (session === undefined) {
      return undefined;
    }
    return session.reconcileLargeScreenPresentation(facts);
  }

  static reconcileLargeScreenWindowFacts(
    windowSessionId: string,
    input: BrowserLargeScreenWindowFactsInput,
    policy: BrowserLargeScreenWindowFactsPolicy
  ): BrowserShellPresentationReconcileResult {
    const normalizedWindowSessionId = BrowserWindowRuntime.resolveWindowId(windowSessionId);
    const session = BrowserWindowRuntime.windowSessions[normalizedWindowSessionId];
    if (session === undefined) {
      return { snapshot: undefined, changed: false };
    }
    return session.reconcileLargeScreenWindowFacts(input, policy);
  }

  static connectShellPresentation(
    storage: LocalStorage | undefined,
    catalog?: BrowserShellAdapterCatalogSnapshot
  ): BrowserWindowSessionShellPresentationBinding | undefined {
    const windowSessionId = String(storage?.get(STORAGE_WINDOW_SESSION_ID_KEY) ?? '').trim();
    if (windowSessionId.length === 0) {
      return undefined;
    }
    const session = BrowserWindowRuntime.windowSessions[windowSessionId];
    if (session === undefined) {
      return undefined;
    }
    if (catalog !== undefined) {
      session.connectShellPresentation(catalog);
    }
    return session.createShellPresentationBinding();
  }

  static releaseSession(windowId: string): void {
    if (windowId.trim().length === 0) {
      return;
    }
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    const session = BrowserWindowRuntime.windowSessions[normalizedWindowId];
    if (session === undefined) {
      return;
    }
    session.release(normalizedWindowId, BrowserWindowRuntime.nextSessionLifetimeRevision());
    BrowserWindowRuntime.windowSessions = BrowserWindowRuntime.filterRecord(
      BrowserWindowRuntime.windowSessions,
      (key: string) => key !== normalizedWindowId
    );
  }

  static reconcileSessionLifetime(windowId: string, foreground: boolean): void {
    if (windowId.trim().length === 0) {
      return;
    }
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    const session = BrowserWindowRuntime.windowSessions[normalizedWindowId];
    if (session === undefined) {
      return;
    }
    session.reconcileLifetime({
      windowId: normalizedWindowId,
      revision: BrowserWindowRuntime.nextSessionLifetimeRevision(),
      foreground: foreground
    });
  }

  static hasForegroundWindows(): boolean {
    return BrowserWindowRuntime.foregroundWindowIds.length > 0;
  }

  static getActiveWindowId(): string {
    return BrowserWindowRuntime.activeWindowId;
  }

  static resolveActiveShellPresentationSurface(): BrowserShellPresentationSurface | undefined {
    return BrowserWindowRuntime.windowSessions[BrowserWindowRuntime.activeWindowId]
      ?.resolveShellPresentationSurface();
  }

  static peekShortcutWindowId(): string | undefined {
    const keys = Object.keys(BrowserWindowRuntime.pendingLaunches);
    for (let index = 0; index < keys.length; index++) {
      const windowId = keys[index];
      const payload = BrowserWindowRuntime.pendingLaunches[windowId];
      if (payload?.shortcut !== undefined && windowId !== DEFAULT_WINDOW_ID) {
        return windowId;
      }
    }
    return undefined;
  }

  static applyWindowIdToStorage(storage: LocalStorage, windowId: string): void {
    BrowserWindowRuntime.writeWindowId(storage, BrowserWindowRuntime.resolveWindowId(windowId));
  }

  static prepareInitialShellPresentation(
    storage: LocalStorage,
    presentationInput?: BrowserWindowPresentationProfileInput
  ): void {
    const windowId = BrowserWindowRuntime.resolveWindowIdFromStorage(storage);
    const launchPayload = BrowserWindowRuntime.peekPendingLaunch(windowId, storage);
    const showHomeSurface = !BrowserWindowRuntime.isWebSceneLaunchPayload(launchPayload);
    storage.setOrCreate(BROWSER_INITIAL_HOME_SURFACE_VISIBLE_STORAGE_KEY, showHomeSurface);
    storage.set(BROWSER_INITIAL_HOME_SURFACE_VISIBLE_STORAGE_KEY, showHomeSurface);
    BrowserWindowRuntime.writeInitialViewportDimension(
      storage,
      BROWSER_INITIAL_VIEWPORT_WIDTH_STORAGE_KEY,
      presentationInput?.windowWidthVp
    );
    BrowserWindowRuntime.writeInitialViewportDimension(
      storage,
      BROWSER_INITIAL_VIEWPORT_HEIGHT_STORAGE_KEY,
      presentationInput?.windowHeightVp
    );
  }

  static resolveInitialShellViewport(storage: LocalStorage | undefined): BrowserInitialShellViewport {
    return {
      width: BrowserWindowRuntime.readInitialViewportDimension(
        storage,
        BROWSER_INITIAL_VIEWPORT_WIDTH_STORAGE_KEY,
        DEFAULT_INITIAL_VIEWPORT_WIDTH
      ),
      height: BrowserWindowRuntime.readInitialViewportDimension(
        storage,
        BROWSER_INITIAL_VIEWPORT_HEIGHT_STORAGE_KEY,
        DEFAULT_INITIAL_VIEWPORT_HEIGHT
      )
    };
  }

  static consumeInitialHomeSurfaceVisibility(storage: LocalStorage | undefined): boolean {
    if (storage === undefined) {
      return true;
    }
    const showHomeSurface = Boolean(
      storage.get(BROWSER_INITIAL_HOME_SURFACE_VISIBLE_STORAGE_KEY) ?? true
    );
    storage.set(BROWSER_INITIAL_HOME_SURFACE_VISIBLE_STORAGE_KEY, true);
    return showHomeSurface;
  }

  static isWebSceneLaunchPayload(payload: BrowserLaunchPayload | undefined): boolean {
    if (payload === undefined || payload.appShortcut.length > 0) {
      return false;
    }
    return payload.uri.trim().length > 0 || payload.tabMoveRequestId.length > 0;
  }

  private static writeInitialViewportDimension(
    storage: LocalStorage,
    key: string,
    value: number | undefined
  ): void {
    const normalizedValue = BrowserWindowRuntime.normalizeInitialViewportDimension(value, 0);
    storage.setOrCreate(key, normalizedValue);
    storage.set(key, normalizedValue);
  }

  private static readInitialViewportDimension(
    storage: LocalStorage | undefined,
    key: string,
    fallback: number
  ): number {
    if (storage === undefined) {
      return fallback;
    }
    return BrowserWindowRuntime.normalizeInitialViewportDimension(storage.get<number>(key), fallback);
  }

  private static normalizeInitialViewportDimension(value: number | undefined, fallback: number): number {
    if (value === undefined || !Number.isFinite(value) || value <= 0) {
      return fallback;
    }
    return Math.max(1, Math.round(value));
  }

  static applyActiveWindowIdToRegisteredStorage(windowId: string): string {
    const normalized = BrowserWindowRuntime.resolveWindowId(windowId);
    const storage = BrowserWindowRuntime.windowStorages[BrowserWindowRuntime.activeWindowId];
    if (storage !== undefined) {
      BrowserWindowRuntime.writeWindowId(storage, normalized);
    }
    return normalized;
  }

  static updateWindowTabSummary(windowId: string, activeTabId: string, tabIds: string[]): void {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    const normalizedTabIds = tabIds.filter((tabId: string) => tabId.length > 0);
    const summaryLine =
      `windowTabs window=${normalizedWindowId} activeTab=${activeTabId || 'none'} ` +
      `tabCount=${normalizedTabIds.length} tabs=${normalizedTabIds.length > 0 ? normalizedTabIds.join(',') : 'none'}`;
    BrowserWindowRuntime.windowTabSummaries[normalizedWindowId] = {
      windowId: normalizedWindowId,
      activeTabId: activeTabId,
      tabCount: normalizedTabIds.length,
      tabIds: normalizedTabIds,
      summaryLine: summaryLine
    };
  }

  static stageLaunchPayload(payload: BrowserLaunchPayload, preferredWindowId?: string): string {
    const targetWindowId = payload.openInNewWindow
      ? BrowserWindowRuntime.resolveNewWindowLaunchTargetWindowId(preferredWindowId)
      : BrowserWindowRuntime.resolveLaunchTargetWindowId(preferredWindowId);
    BrowserWindowRuntime.pendingLaunches[targetWindowId] = payload;
    BrowserWindowRuntime.reconcileWebAppPresentationForLaunch(targetWindowId, payload);
    const storage = BrowserWindowRuntime.windowStorages[targetWindowId];
    if (storage !== undefined) {
      BrowserWindowRuntime.writeLaunch(storage, payload);
    }
    return targetWindowId;
  }

  static stageLaunchPayloadAt(payload: BrowserLaunchPayload, windowId: string): string {
    const normalized = BrowserWindowRuntime.resolveWindowId(windowId);
    BrowserWindowRuntime.pendingLaunches[normalized] = payload;
    BrowserWindowRuntime.reconcileWebAppPresentationForLaunch(normalized, payload);
    const storage = BrowserWindowRuntime.windowStorages[normalized];
    if (storage !== undefined) {
      BrowserWindowRuntime.writeLaunch(storage, payload);
    }
    return normalized;
  }

  static consumePendingLaunchThroughWindowOwner(windowId: string, source: string): boolean {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    return BrowserWindowRuntime.windowSessions[normalizedWindowId]?.consumePendingLaunch(source) ?? false;
  }

  static stageLaunchPayloadAtAndActivateStorage(payload: BrowserLaunchPayload, windowId: string): string {
    const normalized = BrowserWindowRuntime.stageLaunchPayloadAt(payload, windowId);
    BrowserWindowRuntime.applyActiveWindowIdToRegisteredStorage(normalized);
    return normalized;
  }

  static consumePendingLaunch(windowId: string, storage?: LocalStorage): BrowserLaunchPayload | undefined {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    const pendingLaunch = BrowserWindowRuntime.pendingLaunches[normalizedWindowId] ??
      BrowserWindowRuntime.readLaunch(storage ?? BrowserWindowRuntime.windowStorages[normalizedWindowId]);
    BrowserWindowRuntime.pendingLaunches = BrowserWindowRuntime.filterRecord(
      BrowserWindowRuntime.pendingLaunches,
      (key: string) => key !== normalizedWindowId
    );
    const targetStorage = storage ?? BrowserWindowRuntime.windowStorages[normalizedWindowId];
    if (targetStorage !== undefined) {
      BrowserWindowRuntime.clearLaunch(targetStorage);
    }
    return pendingLaunch;
  }

  static peekPendingLaunch(windowId: string, storage?: LocalStorage): BrowserLaunchPayload | undefined {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    return BrowserWindowRuntime.pendingLaunches[normalizedWindowId] ??
      BrowserWindowRuntime.readLaunch(storage ?? BrowserWindowRuntime.windowStorages[normalizedWindowId]);
  }

  private static reconcileWebAppPresentationForLaunch(
    windowId: string,
    payload: BrowserLaunchPayload | undefined
  ): void {
    if (payload?.shortcut === undefined) {
      return;
    }
    BrowserWindowRuntime.windowSessions[windowId]?.reconcileWebAppPresentation(true);
  }

  static stageTabWindowMove(sourceWindowId: string, tab: BrowserTabState): BrowserTabWindowMoveRequest {
    const requestId = BrowserWindowRuntime.createRuntimeRequestId('tab-move');
    const targetWindowInstanceId = BrowserWindowRuntime.createRuntimeRequestId('window');
    const request: BrowserTabWindowMoveRequest = {
      requestId: requestId,
      sourceWindowId: BrowserWindowRuntime.resolveWindowId(sourceWindowId),
      targetWindowInstanceId: targetWindowInstanceId,
      tab: BrowserWindowRuntime.cloneTabState(tab),
      stagedAt: Date.now()
    };
    BrowserWindowRuntime.pendingTabWindowMoves[requestId] = {
      request: request,
      claimedAt: 0
    };
    return BrowserWindowRuntime.cloneTabWindowMoveRequest(request);
  }

  static claimTabWindowMove(requestId: string): BrowserTabWindowMoveRequest | undefined {
    const normalizedRequestId = requestId.trim();
    const record = BrowserWindowRuntime.pendingTabWindowMoves[normalizedRequestId];
    if (record === undefined) {
      return undefined;
    }
    record.claimedAt = Date.now();
    return BrowserWindowRuntime.cloneTabWindowMoveRequest(record.request);
  }

  static acknowledgeTabWindowMove(acknowledgement: BrowserTabWindowMoveAcknowledgement): void {
    const normalizedRequestId = acknowledgement.requestId.trim();
    const record = BrowserWindowRuntime.pendingTabWindowMoves[normalizedRequestId];
    if (record === undefined) {
      return;
    }
    record.acknowledgement = {
      requestId: normalizedRequestId,
      accepted: acknowledgement.accepted,
      targetWindowId: BrowserWindowRuntime.resolveWindowId(acknowledgement.targetWindowId),
      targetTabId: acknowledgement.targetTabId.trim(),
      message: acknowledgement.message
    };
  }

  static waitForTabWindowMoveAcknowledgement(
    requestId: string,
    timeoutMs: number = 15000
  ): Promise<BrowserTabWindowMoveAcknowledgement> {
    const normalizedRequestId = requestId.trim();
    const deadline = Date.now() + Math.max(1000, Math.floor(timeoutMs));
    return new Promise<BrowserTabWindowMoveAcknowledgement>((resolve) => {
      const timer = setInterval((): void => {
        const record = BrowserWindowRuntime.pendingTabWindowMoves[normalizedRequestId];
        if (record?.acknowledgement !== undefined) {
          clearInterval(timer);
          resolve(record.acknowledgement);
          return;
        }
        if (record === undefined || Date.now() >= deadline) {
          clearInterval(timer);
          resolve({
            requestId: normalizedRequestId,
            accepted: false,
            targetWindowId: '',
            targetTabId: '',
            message: record === undefined ? '标签页移动请求已失效。' : '新窗口未能及时接收标签页。'
          });
        }
      }, 40);
    });
  }

  static finishTabWindowMove(requestId: string): void {
    const normalizedRequestId = requestId.trim();
    BrowserWindowRuntime.pendingTabWindowMoves = BrowserWindowRuntime.filterRecord(
      BrowserWindowRuntime.pendingTabWindowMoves,
      (key: string) => key !== normalizedRequestId
    );
  }

  private static resolveLaunchTargetWindowId(preferredWindowId?: string): string {
    const preferred = BrowserWindowRuntime.resolveWindowId(preferredWindowId);
    if (preferred.length > 0 && preferred !== DEFAULT_WINDOW_ID) {
      return preferred;
    }
    if (BrowserWindowRuntime.activeWindowId.length > 0) {
      return BrowserWindowRuntime.activeWindowId;
    }
    return BrowserWindowRuntime.registeredWindowIds[0] ?? DEFAULT_WINDOW_ID;
  }

  private static resolveNewWindowLaunchTargetWindowId(preferredWindowId?: string): string {
    const preferred = BrowserWindowRuntime.resolveWindowId(preferredWindowId);
    if (preferred !== DEFAULT_WINDOW_ID &&
      preferred !== BrowserWindowRuntime.activeWindowId &&
      BrowserWindowRuntime.registeredWindowIds.indexOf(preferred) >= 0) {
      return preferred;
    }
    return DEFAULT_WINDOW_ID;
  }

  private static rehomePendingLaunch(
    closingWindowId: string,
    payload: BrowserLaunchPayload
  ): void {
    const fallbackWindowId = BrowserWindowRuntime.resolveLaunchTargetWindowId(closingWindowId);
    const targetWindowId = fallbackWindowId === closingWindowId ? DEFAULT_WINDOW_ID : fallbackWindowId;
    const existingLaunch = BrowserWindowRuntime.pendingLaunches[targetWindowId];
    if (existingLaunch !== undefined && existingLaunch.receivedAt > payload.receivedAt) {
      return;
    }
    BrowserWindowRuntime.pendingLaunches[targetWindowId] = payload;
    const targetStorage = BrowserWindowRuntime.windowStorages[targetWindowId];
    if (targetStorage !== undefined) {
      BrowserWindowRuntime.writeLaunch(targetStorage, payload);
    }
  }

  private static writeWindowId(storage: LocalStorage, windowId: string): void {
    storage.setOrCreate(STORAGE_WINDOW_ID_KEY, windowId);
    storage.set(STORAGE_WINDOW_ID_KEY, windowId);
  }

  private static writeLaunch(storage: LocalStorage, payload: BrowserLaunchPayload): void {
    storage.setOrCreate(STORAGE_LAUNCH_URI_KEY, payload.uri);
    storage.setOrCreate(STORAGE_LAUNCH_ACTION_KEY, payload.action);
    storage.setOrCreate(STORAGE_LAUNCH_TYPE_KEY, payload.type);
    storage.setOrCreate(STORAGE_LAUNCH_SOURCE_KEY, payload.source);
    storage.setOrCreate(STORAGE_LAUNCH_APP_SHORTCUT_KEY, payload.appShortcut);
    storage.setOrCreate(STORAGE_LAUNCH_RECEIVED_AT_KEY, payload.receivedAt);
    storage.setOrCreate(STORAGE_LAUNCH_NEW_WINDOW_KEY, payload.openInNewWindow);
    storage.setOrCreate(STORAGE_LAUNCH_PROFILE_ID_KEY, payload.profileId);
    storage.setOrCreate(STORAGE_LAUNCH_PRIVACY_MODE_KEY, payload.privacyMode);
    storage.setOrCreate(STORAGE_LAUNCH_DATA_SCOPE_KEY, payload.dataScope);
    storage.setOrCreate(STORAGE_LAUNCH_PRIVATE_WINDOW_INSTANCE_ID_KEY, payload.privateWindowInstanceId);
    storage.setOrCreate(STORAGE_LAUNCH_TAB_MOVE_WINDOW_INSTANCE_ID_KEY, payload.tabMoveWindowInstanceId);
    storage.setOrCreate(STORAGE_LAUNCH_TAB_MOVE_REQUEST_ID_KEY, payload.tabMoveRequestId);
    BrowserWindowRuntime.writeShortcutLaunchContext(storage, payload.shortcut);
    storage.set(STORAGE_LAUNCH_URI_KEY, payload.uri);
    storage.set(STORAGE_LAUNCH_ACTION_KEY, payload.action);
    storage.set(STORAGE_LAUNCH_TYPE_KEY, payload.type);
    storage.set(STORAGE_LAUNCH_SOURCE_KEY, payload.source);
    storage.set(STORAGE_LAUNCH_APP_SHORTCUT_KEY, payload.appShortcut);
    storage.set(STORAGE_LAUNCH_RECEIVED_AT_KEY, payload.receivedAt);
    storage.set(STORAGE_LAUNCH_NEW_WINDOW_KEY, payload.openInNewWindow);
    storage.set(STORAGE_LAUNCH_PROFILE_ID_KEY, payload.profileId);
    storage.set(STORAGE_LAUNCH_PRIVACY_MODE_KEY, payload.privacyMode);
    storage.set(STORAGE_LAUNCH_DATA_SCOPE_KEY, payload.dataScope);
    storage.set(STORAGE_LAUNCH_PRIVATE_WINDOW_INSTANCE_ID_KEY, payload.privateWindowInstanceId);
    storage.set(STORAGE_LAUNCH_TAB_MOVE_WINDOW_INSTANCE_ID_KEY, payload.tabMoveWindowInstanceId);
    storage.set(STORAGE_LAUNCH_TAB_MOVE_REQUEST_ID_KEY, payload.tabMoveRequestId);
    BrowserWindowRuntime.writeShortcutLaunchContext(storage, payload.shortcut);
  }

  private static readLaunch(storage: LocalStorage | undefined): BrowserLaunchPayload | undefined {
    if (storage === undefined) {
      return undefined;
    }
    const uri = String(storage.get(STORAGE_LAUNCH_URI_KEY) ?? '').trim();
    const appShortcut = normalizeAiraAppShortcutTarget(storage.get(STORAGE_LAUNCH_APP_SHORTCUT_KEY) as string | undefined);
    const shortcut = BrowserWindowRuntime.readShortcutLaunchContext(storage);
    const privateWindowInstanceId = String(
      storage.get(STORAGE_LAUNCH_PRIVATE_WINDOW_INSTANCE_ID_KEY) ?? ''
    ).trim();
    const tabMoveWindowInstanceId = String(
      storage.get(STORAGE_LAUNCH_TAB_MOVE_WINDOW_INSTANCE_ID_KEY) ?? ''
    ).trim();
    const tabMoveRequestId = String(storage.get(STORAGE_LAUNCH_TAB_MOVE_REQUEST_ID_KEY) ?? '').trim();
    if (uri.length === 0 && appShortcut.length === 0 && shortcut === undefined &&
      privateWindowInstanceId.length === 0 && tabMoveRequestId.length === 0) {
      return undefined;
    }
    return {
      uri: uri,
      action: String(storage.get(STORAGE_LAUNCH_ACTION_KEY) ?? ''),
      type: String(storage.get(STORAGE_LAUNCH_TYPE_KEY) ?? ''),
      source: String(storage.get(STORAGE_LAUNCH_SOURCE_KEY) ?? ''),
      appShortcut: appShortcut,
      receivedAt: Number(storage.get(STORAGE_LAUNCH_RECEIVED_AT_KEY) ?? Date.now()),
      openInNewWindow: Boolean(storage.get(STORAGE_LAUNCH_NEW_WINDOW_KEY) ?? false),
      profileId: normalizeBrowserProfileId(storage.get(STORAGE_LAUNCH_PROFILE_ID_KEY) as string | undefined),
      privacyMode: normalizeBrowserSessionPrivacyMode(storage.get(STORAGE_LAUNCH_PRIVACY_MODE_KEY) as string | undefined),
      dataScope: normalizeBrowserDataScope(
        storage.get(STORAGE_LAUNCH_DATA_SCOPE_KEY) as string | undefined,
        normalizeBrowserSessionPrivacyMode(storage.get(STORAGE_LAUNCH_PRIVACY_MODE_KEY) as string | undefined)
      ),
      privateWindowInstanceId: privateWindowInstanceId,
      tabMoveWindowInstanceId: tabMoveWindowInstanceId,
      tabMoveRequestId: tabMoveRequestId,
      shortcut: shortcut
    };
  }

  private static clearLaunch(storage: LocalStorage): void {
    storage.set(STORAGE_LAUNCH_URI_KEY, '');
    storage.set(STORAGE_LAUNCH_ACTION_KEY, '');
    storage.set(STORAGE_LAUNCH_TYPE_KEY, '');
    storage.set(STORAGE_LAUNCH_SOURCE_KEY, '');
    storage.set(STORAGE_LAUNCH_APP_SHORTCUT_KEY, '');
    storage.set(STORAGE_LAUNCH_RECEIVED_AT_KEY, 0);
    storage.set(STORAGE_LAUNCH_NEW_WINDOW_KEY, false);
    storage.set(STORAGE_LAUNCH_PROFILE_ID_KEY, DEFAULT_BROWSER_PROFILE_ID);
    storage.set(STORAGE_LAUNCH_PRIVACY_MODE_KEY, 'regular');
    storage.set(STORAGE_LAUNCH_DATA_SCOPE_KEY, 'profile_persistent');
    storage.set(STORAGE_LAUNCH_PRIVATE_WINDOW_INSTANCE_ID_KEY, '');
    storage.set(STORAGE_LAUNCH_TAB_MOVE_WINDOW_INSTANCE_ID_KEY, '');
    storage.set(STORAGE_LAUNCH_TAB_MOVE_REQUEST_ID_KEY, '');
    BrowserWindowRuntime.writeShortcutLaunchContext(storage, undefined);
  }

  private static createRuntimeRequestId(prefix: string): string {
    const randomPart = Math.floor(Math.random() * 0xFFFFFF).toString(36);
    return `${prefix}-${Date.now().toString(36)}-${randomPart}`;
  }

  private static cloneTabWindowMoveRequest(request: BrowserTabWindowMoveRequest): BrowserTabWindowMoveRequest {
    return {
      requestId: request.requestId,
      sourceWindowId: request.sourceWindowId,
      targetWindowInstanceId: request.targetWindowInstanceId,
      tab: BrowserWindowRuntime.cloneTabState(request.tab),
      stagedAt: request.stagedAt
    };
  }

  private static cloneTabState(tab: BrowserTabState): BrowserTabState {
    return {
      id: tab.id,
      profileId: tab.profileId,
      title: tab.title,
      url: tab.url,
      isHome: tab.isHome,
      lastActiveAt: tab.lastActiveAt,
      pendingUrl: tab.pendingUrl,
      navigationHistory: tab.navigationHistory.slice(),
      navigationIndex: tab.navigationIndex,
      runtimeState: tab.runtimeState,
      lastError: tab.lastError,
      lastRestoreReason: tab.lastRestoreReason,
      lastDiscardReason: tab.lastDiscardReason,
      lastCrashReason: tab.lastCrashReason,
      lastLoadedAt: tab.lastLoadedAt,
      webStatePath: tab.webStatePath,
      webStateUpdatedAt: tab.webStateUpdatedAt,
      scrollOffsetY: tab.scrollOffsetY,
      lastGoodUrl: tab.lastGoodUrl,
      lastGoodTitle: tab.lastGoodTitle,
      lastRestorableUrl: tab.lastRestorableUrl,
      lastRestorableTitle: tab.lastRestorableTitle,
      lastRestoreType: tab.lastRestoreType,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      launchContext: {
        sourceType: tab.launchContext.sourceType,
        sourceId: tab.launchContext.sourceId,
        sourceUrl: tab.launchContext.sourceUrl,
        key: tab.launchContext.key
      },
      openerTabId: tab.openerTabId,
      openSource: tab.openSource,
      openedByNewWindow: tab.openedByNewWindow,
      pinned: tab.pinned,
      muted: tab.muted,
      audible: tab.audible
    };
  }

  private static writeShortcutLaunchContext(
    storage: LocalStorage,
    shortcut: BrowserLaunchShortcutContext | undefined
  ): void {
    storage.setOrCreate(STORAGE_LAUNCH_SHORTCUT_ID_KEY, '');
    storage.setOrCreate(STORAGE_LAUNCH_SHORTCUT_TITLE_KEY, '');
    storage.setOrCreate(STORAGE_LAUNCH_SHORTCUT_ICON_PATH_KEY, '');
    storage.setOrCreate(STORAGE_LAUNCH_SHORTCUT_SCOPE_KEY, '');
    storage.setOrCreate(STORAGE_LAUNCH_SHORTCUT_MANIFEST_URL_KEY, '');
    storage.setOrCreate(STORAGE_LAUNCH_SHORTCUT_ORIGIN_KEY, '');
    storage.setOrCreate(STORAGE_LAUNCH_SHORTCUT_THEME_COLOR_KEY, '');
    storage.setOrCreate(STORAGE_LAUNCH_SHORTCUT_CREATED_AT_KEY, 0);
    storage.set(STORAGE_LAUNCH_SHORTCUT_ID_KEY, shortcut?.shortcutId ?? '');
    storage.set(STORAGE_LAUNCH_SHORTCUT_TITLE_KEY, shortcut?.title ?? '');
    storage.set(STORAGE_LAUNCH_SHORTCUT_ICON_PATH_KEY, shortcut?.iconPath ?? '');
    storage.set(STORAGE_LAUNCH_SHORTCUT_SCOPE_KEY, shortcut?.scope ?? '');
    storage.set(STORAGE_LAUNCH_SHORTCUT_MANIFEST_URL_KEY, shortcut?.manifestUrl ?? '');
    storage.set(STORAGE_LAUNCH_SHORTCUT_ORIGIN_KEY, shortcut?.origin ?? '');
    storage.set(STORAGE_LAUNCH_SHORTCUT_THEME_COLOR_KEY, shortcut?.themeColor ?? '');
    storage.set(STORAGE_LAUNCH_SHORTCUT_CREATED_AT_KEY, shortcut?.createdAt ?? 0);
  }

  private static readShortcutLaunchContext(storage: LocalStorage): BrowserLaunchShortcutContext | undefined {
    const shortcutId = String(storage.get(STORAGE_LAUNCH_SHORTCUT_ID_KEY) ?? '').trim();
    if (shortcutId.length === 0) {
      return undefined;
    }
    const createdAt = Number(storage.get(STORAGE_LAUNCH_SHORTCUT_CREATED_AT_KEY) as number | string | undefined ?? 0);
    return {
      shortcutId: shortcutId,
      title: String(storage.get(STORAGE_LAUNCH_SHORTCUT_TITLE_KEY) ?? '').trim(),
      iconPath: String(storage.get(STORAGE_LAUNCH_SHORTCUT_ICON_PATH_KEY) ?? '').trim(),
      scope: String(storage.get(STORAGE_LAUNCH_SHORTCUT_SCOPE_KEY) ?? '').trim(),
      manifestUrl: String(storage.get(STORAGE_LAUNCH_SHORTCUT_MANIFEST_URL_KEY) ?? '').trim(),
      origin: String(storage.get(STORAGE_LAUNCH_SHORTCUT_ORIGIN_KEY) ?? '').trim(),
      themeColor: String(storage.get(STORAGE_LAUNCH_SHORTCUT_THEME_COLOR_KEY) ?? '').trim(),
      createdAt: Number.isFinite(createdAt) ? createdAt : 0
    };
  }

  private static filterRecord<T>(source: Record<string, T>, predicate: (key: string) => boolean): Record<string, T> {
    const result: Record<string, T> = {};
    Object.keys(source).forEach((key: string) => {
      if (predicate(key)) {
        result[key] = source[key];
      }
    });
    return result;
  }

  private static clearPendingLaunchStorage(windowId: string): void {
    const storage = BrowserWindowRuntime.windowStorages[windowId];
    if (storage !== undefined) {
      BrowserWindowRuntime.clearLaunch(storage);
    }
  }

  private static nextSessionLifetimeRevision(): number {
    BrowserWindowRuntime.windowSessionLifetimeRevision += 1;
    return BrowserWindowRuntime.windowSessionLifetimeRevision;
  }
}

export function buildBrowserLaunchPayload(input: BrowserLaunchPayloadInput): BrowserLaunchPayload {
  const privacyMode = normalizeBrowserSessionPrivacyMode(input.privacyMode);
  return {
    uri: input.uri.trim(),
    action: String(input.action ?? ''),
    type: String(input.type ?? ''),
    source: input.source,
    appShortcut: normalizeAiraAppShortcutTarget(input.appShortcut),
    receivedAt: input.receivedAt ?? Date.now(),
    openInNewWindow: Boolean(input.openInNewWindow ?? false),
    profileId: normalizeBrowserProfileId(input.profileId),
    privacyMode: privacyMode,
    dataScope: normalizeBrowserDataScope(input.dataScope, privacyMode),
    privateWindowInstanceId: String(input.privateWindowInstanceId ?? '').trim(),
    tabMoveWindowInstanceId: String(input.tabMoveWindowInstanceId ?? '').trim(),
    tabMoveRequestId: String(input.tabMoveRequestId ?? '').trim(),
    continuation: sharedBrowserContinuationCoordinator.copyPayload(input.continuation),
    shortcut: input.shortcut
  };
}

export function resolveBrowserTabSessionProfileId(
  activeProfileId?: BrowserProfileId | string,
  pendingLaunchPayload?: BrowserLaunchPayload
): BrowserProfileId {
  if (typeof activeProfileId === 'string' && activeProfileId.trim().length > 0) {
    return normalizeBrowserProfileId(activeProfileId);
  }
  if (pendingLaunchPayload !== undefined) {
    return pendingLaunchPayload.profileId;
  }
  return DEFAULT_BROWSER_PROFILE_ID;
}

export function resolveBrowserLaunchPayloadFromWant(want: Want | undefined, source: string): BrowserLaunchPayload | undefined {
  if (want === undefined) {
    return undefined;
  }
  const parameters = want.parameters as Record<string, Object> | undefined;
  const shortcutSource = String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.source] ?? '').trim();
  const privateWindowSource = String(parameters?.[BROWSER_PRIVATE_WINDOW_SOURCE_WANT_KEY] ?? '').trim();
  const privateWindowInstanceId = privateWindowSource === BROWSER_PRIVATE_WINDOW_LAUNCH_SOURCE
    ? String(parameters?.[BROWSER_PRIVATE_WINDOW_INSTANCE_ID_WANT_KEY] ?? '').trim()
    : '';
  const tabMoveSource = String(parameters?.[BROWSER_TAB_WINDOW_MOVE_SOURCE_WANT_KEY] ?? '').trim();
  const tabMoveWindowInstanceId = tabMoveSource === BROWSER_TAB_WINDOW_MOVE_LAUNCH_SOURCE
    ? String(parameters?.[BROWSER_TAB_WINDOW_MOVE_INSTANCE_ID_WANT_KEY] ?? '').trim()
    : '';
  const tabMoveRequestId = tabMoveSource === BROWSER_TAB_WINDOW_MOVE_LAUNCH_SOURCE
    ? String(parameters?.[BROWSER_TAB_WINDOW_MOVE_REQUEST_ID_WANT_KEY] ?? '').trim()
    : '';
  const appShortcut = normalizeAiraAppShortcutTarget(parameters?.[APP_SHORTCUT_WANT_KEY]);
  const searchInvocationSource = String(parameters?.[SEARCH_INVOCATION_SOURCE_WANT_KEY] ?? '').trim();
  const sourceUri = resolveBrowserLaunchUriFromWant(want, parameters, shortcutSource);
  const launchType = String(want.type ?? parameters?.['type'] ?? '');
  const uri = resolveBrowserLaunchViewerUri(sourceUri, launchType);
  const shortcut = resolveShortcutContextFromWant(parameters, shortcutSource);
  const trustedControls = resolveTrustedAiraLaunchControls(parameters, shortcut);
  if (uri.length === 0 && shortcut === undefined && appShortcut.length === 0 &&
    privateWindowInstanceId.length === 0 && tabMoveRequestId.length === 0) {
    return undefined;
  }
  if (privateWindowInstanceId.length > 0) {
    return buildBrowserLaunchPayload({
      uri: uri,
      source: BROWSER_PRIVATE_WINDOW_LAUNCH_SOURCE,
      openInNewWindow: Boolean(parameters?.[BROWSER_PRIVATE_WINDOW_OPEN_NEW_WANT_KEY] ?? true),
      profileId: String(parameters?.[BROWSER_PRIVATE_WINDOW_PROFILE_ID_WANT_KEY] ?? DEFAULT_BROWSER_PROFILE_ID),
      privacyMode: String(parameters?.[BROWSER_PRIVATE_WINDOW_PRIVACY_MODE_WANT_KEY] ?? 'private'),
      dataScope: String(parameters?.[BROWSER_PRIVATE_WINDOW_DATA_SCOPE_WANT_KEY] ?? 'session_ephemeral'),
      privateWindowInstanceId: privateWindowInstanceId
    });
  }
  if (tabMoveWindowInstanceId.length > 0 && tabMoveRequestId.length > 0) {
    return buildBrowserLaunchPayload({
      uri: uri,
      source: BROWSER_TAB_WINDOW_MOVE_LAUNCH_SOURCE,
      openInNewWindow: true,
      profileId: String(parameters?.[BROWSER_TAB_WINDOW_MOVE_PROFILE_ID_WANT_KEY] ?? DEFAULT_BROWSER_PROFILE_ID),
      privacyMode: String(parameters?.[BROWSER_TAB_WINDOW_MOVE_PRIVACY_MODE_WANT_KEY] ?? 'regular'),
      dataScope: String(parameters?.[BROWSER_TAB_WINDOW_MOVE_DATA_SCOPE_WANT_KEY] ?? 'profile_persistent'),
      tabMoveWindowInstanceId: tabMoveWindowInstanceId,
      tabMoveRequestId: tabMoveRequestId
    });
  }
  return buildBrowserLaunchPayload({
    uri: uri,
    action: String(want.action ?? parameters?.['action'] ?? ''),
    type: launchType,
    source: appShortcut.length > 0
      ? resolveAppShortcutLaunchSource(appShortcut, searchInvocationSource)
      : source,
    appShortcut: appShortcut,
    receivedAt: Date.now(),
    openInNewWindow: trustedControls.openInNewWindow,
    shortcut: shortcut
  });
}

function resolveAppShortcutLaunchSource(
  appShortcut: AiraAppShortcutTarget | '',
  searchInvocationSource: string
): string {
  if (appShortcut === 'search' && searchInvocationSource === BROWSER_SEARCH_DESKTOP_CARD_SOURCE) {
    return BROWSER_SEARCH_DESKTOP_CARD_SOURCE;
  }
  return APP_SHORTCUT_SOURCE;
}

function resolveTrustedAiraLaunchControls(
  parameters: Record<string, Object> | undefined,
  shortcut: BrowserLaunchShortcutContext | undefined
): BrowserTrustedLaunchControls {
  if (shortcut === undefined) {
    return {
      openInNewWindow: false
    };
  }
  return {
    openInNewWindow: Boolean(parameters?.['aira.openInNewWindow'] ?? false)
  };
}

function resolveShortcutContextFromWant(
  parameters: Record<string, Object> | undefined,
  shortcutSource: string
): BrowserLaunchShortcutContext | undefined {
  if (shortcutSource !== DESKTOP_WEB_SHORTCUT_SOURCE) {
    return undefined;
  }
  const shortcutId = String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.shortcutId] ?? '').trim();
  if (shortcutId.length === 0) {
    return undefined;
  }
  const createdAtRaw = parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.createdAt];
  const createdAt = Number(createdAtRaw ?? 0);
  return {
    shortcutId: shortcutId,
    title: String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.title] ?? parameters?.['title'] ?? '').trim(),
    iconPath: String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.iconPath] ?? '').trim(),
    scope: String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.scope] ?? '').trim(),
    manifestUrl: String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.manifestUrl] ?? '').trim(),
    origin: String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.origin] ?? '').trim(),
    themeColor: String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.themeColor] ?? '').trim(),
    createdAt: Number.isFinite(createdAt) ? createdAt : 0
  };
}

export function resolveBrowserLaunchWindowId(payload: BrowserLaunchPayload): string {
  if (payload.tabMoveWindowInstanceId.length > 0) {
    return `browser-window:${payload.tabMoveWindowInstanceId}`;
  }
  if (payload.privateWindowInstanceId.length > 0) {
    return `private-window:${payload.privateWindowInstanceId}`;
  }
  if (payload.appShortcut.length > 0) {
    return DEFAULT_WINDOW_ID;
  }
  if (payload.shortcut === undefined) {
    return DEFAULT_WINDOW_ID;
  }
  return `web-app:${payload.shortcut.shortcutId}`;
}

function resolveBrowserLaunchUriFromWant(
  want: Want,
  parameters: Record<string, Object> | undefined,
  shortcutSource: string
): string {
  if (shortcutSource === DESKTOP_WEB_PAGE_SHORTCUT_SOURCE) {
    return String(parameters?.['targetUrl'] ?? parameters?.['url'] ?? parameters?.['uri'] ?? want.uri ?? '').trim();
  }
  return String(want.uri ?? parameters?.['uri'] ?? parameters?.['url'] ?? parameters?.['targetUrl'] ?? '').trim();
}

function resolveBrowserLaunchViewerUri(uri: string, type: string): string {
  const normalizedUri = uri.trim();
  if (!documentViewerService.isDocumentSourceUrl(normalizedUri, type)) {
    return normalizedUri;
  }
  return documentViewerService.buildViewerUrl(normalizedUri, type);
}

export function normalizeAiraAppShortcutTarget(raw: Object | string | undefined): AiraAppShortcutTarget | '' {
  const value = String(raw ?? '').trim();
  if (value === 'scanQr') {
    return value;
  }
  const key = value.replace(/[-_\s]/g, '').toLowerCase();
  switch (key) {
    case 'bookmarks':
      return 'bookmarks';
    case 'history':
      return 'history';
    case 'historystress':
    case 'historystress50000':
    case 'historystressseed':
      return 'history_stress_50000';
    case 'downloads':
      return 'downloads';
    case 'settings':
      return 'settings';
    case 'scanqr':
      return 'scanQr';
    case 'savedpages':
    case 'offlinepages':
      return 'saved_pages';
    case 'sync':
    case 'syncsettings':
      return 'sync';
    case 'airapro':
    case 'pro':
    case 'membership':
    case 'membershipcenter':
      return 'aira_pro';
    case 'search':
      return 'search';
    case 'searchsettings':
      return 'search_settings';
    case 'adblock':
    case 'adblocksettings':
      return 'ad_block_settings';
    case 'sitesettings':
    case 'permissions':
    case 'permissionsitesettings':
      return 'site_settings';
    case 'webpagetranslation':
    case 'webpagetranslationsettings':
    case 'translation':
    case 'translationsettings':
      return 'webpage_translation_settings';
    case 'passwords':
    case 'passwordsettings':
      return 'password_settings';
    case 'userscripts':
    case 'scripts':
      return 'user_scripts';
    case 'useragent':
    case 'useragentsettings':
      return 'user_agent_settings';
    case 'downloadsettings':
      return 'download_settings';
    case 'customhomepage':
    case 'customhomepagesettings':
      return 'custom_homepage_settings';
    case 'general':
    case 'generalsettings':
      return 'general_settings';
    case 'appearance':
    case 'appearancesettings':
      return 'appearance_settings';
    case 'appearancetoolbar':
    case 'appearancetoolbarsettings':
      return 'appearance_toolbar_settings';
    case 'privacy':
    case 'security':
    case 'privacysecurity':
    case 'privacysecuritysettings':
      return 'privacy_security_settings';
    case 'experiments':
    case 'experimentssettings':
      return 'experiments_settings';
    case 'about':
    case 'aboutsettings':
      return 'about_settings';
    case 'startup':
    case 'startupsettings':
      return 'startup_settings';
    case 'privatetabs':
    case 'privatetabssettings':
      return 'private_tabs_settings';
    case 'historyretention':
    case 'historyretentionsettings':
      return 'history_retention_settings';
    case 'themepalette':
    case 'themepalettesettings':
      return 'theme_palette_settings';
    case 'keyboardshortcuts':
    case 'keyboardshortcutssettings':
      return 'keyboard_shortcuts_settings';
    case 'appproxy':
    case 'appproxysettings':
      return 'app_proxy_settings';
    default:
      return '';
  }
}
