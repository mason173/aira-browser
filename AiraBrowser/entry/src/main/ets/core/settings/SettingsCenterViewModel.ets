import { BrowserAppServiceMode } from '../../common/models/BrowserModels';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import { resolveAppResourceText } from '../resources/AppResourceText';
import { localizeSettingsCatalogCopy } from './SettingsCatalogCopy';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export type SettingsCenterDestination =
  'app_service_mode' |
  'advanced_settings' |
  'aira_pro' |
  'general' |
  'custom_homepage' |
  'toolbar_customization' |
  'search' |
  'privacy_security' |
  'private_mode' |
  'site_settings' |
  'ad_blocker' |
  'web_features' |
  'user_scripts' |
  'webpage_translation' |
  'web_apps' |
  'passwords' |
  'downloads' |
  'user_agent' |
  'appearance_toolbar' |
  'experiments' |
  'sync' |
  'cross_device_link' |
  'app_recommendation' |
  'about';

export interface SettingsCenterRowState {
  id: SettingsCenterDestination;
  title: ResourceStr;
  value: ResourceStr;
  isEnabled: boolean;
  icon?: Resource;
  imageIcon?: Resource;
  airaIconId?: AiraRenderableIconId;
}

export interface SettingsCenterGroupState {
  id: string;
  title: ResourceStr;
  rows: SettingsCenterRowState[];
}

export interface SettingsCenterState {
  groups: SettingsCenterGroupState[];
  appProxyNotice: SettingsCenterAppProxyNoticeState;
  showAccountCard: boolean;
  showScanLoginAction: boolean;
}

export interface SettingsCenterAppProxyNoticeState {
  shouldShow: boolean;
  message: ResourceStr;
}

export class SettingsCenterViewModel {
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  buildState(
    dataScope: string = '',
    privacyMode: string = '',
    appServiceMode: BrowserAppServiceMode = 'full',
    appProxyEnabled: boolean = false
  ): SettingsCenterState {
    const isFullServiceMode = appServiceMode !== 'basic';
    const canReadDevicePreferences = this.isDevicePreferenceEffectAllowed(
      'settings_device_preference_read',
      dataScope,
      privacyMode
    );
    const accountRows: SettingsCenterRowState[] = [];
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
      accountRows.push(this.buildRow('aira_pro', '捐赠Pro'));
    }
    accountRows.push(this.buildRow(
      'sync',
      '数据同步',
      this.getFullModeRequiredValue(isFullServiceMode),
      isFullServiceMode
    ));
    accountRows.push(this.buildRow(
      'cross_device_link',
      '与电脑互联',
      '',
      canReadDevicePreferences && isFullServiceMode
    ));
    return {
      appProxyNotice: this.buildAppProxyNotice(appProxyEnabled),
      showAccountCard: AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial(),
      showScanLoginAction: AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial(),
      groups: [
        {
          id: 'account',
          title: localizeSettingsCatalogCopy(
            AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity() ? '同步与备份' : '账号与同步'
          ),
          rows: accountRows
        },
        {
          id: 'basic',
          title: localizeSettingsCatalogCopy('通用'),
          rows: [
            this.buildRow('general', '通用'),
            this.buildRow('search', '搜索设置', '', canReadDevicePreferences),
            this.buildRow(
              'appearance_toolbar',
              '外观设置',
              '',
              canReadDevicePreferences
            ),
            this.buildRow('custom_homepage', '主页设置'),
            this.buildRow('toolbar_customization', '工具栏设置', '', canReadDevicePreferences)
          ]
        },
        {
          id: 'privacy',
          title: localizeSettingsCatalogCopy('隐私与安全'),
          rows: [
            this.buildRow('privacy_security', '隐私防护'),
            this.buildRow('private_mode', '隐私模式')
          ]
        },
        {
          id: 'experience',
          title: localizeSettingsCatalogCopy('网页功能'),
          rows: [
            this.buildRow('web_features', '网页功能'),
            this.buildRow(
              'user_scripts',
              '用户脚本',
              this.getFullModeRequiredValue(isFullServiceMode),
              isFullServiceMode
            ),
            this.buildRow('web_apps', '网页应用')
          ]
        },
        {
          id: 'advanced',
          title: localizeSettingsCatalogCopy('高级'),
          rows: [
            this.buildRow('user_agent', '网页标识'),
            this.buildRow(
              'experiments',
              '实验室',
              isFullServiceMode ? '' : this.getFullModeRequiredValue(isFullServiceMode),
              canReadDevicePreferences && isFullServiceMode
            ),
            this.buildRow('advanced_settings', '高级设置'),
            this.buildRow('app_recommendation', '应用推荐'),
            this.buildRow('about', '关于Aira')
          ]
        }
      ]
    };
  }

  private buildAppProxyNotice(appProxyEnabled: boolean): SettingsCenterAppProxyNoticeState {
    return {
      shouldShow: appProxyEnabled,
      message: $r('app.string.settings_experiments_toast_proxy_on')
    };
  }

  private buildRow(
    id: SettingsCenterDestination,
    title: ResourceStr,
    value: ResourceStr = '',
    isEnabled: boolean = true
  ): SettingsCenterRowState {
    return {
      id: id,
      title: title,
      value: value,
      isEnabled: isEnabled,
      icon: this.resolveIcon(id),
      imageIcon: undefined,
      airaIconId: this.resolveAiraIconId(id)
    };
  }

  private resolveIcon(id: SettingsCenterDestination): Resource | undefined {
    switch (id) {
      case 'advanced_settings':
        return $r('sys.symbol.line_3_horizontal');
      case 'app_service_mode':
        return $r('sys.symbol.checkmark_shield_fill');
      case 'aira_pro':
        return $r('sys.symbol.person_fill');
      case 'general':
        return $r('sys.symbol.gearshape_fill');
      case 'custom_homepage':
        return $r('sys.symbol.house_fill');
      case 'toolbar_customization':
        return undefined;
      case 'search':
        return $r('sys.symbol.doc_text_magnifyingglass_fill');
      case 'privacy_security':
        return $r('sys.symbol.person_shield_fill');
      case 'private_mode':
        return undefined;
      case 'passwords':
        return $r('sys.symbol.lock_fill');
      case 'web_features':
        return $r('sys.symbol.compass_circle_fill');
      case 'webpage_translation':
        return $r('sys.symbol.translate_square_fill');
      case 'web_apps':
        return $r('sys.symbol.rectangle_on_rectangle_fill');
      case 'user_scripts':
        return $r('sys.symbol.doc_text_fill');
      case 'downloads':
        return $r('sys.symbol.download_fill');
      case 'user_agent':
        return $r('sys.symbol.phone_fill');
      case 'appearance_toolbar':
        return undefined;
      case 'experiments':
        return $r('sys.symbol.wand_and_stars_fill');
      case 'sync':
        return $r('sys.symbol.icloud_fill');
      case 'cross_device_link':
        return $r('sys.symbol.link');
      case 'app_recommendation':
        return $r('sys.symbol.square_fill_grid_2x2');
      case 'about':
        return $r('sys.symbol.info_circle_fill');
      default:
        return $r('sys.symbol.gearshape_fill');
    }
  }

  private resolveAiraIconId(id: SettingsCenterDestination): AiraRenderableIconId | undefined {
    switch (id) {
      case 'advanced_settings':
      case 'app_service_mode':
        return 'settings.appServiceMode';
      case 'aira_pro':
        return 'settings.membership';
      case 'general':
        return 'settings.general';
      case 'custom_homepage':
        return 'settings.customHomepage';
      case 'toolbar_customization':
        return 'settings.toolbar';
      case 'search':
        return 'settings.search';
      case 'privacy_security':
        return 'settings.privacySecurity';
      case 'private_mode':
        return 'browser.toolbar.privacyMode';
      case 'web_features':
        return 'settings.webFeatures';
      case 'user_scripts':
        return 'settings.userScripts';
      case 'webpage_translation':
        return 'settings.webpageTranslation';
      case 'web_apps':
        return 'settings.webApps';
      case 'passwords':
        return 'settings.passwords';
      case 'downloads':
        return 'settings.downloads';
      case 'user_agent':
        return 'settings.userAgent';
      case 'appearance_toolbar':
        return 'settings.appearance';
      case 'cross_device_link':
        return 'browser.toolbar.sendToDesktop';
      case 'experiments':
        return 'settings.experiments';
      case 'sync':
        return 'settings.sync';
      case 'about':
        return 'settings.about';
      default:
        return undefined;
    }
  }

  private getFullModeRequiredValue(isFullServiceMode: boolean): ResourceStr {
    return isFullServiceMode ? '' : localizeSettingsCatalogCopy('需全量模式');
  }

  private isDevicePreferenceEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    dataScope: string,
    privacyMode: string
  ): boolean {
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: dataScope,
        privacyMode: privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }

}
