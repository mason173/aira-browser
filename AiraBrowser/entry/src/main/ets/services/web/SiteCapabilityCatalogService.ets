import { Permissions } from '@kit.AbilityKit';
import {
  ExternalNavigationAppOpenPolicy,
  SitePermissionKind,
  SitePermissionRule
} from '../../common/models/BrowserModels';

export type SiteCapabilityId =
  'camera' |
  'microphone' |
  'location' |
  'sensor' |
  'clipboard' |
  'open_app';

export type SiteCustomizationCapabilityFilterId =
  'external_actions' |
  'desktop_site' |
  'private_site' |
  'javascript';

export type SiteCapabilityGroup =
  'device_permission' |
  'navigation_policy';

export interface SiteCapabilityDefinition {
  id: SiteCapabilityId;
  group: SiteCapabilityGroup;
  title: string;
  objectLabel: string;
  summaryLabel: string;
  canSetDefault: boolean;
  canSetSiteRule: boolean;
  requiresSystemPermission: boolean;
}

export interface SitePermissionRuleOption {
  value: SitePermissionRule;
  label: string;
  helperText: string;
}

export interface ExternalNavigationPolicyOption {
  value: ExternalNavigationAppOpenPolicy;
  label: string;
  helperText: string;
}

export interface SiteProtectedResourceResolution {
  resources: string[];
  kinds: SitePermissionKind[];
  unsupportedResources: string[];
}

export class SiteCapabilityCatalogService {
  listDevicePermissionKinds(): SitePermissionKind[] {
    return ['location', 'camera', 'microphone', 'sensor', 'clipboard'];
  }

  getDevicePermissionDefinition(kind: SitePermissionKind): SiteCapabilityDefinition {
    if (kind === 'camera') {
      return {
        id: 'camera',
        group: 'device_permission',
        title: '摄像头',
        objectLabel: '摄像头',
        summaryLabel: '摄像头',
        canSetDefault: true,
        canSetSiteRule: true,
        requiresSystemPermission: true
      };
    }
    if (kind === 'microphone') {
      return {
        id: 'microphone',
        group: 'device_permission',
        title: '麦克风',
        objectLabel: '麦克风',
        summaryLabel: '麦克风',
        canSetDefault: true,
        canSetSiteRule: true,
        requiresSystemPermission: true
      };
    }
    if (kind === 'location') {
      return {
        id: 'location',
        group: 'device_permission',
        title: '位置信息',
        objectLabel: '位置',
        summaryLabel: '定位',
        canSetDefault: true,
        canSetSiteRule: true,
        requiresSystemPermission: true
      };
    }
    if (kind === 'clipboard') {
      return {
        id: 'clipboard',
        group: 'device_permission',
        title: '剪贴板',
        objectLabel: '剪贴板',
        summaryLabel: '剪贴板',
        canSetDefault: true,
        canSetSiteRule: true,
        requiresSystemPermission: true
      };
    }
    return {
      id: 'sensor',
      group: 'device_permission',
      title: '传感器',
      objectLabel: '传感器',
      summaryLabel: '传感器',
      canSetDefault: true,
      canSetSiteRule: true,
      requiresSystemPermission: true
    };
  }

  getOpenAppDefinition(): SiteCapabilityDefinition {
    return {
      id: 'open_app',
      group: 'navigation_policy',
      title: '打开应用',
      objectLabel: '外部应用',
      summaryLabel: '打开应用',
      canSetDefault: true,
      canSetSiteRule: true,
      requiresSystemPermission: false
    };
  }

  resolvePermissionKind(value: string): SitePermissionKind {
    if (value === 'microphone' || value === 'location' || value === 'sensor' || value === 'clipboard') {
      return value;
    }
    return 'camera';
  }

  getPermissionTitle(kind: SitePermissionKind): string {
    return this.getDevicePermissionDefinition(kind).title;
  }

  getPermissionObjectLabel(kind: SitePermissionKind): string {
    return this.getDevicePermissionDefinition(kind).objectLabel;
  }

  getPermissionSummaryLabel(kind: SitePermissionKind): string {
    return this.getDevicePermissionDefinition(kind).summaryLabel;
  }

  getPermissionKindsLabel(kinds: SitePermissionKind[]): string {
    return kinds.map((kind: SitePermissionKind) => this.getPermissionTitle(kind)).join('和');
  }

  getPermissionRuleLabel(rule: SitePermissionRule): string {
    if (rule === 'allow') {
      return '允许';
    }
    if (rule === 'block') {
      return '阻止';
    }
    return '询问';
  }

  getPermissionRuleDescription(kind: SitePermissionKind, rule: SitePermissionRule): string {
    if (rule === 'allow') {
      return '已允许此站点使用';
    }
    if (rule === 'block') {
      return '已阻止此站点使用';
    }
    return '每次访问前询问';
  }

  buildSitePermissionOptions(kind: SitePermissionKind): SitePermissionRuleOption[] {
    const objectLabel = this.getPermissionObjectLabel(kind);
    return [
      {
        value: 'ask',
        label: '询问',
        helperText: `网站请求${objectLabel}时先询问`
      },
      {
        value: 'allow',
        label: '允许',
        helperText: `允许此站点使用${objectLabel}`
      },
      {
        value: 'block',
        label: '阻止',
        helperText: `阻止此站点使用${objectLabel}`
      }
    ];
  }

  buildDefaultPermissionOptions(): SitePermissionRuleOption[] {
    return [
      {
        value: 'ask',
        label: '询问',
        helperText: '每次请求都确认'
      },
      {
        value: 'allow',
        label: '允许',
        helperText: '默认允许'
      },
      {
        value: 'block',
        label: '阻止',
        helperText: '默认阻止'
      }
    ];
  }

  buildExternalNavigationOptions(): ExternalNavigationPolicyOption[] {
    return [
      {
        value: 'ask',
        label: '跟随默认',
        helperText: '使用全局外部应用打开策略'
      },
      {
        value: 'allow',
        label: '允许',
        helperText: '用户触发时允许打开外部应用'
      },
      {
        value: 'block',
        label: '阻止',
        helperText: '阻止此站点打开外部应用'
      }
    ];
  }

  getExternalNavigationPolicyLabel(policy: ExternalNavigationAppOpenPolicy): string {
    if (policy === 'allow') {
      return '允许';
    }
    if (policy === 'block') {
      return '阻止';
    }
    return '询问';
  }

  resolveSitePermissionKinds(resources: string[]): SitePermissionKind[] {
    return this.resolveProtectedResources(resources).kinds;
  }

  resolveProtectedResources(resources: string[]): SiteProtectedResourceResolution {
    const supportedResources: string[] = [];
    const kinds: SitePermissionKind[] = [];
    const unsupportedResources: string[] = [];
    resources.forEach((resource: string) => {
      if (resource === 'TYPE_VIDEO_CAPTURE') {
        if (!kinds.includes('camera')) {
          kinds.push('camera');
        }
        supportedResources.push(resource);
        return;
      }
      if (resource === 'TYPE_AUDIO_CAPTURE') {
        if (!kinds.includes('microphone')) {
          kinds.push('microphone');
        }
        supportedResources.push(resource);
        return;
      }
      if (resource === 'TYPE_SENSOR') {
        if (!kinds.includes('sensor')) {
          kinds.push('sensor');
        }
        supportedResources.push(resource);
        return;
      }
      unsupportedResources.push(resource);
    });
    return {
      resources: supportedResources,
      kinds: kinds,
      unsupportedResources: unsupportedResources
    };
  }

  resolveSystemPermissions(kinds: SitePermissionKind[]): Permissions[] {
    const permissions: Permissions[] = [];
    if (kinds.includes('camera')) {
      permissions.push('ohos.permission.CAMERA');
    }
    if (kinds.includes('microphone')) {
      permissions.push('ohos.permission.MICROPHONE');
    }
    if (kinds.includes('location')) {
      permissions.push('ohos.permission.APPROXIMATELY_LOCATION');
      permissions.push('ohos.permission.LOCATION');
    }
    if (kinds.includes('sensor')) {
      permissions.push('ohos.permission.ACCELEROMETER');
    }
    if (kinds.includes('clipboard')) {
      permissions.push('ohos.permission.READ_PASTEBOARD');
    }
    return permissions;
  }
}
