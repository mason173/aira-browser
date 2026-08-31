export interface SyncOperationProgressTipsState {
  tips: string[];
  index: number;
  activeTip: string;
}

export interface SyncOperationProgressTimingProfile {
  tipIntervalMs: number;
  visualIntervalMs: number;
  minVisibleMs: number;
  timeoutMs: number;
  finishIntervalMs: number;
  successVisibleMs: number;
  inProgressTarget: number;
}

export const SYNC_OPERATION_PROGRESS_TIMING: SyncOperationProgressTimingProfile = {
  tipIntervalMs: 900,
  visualIntervalMs: 140,
  minVisibleMs: 900,
  timeoutMs: 180000,
  finishIntervalMs: 35,
  successVisibleMs: 360,
  inProgressTarget: 92
};

export class SyncOperationProgressViewModel {
  resolveVisualProgress(currentProgress: number, targetProgress: number, elapsedMs: number): number {
    const current = this.clampProgress(currentProgress);
    const visualCap = Math.min(this.resolveElapsedProgress(elapsedMs), this.clampProgress(targetProgress));
    const target = Math.max(current, Math.min(92, visualCap));
    if (current >= target) {
      return current;
    }
    return target;
  }

  resolveTimeoutMessage(title: string): string {
    if (title.indexOf('上传') >= 0) {
      return '上传时间过长，请检查网络或 WebDAV 服务后再试。';
    }
    if (title.indexOf('下载') >= 0) {
      return '下载时间过长，请检查网络或云端数据后再试。';
    }
    if (title.indexOf('导入') >= 0 || title.indexOf('导出') >= 0) {
      return '书签文件处理时间过长，请稍后再试。';
    }
    return '同步等待时间过长，请检查网络或稍后再试。';
  }

  buildInitialTips(title: string, firstTip: string): SyncOperationProgressTipsState {
    const tips = this.buildTips(title, firstTip);
    return {
      tips: tips,
      index: 0,
      activeTip: tips.length > 0 ? tips[0] : firstTip
    };
  }

  appendTip(state: SyncOperationProgressTipsState, tip: string): SyncOperationProgressTipsState {
    const tips = state.tips.slice();
    this.pushUniqueTip(tips, tip);
    return {
      tips: tips,
      index: state.index,
      activeTip: state.activeTip
    };
  }

  advanceTip(state: SyncOperationProgressTipsState): SyncOperationProgressTipsState {
    if (state.tips.length === 0) {
      return state;
    }
    const index = (state.index + 1) % state.tips.length;
    return {
      tips: state.tips,
      index: index,
      activeTip: state.tips[index]
    };
  }

  private buildTips(title: string, firstTip: string): string[] {
    const tips: string[] = [];
    this.pushUniqueTip(tips, firstTip);
    if (title.indexOf('同步') >= 0) {
      return this.appendTips(tips, [
        '正在整理本机数据',
        '正在确认云端同步状态',
        '正在比较本机和云端变化',
        '正在保护现有数据',
        '正在处理新增和更新内容',
        '正在写入同步记录',
        '正在收尾，请稍候'
      ]);
    }
    if (title.indexOf('上传') >= 0) {
      return this.appendTips(tips, [
        '正在整理本机内容',
        '正在准备云端目录',
        '正在上传本地书签',
        '正在校验云端写入结果',
        '正在更新同步记录'
      ]);
    }
    if (title.indexOf('下载') >= 0) {
      return this.appendTips(tips, [
        '正在连接云端空间',
        '正在读取云端数据',
        '正在检查数据完整性',
        '正在准备写入本机',
        '正在更新本地书签'
      ]);
    }
    if (title.indexOf('导入') >= 0) {
      return this.appendTips(tips, [
        '正在读取书签文件',
        '正在检查书签内容',
        '正在准备恢复数据',
        '正在写入本地书签',
        '正在完成导入'
      ]);
    }
    if (title.indexOf('导出') >= 0) {
      return this.appendTips(tips, [
        '正在整理本机数据',
        '正在生成书签文件',
        '正在写入书签文件',
        '正在确认文件保存结果',
        '正在完成导出'
      ]);
    }
    return this.appendTips(tips, [
      '正在读取当前状态',
      '正在整理本机信息',
      '正在更新显示内容',
      '正在完成处理'
    ]);
  }

  private appendTips(tips: string[], nextTips: string[]): string[] {
    nextTips.forEach((tip: string) => {
      this.pushUniqueTip(tips, tip);
    });
    return tips;
  }

  private pushUniqueTip(tips: string[], tip: string): void {
    const normalized = tip.trim();
    if (normalized.length > 0 && tips.indexOf(normalized) < 0) {
      tips.push(normalized);
    }
  }

  private clampProgress(progress: number): number {
    return Math.max(0, Math.min(100, Math.round(progress)));
  }

  private resolveElapsedProgress(elapsedMs: number): number {
    const elapsed = Math.max(0, elapsedMs);
    const progress = 92 * (1 - Math.exp(0 - elapsed / 8500));
    return Math.max(0, Math.min(92, Math.floor(progress)));
  }
}
