import {
  BrowserDownloadAutoClearPolicy,
  BrowserDownloadLocation,
  BrowserHlsSegmentConcurrency,
  BrowserPrivateDownloadFilePolicy,
  BrowserPrivateDownloadRecordPolicy,
  BrowserDownloadSettings
} from '../../common/models/BrowserModels';

export interface DownloadSettingsOptionView<T> {
  value: T;
  label: string;
  helperText: string;
}

export interface DownloadSettingsSectionState {
  summaryText: string;
  helperText: string;
  defaultLocation: BrowserDownloadLocation;
  defaultLocationLabel: string;
  askBeforeDownload: boolean;
  allowCellularDownloads: boolean;
  autoResumeAfterRestart: boolean;
  hlsSegmentConcurrency: BrowserHlsSegmentConcurrency;
  autoClearPolicy: BrowserDownloadAutoClearPolicy;
  privateFilePolicy: BrowserPrivateDownloadFilePolicy;
  privateRecordPolicy: BrowserPrivateDownloadRecordPolicy;
  autoClearOptions: DownloadSettingsOptionView<BrowserDownloadAutoClearPolicy>[];
  hlsSegmentConcurrencyOptions: DownloadSettingsOptionView<BrowserHlsSegmentConcurrency>[];
  privateFileOptions: DownloadSettingsOptionView<BrowserPrivateDownloadFilePolicy>[];
  privateRecordOptions: DownloadSettingsOptionView<BrowserPrivateDownloadRecordPolicy>[];
}

const DOWNLOAD_AUTO_CLEAR_OPTIONS: DownloadSettingsOptionView<BrowserDownloadAutoClearPolicy>[] = [
  {
    value: 'manual',
    label: '手动',
    helperText: '保留所有记录'
  },
  {
    value: 'clear_completed',
    label: '仅清理已完成',
    helperText: '完成后自动收起'
  },
  {
    value: 'clear_completed_and_failed',
    label: '清理已完成和失败',
    helperText: '完成和失败后收起'
  }
];

const HLS_SEGMENT_CONCURRENCY_OPTIONS: DownloadSettingsOptionView<BrowserHlsSegmentConcurrency>[] = [
  {
    value: '4',
    label: '4',
    helperText: ''
  },
  {
    value: '8',
    label: '8',
    helperText: ''
  },
  {
    value: '16',
    label: '16',
    helperText: ''
  }
];

const PRIVATE_DOWNLOAD_FILE_OPTIONS: DownloadSettingsOptionView<BrowserPrivateDownloadFilePolicy>[] = [
  {
    value: 'prompt_for_location',
    label: '下载前询问',
    helperText: '下载前确认'
  },
  {
    value: 'session_temp_only',
    label: '仅保留临时文件',
    helperText: '退出私密后清理'
  }
];

const PRIVATE_DOWNLOAD_RECORD_OPTIONS: DownloadSettingsOptionView<BrowserPrivateDownloadRecordPolicy>[] = [
  {
    value: 'keep_until_window_close',
    label: '关闭私密窗口后清除',
    helperText: '仅本次私密会话保留'
  },
  {
    value: 'clear_after_export',
    label: '导出后立即清除',
    helperText: '导出后移除记录'
  }
];

export class DownloadSettingsViewModel {
  buildState(settings: BrowserDownloadSettings): DownloadSettingsSectionState {
    return {
      summaryText: this.buildSummaryText(settings),
      helperText: this.buildHelperText(settings),
      defaultLocation: settings.defaultLocation,
      defaultLocationLabel: this.getLocationLabel(settings.defaultLocation),
      askBeforeDownload: settings.askBeforeDownload,
      allowCellularDownloads: settings.allowCellularDownloads,
      autoResumeAfterRestart: settings.autoResumeAfterRestart,
      hlsSegmentConcurrency: settings.hlsSegmentConcurrency,
      autoClearPolicy: settings.autoClearPolicy,
      privateFilePolicy: settings.privateFilePolicy,
      privateRecordPolicy: settings.privateRecordPolicy,
      autoClearOptions: DOWNLOAD_AUTO_CLEAR_OPTIONS.slice(),
      hlsSegmentConcurrencyOptions: HLS_SEGMENT_CONCURRENCY_OPTIONS.slice(),
      privateFileOptions: PRIVATE_DOWNLOAD_FILE_OPTIONS.slice(),
      privateRecordOptions: PRIVATE_DOWNLOAD_RECORD_OPTIONS.slice()
    };
  }

  buildSettingsPatch(
    currentSettings: BrowserDownloadSettings,
    patch: Partial<BrowserDownloadSettings>
  ): BrowserDownloadSettings {
    return {
      defaultLocation: patch.defaultLocation ?? currentSettings.defaultLocation,
      askBeforeDownload: patch.askBeforeDownload ?? currentSettings.askBeforeDownload,
      allowCellularDownloads: patch.allowCellularDownloads ?? currentSettings.allowCellularDownloads,
      autoResumeAfterRestart: patch.autoResumeAfterRestart ?? currentSettings.autoResumeAfterRestart,
      hlsSegmentConcurrency: patch.hlsSegmentConcurrency ?? currentSettings.hlsSegmentConcurrency,
      autoClearPolicy: patch.autoClearPolicy ?? currentSettings.autoClearPolicy,
      privateFilePolicy: patch.privateFilePolicy ?? currentSettings.privateFilePolicy,
      privateRecordPolicy: patch.privateRecordPolicy ?? currentSettings.privateRecordPolicy
    };
  }

  private buildSummaryText(settings: BrowserDownloadSettings): string {
    const askBeforeDownloadLabel = settings.askBeforeDownload ? '下载前询问' : '直接下载';
    const networkLabel = settings.allowCellularDownloads ? '可用移动数据' : '仅 WLAN';
    const resumeLabel = settings.autoResumeAfterRestart ? '启动后恢复' : '手动恢复';
    return `${this.getLocationLabel(settings.defaultLocation)} · ${askBeforeDownloadLabel} · ${networkLabel} · ${resumeLabel}`;
  }

  private buildHelperText(settings: BrowserDownloadSettings): string {
    if (!settings.autoResumeAfterRestart) {
      return '重启后不会自动继续未完成下载';
    }
    if (settings.askBeforeDownload) {
      return '下载前先确认';
    }
    if (settings.autoClearPolicy === 'manual') {
      return '记录保留到手动清理';
    }
    return '记录会按规则收起';
  }

  private getLocationLabel(location: BrowserDownloadLocation): string {
    return location === 'system_downloads' ? '我的手机/Download/Aira' : location;
  }

}
