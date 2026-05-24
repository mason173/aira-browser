export type ShortcutVisualMode = 'favicon' | 'letter';
export type ShortcutIconAppearance = 'colorful' | 'monochrome' | 'accent';
export type ShortcutKind = 'link' | 'folder';
export type ShortcutFolderDisplayMode = 'small' | 'large';

export interface Shortcut {
  id: string;
  title: string;
  url: string;
  icon: string;
  kind?: ShortcutKind;
  children?: Shortcut[];
  folderDisplayMode?: ShortcutFolderDisplayMode;
  iconRendering?: ShortcutVisualMode;
  iconColor?: string;
}

export type ShortcutDraft = Omit<Shortcut, 'id' | 'kind' | 'children'>;
export type ScenarioShortcuts = Record<string, Shortcut[]>;
