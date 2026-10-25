/**
 * Maps the "实验室" (Laboratory) settings page and its inline panels to localized
 * resources. Applied at the settings presentation boundary so the detail view model
 * can keep producing plain strings.
 */
export function localizeExperimentsSettingsCopy(value: ResourceStr): ResourceStr {
  if (typeof value !== 'string') {
    return value;
  }
  switch (value) {
    case '实验室':
      return $r('app.string.settings_experiments_title');
    case '页面手势':
      return $r('app.string.settings_experiments_page_gestures');
    case '滑动前进后退':
      return $r('app.string.settings_experiments_swipe_navigation');
    case '下拉刷新':
      return $r('app.string.settings_experiments_pull_refresh');
    case '强制允许网页缩放':
      return $r('app.string.settings_experiments_force_web_zoom');
    case '智感握姿':
      return $r('app.string.settings_experiments_smart_grip');
    case '下拉刷新会在普通网页顶部下拉时刷新当前页；强制网页缩放会在系统支持时忽略页面 viewport 里的缩放限制；智感握姿会在系统支持时识别握持手，用于优化单手操作布局。':
      return $r('app.string.settings_experiments_gestures_footer');
    case '视频接管':
      return $r('app.string.settings_experiments_video_section');
    case '网页视频接管':
      return $r('app.string.settings_experiments_web_video_takeover');
    case '开启后，可使用 Aira 播放器控制网页中的真实视频。':
      return $r('app.string.settings_experiments_video_footer');
    case '小说模式':
      return $r('app.string.settings_experiments_novel_mode');
    case '自动进入小说模式':
      return $r('app.string.settings_experiments_novel_auto_takeover');
    case '关闭自动进入后，仍可通过悬浮按钮手动进入；关闭小说模式后，悬浮按钮也会隐藏。':
      return $r('app.string.settings_experiments_novel_footer');
    case '高级网络':
      return $r('app.string.settings_experiments_network_section');
    case '应用内代理':
      return $r('app.string.settings_app_proxy');
    case '开启后，网页会通过你设置的代理访问网络；修改后会自动生效。':
      return $r('app.string.settings_experiments_network_footer');
    case '网页丝滑模式':
      return $r('app.string.settings_experiments_smooth_section');
    case '滚动时暂停网页动画':
      return $r('app.string.settings_experiments_pause_animations');
    case '滚动时临时暂停 CSS 动画和过渡':
      return $r('app.string.settings_experiments_pause_animations_desc');
    case '滚动时降低媒体扰动':
      return $r('app.string.settings_experiments_reduce_media_motion');
    case '滚动时弱化广告 iframe，并暂停离屏视频':
      return $r('app.string.settings_experiments_reduce_media_motion_desc');
    case '加强广告资源拦截':
      return $r('app.string.settings_experiments_strengthen_ad_blocking');
    case '额外拦截常见广告、埋点和重媒体资源':
      return $r('app.string.settings_experiments_strengthen_ad_blocking_desc');
    case '三个实验选项可单独开关；遇到页面表现异常时关闭对应项即可。':
      return $r('app.string.settings_experiments_smooth_footer');
    case '关闭':
      return $r('app.string.settings_experiments_proxy_off');
    case '待配置':
      return $r('app.string.settings_experiments_proxy_pending');
    case '实验室设置更新失败。':
      return $r('app.string.settings_experiments_update_failed');
    default:
      return value;
  }
}

/** Maps the experiment-toggle toast produced by the settings detail view model. */
export function localizeExperimentUpdateToast(value: string): ResourceStr {
  switch (value) {
    case '滚动动画暂停已开启':
      return $r('app.string.settings_experiments_toast_pause_animations_on');
    case '滚动动画暂停已关闭':
      return $r('app.string.settings_experiments_toast_pause_animations_off');
    case '媒体弱化已开启':
      return $r('app.string.settings_experiments_toast_reduce_motion_on');
    case '媒体弱化已关闭':
      return $r('app.string.settings_experiments_toast_reduce_motion_off');
    case '增强拦截已开启':
      return $r('app.string.settings_experiments_toast_strengthen_ads_on');
    case '增强拦截已关闭':
      return $r('app.string.settings_experiments_toast_strengthen_ads_off');
    case '滑动前进后退已开启':
      return $r('app.string.settings_experiments_toast_swipe_navigation_on');
    case '滑动前进后退已关闭':
      return $r('app.string.settings_experiments_toast_swipe_navigation_off');
    case '下拉刷新已开启':
      return $r('app.string.settings_experiments_toast_pull_refresh_on');
    case '下拉刷新已关闭':
      return $r('app.string.settings_experiments_toast_pull_refresh_off');
    case '网页底栏防遮挡已开启':
      return $r('app.string.settings_experiments_toast_bottom_safe_area_on');
    case '网页底栏防遮挡已关闭':
      return $r('app.string.settings_experiments_toast_bottom_safe_area_off');
    case '强制网页缩放已开启':
      return $r('app.string.settings_experiments_toast_force_zoom_on');
    case '强制网页缩放已关闭':
      return $r('app.string.settings_experiments_toast_force_zoom_off');
    case '智感握姿已开启':
      return $r('app.string.settings_experiments_toast_smart_grip_on');
    case '智感握姿已关闭':
      return $r('app.string.settings_experiments_toast_smart_grip_off');
    case '网页视频接管已开启':
      return $r('app.string.settings_experiments_toast_video_takeover_on');
    case '网页视频接管已关闭':
      return $r('app.string.settings_experiments_toast_video_takeover_off');
    case '小说模式已开启':
      return $r('app.string.settings_experiments_toast_novel_mode_on');
    case '小说模式已关闭':
      return $r('app.string.settings_experiments_toast_novel_mode_off');
    case '小说自动接管已开启':
      return $r('app.string.settings_experiments_toast_novel_auto_on');
    case '小说自动接管已关闭':
      return $r('app.string.settings_experiments_toast_novel_auto_off');
    case '应用内代理已开启':
      return $r('app.string.settings_experiments_toast_proxy_on');
    case '应用内代理已关闭':
      return $r('app.string.settings_experiments_toast_proxy_off');
    case '实验室设置已更新':
      return $r('app.string.settings_experiments_toast_updated');
    default:
      return value;
  }
}

/**
 * Maps the settings search-result title for the "实验室" destination tree to
 * localized resources. Called from the search projection boundary.
 */
export function localizeSettingsSearchTargetCopy(value: string): ResourceStr {
  switch (value) {
    case '实验室':
      return $r('app.string.settings_experiments_title');
    case '滑动前进后退':
      return $r('app.string.settings_experiments_swipe_navigation');
    case '下拉刷新':
      return $r('app.string.settings_experiments_pull_refresh');
    case '强制允许网页缩放':
      return $r('app.string.settings_experiments_force_web_zoom');
    case '智感握姿':
      return $r('app.string.settings_experiments_smart_grip');
    case '网页视频接管':
      return $r('app.string.settings_experiments_web_video_takeover');
    case '小说模式':
      return $r('app.string.settings_experiments_novel_mode');
    case '自动进入小说模式':
      return $r('app.string.settings_experiments_novel_auto_takeover');
    case '应用内代理':
      return $r('app.string.settings_app_proxy');
    case '滚动时暂停网页动画':
      return $r('app.string.settings_experiments_pause_animations');
    case '滚动时降低媒体扰动':
      return $r('app.string.settings_experiments_reduce_media_motion');
    case '加强广告资源拦截':
      return $r('app.string.settings_experiments_strengthen_ad_blocking');
    default:
      return value;
  }
}

/** Maps the "实验室" risk-confirmation prompt text to localized resources. */
export function localizeExperimentsRiskPromptCopy(value: ResourceStr): ResourceStr {
  if (typeof value !== 'string') {
    return value;
  }
  switch (value) {
    case '开启媒体扰动抑制？':
      return $r('app.string.settings_experiments_risk_title');
    case '开启后，滚动时会弱化广告 iframe，并暂停离屏视频，可能提升流畅度，但少数网页的视频或广告位表现会变化。':
      return $r('app.string.settings_experiments_risk_message');
    case '开启':
      return $r('app.string.settings_experiments_risk_confirm');
    case '取消':
      return $r('app.string.settings_experiments_risk_cancel');
    default:
      return value;
  }
}
