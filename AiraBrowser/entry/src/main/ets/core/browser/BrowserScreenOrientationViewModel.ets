export type BrowserScreenOrientationMode = 'system' | 'portrait' | 'landscape';

export interface BrowserScreenOrientationOptionState {
  mode: BrowserScreenOrientationMode;
  title: string;
  helperText: string;
  icon: Resource;
  isSelected: boolean;
}

export class BrowserScreenOrientationViewModel {
  buildOptions(selectedMode: BrowserScreenOrientationMode): BrowserScreenOrientationOptionState[] {
    return [
      this.buildOption(
        'system',
        '跟随系统',
        '使用系统旋转锁定与方向设置',
        $r('sys.symbol.gyroscope'),
        selectedMode
      ),
      this.buildOption(
        'portrait',
        '竖屏',
        '将浏览器固定为竖屏显示',
        $r('sys.symbol.rectangle'),
        selectedMode
      ),
      this.buildOption(
        'landscape',
        '横屏',
        '将浏览器固定为横屏显示',
        $r('sys.symbol.rectangle_on_rectangle_fill'),
        selectedMode
      )
    ];
  }

  resolveLabel(mode: BrowserScreenOrientationMode): string {
    if (mode === 'portrait') {
      return '竖屏';
    }
    if (mode === 'landscape') {
      return '横屏';
    }
    return '跟随系统';
  }

  resolveIcon(mode: BrowserScreenOrientationMode): Resource {
    if (mode === 'portrait') {
      return $r('sys.symbol.rectangle');
    }
    if (mode === 'landscape') {
      return $r('sys.symbol.rectangle_on_rectangle_fill');
    }
    return $r('sys.symbol.gyroscope');
  }

  private buildOption(
    mode: BrowserScreenOrientationMode,
    title: string,
    helperText: string,
    icon: Resource,
    selectedMode: BrowserScreenOrientationMode
  ): BrowserScreenOrientationOptionState {
    return {
      mode: mode,
      title: title,
      helperText: helperText,
      icon: icon,
      isSelected: mode === selectedMode
    };
  }
}
