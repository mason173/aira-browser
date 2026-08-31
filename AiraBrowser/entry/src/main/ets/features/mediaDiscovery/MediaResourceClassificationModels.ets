export type MediaResourceFrameType =
  | 'main_frame'
  | 'sub_frame'
  | 'dom_frame'
  | 'dom_document'
  | 'unknown';

export type MediaResourceDomSignal =
  | 'video_element'
  | 'audio_element'
  | 'image_element'
  | 'css_background'
  | 'image_performance'
  | 'embedded_attribute'
  | 'performance_entry'
  | 'anchor'
  | 'location'
  | 'script_text'
  | 'text_match';

export type MediaResourceEvidence =
  | 'mime'
  | 'explicit_extension'
  | 'media_element'
  | 'image_element'
  | 'streaming_url_hint'
  | 'generic_url_hint'
  | 'weak_text_match'
  | 'negative';
