/**
 * 小说模式的会话快照与监听(驱动 NovelReaderOverlay)。
 * 采用"控制器持有快照 + 监听回调通知 UI"的模式,数据单位是"一本书 + 当前一章"。
 * 章节识别:当前章从 DOM 抽;上一章/下一章/目录靠页面里的文字链接 + fetch 后台抓。
 */

import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  ReaderModeBrightnessMode,
  ReaderModeLineHeight,
  ReaderModePageWidth,
  ReaderModeTheme
} from '../../common/models/BrowserModels';
import {
  NovelBookCoverPalette,
  NovelBookPaletteThemeMode
} from './NovelLibraryModels';
import {
  NovelSessionCommittedChapter,
  NovelSessionContentKind,
  NovelSessionFailureCode,
  NovelSessionOperationSnapshot
} from './NovelReadingSessionState';
import {
  ReadingPresentationMode,
  ReadingSurfaceAppearance
} from '../reading/ReadingSurfaceModels';

export const NOVEL_CATALOG_RANGE_SIZE: number = 100;

/** 目录里的一章:稳定零基章序 + 标题 + 章节 URL。 */
export interface NovelCatalogEntry {
  ordinal: number;
  title: string;
  url: string;
}

/** 仅保存站点分页规则的游标和值；传输 recipe 始终留在编译代码中。 */
export interface NovelCatalogPageCursor {
  ruleId: string;
  bookToken: string;
  initialPage: number;
  nextPage: number;
  pageSize: number;
  totalHint: number;
  totalPages: number;
}

export interface NovelCatalogPageResult {
  entries: NovelCatalogEntry[];
  cursor: NovelCatalogPageCursor;
  hasMore: boolean;
}

/** Reader-facing Catalog item with canonical Session identity. */
export interface NovelReaderCatalogEntry {
  id: string;
  ordinal: number;
  title: string;
  url: string;
}

/** 一次章节抽取结果(当前章或 fetch 抓来的章)。 */
export interface NovelChapterExtract {
  pageUrl: string;          // 实际承载本章的最终响应 URL（用于重定向后的相对链接和源页导航）
  title: string;
  paragraphs: string[];
  images: string[];        // 漫画整章图片(小说为空)
  prevUrl: string;
  nextUrl: string;
  catalogUrl: string;
  bookTitle: string;
  pageTotal: number;      // 该章被站点拆成几页(1=不分页)
  nextPageUrl: string;    // 同章下一页(非下一章)
}

/** 目录抓取结果:书籍信息 + 章节列表。 */
export interface NovelCatalogResult {
  bookTitle: string;
  author: string;
  coverUrl: string;
  complete: boolean;
  entries: NovelCatalogEntry[];
}

/** 接管首屏所需的轻量书籍概览；完整目录不属于这个关键路径。 */
export interface NovelBookOverview {
  contentKind: NovelContentKind;
  title: string;
  author: string;
  category: string;
  latest: string;
  cover: string;
  synopsis: string;
  host: string;
  catalogUrl: string;
  startChapterUrl: string;
  /** 当前活 DOM 的目录来源已由站点规则确认完整。 */
  catalogSourceComplete: boolean;
  catalogTotal: number;
  /** 首屏可用的小批章节；完整目录由后台目录流程负责。 */
  initialEntries: NovelCatalogEntry[];
  catalogPageCursor?: NovelCatalogPageCursor;
}

/** 小说模式当前呈现:书籍接管页 / 阅读器 / 空(未识别)。 */
export type NovelReaderMode = 'book' | 'reader' | 'empty';

export type NovelReaderPhase = 'inactive' | 'detecting' | 'book' | 'reader' | 'suspended';
export type NovelReaderPageEntryKind = '' | 'resume' | 'replace';

/** DOM 探测结果。空值表示没有识别为小说页面。 */
export type NovelDetectedPageType = '' | 'book' | 'chapter';

/** 内容类型:小说=翻页读文字,漫画=上下滚动看图。 */
export type NovelContentKind = NovelSessionContentKind;

export function resolveNovelContentLabel(contentKind: NovelContentKind): string {
  return contentKind === 'comic' ? '漫画' : '小说';
}

export function resolveNovelModeLabel(contentKind: NovelContentKind): string {
  return `${resolveNovelContentLabel(contentKind)}模式`;
}

export function resolveNovelReadingModeLabel(contentKind: NovelContentKind): string {
  return `${resolveNovelContentLabel(contentKind)}阅读模式`;
}

export type NovelReaderPageMode = ReadingPresentationMode;

export type NovelReaderControlPanel = 'text' | 'appearance' | 'settings';

export interface NovelReaderPreferences {
  fontSize: number;
  theme: ReaderModeTheme;
  lineHeight: ReaderModeLineHeight;
  pageWidth: ReaderModePageWidth;
  brightnessMode: ReaderModeBrightnessMode;
  brightnessPercent: number;
  pageMode: NovelReaderPageMode;
  autoReadingEnabled: boolean;
  autoReadingSpeed: number;
  volumeKeyPagingEnabled: boolean;
  systemStatusBarVisible: boolean;
  chapterNameVisible: boolean;
  pageNumberVisible: boolean;
}

export interface NovelReaderPreferencesPort {
  load(defaultValue: NovelReaderPreferences): Promise<NovelReaderPreferences>;
  save(value: NovelReaderPreferences): Promise<void>;
}

/** Regular profile 的阅读恢复记录；private scope 永远不调用该端口。 */
export interface NovelReadingCheckpointRecord {
  bookId: string;
  bookDetailUrl: string;
  chapterId: string;
  canonicalUrl: string;
  chapterTitle: string;
  characterOffset: number;
  updatedAt: number;
}

export interface NovelReadingCheckpointPort {
  load(bookId: string): Promise<NovelReadingCheckpointRecord | undefined>;
  loadByBookDetailUrl(bookDetailUrl: string): Promise<NovelReadingCheckpointRecord | undefined>;
  save(value: NovelReadingCheckpointRecord): Promise<void>;
  clear(bookId: string): Promise<void>;
}

export interface NovelReadingRecoveryMarkerRecord {
  bookIdentity: string;
  bookTitle: string;
  sourceTabId: string;
  sourcePageUrl: string;
  updatedAt: number;
}

export interface NovelReadingRecoveryMarkerPort {
  load(): Promise<NovelReadingRecoveryMarkerRecord | undefined>;
  save(value: NovelReadingRecoveryMarkerRecord): Promise<void>;
  clear(): Promise<void>;
}

export interface NovelCatalogCacheRecord {
  bookId: string;
  catalogUrl: string;
  sourceLatest: string;
  complete: boolean;
  cachedAt: number;
  entries: NovelCatalogEntry[];
  totalHint: number;
  pageCursor?: NovelCatalogPageCursor;
}

export interface NovelCatalogCachePort {
  read(bookId: string): Promise<NovelCatalogCacheRecord | undefined>;
  write(value: NovelCatalogCacheRecord): Promise<void>;
}

/** 通过抽取校验并提交过的规范化章节工件；不包含原始 HTML 或可执行脚本。 */
export interface NovelChapterArtifactCacheRecord {
  bookId: string;
  chapterId: string;
  bookDetailUrl: string;
  bookTitle: string;
  canonicalUrl: string;
  requestedUrl: string;
  finalUrl: string;
  title: string;
  contentKind: NovelContentKind;
  paragraphs: string[];
  images: string[];
  prevUrl: string;
  nextUrl: string;
  catalogUrl: string;
  cachedAt: number;
}

export interface NovelChapterArtifactCacheReadResult {
  artifact: NovelChapterArtifactCacheRecord;
  refreshRecommended: boolean;
}

export interface NovelChapterArtifactCachePort {
  readChapter(chapterUrl: string): Promise<NovelChapterArtifactCacheReadResult | undefined>;
  readLatestForBook(detailUrl: string): Promise<NovelChapterArtifactCacheReadResult | undefined>;
  write(value: NovelChapterArtifactCacheRecord): Promise<void>;
  markLatestForBook(value: NovelChapterArtifactCacheRecord): Promise<void>;
}

/** 未来持久化使用字符锚点,不能保存会随排版变化的页码。 */
export interface NovelReadingPosition {
  chapterId: string;
  characterOffset: number;
}

export interface NovelReaderSessionScope {
  tabId: string;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export type NovelTopPromptKind = '' | 'bookshelf_added' | 'auto_takeover';

export interface NovelTopPromptState {
  visible: boolean;
  key: string;
  kind: NovelTopPromptKind;
  bookTitle: string;
  contentKind: NovelContentKind;
}

export interface NovelReaderOverlayBackState {
  panelVisible: boolean;
  dismissPanelRequestVersion: number;
}

export interface NovelReaderPageReadyFacts {
  tabId: string;
  activeTabId: string;
  webPageVisible: boolean;
  pageUrl: string;
  acceptedNavigationCommitUrl?: string;
  scope: NovelReaderSessionScope;
}

export interface NovelReaderSnapshot {
  visible: boolean;
  reentryAvailable: boolean;  // 用户退出接管后,允许从原网页再次进入
  reentryPageUrl: string;
  phase: NovelReaderPhase;
  bookIdentity: string;
  pageEntryAvailable: boolean;
  pageEntryKind: NovelReaderPageEntryKind;
  pageEntryTabId: string;
  pageEntryPageUrl: string;
  bookTitle: string;
  bookAuthor: string;
  bookCoverUrl: string;
  bookCategory: string;      // 类别(图四)
  bookLatest: string;        // 最新章节名(图四)
  bookSynopsis: string;      // 简介(图四)
  sourceHost: string;        // 来源域名(图四)
  pageUrl: string;           // 当前章节 URL
  bookshelfDetailUrl: string; // 书架持久化使用的书籍详情页 URL，不随章节切换变化
  catalogUrl: string;        // 目录页 URL,无则为空
  catalog: NovelReaderCatalogEntry[];
  catalogLoadingMore: boolean;
  catalogLoadingRangeStart: number;
  catalogLoadingRangeEnd: number;
  catalogHasMore: boolean;
  catalogTotalHint: number;
  catalogRangeExtentHint: number;
  catalogSupportsRandomAccess: boolean;
  canNavigatePrevious: boolean;
  canNavigateNext: boolean;
  bookInBookshelf: boolean;
  bookshelfActionBusy: boolean;
  bookshelfAvailable: boolean;
  topPrompt: NovelTopPromptState;
  overlayBackState: NovelReaderOverlayBackState;
  bookPalette?: NovelBookCoverPalette;
  bookPaletteKey: string;
  bookPaletteLoading: boolean;
  preferences: NovelReaderPreferences;
  position: NovelReadingPosition;
  resumeHint: string;
  activeChapterId: string;
  contentKind: NovelContentKind;
  chapterTrail: NovelSessionCommittedChapter[];
  openingTransition: NovelSessionOperationSnapshot;
  chapterTransition: NovelSessionOperationSnapshot;
  catalogTransition: NovelSessionOperationSnapshot;
  openingFailure: NovelSessionFailureCode;
  scope: NovelReaderSessionScope;
}

type NovelReaderSimpleActionType =
  'close' |
  'cancel_close' |
  'confirm_close' |
  'suspend_to_home' |
  'continue_reading' |
  'activate_page_entry' |
  'previous_chapter' |
  'next_chapter' |
  'continue_vertical' |
  'open_catalog' |
  'retry_catalog' |
  'retry_chapter' |
  'return_to_source' |
  'copy_source_link' |
  'share_source_link' |
  'start_reading' |
  'toggle_bookshelf' |
  'dismiss_panel' |
  'dismiss_top_prompt';

interface NovelReaderSimpleAction {
  type: NovelReaderSimpleActionType;
}

interface NovelReaderSelectChapterAction {
  type: 'select_chapter';
  chapterId?: string;
  /** Frozen shell callback name; the value is a canonical Chapter ID, never a target URL. */
  url?: string;
}

interface NovelReaderLoadCatalogRangeAction {
  type: 'load_catalog_range';
  startOrdinal: number;
  endOrdinal: number;
}

interface NovelReaderOpenControlPanelAction {
  type: 'open_control_panel';
  panel: NovelReaderControlPanel;
}

interface NovelReaderAppearanceChangeAction {
  type: 'reading_appearance_change';
  appearance: ReadingSurfaceAppearance;
}

interface NovelReaderPageModeChangeAction {
  type: 'reading_page_mode_change';
  mode: NovelReaderPageMode;
}

interface NovelReaderAutoReadingChangeAction {
  type: 'auto_reading_change';
  enabled: boolean;
}

interface NovelReaderVolumeKeyPagingChangeAction {
  type: 'volume_key_paging_change';
  enabled: boolean;
}

interface NovelReaderChapterNameVisibilityChangeAction {
  type: 'chapter_name_visibility_change';
  visible: boolean;
}

interface NovelReaderPageNumberVisibilityChangeAction {
  type: 'page_number_visibility_change';
  visible: boolean;
}

interface NovelReaderPreferencesAction {
  type: 'update_preferences';
  preferences: NovelReaderPreferences;
}

interface NovelReaderProgressAction {
  type: 'progress_change';
  chapterId: string;
  characterOffset: number;
}

interface NovelReaderPanelVisibilityAction {
  type: 'panel_visibility_change';
  visible: boolean;
}

interface NovelReaderStatusBarVisibilityAction {
  type: 'status_bar_visibility_change';
  visible: boolean;
}

interface NovelReaderStatusBarVisibilityApplyAction {
  type: 'status_bar_visibility_apply';
  visible: boolean;
}

interface NovelReaderResolveBookPaletteAction {
  type: 'resolve_book_palette';
  themeMode: NovelBookPaletteThemeMode;
}

export type NovelReaderAction =
  NovelReaderSimpleAction |
  NovelReaderSelectChapterAction |
  NovelReaderLoadCatalogRangeAction |
  NovelReaderOpenControlPanelAction |
  NovelReaderAppearanceChangeAction |
  NovelReaderPageModeChangeAction |
  NovelReaderAutoReadingChangeAction |
  NovelReaderVolumeKeyPagingChangeAction |
  NovelReaderChapterNameVisibilityChangeAction |
  NovelReaderPageNumberVisibilityChangeAction |
  NovelReaderPreferencesAction |
  NovelReaderProgressAction |
  NovelReaderPanelVisibilityAction |
  NovelReaderStatusBarVisibilityAction |
  NovelReaderStatusBarVisibilityApplyAction |
  NovelReaderResolveBookPaletteAction;

export interface NovelReaderOpenCatalogEffect {
  type: 'open_catalog';
}

export interface NovelReaderOpenControlPanelEffect {
  type: 'open_control_panel';
  panel: NovelReaderControlPanel;
}

export interface NovelReaderCloseSystemSheetEffect {
  type: 'close_system_sheet';
}

export interface NovelReaderWindowBrightnessEffect {
  type: 'apply_window_brightness';
  brightnessMode: ReaderModeBrightnessMode;
  brightnessPercent: number;
}

export interface NovelReaderWindowBrightnessRestoreEffect {
  type: 'restore_window_brightness';
}

export interface NovelReaderExitConfirmationEffect {
  type: 'show_exit_confirmation';
  contentKind: NovelContentKind;
}

export interface NovelReaderStatusBarVisibilityEffect {
  type: 'status_bar_visibility_override';
  visible: boolean;
}

export interface NovelReaderStatusBarVisibilityReleaseEffect {
  type: 'status_bar_visibility_release';
}

export interface NovelReaderRevealBrowserHomeEffect {
  type: 'reveal_browser_home';
}

export interface NovelReaderActivateSourceTabEffect {
  type: 'activate_source_tab';
  tabId: string;
}

export interface NovelReaderRecoverSuspendedReadingEffect {
  type: 'recover_suspended_reading';
  tabId: string;
  url: string;
  title: string;
}

export interface NovelReaderSourceChapterNavigationEffect {
  type: 'navigate_source_chapter';
  tabId: string;
  url: string;
}

export interface NovelReaderCopySourceUrlEffect {
  type: 'copy_source_url';
  url: string;
}

export interface NovelReaderShareSourceUrlEffect {
  type: 'share_source_url';
  title: string;
  url: string;
}

export interface NovelReaderToastEffect {
  type: 'toast';
  message: string;
}

export type NovelReaderEffect = NovelReaderOpenCatalogEffect |
  NovelReaderOpenControlPanelEffect |
  NovelReaderCloseSystemSheetEffect |
  NovelReaderWindowBrightnessEffect |
  NovelReaderWindowBrightnessRestoreEffect |
  NovelReaderExitConfirmationEffect |
  NovelReaderStatusBarVisibilityEffect |
  NovelReaderStatusBarVisibilityReleaseEffect |
  NovelReaderRevealBrowserHomeEffect |
  NovelReaderActivateSourceTabEffect |
  NovelReaderRecoverSuspendedReadingEffect |
  NovelReaderSourceChapterNavigationEffect |
  NovelReaderCopySourceUrlEffect |
  NovelReaderShareSourceUrlEffect |
  NovelReaderToastEffect;

export interface NovelReaderSessionListener {
  onSnapshotChanged: (snapshot: NovelReaderSnapshot) => void;
  onEffect?: (effect: NovelReaderEffect) => boolean;
}

export function createDefaultNovelReaderPreferences(): NovelReaderPreferences {
  return {
    fontSize: 19,
    theme: 'system',
    lineHeight: 'comfortable',
    pageWidth: 'standard',
    brightnessMode: 'system',
    brightnessPercent: 60,
    pageMode: 'horizontal',
    autoReadingEnabled: false,
    autoReadingSpeed: 3,
    volumeKeyPagingEnabled: false,
    systemStatusBarVisible: false,
    chapterNameVisible: true,
    pageNumberVisible: true
  };
}

export function createDefaultNovelReaderSessionScope(): NovelReaderSessionScope {
  return {
    tabId: '',
    privacyMode: 'regular',
    dataScope: 'profile_persistent'
  };
}

export function createDefaultNovelReaderOverlayBackState(): NovelReaderOverlayBackState {
  return {
    panelVisible: false,
    dismissPanelRequestVersion: 0
  };
}

export function createDefaultNovelReaderSnapshot(): NovelReaderSnapshot {
  return {
    visible: false,
    reentryAvailable: false,
    reentryPageUrl: '',
    phase: 'inactive',
    bookIdentity: '',
    pageEntryAvailable: false,
    pageEntryKind: '',
    pageEntryTabId: '',
    pageEntryPageUrl: '',
    bookTitle: '',
    bookAuthor: '',
    bookCoverUrl: '',
    bookCategory: '',
    bookLatest: '',
    bookSynopsis: '',
    sourceHost: '',
    pageUrl: '',
    bookshelfDetailUrl: '',
    catalogUrl: '',
    catalog: [],
    catalogLoadingMore: false,
    catalogLoadingRangeStart: -1,
    catalogLoadingRangeEnd: -1,
    catalogHasMore: false,
    catalogTotalHint: 0,
    catalogRangeExtentHint: 0,
    catalogSupportsRandomAccess: false,
    canNavigatePrevious: false,
    canNavigateNext: false,
    bookInBookshelf: false,
    bookshelfActionBusy: false,
    bookshelfAvailable: false,
    topPrompt: {
      visible: false,
      key: '',
      kind: '',
      bookTitle: '',
      contentKind: 'novel'
    },
    overlayBackState: createDefaultNovelReaderOverlayBackState(),
    bookPaletteKey: '',
    bookPaletteLoading: false,
    preferences: createDefaultNovelReaderPreferences(),
    position: {
      chapterId: '',
      characterOffset: 0
    },
    resumeHint: '',
    activeChapterId: '',
    contentKind: 'novel',
    chapterTrail: [],
    openingTransition: { status: 'idle', requestId: '', failureCode: '' },
    chapterTransition: { status: 'idle', requestId: '', failureCode: '' },
    catalogTransition: { status: 'idle', requestId: '', failureCode: '' },
    openingFailure: '',
    scope: createDefaultNovelReaderSessionScope()
  };
}
