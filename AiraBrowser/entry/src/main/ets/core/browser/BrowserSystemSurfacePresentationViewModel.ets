import { BrowserSystemSheetSnapshot } from './BrowserTransientSurfaceCoordinator';
import { BrowserSystemSheetType } from './BrowserShellRuntimeContracts';

export function isNovelReaderSystemSurfaceType(type: BrowserSystemSheetType): boolean {
  return type === 'novelCatalog' || type === 'novelReaderText' ||
    type === 'novelReaderAppearance' || type === 'novelReaderSettings';
}

export function resolveNovelReaderSystemSurfaceTitle(type: BrowserSystemSheetType): string {
  if (type === 'novelCatalog') {
    return '目录';
  }
  if (type === 'novelReaderAppearance') {
    return '亮度与主题';
  }
  if (type === 'novelReaderSettings') {
    return '阅读设置';
  }
  if (type === 'novelReaderText') {
    return '文字';
  }
  return '';
}

export interface BrowserNovelReaderDialogLayout {
  preferredWidth: number;
  preferredHeight: number;
  softMinWidth: number;
  maxWidth: number;
  softMinHeight: number;
  maxHeight: number;
}

export function resolveNovelReaderSystemSurfaceLayout(
  type: BrowserSystemSheetType
): BrowserNovelReaderDialogLayout {
  if (type === 'novelCatalog') {
    return {
      preferredWidth: 680,
      preferredHeight: 680,
      softMinWidth: 560,
      maxWidth: 760,
      softMinHeight: 500,
      maxHeight: 720
    };
  }
  if (type === 'novelReaderAppearance') {
    return {
      preferredWidth: 520,
      preferredHeight: 270,
      softMinWidth: 460,
      maxWidth: 560,
      softMinHeight: 240,
      maxHeight: 310
    };
  }
  if (type === 'novelReaderText') {
    return {
      preferredWidth: 520,
      preferredHeight: 300,
      softMinWidth: 460,
      maxWidth: 560,
      softMinHeight: 260,
      maxHeight: 340
    };
  }
  return {
    preferredWidth: 600,
    preferredHeight: 560,
    softMinWidth: 500,
    maxWidth: 640,
    softMinHeight: 420,
    maxHeight: 600
  };
}

export interface BrowserSystemSurfacePresentation {
  phoneSheetVisible: boolean;
  largeScreenHomeShortcutDialogVisible: boolean;
  largeScreenHomeSettingsDialogVisible: boolean;
  largeScreenUserScriptInstallDialogVisible: boolean;
  largeScreenNovelReaderDialogVisible: boolean;
  largeScreenNovelReaderDialogTitle: string;
}

export class BrowserSystemSurfacePresentationViewModel {
  resolve(
    systemSheet: BrowserSystemSheetSnapshot,
    shellFamily: 'phone' | 'large_screen'
  ): BrowserSystemSurfacePresentation {
    const largeScreenHomeShortcutDialogVisible = systemSheet.visible &&
      systemSheet.type === 'homeShortcutSelection' &&
      shellFamily === 'large_screen';
    const largeScreenHomeSettingsDialogVisible = systemSheet.visible &&
      systemSheet.type === 'homeSettings' &&
      shellFamily === 'large_screen';
    const largeScreenUserScriptInstallDialogVisible = systemSheet.visible &&
      systemSheet.type === 'userScriptInstall' &&
      shellFamily === 'large_screen';
    const largeScreenNovelReaderDialogVisible = systemSheet.visible &&
      isNovelReaderSystemSurfaceType(systemSheet.type) &&
      shellFamily === 'large_screen';
    return {
      phoneSheetVisible: systemSheet.visible &&
        systemSheet.type !== 'none' &&
        !largeScreenHomeShortcutDialogVisible &&
        !largeScreenHomeSettingsDialogVisible &&
        !largeScreenUserScriptInstallDialogVisible &&
        !largeScreenNovelReaderDialogVisible,
      largeScreenHomeShortcutDialogVisible: largeScreenHomeShortcutDialogVisible,
      largeScreenHomeSettingsDialogVisible: largeScreenHomeSettingsDialogVisible,
      largeScreenUserScriptInstallDialogVisible: largeScreenUserScriptInstallDialogVisible,
      largeScreenNovelReaderDialogVisible: largeScreenNovelReaderDialogVisible,
      largeScreenNovelReaderDialogTitle: resolveNovelReaderSystemSurfaceTitle(systemSheet.type)
    };
  }
}
