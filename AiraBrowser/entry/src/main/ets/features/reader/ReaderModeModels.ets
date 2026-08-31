import {
  ReaderModeBrightnessMode,
  ReaderModeLineHeight,
  ReaderModePageWidth,
  ReaderModePreferences,
  ReaderModeTheme
} from '../../common/models/BrowserModels';
import {
  ReadingPresentationMode,
  ReadingSurfaceAppearance
} from '../reading/ReadingSurfaceModels';

export type ReaderModeBlockType =
  'heading' |
  'paragraph' |
  'image' |
  'link' |
  'quote' |
  'list_item' |
  'code';

export interface ReaderModeBlock {
  id: string;
  type: ReaderModeBlockType;
  text: string;
  url?: string;
  originalUrl?: string;
  fallbackUrls?: string[];
  alt?: string;
  caption?: string;
  level?: number;
  width?: number;
  height?: number;
  renderedWidth?: number;
  renderedHeight?: number;
  qualityScore?: number;
  hiddenReason?: string;
  imageFailurePolicy?: string;
  sourceTagName?: string;
  sourceClassName?: string;
  sourceId?: string;
  sourceRole?: string;
}

export interface ReaderModeArticle {
  title: string;
  byline: string;
  siteName: string;
  publishedAt: string;
  url: string;
  excerpt: string;
  diagnostics?: ReaderModeArticleDiagnostics;
  blocks: ReaderModeBlock[];
}

export interface ReaderModeArticleDiagnostics {
  adapterId: string;
  sourceTagName: string;
  sourceClassName: string;
  sourceTextLength: number;
  sourceScore: number;
  candidateCount: number;
  extractionStrategy: string;
  rawBlockCount?: number;
  retainedBlockCount?: number;
  rawImageCount?: number;
  retainedImageCount?: number;
  hiddenImageCount?: number;
  postProcessSummary?: string;
}

export interface ReaderModeProbeCandidate {
  selector: string;
  tagName: string;
  textLength: number;
  paragraphCount: number;
  linkTextLength: number;
  score: number;
}

export interface ReaderModeProbeResult {
  url: string;
  title: string;
  host: string;
  siteName: string;
  publishedAt: string;
  paragraphCount: number;
  textLength: number;
  linkTextLength: number;
  candidates: ReaderModeProbeCandidate[];
}

export interface ReaderEligibilityResult {
  readable: boolean;
  score: number;
  reason: string;
  bestSelector: string;
}

export {
  ReaderModeLineHeight,
  ReaderModeBrightnessMode,
  ReaderModePageWidth,
  ReaderModePreferences,
  ReaderModeTheme
};

export interface ReaderModeSearchState {
  query: string;
  matches: number;
  activeIndex: number;
  activeBlockId: string;
  blockMatchCounts: Record<string, number>;
}

export interface ReaderModeViewState {
  visible: boolean;
  loading: boolean;
  errorMessage: string;
  article: ReaderModeArticle;
  preferences: ReaderModePreferences;
  search: ReaderModeSearchState;
}

export interface ReaderModeOverlayBackState {
  imagePreviewVisible: boolean;
  dismissImagePreviewRequestVersion: number;
  panelVisible: boolean;
  dismissPanelRequestVersion: number;
}

export type ReaderModeControlPanel = 'text' | 'appearance' | 'settings';

type ReaderModeSimpleActionType =
  'close' |
  'copy_link' |
  'share' |
  'bookmark' |
  'open_bookmarks' |
  'open_speech_player' |
  'search_previous' |
  'search_next';

interface ReaderModeSimpleAction {
  type: ReaderModeSimpleActionType;
}

interface ReaderModeOpenLinkAction {
  type: 'open_link';
  url: string;
}

interface ReaderModeSearchChangeAction {
  type: 'search_change';
  query: string;
}

interface ReaderModeOpenControlPanelAction {
  type: 'open_control_panel';
  panel: ReaderModeControlPanel;
}

interface ReaderModeAppearanceChangeAction {
  type: 'reading_appearance_change';
  appearance: ReadingSurfaceAppearance;
}

interface ReaderModePresentationModeChangeAction {
  type: 'reading_presentation_mode_change';
  mode: ReadingPresentationMode;
}

interface ReaderModePreferencesChangeAction {
  type: 'update_preferences';
  preferences: ReaderModePreferences;
  resetPresentationModeOverride?: boolean;
}

interface ReaderModeLayoutFailureAction {
  type: 'reading_layout_failure';
}

interface ReaderModeStatusBarVisibilityChangeAction {
  type: 'status_bar_visibility_change';
  visible: boolean;
  source: string;
}

interface ReaderModeOverlayVisibilityChangeAction {
  type: 'image_preview_visibility_change' | 'panel_visibility_change';
  visible: boolean;
}

export type ReaderModeAction =
  ReaderModeSimpleAction |
  ReaderModeOpenLinkAction |
  ReaderModeSearchChangeAction |
  ReaderModeOpenControlPanelAction |
  ReaderModeAppearanceChangeAction |
  ReaderModePresentationModeChangeAction |
  ReaderModePreferencesChangeAction |
  ReaderModeLayoutFailureAction |
  ReaderModeStatusBarVisibilityChangeAction |
  ReaderModeOverlayVisibilityChangeAction;

export function createEmptyReaderModeArticle(): ReaderModeArticle {
  return {
    title: '',
    byline: '',
    siteName: '',
    publishedAt: '',
    url: '',
    excerpt: '',
    blocks: []
  };
}

export function createDefaultReaderModePreferences(): ReaderModePreferences {
  return {
    fontSize: 18,
    theme: 'system',
    lineHeight: 'comfortable',
    pageWidth: 'wide',
    brightnessMode: 'system',
    brightnessPercent: 60,
    pageMode: 'vertical'
  };
}

export function createDefaultReaderModeViewState(): ReaderModeViewState {
  return {
    visible: false,
    loading: false,
    errorMessage: '',
    article: createEmptyReaderModeArticle(),
    preferences: createDefaultReaderModePreferences(),
    search: {
      query: '',
      matches: 0,
      activeIndex: -1,
      activeBlockId: '',
      blockMatchCounts: {}
    }
  };
}

export function createDefaultReaderModeOverlayBackState(): ReaderModeOverlayBackState {
  return {
    imagePreviewVisible: false,
    dismissImagePreviewRequestVersion: 0,
    panelVisible: false,
    dismissPanelRequestVersion: 0
  };
}
