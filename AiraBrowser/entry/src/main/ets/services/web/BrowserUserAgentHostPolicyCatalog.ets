import {
  AIRA_COMPAT_MOBILE_USER_AGENT,
  AIRA_COMPAT_DESKTOP_USER_AGENT,
  BrowserUserAgentApplicationFamily
} from './BrowserUserAgentService';
import { GOOGLE_SEARCH_COMPATIBILITY_HOST_CHUNKS } from './GeneratedGoogleSearchCompatibilityHosts';

export type BrowserUserAgentHostProfileId = 'aira_android_compat' | 'aira_desktop_compat';

export interface BrowserUserAgentHostProfile {
  id: BrowserUserAgentHostProfileId;
  userAgent: string;
}

export interface BrowserUserAgentHostCompatibilityRule {
  id: string;
  profileId: BrowserUserAgentHostProfileId;
  mandatory: boolean;
  applicationFamilies: BrowserUserAgentApplicationFamily[];
  hosts: string[];
  reason: string;
  verificationUrl: string;
  addedAt: string;
  lastVerifiedAt: string;
}

export interface BrowserUserAgentHostPolicyMatch {
  host: string;
  profileId: BrowserUserAgentHostProfileId;
  ruleId: string;
  reason: string;
  userAgent: string;
}

export interface BrowserUserAgentHostPolicyGroup {
  profileId: BrowserUserAgentHostProfileId;
  userAgent: string;
  hosts: string[];
  ruleIds: string[];
}

interface BrowserUserAgentHostAssignment {
  host: string;
  profileId: BrowserUserAgentHostProfileId;
  ruleId: string;
}

interface BundledGoogleSearchCompatibilityProfile {
  idSegment: string;
  profileId: BrowserUserAgentHostProfileId;
  applicationFamilies: BrowserUserAgentApplicationFamily[];
  reason: string;
}

const HOST_PROFILES: BrowserUserAgentHostProfile[] = [
  {
    id: 'aira_android_compat',
    userAgent: AIRA_COMPAT_MOBILE_USER_AGENT
  },
  {
    id: 'aira_desktop_compat',
    userAgent: AIRA_COMPAT_DESKTOP_USER_AGENT
  }
];

const BUNDLED_GOOGLE_SEARCH_COMPATIBILITY_PROFILES: BundledGoogleSearchCompatibilityProfile[] = [
  {
    idSegment: 'mobile',
    profileId: 'aira_android_compat',
    applicationFamilies: ['mobile'],
    reason: 'Google Search pages require Aira\'s stable Android-shaped Chrome compatibility identity.'
  },
  {
    idSegment: 'desktop',
    profileId: 'aira_desktop_compat',
    applicationFamilies: ['tablet', 'desktop'],
    reason: 'Google Search large-screen pages require Aira\'s verified Windows Chrome compatibility identity.'
  }
];

function buildBundledGoogleSearchCompatibilityRules(): BrowserUserAgentHostCompatibilityRule[] {
  const rules: BrowserUserAgentHostCompatibilityRule[] = [];
  BUNDLED_GOOGLE_SEARCH_COMPATIBILITY_PROFILES.forEach(
    (profile: BundledGoogleSearchCompatibilityProfile): void => {
      GOOGLE_SEARCH_COMPATIBILITY_HOST_CHUNKS.forEach((hosts: string[], index: number): void => {
        const ordinal = index + 1 < 10 ? `0${index + 1}` : `${index + 1}`;
        rules.push({
          id: `google-search-${profile.idSegment}-compat-${ordinal}`,
          profileId: profile.profileId,
          mandatory: true,
          applicationFamilies: profile.applicationFamilies.slice(),
          hosts: hosts.slice(),
          reason: profile.reason,
          verificationUrl: 'https://www.google.com/supported_domains',
          addedAt: '2026-08-29',
          lastVerifiedAt: '2026-08-29'
        });
      });
    }
  );
  return rules;
}

const BUNDLED_HOST_COMPATIBILITY_RULES: BrowserUserAgentHostCompatibilityRule[] =
  buildBundledGoogleSearchCompatibilityRules().concat([
  {
    id: 'youtube-mobile-compat',
    profileId: 'aira_android_compat',
    mandatory: true,
    applicationFamilies: ['mobile'],
    hosts: ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be'],
    reason: 'YouTube pages require Aira\'s stable Android-shaped Chrome compatibility identity.',
    verificationUrl: 'https://www.youtube.com/',
    addedAt: '2026-08-17',
    lastVerifiedAt: '2026-08-17'
  },
  {
    id: 'youtube-desktop-compat',
    profileId: 'aira_desktop_compat',
    mandatory: true,
    applicationFamilies: ['tablet', 'desktop'],
    hosts: ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be'],
    reason: 'YouTube large-screen pages require Aira\'s verified Windows Chrome compatibility identity.',
    verificationUrl: 'https://www.youtube.com/',
    addedAt: '2026-08-17',
    lastVerifiedAt: '2026-08-17'
  }
]);

export class BrowserUserAgentHostPolicyCatalog {
  resolve(applicationFamily: BrowserUserAgentApplicationFamily): BrowserUserAgentHostPolicyGroup[] {
    const profiles = this.copyAndValidateProfiles();
    const groups: BrowserUserAgentHostPolicyGroup[] = profiles.map((profile: BrowserUserAgentHostProfile) => {
      const group: BrowserUserAgentHostPolicyGroup = {
        profileId: profile.id,
        userAgent: profile.userAgent,
        hosts: [],
        ruleIds: []
      };
      return group;
    });
    const assignments: BrowserUserAgentHostAssignment[] = [];
    const ruleIds: string[] = [];

    this.packagedRules().forEach((rule: BrowserUserAgentHostCompatibilityRule) => {
      const profile = this.resolveRuleProfile(rule, profiles);
      this.validateRule(rule);
      if (ruleIds.indexOf(rule.id) >= 0) {
        throw new Error(`Duplicate Host UA rule id: ${rule.id}`);
      }
      ruleIds.push(rule.id);
      if (rule.applicationFamilies.indexOf(applicationFamily) < 0) {
        return;
      }
      const group = groups.find((candidate: BrowserUserAgentHostPolicyGroup) => {
        return candidate.profileId === profile.id;
      });
      if (group === undefined) {
        throw new Error(`Host UA profile group is missing: ${profile.id}`);
      }
      rule.hosts.forEach((host: string) => {
        this.validateExplicitHost(host, rule.id);
        const existing = assignments.find((assignment: BrowserUserAgentHostAssignment) => {
          return assignment.host === host;
        });
        if (existing !== undefined) {
          throw new Error(
            `Host UA assignment conflict: ${host} is declared by ${existing.ruleId} (${existing.profileId}) and ` +
              `${rule.id} (${profile.id}).`
          );
        }
        assignments.push({
          host: host,
          profileId: profile.id,
          ruleId: rule.id
        });
        group.hosts.push(host);
        if (group.ruleIds.indexOf(rule.id) < 0) {
          group.ruleIds.push(rule.id);
        }
      });
    });

    groups.forEach((group: BrowserUserAgentHostPolicyGroup) => {
      group.hosts.sort();
      group.ruleIds.sort();
    });
    return groups;
  }

  resolveMandatoryCompatibility(
    applicationFamily: BrowserUserAgentApplicationFamily,
    host: string,
    requestedApplicationFamily: BrowserUserAgentApplicationFamily = applicationFamily
  ): BrowserUserAgentHostPolicyMatch | undefined {
    // The physical application family controls the ordinary Host replay
    // baseline, but a managed Host may be requested in the other cloud shape
    // by a tab/site/global identity. Validate and resolve against that
    // requested shape so the mandatory winner remains package-owned without
    // locking users to the device's initial family.
    this.resolve(requestedApplicationFamily);
    const normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.length <= 0) {
      return undefined;
    }
    const rule = this.packagedRules().find((candidate: BrowserUserAgentHostCompatibilityRule) => {
      return candidate.mandatory && candidate.applicationFamilies.indexOf(requestedApplicationFamily) >= 0 &&
        candidate.hosts.indexOf(normalizedHost) >= 0;
    });
    if (rule === undefined) {
      return undefined;
    }
    const profile = this.resolveRuleProfile(rule, this.copyAndValidateProfiles());
    return {
      host: normalizedHost,
      profileId: profile.id,
      ruleId: rule.id,
      reason: rule.reason,
      userAgent: profile.userAgent.trim()
    };
  }

  private copyAndValidateProfiles(): BrowserUserAgentHostProfile[] {
    const profiles: BrowserUserAgentHostProfile[] = [];
    HOST_PROFILES.forEach((profile: BrowserUserAgentHostProfile) => {
      if (profile.id.trim().length <= 0 || profile.userAgent.trim().length <= 0) {
        throw new Error('Host UA profiles require a non-empty id and User-Agent.');
      }
      if (profiles.some((candidate: BrowserUserAgentHostProfile) => candidate.id === profile.id)) {
        throw new Error(`Duplicate host UA profile id: ${profile.id}`);
      }
      if (profiles.some((candidate: BrowserUserAgentHostProfile) => {
        return candidate.userAgent === profile.userAgent.trim();
      })) {
        throw new Error(`Duplicate concrete User-Agent in host UA profile: ${profile.id}`);
      }
      profiles.push({
        id: profile.id,
        userAgent: profile.userAgent.trim()
      });
    });
    return profiles;
  }

  private packagedRules(): BrowserUserAgentHostCompatibilityRule[] {
    return this.copyRules(BUNDLED_HOST_COMPATIBILITY_RULES);
  }

  private copyRules(rules: BrowserUserAgentHostCompatibilityRule[]): BrowserUserAgentHostCompatibilityRule[] {
    return rules.map((rule: BrowserUserAgentHostCompatibilityRule): BrowserUserAgentHostCompatibilityRule => ({
      id: rule.id.trim(),
      profileId: rule.profileId,
      mandatory: rule.mandatory,
      applicationFamilies: rule.applicationFamilies.slice(),
      hosts: rule.hosts.slice(),
      reason: rule.reason.trim(),
      verificationUrl: rule.verificationUrl.trim(),
      addedAt: rule.addedAt.trim(),
      lastVerifiedAt: rule.lastVerifiedAt.trim()
    }));
  }

  private resolveRuleProfile(
    rule: BrowserUserAgentHostCompatibilityRule,
    profiles: BrowserUserAgentHostProfile[]
  ): BrowserUserAgentHostProfile {
    const profile = profiles.find((candidate: BrowserUserAgentHostProfile) => {
      return candidate.id === rule.profileId;
    });
    if (profile === undefined) {
      throw new Error(`Host UA rule ${rule.id} references unknown profile ${rule.profileId}.`);
    }
    return profile;
  }

  private validateRule(rule: BrowserUserAgentHostCompatibilityRule): void {
    if (rule.id.trim().length <= 0 || rule.reason.trim().length <= 0 ||
      rule.verificationUrl.trim().length <= 0 || rule.addedAt.trim().length <= 0 ||
      rule.lastVerifiedAt.trim().length <= 0) {
      throw new Error('Host UA rules require id, evidence metadata, and review dates.');
    }
    if (rule.applicationFamilies.length <= 0 || rule.hosts.length <= 0) {
      throw new Error(`Host UA rule ${rule.id} requires an application family and at least one host.`);
    }
  }

  private validateExplicitHost(host: string, ruleId: string): void {
    const invalid = host.length <= 0 || host !== host.trim() || host !== host.toLowerCase() ||
      host.indexOf('.') <= 0 || host.startsWith('.') || host.endsWith('.') || host.indexOf('..') >= 0 ||
      host.indexOf('://') >= 0 || host.indexOf('/') >= 0 || host.indexOf(':') >= 0 ||
      host.indexOf('*') >= 0 || host.indexOf('?') >= 0 || host.indexOf('#') >= 0 ||
      host.indexOf('@') >= 0 || host.indexOf(' ') >= 0 || host.indexOf('\t') >= 0 || host.indexOf('\n') >= 0;
    if (invalid) {
      throw new Error(`Host UA rule ${ruleId} contains an invalid explicit host: ${host}`);
    }
  }
}
