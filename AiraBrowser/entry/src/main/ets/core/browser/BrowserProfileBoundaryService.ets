import {
  BookmarkStorageScope,
  BrowserDataBoundary,
  BrowserDataBoundaryInput,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  buildBrowserDataBoundary
} from '../../common/models/BrowserModels';

export type BrowserDownloadMode = 'normal' | 'incognito';
export type BrowserSitePermissionScope = 'profile_persistent' | 'incognito_session_only';
export type BrowserProfileBoundaryLike = BrowserDataBoundary | BrowserDataBoundaryInput | undefined;

export interface BrowserProfileBoundarySameProfileResult {
  action: string;
  allowed: boolean;
  reason: string;
  source: BrowserDataBoundary;
  target: BrowserDataBoundary;
  summaryLine: string;
}

export class BrowserProfileBoundaryService {
  buildBoundary(input: BrowserProfileBoundaryLike = undefined): BrowserDataBoundary {
    return buildBrowserDataBoundary(this.toBoundaryInput(input));
  }

  buildBoundaryFromInput(input: BrowserDataBoundaryInput = {}): BrowserDataBoundary {
    return buildBrowserDataBoundary(input);
  }

  isPrivate(input: BrowserProfileBoundaryLike): boolean {
    const boundary = this.buildBoundary(input);
    return boundary.privacyMode === 'private';
  }

  isSessionEphemeral(input: BrowserProfileBoundaryLike): boolean {
    const boundary = this.buildBoundary(input);
    return boundary.privacyMode === 'private' || boundary.dataScope === 'session_ephemeral';
  }

  inheritFromOpener(
    openerBoundary: BrowserProfileBoundaryLike,
    explicitTarget: BrowserDataBoundaryInput = {}
  ): BrowserDataBoundary {
    const opener = this.buildBoundary(openerBoundary);
    return this.buildBoundary({
      profileId: explicitTarget.profileId ?? opener.profileId,
      privacyMode: explicitTarget.privacyMode ?? opener.privacyMode,
      dataScope: explicitTarget.dataScope ?? opener.dataScope,
      sessionId: explicitTarget.sessionId,
      storagePartitionId: explicitTarget.storagePartitionId
    });
  }

  inheritFromBoundaryInputs(
    openerBoundary: BrowserDataBoundaryInput | undefined,
    explicitTarget: BrowserDataBoundaryInput = {}
  ): BrowserDataBoundary {
    const opener = this.buildBoundary(openerBoundary ?? {});
    return this.buildBoundary({
      profileId: explicitTarget.profileId ?? opener.profileId,
      privacyMode: explicitTarget.privacyMode ?? opener.privacyMode,
      dataScope: explicitTarget.dataScope ?? opener.dataScope,
      sessionId: explicitTarget.sessionId,
      storagePartitionId: explicitTarget.storagePartitionId
    });
  }

  requireSameProfile(
    sourceBoundary: BrowserProfileBoundaryLike,
    targetBoundary: BrowserProfileBoundaryLike,
    action: string
  ): BrowserProfileBoundarySameProfileResult {
    const source = this.buildBoundary(sourceBoundary);
    const target = this.buildBoundary(targetBoundary);
    const sameProfile = source.profileId === target.profileId &&
      source.privacyMode === target.privacyMode &&
      source.dataScope === target.dataScope;
    const reason = sameProfile ? 'same_profile' : 'profile_boundary_mismatch';
    return {
      action: action,
      allowed: sameProfile,
      reason: reason,
      source: source,
      target: target,
      summaryLine: `profileBoundary action=${action} allowed=${sameProfile ? 1 : 0} reason=${reason} ` +
        `sourceProfile=${source.profileId} sourcePrivacy=${source.privacyMode} sourceScope=${source.dataScope} ` +
        `targetProfile=${target.profileId} targetPrivacy=${target.privacyMode} targetScope=${target.dataScope}`
    };
  }

  resolveWebIncognitoMode(input: BrowserProfileBoundaryLike): boolean {
    return this.isSessionEphemeral(input);
  }

  resolveBookmarkScope(input: BrowserProfileBoundaryLike): BookmarkStorageScope {
    return this.isSessionEphemeral(input) ? 'private' : 'regular';
  }

  resolveDownloadMode(input: BrowserProfileBoundaryLike): BrowserDownloadMode {
    return this.isSessionEphemeral(input) ? 'incognito' : 'normal';
  }

  resolveSitePermissionScope(
    input: BrowserProfileBoundaryLike
  ): BrowserSitePermissionScope {
    return this.isSessionEphemeral(input) ? 'incognito_session_only' : 'profile_persistent';
  }

  buildBoundaryInput(
    profileId: BrowserProfileId,
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): BrowserDataBoundaryInput {
    return {
      profileId: profileId,
      privacyMode: privacyMode,
      dataScope: dataScope
    };
  }

  private toBoundaryInput(input: BrowserProfileBoundaryLike): BrowserDataBoundaryInput {
    if (input === undefined) {
      return {};
    }
    return {
      profileId: input.profileId,
      privacyMode: input.privacyMode,
      dataScope: input.dataScope,
      sessionId: input.sessionId,
      storagePartitionId: input.storagePartitionId
    };
  }
}
