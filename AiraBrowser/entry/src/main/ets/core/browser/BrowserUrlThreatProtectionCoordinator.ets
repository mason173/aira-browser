import {
  BrowserWebSecuritySettingsRepository,
  sharedBrowserWebSecuritySettingsRepository
} from '../../data/preferences/BrowserWebSecuritySettingsRepository';
import {
  BrowserUrlThreatAssessment,
  BrowserUrlThreatVerdict,
  HuaweiUrlThreatDetectionService,
  sharedHuaweiUrlThreatDetectionService
} from '../../services/web/HuaweiUrlThreatDetectionService';

export interface BrowserUrlThreatNoticeState {
  visible: boolean;
  key: string;
  tabId: string;
  generation: number;
  title: string;
  subtitle: string;
}

export const HIDDEN_BROWSER_URL_THREAT_NOTICE_STATE: BrowserUrlThreatNoticeState = {
  visible: false,
  key: '',
  tabId: '',
  generation: 0,
  title: '',
  subtitle: ''
};

export interface BrowserUrlThreatProtectionHost {
  isActiveTab: (tabId: string) => boolean;
  publishNoticeState: (state: BrowserUrlThreatNoticeState) => void;
}

interface BrowserUrlThreatPendingAssessment {
  generation: number;
  assessment: BrowserUrlThreatAssessment;
}

const URL_THREAT_NOTICE_DURATION_MS: number = 5 * 1000;

export class BrowserUrlThreatProtectionCoordinator {
  private readonly host: BrowserUrlThreatProtectionHost;
  private readonly detectionService: HuaweiUrlThreatDetectionService;
  private readonly settingsRepository: BrowserWebSecuritySettingsRepository;
  private readonly navigationGenerationByTabId: Map<string, number> = new Map<string, number>();
  private readonly pendingThreatByTabId: Map<string, BrowserUrlThreatPendingAssessment> =
    new Map<string, BrowserUrlThreatPendingAssessment>();
  private readonly notifiedThreatKeyByTabId: Map<string, string> = new Map<string, string>();
  private visibleNoticeState: BrowserUrlThreatNoticeState = HIDDEN_BROWSER_URL_THREAT_NOTICE_STATE;
  private autoDismissTimer: number = 0;

  constructor(
    host: BrowserUrlThreatProtectionHost,
    detectionService: HuaweiUrlThreatDetectionService = sharedHuaweiUrlThreatDetectionService,
    settingsRepository: BrowserWebSecuritySettingsRepository = sharedBrowserWebSecuritySettingsRepository
  ) {
    this.host = host;
    this.detectionService = detectionService;
    this.settingsRepository = settingsRepository;
  }

  observePageBegin(tabId: string, url: string): void {
    const generation = this.nextTabGeneration(tabId);
    this.pendingThreatByTabId.delete(tabId);
    this.notifiedThreatKeyByTabId.delete(tabId);
    this.clearPublishedNoticeForTab(tabId);
    if (!this.isProtectionEnabled()) {
      return;
    }
    const checkedUrl = this.detectionService.resolveCheckUrl(url);
    if (checkedUrl.length <= 0) {
      return;
    }
    void this.detectionService.checkUrl(checkedUrl)
      .then((assessment: BrowserUrlThreatAssessment): void => {
        this.applyPageAssessment(tabId, generation, assessment);
      })
      .catch((_error: Error): void => {
      });
  }

  handleActiveTabChanged(tabId: string): void {
    if (this.visibleNoticeState.visible && this.visibleNoticeState.tabId !== tabId) {
      this.clearPublishedNotice();
    }
    const pending = this.pendingThreatByTabId.get(tabId);
    if (pending === undefined) {
      return;
    }
    if (!this.isProtectionEnabled()) {
      this.pendingThreatByTabId.delete(tabId);
      return;
    }
    if (!this.host.isActiveTab(tabId) || this.navigationGenerationByTabId.get(tabId) !== pending.generation) {
      return;
    }
    this.pendingThreatByTabId.delete(tabId);
    this.publishThreatNotice(tabId, pending.generation, pending.assessment);
  }

  dismissNotice(): void {
    this.clearPublishedNotice();
  }

  clearTab(tabId: string): void {
    this.navigationGenerationByTabId.delete(tabId);
    this.pendingThreatByTabId.delete(tabId);
    this.notifiedThreatKeyByTabId.delete(tabId);
    this.clearPublishedNoticeForTab(tabId);
  }

  private applyPageAssessment(
    tabId: string,
    generation: number,
    assessment: BrowserUrlThreatAssessment
  ): void {
    if (this.navigationGenerationByTabId.get(tabId) !== generation ||
      !this.isProtectionEnabled() || !this.isThreat(assessment)) {
      return;
    }
    if (!this.host.isActiveTab(tabId)) {
      this.pendingThreatByTabId.set(tabId, {
        generation: generation,
        assessment: assessment
      });
      return;
    }
    this.publishThreatNotice(tabId, generation, assessment);
  }

  private publishThreatNotice(
    tabId: string,
    generation: number,
    assessment: BrowserUrlThreatAssessment
  ): void {
    if (!this.host.isActiveTab(tabId) || this.navigationGenerationByTabId.get(tabId) !== generation) {
      return;
    }
    const noticeKey = `${tabId}:${generation}:${assessment.verdict}:${assessment.checkedUrl}`;
    if (this.notifiedThreatKeyByTabId.get(tabId) === noticeKey) {
      return;
    }
    this.notifiedThreatKeyByTabId.set(tabId, noticeKey);
    this.visibleNoticeState = this.buildNoticeState(tabId, generation, noticeKey, assessment.verdict);
    this.host.publishNoticeState(this.visibleNoticeState);
    this.scheduleAutoDismiss(noticeKey);
  }

  private buildNoticeState(
    tabId: string,
    generation: number,
    key: string,
    verdict: BrowserUrlThreatVerdict
  ): BrowserUrlThreatNoticeState {
    if (verdict === 'malware') {
      return {
        visible: true,
        key: key,
        tabId: tabId,
        generation: generation,
        title: '检测到网站安全风险',
        subtitle: '请谨慎下载或安装内容'
      };
    }
    if (verdict === 'phishing') {
      return {
        visible: true,
        key: key,
        tabId: tabId,
        generation: generation,
        title: '检测到网站安全风险',
        subtitle: '请谨慎输入账号或付款信息'
      };
    }
    return {
      visible: true,
      key: key,
      tabId: tabId,
      generation: generation,
      title: '检测到网站安全风险',
      subtitle: '请留意页面内容和信息输入'
    };
  }

  private scheduleAutoDismiss(noticeKey: string): void {
    this.cancelAutoDismiss();
    this.autoDismissTimer = setTimeout((): void => {
      if (this.visibleNoticeState.key !== noticeKey) {
        return;
      }
      this.autoDismissTimer = 0;
      this.visibleNoticeState = HIDDEN_BROWSER_URL_THREAT_NOTICE_STATE;
      this.host.publishNoticeState(HIDDEN_BROWSER_URL_THREAT_NOTICE_STATE);
    }, URL_THREAT_NOTICE_DURATION_MS);
  }

  private clearPublishedNoticeForTab(tabId: string): void {
    if (this.visibleNoticeState.visible && this.visibleNoticeState.tabId === tabId) {
      this.clearPublishedNotice();
    }
  }

  private clearPublishedNotice(): void {
    this.cancelAutoDismiss();
    if (!this.visibleNoticeState.visible) {
      return;
    }
    this.visibleNoticeState = HIDDEN_BROWSER_URL_THREAT_NOTICE_STATE;
    this.host.publishNoticeState(HIDDEN_BROWSER_URL_THREAT_NOTICE_STATE);
  }

  private cancelAutoDismiss(): void {
    if (this.autoDismissTimer !== 0) {
      clearTimeout(this.autoDismissTimer);
      this.autoDismissTimer = 0;
    }
  }

  private isThreat(assessment: BrowserUrlThreatAssessment): boolean {
    return assessment.status === 'checked' &&
      (assessment.verdict === 'malware' || assessment.verdict === 'phishing' || assessment.verdict === 'other');
  }

  private nextTabGeneration(tabId: string): number {
    const generation = (this.navigationGenerationByTabId.get(tabId) ?? 0) + 1;
    this.navigationGenerationByTabId.set(tabId, generation);
    return generation;
  }

  private isProtectionEnabled(): boolean {
    return this.settingsRepository.getSettings().safeBrowsingEnabled;
  }
}
