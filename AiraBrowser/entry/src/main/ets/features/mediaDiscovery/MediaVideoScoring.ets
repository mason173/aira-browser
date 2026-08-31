import { MediaCandidateKind } from './MediaCandidateModels';

function baseScoreForKind(kind: MediaCandidateKind): number {
  switch (kind) {
    case 'hls': return 100;
    case 'dash': return 90;
    case 'mp4': return 80;
    case 'webm': return 80;
    case 'audio': return 50;
    case 'segment': return 20;
    default: return 10;
  }
}

export interface ScoringInput {
  kind: MediaCandidateKind;
  source: 'network' | 'dom';
  isNoiseUrl: boolean;
  fromBlob: boolean;
  inferredFromUrlHint?: boolean;
}

const VISIBLE_THRESHOLD: number = 70;

export class MediaVideoScoring {
  computeScore(input: ScoringInput): number {
    let score = baseScoreForKind(input.kind);
    if (input.fromBlob) {
      score = Math.min(score, 10);
    }
    if (input.isNoiseUrl) {
      score -= 60;
    }
    if (input.source === 'dom' && (input.kind === 'mp4' || input.kind === 'webm')) {
      score = Math.max(score - 10, 0);
    }
    if (input.source === 'network' && input.inferredFromUrlHint === true) {
      score = Math.min(score, 35);
    }
    if (score < 0) {
      score = 0;
    }
    return score;
  }

  visibleThreshold(): number {
    return VISIBLE_THRESHOLD;
  }

  isVisible(score: number): boolean {
    return score >= VISIBLE_THRESHOLD;
  }
}
