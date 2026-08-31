import { MediaCandidateFamily } from './MediaCandidateModels';
import {
  MediaResourceDomSignal,
  MediaResourceEvidence
} from './MediaResourceClassificationModels';

export interface MediaResourceScoringInput {
  family: MediaCandidateFamily;
  source: 'network' | 'dom';
  evidence: MediaResourceEvidence;
  domSignal?: MediaResourceDomSignal;
  isNoiseUrl: boolean;
  fromBlob: boolean;
}

const VISIBLE_THRESHOLD: number = 30;

export class MediaResourceScoring {
  computeScore(input: MediaResourceScoringInput): number {
    let score = this.baseScoreForFamily(input.family);
    score += this.evidenceBonus(input.evidence);
    if (input.source === 'network') {
      score += 10;
    }
    if (input.source === 'dom') {
      score += this.domSignalBonus(input.domSignal);
    }
    if (input.evidence === 'generic_url_hint') {
      score = Math.min(score, 25);
    }
    if (input.evidence === 'weak_text_match') {
      score = Math.min(score, 18);
    }
    if (input.family === 'segment') {
      score = Math.min(score, 25);
    }
    if (input.fromBlob) {
      score = Math.min(score, 10);
    }
    if (input.isNoiseUrl) {
      score -= 50;
    }
    if (score < 0) {
      return 0;
    }
    return score;
  }

  isVisible(score: number): boolean {
    return score >= VISIBLE_THRESHOLD;
  }

  private baseScoreForFamily(family: MediaCandidateFamily): number {
    switch (family) {
      case 'manifest': return 100;
      case 'video': return 90;
      case 'audio': return 70;
      case 'image': return 45;
      case 'file': return 60;
      case 'segment': return 12;
      default: return 0;
    }
  }

  private evidenceBonus(evidence: MediaResourceEvidence): number {
    switch (evidence) {
      case 'mime': return 30;
      case 'media_element': return 25;
      case 'image_element': return 16;
      case 'explicit_extension': return 12;
      case 'streaming_url_hint': return 5;
      case 'generic_url_hint': return -35;
      case 'weak_text_match': return -45;
      default: return -100;
    }
  }

  private domSignalBonus(signal: MediaResourceDomSignal | undefined): number {
    switch (signal) {
      case 'video_element':
      case 'audio_element': return 20;
      case 'image_element':
      case 'css_background':
      case 'image_performance': return 12;
      case 'embedded_attribute':
      case 'anchor': return 2;
      case 'performance_entry': return 0;
      case 'script_text': return -15;
      case 'location':
      case 'text_match': return -20;
      default: return 0;
    }
  }
}
