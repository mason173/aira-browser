import { BrowserDesktopSiteMode } from '../../services/web/BrowserUserAgentService';

export interface BrowserDesktopSiteModeOptionState {
  mode: BrowserDesktopSiteMode;
  title: string;
  helperText: string;
  isSelected: boolean;
}

export interface BrowserDesktopSiteModeSheetState {
  options: BrowserDesktopSiteModeOptionState[];
  defaultUserAgentSummary: string;
}

export class BrowserDesktopSiteModeSheetViewModel {
  buildState(
    selectedMode: BrowserDesktopSiteMode,
    defaultUserAgentSummary: string
  ): BrowserDesktopSiteModeSheetState {
    return {
      options: [
        this.buildOption('default', '跟随默认', `使用默认网页标识：${defaultUserAgentSummary}`, selectedMode),
        this.buildOption('mobile', '移动版', '只让当前站点使用移动版网页', selectedMode),
        this.buildOption('desktop', '桌面版', '只让当前站点使用桌面版网页', selectedMode)
      ],
      defaultUserAgentSummary: defaultUserAgentSummary
    };
  }

  resolveToolbarLabel(mode: BrowserDesktopSiteMode): string {
    if (mode === 'desktop') {
      return '桌面版';
    }
    if (mode === 'mobile') {
      return '移动版';
    }
    return '跟随默认';
  }

  private buildOption(
    mode: BrowserDesktopSiteMode,
    title: string,
    helperText: string,
    selectedMode: BrowserDesktopSiteMode
  ): BrowserDesktopSiteModeOptionState {
    return {
      mode: mode,
      title: title,
      helperText: helperText,
      isSelected: selectedMode === mode
    };
  }
}
