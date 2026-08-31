import { common } from '@kit.AbilityKit';
import { ReleaseNoticeRepository } from '../../data/update/ReleaseNoticeRepository';
import {
  AppVersionIdentity,
  ChangelogContentService
} from '../../services/settings/ChangelogContentService';
import {
  ReleaseNoticeContentService
} from '../../services/update/ReleaseNoticeContentService';

export interface ReleaseNoticeUiState {
  visible: boolean;
  noticeId: string;
  appName: string;
  versionName: string;
  versionCode: number;
  title: string;
  updatedAt: string;
  summary: string;
  items: string[];
  feedbackText: string;
  actionLabel: string;
}

export const HIDDEN_RELEASE_NOTICE_UI_STATE: ReleaseNoticeUiState = {
  visible: false,
  noticeId: '',
  appName: '',
  versionName: '',
  versionCode: 0,
  title: '',
  updatedAt: '',
  summary: '',
  items: [],
  feedbackText: '',
  actionLabel: ''
};

const RELEASE_NOTICE_MAX_ITEMS: number = 5;
const RELEASE_NOTICE_APP_NAME: string = 'Aira';

export class ReleaseNoticeCoordinator {
  private repository: ReleaseNoticeRepository;
  private changelogService: ChangelogContentService;
  private contentService: ReleaseNoticeContentService;

  constructor(
    repository: ReleaseNoticeRepository,
    changelogService: ChangelogContentService = new ChangelogContentService(),
    contentService?: ReleaseNoticeContentService
  ) {
    this.repository = repository;
    this.changelogService = changelogService;
    this.contentService = contentService ?? new ReleaseNoticeContentService(changelogService);
  }

  async initializeForCurrentVersion(): Promise<void> {
    const version = this.changelogService.resolveCurrentVersion();
    await this.repository.initialize(version.versionCode, version.versionName);
  }

  async buildNoticeState(context: common.Context): Promise<ReleaseNoticeUiState> {
    const version = this.changelogService.resolveCurrentVersion();
    await this.ensureInitialized(version);
    const state = this.repository.getState();
    if (version.versionCode <= state.lastAcknowledgedVersionCode) {
      return HIDDEN_RELEASE_NOTICE_UI_STATE;
    }
    const content = this.contentService.buildContent(context, version);
    if (content === undefined) {
      return HIDDEN_RELEASE_NOTICE_UI_STATE;
    }
    return {
      visible: true,
      noticeId: content.noticeId,
      appName: RELEASE_NOTICE_APP_NAME,
      versionName: version.versionName,
      versionCode: version.versionCode,
      title: content.title,
      updatedAt: content.updatedAt,
      summary: content.summary,
      items: content.items.slice(0, RELEASE_NOTICE_MAX_ITEMS),
      feedbackText: content.feedbackText,
      actionLabel: content.actionLabel
    };
  }

  async acknowledgeCurrentVersion(): Promise<void> {
    const version = this.changelogService.resolveCurrentVersion();
    await this.ensureInitialized(version);
    await this.repository.acknowledge(version.versionCode, version.versionName);
  }

  private async ensureInitialized(version: AppVersionIdentity): Promise<void> {
    if (this.repository.isInitialized()) {
      return;
    }
    await this.repository.initialize(version.versionCode, version.versionName);
  }
}
