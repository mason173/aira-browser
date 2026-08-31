export type VideoAssistantPlaybackStatus =
  | 'idle'
  | 'loading'
  | 'ready'
  | 'playing'
  | 'paused'
  | 'ended'
  | 'error';

export type VideoAssistantLoadingReason = '' | 'preparing' | 'seeking' | 'buffering';

export type VideoAssistantScaleMode = 'contain' | 'crop' | 'stretch';

export interface VideoAssistantItem {
  id: string;
  tabId: string;
  title: string;
  pageUrl: string;
  url: string;
  posterUrl?: string;
  width: number;
  height: number;
}

export interface VideoAssistantState {
  active: boolean;
  item: VideoAssistantItem;
  playbackStatus: VideoAssistantPlaybackStatus;
  loadingReason: VideoAssistantLoadingReason;
  positionSeconds: number;
  durationSeconds: number;
  errorMessage: string;
  fullscreen: boolean;
  startedAtMs: number;
}

export function createEmptyVideoAssistantItem(): VideoAssistantItem {
  return {
    id: '',
    tabId: '',
    title: '网页视频',
    pageUrl: '',
    url: '',
    width: 0,
    height: 0
  };
}

export function createInactiveVideoAssistantState(): VideoAssistantState {
  return {
    active: false,
    item: createEmptyVideoAssistantItem(),
    playbackStatus: 'idle',
    loadingReason: '',
    positionSeconds: 0,
    durationSeconds: 0,
    errorMessage: '',
    fullscreen: false,
    startedAtMs: 0
  };
}
