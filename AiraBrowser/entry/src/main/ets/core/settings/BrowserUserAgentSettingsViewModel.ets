import {
  BrowserCustomUserAgentRecord,
  BrowserUserAgentMode,
  BrowserUserAgentPresetId,
  BrowserUserAgentSettings
} from '../../common/models/BrowserModels';
import {
  BrowserUserAgentPreset,
  BrowserUserAgentService,
  ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID,
  SYSTEM_DEFAULT_USER_AGENT_PRESET_ID
} from '../../services/web/BrowserUserAgentService';

export interface BrowserUserAgentOptionView {
  id: BrowserUserAgentPresetId;
  title: string;
  subtitle: string;
  mode: BrowserUserAgentMode;
  icon: Resource;
}

export interface BrowserCustomUserAgentOptionView {
  id: string;
  title: string;
  subtitle: string;
  mode: BrowserUserAgentMode;
  userAgent: string;
}

export interface BrowserUserAgentSettingsViewState {
  summary: string;
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
      summary: this.service.resolveSettingsSummary(normalized),
      customUserAgent: normalized.customUserAgent,
      selectedCustomUserAgentId: normalized.selectedCustomUserAgentId,
      customUserAgents: this.buildCustomUserAgentOptions(normalized.customUserAgents),
      mobileOptions: this.buildOptions(normalized, 'mobile'),
      desktopOptions: this.buildOptions(normalized, 'desktop')
    };
  }

  private buildOptions(
    settings: BrowserUserAgentSettings,
    mode: BrowserUserAgentMode
  ): BrowserUserAgentOptionView[] {
    return this.service.getPresets()
      .filter((preset: BrowserUserAgentPreset) => preset.mode === mode)
      .map((preset: BrowserUserAgentPreset) => {
        const option: BrowserUserAgentOptionView = {
          id: preset.id,
          title: preset.title,
          subtitle: this.resolveOptionSubtitle(preset),
          mode: preset.mode,
          icon: this.resolveOptionIcon(preset)
        };
        return option;
      });
  }

  private resolveOptionSubtitle(preset: BrowserUserAgentPreset): string {
    if (preset.id === SYSTEM_DEFAULT_USER_AGENT_PRESET_ID) {
      return preset.subtitle;
    }
    if (preset.mode === 'desktop') {
      return `${preset.subtitle}，可能影响部分网站验证`;
    }
    return `${preset.subtitle}，验证异常时建议改回 Aira 默认`;
  }

  private resolveOptionIcon(preset: BrowserUserAgentPreset): Resource {
    if (preset.id === ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID) {
      return $r('sys.symbol.compass_circle_fill');
    }
    if (preset.mode === 'desktop') {
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
        mode: 'custom',
        userAgent: record.userAgent
      };
      return option;
    });
  }

  private resolveCustomUserAgentSubtitle(userAgent: string): string {
    const trimmedUserAgent = userAgent.trim();
    if (trimmedUserAgent.length <= 0) {
      return '未填写 UA';
    }
    return trimmedUserAgent.length > 72 ? `${trimmedUserAgent.slice(0, 72)}...` : trimmedUserAgent;
  }
}
