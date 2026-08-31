import {
  ReaderModeBrightnessMode,
  ReaderModeLineHeight,
  ReaderModePageWidth,
  ReaderModeTheme,
  ReadingPageMode
} from '../../common/models/BrowserModels';
import { ReadingAnchor } from './ReadingDocumentModels';

export type ReadingPresentationMode = ReadingPageMode;

export interface ReadingSurfaceAppearance {
  fontSize: number;
  theme: ReaderModeTheme;
  lineHeight: ReaderModeLineHeight;
  pageWidth: ReaderModePageWidth;
  brightnessMode: ReaderModeBrightnessMode;
  brightnessPercent: number;
}

export interface ReadingSurfaceOptions {
  documentHeaderVisible: boolean;
  pageHeaderVisible: boolean;
  pageNumberVisible: boolean;
  paragraphIndentVisible: boolean;
  continuationAvailable: boolean;
  continuationLabel: string;
  contentTopInset: number;
  contentBottomInset: number;
}

export type ReadingSurfaceCommandType = 'page_previous' | 'page_next' | 'scroll_step';

export interface ReadingSurfaceCommand {
  version: number;
  type: ReadingSurfaceCommandType;
  distance: number;
}

export interface ReadingSurfaceSearchPresentation {
  query: string;
  activeBlockId: string;
  activeMatchIndexInBlock: number;
}

interface ReadingSurfaceAnchorChangeAction {
  type: 'anchor_change';
  anchor: ReadingAnchor;
}

interface ReadingSurfaceOpenLinkAction {
  type: 'open_link';
  blockId: string;
  url: string;
}

interface ReadingSurfacePreviewImageAction {
  type: 'preview_image';
  blockId: string;
  url: string;
  caption: string;
}

interface ReadingSurfaceLayoutFailureAction {
  type: 'layout_failure';
  anchor: ReadingAnchor;
}

interface ReadingSurfaceSimpleAction {
  type: 'toggle_chrome' | 'reach_start' | 'reach_end';
}

export type ReadingSurfaceAction = ReadingSurfaceAnchorChangeAction |
  ReadingSurfaceOpenLinkAction |
  ReadingSurfacePreviewImageAction |
  ReadingSurfaceLayoutFailureAction |
  ReadingSurfaceSimpleAction;

export function createDefaultReadingSurfaceAppearance(): ReadingSurfaceAppearance {
  return {
    fontSize: 19,
    theme: 'system',
    lineHeight: 'comfortable',
    pageWidth: 'standard',
    brightnessMode: 'system',
    brightnessPercent: 60
  };
}

export function createDefaultReadingSurfaceOptions(): ReadingSurfaceOptions {
  return {
    documentHeaderVisible: false,
    pageHeaderVisible: true,
    pageNumberVisible: true,
    paragraphIndentVisible: false,
    continuationAvailable: false,
    continuationLabel: '继续阅读',
    contentTopInset: 0,
    contentBottomInset: 0
  };
}

export function createDefaultReadingSurfaceCommand(): ReadingSurfaceCommand {
  return {
    version: 0,
    type: 'page_next',
    distance: 0
  };
}

export function createDefaultReadingSurfaceSearchPresentation(): ReadingSurfaceSearchPresentation {
  return {
    query: '',
    activeBlockId: '',
    activeMatchIndexInBlock: -1
  };
}
