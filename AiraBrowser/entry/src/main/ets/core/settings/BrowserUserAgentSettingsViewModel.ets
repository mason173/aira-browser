import {
  BrowserCustomUserAgentRecord,
  BrowserUserAgentMode,
  BrowserUserAgentPresetId,
  BrowserUserAgentSettings
} from '../../common/models/BrowserModels';
import {
  BrowserUserAgentPreset,
  BrowserUserAgentPresetKind,
  BrowserDesktopSiteMode,
  BrowserUserAgentService,
  ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID,
  APPLICATION_DEFAULT_USER_AGENT_PRESET_ID
} from '../../services/web/BrowserUserAgentService';
import { resolveAppResourceText } from '../resources/AppResourceText';

export interface BrowserUserAgentOptionView {
  id: BrowserUserAgentPresetId;
  title: ResourceStr;
  subtitle: ResourceStr;
  kind: BrowserUserAgentPresetKind;
  presentationMode: BrowserDesktopSiteMode;
  selectionMode: BrowserUserAgentMode;
  icon: Resource;
}

export interface BrowserCustomUserAgentOptionView {
  id: string;
  title: string;
  subtitle: ResourceStr;
  selectionMode: BrowserUserAgentMode;
  userAgent: string;
}

export interface BrowserUserAgentSettingsViewState {
  summary: ResourceStr;
  customUserAgent: string;
  selectedCustomUserAgentId: string;
  customUserAgents: BrowserCustomUserAgentOptionView[];
  mobileOptions: BrowserUserAgentOptionView[];
  desktopOptions: BrowserUserAgentOptionView[];
}

export class BrowserUserAgentSettingsViewModel {
  private service: BrowserUserAgentService = new BrowserUserAgentService();

  buildState(settings: BrowserUserAgentSettings): BrowserUserAgentSettingsViewState {
    const normalized = this.service.normalizeSettings(settings);
    return {
      summary: this.resolveSettingsSummary(normalized),
      customUserAgent: normalized.customUserAgent,
      selectedCustomUserAgentId: normalized.selectedCustomUserAgentId,
      customUserAgents: this.buildCustomUserAgentOptions(normalized.customUserAgents),
      mobileOptions: this.buildOptions('mobile'),
      desktopOptions: this.buildOptions('desktop')
    };
  }

  resolveDesktopPresentationOptions(state: BrowserUserAgentSettingsViewState): BrowserUserAgentOptionView[] {
    // Automatic/native choices are neutral; their phone UI grouping does not restrict availability.
    return state.mobileOptions.filter((option: BrowserUserAgentOptionView): boolean =>
      option.presentationMode === 'default'
    ).concat(state.desktopOptions);
  }

  /**
   * Same decision as BrowserUserAgentService.resolveSettingsSummary, but resolved to a resource so the
   * identity catalog's own titles swap with the app language instead of staying in the source language.
   */
  resolveSettingsSummary(settings: BrowserUserAgentSettings): ResourceStr {
    const normalized = this.service.normalizeSettings(settings);
    if (normalized.defaultMode === 'custom') {
      const selectedCustomUserAgent = normalized.customUserAgents
        .find((record: BrowserCustomUserAgentRecord) => record.id === normalized.selectedCustomUserAgentId);
      if (selectedCustomUserAgent !== undefined) {
        return selectedCustomUserAgent.name;
      }
      return normalized.customUserAgent.length > 0
        ? $r('app.string.settings_custom_ua')
        : $r('app.string.web_ua_custom_ua_empty');
    }
    return this.resolvePresetTitle(normalized.selectedPresetId);
  }

  private buildOptions(
    mode: 'mobile' | 'desktop'
  ): BrowserUserAgentOptionView[] {
    return this.service.getPresets()
      .filter((preset: BrowserUserAgentPreset) => preset.presentationMode === mode ||
        (mode === 'mobile' && preset.presentationMode === 'default'))
      .map((preset: BrowserUserAgentPreset) => {
        const option: BrowserUserAgentOptionView = {
          id: preset.id,
          title: this.resolvePresetTitle(preset.id),
          subtitle: this.resolveOptionSubtitle(preset),
          kind: preset.kind,
          presentationMode: preset.presentationMode,
          selectionMode: this.service.resolvePresetSettingsMode(preset.id),
          icon: this.resolveOptionIcon(preset)
        };
        return option;
      });
  }

  private resolvePresetTitle(presetId: BrowserUserAgentPresetId): ResourceStr {
    switch (presetId) {
      case APPLICATION_DEFAULT_USER_AGENT_PRESET_ID:
        return $r('app.string.web_ua_preset_aira_default');
      case ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID:
        return $r('app.string.web_ua_preset_arkweb_original');
      case 'mobile_huawei_browser':
        return $r('app.string.web_ua_preset_huawei_browser');
      case 'mobile_chrome_android':
        return $r('app.string.web_ua_preset_chrome_android');
      case 'mobile_safari_iphone':
        return $r('app.string.web_ua_preset_safari_iphone');
      case 'desktop_chrome_windows':
        return $r('app.string.web_ua_preset_chrome_windows');
      case 'desktop_edge_windows':
        return $r('app.string.web_ua_preset_edge_windows');
      case 'desktop_safari_mac':
        return $r('app.string.web_ua_preset_safari_mac');
      case 'desktop_firefox_windows':
        return $r('app.string.web_ua_preset_firefox_windows');
      default:
        return this.service.findPreset(presetId).title;
    }
  }

  private resolvePresetSubtitle(presetId: BrowserUserAgentPresetId): ResourceStr {
    switch (presetId) {
      case APPLICATION_DEFAULT_USER_AGENT_PRESET_ID:
        return $r('app.string.web_ua_preset_aira_default_desc');
      case ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID:
        return $r('app.string.web_ua_preset_arkweb_original_desc');
      case 'mobile_huawei_browser':
        return $r('app.string.web_ua_preset_huawei_browser_desc');
      case 'mobile_chrome_android':
        return $r('app.string.web_ua_preset_chrome_android_desc');
      case 'mobile_safari_iphone':
        return $r('app.string.web_ua_preset_safari_iphone_desc');
      case 'desktop_chrome_windows':
        return $r('app.string.web_ua_preset_chrome_windows_desc');
      case 'desktop_edge_windows':
        return $r('app.string.web_ua_preset_edge_windows_desc');
      case 'desktop_safari_mac':
        return $r('app.string.web_ua_preset_safari_mac_desc');
      case 'desktop_firefox_windows':
        return $r('app.string.web_ua_preset_firefox_windows_desc');
      default:
        return this.service.findPreset(presetId).subtitle;
    }
  }

  private resolveOptionSubtitle(preset: BrowserUserAgentPreset): ResourceStr {
    const presetSubtitle = this.resolvePresetSubtitle(preset.id);
    if (preset.presentationMode === 'default') {
      return presetSubtitle;
    }
    const presetSubtitleText = this.resolveResourceText(presetSubtitle);
    if (preset.presentationMode === 'desktop') {
      return $r('app.string.web_ua_option_desktop_note', presetSubtitleText);
    }
    return $r('app.string.web_ua_option_mobile_note', presetSubtitleText);
  }

  private resolveResourceText(value: ResourceStr): string {
    return typeof value === 'string' ? value : resolveAppResourceText(value);
  }

  private resolveOptionIcon(preset: BrowserUserAgentPreset): Resource {
    if (preset.id === ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID) {
      return $r('sys.symbol.compass_circle_fill');
    }
    if (preset.presentationMode === 'desktop') {
      return $r('sys.symbol.rectangle_on_rectangle_fill');
    }
    return $r('sys.symbol.phone_fill');
  }

  private buildCustomUserAgentOptions(records: BrowserCustomUserAgentRecord[]): BrowserCustomUserAgentOptionView[] {
    return records.map((record: BrowserCustomUserAgentRecord) => {
      const option: BrowserCustomUserAgentOptionView = {
        id: record.id,
        title: record.name,
        subtitle: this.resolveCustomUserAgentSubtitle(record.userAgent),
        selectionMode: 'custom',
        userAgent: record.userAgent
      };
      return option;
    });
  }

  private resolveCustomUserAgentSubtitle(userAgent: string): ResourceStr {
    const trimmedUserAgent = userAgent.trim();
    if (trimmedUserAgent.length <= 0) {
      return $r('app.string.web_ua_custom_ua_subtitle_empty');
    }
    return trimmedUserAgent.length > 72 ? `${trimmedUserAgent.slice(0, 72)}...` : trimmedUserAgent;
  }
}
