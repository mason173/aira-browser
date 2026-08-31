export interface KeyboardShortcutRowState {
  id: string;
  title: string;
  shortcut: string;
}

export interface KeyboardShortcutGroupState {
  id: string;
  title: string;
  rows: KeyboardShortcutRowState[];
}

export class KeyboardShortcutsSettingsViewModel {
  buildGroups(): KeyboardShortcutGroupState[] {
    return [
      {
        id: 'tabs',
        title: '标签页',
        rows: [
          this.row('new_tab', '打开新标签页', 'Ctrl+T'),
          this.row('close_tab', '关闭当前标签页', 'Ctrl+W'),
          this.row('restore_tab', '恢复最近关闭标签页', 'Ctrl+Shift+T'),
          this.row('next_tab', '切到下一个标签页', 'Ctrl+Tab'),
          this.row('previous_tab', '切到上一个标签页', 'Ctrl+Shift+Tab'),
          this.row('numbered_tabs', '切到指定标签页', 'Ctrl+1~9'),
          this.row('tabs_overview', '打开或关闭标签页列表', 'Ctrl+Shift+A'),
          this.row('tabs_overview_keyboard', '在标签页列表中选择标签页', '方向键 / Enter')
        ]
      },
      {
        id: 'browse',
        title: '浏览',
        rows: [
          this.row('address_alt', '焦点移到地址栏', 'Alt+D'),
          this.row('address_ctrl', '焦点移到地址栏', 'Ctrl+L'),
          this.row('find', '查找页面内容', 'Ctrl+F'),
          this.row('reload_ctrl', '刷新页面', 'Ctrl+R'),
          this.row('reload_f5', '刷新页面', 'F5'),
          this.row('fullscreen', '进入或退出全屏', 'F11'),
          this.row('escape', '退出当前状态或停止加载', 'Esc')
        ]
      },
      {
        id: 'navigation',
        title: '导航',
        rows: [
          this.row('back', '后退', 'Alt+Left'),
          this.row('forward', '前进', 'Alt+Right')
        ]
      },
      {
        id: 'management',
        title: '管理',
        rows: [
          this.row('history', '打开历史记录', 'Ctrl+H'),
          this.row('downloads', '打开下载管理', 'Ctrl+J'),
          this.row('bookmark', '收藏当前页面', 'Ctrl+D'),
          this.row('save_offline', '保存当前网页到离线页面', 'Ctrl+S')
        ]
      }
    ];
  }

  private row(id: string, title: string, shortcut: string): KeyboardShortcutRowState {
    return {
      id: id,
      title: title,
      shortcut: shortcut
    };
  }
}
