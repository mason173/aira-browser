import { common } from '@kit.AbilityKit';
import buffer from '@ohos.buffer';
import {
  AppVersionIdentity,
  ChangelogContentService
} from '../settings/ChangelogContentService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

const RELEASE_NOTICE_RAW_FILE_NAME: string = 'release_notice.json';
const DEFAULT_RELEASE_NOTICE_ACTION_LABEL: string = '查看详细更新日志';
const RELEASE_NOTICE_FEEDBACK_TEXT: string = '问题反馈QQ群：1049806927';

interface ReleaseNoticeConfig {
  enabled?: boolean;
  noticeId?: string;
  title?: string;
  updatedAt?: string;
  summary?: string;
  items?: string[];
  actionLabel?: string;
}

export interface ReleaseNoticeContent {
  noticeId: string;
  title: string;
  updatedAt: string;
  summary: string;
  items: string[];
  feedbackText: string;
  actionLabel: string;
}

export class ReleaseNoticeContentService {
  private changelogService: ChangelogContentService;

  constructor(changelogService: ChangelogContentService = new ChangelogContentService()) {
    this.changelogService = changelogService;
  }

  buildContent(context: common.Context, version: AppVersionIdentity): ReleaseNoticeContent | undefined {
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()) {
      return undefined;
    }
    const config = this.readConfig(context);
    if (config === undefined || config.enabled !== true) {
      return undefined;
    }
    const changelogSection = this.changelogService.buildCurrentSection(context);
    const summary = this.normalizeText(config.summary, changelogSection.summary);
    const items = this.normalizeItems(config.items, changelogSection.items);
    return {
      noticeId: this.buildNoticeId(config.noticeId, version),
      title: this.normalizeText(config.title, `Aira 已更新到 ${version.versionName}`),
      updatedAt: this.normalizeText(config.updatedAt, changelogSection.updateDate),
      summary: summary.length > 0 ? summary : '这一版带来了一些体验优化和问题修复。',
      items: items,
      feedbackText: RELEASE_NOTICE_FEEDBACK_TEXT,
      actionLabel: this.normalizeText(config.actionLabel, DEFAULT_RELEASE_NOTICE_ACTION_LABEL)
    };
  }

  private readConfig(context: common.Context): ReleaseNoticeConfig | undefined {
    try {
      const rawFile = context.resourceManager.getRawFileContentSync(RELEASE_NOTICE_RAW_FILE_NAME);
      return JSON.parse(buffer.from(rawFile.buffer).toString('utf8')) as ReleaseNoticeConfig;
    } catch (_error) {
      return undefined;
    }
  }

  private buildNoticeId(noticeId: string | undefined, version: AppVersionIdentity): string {
    const normalizedNoticeId = this.normalizeText(noticeId, 'current-release');
    return `${normalizedNoticeId}-${version.versionCode}`;
  }

  private normalizeText(value: string | undefined, fallback: string): string {
    const normalizedValue = `${value ?? ''}`.trim();
    return normalizedValue.length > 0 ? normalizedValue : fallback;
  }

  private normalizeItems(value: string[] | undefined, fallback: string[]): string[] {
    const source = Array.isArray(value) && value.length > 0 ? value : fallback;
    const items: string[] = [];
    source.forEach((item: string) => {
      const normalizedItem = item.trim();
      if (normalizedItem.length > 0) {
        items.push(normalizedItem);
      }
    });
    return items;
  }
}
