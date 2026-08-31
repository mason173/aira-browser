import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { productViewManager } from '@kit.AppGalleryKit';
import {
  DESKTOP_WEB_SHORTCUT_ID_PREFIX,
  DESKTOP_WEB_SHORTCUT_SOURCE,
  DESKTOP_WEB_SHORTCUT_WANT_KEYS
} from '../../data/webapps/WebAppInstallModels';

export interface WebAppPinnedShortcutState {
  shortcutIds: string[];
  isTrusted: boolean;
  errorCode: number;
}

interface PinShortcutInfoCompat {
  shortcutId: string;
  want?: Want;
}

export class WebAppPinnedShortcutCoordinator {
  async queryPinnedShortcutState(): Promise<WebAppPinnedShortcutState> {
    try {
      const infos = await productViewManager.getPinShortcutInfos() as PinShortcutInfoCompat[];
      return {
        shortcutIds: this.extractAiraShortcutIds(infos),
        isTrusted: true,
        errorCode: 0
      };
    } catch (error) {
      const businessError = error as BusinessError;
      return {
        shortcutIds: [],
        isTrusted: false,
        errorCode: Number(businessError?.code ?? 0)
      };
    }
  }

  private extractAiraShortcutIds(infos: PinShortcutInfoCompat[]): string[] {
    const ids: string[] = [];
    infos.forEach((info: PinShortcutInfoCompat) => {
      const shortcutId = info.shortcutId.trim();
      if (shortcutId.length === 0 || ids.indexOf(shortcutId) >= 0) {
        return;
      }
      if (this.isAiraDesktopWebShortcut(info)) {
        ids.push(shortcutId);
      }
    });
    return ids;
  }

  private isAiraDesktopWebShortcut(info: PinShortcutInfoCompat): boolean {
    if (info.shortcutId.trim().startsWith(DESKTOP_WEB_SHORTCUT_ID_PREFIX)) {
      return true;
    }
    const parameters = info.want?.parameters as Record<string, Object> | undefined;
    const source = String(parameters?.[DESKTOP_WEB_SHORTCUT_WANT_KEYS.source] ?? '').trim();
    return source === DESKTOP_WEB_SHORTCUT_SOURCE;
  }
}
