export function localizePrivacyModeSettingsCopy(value: ResourceStr): ResourceStr {
  if (typeof value !== 'string') {
    return value;
  }
  switch (value) {
    case '进入隐私模式时验证身份':
      return $r('app.string.settings_privacy_authenticate');
    case '始终保持隐私模式':
      return $r('app.string.settings_always_private_title');
    case '自动静音':
      return $r('app.string.settings_privacy_auto_mute');
    case '开启后，在隐私模式下打开的网页默认静音；按音量键可恢复当前网页声音。':
      return $r('app.string.settings_privacy_auto_mute_note');
    case '隐私模式保留 Cookie':
      return $r('app.string.settings_privacy_keep_cookies');
    case '模糊私密标签页预览':
      return $r('app.string.settings_privacy_blur_previews');
    case '普通与私密数据':
      return $r('app.string.settings_privacy_data_scope');
    case '分开保存':
      return $r('app.string.settings_privacy_stored_separately');
    case '允许在隐私模式运行用户脚本':
      return $r('app.string.settings_privacy_allow_scripts');
    case '私密标签页恢复':
      return $r('app.string.settings_privacy_restore_tabs');
    case '关闭后不恢复':
      return $r('app.string.settings_privacy_never_restore');
    case '允许恢复':
      return $r('app.string.settings_privacy_allow_restore');
    case '控制如何进入隐私模式，不改变普通模式的防跟踪设置。':
      return $r('app.string.settings_privacy_entry_footer');
    case '关闭全部隐私标签页时按这里的规则处理数据；私密数据不会混入普通浏览资料。':
      return $r('app.string.settings_privacy_data_footer');
    case '当前私密会话不能修改设备级隐私设置。':
      return $r('app.string.settings_privacy_session_locked');
    case '关闭后私密会话不会注入已安装的用户脚本，效果与之前一致。':
      return $r('app.string.settings_privacy_scripts_footer');
    case '设置关闭隐私标签页后是否参与下次启动恢复。':
      return $r('app.string.settings_privacy_restore_footer');
    default:
      return value;
  }
}
