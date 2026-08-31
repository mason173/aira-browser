import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { HistoryFeature } from '../../features/history/HistoryFeature';
import { ActivitySearchUrlService } from '../../services/activity/ActivitySearchUrlService';
import { ActivityTracker } from '../../services/activity/ActivityTracker';
import { DocumentViewerService } from '../../services/viewer/DocumentViewerService';
import { AppReviewPromptCoordinator } from '../review/AppReviewPromptCoordinator';
import { BrowserTabState } from '../tabs/TabManager';
import { SiteClearOnCloseCoordinator } from './SiteClearOnCloseCoordinator';
import {
  BrowserHistoryVisitSkipReason as BrowserWebHistoryVisitSkipReason,
  BrowserWebEventCommitCoordinator,
  BrowserWebHistoryVisitCommit
} from './BrowserWebEventCommitCoordinator';

export type BrowserHistoryVisitSkipReason =
  BrowserWebHistoryVisitSkipReason |
  'document_viewer' |
  'site_clear_on_close' |
  'history_disabled';

export interface BrowserHistoryVisitDocumentViewerState {
  chromePolicyActive: boolean;
  browserTab: boolean;
}

export interface BrowserHistoryVisitRecordingInput {
  tabId: string;
  url: string;
  title: string;
  now: number;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  documentViewerState: BrowserHistoryVisitDocumentViewerState;
  webEventCommitCoordinator: BrowserWebEventCommitCoordinator;
  historyFeature: HistoryFeature;
  appReviewPromptCoordinator: AppReviewPromptCoordinator;
  activityTracker: ActivityTracker;
  onHistoryChanged: () => void;
  shouldSkipForSiteClearOnClose?: () => boolean;
  onSkipped?: (reason: BrowserHistoryVisitSkipReason) => void;
}

export interface BrowserHistoryVisitPersistenceInput {
  commit: BrowserWebHistoryVisitCommit;
  url: string;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  historyFeature: HistoryFeature;
  appReviewPromptCoordinator: AppReviewPromptCoordinator;
  activityTracker: ActivityTracker;
  onHistoryChanged: () => void;
  documentViewerState?: BrowserHistoryVisitDocumentViewerState;
  shouldSkipForSiteClearOnClose?: () => boolean;
  onSkipped?: (reason: BrowserHistoryVisitSkipReason) => void;
}

export interface BrowserHistoryVisitRecordingHost {
  resolveTab: (tabId: string) => BrowserTabState | undefined;
  resolveProfileId: (tabId: string) => BrowserProfileId;
  resolvePrivacyMode: (tabId: string) => BrowserSessionPrivacyMode;
  resolveDataScope: (tabId: string) => BrowserDataScope;
  invalidateSearchSuggestionCache: () => void;
}

export class BrowserHistoryVisitPersistenceCoordinator {
  private readonly webEventCommitCoordinator: BrowserWebEventCommitCoordinator;
  private readonly historyFeature: HistoryFeature;
  private readonly appReviewPromptCoordinator: AppReviewPromptCoordinator;
  private readonly activityTracker: ActivityTracker;
  private readonly documentViewerService: DocumentViewerService;
  private readonly siteClearOnCloseCoordinator: SiteClearOnCloseCoordinator;
  private readonly host: BrowserHistoryVisitRecordingHost;
  private readonly searchUrlService: ActivitySearchUrlService = new ActivitySearchUrlService();

  constructor(
    webEventCommitCoordinator: BrowserWebEventCommitCoordinator,
    historyFeature: HistoryFeature,
    appReviewPromptCoordinator: AppReviewPromptCoordinator,
    activityTracker: ActivityTracker,
    documentViewerService: DocumentViewerService,
    siteClearOnCloseCoordinator: SiteClearOnCloseCoordinator,
    host: BrowserHistoryVisitRecordingHost
  ) {
    this.webEventCommitCoordinator = webEventCommitCoordinator;
    this.historyFeature = historyFeature;
    this.appReviewPromptCoordinator = appReviewPromptCoordinator;
    this.activityTracker = activityTracker;
    this.documentViewerService = documentViewerService;
    this.siteClearOnCloseCoordinator = siteClearOnCloseCoordinator;
    this.host = host;
  }

  record(tabId: string, url: string, title: string): void {
    const tab = this.host.resolveTab(tabId);
    this.recordFromInput({
      tabId: tabId,
      url: url,
      title: title,
      now: Date.now(),
      privacyMode: tab?.privacyMode ?? 'regular',
      dataScope: tab?.dataScope ?? 'profile_persistent',
      documentViewerState: {
        chromePolicyActive: this.documentViewerService.resolveChromePolicy(url).active,
        browserTab: this.isDocumentViewerBrowserTab(tab)
      },
      webEventCommitCoordinator: this.webEventCommitCoordinator,
      historyFeature: this.historyFeature,
      appReviewPromptCoordinator: this.appReviewPromptCoordinator,
      activityTracker: this.activityTracker,
      onHistoryChanged: () => {
        this.host.invalidateSearchSuggestionCache();
      },
      shouldSkipForSiteClearOnClose: () => this.siteClearOnCloseCoordinator.shouldSkipHistoryVisit(
        url,
        this.host.resolveProfileId(tabId),
        this.host.resolvePrivacyMode(tabId),
        this.host.resolveDataScope(tabId)
      ),
      onSkipped: (_reason: BrowserHistoryVisitSkipReason) => {}
    });
  }

  private recordFromInput(input: BrowserHistoryVisitRecordingInput): void {
    const commit = input.webEventCommitCoordinator.buildHistoryVisitCommit(
      input.tabId,
      input.url,
      input.title,
      input.now,
      input.dataScope,
      input.privacyMode
    );
    this.persist({
      commit: commit,
      url: input.url,
      privacyMode: input.privacyMode,
      dataScope: input.dataScope,
      historyFeature: input.historyFeature,
      appReviewPromptCoordinator: input.appReviewPromptCoordinator,
      activityTracker: input.activityTracker,
      onHistoryChanged: input.onHistoryChanged,
      documentViewerState: input.documentViewerState,
      shouldSkipForSiteClearOnClose: input.shouldSkipForSiteClearOnClose,
      onSkipped: input.onSkipped
    });
  }

  persist(input: BrowserHistoryVisitPersistenceInput): void {
    const command = input.commit.command;
    if (!input.commit.shouldRecord || command === undefined) {
      this.notifySkipped(input, input.commit.skipReason);
      return;
    }
    if (this.shouldSkipDocumentViewerHistoryVisit(input.documentViewerState)) {
      this.notifySkipped(input, 'document_viewer');
      return;
    }
    if (input.shouldSkipForSiteClearOnClose !== undefined && input.shouldSkipForSiteClearOnClose()) {
      this.notifySkipped(input, 'site_clear_on_close');
      return;
    }
    input.appReviewPromptCoordinator.recordRegularPageVisit({
      url: input.url,
      privacyMode: input.privacyMode,
      dataScope: input.dataScope
    });
    input.historyFeature.addVisitIfAllowed(command)
      .then((visit) => {
        if (visit !== undefined) {
          input.activityTracker.recordPageVisit(command.visitedAt ?? Date.now());
          if (this.searchUrlService.isSearchResultUrl(command.url)) {
            input.activityTracker.recordSearch(command.visitedAt ?? Date.now());
          }
        } else {
          this.notifySkipped(input, 'history_disabled');
        }
        input.onHistoryChanged();
      })
      .catch((_error: Error) => {
      });
  }

  private shouldSkipDocumentViewerHistoryVisit(state?: BrowserHistoryVisitDocumentViewerState): boolean {
    if (state === undefined) {
      return false;
    }
    return state.chromePolicyActive || state.browserTab;
  }

  private isDocumentViewerBrowserTab(tab: BrowserTabState | undefined): boolean {
    if (tab === undefined) {
      return false;
    }
    const candidates: string[] = [
      tab.pendingUrl,
      tab.url,
      tab.lastGoodUrl,
      tab.lastRestorableUrl
    ];
    tab.navigationHistory.forEach((historyUrl: string) => {
      candidates.push(historyUrl);
    });
    for (let index = 0; index < candidates.length; index += 1) {
      const candidateUrl = candidates[index].trim();
      if (candidateUrl.length > 0 && this.documentViewerService.resolveChromePolicy(candidateUrl).active) {
        return true;
      }
    }
    return false;
  }

  private notifySkipped(
    input: BrowserHistoryVisitPersistenceInput,
    reason?: BrowserHistoryVisitSkipReason
  ): void {
    if (reason === undefined || input.onSkipped === undefined) {
      return;
    }
    input.onSkipped(reason);
  }
}
