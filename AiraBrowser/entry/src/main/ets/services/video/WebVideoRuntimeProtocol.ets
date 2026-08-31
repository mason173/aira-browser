export const WEB_VIDEO_RUNTIME_ID_PROPERTY: string = '__airaPageBehaviorVideoRuntimeId';
export const WEB_VIDEO_ORIGINAL_OBJECT_FIT_PROPERTY: string = '__airaVideoAssistantOriginalObjectFit';
export const WEB_VIDEO_ORIGINAL_OBJECT_FIT_PRIORITY_PROPERTY: string =
  '__airaVideoAssistantOriginalObjectFitPriority';
export const WEB_VIDEO_ORIGINAL_CONTROLS_PROPERTY: string = '__airaVideoAssistantOriginalControls';
export const WEB_VIDEO_CONTROLS_OBSERVER_PROPERTY: string = '__airaVideoAssistantControlsObserver';
export const WEB_VIDEO_CONTROLS_HIDDEN_MARKER_ATTRIBUTE: string =
  'data-aira-video-assistant-controls-hidden';
export const WEB_VIDEO_ORIGINAL_CONTROLS_HIDDEN_MARKER_PROPERTY: string =
  '__airaVideoAssistantOriginalControlsHiddenMarker';
export const WEB_VIDEO_CONTROLS_STYLE_ELEMENT_ID: string = 'aira-video-assistant-controls-hidden-style';
export const WEB_VIDEO_FULLSCREEN_REQUEST_RESULT_EVENT: string = '__airaVideoAssistantFullscreenRequestResult';
export const WEB_VIDEO_LIVE_PRESENTATION_PROPERTY: string = '__airaVideoAssistantLivePresentation';
export const WEB_VIDEO_ACTION_TOOLBAR_PROTOCOL: string = 'aira_video_action_toolbar_v1';

export type WebVideoFullscreenCapability = 'none' | 'standard' | 'webkit';

export function normalizeWebVideoFullscreenCapability(
  value: string | undefined
): WebVideoFullscreenCapability {
  const normalized = value?.trim().toLowerCase() ?? '';
  if (normalized === 'standard') {
    return 'standard';
  }
  if (normalized === 'webkit') {
    return 'webkit';
  }
  return 'none';
}
