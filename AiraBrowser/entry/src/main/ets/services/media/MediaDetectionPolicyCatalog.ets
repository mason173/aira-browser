export type MediaDeepProbeStrategyId =
  'inline_scripts' |
  'location' |
  'metadata' |
  'performance_entries' |
  'player_adapters' |
  'player_configs' |
  'vendor_adapters';

export interface MediaDetectionPolicy {
  deepProbeDelaysMs: number[];
  deepProbeStrategyIds: MediaDeepProbeStrategyId[];
  globalConfigNames: string[];
  maxDeepProbeRunsPerNavigation: number;
  maxInFlightDeepProbes: number;
  mediaFieldNames: string[];
  mediaQueryParameterNames: string[];
  playerMethodNames: string[];
  spaRouteReprobeEnabled: boolean;
}

export const DEFAULT_MEDIA_DETECTION_POLICY: MediaDetectionPolicy = {
  deepProbeDelaysMs: [0, 1800, 5000],
  deepProbeStrategyIds: [
    'player_adapters',
    'metadata',
    'player_configs',
    'vendor_adapters',
    'performance_entries',
    'inline_scripts',
    'location'
  ],
  globalConfigNames: [
    '__INITIAL_STATE__', '__INITIAL_DATA__', '__NEXT_DATA__', '__NUXT__', '__playinfo__',
    'playerConfig', 'videoConfig', 'playConfig', 'playurl', 'playUrlInfo', 'videoData',
    'playerData', 'videoInfo', 'mediaInfo', 'streamInfo', 'playInfo', 'jwplayerConfig',
    'dplayerOptions', 'videoSources', 'mediaSources'
  ],
  maxDeepProbeRunsPerNavigation: 3,
  maxInFlightDeepProbes: 1,
  mediaFieldNames: [
    'url3', 'url_next', 'url', 'src', 'file', 'fileUrl', 'file_url', 'source', 'sources',
    'sourceUrl', 'source_url', 'video', 'video_url', 'videoUrl', 'play_url', 'playUrl',
    'playback_url', 'playbackUrl', 'stream', 'stream_url', 'streamUrl', 'media_url', 'mediaUrl',
    'contentUrl', 'content_url', 'downloadUrl', 'download_url', 'baseUrl', 'base_url',
    'backupUrl', 'backup_url', 'm3u8', 'm3u8_2', 'm3u8Url', 'hls', 'hlsUrl', 'hls_url',
    'mpd', 'mpdUrl', 'dash', 'dashUrl', 'dash_url', 'currentSrc', 'href'
  ],
  mediaQueryParameterNames: [
    'file', 'source', 'src', 'video_url', 'video', 'url', 'hls', 'm3u8', 'mpd', 'dash'
  ],
  playerMethodNames: ['loadSource', 'attachSource', 'setSrc', 'load', 'src', 'initialize', 'setup'],
  spaRouteReprobeEnabled: true
};

/** Package-owned bounds for generic media discovery. */
export class MediaDetectionPolicyCatalog {
  currentPolicy(): MediaDetectionPolicy {
    return {
      deepProbeDelaysMs: DEFAULT_MEDIA_DETECTION_POLICY.deepProbeDelaysMs.slice(),
      deepProbeStrategyIds: DEFAULT_MEDIA_DETECTION_POLICY.deepProbeStrategyIds.slice(),
      globalConfigNames: DEFAULT_MEDIA_DETECTION_POLICY.globalConfigNames.slice(),
      maxDeepProbeRunsPerNavigation: DEFAULT_MEDIA_DETECTION_POLICY.maxDeepProbeRunsPerNavigation,
      maxInFlightDeepProbes: DEFAULT_MEDIA_DETECTION_POLICY.maxInFlightDeepProbes,
      mediaFieldNames: DEFAULT_MEDIA_DETECTION_POLICY.mediaFieldNames.slice(),
      mediaQueryParameterNames: DEFAULT_MEDIA_DETECTION_POLICY.mediaQueryParameterNames.slice(),
      playerMethodNames: DEFAULT_MEDIA_DETECTION_POLICY.playerMethodNames.slice(),
      spaRouteReprobeEnabled: DEFAULT_MEDIA_DETECTION_POLICY.spaRouteReprobeEnabled
    };
  }
}

export const sharedMediaDetectionPolicyCatalog: MediaDetectionPolicyCatalog =
  new MediaDetectionPolicyCatalog();
