import { common } from '@kit.AbilityKit';
import { BrowserWebLoadDataPayload } from '../../core/browser/BrowserWebLoadCoordinator';
import {
  MarkdownDocumentTheme,
  MarkdownDocumentViewerService
} from '../markdown/MarkdownDocumentViewerService';
import { ChangelogContentService } from './ChangelogContentService';

const SETTINGS_CHANGELOG_TITLE: string = '更新日志';
const SETTINGS_CHANGELOG_SOURCE_URL: string = 'https://aira.local/settings/changelog.md';
const SETTINGS_CHANGELOG_BASE_URL: string = 'https://aira.local/settings/';

export class SettingsChangelogMarkdownService {
  private changelogContentService: ChangelogContentService = new ChangelogContentService();
  private markdownViewerService: MarkdownDocumentViewerService = new MarkdownDocumentViewerService();

  buildPayload(context: common.Context, theme?: MarkdownDocumentTheme): BrowserWebLoadDataPayload {
    return this.markdownViewerService.buildPayloadFromMarkdown({
      title: SETTINGS_CHANGELOG_TITLE,
      sourceUri: SETTINGS_CHANGELOG_SOURCE_URL,
      markdown: this.changelogContentService.buildFullMarkdown(context),
      baseUrl: SETTINGS_CHANGELOG_BASE_URL,
      historyUrl: SETTINGS_CHANGELOG_SOURCE_URL,
      theme: theme
    });
  }
}
