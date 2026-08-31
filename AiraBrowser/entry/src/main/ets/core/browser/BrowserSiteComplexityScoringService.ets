import { BrowserTabState } from '../tabs/TabManager';

export type BrowserSiteComplexityLevel = 'none' | 'low' | 'medium' | 'high' | 'critical';
export type BrowserSiteComplexitySignalKind = 'media' | 'auth' | 'payment' | 'form';

export interface BrowserSiteComplexityScore {
  score: number;
  level: BrowserSiteComplexityLevel;
  signalKinds: BrowserSiteComplexitySignalKind[];
  heuristicKinds: BrowserSiteComplexitySignalKind[];
  historyDepth: number;
  reasonLine: string;
}

export class BrowserSiteComplexityScoringService {
  evaluateTab(tab: BrowserTabState): BrowserSiteComplexityScore {
    const signalKinds: BrowserSiteComplexitySignalKind[] = [];
    const heuristicKinds = this.resolveHeuristicKinds(tab, signalKinds);
    const historyDepth = tab.navigationHistory.length;
    let score = 0;

    signalKinds.forEach((kind: BrowserSiteComplexitySignalKind) => {
      score += this.resolveSignalScore(kind);
    });
    heuristicKinds.forEach((kind: BrowserSiteComplexitySignalKind) => {
      score += this.resolveHeuristicScore(kind);
    });
    if (historyDepth >= 6) {
      score += 12;
    } else if (historyDepth >= 3) {
      score += 6;
    }

    const normalizedScore = Math.max(0, Math.min(100, score));
    return {
      score: normalizedScore,
      level: this.resolveLevel(normalizedScore),
      signalKinds: signalKinds,
      heuristicKinds: heuristicKinds,
      historyDepth: historyDepth,
      reasonLine: this.buildReasonLine(
        normalizedScore,
        signalKinds,
        heuristicKinds,
        historyDepth
      )
    };
  }

  private resolveHeuristicKinds(
    tab: BrowserTabState,
    signalKinds: BrowserSiteComplexitySignalKind[]
  ): BrowserSiteComplexitySignalKind[] {
    const heuristics: BrowserSiteComplexitySignalKind[] = [];
    const signal = `${tab.url} ${tab.pendingUrl} ${tab.title}`.toLowerCase();
    this.pushHeuristicKind(heuristics, signalKinds, signal, 'payment', [
      'checkout',
      'billing',
      'payment',
      'order',
      'pay',
      'alipay',
      'wechatpay',
      '支付',
      '订单',
      '收银台'
    ]);
    this.pushHeuristicKind(heuristics, signalKinds, signal, 'auth', [
      'login',
      'signin',
      'sign-in',
      'account',
      'passport',
      'auth',
      'otp',
      'verify',
      '登录',
      '验证',
      '账户'
    ]);
    this.pushHeuristicKind(heuristics, signalKinds, signal, 'media', [
      'video',
      'music',
      'audio',
      'player',
      'podcast',
      'live',
      'media',
      '视频',
      '音乐',
      '播放',
      '直播'
    ]);
    this.pushHeuristicKind(heuristics, signalKinds, signal, 'form', [
      'editor',
      'compose',
      'draft',
      'submit',
      'apply',
      'form',
      '编辑',
      '草稿',
      '提交',
      '表单'
    ]);
    return heuristics;
  }

  private pushHeuristicKind(
    target: BrowserSiteComplexitySignalKind[],
    signalKinds: BrowserSiteComplexitySignalKind[],
    signal: string,
    kind: BrowserSiteComplexitySignalKind,
    keywords: string[]
  ): void {
    if (signalKinds.indexOf(kind) >= 0 || target.indexOf(kind) >= 0) {
      return;
    }
    if (keywords.some((keyword: string) => signal.indexOf(keyword) >= 0)) {
      target.push(kind);
    }
  }

  private resolveSignalScore(kind: BrowserSiteComplexitySignalKind): number {
    switch (kind) {
      case 'payment':
        return 46;
      case 'auth':
        return 34;
      case 'media':
        return 26;
      case 'form':
        return 18;
      default:
        return 0;
    }
  }

  private resolveHeuristicScore(kind: BrowserSiteComplexitySignalKind): number {
    switch (kind) {
      case 'payment':
        return 26;
      case 'auth':
        return 20;
      case 'media':
        return 14;
      case 'form':
        return 12;
      default:
        return 0;
    }
  }

  private resolveLevel(score: number): BrowserSiteComplexityLevel {
    if (score >= 80) {
      return 'critical';
    }
    if (score >= 55) {
      return 'high';
    }
    if (score >= 25) {
      return 'medium';
    }
    if (score > 0) {
      return 'low';
    }
    return 'none';
  }

  private buildReasonLine(
    score: number,
    signalKinds: BrowserSiteComplexitySignalKind[],
    heuristicKinds: BrowserSiteComplexitySignalKind[],
    historyDepth: number
  ): string {
    const details: string[] = [];
    if (signalKinds.length > 0) {
      details.push(`signals=${signalKinds.join('+')}`);
    }
    if (heuristicKinds.length > 0) {
      details.push(`heuristic=${heuristicKinds.join('+')}`);
    }
    if (historyDepth >= 3) {
      details.push(`history=${historyDepth}`);
    }
    if (details.length === 0) {
      return 'complexity=none score=0';
    }
    return `complexity=${this.resolveLevel(score)} score=${score} ${details.join(' ')}`;
  }
}
