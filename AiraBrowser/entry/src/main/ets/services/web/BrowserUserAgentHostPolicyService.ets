import { webview } from '@kit.ArkWeb';
import {
  BrowserUserAgentApplicationFamily,
  BrowserUserAgentService
} from './BrowserUserAgentService';
import { BrowserUserAgentSettings } from '../../common/models/BrowserModels';
import {
  BrowserUserAgentHostPolicyCatalog,
  BrowserUserAgentHostPolicyMatch,
  BrowserUserAgentHostPolicyGroup
} from './BrowserUserAgentHostPolicyCatalog';
import { BrowserUserAgentMandatoryCompatibility } from './BrowserUserAgentService';

const sharedBrowserUserAgentHostPolicyCatalog: BrowserUserAgentHostPolicyCatalog =
  new BrowserUserAgentHostPolicyCatalog();

export interface BrowserUserAgentHostPolicyApplyResult {
  applied: boolean;
  hosts: string[];
  profileIds: string[];
  ruleIds: string[];
  message: string;
}

export interface BrowserUserAgentApplicationPolicyApplyResult {
  applied: boolean;
  userAgent: string;
  message: string;
}

export class BrowserUserAgentHostPolicyService {
  private static currentApplicationFamily: BrowserUserAgentApplicationFamily = 'mobile';
  private readonly userAgentService: BrowserUserAgentService = new BrowserUserAgentService();
  private readonly compatibilityCatalog: BrowserUserAgentHostPolicyCatalog =
    sharedBrowserUserAgentHostPolicyCatalog;
  private applicationFamily: BrowserUserAgentApplicationFamily = 'mobile';
  private lastAppliedHostPolicyKey: string = '';

  static resolveCurrentApplicationFamily(): BrowserUserAgentApplicationFamily {
    return BrowserUserAgentHostPolicyService.currentApplicationFamily;
  }

  static resolveMandatoryCompatibilityForHost(
    host: string,
    requestedApplicationFamily?: BrowserUserAgentApplicationFamily
  ): BrowserUserAgentMandatoryCompatibility | undefined {
    const normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.length <= 0) {
      return undefined;
    }
    const applicationFamily = requestedApplicationFamily ??
      BrowserUserAgentHostPolicyService.currentApplicationFamily;
    const match: BrowserUserAgentHostPolicyMatch | undefined =
      sharedBrowserUserAgentHostPolicyCatalog.resolveMandatoryCompatibility(
        BrowserUserAgentHostPolicyService.currentApplicationFamily,
        normalizedHost,
        applicationFamily
      );
    if (match === undefined) {
      return undefined;
    }
    return {
      host: match.host,
      ruleId: match.ruleId,
      identityId: `host_profile:${match.profileId}`,
      reason: match.reason,
      userAgent: match.userAgent,
      mode: match.profileId === 'aira_android_compat' ? 'mobile' : 'desktop'
    };
  }

  applyApplicationUserAgentForSettings(
    settings: BrowserUserAgentSettings
  ): BrowserUserAgentApplicationPolicyApplyResult {
    const hostPolicyResult = this.applyHostCompatibilityPolicy();
    let systemDefaultUserAgent = '';
    try {
      systemDefaultUserAgent = webview.WebviewController.getDefaultUserAgent();
    } catch (_error) {
    }
    const applicableDefaultUserAgent = this.userAgentService.resolveApplicationDefaultUserAgent(
      settings,
      systemDefaultUserAgent,
      this.applicationFamily
    );
    const applicableDefaultMessage = this.applicationFamily === 'mobile'
      ? 'Phone Shell uses the Android-compatible Aira Default through the per-controller Browsing Identity runtime.'
      : 'Large-Screen Shell uses the desktop default through the per-controller Browsing Identity runtime.';
    return {
      applied: hostPolicyResult.applied,
      userAgent: applicableDefaultUserAgent,
      message: `${hostPolicyResult.message} ${applicableDefaultMessage}`
    };
  }

  reconcileApplicationUserAgentForDevice(
    settings: BrowserUserAgentSettings,
    detectedFormFactor: string
  ): BrowserUserAgentApplicationPolicyApplyResult {
    this.applicationFamily = this.userAgentService.resolveApplicationFamilyForDevice(detectedFormFactor);
    BrowserUserAgentHostPolicyService.currentApplicationFamily = this.applicationFamily;
    return this.applyApplicationUserAgentForSettings(settings);
  }

  reconcileApplicationUserAgentForPresentation(
    settings: BrowserUserAgentSettings,
    shellFamily: string
  ): BrowserUserAgentApplicationPolicyApplyResult {
    this.applicationFamily = this.userAgentService.resolveApplicationFamilyForShell(shellFamily);
    BrowserUserAgentHostPolicyService.currentApplicationFamily = this.applicationFamily;
    return this.applyApplicationUserAgentForSettings(settings);
  }

  applyHostCompatibilityPolicy(): BrowserUserAgentHostPolicyApplyResult {
    let groups: BrowserUserAgentHostPolicyGroup[] = [];
    try {
      groups = this.compatibilityCatalog.resolve(this.applicationFamily);
    } catch (error) {
      return {
        applied: false,
        hosts: [],
        profileIds: [],
        ruleIds: [],
        message: `Host User-Agent compatibility catalog rejected: ${JSON.stringify(error)}`
      };
    }

    const hosts: string[] = [];
    const profileIds: string[] = [];
    const ruleIds: string[] = [];
    const policyKey = this.buildHostPolicyKey(groups);
    if (policyKey === this.lastAppliedHostPolicyKey) {
      groups.forEach((group: BrowserUserAgentHostPolicyGroup) => {
        profileIds.push(group.profileId);
        group.hosts.forEach((host: string) => hosts.push(host));
        group.ruleIds.forEach((ruleId: string) => {
          if (ruleIds.indexOf(ruleId) < 0) {
            ruleIds.push(ruleId);
          }
        });
      });
      return {
        applied: true,
        hosts: hosts,
        profileIds: profileIds,
        ruleIds: ruleIds,
        message: `Host User-Agent compatibility policy unchanged: family=${this.applicationFamily} ` +
          `profiles=${profileIds.length} hosts=${hosts.length} rules=${ruleIds.length}`
      };
    }
    for (let index = 0; index < groups.length; index += 1) {
      const group = groups[index];
      try {
        webview.WebviewController.setUserAgentForHosts(group.userAgent, group.hosts);
      } catch (error) {
        return {
          applied: false,
          hosts: hosts,
          profileIds: profileIds,
          ruleIds: ruleIds,
          message: `Host User-Agent compatibility profile ${group.profileId} failed: ${JSON.stringify(error)}`
        };
      }
      profileIds.push(group.profileId);
      group.hosts.forEach((host: string) => hosts.push(host));
      group.ruleIds.forEach((ruleId: string) => {
        if (ruleIds.indexOf(ruleId) < 0) {
          ruleIds.push(ruleId);
        }
      });
    }
    this.lastAppliedHostPolicyKey = policyKey;
    return {
      applied: true,
      hosts: hosts,
      profileIds: profileIds,
      ruleIds: ruleIds,
      message: `Host User-Agent compatibility policy applied: family=${this.applicationFamily} ` +
        `profiles=${profileIds.length} hosts=${hosts.length} rules=${ruleIds.length}`
    };
  }

  private buildHostPolicyKey(groups: BrowserUserAgentHostPolicyGroup[]): string {
    return groups.map((group: BrowserUserAgentHostPolicyGroup) => {
      return `${group.profileId}|${group.userAgent}|${group.hosts.join(',')}|${group.ruleIds.join(',')}`;
    }).join('\n');
  }
}
