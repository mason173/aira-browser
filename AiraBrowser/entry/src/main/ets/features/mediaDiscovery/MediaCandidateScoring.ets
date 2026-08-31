import {
  MediaActionHint,
  MediaCandidate,
  MediaDetectionState,
  MediaDownloadabilityState,
  MediaPlayabilityState
} from './MediaCandidateModels';

export class MediaCandidateScoring {
  normalizeConfidence(score: number): number {
    if (score <= 0) {
      return 0;
    }
    return Math.floor(score);
  }

  mergeConfidence(current: number, next: number): number {
    return Math.max(this.normalizeConfidence(current), this.normalizeConfidence(next));
  }

  mergeDetectionState(current: MediaDetectionState, next: MediaDetectionState): MediaDetectionState {
    if (current === 'stale') {
      return next;
    }
    if (next === 'stale') {
      return current;
    }
    if (current === 'needs_processing' || next === 'needs_processing') {
      return 'needs_processing';
    }
    return 'detected';
  }

  mergePlayabilityState(current: MediaPlayabilityState, next: MediaPlayabilityState): MediaPlayabilityState {
    const currentRank = this.playabilityRank(current);
    const nextRank = this.playabilityRank(next);
    return nextRank > currentRank ? next : current;
  }

  mergeDownloadabilityState(
    current: MediaDownloadabilityState,
    next: MediaDownloadabilityState
  ): MediaDownloadabilityState {
    const currentRank = this.downloadabilityRank(current);
    const nextRank = this.downloadabilityRank(next);
    return nextRank > currentRank ? next : current;
  }

  mergeActionHints(target: MediaActionHint[], source: MediaActionHint[]): void {
    for (let i = 0; i < source.length; i++) {
      if (target.indexOf(source[i]) < 0) {
        target.push(source[i]);
      }
    }
  }

  private playabilityRank(state: MediaPlayabilityState): number {
    switch (state) {
      case 'playing_native': return 90;
      case 'playable': return 80;
      case 'candidate': return 70;
      case 'needs_processing': return 60;
      case 'requires_po_token':
      case 'signature_failed':
      case 'format_unavailable':
      case 'expired':
      case 'protected':
      case 'failed':
      case 'unsupported': return 20;
      default: return 0;
    }
  }

  private downloadabilityRank(state: MediaDownloadabilityState): number {
    switch (state) {
      case 'downloadable': return 80;
      case 'manifest': return 70;
      case 'needs_headers': return 60;
      case 'copy_only': return 50;
      case 'expired':
      case 'unsupported': return 10;
      default: return 0;
    }
  }
}
