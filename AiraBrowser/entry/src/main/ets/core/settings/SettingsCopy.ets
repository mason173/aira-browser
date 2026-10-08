/**
 * Settings copy that still travels as a plain string, mapped to its  resource.
 *
 * Several settings owners build their state as plain strings because the value is compared,
 * stored, or formatted before it is rendered — a language label, a day count, a status line.
 * That is the one place a literal is the right shape, and this is where it becomes localized.
 *
 * The Chinese value stays the identity the owner already produces; every render sink asks for
 * the resource instead. An unmapped value returns unchanged, so a missing translation degrades
 * to the existing literal rather than an empty label.
 */
export function localizeSettingsCopy(value: ResourceStr): ResourceStr {
  if (typeof value !== 'string') {
    return value;
  }
  switch (value) {
    case '关闭设置':
      return $r('app.string.settings_close');
    case '图标管理服务暂不可用。':
      return $r('app.string.settings_app_icon_01');
    case '应用图标更新失败。':
      return $r('app.string.settings_app_icon_02');
    case '继续切换':
      return $r('app.string.settings_desktop_interface_01');
    case '正在确认登录':
      return $r('app.string.settings_desktop_login_01');
    case '确认登录':
      return $r('app.string.settings_desktop_login_02');
    case 'Aira 账号':
      return $r('app.string.settings_desktop_login_03');
    case '当前华为账号':
      return $r('app.string.settings_desktop_login_04');
    case '跟随主题色':
      return $r('app.string.settings_home_01');
    case '查看更多':
      return $r('app.string.settings_about_01');
    case '账号与会员需切换到全量模式后使用。':
      return $r('app.string.settings_center_01');
    case '代理设置暂时无法打开，请稍后重试。':
      return $r('app.string.settings_center_02');
    case '自定义 DNS 编辑页暂时无法打开，请稍后重试。':
      return $r('app.string.settings_center_03');
    case '设置页面':
      return $r('app.string.settings_center_04');
    case '设置页面导航失败，请重试':
      return $r('app.string.settings_center_05');
    case '返回设置':
      return $r('app.string.settings_scaffold_01');
    case '搜索引擎已更新。':
      return $r('app.string.settings_detail_01');
    case '搜索引擎更新失败。':
      return $r('app.string.settings_detail_02');
    case '站点默认权限更新失败。':
      return $r('app.string.settings_detail_03');
    case '主题色更新失败。':
      return $r('app.string.settings_theme_palette_01');
    case '覆盖书签':
      return $r('app.string.settings_sync_01');
    case '启用 WebDAV 同步':
      return $r('app.string.settings_sync_webdav_01');
    case 'WebDAV 服务商':
      return $r('app.string.settings_sync_webdav_02');
    case 'WebDAV 用户名':
      return $r('app.string.settings_sync_webdav_03');
    case 'WebDAV 密码':
      return $r('app.string.settings_sync_webdav_04');
    case '关闭 WebDAV 额外备份':
      return $r('app.string.settings_sync_webdav_05');
    case '关闭 WebDAV 同步':
      return $r('app.string.settings_sync_webdav_06');
    case 'WebDAV 地址':
      return $r('app.string.settings_sync_webdav_07');
    case '正在更新 WebDAV 备份':
      return $r('app.string.settings_sync_webdav_08');
    case '正在开启 WebDAV 额外备份':
      return $r('app.string.settings_sync_webdav_09');
    case '正在同步 WebDAV':
      return $r('app.string.settings_sync_webdav_10');
    case '正在启用 WebDAV 同步':
      return $r('app.string.settings_sync_webdav_11');
    case '正在保存配置，并用本机内容覆盖 WebDAV':
      return $r('app.string.settings_sync_webdav_12');
    case '正在保存配置并检查连接':
      return $r('app.string.settings_sync_webdav_13');
    case '正在保存配置并开启书签和全部常用设置':
      return $r('app.string.settings_sync_webdav_14');
    case '开启同步':
      return $r('app.string.settings_sync_webdav_15');
    case '正在覆盖写入 WebDAV 额外备份':
      return $r('app.string.settings_sync_webdav_16');
    case '正在处理 WebDAV 同步状态':
      return $r('app.string.settings_sync_webdav_17');
    case 'WebDAV 额外备份':
      return $r('app.string.settings_sync_webdav_18');
    case '开启 WebDAV 额外备份':
      return $r('app.string.settings_sync_webdav_19');
    case '关闭 WebDAV 额外备份吗':
      return $r('app.string.settings_sync_webdav_20');
    case '关闭 WebDAV 同步吗':
      return $r('app.string.settings_sync_webdav_21');
    case '关闭后会停止向 WebDAV 覆盖写入额外副本，当前同步方式和已填写的 WebDAV 配置都不会删除。':
      return $r('app.string.settings_sync_webdav_22');
    case '关闭后会停止通过 WebDAV 同步书签，本机书签和已填写的 WebDAV 配置不会删除。':
      return $r('app.string.settings_sync_webdav_23');
    case '关闭失败':
      return $r('app.string.settings_sync_webdav_24');
    case '暂时没能关闭 WebDAV 额外备份，请稍后再试。':
      return $r('app.string.settings_sync_webdav_25');
    case '暂时没能关闭 WebDAV 同步，请检查网络后再试。':
      return $r('app.string.settings_sync_webdav_26');
    case '同步':
      return $r('app.string.settings_sync_webdav_27');
    case 'Aira 活跃':
      return $r('app.string.settings_activity_01');
    case '开始使用 Aira 后，这里会点亮你的活跃日历':
      return $r('app.string.settings_activity_02');
    case '夜色':
      return $r('app.string.settings_app_icon_05');
    case '海蓝':
      return $r('app.string.settings_app_icon_06');
    case '缤纷':
      return $r('app.string.settings_app_icon_07');
    case '磨砂':
      return $r('app.string.settings_app_icon_08');
    case '正在读取应用图标...':
      return $r('app.string.settings_app_icon_09');
    case '应用图标由华为应用市场图标管理服务提供，审核通过后会在这里显示。':
      return $r('app.string.settings_app_icon_10');
    case '经典':
      return $r('app.string.settings_app_icon_11');
    case '暂无可用的应用图标。':
      return $r('app.string.settings_app_icon_12');
    case '切换后桌面图标会由系统更新；如果系统正在使用自定义主题图标，切换可能会失败。':
      return $r('app.string.settings_app_icon_13');
    case '需要先在 AppGallery Connect 图标管理中创建图标并通过审核，审核通过后会自动出现在这里。':
      return $r('app.string.settings_app_icon_14');
    case '切换到基本模式？':
      return $r('app.string.settings_app_service_mode_01');
    case '基本模式会关闭账号登录、同步、会员、翻译、脚本、网页内容过滤、壁纸、远程建议和实验功能。大部分增强能力将不可用，App 会重启以应用更改；已保存的数据不会删除。':
      return $r('app.string.settings_app_service_mode_02');
    case '切换到基本模式':
      return $r('app.string.settings_app_service_mode_03');
    case '手机使用桌面界面可能出现内容过密、按钮过小或部分布局不适配。切换到桌面界面前需要再次确认。':
      return $r('app.string.settings_desktop_interface_02');
    case '小折叠屏展开后仍使用触屏界面，因为展开后的屏幕较窄；手动选择桌面界面时除外。':
      return $r('app.string.settings_desktop_interface_03');
    case '自动模式会在设备展开时使用桌面界面，收起时恢复触屏界面；半折叠或状态未知时保持当前界面。':
      return $r('app.string.settings_desktop_interface_04');
    case '自动模式会在连接鼠标或触控板时使用桌面界面，断开后恢复触屏界面。物理键盘仍可在触屏界面中使用快捷键。':
      return $r('app.string.settings_desktop_interface_05');
    case '站点网页标识引用回退失败。':
      return $r('app.string.settings_user_agent_01');
    case '15 天':
      return $r('app.string.settings_general_01');
    case '7 天':
      return $r('app.string.settings_general_02');
    case '3 天':
      return $r('app.string.settings_general_03');
    case '1 天':
      return $r('app.string.settings_general_04');
    case '支持 PNG、JPG、GIF、WebP、BMP、SVG、HEIC、AVIF 等格式':
      return $r('app.string.settings_home_logo_01');
    case '这个 Logo 不可用。':
      return $r('app.string.settings_home_logo_02');
    case '不显示':
      return $r('app.string.settings_home_02');
    case '本地浏览功能已全部开启':
      return $r('app.string.settings_account_card_01');
    case '华为账号已登录，当前使用华为云空间同步':
      return $r('app.string.settings_account_card_02');
    case '华为账号已登录，当前使用 Aira 云同步':
      return $r('app.string.settings_account_card_03');
    case '华为账号已登录，当前使用 WebDAV 同步':
      return $r('app.string.settings_account_card_04');
    case '华为账号已登录，当前为 Aira Club':
      return $r('app.string.settings_account_card_05');
    case '搜索和书签':
      return $r('app.string.settings_detail_07');
    case '10000 条':
      return $r('app.string.settings_detail_08');
    case '尚无已保存站点权限':
      return $r('app.string.settings_detail_09');
    case '当前私密会话':
      return $r('app.string.settings_detail_10');
    case '私密入口':
      return $r('app.string.settings_detail_11');
    case '仅限本次会话':
      return $r('app.string.settings_detail_12');
    case '不改常规浏览资料':
      return $r('app.string.settings_detail_13');
    case '地址栏显示本地建议':
      return $r('app.string.settings_detail_14');
    case '即将推出':
      return $r('app.string.settings_detail_15');
    case '后续补充':
      return $r('app.string.settings_detail_16');
    case '暂未开放设置项':
      return $r('app.string.settings_detail_17');
    case '适合中文内容搜索':
      return $r('app.string.settings_detail_18');
    case '更注重隐私':
      return $r('app.string.settings_detail_19');
    case '国际搜索补充':
      return $r('app.string.settings_detail_20');
    case '使用 Google 搜索':
      return $r('app.string.settings_detail_21');
    case '使用 Bing 搜索':
      return $r('app.string.settings_detail_22');
    case '15 天未使用':
      return $r('app.string.settings_detail_23');
    case '7 天未使用':
      return $r('app.string.settings_detail_24');
    case '3 天未使用':
      return $r('app.string.settings_detail_25');
    case '1 天未使用':
      return $r('app.string.settings_detail_26');
    case '3000 条':
      return $r('app.string.settings_detail_27');
    case '关闭后不进入下次启动恢复':
      return $r('app.string.settings_detail_28');
    case '会降低隐私边界，请谨慎开启':
      return $r('app.string.settings_detail_29');
    case '当前会话不可更改全局外部应用策略。':
      return $r('app.string.settings_external_navigation_01');
    case '已阻止网站打开外部应用。':
      return $r('app.string.settings_external_navigation_02');
    case '已允许网站直接打开外部应用。':
      return $r('app.string.settings_external_navigation_03');
    case '打开外部应用前会先询问。':
      return $r('app.string.settings_external_navigation_04');
    case '快捷方式':
      return $r('app.string.settings_general_05');
    case '仅搜索':
      return $r('app.string.settings_general_06');
    case '自动续费说明':
      return $r('app.string.settings_legal_01');
    case '更新日期：2026-05-20':
      return $r('app.string.settings_legal_02');
    case '本说明用于帮助你理解 Aira Pro 订阅的续费、扣款、取消和权益变化规则。实际价格、周期、优惠和支付结果以华为支付或订阅管理页面展示为准。':
      return $r('app.string.settings_legal_03');
    case '订阅与续费':
      return $r('app.string.settings_legal_04');
    case 'Aira Pro 可能提供月度、季度、年度等订阅周期。你选择并确认支付后，对应 Pro 权益会在订阅有效期内生效。':
      return $r('app.string.settings_legal_05');
    case '如果你在支付页面开通连续订阅，系统会在每个订阅周期到期前按照平台规则自动续费。':
      return $r('app.string.settings_legal_06');
    case '扣款与价格':
      return $r('app.string.settings_legal_07');
    case '订阅价格、优惠、试用、税费、扣款时间和扣款方式以华为支付页面或订阅管理页面展示的信息为准。':
      return $r('app.string.settings_legal_08');
    case '如果支付失败、账号状态异常或平台未能确认订阅状态，Pro 权益可能无法立即生效。你可以稍后返回会员页恢复购买。':
      return $r('app.string.settings_legal_09');
    case '取消续费':
      return $r('app.string.settings_legal_10');
    case '你可以通过华为官方订阅管理页面取消自动续费。取消后，已购买周期内的 Pro 权益通常会保留到当前周期结束。':
      return $r('app.string.settings_legal_11');
    case '为避免下个周期继续扣款，请在平台要求的时间前完成取消操作。具体取消路径、截止时间和生效规则以华为订阅管理页面为准。':
      return $r('app.string.settings_legal_12');
    case '权益变化':
      return $r('app.string.settings_legal_13');
    case '如果订阅到期、取消、退款或支付状态异常，Aira Pro 权益可能会停止或回到当前账号可用的基础权益。':
      return $r('app.string.settings_legal_14');
    case '会员权益、订阅周期和价格如有调整，我们会在应用内或支付页面以适当方式提示。':
      return $r('app.string.settings_legal_15');
    case '没有需要刷新的网站图标。':
      return $r('app.string.settings_site_icon_01');
    case '网站图标暂时无法刷新，请稍后再试。':
      return $r('app.string.settings_site_icon_02');
    case 'WebDAV 同步':
      return $r('app.string.settings_sync_goal_webdav');
    case '书签冲突处理失败':
      return $r('app.string.settings_sync_conflicts_failed');
    case '以云端为准':
      return $r('app.string.settings_sync_prefer_cloud');
    case '以本机为准':
      return $r('app.string.settings_sync_prefer_local');
    case '关闭':
      return $r('app.string.settings_sync_close');
    case '华为账号登录失败':
      return $r('app.string.settings_pro_sign_in_failed');
    case '取消':
      return $r('app.string.settings_sync_self_host_cancel');
    case '密码':
      return $r('app.string.settings_app_proxy_field_password');
    case '未配置':
      return $r('app.string.settings_web_translation_status_unconfigured');
    case '查看 Aira Pro':
      return $r('app.string.settings_sync_view_pro');
    case '查看权益':
      return $r('app.string.settings_sync_view_benefits');
    case '正在准备本机和云端数据':
      return $r('app.string.settings_sync_advanced_preparing_both');
    case '正在处理书签冲突':
      return $r('app.string.settings_sync_resolving_conflicts');
    case '正在完成处理':
      return $r('app.string.settings_sync_advanced_finishing');
    case '正在开启同步':
      return $r('app.string.settings_sync_advanced_turning_on');
    case '正在按你的选择合并并保存书签':
      return $r('app.string.settings_sync_resolving_conflicts_detail');
    case '用户名':
      return $r('app.string.settings_app_proxy_field_username');
    case '稍后':
      return $r('app.string.settings_sync_later');
    case '复制失败，请稍后重试。':
      return $r('app.string.ui_copy_failed');
    case '操作超时':
      return $r('app.string.settings_sync_advanced_timeout');
    case '当前没有可复制的错误详情。':
      return $r('app.string.settings_sync_advanced_copy_empty');
    case '错误详情已复制。':
      return $r('app.string.settings_sync_advanced_copied');
    case '选择 Logo 失败，请稍后重试。':
      return $r('app.string.settings_home_04');
    case '已启用':
      return $r('app.string.user_script_detail_enabled');
    case '搜索':
      return $r('app.string.settings_search_engine_page_title');
    case '系统主页':
      return $r('app.string.settings_custom_home_system');
    case '询问':
      return $r('app.string.settings_site_capability_rule_ask');
    case '保存并开启为额外备份':
      return $r('app.string.settings_sync_webdav_29');
    case '保存并更新额外备份':
      return $r('app.string.settings_sync_webdav_30');
    case '启用 WebDAV 书签同步':
      return $r('app.string.settings_sync_webdav_31');
    case '正在关闭 WebDAV 同步':
      return $r('app.string.settings_sync_webdav_32');
    case '正在关闭 WebDAV 额外备份':
      return $r('app.string.settings_sync_webdav_33');
    case '设为当前同步方式并开启':
      return $r('app.string.settings_sync_webdav_34');
    case '已保存，未开启':
      return $r('app.string.settings_sync_webdav_35');
    case '当前为额外备份位置':
      return $r('app.string.settings_sync_webdav_36');
    case '当前同步方式，书签同步未开启':
      return $r('app.string.settings_sync_webdav_37');
    case '正在关闭':
      return $r('app.string.settings_sync_webdav_38');
    case '正在开启':
      return $r('app.string.settings_sync_webdav_39');
    case '立即同步':
      return $r('app.string.settings_sync_now');
    case '书签同步已开启':
      return $r('app.string.settings_sync_bookmarks_on');
    case '额外备份已开启':
      return $r('app.string.settings_sync_backup_enabled');
    case '正在同步':
      return $r('app.string.settings_sync_syncing');
    case '正在保存 WebDAV 额外备份':
      return $r('app.string.settings_sync_webdav_40');
    case '添加自定义 Logo':
      return $r('app.string.settings_home_logo_add');
    case '当前版本':
      return $r('app.string.settings_about_version_title');
    case '未登录':
      return $r('app.string.settings_account_signed_out');
    case '本地浏览功能已全部开启，登录后可使用账号与云服务':
      return $r('app.string.settings_account_signed_out_note');
    case '华为账号登录未完成':
      return $r('app.string.settings_pro_sign_in_incomplete');
    case '请回到普通会话后登录华为账号。':
      return $r('app.string.settings_pro_sign_in_private');
    case '删除':
      return $r('app.string.settings_delete');
    case '删除用户脚本':
      return $r('app.string.user_script_delete_dialog_title');
    case '导出脚本失败，请稍后重试。':
      return $r('app.string.user_script_export_failed');
    case '已选择该文件夹。若下载时无法写入，将回退到系统下载目录。':
      return $r('app.string.settings_web_download_folder_selected_fallback');
    case '已选择该文件夹。重启应用后需要重新授权。':
      return $r('app.string.settings_web_download_folder_selected_reauth');
    case '当前设备不支持选择文件夹。':
      return $r('app.string.settings_web_download_folder_unsupported');
    case '这个文件夹不可用，请换一个再试。':
      return $r('app.string.settings_web_download_folder_unavailable');
    case '选择下载位置失败':
      return $r('app.string.settings_web_download_folder_failed');
    case '更多操作':
      return $r('app.string.settings_more_actions');
    case '私密模式':
      return $r('app.string.settings_private_mode');
    case '同步服务':
      return $r('app.string.settings_sync_advanced_service');
    case '更改同步方式':
      return $r('app.string.settings_sync_advanced_change_method');
    case '未知错误':
      return $r('app.string.settings_sync_advanced_unknown_error');
    case '检查远端数据':
      return $r('app.string.settings_sync_advanced_check_remote');
    case '立即合并同步':
      return $r('app.string.settings_sync_advanced_merge');
    case '未知':
      return $r('app.string.user_script_unknown');
    case '华为账号':
      return $r('app.string.settings_account_huawei');
    case '允许':
      return $r('app.string.settings_site_capability_rule_allow');
    case '简体中文':
      return $r('app.string.settings_general_language_chinese');
    case '默认跟随系统语言':
      return $r('app.string.settings_general_language_detail');
    case '网址主页':
      return $r('app.string.settings_custom_home_type_url');
    case '自定义主页':
      return $r('app.string.settings_custom_home_fallback_title');
    default:
      return value;
  }
}
