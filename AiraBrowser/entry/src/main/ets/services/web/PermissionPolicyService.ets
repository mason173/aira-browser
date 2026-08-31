import { common } from '@kit.AbilityKit';
import {
  BrowserDataScope,
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID,
  SitePermissionKind,
  SitePermissionRule,
  SitePermissionSettings
} from '../../common/models/BrowserModels';
import {
  SystemPermissionGrantResult
} from '../system/SystemPermissionService';
import {
  SitePolicyService,
  SiteProtectedResourceDecision
} from './SitePolicyService';

export type PermissionPolicyAction = 'allow' | 'block' | 'prompt' | 'deny';

export interface PermissionPolicyDecision {
  action: PermissionPolicyAction;
  origin: string;
  resources: string[];
  kinds: SitePermissionKind[];
  label: string;
  auditType: string;
  auditMessage: string;
}

export class PermissionPolicyService {
  private sitePolicyService: SitePolicyService;

  constructor(sitePolicyService: SitePolicyService) {
    this.sitePolicyService = sitePolicyService;
  }

  resolveProtectedResourceDecision(
    origin: string,
    resources: string[],
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): PermissionPolicyDecision {
    const decision = this.sitePolicyService.resolveProtectedResourceDecision(origin, resources, profileId, dataScope);
    if (decision === undefined) {
      return this.buildDecision('deny', '', resources, [], '未知权限', 'permission_denied', '无法识别站点权限请求。');
    }
    const settings = this.sitePolicyService.getEffectiveSitePermissionSettings(decision.origin, profileId, dataScope);
    const action = this.resolveAction(settings, decision, profileId, dataScope);
    const label = this.sitePolicyService.getSitePermissionKindsLabel(decision.kinds);
    return this.buildDecision(
      action,
      decision.origin,
      decision.resources,
      decision.kinds,
      label,
      action === 'prompt' ? 'permission_prompt' : `permission_${action}`,
      `${decision.origin} ${this.getActionLabel(action)} ${label}`
    );
  }

  resolveGeolocationDecision(
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): PermissionPolicyDecision {
    const normalizedOrigin = this.sitePolicyService.normalizeOrigin(origin);
    if (normalizedOrigin.length === 0) {
      return this.buildDecision('deny', '', [], ['location'], '位置信息', 'permission_denied', '无法识别定位权限来源。');
    }
    const settings = this.sitePolicyService.getEffectiveSitePermissionSettings(normalizedOrigin, profileId, dataScope);
    let action: PermissionPolicyAction = 'prompt';
    if (settings.location === 'block') {
      action = 'block';
    } else if (this.sitePolicyService.isPermissionAllowedForSession(normalizedOrigin, 'location', profileId, dataScope) ||
      settings.location === 'allow') {
      action = 'allow';
    }
    return this.buildDecision(
      action,
      normalizedOrigin,
      [],
      ['location'],
      '位置信息',
      action === 'prompt' ? 'permission_prompt' : `permission_${action}`,
      `${normalizedOrigin} ${this.getActionLabel(action)} 位置信息`
    );
  }

  requestAppPermissionsForKinds(
    context: common.UIAbilityContext,
    kinds: SitePermissionKind[]
  ): Promise<SystemPermissionGrantResult> {
    return this.sitePolicyService.requestAppPermissionsForKinds(context, kinds);
  }

  requestAppPermissionSettingsForKinds(
    context: common.UIAbilityContext,
    kinds: SitePermissionKind[]
  ): Promise<SystemPermissionGrantResult> {
    return this.sitePolicyService.requestAppPermissionSettingsForKinds(context, kinds);
  }

  getSitePermissionRule(settings: SitePermissionSettings, kind: SitePermissionKind): SitePermissionRule {
    return this.sitePolicyService.getSitePermissionRule(settings, kind);
  }

  private resolveAction(
    settings: SitePermissionSettings,
    decision: SiteProtectedResourceDecision,
    profileId: BrowserProfileId,
    dataScope: BrowserDataScope
  ): PermissionPolicyAction {
    if (this.sitePolicyService.shouldBlockSitePermission(settings, decision.kinds)) {
      return 'block';
    }
    if (this.sitePolicyService.arePermissionsAllowedForSession(decision.origin, decision.kinds, profileId, dataScope)) {
      return 'allow';
    }
    if (this.sitePolicyService.shouldAllowSitePermission(settings, decision.kinds)) {
      return 'allow';
    }
    return 'prompt';
  }

  private buildDecision(
    action: PermissionPolicyAction,
    origin: string,
    resources: string[],
    kinds: SitePermissionKind[],
    label: string,
    auditType: string,
    auditMessage: string
  ): PermissionPolicyDecision {
    return {
      action: action,
      origin: origin,
      resources: resources.slice(),
      kinds: kinds.slice(),
      label: label,
      auditType: auditType,
      auditMessage: auditMessage
    };
  }

  private getActionLabel(action: PermissionPolicyAction): string {
    if (action === 'allow') {
      return '已自动允许';
    }
    if (action === 'block') {
      return '已按规则阻止';
    }
    if (action === 'deny') {
      return '已拒绝';
    }
    return '请求';
  }
}
