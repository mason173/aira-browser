import { appInfoManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface DynamicAppIconOption {
  iconId: string;
  iconUrl: string;
  enabled: boolean;
}

export type DynamicAppIconAvailability =
  'available' |
  'empty' |
  'service_unavailable' |
  'internal_error';

export interface DynamicAppIconQueryResult {
  availability: DynamicAppIconAvailability;
  icons: DynamicAppIconOption[];
  code: number;
  message: string;
}

export type DynamicAppIconMutationKind = 'select' | 'restore_default';

export interface DynamicAppIconMutationResult {
  ok: boolean;
  kind: DynamicAppIconMutationKind;
  code: number;
  message: string;
}

const DYNAMIC_ICON_SERVICE_CONNECT_FAILED_CODE: number = 1006800001;
const DYNAMIC_ICON_INTERNAL_ERROR_CODE: number = 1006800009;
const DYNAMIC_ICON_NO_DATA_CODE: number = 1006800010;
const DYNAMIC_ICON_SELECT_FAILED_CODE: number = 1006800011;
const DYNAMIC_ICON_DISABLE_FAILED_CODE: number = 1006800012;
const DYNAMIC_ICON_CUSTOM_THEME_CONFLICT_CODE: number = 1006800013;

export class DynamicAppIconService {
  async queryIcons(): Promise<DynamicAppIconQueryResult> {
    try {
      const icons = await appInfoManager.queryDynamicIcons();
      const mappedIcons = icons.map((icon: appInfoManager.DynamicIconInfo): DynamicAppIconOption => {
        return {
          iconId: icon.iconId,
          iconUrl: icon.iconUrl,
          enabled: icon.enabled
        };
      });
      return {
        availability: mappedIcons.length > 0 ? 'available' : 'empty',
        icons: mappedIcons,
        code: 0,
        message: mappedIcons.length > 0 ? '' : '暂无可用的应用图标。'
      };
    } catch (error) {
      return this.buildQueryFailure(error as BusinessError);
    }
  }

  async selectIcon(iconId: string): Promise<DynamicAppIconMutationResult> {
    const normalizedIconId = iconId.trim();
    if (normalizedIconId.length <= 0) {
      return {
        ok: false,
        kind: 'select',
        code: 401,
        message: '图标信息无效。'
      };
    }
    try {
      await appInfoManager.selectDynamicIcon(normalizedIconId);
      return {
        ok: true,
        kind: 'select',
        code: 0,
        message: '应用图标已更新。'
      };
    } catch (error) {
      return this.buildMutationFailure('select', error as BusinessError);
    }
  }

  async restoreDefaultIcon(): Promise<DynamicAppIconMutationResult> {
    try {
      await appInfoManager.disableDynamicIcon();
      return {
        ok: true,
        kind: 'restore_default',
        code: 0,
        message: '已恢复默认应用图标。'
      };
    } catch (error) {
      return this.buildMutationFailure('restore_default', error as BusinessError);
    }
  }

  private buildQueryFailure(error: BusinessError): DynamicAppIconQueryResult {
    const code = Number(error?.code ?? 0);
    if (code === DYNAMIC_ICON_NO_DATA_CODE) {
      return {
        availability: 'empty',
        icons: [],
        code: code,
        message: '暂无可用的应用图标。'
      };
    }
    if (code === DYNAMIC_ICON_SERVICE_CONNECT_FAILED_CODE) {
      return {
        availability: 'service_unavailable',
        icons: [],
        code: code,
        message: '图标管理服务暂不可用。'
      };
    }
    if (code === DYNAMIC_ICON_INTERNAL_ERROR_CODE) {
      return {
        availability: 'internal_error',
        icons: [],
        code: code,
        message: '读取应用图标失败，请稍后重试。'
      };
    }
    return {
      availability: 'service_unavailable',
      icons: [],
      code: code,
      message: '暂时无法读取应用图标。'
    };
  }

  private buildMutationFailure(
    kind: DynamicAppIconMutationKind,
    error: BusinessError
  ): DynamicAppIconMutationResult {
    const code = Number(error?.code ?? 0);
    return {
      ok: false,
      kind: kind,
      code: code,
      message: this.resolveMutationFailureMessage(kind, code)
    };
  }

  private resolveMutationFailureMessage(kind: DynamicAppIconMutationKind, code: number): string {
    if (code === DYNAMIC_ICON_CUSTOM_THEME_CONFLICT_CODE) {
      return '当前系统主题正在使用自定义图标，无法切换应用图标。';
    }
    if (kind === 'select' && code === DYNAMIC_ICON_SELECT_FAILED_CODE) {
      return '切换应用图标失败，请稍后重试。';
    }
    if (kind === 'restore_default' && code === DYNAMIC_ICON_DISABLE_FAILED_CODE) {
      return '恢复默认图标失败，请稍后重试。';
    }
    if (code === DYNAMIC_ICON_INTERNAL_ERROR_CODE) {
      return '图标管理服务异常，请稍后重试。';
    }
    return kind === 'select' ? '切换应用图标失败。' : '恢复默认图标失败。';
  }
}
