import {
  SiteIconCachedFile,
  SiteIconCandidate,
  SiteIconCandidateSource,
  SiteIconResult
} from '../../common/models/SiteIconModels';

const MIN_VALID_ICON_EDGE: number = 32;
const MAX_VALID_ICON_EDGE: number = 1024;
const MAX_CANDIDATE_SCORE_EDGE: number = 1024;

export class SiteIconResolutionPolicyService {
  rankCandidates(candidates: SiteIconCandidate[]): SiteIconCandidate[] {
    const deduped: SiteIconCandidate[] = [];
    candidates.forEach((candidate: SiteIconCandidate) => {
      if (candidate.url.length === 0) {
        return;
      }
      const existingIndex = deduped.findIndex((existing: SiteIconCandidate) => existing.url === candidate.url);
      if (existingIndex < 0) {
        deduped.push(candidate);
        return;
      }
      if (this.scoreCandidate(candidate) > this.scoreCandidate(deduped[existingIndex])) {
        deduped[existingIndex] = candidate;
      }
    });
    return deduped.sort((left: SiteIconCandidate, right: SiteIconCandidate) => (
      this.scoreCandidate(right) - this.scoreCandidate(left)
    ));
  }

  scoreCandidate(candidate: SiteIconCandidate): number {
    return this.resolveSourceWeight(candidate.source) +
      Math.min(candidate.size, MAX_CANDIDATE_SCORE_EDGE) * 1000 +
      (candidate.scalable ? 4000 : 0) +
      (candidate.purpose.indexOf('maskable') >= 0 ? 1200 : 0);
  }

  shouldReplaceCachedIconWithCandidate(
    cached: SiteIconCachedFile | SiteIconResult | undefined,
    candidate: SiteIconCandidate
  ): boolean {
    if (cached === undefined) {
      return this.isValidActualCandidate(candidate);
    }
    if (!this.isValidActualCandidate(candidate)) {
      return false;
    }
    const currentPriority = this.resolveSourcePriority(cached.source ?? 'rootIcon');
    const incomingPriority = this.resolveSourcePriority(candidate.source);
    if (incomingPriority !== currentPriority) {
      return incomingPriority > currentPriority;
    }
    return candidate.size > this.resolveCachedEdge(cached);
  }

  shouldInspectCandidate(
    cached: SiteIconCachedFile | SiteIconResult | undefined,
    candidate: SiteIconCandidate
  ): boolean {
    if (cached === undefined) {
      return true;
    }
    const normalizedUrl = candidate.url.trim();
    const cachedIconUrl = cached.iconUrl?.trim() ?? '';
    if (normalizedUrl.length > 0 && cachedIconUrl.length > 0 && normalizedUrl === cachedIconUrl) {
      return false;
    }
    const currentPriority = this.resolveSourcePriority(cached.source ?? 'rootIcon');
    const incomingPriority = this.resolveSourcePriority(candidate.source);
    if (incomingPriority !== currentPriority) {
      return incomingPriority > currentPriority;
    }
    const declaredEdge = Math.max(0, Math.floor(candidate.size));
    return declaredEdge <= 0 || declaredEdge > this.resolveCachedEdge(cached);
  }

  private isValidActualCandidate(candidate: SiteIconCandidate): boolean {
    if (candidate.scalable) {
      return true;
    }
    const edge = Math.max(0, Math.floor(candidate.size));
    return edge >= MIN_VALID_ICON_EDGE && edge <= MAX_VALID_ICON_EDGE;
  }

  private resolveCachedEdge(cached: SiteIconCachedFile | SiteIconResult): number {
    const width = Math.max(0, Math.floor(cached.width ?? 0));
    const height = Math.max(0, Math.floor(cached.height ?? 0));
    return Math.min(width, height);
  }

  private resolveSourcePriority(source: SiteIconCandidateSource): number {
    switch (source) {
      case 'appleTouch':
      case 'rootAppleTouch':
        return 4;
      case 'manifest':
        return 3;
      case 'documentIcon':
      case 'arkweb':
      case 'override':
      case 'rootIcon':
        return 2;
      case 'remoteFallback':
        return 1;
      default:
        return 0;
    }
  }

  private resolveSourceWeight(source: SiteIconCandidateSource): number {
    switch (source) {
      case 'appleTouch':
      case 'rootAppleTouch':
        return 8000000;
      case 'manifest':
        return 6000000;
      case 'documentIcon':
      case 'arkweb':
      case 'override':
      case 'rootIcon':
        return 4000000;
      case 'remoteFallback':
        return -500000;
      default:
        return 0;
    }
  }
}
