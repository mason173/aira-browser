export type BrowserHostedWebNodeDisposeReason =
  'tab_close' |
  'background_preview_release' |
  'manual_home' |
  'recovery_degraded_home' |
  'runtime_cooling_snapshot_release' |
  'page_disappear' |
  'context_switch' |
  'user_agent_changed';

export type BrowserHostedWebNodeDisposeAllReason =
  'page_disappear' |
  'proxy_settings_changed' |
  'adblock_settings_changed';

export type BrowserPageReloadReason =
  'user_manual_reload' |
  'user_agent_changed' |
  'user_agent_application_profile_change' |
  'restore_retry_empty_target' |
  'restore_retry_attach_miss' |
  'site_data_clear_current' |
  'site_data_clear_all' |
  'site_protection_toggle' |
  'site_permission_apply' |
  'site_permission_reset_kind';
