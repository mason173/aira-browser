import {
  BrowserUserAgentClientHintsMetadata,
  BrowserUserAgentProfile,
  BrowserUserAgentResolution
} from './BrowserUserAgentService';

export type BrowserBrowsingIdentityPrecedenceSource =
  'mandatory_host' |
  'current_tab' |
  'exact_origin' |
  'global' |
  'aira_compatibility' |
  'applicable_default';

export type BrowserBrowsingIdentityEvidenceStatus =
  'selected' |
  'superseded' |
  'unavailable' |
  'not_configured';

export interface BrowserBrowsingIdentityCandidate {
  source: BrowserBrowsingIdentityPrecedenceSource;
  identityId: string;
  resolution?: BrowserUserAgentResolution;
  unavailableReason: string;
}

export interface BrowserBrowsingIdentityDecisionEvidence {
  source: BrowserBrowsingIdentityPrecedenceSource;
  identityId: string;
  status: BrowserBrowsingIdentityEvidenceStatus;
  reason: string;
}

export interface BrowserBrowsingIdentityPolicySnapshot {
  policySnapshotKey: string;
  mandatoryHost: BrowserBrowsingIdentityCandidate;
  currentTab: BrowserBrowsingIdentityCandidate;
  exactOrigin: BrowserBrowsingIdentityCandidate;
  global: BrowserBrowsingIdentityCandidate;
  airaCompatibility: BrowserBrowsingIdentityCandidate;
  applicableDefault: BrowserBrowsingIdentityCandidate;
}

export interface BrowserBrowsingIdentityDecision extends BrowserUserAgentResolution {
  winningSource: BrowserBrowsingIdentityPrecedenceSource;
  policySnapshotKey: string;
  explanation: BrowserBrowsingIdentityDecisionEvidence[];
  executionFingerprint: string;
}

export class BrowserBrowsingIdentityDecisionService {
  decide(snapshot: BrowserBrowsingIdentityPolicySnapshot): BrowserBrowsingIdentityDecision {
    const candidates = this.orderedCandidates(snapshot);
    let selected = snapshot.applicableDefault;
    for (let index = 0; index < candidates.length; index += 1) {
      if (candidates[index].resolution !== undefined) {
        selected = candidates[index];
        break;
      }
    }
    const resolution = selected.resolution ?? snapshot.applicableDefault.resolution;
    if (resolution === undefined) {
      throw new Error('Browsing Identity Policy Snapshot requires an applicable default identity.');
    }
    return {
      userAgent: resolution.userAgent,
      mode: resolution.mode,
      source: resolution.source,
      reason: resolution.reason,
      matchedHost: resolution.matchedHost,
      identityId: resolution.identityId,
      targetOrigin: resolution.targetOrigin,
      profile: this.cloneProfile(resolution.profile),
      winningSource: selected.source,
      policySnapshotKey: snapshot.policySnapshotKey,
      explanation: this.buildExplanation(candidates, selected.source),
      executionFingerprint: buildBrowserBrowsingIdentityExecutionFingerprint(resolution)
    };
  }

  private orderedCandidates(
    snapshot: BrowserBrowsingIdentityPolicySnapshot
  ): BrowserBrowsingIdentityCandidate[] {
    return [
      snapshot.mandatoryHost,
      snapshot.currentTab,
      snapshot.exactOrigin,
      snapshot.global,
      snapshot.airaCompatibility,
      snapshot.applicableDefault,
    ];
  }

  private buildExplanation(
    candidates: BrowserBrowsingIdentityCandidate[],
    selectedSource: BrowserBrowsingIdentityPrecedenceSource
  ): BrowserBrowsingIdentityDecisionEvidence[] {
    return candidates.map((candidate: BrowserBrowsingIdentityCandidate): BrowserBrowsingIdentityDecisionEvidence => {
      if (candidate.source === selectedSource && candidate.resolution !== undefined) {
        return this.buildEvidence(candidate, 'selected', candidate.resolution.reason);
      }
      if (candidate.resolution !== undefined) {
        return this.buildEvidence(candidate, 'superseded', candidate.resolution.reason);
      }
      if (candidate.unavailableReason.length > 0) {
        return this.buildEvidence(candidate, 'unavailable', candidate.unavailableReason);
      }
      return this.buildEvidence(candidate, 'not_configured', 'No applicable identity was configured.');
    });
  }

  private buildEvidence(
    candidate: BrowserBrowsingIdentityCandidate,
    status: BrowserBrowsingIdentityEvidenceStatus,
    reason: string
  ): BrowserBrowsingIdentityDecisionEvidence {
    return {
      source: candidate.source,
      identityId: candidate.identityId,
      status: status,
      reason: reason
    };
  }

  private cloneProfile(profile: BrowserUserAgentProfile): BrowserUserAgentProfile {
    return {
      identityId: profile.identityId,
      uaStringMode: profile.uaStringMode,
      uaString: profile.uaString,
      clientHintsMode: profile.clientHintsMode,
      metadata: this.cloneMetadata(profile.metadata),
      presentationMode: profile.presentationMode,
      scopeCapability: profile.scopeCapability,
      compatibilityNotice: profile.compatibilityNotice
    };
  }

  private cloneMetadata(
    metadata: BrowserUserAgentClientHintsMetadata | undefined
  ): BrowserUserAgentClientHintsMetadata | undefined {
    if (metadata === undefined) {
      return undefined;
    }
    return {
      brand: metadata.brand,
      majorVersion: metadata.majorVersion,
      fullVersion: metadata.fullVersion,
      platform: metadata.platform,
      platformVersion: metadata.platformVersion,
      mobile: metadata.mobile,
      architecture: metadata.architecture,
      bitness: metadata.bitness,
      model: metadata.model,
      wow64: metadata.wow64
    };
  }
}

export function buildBrowserBrowsingIdentityExecutionFingerprint(
  resolution: BrowserUserAgentResolution
): string {
  const profile = resolution.profile;
  return [
    profile.uaStringMode,
    profile.uaString,
    profile.clientHintsMode,
    buildMetadataFingerprint(profile.metadata),
    profile.presentationMode
  ].join('|');
}

function buildMetadataFingerprint(metadata: BrowserUserAgentClientHintsMetadata | undefined): string {
  if (metadata === undefined) {
    return '';
  }
  return [
    metadata.brand,
    metadata.majorVersion,
    metadata.fullVersion,
    metadata.platform,
    metadata.platformVersion,
    metadata.mobile ? '1' : '0',
    metadata.architecture,
    metadata.bitness,
    metadata.model,
    metadata.wow64 ? '1' : '0'
  ].join(':');
}
